extends SceneTree
## Native pose contact sheet; run with a real GL display, not --headless.
## DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . \
##   --script tests/test_v23_gecko_visual.gd -- /absolute/capture/directory

const SHEET_SIZE := Vector2i(1280, 1050)
const SAMPLE_PROGRESS := [0.0, 0.22, 0.30, 0.42, 0.48, 0.54, 0.60, 0.66, 0.70]
var capture_directory := ""
var specimens: Array[Node2D] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	get_root().get_node("Audio").set_music_enabled(false)
	get_root().get_node("Audio").set_sfx_enabled(false)
	var args := OS.get_cmdline_user_args()
	capture_directory = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../v23-gecko-qa")
	DirAccess.make_dir_recursive_absolute(capture_directory)
	get_root().content_scale_size = SHEET_SIZE
	get_root().size = SHEET_SIZE
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var background := ColorRect.new()
	background.color = Color("d2d4bd")
	background.size = SHEET_SIZE
	get_root().add_child(background)
	for i in range(12):
		var cell := Vector2((i % 4) * 320, (i / 4) * 350)
		var label := Label.new()
		label.text = "SLEEP / slow breath" if i == 0 else ("WAKE %.2f" % SAMPLE_PROGRESS[i] if i < SAMPLE_PROGRESS.size() else ["RUN / planted stride", "JUMP / tucked legs", "BLINK / same profile"][i - SAMPLE_PROGRESS.size()])
		label.position = cell + Vector2(16, 14)
		label.add_theme_color_override("font_color", Color("192f32"))
		label.add_theme_font_size_override("font_size", 20)
		get_root().add_child(label)
		var gecko: Node2D = load("res://scripts/gecko.gd").new()
		gecko.position = cell + Vector2(146, 170)
		gecko.scale = Vector2.ONE * 1.8
		get_root().add_child(gecko)
		gecko.set_process(false)
		gecko._clock = 0.0
		gecko._stride_phase = 0.7
		gecko._tail_phase = 0.3
		if i == 0:
			gecko.mode = "sleep"
		elif i < SAMPLE_PROGRESS.size():
			gecko.set_launch_pose(SAMPLE_PROGRESS[i])
		else:
			gecko.mode = "jump" if i == 10 else "run"
			if i == 10:
				gecko.jump_progress = 0.05
			if i == 11:
				gecko._clock = 4.0
		gecko.queue_redraw()
		specimens.append(gecko)
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var error := image.save_png(capture_directory.path_join("gecko_pose_sheet.png"))
	if error != OK or image.get_size() != SHEET_SIZE:
		push_error("GECKO_VISUAL_QA_FAILED: capture size=%s save=%s" % [image.get_size(), error])
		quit(1)
		return
	print("GECKO_VISUAL_QA_OK: 12 native poses captured in " + capture_directory.path_join("gecko_pose_sheet.png"))
	for specimen in specimens:
		specimen.queue_free()
	specimens.clear()
	await process_frame
	await process_frame
	quit(0)
