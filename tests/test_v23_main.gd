extends SceneTree
## Real-scene difficulty physics, world-attributed rewards, durable checkpoints
## and input/animation regressions. Use an isolated XDG_DATA_HOME when running.
var checks := 0
var failures := 0
var game: Node
var p: Node
const STEP := 1.0 / 120.0
const WORLDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
const STARTS := [800.0, 900.0, 1000.0, 1120.0, 1240.0, 1380.0]
const ONE_KM := [1662.0, 1916.0, 2200.0, 2494.0, 2809.0, 3175.0]
const FOUR_KM := [4392.0, 5156.0, 6040.0, 6904.0, 7864.0, 8980.0]

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _fresh() -> void:
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	# A retained legacy profile can have all difficulties open at its current XP.
	p.data.unlocked_worlds = WORLDS.duplicate()

func _launch(id: String) -> void:
	check(p.select_world(id), "retained unlock can select " + id)
	game._start_run(false)
	game._process(game.transition_duration)
	check(game.state == game.State.RUNNING, "launch reaches real running state: " + id)
	check(game.world_id == id and game.course.world_id == id and game.environment.world_id == id, "scene/course/background use the selected difficulty: " + id)

func _place_safe(metres: float, seconds: float) -> void:
	game.height_px = metres * RushTuning.PIXELS_PER_METRE
	game.max_height_px = game.height_px
	game.run_time = seconds
	game.jump_elapsed = -1.0
	game.center_event = "off"
	game.next_center_metres = 1.0e9
	game.center_first_given = true
	game.center_pending_metres = 0.0
	# Use the actual safe-section feature to isolate speed integration; the
	# certified lethal 3000m route remains covered by test_game.gd.
	game.course.begin_safe_section(game.height_px - 1000.0, game.height_px + 10000.0)
	game.course.ensure_ahead(game.max_height_px, game.run_time)
	game.gecko.position = game.player_position()

func _key(code: Key, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	return event

func _canonical(value: Variant) -> String:
	# JSON stores a single numeric type; normalise both sides before comparing
	# integer dictionary fields with their identical disk-restored float values.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", false, true)), "", false, true)

func _run() -> void:
	p = root.get_node("Progress")
	p.save_file = "user://v23_main_regression.json"
	_fresh()
	p.settings_changed()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	_test_selected_speed_profiles()
	_test_center_prediction()
	_test_result_attribution()
	_test_resume_roundtrips()
	_test_old_checkpoint_settlement()
	await _test_input_and_animation()
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.save_file + suffix))
	print("V23 MAIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_selected_speed_profiles() -> void:
	_fresh()
	for index: int in WORLDS.size():
		var id: String = WORLDS[index]
		_launch(id)
		_place_safe(0.0, 0.0)
		check(game.current_speed() == STARTS[index] and game.speed_at(0.0) == STARTS[index], "main uses selected initial pace: " + id)
		game._simulate_step(STEP)
		check(is_equal_approx(game.height_px, STARTS[index] * STEP), "actual first physics step uses selected pace: " + id)
		_place_safe(1000.0, 10.0)
		var before: float = game.height_px
		game._simulate_step(STEP)
		check(absf(game.height_px - before - ONE_KM[index] * STEP) < 0.000001, "actual 1000m physics follows the selected distance curve: " + id)
		game.max_height_px = 4000.0 * RushTuning.PIXELS_PER_METRE
		check(game.current_speed() == FOUR_KM[index] and game.current_speed() > ONE_KM[index], "selected world keeps accelerating beyond its former cap distance: " + id)
		for height: float in [0.0, 1000.0, 9000.0]:
			game.max_height_px = height * RushTuning.PIXELS_PER_METRE
			var night_speed: float = float(RushTuning.profile_for(id)["night_speed"])
			for second: float in [40.0, 45.0, 59.99, 100.0, 119.99]:
				game.run_time = second
				check(is_equal_approx(game.current_speed(), night_speed), "night retains the selected fixed slow pace: " + id)
		_place_safe(1000.0, 46.0)
		before = game.height_px
		game._simulate_step(STEP)
		check(absf(game.height_px - before - float(RushTuning.profile_for(id)["night_speed"]) * STEP) < 0.000001, "real night physics uses the selected slow pace: " + id)
		game.max_height_px = 4000.0 * RushTuning.PIXELS_PER_METRE
		var previous: float = float(RushTuning.profile_for(id)["night_speed"])
		for second: float in [60.0, 61.0, 62.0, 63.0, 64.0]:
			game.run_time = second
			var speed: float = game.current_speed()
			check(speed >= previous and speed >= float(RushTuning.profile_for(id)["night_speed"]) and speed <= FOUR_KM[index], "selected dawn stays continuous between local night and day speeds: " + id)
			if second > 60.0:
				check(speed > previous, "selected dawn accelerates on every transition sample: " + id)
			previous = speed
		check(previous == FOUR_KM[index], "dawn reaches the selected local daytime curve: " + id)

func _test_center_prediction() -> void:
	_fresh()
	var previous_end := 0.0
	for index: int in WORLDS.size():
		var id: String = WORLDS[index]
		_launch(id)
		game.height_px = 1500.0 * RushTuning.PIXELS_PER_METRE
		game.max_height_px = game.height_px
		game.run_time = 70.0
		for seed: int in range(200):
			game.run_seed = seed
			game.next_center_metres = 1500.0
			game.center_next_allowed_time = 0.0
			game.center_event = "off"
			game.course.safe_sections.clear()
			game._begin_center_event()
			if game.center_will_appear:
				break
		check(game.center_will_appear and game.course.safe_sections.size() == 1, "accepted central respite protects one course interval: " + id)
		var protected_end: float = game.course.safe_sections[0].end
		check(protected_end > previous_end, "central safety prediction follows the selected world's increasing pace: " + id)
		previous_end = protected_end
		for step: int in range(910):
			game._simulate_step(STEP)
		check(game.state == game.State.RUNNING and game.center_event == "off", "real selected-speed central transfer completes safely: " + id)
		check(protected_end > game.height_px + game.current_speed() * 0.4, "selected-world transfer retains a reaction margin after returning to the wall: " + id)

func _test_result_attribution() -> void:
	_fresh()
	_launch("ice")
	_place_safe(320.0, 12.0)
	game.run_coins = 5
	game.run_jumps = 3
	game.run_passed = 12
	check(p.select_world("sky"), "another menu selection is available before settlement")
	game._die("impact")
	check(game.last_result.world_id == "ice" and p.data.last_result.world_id == "ice", "death result belongs to the running world rather than current menu choice")
	check(p.data.world_stats.ice.runs == 1 and p.data.world_stats.ice.best_height == 320.0, "real death credits that world's run and record")
	check(p.world_run_distances("sky").best == 0.0 and p.data.selected_world == "sky", "settlement preserves independent menu choice and unplayed world statistics")
	check(game.last_result.xp == 61 and p.data.world_stats.ice.xp == 61, "result XP uses Hard's multiplier and first-jump award")
	var settled := JSON.stringify(p.data, "", false, true)
	game._die("impact")
	check(JSON.stringify(p.data, "", false, true) == settled, "duplicate death cannot change any settled counter")

	_fresh()
	_launch("crystal")
	_place_safe(650.0, 17.0)
	game.run_coins = 6
	game.run_jumps = 4
	game.run_passed = 10
	game._pause_run()
	game._show_menu()
	game._on_action("world", "sky")
	check(game.world_id == "sky" and p.data.selected_world == "sky", "menu world changes after saving a different world")
	game._cash_out_saved_run()
	check(p.data.last_result.world_id == "crystal" and p.data.world_stats.crystal.best_height == 650.0, "saved-run cashout still credits its checkpoint world")
	check(p.world_run_distances("sky").best == 0.0 and p.load_resume().is_empty(), "saved-run settlement leaves selected world records untouched and clears checkpoint")
	settled = JSON.stringify(p.data, "", false, true)
	game._cash_out_saved_run()
	check(JSON.stringify(p.data, "", false, true) == settled, "saved-run settlement is exactly once")

func _test_resume_roundtrips() -> void:
	for index: int in WORLDS.size():
		for seconds: float in [12.0, 47.0, 62.0]:
			_fresh()
			var id: String = WORLDS[index]
			_launch(id)
			_place_safe(400.125, seconds)
			game.jump_elapsed = 0.11
			game.from_side = -1
			game.target_side = 1
			game.side = -1
			game.run_jumps = 2
			game.run_coins = 4
			game.run_passed = 8
			game.gecko.position = game.player_position()
			var position_before: Vector2 = game.player_position()
			var speed_before: float = game.current_speed()
			game._pause_run()
			var saved: Dictionary = p.load_resume()
			check(int(saved.schema) == 6 and saved.world_id == id and saved.course.world == id, "schema6 stores run and course world consistently: " + id)
			p.load_game()
			game._show_menu()
			game._on_action("world", WORLDS[(index + 1) % WORLDS.size()])
			game._restore_run()
			check(game.state == game.State.PAUSED and game.world_id == id and game.course.world_id == id and game.environment.world_id == id, "disk restore chooses checkpoint world and safely pauses: " + id)
			check(absf(game.run_time - seconds) < 0.0000001 and absf(game.height_px - 400.125 * RushTuning.PIXELS_PER_METRE) < 0.0000001, "day/night/dawn clock and height survive disk roundtrip: " + id)
			check(absf(game.current_speed() - speed_before) < 0.0000001, "restored selected speed exactly matches its saved cycle phase: " + id)
			check(game.player_position().distance_to(position_before) < 0.0000001 and game.gecko.mode == "jump" and is_equal_approx(game.gecko.jump_progress, 0.11 / game.JUMP_DURATION), "in-flight body position and animation phase restore together: " + id)
			check(is_equal_approx(game.gecko.run_speed_factor, speed_before / RushTuning.START_SPEED), "restored animation receives the selected world speed: " + id)
			check(game.run_coins == 4 and game.run_passed == 8 and game.run_jumps == 2, "checkpoint retains temporary counters: " + id)
			check(_canonical(game.course.snapshot()) == _canonical(saved.course), "complete course and protected intervals roundtrip deterministically: " + id)
			game._continue_run()
			for step: int in range(32):
				game._simulate_step(STEP)
			check(game.state == game.State.RUNNING and game.side == 1 and game.jump_elapsed < 0.0 and game.run_jumps == 3, "restored flight lands once and continues in the saved world: " + id)

func _test_old_checkpoint_settlement() -> void:
	_fresh()
	p.data.selected_world = "jungle"
	p.save_resume({"schema": 4, "run_id": "v23-close-legacy4-volcano", "world_id": "volcano", "pixels_per_metre": 64.0,
		"height_px": 900.0 * 64.0, "max_height_px": 900.0 * 64.0, "coins": 7, "jumps": 9, "passed": 16, "course": {"version": 4}})
	p.load_game()
	game._show_menu()
	check(game.state == game.State.MENU and p.load_resume().is_empty(), "schema4 checkpoint is settled and closed before showing the new menu")
	check(p.data.runs == 1 and p.data.last_result.world_id == "volcano", "old checkpoint closes in its saved world exactly once")
	check(p.data.world_stats.volcano.best_height == 900.0 and p.data.world_stats.volcano.total_distance == 900.0 and p.data.world_stats.volcano.jumps == 9, "old checkpoint metres and counters are credited without conversion loss")
	check(p.data.xp == 179 and p.data.coins == 16, "old checkpoint uses its world multiplier, record/height reward and one level bonus")
	check(p.world_run_distances("jungle").best == 0.0 and p.data.selected_world == "jungle", "legacy settlement preserves current world selection and unrelated records")
	var settled := JSON.stringify(p.data, "", false, true)
	game._show_menu()
	game._cash_out_saved_run()
	check(JSON.stringify(p.data, "", false, true) == settled, "reopening menu cannot settle old checkpoint twice")
	p.load_game()
	check(p.data.runs == 1 and p.data.coins == 16 and p.data.world_stats.volcano.runs == 1 and p.load_resume().is_empty(), "once-only legacy settlement survives a disk reload")

func _test_input_and_animation() -> void:
	_fresh()
	p.select_world("sky")
	game.gecko.run_speed_factor = 3.0
	game.gecko._visual_speed_factor = 2.5
	game.gecko._clock = 90.0
	game.gecko._stride_phase = 2.0
	game.gecko._tail_phase = 3.0
	game.gecko.rotation = 0.7
	game.gecko.eat_to(Vector2(-10.0, -120.0))
	game.gecko.electrocute()
	game._start_run(true)
	check(game.gecko.mode == "sleep" and game.gecko.run_speed_factor == 1.0 and game.gecko._visual_speed_factor == 1.0, "retry resets animation speed before the sleeping launch pose")
	check(game.gecko._clock == 0.0 and game.gecko._stride_phase == 0.0 and game.gecko._tail_phase == 0.0 and game.gecko.rotation == 0.0, "retry resets all phase and death rotation state")
	check(game.gecko._ash_positions.is_empty() and game.gecko._electro_clock < 0.0 and not game.gecko.is_eating(), "retry clears electrical ash and unfinished eating")
	game._process(game.transition_duration)
	game._unhandled_input(_key(KEY_SPACE, true))
	check(game.jump_elapsed < 0.0, "keyboard repeat cannot start a jump")
	var secondary := InputEventScreenTouch.new()
	secondary.index = 1
	secondary.pressed = true
	game._unhandled_input(secondary)
	check(game.jump_elapsed < 0.0, "secondary touch cannot launch a second control stream")
	game._unhandled_input(_key(KEY_SPACE))
	check(game.jump_elapsed == 0.0, "one ordinary Space press starts one flight")
	game._simulate_step(STEP)
	var flight_before: float = game.jump_elapsed
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	game._unhandled_input(mouse)
	check(game.jump_elapsed == flight_before and game.run_jumps == 0, "mouse/touch duplication during flight never resets or counts a jump")
	game._unhandled_input(_key(KEY_P))
	var saved_height: float = game.height_px
	var saved_time: float = game.run_time
	var saved_flight: float = game.jump_elapsed
	game._physics_process(0.5)
	game._process(0.5)
	var animation_clock: float = game.gecko._clock
	game._unhandled_input(_key(KEY_SPACE))
	game._unhandled_input(mouse)
	await process_frame
	check(game.state == game.State.PAUSED and game.height_px == saved_height and game.run_time == saved_time and game.jump_elapsed == saved_flight, "pause freezes physics/cycle/flight and ignores jump controls")
	check(not game.gecko.is_processing() and not game.environment.is_processing() and game.gecko._clock == animation_clock and not game.effects.enabled, "pause also freezes body animation, scenery and effects")
	check(p.load_resume().world_id == "sky", "pause checkpoints the actual selected difficulty")
	game._unhandled_input(_key(KEY_P))
	check(game.state == game.State.RUNNING and game.jump_elapsed == saved_flight, "P resumes the same flight without another jump")
	for step: int in range(32):
		game._simulate_step(STEP)
	check(game.side == 1 and game.run_jumps == 1, "single resumed input flight lands and counts exactly once")
	game._start_run(true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.state == game.State.PAUSED and game.height_px == 120.0 and p.load_resume().world_id == "sky", "backgrounding during launch creates a safe resumable checkpoint in the selected world")
