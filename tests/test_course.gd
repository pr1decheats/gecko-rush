extends SceneTree
## Run: godot --headless --path . --script tests/test_course.gd

const CourseScript = preload("res://scripts/course.gd")
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
	for world: String in ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]:
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
					check(kind == "spikes" or kind == "timed" or course.WORLD_TYPES[world].has(kind), "World must respect its obstacle whitelist")
				check(_simulate_witness(course, height), "Actual-motion collision on certified path")
			check(course.rejected_candidates == 0, "Generator should not need to discard built-in patterns")
			total_cells += course.generated_cells
			course.free()
	for kind: String in ["spikes", "stone", "insect", "saw", "electric", "falling", "crystal", "pendulum", "vine"]:
		check(covered.has(kind), "Missing obstacle type: " + kind)
	_test_restore()
	_test_collision_and_coins()
	_test_challenge_unlock()
	print("COURSE TESTS: %d checks, %d failures, %d generated cells, %d obstacle kinds" % [checks, failures, total_cells, covered.size()])
	await process_frame
	quit(0 if failures == 0 else 1)


func _simulate_witness(course, phase_height: float) -> bool:
	# Geometry was validated against complete movement envelopes. This also
	# exercises real shape collision at unrelated phases of every animation.
	for action: Dictionary in course.get_witness():
		var source_side := int(action["from_side"])
		var target_side := int(action["to_side"])
		var source_x := 296.0 if source_side == 0 else 784.0
		var target_x := 296.0 if target_side == 0 else 784.0
		var h := float(action["cell_start"])
		var time := phase_height / 290.0 + float(action["cell_start"]) / 320.0
		while h < float(action["height_px"]):
			if course.collision_at(Vector2(source_x, -h), time, 28.0):
				return false
			h += 5.0
			time += 5.0 / course.speed_at(h)
		if source_side != target_side:
			h = float(action["height_px"])
			var previous := 0.0
			for i in range(1, 125):
				var t := float(i) / 124.0
				var dt := CourseScript.JUMP_DURATION / 124.0
				h += course.speed_at(h) * dt + (sin(PI * t) - sin(PI * previous)) * CourseScript.JUMP_ARC
				var x := lerpf(source_x, target_x, 0.5 - 0.5 * cos(PI * t))
				time += dt
				if course.collision_at(Vector2(x, -h), time, 28.0):
					return false
				previous = t
		while h < float(action["cell_end"]):
			if course.collision_at(Vector2(target_x, -h), time, 28.0):
				return false
			h += 5.0
			time += 5.0 / course.speed_at(h)
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


func _test_challenge_unlock() -> void:
	var ordinary = CourseScript.new()
	var challenge = CourseScript.new()
	root.add_child(ordinary)
	root.add_child(challenge)
	ordinary.setup(441, "jungle")
	ordinary.ensure_ahead(15000.0, 60.0)
	challenge.challenge_level = 8
	challenge.setup(441, "jungle")
	challenge.ensure_ahead(15000.0, 60.0)
	var ordinary_timed := 0
	var challenge_timed := 0
	for item: Dictionary in ordinary.hazards:
		if String(item["kind"]) == "timed":
			ordinary_timed += 1
	for item: Dictionary in challenge.hazards:
		if String(item["kind"]) == "timed":
			challenge_timed += 1
	# Timed spikes now share a shuffled deck with seven structures. Sample
	# several streamed windows rather than requiring one in a particular row.
	for sample in range(20, 100, 4):
		var height := float(sample) * 1120.0
		challenge.ensure_ahead(height, 60.0)
		for item: Dictionary in challenge.hazards:
			if String(item["kind"]) == "timed":
				challenge_timed += 1
	check(ordinary_timed == 0, "Timed spikes must stay locked below level 8")
	check(challenge_timed > 0, "Level 8 must unlock timed-spike trials")
	check(challenge.validate_witness(), "Unlocked timed spikes must preserve the safe route")
	ordinary.free()
	challenge.free()
