extends SceneTree
## Godot --headless --path . --script tests/test_v24_course.gd
## A certificate with optional jumps is insufficient: these tests require
## actual wall contact, then measure inputs made by a collision-driven bot.

const CourseScript = preload("res://scripts/course.gd")
const WORLDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
const SEEDS := [41, 7960, 15879, 23798, 31717, 39636]
const STEP := 1.0 / 120.0
const PLAYER_RADIUS := 20.0
const BOT_LOOKAHEAD := 0.30
var checks := 0
var failures := 0
var forced_gates := 0
var bot_jumps := 0

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
	_test_fast_segments()
	for world: String in WORLDS:
		for seed_value: int in SEEDS:
			_test_camping(world, seed_value)
		for seed_value: int in [41, 15879]:
			_test_actual_gates(world, seed_value)
	for seed_value: int in SEEDS:
		_test_bot_tempo(seed_value)
	for kilometres: float in [12.0, 50.0]:
		for phase: float in [0.0, 39.9, 59.9]:
			_test_late_bot(kilometres, phase)
	_test_full_climb()
	_test_late_restore()
	print("V24 COURSE: %d checks, %d failures, %d physically forced gates, %d collision-driven bot jumps" % [checks, failures, forced_gates, bot_jumps])
	await process_frame
	quit(1 if failures else 0)

func _test_camping(world: String, seed_value: int) -> void:
	for side in range(2):
		var course = CourseScript.new()
		root.add_child(course)
		course.setup(seed_value, world)
		var height := 0.0
		var clock := 0.0
		var x := _wall_x(side)
		var died := false
		while clock < 8.0 and height < 12000.0:
			var before := Vector2(x, -height)
			clock += STEP
			height += RushTuning.run_speed_at(height, clock, world) * STEP
			course.ensure_ahead(height, clock)
			if not course.collision_kind_along(before, Vector2(x, -height), clock - STEP, clock, PLAYER_RADIUS).is_empty():
				died = true
				break
		check(died, "Camping must die early on either wall: %s seed=%d side=%d height=%.0f time=%.2f" % [world, seed_value, side, height, clock])
		course.free()

func _test_actual_gates(world: String, seed_value: int) -> void:
	var course = CourseScript.new()
	root.add_child(course)
	course.setup(seed_value, world)
	for height: float in [0.0, 256000.0, 768000.0, 3200000.0]:
		course.ensure_ahead(height, 0.0)
		var context := "%s seed=%d height=%.0f" % [world, seed_value, height]
		check(course.hazards.size() < 64 and course.witness.size() < 24, "Dynamic lookahead remains bounded: " + context)
		check(course.next_cell >= height + course.stream_ahead_at(height), "Dynamic lookahead supplies future input time: " + context)
		for phase: float in [0.0, 39.9, 59.9]:
			check(course.validate_witness(phase), "Late swept route remains feasible: %s phase=%.1f" % [context, phase])
		for action: Dictionary in course.get_witness():
			var start := float(action["cell_start"])
			var end := float(action["cell_end"])
			if start < height:
				continue # The first streamed cell may already be partly behind us.
			var gates := 0
			for item: Dictionary in course.hazards:
				if bool(item.get("gate", false)) and float(item["h"]) >= start and float(item["h"]) <= end:
					gates += 1
			if bool(action["breathing"]):
				check(int(action["from_side"]) == int(action["to_side"]) and gates == 0, "Rest has no artificial jump instruction: " + context)
				continue
			check(int(action["from_side"]) != int(action["to_side"]), "Every ordinary cell actually changes its safe wall: " + context)
			check(gates >= 1, "Every ordinary cell contains a permanent lethal wall gate: " + context)
			for phase: float in [0.0, 39.9, 59.9]:
				var contact := _walk_lane(course, start, end, int(action["from_side"]), phase)
				check(not contact.is_empty(), "Omitting this jump must cause real contact: %s start=%.0f phase=%.1f" % [context, start, phase])
				check(_walk_lane(course, start, end, int(action["to_side"]), phase).is_empty(), "The arrival wall remains a safe choice: %s start=%.0f phase=%.1f" % [context, start, phase])
			forced_gates += 1
		check(course.rejected_candidates == 0, "Late generation must construct valid gates without discards: " + context)
	course.free()

func _walk_lane(course, start: float, end: float, side: int, phase: float) -> String:
	var height := start
	var clock := phase
	var x := _wall_x(side)
	while height < end:
		var dt := minf(STEP, maxf(0.000001, (end - height) / RushTuning.run_speed_at(height, clock + STEP, course.world_id)))
		var before := Vector2(x, -height)
		clock += dt
		height += RushTuning.run_speed_at(height, clock, course.world_id) * dt
		var contact: String = course.collision_kind_along(before, Vector2(x, -height), clock - dt, clock, PLAYER_RADIUS)
		if not contact.is_empty():
			return contact
	return ""

func _test_bot_tempo(seed_value: int) -> void:
	var result := _run_collision_bot(seed_value, 256000.0, 0.0, 14.0)
	var context := "Hard 4km seed=%d" % seed_value
	check(bool(result["survived"]), "Collision-driven bot must survive: %s %s" % [context, result["error"]])
	var times: Array = result["inputs"]
	check(times.size() >= 22, "Actual geometry must require frequent input: %s jumps=%d" % [context, times.size()])
	var ordinary: Array[float] = []
	var largest_gap := 0.0
	for index in range(1, times.size()):
		var gap := float(times[index]) - float(times[index - 1])
		largest_gap = maxf(largest_gap, gap)
		check(gap >= CourseScript.JUMP_DURATION - STEP, "Inputs are physically distinct completed jumps: " + context)
		if gap < 0.75:
			ordinary.append(gap)
	var mean := 0.0
	for gap: float in ordinary:
		mean += gap
	mean /= maxf(float(ordinary.size()), 1.0)
	check(ordinary.size() >= 18 and mean >= 0.40 and mean <= 0.55, "Measured ordinary input interval is about half a second: %s mean=%.3f count=%d" % [context, mean, ordinary.size()])
	check(largest_gap <= 1.3, "Rest gaps remain bounded: %s max=%.3f" % [context, largest_gap])
	check(int(result["proved_inputs"]) == times.size(), "Every counted input prevents a probed real wall collision: " + context)
	bot_jumps += times.size()

func _test_late_bot(kilometres: float, phase: float) -> void:
	var result := _run_collision_bot(15879, kilometres * 64000.0, phase, 6.0)
	var context := "Hard %.0fkm phase=%.1f" % [kilometres, phase]
	check(bool(result["survived"]), "Fast swept bot route must survive: %s %s" % [context, result["error"]])
	if phase == 0.0:
		check(Array(result["inputs"]).size() >= 8, "Late DAY geometry still requires real inputs: " + context)
	else:
		var day_result := _run_collision_bot(15879, kilometres * 64000.0, 0.0, 6.0)
		check(bool(day_result["survived"]), "Comparison daytime bot survives: " + context)
		check(float(result["height"]) < float(day_result["height"]) and Array(result["inputs"]).size() < Array(day_result["inputs"]).size(), "Night/dawn restores a measurable respite compared with the same late daytime geometry: " + context)
	check(int(result["proved_inputs"]) == Array(result["inputs"]).size(), "Late input count is backed by actual collision: " + context)
	bot_jumps += Array(result["inputs"]).size()

func _test_full_climb() -> void:
	var result := _run_collision_bot(41, 0.0, 0.0, 420.0, 768000.0, true)
	var inputs: Array = result["inputs"]
	check(bool(result["survived"]), "Full Hard climb survives actual swept geometry: " + String(result["error"]))
	check(float(result["height"]) >= 768000.0, "Full Hard bot really reaches 12000m")
	check(inputs.size() >= 200, "Reaching 12000m requires hundreds of real collision-driven inputs, not 20–30 cosmetic jumps: count=%d" % inputs.size())
	check(int(result["proved_inputs"]) == inputs.size(), "Every full-climb input prevents an actual forecast wall collision")
	var largest_gap := 0.0
	for index in range(1, inputs.size()):
		largest_gap = maxf(largest_gap, float(inputs[index]) - float(inputs[index - 1]))
	check(largest_gap <= RushTuning.NIGHT_SECONDS + RushTuning.CYCLE_FADE_SECONDS * 2.0 + 2.5, "Full-climb gaps stay bounded by the deliberate twenty-second night respite plus fades: max=%.3f" % largest_gap)
	print("V24 FULL CLIMB: %d collision-driven jumps, %.2fs, %.0fm" % [inputs.size(), float(result["seconds"]), float(result["height"]) / 64.0])
	bot_jumps += inputs.size()

func _run_collision_bot(seed_value: int, desired_height: float, phase: float, duration: float, stop_height: float = -1.0, from_origin: bool = false) -> Dictionary:
	var course = CourseScript.new()
	root.add_child(course)
	course.setup(seed_value, "ice")
	course.ensure_ahead(desired_height, phase)
	# A late fixture must begin at a reachable cell entry. Thereafter the bot
	# never reads witness actions: all launches follow actual collision probes.
	var entry: Dictionary = {}
	if from_origin:
		entry = {"cell_start": 0.0, "from_side": 0}
	else:
		for action: Dictionary in course.get_witness():
			if float(action["cell_start"]) >= desired_height and not bool(action["breathing"]):
				entry = action
				break
	if entry.is_empty():
		course.free()
		return {"survived": false, "inputs": [], "proved_inputs": 0, "height": desired_height, "seconds": 0.0, "error": "missing late entry"}
	var height := float(entry["cell_start"])
	var side := int(entry["from_side"])
	var from_x := _wall_x(side)
	var to_x := from_x
	var x := from_x
	var clock := phase
	var elapsed := -1.0
	var inputs: Array[float] = []
	var proved := 0
	var error := ""
	while clock < phase + duration and (stop_height < 0.0 or height < stop_height):
		course.ensure_ahead(height, clock)
		if elapsed < 0.0:
			var impact := _standing_impact(course, height, clock, side)
			if not impact.is_empty():
				if String(impact["kind"]) != String(CourseScript.WORLD_WALL_KIND["ice"]):
					error = "input was provoked by an optional central hazard"
					break
				proved += 1
				inputs.append(clock - phase)
				from_x = _wall_x(side)
				to_x = _wall_x(1 - side)
				elapsed = 0.0
		var before := Vector2(x, -height)
		clock += STEP
		height += RushTuning.run_speed_at(height, clock, "ice") * STEP
		if elapsed >= 0.0:
			var old_fraction := elapsed / CourseScript.JUMP_DURATION
			elapsed = minf(elapsed + STEP, CourseScript.JUMP_DURATION)
			var fraction := elapsed / CourseScript.JUMP_DURATION
			height += (sin(fraction * PI) - sin(old_fraction * PI)) * CourseScript.JUMP_ARC
			x = lerpf(from_x, to_x, 0.5 - 0.5 * cos(PI * fraction))
			if elapsed >= CourseScript.JUMP_DURATION - 0.000001:
				side = 1 - side
				elapsed = -1.0
		var contact: String = course.collision_kind_along(before, Vector2(x, -height), clock - STEP, clock, PLAYER_RADIUS)
		if not contact.is_empty():
			error = "contact=%s h=%.0f t=%.3f" % [contact, height, clock - phase]
			break
	course.free()
	return {"survived": error.is_empty(), "inputs": inputs, "proved_inputs": proved, "height": height, "seconds": clock - phase, "error": error}

func _standing_impact(course, height: float, clock: float, side: int) -> Dictionary:
	var probe_height := height
	var probe_clock := clock
	var x := _wall_x(side)
	while probe_clock < clock + BOT_LOOKAHEAD - 0.000001:
		var before := Vector2(x, -probe_height)
		probe_clock += STEP
		probe_height += RushTuning.run_speed_at(probe_height, probe_clock, "ice") * STEP
		var contact: String = course.collision_kind_along(before, Vector2(x, -probe_height), probe_clock - STEP, probe_clock, PLAYER_RADIUS)
		if not contact.is_empty():
			return {"kind": contact, "delay": probe_clock - clock}
	return {}

func _test_fast_segments() -> void:
	var course = CourseScript.new()
	root.add_child(course)
	course.setup(12, "sky")
	course.route_side = 1
	var wall: Dictionary = course._wall_spikes(0.0, 2000.0, 4.0)
	course._cache_geometry(wall)
	course.hazards = [wall]
	var before := Vector2(CourseScript.LEFT_X, -1700.0)
	var after := Vector2(CourseScript.LEFT_X, -2300.0)
	check(not course.collision_at(before, 0.0) and not course.collision_at(after, STEP), "Thin wall fixture has safe endpoints")
	check(course.collision_kind_along(before, after, 0.0, STEP) == String(wall["kind"]), "Swept physics catches a lethal wall between safe endpoints")
	for kind: String in ["boulder", "beetle", "lightning"]:
		var item: Dictionary = course._central_hazard(kind, 0.0)
		item["x"] = 540.0
		item["h"] = 2000.0
		item["r"] = 4.0
		item["amplitude"] = 0.0
		item["motion_x"] = 0.0
		item["motion_y"] = 0.0
		item["phase"] = 0.0
		item["angle_sway"] = 0.0
		course._cache_geometry(item)
		course.hazards = [item]
		before = Vector2(540.0, -1700.0)
		after = Vector2(540.0, -2300.0)
		check(not course.collision_at(before, 0.0) and not course.collision_at(after, STEP), "Fast shape fixture has safe endpoints: " + kind)
		var expected := "electric" if kind == "lightning" else kind
		check(course.collision_kind_along(before, after, 0.0, STEP) == expected, "Swept physics catches thin polygon/circle/capsule: " + kind)
		check(course.collision_kind_along(before + Vector2(180, 0), after + Vector2(180, 0), 0.0, STEP).is_empty(), "Swept physics preserves a clearly separate lane: " + kind)
	course.hazards = []
	course.coins = [{"x": 540.0, "h": 2000.0, "collected": false, "phase": 0.0}]
	before = Vector2(540.0, -1700.0)
	after = Vector2(540.0, -2300.0)
	check(course.collect_along(before + Vector2(180, 0), after + Vector2(180, 0)) == 0, "Fast pickup sweep preserves a separate lane")
	check(course.collect_along(before, after) == 1, "Fast pickup sweep collects a crossed coin between safe endpoints")
	check(course.collect_along(before, after) == 0, "Swept pickup cannot collect one coin twice")
	course.free()

func _test_late_restore() -> void:
	var first = CourseScript.new()
	var restored = CourseScript.new()
	root.add_child(first)
	root.add_child(restored)
	first.setup(68887123, "ice")
	first.ensure_ahead(3200000.0, 39.9)
	first.begin_safe_section(3220000.0, 3260000.0)
	restored.restore(JSON.parse_string(JSON.stringify(first.snapshot(), "", false, true)))
	first.ensure_ahead(3400000.0, 61.0)
	restored.ensure_ahead(3400000.0, 61.0)
	check(_canonical(first.snapshot()) == _canonical(restored.snapshot()), "Very late JSON restore preserves exact future gates and RNG")
	check(restored.validate_witness(39.9), "Very late restored gates remain swept-feasible")
	first.free()
	restored.free()

func _wall_x(side: int) -> float:
	return CourseScript.LEFT_X if side == 0 else CourseScript.RIGHT_X

func _canonical(value: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", false, true)), "", false, true)
