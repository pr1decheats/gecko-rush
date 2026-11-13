extends SceneTree
## Validate the supplied logo and both engine/native iOS launch configuration.
## Can run in an isolated utility project with -- /absolute/game/source.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var project_root := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://")
	var project := ConfigFile.new()
	var presets := ConfigFile.new()
	_check(project.load(project_root.path_join("project.godot")) == OK, "Project configuration loads")
	_check(presets.load(project_root.path_join("export_presets.cfg")) == OK, "Export configuration loads")
	_check(project.get_value("application", "config/icon") == "res://assets/icon.svg", "Gecko app icon is retained")
	_check(project.get_value("application", "boot_splash/show_image") == true, "Custom engine splash is visible")
	_check(project.get_value("application", "boot_splash/image") == "res://assets/triada-games.png", "Engine uses supplied Triada logo")
	_check(project.get_value("application", "boot_splash/stretch_mode") == 1, "Engine keeps image aspect ratio")
	_check(project.get_value("application", "boot_splash/use_filter") == true, "Detailed logo uses filtering")
	_check(int(project.get_value("application", "boot_splash/minimum_display_time")) == 750, "Brand is briefly visible without a long delay")
	var background: Color = project.get_value("application", "boot_splash/bg_color")
	_check(background.is_equal_approx(Color(1.0/255.0, 3.0/255.0, 15.0/255.0, 1)), "Letterbox background matches supplied logo")
	var path := project_root.path_join("assets/triada-games.png")
	var image := Image.load_from_file(path)
	_check(image != null and not image.is_empty(), "Boot PNG decodes")
	_check(image.get_size() == Vector2i(1170, 1075), "Original logo resolution is retained")
	_check(FileAccess.get_sha256(path) == "59f25a432ae2f364524569d1afa703e01fd1632e1684c6d8d3cb52eb55063e84", "Exact native PNG encoding of supplied logo retained")
	for size: Vector2 in [Vector2(1080, 1920), Vector2(1170, 2532), Vector2(750, 1334), Vector2(1920, 1080)]:
		var fitted := Vector2(image.get_size()) * minf(size.x / image.get_width(), size.y / image.get_height())
		_check(fitted.x <= size.x + 0.001 and fitted.y <= size.y + 0.001, "Aspect-fit avoids cropping at " + str(size))
		_check(is_equal_approx(fitted.x / fitted.y, 1170.0 / 1075.0), "Aspect-fit preserves original proportions at " + str(size))
	var section := ""
	for candidate in presets.get_sections():
		if not candidate.ends_with(".options") and presets.get_value(candidate, "platform", "") == "iOS":
			section = candidate + ".options"
	_check(not section.is_empty(), "iOS export exists")
	_check(presets.get_value(section, "storyboard/image_scale_mode") == 2, "Native iOS launch screen uses scaleAspectFit")
	for density in ["2x", "3x"]:
		_check(presets.get_value(section, "storyboard/custom_image@" + density) == "res://assets/triada-games.png", "Native iOS " + density + " uses supplied logo")
	_check(presets.get_value(section, "storyboard/use_custom_bg_color") == true, "iOS custom background enabled")
	_check(presets.get_value(section, "storyboard/custom_bg_color").is_equal_approx(background), "Engine and native iOS background agree")
	if DisplayServer.get_name() != "headless" and args.size() > 1:
		get_root().size = Vector2i(405, 720)
		var backdrop := ColorRect.new()
		backdrop.color = background
		backdrop.size = Vector2(405, 720)
		get_root().add_child(backdrop)
		var logo := TextureRect.new()
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.texture = ImageTexture.create_from_image(image)
		logo.size = Vector2(405, 720)
		get_root().add_child(logo)
		_check(logo.size == Vector2(405, 720), "Logo preview uses the actual portrait frame")
		await create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		var rendered := get_root().get_texture().get_image()
		_check(not rendered.is_empty(), "Native logo preview renders")
		DirAccess.make_dir_recursive_absolute(args[1])
		_check(rendered.save_png(args[1].path_join("triada-logo-fit-preview.png")) == OK, "Native aspect-fit preview saved")
		logo.queue_free()
		backdrop.queue_free()
		await process_frame
	print("V24 branding: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
