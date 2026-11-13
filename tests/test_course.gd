extends SceneTree
## Run: godot --headless --path . --script tests/test_course.gd

const CourseScript = preload("res://scripts/course.gd")
const WORLDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	# This geometry test does not use audio. Stop the optional autoload's music
	# so its active playback can be released before the headless process exits.
	var audio: Node = root.get_node_or_null("Audio")
	if audio != null:
		audio.call("set_music_enabled", false)
	var covered: Dictionary = {}
	var total_cells := 0
	for world: String in WORLDS:
		for seed_index in range(12):
			var course = CourseScript.new()
			root.add_child(course)
			course.setup(seed_index * 7919 + 41, world)
			check(not course.collision_at(Vector2(296.0, -800.0), 0.0), "Opening lane must be safe")
			# Check different speeds, world distributions, phases and streamed
			# neighbouring cells, all the way to the speed cap.
			for height: float in [0.0, 5500.0, 18000.0, 39000.0, 68000.0]:
				course.ensure_ahead(height, height / 330.0)
				check(course.validate_witness(), "Unsafe witness: world=%s seed=%d height=%f" % [world, seed_index, height])
				check(course.hazards.size() < 33, "Hazards must be streamed and bounded")
				for hazard: Dictionary in course.hazards:
					covered[String(hazard["kind"])] = true
					var kind := String(hazard["kind"])
					check(course.WORLD_TYPES[world].has(kind), "World must respect its themed obstacle whitelist")
				check(_simulate_witness(course, height), "Actual-motion collision on certified path")
			check(course.rejected_candidates == 0, "Generator should not need to discard built-in patterns")
			total_cells += course.generated_cells
			course.free()
	for world: String in WORLDS:
		for kind: String in CourseScript.WORLD_TYPES[world]:
			check(covered.has(kind), "Missing themed obstacle type: " + kind)
	check(covered.size() == 24, "Six worlds generate 24 distinct themed obstacle kinds")
	_test_restore()
	_test_collision_and_coins()
	_test_world_difficulty()
	print("COURSE TESTS: %d checks, %d failures, %d generated cells, %d obstacle kinds" % [checks, failures, total_cells, covered.size()])
	await process_frame
	quit(0 if failures == 0 else 1)


func _simulate_witness(course, phase_height: float) -> bool:
	# Independently integrate the same time-dependent selected-world speed
	# and 120Hz jump as main, at unrelated phases of every animation.
	for action: Dictionary in course.get_witness():
		var source_side := int(action["from_side"])
		var target_side := int(action["to_side"])
		var source_x := 296.0 if source_side == 0 else 784.0
		var target_x := 296.0 if target_side == 0 else 784.0
		var h := float(action["cell_start"])
		var time := phase_height / 290.0 + float(action["cell_start"]) / 320.0
		while h < float(action["height_px"]):
			var dt := minf(STEP, maxf(0.000001, (float(action["height_px"]) - h) / RushTuning.run_speed_at(h, time + STEP, course.world_id)))
			time += dt
			h += RushTuning.run_speed_at(h, time, course.world_id) * dt
			if course.collision_at(Vector2(source_x, -h), time, 28.0):
				return false
		if source_side != target_side:
			var elapsed := 0.0
			while elapsed < CourseScript.JUMP_DURATION - 0.000001:
				var dt := minf(STEP, CourseScript.JUMP_DURATION - elapsed)
				var previous := elapsed / CourseScript.JUMP_DURATION
				elapsed += dt
				var t := elapsed / CourseScript.JUMP_DURATION
				time += dt
				h += RushTuning.run_speed_at(h, time, course.world_id) * dt + (sin(PI * t) - sin(PI * previous)) * CourseScript.JUMP_ARC
				var x := lerpf(source_x, target_x, 0.5 - 0.5 * cos(PI * t))
				if course.collision_at(Vector2(x, -h), time, 28.0):
					return false
		while h < float(action["cell_end"]):
			time += STEP
			h += RushTuning.run_speed_at(h, time, course.world_id) * STEP
			if course.collision_at(Vector2(target_x, -h), time, 28.0):
				return false
	return true


func _test_restore() -> void:
	var first = CourseScript.new()
	var restored = CourseScript.new()
	root.add_child(first)
	root.add_child(restored)
	first.setup(68887123, "crystal")
	first.ensure_ahead(12000.0, 44.5)
	# Exercise the actual JSON round-trip, including large RNG state integers.
	var encoded := JSON.stringify(first.snapshot(), "", false, true)
	var decoded: Dictionary = JSON.parse_string(encoded)
	restored.restore(decoded)
	check(restored.world_id == first.world_id, "World must survive restore")
	check(restored.hazards.size() == first.hazards.size(), "Hazards must survive restore")
	check(restored.rng.state == first.rng.state, "Full RNG state must survive JSON")
	first.ensure_ahead(18000.0, 65.0)
	restored.ensure_ahead(18000.0, 65.0)
	check(_canonical_snapshot(first.snapshot()) == _canonical_snapshot(restored.snapshot()), "Resumed future generation must be identical")
	for x: float in [296.0, 330.0, 540.0, 760.0, 784.0]:
		for h: float in [17500.0, 18000.0, 18950.0, 19460.0]:
			check(first.collision_at(Vector2(x, -h), 65.0) == restored.collision_at(Vector2(x, -h), 65.0), "Restored collisions must use the same motion phase")
	first.free()
	restored.free()


func _test_collision_and_coins() -> void:
	var course = CourseScript.new()
	root.add_child(course)
	course.setup(12, "jungle")
	var spike: Dictionary = course.hazards[0]
	check(course.collision_at(Vector2(296.0, -float(spike["h"])), 0.0), "Wall spike must be lethal")
	check(not course.collision_at(Vector2(784.0, -float(spike["h"])), 0.0), "Opposite wall must remain safe")
	var coin: Dictionary = course.coins[0]
	var point := Vector2(float(coin["x"]), -float(coin["h"]))
	check(course.collect_at(point, 0.0) == 1, "A coin must be collectible")
	check(course.collect_at(point, 0.0) == 0, "A coin cannot be collected twice")
	check(course.count_passed(784.0) == 0, "Unpassed hazards cannot award XP")
	check(course.count_passed(2600.0) > 0, "Passing a hazard must count")
	check(course.count_passed(2600.0) == 0, "A hazard cannot count twice")
	course.free()


func _canonical_snapshot(value: Dictionary) -> String:
	# JSON normalizes all numeric values to floats. Canonicalize both sides so
	# int(1) and float(1.0) do not look like different procedural courses.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", false, true)), "", false, true)


func _test_world_difficulty() -> void:
	var previous_speed := 0.0
	var previous_spacing := INF
	var previous_motion := 0.0
	for world: String in WORLDS:
		var ordinary = CourseScript.new()
		var veteran = CourseScript.new()
		root.add_child(ordinary)
		root.add_child(veteran)
		ordinary.challenge_level = 1
		veteran.challenge_level = 80
		ordinary.setup(441, world)
		veteran.setup(441, world)
		ordinary.ensure_ahead(60000.0, 60.0)
		veteran.ensure_ahead(60000.0, 60.0)
		var first: Dictionary = ordinary.snapshot()
		var experienced: Dictionary = veteran.snapshot()
		first.erase("challenge_level")
		experienced.erase("challenge_level")
		check(_canonical_snapshot(first) == _canonical_snapshot(experienced), "Profile level must not increase physics difficulty: " + world)
		var profile: Dictionary = RushTuning.profile_for(world)
		check(float(profile["start_speed"]) > previous_speed, "World tier increases starting speed: " + world)
		check(float(profile["spacing_scale"]) < previous_spacing, "World tier increases obstacle density: " + world)
		check(float(profile["motion_scale"]) > previous_motion, "World tier increases obstacle motion: " + world)
		check(ordinary.validate_witness(40.0), "Night route remains feasible in every tier: " + world)
		previous_speed = float(profile["start_speed"])
		previous_spacing = float(profile["spacing_scale"])
		previous_motion = float(profile["motion_scale"])
		ordinary.free()
		veteran.free()
	for first: String in WORLDS:
		for second: String in WORLDS:
			if first < second:
				check(_canonical_snapshot(_layout_weights(first)) != _canonical_snapshot(_layout_weights(second)), "Worlds need distinct weighted course patterns: %s/%s" % [first, second])

func _layout_weights(world: String) -> Dictionary:
	var counts: Dictionary = {}
	for layout: int in CourseScript.WORLD_LAYOUTS[world]:
		var key := str(layout)
		counts[key] = int(counts.get(key, 0)) + 1
	return counts
