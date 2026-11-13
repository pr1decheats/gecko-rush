extends SceneTree
## Run: godot --headless --path . --script tests/test_v24_tuning.gd
## Day pace grows forever; night restores a deliberately slow fixed world pace.

const Tuning = preload("res://scripts/tuning.gd")
const WORLDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
const METRES := [0.0, 250.0, 1000.0, 4000.0, 12000.0, 50000.0, 1000000.0]
const PHASES := [0.0, 35.999, 36.0, 38.0, 39.999, 40.0, 45.0, 59.999, 60.0, 60.001, 62.0, 64.0, 100.0, 120.0]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func near(actual: float, expected: float, relative: float = 0.00000001) -> bool:
	return absf(actual - expected) <= maxf(0.0000001, absf(expected) * relative)

func _run() -> void:
	var audio: Node = root.get_node_or_null("Audio")
	if audio != null:
		audio.call("set_music_enabled", false)
	_test_curve_targets()
	_test_order_and_growth()
	_test_night_and_bounds()
	_test_joins()
	_test_night_trajectory()
	_test_public_api()
	print("V24 TUNING: %d checks, %d failures" % [checks, failures])
	await process_frame
	quit(1 if failures else 0)

func _test_curve_targets() -> void:
	check(Tuning.speed_at(0.0, "jungle") == 800.0, "Easy begins at the faster 800 px/s baseline")
	check(Tuning.speed_at(0.0, "ice") == 1000.0, "Hard begins at 1000 px/s")
	check(near(Tuning.speed_at(1000.0 * 64.0, "ice"), 2200.0), "Hard has a noticeable 1 km acceleration target")
	check(near(Tuning.speed_at(4000.0 * 64.0, "ice"), 6040.0), "Hard reaches approximately 6000 px/s at 4 km")
	check(near(Tuning.speed_at(12000.0 * 64.0, "ice"), 18040.0), "Hard continues to approximately 18000 px/s at 12 km")
	check(near(Tuning.speed_at(50000.0 * 64.0, "ice"), 110000.0), "Hard does not plateau after a long run")
	check(Tuning.speed_at(1000000.0 * 64.0, "ice") > 20000000.0, "The curve keeps growing at mathematical late heights")

func _test_order_and_growth() -> void:
	for metres: float in METRES:
		var previous := 0.0
		for world: String in WORLDS:
			var height := metres * Tuning.PIXELS_PER_METRE
			var speed: float = Tuning.speed_at(height, world)
			check(is_finite(speed) and speed > previous, "World pace remains ordered at %dm: %s" % [int(metres), world])
			check(Tuning.speed_at(height + Tuning.PIXELS_PER_METRE, world) > speed, "Every extra metre still accelerates: %s at %dm" % [world, int(metres)])
			previous = speed
	for world: String in WORLDS:
		var previous := 0.0
		for index in range(401):
			var metres := float(index) * 125.0
			var current: float = Tuning.speed_at(metres * 64.0, world)
			check(current > previous, "Continuous long-distance acceleration: %s at %dm" % [world, int(metres)])
			previous = current
		var early_gain: float = Tuning.speed_at(2000.0 * 64.0, world) - Tuning.speed_at(1000.0 * 64.0, world)
		var late_gain: float = Tuning.speed_at(13000.0 * 64.0, world) - Tuning.speed_at(12000.0 * 64.0, world)
		check(late_gain > early_gain, "Acceleration continues building after 12 km: " + world)

func _test_night_and_bounds() -> void:
	for world: String in WORLDS:
		for metres: float in METRES:
			var height := metres * 64.0
			var day: float = Tuning.speed_at(height, world)
			check(near(Tuning.min_speed_at(height, world), float(Tuning.profile_for(world)["night_speed"])), "Local minimum is the selected slow night pace: " + world)
			check(Tuning.max_speed_at(height, world) == day, "Local maximum is the current altitude day pace: " + world)
			for phase: float in PHASES:
				var current: float = Tuning.run_speed_at(height, phase, world)
				check(current >= Tuning.min_speed_at(height, world) - 0.000001 and current <= day + 0.000001, "Phase stays within selected-world local bounds: " + world)
			for phase: float in [40.0, 45.0, 59.999, 100.0, 119.999]:
				check(near(Tuning.run_speed_at(height, phase, world), float(Tuning.profile_for(world)["night_speed"])), "Full night keeps the selected slow pace at every height: " + world)
		check(Tuning.run_speed_at(12000.0 * 64.0, 45.0, world) == Tuning.run_speed_at(4000.0 * 64.0, 45.0, world), "Night remains visibly slow after 12 km: " + world)

func _test_joins() -> void:
	for world: String in WORLDS:
		for metres: float in [0.0, 4000.0, 50000.0, 1000000.0]:
			var height := metres * 64.0
			var day: float = Tuning.speed_at(height, world)
			for boundary: float in [36.0, 40.0, 60.0, 64.0, 96.0, 100.0, 120.0, 124.0]:
				var before: float = Tuning.run_speed_at(height, boundary - 0.0001, world)
				var after: float = Tuning.run_speed_at(height, boundary + 0.0001, world)
				check(absf(after - before) < day * 0.0000001, "Day/night joins remain continuous at t=%f: %s" % [boundary, world])
			check(near(Tuning.run_speed_at(height, 0.0, world), day), "Opening day uses full altitude pace: " + world)
			check(near(Tuning.run_speed_at(height, 64.0, world), day), "Dawn restores the altitude curve: " + world)

func _test_night_trajectory() -> void:
	for world: String in WORLDS:
		var height := 4000.0 * 64.0
		var clock := 44.0
		var opening: float = Tuning.run_speed_at(height, clock, world)
		var previous := opening
		for step in range(360):
			clock += 1.0 / 120.0
			var current: float = Tuning.run_speed_at(height, clock, world)
			check(near(current, opening), "Real 120 Hz night travel retains its slow pace: " + world)
			height += current / 120.0
			previous = current
		check(near(height, 4000.0 * 64.0 + opening * 3.0), "Real night travel advances by its fixed pace for three seconds: " + world)
		check(near(previous, opening), "Real night movement avoids height-driven acceleration until dawn: " + world)

func _test_public_api() -> void:
	var mutable: Dictionary = Tuning.profile_for("jungle")
	mutable["start_speed"] = -100.0
	mutable["growth_per_km"] = 0.0
	check(Tuning.profile_for("jungle")["start_speed"] == 800.0, "Public profile copy cannot mutate live physics")
	check(Tuning.speed_at(-1234.0, "ice") == 1000.0, "Negative height clamps to the starting altitude")
	check(Tuning.speed_at(1234.0) == Tuning.speed_at(1234.0, "jungle"), "Default speed world remains Easy")
	check(Tuning.run_speed_at(1234.0, 45.0) == Tuning.run_speed_at(1234.0, 45.0, "jungle"), "Default phase speed world remains Easy")
	check(Tuning.speed_at(1234.0, "missing") == Tuning.speed_at(1234.0, "jungle"), "Invalid world falls back safely")
	for world: String in WORLDS:
		var profile: Dictionary = Tuning.profile_for(world)
		check(not profile.has("max_speed") and not profile.has("cap_metres") and profile.has("night_speed"), "Runtime profiles expose endless day growth and the deliberate night respite: " + world)
		check(float(profile["growth_per_km"]) > 0.0 and float(profile["endless_quadratic"]) > 0.0, "Every profile has positive endless growth: " + world)
