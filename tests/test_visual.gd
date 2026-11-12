extends SceneTree
## Reproducible native-render visual checks. Run without --headless, e.g.:
## DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . --script tests/test_visual.gd
## Optional first user argument changes capture directory; default ../qa.
## Uses an isolated save name; launch with XDG_DATA_HOME in a QA directory.

var game: Node2D
var progress: Node
var audio: Node
var capture_directory: String
var captures: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	progress = get_root().get_node("Progress")
	audio = get_root().get_node("Audio")
	var args := OS.get_cmdline_user_args()
	capture_directory = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../qa")
	DirAccess.make_dir_recursive_absolute(capture_directory)
	progress.save_file = "user://visual_qa.json"
	progress.data = progress._defaults()
	progress.data.settings = {"music": false, "sfx": false}
	audio.set_music_enabled(false)
	audio.set_sfx_enabled(false)
	get_root().size = Vector2i(540, 960)
	game = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(game)
	await process_frame
	game.set_physics_process(false)
	await _capture("menu")
	await _check_native_touch()
	game._start_run(false)
	game.set_process(false)
	game._process(0.3)
	await _capture("launch_floor")
	game._process(0.4)
	await _capture("launch_turn")
	game._process(0.6)
	await _capture("launch_crawl")
	game._process(0.6)
	game.set_process(true)

	_set_run("jungle")
	await _capture("hud")
	game.run_time = 40.0
	await _capture("night")
	game.gecko.eat_to(Vector2(-15, -180))
	await _capture("eat", 0.055)
	game.run_time = 62.0
	await _capture("dawn")
	game.center_event = "preview"
	game.center_elapsed = 0.65
	game.course.begin_safe_section(4500.0, 11500.0)
	await _capture("center_preview")
	game.center_origin_side = -1
	game.center_lane_x = game.CENTER_WALL_LEFT - 26.0
	game.center_event = "ride"
	game.center_elapsed = 4.55
	game.side = 1
	game.gecko.side = 1
	game.gecko.position = game.player_position()
	game.run_time = 10.0
	await _capture("center_cracks")
	game.center_wall.shatter()
	game.center_event = "exit"
	game.center_elapsed = 0.2
	await _capture("center_debris", 0.25)
	game._reset_center_event()
	_set_run("jungle")
	game.course.hazards.clear()
	for index in range(4):
		var kind: String = ["electric", "crystal", "pendulum", "vine"][index]
		var hazard: Dictionary = game.course._central_hazard(kind, 6000.0)
		hazard.x = 540.0
		hazard.h = 6300.0 + index * 310.0
		game.course._cache_geometry(hazard)
		game.course.hazards.append(hazard)
	game.course._draw_needed = true
	await _capture("new_obstacles")
	game._die("electric")
	await _capture("electric_skeleton", 0.09)
	await _capture("electric_ash", 0.42)
	for world in ["canyon", "ice", "crystal", "volcano", "sky"]:
		_set_run(world)
		await _capture("world_" + world)

	game._show_menu()
	for panel in ["shop", "profile", "daily", "settings"]:
		game.state = game.State.PANEL
		game.ui.show_panel(panel)
		await _capture(panel)

	for tab in ["sound", "graphics", "language", "creators"]:
		game.ui._settings_tab = tab
		game.ui.show_panel("settings")
		await _capture("settings_" + tab)
	progress.data.settings["language"] = "en"
	progress.data.settings["fps"] = 120
	progress.settings_changed()
	game._show_menu()
	await _capture("english")
	progress.data.settings["theme"] = "light"
	progress.settings_changed()
	game._show_menu()
	await _capture("light")
	progress.data.settings["theme"] = "dark"
	progress.data.settings["language"] = "ru"
	progress.settings_changed()
	var summary := {"run_id": "visual-qa-432", "height": 432.0, "coins": 8, "jumps": 32, "passed": 29}
	var rewards: Dictionary = progress.finish_run(summary)
	summary.merge(rewards, true)
	game.state = game.State.RESULTS
	game.ui.show_results(summary)
	await _capture("results")

	get_root().size = Vector2i(360, 800)
	await process_frame
	game._show_menu()
	await _capture("narrow_menu")
	_set_run("jungle")
	await _capture("narrow_hud")
	game.state = game.State.PANEL
	game.ui.show_panel("profile")
	await _capture("narrow_profile")
	game.ui.show_results(summary)
	await _capture("narrow_results")

	progress.data = progress._defaults()
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(progress.save_file + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	audio.set_music_enabled(false)
	audio.set_sfx_enabled(false)
	game.queue_free()
	await process_frame
	await process_frame
	print("VISUAL_QA_%s: %d native rendered screenshots, %d failures in %s" % ["OK" if failures == 0 else "FAILED", captures, failures, capture_directory])
	quit(0 if failures == 0 else 1)

func _set_run(theme_id: String) -> void:
	game.state = game.State.RUNNING
	game.world_id = theme_id
	game.height_px = 6000.0
	game.max_height_px = 6000.0
	game.camera_height = 5870.0
	game.run_time = 10.0
	game.side = 1
	game.gecko.side = 1
	game.jump_elapsed = -1.0
	game.gecko.position = game.player_position()
	game.gecko.mode = "run"
	game.environment.set_world(theme_id)
	game.environment.menu_blend = 0.0
	game.course.setup(87023, theme_id)
	game.course.ensure_ahead(6000.0, 10.0)
	game.course.visible = true
	game.ui.show_hud()
	game.ui.set_hint_visible(false)
	game.ui.update_hud(187.0, 2)
	game._update_camera(0.0)

func _capture(filename: String, delay: float = 0.42) -> void:
	# Allow font/container layout, fade and the real GL frame to settle.
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	if image.is_empty():
		push_error("Empty native-render capture: " + filename)
		quit(1)
		return
	var error := image.save_png(capture_directory.path_join(filename + ".png"))
	if error != OK:
		push_error("Could not write capture: " + filename)
		quit(1)
		return
	captures += 1
	print("CAPTURED %s %dx%d logical=%s window=%s" % [filename, image.get_width(), image.get_height(), get_root().get_visible_rect().size, DisplayServer.window_get_size()])

func _find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := _find_button(child, title)
		if found != null:
			return found
	return null

func _check_native_touch() -> void:
	var play := _find_button(game.ui, "ИГРАТЬ")
	if play == null:
		push_error("TOUCH_QA_FAILED: play button missing")
		failures += 1
		return
	await _touch_at(play.get_global_rect().get_center())
	if game.state != game.State.TRANSITION and game.state != game.State.RUNNING:
		_fail_touch("native play button did not launch; state=%s" % game.state)
		game._show_menu()
		return
	print("TOUCH_QA_OK: native ScreenTouch launched game; state=%s" % game.state)
	game._process(1.9)
	await process_frame
	await process_frame
	if game.state != game.State.RUNNING:
		_fail_touch("launch did not reach RUNNING")
		game._show_menu()
		return
	await _touch_at(Vector2(540.0, 900.0))
	if game.jump_elapsed != 0.0:
		_fail_touch("free field touch did not start exactly one jump: elapsed=%s" % game.jump_elapsed)
	else:
		print("TOUCH_QA_OK: free-field touch started a jump")
	game.jump_elapsed = 0.2
	await _touch_at(Vector2(540.0, 900.0))
	if not is_equal_approx(game.jump_elapsed, 0.2):
		_fail_touch("in-flight touch reset flight: elapsed=%s" % game.jump_elapsed)
	else:
		print("TOUCH_QA_OK: in-flight touch did not duplicate/reset jump")
	game.jump_elapsed = -1.0
	var pause_button := _find_button(game.ui, "Ⅱ")
	if pause_button == null:
		_fail_touch("pause button missing")
	else:
		await _touch_at(pause_button.get_global_rect().get_center())
		if game.state != game.State.PAUSED or game.jump_elapsed != -1.0:
			_fail_touch("pause touch propagated or did not pause: state=%s flight=%s" % [game.state, game.jump_elapsed])
		else:
			print("TOUCH_QA_OK: pause button paused without triggering jump")
			await _capture("pause")
	game._show_menu()

func _touch_at(logical_position: Vector2) -> void:
	var window_position: Vector2 = get_root().get_final_transform() * logical_position
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = window_position
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = window_position
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await process_frame

func _fail_touch(message: String) -> void:
	push_error("TOUCH_QA_FAILED: " + message)
	failures += 1
