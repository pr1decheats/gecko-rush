extends SceneTree
## Drive the real main scene and protect the player's complete paused snapshot.
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

func _snapshot() -> Dictionary:
	return {
		"height": game.height_px, "max": game.max_height_px, "time": game.run_time,
		"jump": game.jump_elapsed, "side": game.side, "from": game.from_side,
		"target": game.target_side, "coins": game.run_coins, "jumps": game.run_jumps,
		"passed": game.run_passed, "center": game.center_event,
		"center_elapsed": game.center_elapsed, "camera": game.camera_height,
		"course": JSON.stringify(game.course.snapshot(), "", false, true),
		"player": game.gecko.position, "xp": progress.data.xp,
		"bank": progress.data.coins
	}

func _fresh() -> void:
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._start_run(true)
	game._process(1.4)
	check(game.state == game.State.RUNNING, "Fixture completes the ordinary floor-to-wall launch")
	game.set_process(false)
	game.set_physics_process(false)

func _pause_at_launch() -> Dictionary:
	_fresh()
	game._pause_run()
	check(game.state == game.State.PAUSED, "Run enters the existing pause screen")
	return _snapshot()

func _run() -> void:
	await process_frame
	progress = root.get_node("Progress")
	progress.save_file = "user://v26_resume_countdown_test.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.settings_changed()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var frozen := _pause_at_launch()
	game._on_action("continue")
	check(game.state == game.State.RESUMING, "Continue begins a countdown rather than moving immediately")
	check(game._resume_layer.visible and game._resume_label.text == "3", "Visible countdown starts at three")
	check(not game.gecko.is_processing() and not game.environment.is_processing() and not game.effects.enabled and not game.center_wall.animation_enabled, "Run animations also stay frozen during the countdown")
	check(not game.jump(), "Direct jump input cannot begin a flight during countdown")
	for keycode: int in [KEY_SPACE, KEY_ENTER]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		game._unhandled_input(key)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	game._unhandled_input(mouse)
	game._physics_process(0.2)
	game._simulate_step(0.2)
	check(_snapshot() == frozen, "Physics, direct simulation and all jump controls cannot advance or reward the frozen run")
	game._process(0.999)
	check(game._resume_label.text == "3" and game.state == game.State.RESUMING, "Three remains visible for the first whole second")
	game._process(0.001)
	check(game._resume_label.text == "2" and game.state == game.State.RESUMING, "Second second displays two")
	game._process(1.0)
	check(game._resume_label.text == "1" and game.state == game.State.RESUMING, "Third second displays one")
	game._process(0.999)
	game._physics_process(0.2)
	check(game.state == game.State.RESUMING and _snapshot() == frozen, "No world, timer, camera, center wall, XP or collection changes before three seconds")
	game._process(0.001)
	check(game.state == game.State.RUNNING and not game._resume_layer.visible, "Only the completed countdown releases the run")
	check(game.gecko.is_processing() and game.environment.is_processing() and game.effects.enabled and game.center_wall.animation_enabled, "Run animation is released together with physics")
	check(_snapshot() == frozen, "Finishing the overlay itself never spends a simulation tick")
	game._physics_process(1.0 / 120.0)
	check(game.height_px > float(frozen.height) and game.run_time > float(frozen.time), "The next real physics tick resumes ordinary climbing")
	_test_interruptions()
	_test_flight_checkpoint()
	_test_center_wall()
	await _test_layout_and_native_captures()
	game.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_file + suffix))
	print("V26 RESUME COUNTDOWN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_interruptions() -> void:
	for notice: int in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		var frozen := _pause_at_launch()
		game._continue_run()
		game._process(0.7)
		game._notification(notice)
		check(game.state == game.State.PAUSED and not game._resume_layer.visible, "Backgrounding cancels the overlay and returns to a safe pause")
		game._process(20.0)
		game._physics_process(0.2)
		game._continue_run()
		check(game.state == game.State.PAUSED and _snapshot() == frozen, "An inactive application cannot restart through a hidden countdown")
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		game._continue_run()
		check(game.state == game.State.RESUMING and game._resume_label.text == "3" and game.resume_elapsed == 0.0, "Returning starts a fresh full countdown after Continue")
		game._process(2.5)
		check(game.state == game.State.RESUMING, "An interrupted countdown does not carry old elapsed time")
		game._process(0.5)
		check(game.state == game.State.RUNNING and _snapshot() == frozen, "Foreground countdown resumes the same untouched position")
	_pause_at_launch()
	game._continue_run()
	game._process(1.2)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_input(escape)
	check(game.state == game.State.PAUSED and not game._resume_layer.visible, "Escape during countdown safely pauses instead of skipping to motion")
	game._continue_run()
	game._process(0.6)
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.state == game.State.PAUSED, "Android back request also safely cancels countdown")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.state == game.State.RESUMING and game._resume_label.text == "3", "Back from pause uses the same guarded countdown")
	game._on_action("menu")
	check(game.state == game.State.MENU and not game._resume_layer.visible, "Returning to menu never leaves a countdown covering its controls")

func _test_flight_checkpoint() -> void:
	_fresh()
	check(game.jump(), "Mid-flight checkpoint fixture begins a real jump")
	game._physics_process(0.08)
	game._pause_run()
	var frozen := _snapshot()
	var flight: float = game.jump_elapsed
	game._continue_run()
	game._process(1.3)
	game._store_resume()
	var saved: Dictionary = progress.load_resume()
	check(int(saved.schema) == game.RESUME_SCHEMA and saved.jump_elapsed == flight, "Closing during countdown stores the ordinary existing-schema flight checkpoint")
	check(saved.time == frozen.time and saved.height_px == frozen.height, "Stored checkpoint excludes countdown seconds and motion")
	game._show_menu()
	game._restore_run()
	check(game.state == game.State.PAUSED and not game._resume_layer.visible and game.jump_elapsed == flight, "Restored run remains safely paused at the original flight fraction")
	game._continue_run()
	game._process(2.99)
	game._physics_process(0.2)
	check(game.state == game.State.RESUMING and game.jump_elapsed == flight and game.run_jumps == int(frozen.jumps), "Disk restoration cannot finish the old flight before a complete countdown")
	game._process(0.01)
	game._physics_process(0.2)
	check(game.state == game.State.RUNNING and game.jump_elapsed == -1.0 and game.run_jumps == int(frozen.jumps) + 1, "Resumed flight lands exactly once after the countdown")

func _test_center_wall() -> void:
	_fresh()
	game.run_time = 70.0
	game.height_px = 1500.0 * RushTuning.PIXELS_PER_METRE
	game.max_height_px = game.height_px
	game.course.ensure_ahead(game.height_px, game.run_time)
	game._begin_center_event()
	game._tick_center_event(RushTuning.CENTER_PREVIEW_SECONDS)
	game._tick_center_event(RushTuning.CENTER_ENTER_SECONDS)
	game.gecko.position = game.player_position()
	game._pause_run()
	var frozen := _snapshot()
	game._continue_run()
	game._process(2.9)
	game._physics_process(0.2)
	check(game.center_event == "ride" and _snapshot() == frozen, "Countdown does not consume the five-second safe wall or move its rider")
	game._process(0.1)
	game._physics_process(1.0 / 120.0)
	check(game.center_event == "ride" and game.center_elapsed > float(frozen.center_elapsed), "Safe wall lifetime resumes only after the countdown")

func _test_layout_and_native_captures() -> void:
	var args := OS.get_cmdline_user_args()
	var capture_dir := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../v26-pause-captures")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for frame: Vector2i in [Vector2i(540, 960), Vector2i(360, 800), Vector2i(1280, 720)]:
		root.size = frame
		await process_frame
		for theme: String in ["dark", "light"]:
			progress.data.settings.theme = theme
			_pause_at_launch()
			game._continue_run()
			game._update_layout()
			var viewport: Vector2 = game.get_viewport_rect().size
			check(game._resume_backdrop.size == viewport, "Input guard covers the entire viewport at " + str(frame))
			var panel: Rect2 = game._resume_panel.get_rect()
			check(panel.position.x >= 0 and panel.position.y >= 0 and panel.end.x <= viewport.x and panel.end.y <= viewport.y, "Countdown fits portrait/narrow/desktop viewports in both themes")
			check((panel.position + panel.size * 0.5).is_equal_approx(viewport * 0.5), "Countdown remains centered after resize")
			var style: StyleBoxFlat = game._resume_panel.get_theme_stylebox("panel")
			check((style.bg_color.r > 0.8) == (theme == "light"), "Overlay respects the selected light or dark theme")
			if DisplayServer.get_name() != "headless" and frame == Vector2i(540, 960) and theme == "dark":
				for digit in [3, 2, 1]:
					game.resume_elapsed = float(3 - digit) + 0.25
					game._update_resume_digit()
					await process_frame
					await RenderingServer.frame_post_draw
					var captured := root.get_texture().get_image()
					check(not captured.is_empty() and captured.save_png(capture_dir.path_join("resume-%d.png" % digit)) == OK, "Native countdown digit %d captured" % digit)
			game._pause_run()
