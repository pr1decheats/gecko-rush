extends SceneTree
## Fixed slow nights and the guaranteed, deferrable 1500m central wall.
## Run: godot --headless --path . --script tests/test_v25_night_center.gd
const WORLDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
const NIGHT_SPEEDS := [680.0, 760.0, 840.0, 920.0, 1000.0, 1080.0]
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node
var p: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _prepare(world_id: String = "ice", metres: float = 1500.0, seconds: float = 10.0) -> void:
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.data.unlocked_worlds = WORLDS.duplicate()
	p.data.selected_world = world_id
	game._start_run(true)
	game._process(game.transition_duration)
	game.height_px = metres * RushTuning.PIXELS_PER_METRE
	game.max_height_px = game.height_px
	game.run_time = seconds
	game.course.ensure_ahead(game.max_height_px, seconds)
	game.gecko.position = game.player_position()

func _restore_from_disk() -> void:
	p.load_game()
	game._show_menu()
	game._restore_run()

func _drop_new_fields(saved: Dictionary) -> void:
	for key: String in ["pending_metres", "first_given", "active_metres"]:
		saved.center.erase(key)

func _run() -> void:
	p = root.get_node("Progress")
	p.save_file = "user://v25_night_center_regression.json"
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.settings_changed()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	_test_slow_nights()
	_test_guaranteed_first()
	_test_deferred_windows()
	_test_pending_roundtrip()
	_test_schema6_migration()
	_test_cancelled_first()
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.save_file + suffix))
	print("V25 NIGHT/CENTER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_slow_nights() -> void:
	for index in range(WORLDS.size()):
		var id: String = WORLDS[index]
		var slow: float = NIGHT_SPEEDS[index]
		check(float(RushTuning.profile_for(id)["night_speed"]) == slow, "World exposes its deliberate night pace: " + id)
		for metres: float in [0.0, 1500.0, 4000.0, 12000.0, 50000.0, 1000000.0]:
			var height := metres * RushTuning.PIXELS_PER_METRE
			check(RushTuning.min_speed_at(height, id) == slow, "Certificate uses the actual slow minimum at every height: " + id)
			for second: float in [40.0, 45.0, 59.999, 100.0, 119.999]:
				check(is_equal_approx(RushTuning.run_speed_at(height, second, id), slow), "Twenty-second full night is slow and independent of height: %s at %.0fm" % [id, metres])
			check(RushTuning.speed_at(height + 64.0, id) > RushTuning.speed_at(height, id), "Day acceleration remains unbounded through the night fix: " + id)
			if metres >= 1500.0:
				check(slow < RushTuning.speed_at(height, id) * 0.4, "Night slowdown is visibly large after the first milestone: " + id)
		_prepare(id, 12000.0, 39.0)
		var dusk: Array[float] = []
		for second: float in [36.0, 37.0, 38.0, 39.0, 40.0]:
			dusk.append(RushTuning.run_speed_at(game.height_px, second, id))
		for step in range(1, dusk.size()):
			check(dusk[step] < dusk[step - 1], "Dusk slows continuously toward the respite: " + id)
		var night_start: float = game.height_px
		game.run_time = 40.0
		# This safe fixture isolates exact distance, not obstacle avoidance.
		game.center_first_given = true
		game.next_center_metres = 1.0e12
		game.course.begin_safe_section(game.height_px - 100.0, game.height_px + slow * 21.0)
		for step in range(2400):
			game._simulate_step(STEP)
		check(game.state == game.State.RUNNING and absf(game.height_px - night_start - slow * 20.0) < 0.001, "Actual main physics advances exactly twenty seconds at the slow pace: " + id)
		var previous := slow
		for second: float in [60.0, 61.0, 62.0, 63.0, 64.0]:
			var current := RushTuning.run_speed_at(game.height_px, second, id)
			check(current >= previous, "Dawn gradually restores height-driven speed: " + id)
			previous = current
		check(previous == RushTuning.speed_at(game.height_px, id), "Dawn returns to the unlimited day curve: " + id)

func _test_guaranteed_first() -> void:
	for id: String in WORLDS:
		for seed_value in range(8):
			_prepare(id)
			game.run_seed = seed_value * 7919 + 41
			game._tick_center_event(STEP)
			check(game.center_event == "preview" and game.center_will_appear and game.center_first_given, "First 1500m daytime milestone always accepts: %s seed=%d" % [id, seed_value])
			check(game.center_active_metres == 1500.0 and game.center_pending_metres == 0.0 and game.next_center_metres == 3000.0, "Guaranteed first preview consumes exactly its pending event: " + id)
			check(not game.course.safe_sections.is_empty(), "Guaranteed preview clears actual hazards before transfer: " + id)
		# Verify the accepted warning becomes the actual safe wall, not only a flag.
		for step in range(910):
			game._simulate_step(STEP)
		check(game.state == game.State.RUNNING and game.center_event == "off" and game.center_first_given, "Actual first central ride and return complete in daylight: " + id)
		check(game.side == -1 and game.player_position().x == game.LEFT_X, "First central respite returns to its original outer wall: " + id)

func _test_deferred_windows() -> void:
	for seconds: float in [30.0, 35.0, 36.0, 39.9, 40.0, 50.0, 59.9, 60.0, 62.0, 63.9]:
		_prepare("ice", 4000.0, seconds)
		game._tick_center_event(STEP)
		game._update_center_visual(RushTuning.night_amount(game.run_time))
		check(game.center_event == "off" and not game.center_will_appear and game.center_wall.phase == "off", "Ineligible time shows neither wall nor ghost: t=%.1f" % seconds)
		check(game.center_pending_metres == 1500.0 and not game.center_first_given and game.center_next_allowed_time == 0.0, "Night/late day/dawn preserves the original first milestone: t=%.1f" % seconds)
		check(game.course.safe_sections.is_empty(), "Deferred event grants no hidden invulnerability: t=%.1f" % seconds)
		game.max_height_px = 12000.0 * RushTuning.PIXELS_PER_METRE
		game.height_px = game.max_height_px
		game.run_time = 64.0
		game._tick_center_event(STEP)
		check(game.center_event == "preview" and game.center_will_appear and game.center_active_metres == 1500.0 and game.center_first_given, "First eligible full daylight delivers the deferred first wall despite crossed milestones: t=%.1f" % seconds)
		check(game.next_center_metres > 12000.0 and game.center_pending_metres == 0.0, "Crossed later milestones coalesce instead of chaining first respites")

func _test_pending_roundtrip() -> void:
	_prepare("ice", 4000.0, 50.0)
	game._tick_center_event(STEP)
	game._pause_run()
	var saved: Dictionary = p.load_resume()
	check(saved.schema == 6 and saved.center.pending_metres == 1500.0 and not saved.center.first_given and saved.center.active_metres == 0.0, "Schema6 additively persists the deferred first event")
	_restore_from_disk()
	check(game.state == game.State.PAUSED and game.run_time == 50.0 and game.center_pending_metres == 1500.0 and not game.center_first_given and game.center_event == "off", "Pause and disk restore preserve pending night milestone without a ghost")
	game._continue_run()
	game.run_time = 64.0
	game._tick_center_event(STEP)
	check(game.center_event == "preview" and game.center_will_appear and game.center_active_metres == 1500.0, "Resumed pending event starts at the first full daylight window")
	game.center_elapsed = 0.7
	game._pause_run()
	_restore_from_disk()
	check(game.state == game.State.PAUSED and game.center_event == "preview" and game.center_elapsed == 0.7 and game.center_first_given and game.center_active_metres == 1500.0 and game.center_pending_metres == 0.0, "Accepted first warning restores its exact stage without duplicating its pending event")

func _test_schema6_migration() -> void:
	for phase: String in ["off", "miss"]:
		_prepare("ice", 4000.0, 50.0)
		game.center_event = phase
		game.center_will_appear = false
		game.next_center_metres = 4500.0
		game.center_next_allowed_time = 110.0
		game._pause_run()
		var saved: Dictionary = p.load_resume()
		_drop_new_fields(saved)
		p.save_resume(saved)
		_restore_from_disk()
		check(game.state == game.State.PAUSED and game.center_event == "off" and game.center_pending_metres == 1500.0 and not game.center_first_given and game.center_next_allowed_time == 0.0, "Old schema6 ambiguous night checkpoint repairs the skipped first opportunity: " + phase)
		game._continue_run()
		game.run_time = 64.0
		game._tick_center_event(STEP)
		check(game.center_will_appear and game.center_active_metres == 1500.0, "Migrated old checkpoint receives a guaranteed first daytime wall: " + phase)
	for phase: String in ["preview", "enter", "ride", "exit"]:
		_prepare("ice", 1500.0, 10.0)
		game._tick_center_event(STEP)
		game.center_event = phase
		game.center_elapsed = 0.2
		game._pause_run()
		var saved: Dictionary = p.load_resume()
		_drop_new_fields(saved)
		p.save_resume(saved)
		_restore_from_disk()
		check(game.state == game.State.PAUSED and game.center_event == phase and game.center_first_given and game.center_active_metres == 1500.0 and game.center_pending_metres == 0.0, "Old accepted schema6 transfer resumes without awarding a duplicate first event: " + phase)
	_prepare("ice", 1000.0, 50.0)
	game._pause_run()
	var before: Dictionary = p.load_resume()
	_drop_new_fields(before)
	p.save_resume(before)
	_restore_from_disk()
	check(not game.center_first_given and game.center_pending_metres == 0.0 and game.center_event == "off", "Old pre-milestone checkpoint does not manufacture an early center wall")

func _test_cancelled_first() -> void:
	for phase: String in ["preview", "enter", "ride", "exit"]:
		_prepare()
		game._tick_center_event(STEP)
		game.center_event = phase
		game.center_elapsed = 0.2
		game.run_time = 50.0
		game._tick_center_event(STEP)
		check(game.center_event == "off" and not game.center_will_appear and game.center_wall.phase == "off", "Night cancels every illegal central visual stage: " + phase)
		if phase in ["preview", "enter"]:
			check(not game.center_first_given and game.center_pending_metres == 1500.0 and game.center_next_allowed_time == 0.0, "An interrupted first warning/transfer is retried at daytime: " + phase)
		else:
			check(game.center_first_given and game.center_pending_metres == 0.0, "An already delivered ride is not duplicated after a night cancellation: " + phase)
