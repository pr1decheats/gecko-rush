extends SceneTree
## Icicle size/readability contracts, exact drawn-body collision and legacy saves.
var checks := 0
var failures := 0
var course: RushCourse

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _body_size(item: Dictionary) -> Vector2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector2 in item["_polygon"]:
		var rotated := point.rotated(float(item["angle"]))
		low = low.min(rotated)
		high = high.max(rotated)
	return high - low

func _stationary_icicle(scale_value: float = 1.0, legacy: bool = false) -> Dictionary:
	var item := course._central_hazard("icicle", 0.0)
	if legacy:
		item["r"] = 14.0
		item["half_length"] = 33.0
	course._scale_hazard(item, scale_value)
	item["x"] = 540.0
	item["h"] = 2000.0
	item["amplitude"] = 0.0
	item["motion_x"] = 0.0
	item["motion_y"] = 0.0
	item["phase"] = 0.0
	course._cache_geometry(item)
	return item

func _check_texture_parity(item: Dictionary, context: String) -> void:
	var texture: Image = course._long_polygon_texture("icicle").get_image()
	var polygon: PackedVector2Array = item["_polygon"]
	var extent := Vector2(float(item["r"]) + float(item["half_length"]), float(item["r"]))
	var matched := true
	var samples := 0
	for y in range(1, texture.get_height() - 1, 2):
		for x in range(1, texture.get_width() - 1, 2):
			var local := Vector2((float(x) / (texture.get_width() - 1) * 2.0 - 1.0) * extent.x, (float(y) / (texture.get_height() - 1) * 2.0 - 1.0) * extent.y)
			var nearest_edge := INF
			for index in polygon.size():
				nearest_edge = minf(nearest_edge, Geometry2D.get_closest_point_to_segment(local, polygon[index], polygon[(index + 1) % polygon.size()]).distance_to(local))
			if nearest_edge < 0.3:
				continue
			var world := Vector2(540.0, -2000.0) + local.rotated(float(item["angle"]))
			var visible := texture.get_pixel(x, y).a > 0.5
			var lethal := course.collision_at(world, 0.0, 0.0)
			matched = matched and visible == lethal
			samples += 1
	check(samples > 500 and matched, "opaque texture and actual polygon contact agree: " + context)

func _run() -> void:
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	course = RushCourse.new()
	root.add_child(course)
	course.setup(41, "ice")
	for scale_value: float in [1.0, 0.76, 0.68]:
		var item := _stationary_icicle(scale_value)
		course.hazards = [item]
		var size := _body_size(item)
		check(is_equal_approx(size.x, 30.24 * scale_value), "icicle opaque/collision width is 50 percent larger at scale " + str(scale_value))
		check(is_equal_approx(size.y, 110.0 * scale_value), "icicle length grows only 17 percent at scale " + str(scale_value))
		check(size.x / (20.16 * scale_value) <= 1.6 and size.y / (94.0 * scale_value) < 1.25, "icicle remains a moderate increase at scale " + str(scale_value))
		check(str(item["shape"]) == "polygon" and is_equal_approx(float(item["angle"]), PI * 0.5), "falling/wall-attached icicle keeps its downward polygon silhouette")
		_check_texture_parity(item, "current scale " + str(scale_value))

	var enlarged := _stationary_icicle()
	course.hazards = [enlarged]
	# At this broad part of the tapered body, the old radius cannot reach x=13.
	var widened_band := Vector2(540.0 + 13.0, -2000.0 - 35.0)
	check(course.collision_kind_at(widened_band, 0.0, 0.0) == "icicle", "new visible side band is lethal")
	check(not course.collision_at(Vector2(540.0 + 17.0, -2000.0 - 35.0), 0.0, 0.0), "clear space outside the widened silhouette stays safe")
	var before := Vector2(553.0, -2120.0)
	var after := Vector2(553.0, -1880.0)
	check(not course.collision_at(before, 0.0, 0.0) and not course.collision_at(after, 0.0, 0.0), "fast crossing starts and ends outside the icicle")
	check(course.collision_kind_along(before, after, 0.0, 1.0 / 120.0, 0.0) == "icicle", "CCD catches a fast crossing through the newly visible band")
	check(course.collision_kind_along(Vector2(558.0, -2120.0), Vector2(558.0, -1880.0), 0.0, 1.0 / 120.0, 0.0).is_empty(), "adjacent fast crossing outside the body stays clear")

	var legacy := _stationary_icicle(1.0, true)
	course.hazards = [legacy]
	var saved: Dictionary = JSON.parse_string(JSON.stringify(course.snapshot(), "", false, true))
	var restored := RushCourse.new()
	root.add_child(restored)
	restored.restore(saved)
	check(restored.hazards[0]["r"] == 14.0 and restored.hazards[0]["half_length"] == 33.0, "older checkpoints retain their actual icicle dimensions")
	course.hazards = restored.hazards
	_check_texture_parity(course.hazards[0], "legacy 14/33 checkpoint")
	restored.free()

	var bright := false
	var dark := false
	var image: Image = course._long_polygon_texture("icicle").get_image()
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.5:
				bright = bright or pixel.get_luminance() > 0.9
				dark = dark or pixel.get_luminance() < 0.35
	check(bright and dark, "icicle has a bright internal face and a dark contrasting contour")
	var chunk := course._central_hazard("ice_chunk", 0.0)
	var frost := course._central_hazard("frost", 0.0)
	var teeth := course._wall_spikes(0.0, 2000.0, 48.0)
	check(chunk["r"] == 38.0 and frost["r"] == 13.0 and frost["half_length"] == 38.0, "ice chunks and frost keep their existing dimensions")
	check(teeth["kind"] == "ice_teeth" and course.SPIKE_REACH == 84.0, "wall ice teeth keep their existing reach and silhouette")
	var kinds: Dictionary = {}
	for world: String in course.WORLD_TYPES:
		for kind: String in course.WORLD_TYPES[world]:
			kinds[kind] = true
	check(kinds.size() == 24, "all 24 themed obstacle kinds remain available")
	course.free()
	await process_frame
	print("V25 ICICLES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
