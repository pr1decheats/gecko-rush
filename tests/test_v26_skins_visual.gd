extends SceneTree
## Skin API and native contact sheets use the actual animated player rig.
const IDS := ["neon_pulse", "desert_wanderer", "shadow_jumper", "cosmo_gecko", "jungle_hunter",
	"pirate_captain", "robo_gecko", "electro_shock", "royal_pearl", "cyber_ninja",
	"rainbow_spark", "moon_ghost", "golden_champion", "volcanic_fighter", "pixel_gecko",
	"frost_crystal", "venom_chameleon", "star_wanderer", "steel_knight", "ghost_dragon"]
const GECKO = preload("res://scripts/gecko.gd")
var checks := 0
var failures := 0
var geckos: Array = []

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
	var container := Node2D.new()
	root.add_child(container)
	var color_signatures: Dictionary = {}
	for id: String in IDS:
		var gecko := GECKO.new()
		gecko.set_skin(id)
		check(gecko.skin_id == id, "Unowned shop preview accepts " + id + " before ready")
		container.add_child(gecko)
		gecko.set_process(false)
		var palette := ""
		for name: String in ["ink", "deep", "skin", "lit", "pale", "accent"]:
			palette += gecko._c(name).to_html()
		check(not color_signatures.has(palette), "Distinct body/gear palette for " + id)
		color_signatures[palette] = id
		gecko.run_speed_factor = 80.0
		gecko.mode = "run"
		gecko._process(0.25)
		check(gecko._visual_speed_factor <= 3.0, "Costume does not accelerate the animation unnaturally: " + id)
		gecko.reset_animation()
		check(gecko.skin_id == id and gecko._visual_speed_factor == 1.0 and gecko._stride_phase == 0.0, "Retry resets movement phases while retaining " + id)
		geckos.append(gecko)
	var fallback := GECKO.new()
	fallback.set_skin("unknown-unowned-id")
	check(fallback.skin_id == "standard_green", "Unknown skin safely uses original green gecko")
	fallback.free()
	container.queue_free()
	await process_frame
	geckos.clear()
	if DisplayServer.get_name() != "headless":
		await _capture()
	print("V26 SKINS VISUAL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var directory := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../v26-skins-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1200)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color("111b2a")
	backdrop.size = Vector2(1600, 1200)
	viewport.add_child(backdrop)
	for index in range(IDS.size()):
		var column := index % 5
		var row := index / 5
		var card := ColorRect.new()
		card.color = Color("1d2a3b")
		card.position = Vector2(column * 320 + 8, row * 300 + 8)
		card.size = Vector2(304, 284)
		viewport.add_child(card)
		var label := Label.new()
		label.text = "%02d  %s" % [index + 1, IDS[index]]
		label.add_theme_font_size_override("font_size", 17)
		label.position = Vector2(column * 320 + 20, row * 300 + 262)
		label.size = Vector2(288, 24)
		viewport.add_child(label)
		var gecko := GECKO.new()
		gecko.set_skin(IDS[index])
		gecko.position = Vector2(column * 320 + 155, row * 300 + 144)
		viewport.add_child(gecko)
		gecko.set_process(false)
		geckos.append(gecko)
	for fixture in ["run", "sleep", "jump", "wake", "ground", "right", "blink"]:
		for gecko in geckos:
			gecko.side = 1 if fixture == "right" else -1
			gecko.jump_progress = 0.45
			gecko.launch_progress = 0.52
			gecko.mode = "wake_climb" if fixture == "wake" else ("ground_idle" if fixture == "ground" else ("run" if fixture in ["right", "blink"] else fixture))
			gecko._clock = 4.0 if fixture == "blink" else 1.6
			gecko._stride_phase = 1.2
			gecko._tail_phase = 0.8
			gecko.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var captured := viewport.get_texture().get_image()
		check(not captured.is_empty() and captured.get_size() == Vector2i(1600, 1200), fixture + " actually renders all 20 skins")
		check(captured.save_png(directory.path_join("skins-" + fixture + ".png")) == OK, fixture + " native contact sheet saved")
		var hashes: Dictionary = {}
		for index in range(IDS.size()):
			var avatar := captured.get_region(Rect2i(index % 5 * 320 + 45, index / 5 * 300 + 25, 220, 230))
			var signature := hash(avatar.get_data())
			check(not hashes.has(signature), fixture + " visible outfit differs for " + IDS[index])
			hashes[signature] = IDS[index]
		print("SKIN_CAPTURE ", fixture, " 20 distinct animated player skins")
	viewport.queue_free()
	await process_frame
	await process_frame
	geckos.clear()
