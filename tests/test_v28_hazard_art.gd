extends SceneTree
## The new materials must preserve every actual collision body and cached work.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _fixture(course: RushCourse, kind: String) -> Dictionary:
	var item := course._central_hazard(kind, 0)
	item["x"] = 540.0
	item["h"] = 2000.0
	for key: String in ["amplitude", "motion_x", "motion_y", "angle", "angle_sway", "spin", "phase"]:
		item[key] = 0.0
	course._cache_geometry(item)
	return item

func _body_parity(course: RushCourse, kind: String) -> void:
	var item := _fixture(course, kind)
	course.hazards = [item]
	var image: Image = course._art[kind].get_image()
	var capsule := String(item["shape"]) == "capsule"
	var extent := Vector2(float(item["r"]) + float(item["half_length"]), float(item["r"]))
	if capsule: extent.x = float(item["half_length"])
	var mismatches := 0
	var samples := 0
	var colors := {}
	var low := 1.0
	var high := 0.0
	for y in range(1, image.get_height() - 1, 3):
		for x in range(1, image.get_width() - 1, 3):
			var point := Vector2((float(x) / (image.get_width() - 1) * 2.0 - 1.0) * extent.x, (float(y) / (image.get_height() - 1) * 2.0 - 1.0) * extent.y)
			var body: bool
			var edge := INF
			if capsule:
				body = true # This is the filled rectangle between capsule end centres.
			elif String(item["shape"]) == "polygon":
				body = Geometry2D.is_point_in_polygon(point, item["_polygon"])
				for index in item["_polygon"].size():
					edge = minf(edge, Geometry2D.get_closest_point_to_segment(point, item["_polygon"][index], item["_polygon"][(index + 1) % item["_polygon"].size()]).distance_to(point))
			else:
				body = point.length() <= float(item["r"])
				edge = absf(point.length() - float(item["r"]))
			if edge < 0.25: continue
			var color := image.get_pixel(x, y)
			if (color.a > 0.5) != body: mismatches += 1
			if color.a > 0.5:
				colors[color.to_rgba32()] = true
				low = minf(low, color.get_luminance())
				high = maxf(high, color.get_luminance())
			samples += 1
	check(samples > 700 and mismatches == 0, kind + ": cached visible body agrees with lethal silhouette")
	check(colors.size() >= (5 if kind == "fire_jet" else 8) and high - low > 0.22, kind + ": readable outline, inset bevel and material shading")
	check(image.get_width() >= 128, kind + ": twice the previous source pixel density")

func _run() -> void:
	await process_frame
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	var course := RushCourse.new()
	root.add_child(course)
	var parity_count := 0
	for world: String in RushCourse.WORLD_TYPES:
		course.setup(41, world)
		for kind: String in RushCourse.WORLD_TYPES[world]:
			if kind == String(RushCourse.WORLD_WALL_KIND[world]):
				var image: Image = course._art["spikes"].get_image()
				check(image.get_size() == Vector2i(168, 64), world + ": teeth have double source resolution")
				var mismatches := 0
				for y in range(1, 63, 2):
					for x in range(1, 167, 2):
						var normalized := Vector2(float(x) / 167.0, float(y) / 63.0 * 2.0 - 1.0)
						if absf(normalized.x + absf(normalized.y) - 1.0) < 0.01: continue
						if (image.get_pixel(x, y).a > 0.5) != (normalized.x + absf(normalized.y) <= 1.0): mismatches += 1
				check(mismatches == 0, world + ": triangle material stays in the actual tooth")
			else:
				_body_parity(course, kind)
			parity_count += 1
		var art_id: int = course._art["spikes"].get_instance_id()
		course._ensure_art()
		check(art_id == course._art["spikes"].get_instance_id(), world + ": drawing reuses cached texture")
	course.setup(1, "ice")
	course.animation_time = 2.5
	course.render_time = 2.48
	var saved := course.snapshot()
	check(not saved.has("render_time") and is_equal_approx(float(saved["animation_time"]), 2.5), "render interpolation clock never changes or enters physics snapshots")
	course.restore(saved)
	check(course.render_time == -1.0 and is_equal_approx(course.animation_time, 2.5), "restore resets presentation clock, retaining physics time")
	course.render_time = 4.0
	course.setup(1, "jungle")
	check(course.render_time == -1.0 and course.animation_time == 0.0, "new run resets both animation clocks")
	check(parity_count == 24, "all 24 world hazards covered")
	course.queue_free()
	print("V28 hazard art: %d bodies, %d checks, %d failures" % [parity_count, checks, failures])
	quit(1 if failures else 0)
