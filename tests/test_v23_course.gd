extends SceneTree
## Run: godot --headless --path . --script tests/test_v23_course.gd
## World selection controls obstacle families, spacing and motion. A route
## certificate is also exercised with the same timed speed and jump as main.

const CourseScript = preload("res://scripts/course.gd")
const WORLDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
const THEMED_TYPES := {
	"jungle": ["root", "beetle", "vine", "thorns"],
	"canyon": ["boulder", "rockfall", "canyon_weight", "sand_spur"],
	"ice": ["icicle", "ice_chunk", "frost", "ice_teeth"],
	"crystal": ["prism", "crystal_beam", "shard", "crystal_teeth"],
	"volcano": ["lava_orb", "fire_jet", "obsidian", "magma_teeth"],
	"sky": ["lightning", "storm_orb", "wind_blade", "storm_spikes"],
}
const STEP := 1.0 / 120.0
const ROUTE_RADIUS := 28.0
var checks := 0
var failures := 0
var generated_cells := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var audio: Node = root.get_node_or_null("Audio")
	if audio != null:
		audio.call("set_music_enabled", false)
	_test_world_profiles()
	for world: String in WORLDS:
		var generated_types: Dictionary = {}
		_test_variety(world)
		_test_themed_collisions(world)
		_test_level_independence(world)
		_test_restore(world)
		_test_safe_section(world)
		for seed_index in range(4):
			var course = CourseScript.new()
			root.add_child(course)
			course.setup(seed_index * 7919 + 41, world)
			check(not course.collision_at(Vector2(CourseScript.LEFT_X, -800.0), 0.0), "Opening must be safe: " + world)
			for height: float in [0.0, 12000.0, 68000.0, 160000.0]:
				course.ensure_ahead(height, height / 900.0)
				var context := "%s seed=%d height=%d" % [world, seed_index, int(height)]
				check(course.validate_witness(), "Invalid complete-motion certificate: " + context)
				check(course.hazards.size() < 40, "Hazards must remain streamed: " + context)
				for item: Dictionary in course.hazards:
					var kind := String(item["kind"])
					check(kind in THEMED_TYPES[world], "Foreign obstacle %s in %s" % [kind, context])
					generated_types[kind] = true
				for phase: float in [0.0, 39.9, 59.9]:
					check(course.validate_witness(phase), "Timed selected-world route certification at phase=%f: %s" % [phase, context])
					check(_simulate_witness(course, phase), "Real selected-world route collision at phase=%f: %s" % [phase, context])
			check(course.rejected_candidates == 0, "Built-in themed patterns need no emergency rejection: %s seed=%d" % [world, seed_index])
			generated_cells += course.generated_cells
			course.free()
		for kind: String in THEMED_TYPES[world]:
			check(generated_types.has(kind), "Themed obstacle actually appears in generation: %s/%s" % [world, kind])
	print("V23 COURSE: %d checks, %d failures, %d generated cells" % [checks, failures, generated_cells])
	await process_frame
	quit(1 if failures else 0)

func _test_world_profiles() -> void:
	var previous_speed := 0.0
	var previous_spacing := INF
	var previous_motion := 0.0
	for world: String in WORLDS:
		check(CourseScript.WORLD_TYPES[world].size() == THEMED_TYPES[world].size(), "World exposes its distinct themed obstacle family: " + world)
		for kind: String in THEMED_TYPES[world]:
			check(CourseScript.WORLD_TYPES[world].has(kind), "Themed obstacle belongs to its world: %s/%s" % [world, kind])
		var profile: Dictionary = RushTuning.profile_for(world)
		check(float(profile["start_speed"]) >= previous_speed, "Selected difficulty orders starting speed: " + world)
		check(float(profile["spacing_scale"]) <= previous_spacing, "Selected difficulty orders spacing: " + world)
		check(float(profile["motion_scale"]) >= previous_motion, "Selected difficulty orders motion: " + world)
		for height: float in [0.0, 16000.0, 64000.0, 128000.0, 1000000.0]:
			check(RushTuning.speed_at(height, world) <= 2700.0, "Day speed cap: " + world)
			check(RushTuning.run_speed_at(height, 45.0, world) == float(profile["night_speed"]), "Night uses selected-world speed: " + world)
		previous_speed = float(profile["start_speed"])
		previous_spacing = float(profile["spacing_scale"])
		previous_motion = float(profile["motion_scale"])
	var easiest = CourseScript.new()
	var hardest = CourseScript.new()
	root.add_child(easiest)
	root.add_child(hardest)
	easiest.setup(983, "jungle")
	hardest.setup(983, "sky")
	var easy_span := float(easiest.witness[0]["cell_end"]) - float(easiest.witness[0]["cell_start"])
	var hard_span := float(hardest.witness[0]["cell_end"]) - float(hardest.witness[0]["cell_start"])
	check(easy_span > hard_span, "Selected-world spacing must change generated geometry")
	easiest.free()
	hardest.free()
	for first: String in WORLDS:
		for second: String in WORLDS:
			if first >= second:
				continue
			check(CourseScript.WORLD_TYPES[first] != CourseScript.WORLD_TYPES[second], "Worlds need distinct obstacle families: %s/%s" % [first, second])
			check(_canonical(_layout_weights(first)) != _canonical(_layout_weights(second)), "Worlds need distinct weighted course patterns: %s/%s" % [first, second])

func _test_variety(world: String) -> void:
	var course = CourseScript.new()
	root.add_child(course)
	course.setup(2929, world)
	var previous: Array[String] = []
	var covered: Dictionary = {}
	for index in range(100):
		var chosen: String = course._choose_type()
		check(CourseScript.WORLD_TYPES[world].has(chosen), "World type picker respects its family: " + world)
		check(not previous.has(chosen), "Avoid recent obstacle repetition: " + world)
		covered[chosen] = true
		previous.append(chosen)
		if previous.size() > 2:
			previous.pop_front()
	check(covered.size() >= 3, "World offers several obstacle behaviors: " + world)
	var previous_layout := -1
	var layouts: Dictionary = {}
	for index in range(100):
		var layout: int = course._next_layout()
		check(layout != previous_layout, "Avoid consecutive pattern repetition: " + world)
		layouts[layout] = true
		previous_layout = layout
	check(layouts.size() >= 4, "World offers several course patterns: " + world)
	course.free()

func _test_level_independence(world: String) -> void:
	var first = CourseScript.new()
	var veteran = CourseScript.new()
	root.add_child(first)
	root.add_child(veteran)
	first.challenge_level = 1
	veteran.challenge_level = 99
	first.setup(441, world)
	veteran.setup(441, world)
	first.ensure_ahead(90000.0, 45.0)
	veteran.ensure_ahead(90000.0, 45.0)
	var first_state: Dictionary = first.snapshot()
	var veteran_state: Dictionary = veteran.snapshot()
	first_state.erase("challenge_level")
	veteran_state.erase("challenge_level")
	check(_canonical(first_state) == _canonical(veteran_state), "Profile XP must not change selected-world physics: " + world)
	first.free()
	veteran.free()

func _test_themed_collisions(world: String) -> void:
	var course = CourseScript.new()
	root.add_child(course)
	course.setup(13, world)
	# The final family member is the wall shape. Exercise the three other
	# families directly so rare pulse/beam hazards cannot escape collision
	# coverage merely because a sampled generated window did not contain one.
	for index in range(3):
		var kind: String = THEMED_TYPES[world][index]
		var item: Dictionary = course._central_hazard(kind, 0.0)
		item["x"] = 540.0
		item["h"] = 2000.0
		item["phase"] = 0.0
		item["amplitude"] = 0.0
		course._cache_geometry(item)
		course.hazards = [item]
		var center: Vector2 = course._hazard_center(item, 0.0)
		var expected := "electric" if kind in ["lightning", "storm_orb"] else kind
		check(course.collision_kind_at(center, 0.0, 20.0) == expected, "Themed contact selects the correct death effect: " + kind)
		check(not course.collision_at(Vector2(540.0, -2000.0 - float(item["_ey"]) - 100.0), 0.0, 20.0), "Themed hit area remains inside its certified envelope: " + kind)
	var wall: Dictionary = course._wall_spikes(0.0, 2000.0, 48.0)
	wall["phase"] = 0.0
	course._cache_geometry(wall)
	course.hazards = [wall]
	var triangle: PackedVector2Array = wall["_triangles"][0]
	var contact := (triangle[0] + triangle[1] + triangle[2]) / 3.0
	check(String(wall["kind"]) == THEMED_TYPES[world][3], "World wall hazard uses its themed shape: " + world)
	check(course.collision_kind_at(contact, 0.0, 20.0) == String(wall["kind"]), "Themed wall shape is lethal where drawn: " + world)
	course.free()

func _test_restore(world: String) -> void:
	var first = CourseScript.new()
	var restored = CourseScript.new()
	root.add_child(first)
	root.add_child(restored)
	first.setup(68887123, world)
	first.ensure_ahead(12000.0, 44.5)
	first.begin_safe_section(14000.0, 17000.0)
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(first.snapshot(), "", false, true))
	restored.restore(decoded)
	check(restored.rng.state == first.rng.state, "JSON preserves full RNG state: " + world)
	first.ensure_ahead(22000.0, 61.0)
	restored.ensure_ahead(22000.0, 61.0)
	check(_canonical(first.snapshot()) == _canonical(restored.snapshot()), "JSON restore preserves future themed generation: " + world)
	check(_simulate_witness(restored, 39.9), "Restored route preserves transition feasibility: " + world)
	first.free()
	restored.free()

func _test_safe_section(world: String) -> void:
	var course = CourseScript.new()
	root.add_child(course)
	course.setup(12, world)
	course.begin_safe_section(4000.0, 9000.0)
	course.ensure_ahead(7000.0, 45.0)
	check(course.validate_witness(), "Safe sections preserve route certificate: " + world)
	var first := 4000.0 - CourseScript.SAFE_SECTION_PADDING
	var last := 9000.0 + CourseScript.SAFE_SECTION_PADDING
	for item: Dictionary in course.hazards:
		check(float(item["h"]) + float(item["_ey"]) < first or float(item["h"]) - float(item["_ey"]) > last, "Complete moving obstacle envelope clears central event: " + world)
	for items: Array in [course.coins, course.flies]:
		for item: Dictionary in items:
			check(float(item["h"]) < first or float(item["h"]) > last, "Central event suppresses pickups: " + world)
	for height: float in [4000.0, 6000.0, 8900.0]:
		for x: float in [CourseScript.LEFT_X, 540.0, CourseScript.RIGHT_X]:
			check(not course.collision_at(Vector2(x, -height), 45.0), "Central event remains clear across its full width: " + world)
	course.free()

func _simulate_witness(course, start_time: float) -> bool:
	# Restart the clock for every action to cover arbitrary animation phases
	# and day/night boundaries independently. Motion still uses real seconds.
	for action: Dictionary in course.get_witness():
		var source_x := CourseScript.LEFT_X if int(action["from_side"]) == 0 else CourseScript.RIGHT_X
		var target_x := CourseScript.LEFT_X if int(action["to_side"]) == 0 else CourseScript.RIGHT_X
		var height := float(action["cell_start"])
		var clock := start_time
		var jump_start := float(action["height_px"])
		while height < jump_start:
			var dt := minf(STEP, maxf(0.000001, (jump_start - height) / RushTuning.run_speed_at(height, clock + STEP, course.world_id)))
			clock += dt
			height += RushTuning.run_speed_at(height, clock, course.world_id) * dt
			if course.collision_at(Vector2(source_x, -height), clock, ROUTE_RADIUS):
				return false
		if source_x != target_x:
			var elapsed := 0.0
			while elapsed < CourseScript.JUMP_DURATION - 0.000001:
				var dt := minf(STEP, CourseScript.JUMP_DURATION - elapsed)
				var old_fraction := elapsed / CourseScript.JUMP_DURATION
				elapsed += dt
				var fraction := elapsed / CourseScript.JUMP_DURATION
				clock += dt
				height += RushTuning.run_speed_at(height, clock, course.world_id) * dt
				height += (sin(fraction * PI) - sin(old_fraction * PI)) * CourseScript.JUMP_ARC
				var x := lerpf(source_x, target_x, 0.5 - 0.5 * cos(PI * fraction))
				if course.collision_at(Vector2(x, -height), clock, ROUTE_RADIUS):
					return false
		while height < float(action["cell_end"]):
			clock += STEP
			height += RushTuning.run_speed_at(height, clock, course.world_id) * STEP
			if course.collision_at(Vector2(target_x, -height), clock, ROUTE_RADIUS):
				return false
	return true

func _canonical(value: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", false, true)), "", false, true)

func _layout_weights(world: String) -> Dictionary:
	var counts: Dictionary = {}
	for layout: int in CourseScript.WORLD_LAYOUTS[world]:
		var key := str(layout)
		counts[key] = int(counts.get(key, 0)) + 1
	return counts
