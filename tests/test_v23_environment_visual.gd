extends SceneTree
## Native rendered biome review, with isolated application data and no game state.
## DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . --script tests/test_v23_environment_visual.gd -- /absolute/captures

const WORLD_IDS: Array[String] = ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
var environment: Node2D
var captures: int = 0
var failures: int = 0
var capture_directory: String
var day_samples: Array[PackedByteArray] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	get_root().get_node("Audio").set_music_enabled(false)
	get_root().get_node("Audio").set_sfx_enabled(false)
	var args := OS.get_cmdline_user_args()
	capture_directory = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../qa-v23-environment")
	DirAccess.make_dir_recursive_absolute(capture_directory)
	get_root().size = Vector2i(540, 960)
	environment = load("res://scripts/environment.gd").new()
	get_root().add_child(environment)
	environment.set_process(false)
	environment.viewport_height = 1920.0
	environment.camera_height = 5800.0
	environment.time = 12.0
	for id in WORLD_IDS:
		environment.set_world(id)
		var cached_texture: Texture2D = environment._active.scenery_day[0]
		for phase in ["day", "night"]:
			environment.night_amount = 0.0 if phase == "day" else 1.0
			environment.queue_redraw()
			var rendered: Image = await _capture(id + "_" + phase)
			if phase == "day":
				var sample := rendered.get_region(Rect2i(142, 100, 250, 650)).get_data()
				for previous in day_samples:
					_check(sample != previous, id + " has distinct rendered scene pixels")
				day_samples.append(sample)
			environment._process(0.016)
			_check(environment._active.scenery_day[0] == cached_texture, "animation reuses cached " + id + " textures")
			_check(environment._active.scenery_day.size() == 2 and environment._active.scenery_night.size() == 2, id + " has two day/night parallax layers")
		# Re-selecting a cached world must not recreate its artwork.
		environment.set_world(id)
		_check(environment._active.scenery_day[0] == cached_texture, id + " re-selection keeps cached textures")
	# Full-width scenery must remain present when center-wall events hide side walls.
	environment.set_world("jungle")
	environment.night_amount = 0.0
	environment.side_walls_visibility = 0.0
	environment.queue_redraw()
	await _capture("jungle_full_width")
	# The menu still has an opaque, grass-topped starting ledge.
	environment.side_walls_visibility = 1.0
	environment.camera_height = 0.0
	environment.queue_redraw()
	await _capture("jungle_menu_floor")
	environment.theme = "light"
	environment.queue_redraw()
	await _capture("jungle_light_theme")
	print("V23_ENVIRONMENT_%s: %d native captures, %d failures in %s" % ["OK" if failures == 0 else "FAILED", captures, failures, capture_directory])
	environment.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)

func _capture(filename: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	_check(not image.is_empty(), filename + " has a rendered image")
	_check(image.save_png(capture_directory.path_join(filename + ".png")) == OK, filename + " saves successfully")
	captures += 1
	print("CAPTURED %s %dx%d" % [filename, image.get_width(), image.get_height()])
	return image

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("V23_ENVIRONMENT_FAILED: " + message)
