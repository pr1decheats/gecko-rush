extends SceneTree
## Integrated native production scenes using ordinary seeded generated obstacles.
var game: Node
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _prepare(world_id: String, seconds: float) -> void:
	var height := 575.0 * RushTuning.PIXELS_PER_METRE
	game.state = game.State.RUNNING
	game.world_id = world_id
	game.height_px = height
	game.max_height_px = height
	game.run_time = seconds
	game.jump_elapsed = -1.0
	game._reset_center_event()
	game.center_first_given = true
	game.next_center_metres = 1.0e12
	game.course.setup(41, world_id)
	game.course.ensure_ahead(height, seconds)
	game.course.visible = true
	game.side = -1
	if game.course.collision_at(Vector2(game.LEFT_X, -height), seconds): game.side = 1
	game.gecko.side = game.side
	game.gecko.mode = "run"
	game.gecko.position = game.player_position()
	game.gecko.run_speed_factor = game.current_speed() / RushTuning.START_SPEED
	game.environment.set_world(world_id)
	game.environment.menu_blend = 0.0
	game.ui.show_hud()
	game.ui.set_hint_visible(false)
	game._reset_motion_interpolation()
	game.camera_height = height - 130.0 + game.current_speed() / 7.5
	game._process(0.0)
	game.course.queue_redraw()
	game.environment.queue_redraw()

func _run() -> void:
	await process_frame
	var progress := root.get_node("Progress")
	progress.save_file = "user://v28_world_capture.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.settings_changed()
	var args := OS.get_cmdline_user_args()
	var output: String = args[0] if not args.is_empty() else "/tmp/v28-world-capture"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(540, 960)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	for world_id: String in RushCourse.WORLD_TYPES:
		for fixture in [[10.0, "day"], [50.0, "night"]]:
			_prepare(world_id, float(fixture[0]))
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			if image.is_empty() or image.save_png(output.path_join("%s_%s.png" % [world_id, fixture[1]])) != OK:
				push_error("Native world screenshot failed")
				failures += 1
			print("V28_WORLD %s %s generated_hazards=%d" % [world_id, fixture[1], game.course.hazards.size()])
	game.queue_free()
	await process_frame
	await process_frame
	print("V28 integrated world capture: 12 frames, %d failures" % failures)
	quit(1 if failures else 0)
