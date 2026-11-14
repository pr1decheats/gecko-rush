extends SceneTree
## Readable relay size/density, exact visible-body collision and saved geometry.
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

func _stationary_frost(legacy_scale: float = 0.0) -> Dictionary:
	var item := course._central_hazard("frost", 0.0)
	if legacy_scale > 0.0:
		item["r"] = 13.0 * legacy_scale
		item["half_length"] = 38.0 * legacy_scale
	item["x"] = 540.0
	item["h"] = 2000.0
	item["angle"] = 0.0
	item["motion_x"] = 0.0
	item["motion_y"] = 0.0
	item["amplitude"] = 0.0
	item["phase"] = 0.0
	course._cache_geometry(item)
	return item

func _size(item: Dictionary) -> Vector2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector2 in item["_polygon"]:
		low = low.min(point)
		high = high.max(point)
	return high - low

func _texture_parity(item: Dictionary, context: String) -> void:
	var image: Image = course._long_polygon_texture("frost").get_image()
	var polygon: PackedVector2Array = item["_polygon"]
	var extent := Vector2(float(item["r"]) + float(item["half_length"]), float(item["r"]))
	var matches := true
	var samples := 0
	for y in range(1, image.get_height() - 1, 2):
		for x in range(1, image.get_width() - 1, 2):
			var point := Vector2((float(x) / (image.get_width() - 1) * 2.0 - 1.0) * extent.x, (float(y) / (image.get_height() - 1) * 2.0 - 1.0) * extent.y)
			var distance := INF
			for index in polygon.size():
				distance = minf(distance, Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()]).distance_to(point))
			if distance < 0.3:
				continue
			matches = matches and (image.get_pixel(x, y).a > 0.5) == course.collision_at(Vector2(540, -2000) + point, 0.0, 0.0)
			samples += 1
	check(samples > 600 and matches, "Rendered frost pixels and actual collision agree: " + context)

func _run() -> void:
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	course = RushCourse.new()
	root.add_child(course)
	course.setup(41, "ice")
	var frost := _stationary_frost()
	course.hazards = [frost]
	check(_size(frost).is_equal_approx(Vector2(140, 52)), "Frost body is one clearly visible 140x52 obstacle")
	check(_size(frost).x < 170.0 and _size(frost).y < 70.0, "Frost stays smaller than a large wall obstacle")
	var widened := Vector2(540, -1982)
	check(course.collision_kind_at(widened, 0.0, 0.0) == "frost", "The enlarged white central band is actually lethal")
	check(not course.collision_at(Vector2(540, -1969), 0.0, 0.0), "Clear air outside the enlarged body remains safe")
	check(course.collision_kind_along(Vector2(400, -1982), Vector2(680, -1982), 0.0, 1.0 / 120.0, 0.0) == "frost", "CCD catches high-speed crossing through the newly visible band")
	check(course.collision_kind_along(Vector2(400, -1969), Vector2(680, -1969), 0.0, 1.0 / 120.0, 0.0).is_empty(), "Adjacent swept path outside the body stays clear")
	if DisplayServer.get_name() != "headless":
		_texture_parity(frost, "current 26/44")
	for scale_value: float in [1.0, 0.64]:
		var old := _stationary_frost(scale_value)
		course.hazards = [old]
		var r := 13.0 * scale_value
		var length := 38.0 * scale_value
		var tip := r + length
		var old_polygon := PackedVector2Array([Vector2(-tip, 0), Vector2(-length, -r * 0.45), Vector2(-length * 0.35, -r * 0.45), Vector2(-length * 0.12, -r), Vector2(length * 0.12, -r), Vector2(length * 0.35, -r * 0.45), Vector2(length, -r * 0.45), Vector2(tip, 0), Vector2(length, r * 0.45), Vector2(length * 0.35, r * 0.45), Vector2(length * 0.12, r), Vector2(-length * 0.12, r), Vector2(-length * 0.35, r * 0.45), Vector2(-length, r * 0.45)])
		var preserved: bool = old_polygon.size() == old["_polygon"].size()
		for index in old_polygon.size():
			preserved = preserved and old_polygon[index].is_equal_approx(old["_polygon"][index])
		check(preserved, "Existing saved frost silhouette is unchanged at scale " + str(scale_value))
		var saved: Dictionary = JSON.parse_string(JSON.stringify(course.snapshot(), "", false, true))
		var restored := RushCourse.new()
		root.add_child(restored)
		restored.restore(saved)
		check(is_equal_approx(float(restored.hazards[0]["r"]), r) and is_equal_approx(float(restored.hazards[0]["half_length"]), length), "Checkpoint preserves old dimensions at scale " + str(scale_value))
		course.hazards = restored.hazards
		if DisplayServer.get_name() != "headless":
			_texture_parity(course.hazards[0], "legacy scale " + str(scale_value))
		restored.free()
	var relay_cells := 0
	var relay_count := 0
	for world: String in ["ice", "crystal", "sky"]:
		for seed_value: int in [41, 7960, 15879]:
			course.setup(seed_value, world)
			for metres: float in [0.0, 575.0, 4000.0, 12000.0]:
				course.ensure_ahead(metres * 64.0, 10.0)
				for action: Dictionary in course.witness:
					if int(action.get("layout", -1)) != 8 or bool(action.get("breathing", false)):
						continue
					var count := 0
					for hazard: Dictionary in course.hazards:
						if not bool(hazard.get("gate", false)) and float(hazard["h"]) >= float(action["cell_start"]) and float(hazard["h"]) <= float(action["cell_end"]):
							count += 1
							check(float(hazard["x"]) == 540.0, "Readable relay remains centered away from both wall lanes")
					check(count == 1, "A relay cell contains one readable obstacle instead of two miniatures: " + world)
					relay_cells += 1
					relay_count += count
				check(course.rejected_candidates == 0, "Larger relay envelopes keep every built-in pattern feasible: " + world)
				check(course.validate_witness(39.9) and course.validate_witness(59.9), "Larger bodies remain safe across dusk/dawn: " + world)
	check(relay_cells > 12 and relay_count == relay_cells, "Multiple seeds/heights exercise reduced density in all three relay worlds")
	if DisplayServer.get_name() != "headless":
		var image: Image = course._long_polygon_texture("frost").get_image()
		var bright := false
		var dark := false
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x, y)
				if color.a > 0.5:
					bright = bright or color.get_luminance() > 0.95
					dark = dark or color.get_luminance() < 0.3
		check(bright and dark, "Frost has a bright white face and deep blue contour")
	course.free()
	await process_frame
	print("V26 VISIBILITY: %d checks, %d failures, %d single-relay cells" % [checks, failures, relay_cells])
	quit(1 if failures else 0)
