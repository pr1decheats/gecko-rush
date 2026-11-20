extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	await process_frame
	root.size = Vector2i(270,480)
	var progress := root.get_node("Progress")
	progress.save_file = "user://v28-live-only.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.settings_changed()
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_run(true)
	game._process(1.4)
	game.course.begin_safe_section(0.0,100000.0)
	# Only reduce artwork cost to let software GL deliver >120 actual frames.
	# The unmodified production _process and _physics_process both run normally.
	game.environment.visible = false
	game.course.visible = false
	game.ui.visible = false
	Engine.max_fps = 240
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var previous_time: float = game.run_time
	var previous_position: Vector2 = game.gecko.position
	var between := 0
	var advancing := 0
	var fractions := {}
	for frame in range(240):
		await RenderingServer.frame_post_draw
		var fraction := Engine.get_physics_interpolation_fraction()
		fractions[roundi(fraction * 1000.0)] = true
		if frame > 5 and game.run_time == previous_time:
			between += 1
			if game.gecko.position.distance_to(previous_position) > 0.0001:
				advancing += 1
		previous_time = game.run_time
		previous_position = game.gecko.position
	print("LIVE MAIN: ", fractions.size(), " different Engine interpolation fractions; ", advancing, "/", between, " intervening real rendered frames advance without a new physics tick; state=", game.state)
	quit(0 if fractions.size() > 2 and advancing == between and between > 0 else 1)
