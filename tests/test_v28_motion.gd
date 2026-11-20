extends SceneTree
## Exercise production main.tscn at independent simulation/render rates.
## Native run also captures an ordinary generated course, with real collisions.
## DISPLAY=:99 godot --path . --script tests/test_v28_motion.gd -- /absolute/output
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node
var progress: Node
var output := ""
var metrics: Array = []
var launched: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _fixture(metres: float = 0.0, seconds: float = 4.0, world_id: String = "jungle", protected: bool = true) -> void:
	game._start_run(true)
	game._process(1.4)
	game.set_process(false)
	game.set_physics_process(false)
	game._set_run_visuals_frozen(true)
	game.world_id = world_id
	game.environment.set_world(world_id)
	game.environment.menu_blend = 0.0
	game.height_px = maxf(120.0, metres * RushTuning.PIXELS_PER_METRE)
	game.max_height_px = game.height_px
	game.run_time = seconds
	game.side = -1
	game.from_side = -1
	game.target_side = 1
	game.jump_elapsed = -1.0
	game.gecko.side = -1
	game.gecko.mode = "run"
	game.gecko.position = game.player_position()
	game._reset_center_event()
	game.next_center_metres = 1.0e12
	game.center_first_given = true
	game.course.setup(928114, world_id)
	if protected:
		game.course.begin_safe_section(game.height_px - 2000.0, game.height_px + 100000.0)
	game.course.ensure_ahead(game.height_px, game.run_time)
	game.camera_height = maxf(game.height_px - 130.0, 0.0)
	game._reset_motion_interpolation()
	game._update_camera(0.0)
	game.ui.show_hud()
	game.ui.set_hint_visible(false)

func _run() -> void:
	await process_frame
	progress = root.get_node("Progress")
	progress.save_file = "user://v28_motion_test.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.settings_changed()
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	for setting: Array in [[0.0, 4.0, "jungle"], [4000.0, 4.0, "ice"], [12000.0, 4.0, "sky"], [4000.0, 35.5, "ice"], [4000.0, 59.5, "ice"]]:
		var baseline: Dictionary = {}
		for fps: int in [30, 60, 120, 240]:
			var result := _trajectory(fps, float(setting[0]), float(setting[1]), str(setting[2]))
			if baseline.is_empty():
				baseline = result
			else:
				check(absf(float(result.height) - float(baseline.height)) < 0.000001 and absf(float(result.time) - float(baseline.time)) < 0.000001 and result.jumps == baseline.jumps, "Render FPS never changes authoritative flight, speed or rewards: %s" % fps)
	_test_turn()
	_test_pause_and_restore()
	_test_center_transfer()
	_test_collision()
	if DisplayServer.get_name() != "headless":
		var args := OS.get_cmdline_user_args()
		output = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../qa-v28-motion")
		DirAccess.make_dir_recursive_absolute(output)
		await _native_rates()
		await _capture_actual_course()
		var report := FileAccess.open(output.path_join("motion-metrics.json"), FileAccess.WRITE)
		report.store_string(JSON.stringify(metrics, "\t"))
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_file + suffix))
	print("V28 MOTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _trajectory(fps: int, metres: float, seconds: float, world_id: String) -> Dictionary:
	_fixture(metres, seconds, world_id)
	var ticks := 0
	var previous := game.gecko.position as Vector2
	var previous_screen := game.gecko.global_position as Vector2
	var previous_delta := Vector2.ZERO
	var frames_advanced := 0
	var max_world_step := 0.0
	var max_screen_acceleration := 0.0
	for frame in range(1, fps * 2 + 1):
		var frame_time := float(frame) / float(fps)
		var complete_ticks := floori(frame_time / STEP + 0.00001)
		while ticks < complete_ticks:
			if ticks == 36:
				check(game.jump(), "Real main jump starts at each sampled FPS")
			game._physics_process(STEP)
			ticks += 1
		var authority := game.player_position() as Vector2
		var saved_height: float = game.height_px
		var saved_time: float = game.run_time
		var fraction := clampf((frame_time - float(ticks) * STEP) / STEP, 0.0, 1.0)
		game._render_motion(fraction)
		game._update_camera(1.0 / float(fps))
		game.gecko._process(1.0 / float(fps))
		var at := game.gecko.position as Vector2
		var screen := game.gecko.global_position as Vector2
		var movement := at.distance_to(previous)
		if frame > 2 and movement > 0.0001:
			frames_advanced += 1
		max_world_step = maxf(max_world_step, movement)
		var screen_delta := screen - previous_screen
		if frame > 3:
			max_screen_acceleration = maxf(max_screen_acceleration, screen_delta.distance_to(previous_delta))
		check(at.is_finite() and screen.is_finite(), "Rendered production trajectory stays finite")
		check(game.player_position() == authority and game.height_px == saved_height and game.run_time == saved_time, "Rendering cannot move collision/save coordinates")
		var a: Vector2 = game._motion_previous.position
		var b: Vector2 = game._motion_current.position
		check(at.x >= minf(a.x, b.x) - 0.02 and at.x <= maxf(a.x, b.x) + 0.02 and at.y >= minf(a.y, b.y) - 0.1 and at.y <= maxf(a.y, b.y) + 0.1, "Interpolation cannot overshoot a completed physical span")
		previous = at
		previous_screen = screen
		previous_delta = screen_delta
	check(game.state == game.State.RUNNING and game.run_jumps == 1 and game.side == 1, "Real flight lands once on the opposite wall")
	check(frames_advanced == fps * 2 - 2, "Every visible running frame advances, including 240 Hz between 120 Hz ticks")
	check(max_screen_acceleration < 6000.0 / float(fps), "No camera/body sawtooth during jump or day/night transition")
	metrics.append({"fps": fps, "metres": metres, "time": seconds, "world": world_id, "advanced": frames_advanced, "frames": fps * 2 - 2, "max_world_step": max_world_step, "max_screen_acceleration": max_screen_acceleration})
	return {"height": game.height_px, "time": game.run_time, "jumps": game.run_jumps}

func _test_turn() -> void:
	_fixture()
	for wall: int in [-1, 1]:
		game.gecko.side = wall
		game.gecko.mode = "jump"
		var previous := Vector2.ZERO
		for frame in range(241):
			var p := float(frame) / 240.0
			game.gecko.jump_progress = p
			game.gecko.clear_render_motion()
			var mouth := game.gecko.get_mouth_position() as Vector2
			if frame > 0:
				check(mouth.distance_to(previous) < 2.0, "Head turns continuously through the old 72% mirror boundary")
			previous = mouth
		var near_start := game.gecko._jump_projection(0.0, wall) as Vector2
		var near_end := game.gecko._jump_projection(1.0, wall) as Vector2
		check(absf(near_start.x + wall) < 0.0001 and absf(near_end.x - wall) < 0.0001, "Turn connects both exact wall profiles")

func _test_pause_and_restore() -> void:
	_fixture(4000.0, 10.0, "ice")
	game.jump()
	for i in range(13):
		game._physics_process(STEP)
	game._render_motion(0.5)
	var frozen := game.gecko.position as Vector2
	var frozen_time: float = game.run_time
	game._pause_run()
	game._continue_run()
	for i in range(3):
		game._process(1.0)
		check(game.gecko.position == frozen and game.run_time == frozen_time, "3, 2, 1 holds exactly the displayed in-flight frame")
	game._render_motion(0.9)
	check(game.gecko.position == frozen, "Countdown ending before a physical tick cannot rewind the display")
	game._physics_process(STEP)
	game._render_motion(0.0)
	check(game.gecko.position.distance_to(frozen) < 0.01, "First resumed span starts at the exact frozen display")
	game._render_motion(0.5)
	check(game.gecko.position.distance_to(frozen) > 0.1, "Animation then resumes along the original flight")
	game._pause_run()
	game._restore_run()
	check(game.gecko.position.distance_to(game.player_position()) < 0.01 and game._motion_previous == game._motion_current, "Checkpoint load starts one fresh interpolation span")

func _test_center_transfer() -> void:
	_fixture(1500.0, 10.0)
	game.center_event = "enter"
	game.center_elapsed = 0.0
	game.center_origin_side = -1
	game.center_entry_x = game.LEFT_X
	game.center_lane_x = game.CENTER_WALL_LEFT - 26.0
	game.center_will_appear = true
	game.gecko.mode = "jump"
	game.gecko.jump_progress = 0.0
	game._reset_motion_interpolation()
	var previous := game.gecko.position as Vector2
	for frame in range(240 * 7):
		if frame % 2 == 0:
			game._physics_process(STEP)
		game._render_motion(0.5 if frame % 2 else 0.0)
		var at := game.gecko.position as Vector2
		check(at.distance_to(previous) < 20.0, "Center entry, five-second crawl and exit stay continuous at 240 Hz")
		previous = at
	check(game.center_event == "off" and game.side == -1, "Center transfer returns to the original wall without changing rules")

func _test_collision() -> void:
	_fixture()
	var at := game.player_position() as Vector2
	# Deliberately move the drawn actor far away. Physics must still hit the
	# real wall hazard at the authoritative player coordinate.
	game.course.route_side = 1
	var hazard: Dictionary = game.course._wall_spikes(game.height_px + 5.0, 0.0, 40.0)
	game.course._cache_geometry(hazard)
	game.course.hazards = [hazard]
	game.course.safe_sections.clear()
	game.gecko.position = at + Vector2(100000.0, 100000.0)
	game._physics_process(STEP)
	check(game.state == game.State.DYING, "Collision uses authoritative simulation, never an interpolated/drawn Node2D")

func _draw_native_frame(delta: float, alpha: float) -> void:
	# The simulation is manual only to control the exact sampling rate.
	# Advance every production visual component as ordinary main play does.
	game._render_motion(alpha)
	game._update_camera(delta)
	var night := RushTuning.night_amount(float(game._motion_rendered.time))
	game.environment.night_amount = night
	game.course.night_amount = night
	game.gecko.night_amount = night
	game._update_center_visual(night)
	game.ui.update_hud(game.max_height_px / RushTuning.PIXELS_PER_METRE, game.run_coins)
	game.ui.update_cycle(RushTuning.is_night(game.run_time), RushTuning.cycle_remaining(game.run_time))
	game.gecko._process(delta)
	game.environment._process(delta)
	game.effects.enabled = true
	game.effects._process(delta)
	game.effects.enabled = false
	game.center_wall.animation_enabled = true
	game.center_wall._process(delta)
	game.center_wall.animation_enabled = false

func _native_rates() -> void:
	root.size = Vector2i(540, 960)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for fps: int in [60, 120, 240]:
		Engine.max_fps = fps
		var benchmark_start := Time.get_ticks_usec()
		_fixture(4000.0, 8.0, "ice")
		var ticks := 0
		var previous := game.gecko.position as Vector2
		var advanced := 0
		var images := {}
		for frame in range(1, fps + 1):
			var frame_time := float(frame) / float(fps)
			var target_ticks := floori(frame_time / STEP + 0.00001)
			while ticks < target_ticks:
				if ticks == 20:
					game.jump()
				game._physics_process(STEP)
				ticks += 1
			_draw_native_frame(1.0 / float(fps), clampf((frame_time - ticks * STEP) / STEP, 0.0, 1.0))
			if frame > 2 and game.gecko.position.distance_to(previous) > 0.0001:
				advanced += 1
			previous = game.gecko.position
			await RenderingServer.frame_post_draw
			if frame in [fps / 4, fps / 2, fps * 3 / 4]:
				var image := root.get_texture().get_image()
				check(not image.is_empty(), "Actual main scene renders through GL at %s Hz sample" % fps)
				images[frame] = hash(image.get_data())
				image.save_png(output.path_join("main-%s-%s.png" % [fps, frame]))
		check(advanced == fps - 2, "Native 240 Hz frames do not duplicate every other 120 Hz transform")
		check(images.values()[0] != images.values()[1] and images.values()[1] != images.values()[2], "Native full-scene frames contain visibly changing gameplay")
		metrics.append({"native_fps_setting": fps, "advanced": advanced, "expected": fps - 2, "elapsed_seconds": float(Time.get_ticks_usec() - benchmark_start) / 1000000.0})

func _capture_actual_course() -> void:
	Engine.max_fps = 60
	_fixture(0.0, 4.0, "jungle", false)
	var folder := output.path_join("actual-course")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames := 0
	launched.clear()
	for frame in range(480):
		for tick in range(2):
			_follow_route()
			game._physics_process(STEP)
		_draw_native_frame(1.0 / 60.0, 0.5)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(folder.path_join("frame-%04d.png" % frames))
		frames += 1
		if game.state != game.State.RUNNING:
			break
	check(game.state == game.State.RUNNING and game.run_jumps >= 2, "Native real generated course survives through multiple real jumps")
	metrics.append({"actual_course_frames": frames, "real_jumps": game.run_jumps, "metres": game.max_height_px / RushTuning.PIXELS_PER_METRE})

func _follow_route() -> void:
	if game.jump_elapsed >= 0.0 or game.center_event in ["enter", "ride", "exit"]:
		return
	for item: Dictionary in game.course.get_witness():
		var key := str(item.cell_start)
		if launched.has(key):
			continue
		if game.height_px >= float(item.height_px) and game.height_px < float(item.cell_end):
			var wanted_side := -1 if int(item.to_side) == 0 else 1
			if game.side != wanted_side:
				if game.jump():
					launched[key] = true
			else:
				launched[key] = true
