extends SceneTree
## Regression coverage for the Android 2.1 climb, night and respite lifecycle.
var checks := 0
var failures := 0
var game: Node
var progress: Node

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	progress = root.get_node("Progress")
	progress.save_file = "user://v21_regression.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.settings_changed()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	check(game.gecko.mode == "sleep", "menu gecko sleeps curled up")
	check(is_equal_approx(game.gecko.position.y + GeckoVisual.GROUND_FEET_Y, 73.0), "menu gecko feet meet floor")
	check(game.ui._content.find_child("RunDistanceCards", true, false) != null, "three run-distance cards exist")
	check(RushTuning.PIXELS_PER_METRE == 64.0, "metre counter advances at half the old rate")
	for height: float in [0.0, 64000.0, 256000.0]:
		for second: float in [40.0, 45.0, 50.0, 59.99, 100.0, 119.99]:
			check(is_equal_approx(RushTuning.run_speed_at(height, second), RushTuning.speed_at(height) * 0.85), "Easy night retains 85 percent of the height-dependent day pace")
	check(not RushTuning.is_night(39.99) and RushTuning.is_night(40.0) and RushTuning.is_night(59.99) and not RushTuning.is_night(60.0), "night lasts exactly twenty seconds")
	check(absf(RushTuning.run_speed_at(64000, 39.999) - 1662.0 * 0.85) < 0.01, "dusk slowdown reaches the height-dependent night pace continuously")
	var dawn_speeds: Array[float] = []
	for second: float in [60, 61, 62, 63, 64]:
		dawn_speeds.append(RushTuning.run_speed_at(64000, second))
	for index in range(1, dawn_speeds.size()):
		check(dawn_speeds[index] > dawn_speeds[index - 1], "dawn accelerates gradually")
	check(RushTuning.night_amount(60) == 1 and RushTuning.night_amount(62) > 0 and RushTuning.night_amount(62) < 1 and RushTuning.night_amount(64) == 0, "background dawn crossfades over four seconds")
	game.gecko.run_speed_factor = 4.0
	game.gecko.mode = "run"
	game.gecko._process(100.0)
	game.gecko.eat_to(Vector2(-10, -100))
	game._start_run(true)
	check(game.gecko.run_speed_factor == 1 and game.gecko._visual_speed_factor == 1, "new run resets actual and smoothed animation speeds")
	check(game.gecko._stride_phase == 0 and game.gecko._tail_phase == 0 and game.gecko._clock == 0 and not game.gecko.is_eating(), "new run resets every animation phase")
	game._process(0.3)
	check(game.gecko.mode == "wake_climb" and game.gecko.launch_progress > 0.0, "earthquake starts the wake-up sequence")
	game._process(1.1)
	check(game.state == game.State.RUNNING and game.gecko.mode == "run", "crawl launch joins normal wall movement")
	var accepted_seed := -1
	var missed_seed := -1
	var accepted := 0
	for seed_index in range(200):
		game._reset_center_event()
		game.run_seed = seed_index
		game._begin_center_event()
		if game.center_will_appear:
			accepted += 1
			accepted_seed = seed_index
		else:
			missed_seed = seed_index
	check(accepted > 65 and accepted < 135 and accepted_seed >= 0 and missed_seed >= 0, "independent event chance is approximately fifty percent")
	_prepare_event(accepted_seed)
	check(game.center_event == "preview" and game.center_will_appear and game.next_center_metres == 3000.0, "1500m milestone previews exactly one accepted event")
	check(not game.course.safe_sections.is_empty(), "accepted preview clears the approach before transfer")
	game._tick_center_event(RushTuning.CENTER_PREVIEW_SECONDS)
	check(game.center_event == "enter", "accepted ghost becomes a real wall")
	game._tick_center_event(RushTuning.CENTER_ENTER_SECONDS)
	game._process(0.0)
	check(game.center_event == "ride" and game.environment.side_walls_visibility == 0, "side walls disappear during the central climb")
	check(game.player_position().x == game.center_lane_x and not game.jump(), "respite automatically holds its safe wall lane")
	for index in range(300):
		game._simulate_step(1.0 / 120.0)
	check(game.center_event == "ride", "respite is still active after two and a half seconds")
	var before: float = game.center_elapsed
	game._pause_run()
	game._physics_process(2.0)
	check(game.center_elapsed == before, "pause freezes central wall lifetime")
	game._show_menu()
	game._restore_run()
	check(game.center_event == "ride" and absf(game.center_elapsed - before) < 0.00001, "checkpoint restores central wall lifetime")
	check(not game.course.safe_sections.is_empty(), "checkpoint restores protected course interval")
	game._continue_run()
	for index in range(181):
		game._simulate_step(1.0 / 120.0)
	game._process(0.0)
	check(game.center_event == "ride" and game.center_wall.ride_elapsed > 4.0, "cracks begin during the last second")
	for index in range(120):
		game._simulate_step(1.0 / 120.0)
	check(game.center_event == "exit" and not game.center_wall._shards.is_empty(), "five-second wall shatters into actual falling debris")
	game._tick_center_event(RushTuning.CENTER_EXIT_SECONDS)
	game._process(0.0)
	check(game.center_event == "off" and game.environment.side_walls_visibility == 1, "return restores both side walls")
	check(game.player_position().x == game.LEFT_X and game.side == -1, "return reaches the correct original side")
	_prepare_event(missed_seed)
	check(not game.center_will_appear and game.course.safe_sections.is_empty(), "failed roll preserves the ordinary course")
	game._tick_center_event(RushTuning.CENTER_PREVIEW_SECONDS)
	check(game.center_event == "miss", "failed ghost fades away")
	game._tick_center_event(0.5)
	check(game.center_event == "off" and game.center_wall._shards.is_empty(), "failed ghost never becomes a ride or debris")
	_test_course_restore()
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_file + suffix))
	print("V21: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _prepare_event(seed_index: int) -> void:
	game._start_run(true)
	game.run_seed = seed_index
	game.state = game.State.RUNNING
	game.run_time = 70.0
	game.height_px = 1500.0 * RushTuning.PIXELS_PER_METRE
	game.max_height_px = game.height_px
	game.course.setup(seed_index, "jungle")
	game.course.ensure_ahead(game.height_px, game.run_time)
	game._begin_center_event()

func _test_course_restore() -> void:
	var first := RushCourse.new()
	var second := RushCourse.new()
	root.add_child(first)
	root.add_child(second)
	first.setup(1785, "jungle")
	first.ensure_ahead(11000.0, 10.0)
	first.begin_safe_section(12000.0, 25000.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(first.snapshot(), "", false, true))
	second.restore(data)
	first.ensure_ahead(23000.0, 43.0)
	second.ensure_ahead(23000.0, 43.0)
	check(JSON.stringify(JSON.parse_string(JSON.stringify(first.snapshot(), "", false, true)), "", false, true) == JSON.stringify(JSON.parse_string(JSON.stringify(second.snapshot(), "", false, true)), "", false, true), "shuffled layouts and protected intervals survive JSON deterministically")
	for height: float in [12000, 18000, 24990]:
		for x: float in [296, 464, 540, 616, 784]:
			check(not second.collision_at(Vector2(x, -height), 43.0), "protected corridor has no lethal shapes at any lane")
	first.free()
	second.free()
