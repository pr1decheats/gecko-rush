extends SceneTree
## Verify that the actual player and previews use the illustrated atlases.
## Native mode also captures the standard character's complete pose sequence.
const GECKO = preload("res://scripts/gecko.gd")
var checks := 0
var failures := 0
var specimens: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GECKO.DETAILED_CATALOG))
	var skins: Dictionary = manifest.get("skins", {})
	check(skins.size() == 21, "Default character and all 20 outfits have illustrated art")
	var textures: Dictionary = {}
	for id: String in skins:
		var gecko := GECKO.new()
		gecko.set_skin(id)
		root.add_child(gecko)
		gecko.set_process(false)
		gecko.mode = "run"
		check(gecko._sync_detailed_visual(), "Player uses illustrated RUN mesh: " + id)
		check(gecko._detailed_active and gecko._detailed_run.visible, "Illustrated body replaces fallback drawing: " + id)
		check(gecko._detailed_run.texture != null and gecko._detailed_run.mesh.get_surface_count() == 1, "Atlas texture and connected mesh loaded: " + id)
		var vertices: PackedVector3Array = gecko._detailed_run.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(vertices.size() == 1025, "One connected mesh deforms limbs and tail without separate floating pieces: " + id)
		for pose: String in ["run", "sleep"]:
			var data: Dictionary = skins[id][pose]
			var image: Texture2D = load(data["texture"])
			var rect: Array = data["rect"]
			check(rect[0] >= 0 and rect[1] >= 0 and rect[0] + rect[2] <= image.get_width() and rect[1] + rect[3] <= image.get_height(), "Correct atlas crop for " + id + " / " + pose)
			textures[data["texture"]] = true
		var texture_id := gecko._detailed_run.texture.get_instance_id()
		gecko._process(0.20)
		gecko._sync_detailed_visual()
		var shader: ShaderMaterial = gecko._detailed_run.material
		check(is_equal_approx(shader.get_shader_parameter("stride_phase"), gecko._stride_phase), "GPU stride follows explicit animation clock: " + id)
		check(gecko._detailed_run.texture.get_instance_id() == texture_id, "Animation retains cached original texture: " + id)
		var phase: float = shader.get_shader_parameter("stride_phase")
		await process_frame
		check(is_equal_approx(shader.get_shader_parameter("stride_phase"), phase), "Paused character freezes GPU animation: " + id)
		gecko._clock = 4.0
		gecko._sync_detailed_visual()
		check(float(shader.get_shader_parameter("closed_eye")) > 0.98, "Blink closes the illustrated eye: " + id)
		gecko.mode = "sleep"
		check(gecko._sync_detailed_visual() and gecko._detailed_sleep.visible and not gecko._detailed_run.visible, "Curled sleeping art uses one coherent body: " + id)
		check(gecko._detailed_sleep.texture != null and gecko._detailed_sleep.position.y == GECKO.GROUND_FEET_Y, "Sleeping body rests on menu floor: " + id)
		gecko.set_launch_pose(0.52)
		gecko._sync_detailed_visual()
		check(gecko._detailed_run.visible and float(shader.get_shader_parameter("unfold")) > 0.0, "Waking unfolds the same textured mesh: " + id)
		gecko.electrocute()
		check(not gecko._sync_detailed_visual() and not gecko._detailed_root.visible, "Electric skeleton and ash replace sprite during death: " + id)
		gecko.reset_animation()
		gecko._sync_detailed_visual()
		check(gecko.skin_id == id and gecko._stride_phase == 0.0 and gecko._tail_phase == 0.0, "Retry retains outfit and resets both phases: " + id)
		check(float(shader.get_shader_parameter("stride_phase")) == 0.0 and float(shader.get_shader_parameter("tail_phase")) == 0.0, "Reset reaches the GPU rig: " + id)
		var expected_filter := CanvasItem.TEXTURE_FILTER_NEAREST if id == "pixel_gecko" else CanvasItem.TEXTURE_FILTER_LINEAR
		check(gecko._detailed_run.texture_filter == expected_filter and gecko._detailed_sleep.texture_filter == expected_filter, "Appropriate texture filtering: " + id)
		gecko.queue_free()
	await process_frame
	check(textures.size() == 11, "Six run atlases and five separate sleep atlases are shared by 21 characters")
	var shader_text := FileAccess.get_file_as_string("res://assets/characters/rig.gdshader")
	check(not shader_text.contains("TIME"), "Shader has no independent clock that could animate during pause")
	if DisplayServer.get_name() != "headless":
		await _capture()
	print("V26 DETAILED VISUAL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var directory := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../v26-detailed-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 1120)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color("111b2a")
	backdrop.size = viewport.size
	viewport.add_child(backdrop)
	var fixtures := ["sleep", "wake .22", "wake .34", "wake .48", "wake .60", "wake .68", "run", "jump", "blink", "right", "eat", "electric"]
	for index in range(fixtures.size()):
		var column := index % 4
		var row := index / 4
		var card := ColorRect.new()
		card.color = Color("1d2a3b")
		card.position = Vector2(column * 360 + 8, row * 370 + 8)
		card.size = Vector2(344, 354)
		viewport.add_child(card)
		var label := Label.new()
		label.text = "STANDARD / " + fixtures[index]
		label.add_theme_font_size_override("font_size", 19)
		label.position = card.position + Vector2(12, 12)
		viewport.add_child(label)
		var gecko := GECKO.new()
		gecko.position = card.position + Vector2(166, 183)
		gecko.scale = Vector2.ONE * 1.28
		viewport.add_child(gecko)
		gecko.set_process(false)
		gecko._clock = 4.0 if fixtures[index] == "blink" else 1.4
		gecko._stride_phase = 1.1
		gecko._tail_phase = 0.8
		gecko.mode = "run"
		if fixtures[index] == "sleep":
			gecko.mode = "sleep"
		elif fixtures[index].begins_with("wake"):
			gecko.set_launch_pose(float(fixtures[index].split(" ")[1]))
		elif fixtures[index] == "jump":
			gecko.mode = "jump"
			gecko.jump_progress = 0.43
		elif fixtures[index] == "right":
			gecko.side = 1
		elif fixtures[index] == "eat":
			gecko.eat_to(Vector2(-45, -58))
			gecko._eat_clock = 0.08
		elif fixtures[index] == "electric":
			gecko.electrocute()
			gecko._electro_clock = 0.12
		gecko.queue_redraw()
		specimens.append(gecko)
	await process_frame
	await RenderingServer.frame_post_draw
	var captured := viewport.get_texture().get_image()
	check(captured.save_png(directory.path_join("standard-detailed-poses.png")) == OK, "Standard sleep/wake/run/jump/blink/eating/electrical poses captured")
	viewport.queue_free()
	specimens.clear()
	await process_frame
