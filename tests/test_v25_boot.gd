extends SceneTree
## Exercise what the player sees and does at the actual new entry scene.
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var p := root.get_node("Progress")
	p.save_file = "user://v25_boot_test.json"
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.settings_changed()
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/boot.tscn", "App actually enters the studio intro")
	check(ProjectSettings.get_setting("application/boot_splash/image") == "res://assets/triada-games-launch.png", "Engine uses the compact handoff")
	var boot = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	boot.set_process(false)
	check(not boot.request_skip(), "Initial touch cannot accidentally skip into the game")
	for frame in [Vector2i(540, 960), Vector2i(360, 800)]:
		root.size = frame
		await process_frame
		boot._layout()
		var width: float = boot._logo_root.scale.x * 1170.0
		check(is_equal_approx(width / boot.get_viewport_rect().size.x, 0.55), "Logo stays compact on " + str(frame))
		check(boot._logo_root.position.is_equal_approx(boot.get_viewport_rect().size * 0.5), "Logo remains centered on " + str(frame))
	var previous := 0.0
	for moment in [0.0, 0.175, 0.35, 0.525, 0.7]:
		boot.update_visuals(moment)
		check(boot.logo_opacity >= previous, "Intro fades in without flashes")
		previous = boot.logo_opacity
	boot.update_visuals(0.7)
	var earlier: float = boot._symbol.rotation
	boot.update_visuals(1.9)
	check(boot._symbol.rotation > earlier, "Triangle actually rotates while displayed")
	check(boot._symbol.rotation < PI / 6.0, "Triangle turns slowly instead of spinning rapidly")
	check(boot._wordmark.rotation == 0.0, "TRIADA above GAMES stays upright")
	boot.update_visuals(2.25)
	check(boot.logo_opacity > 0.0 and boot.logo_opacity < 1.0, "Intro fades out smoothly")
	boot._process(2.6)
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.get_script().resource_path == "res://scripts/main.gd", "Completed intro enters the actual game scene")
	if current_scene != null:
		check(current_scene.state == current_scene.State.MENU, "Intro does not start a run by itself")
	var skipped = load("res://scenes/boot.tscn").instantiate()
	current_scene.queue_free()
	await process_frame
	root.add_child(skipped)
	current_scene = skipped
	skipped.set_process(false)
	skipped.elapsed = 0.4
	skipped.update_visuals(0.4)
	check(skipped.request_skip(), "Player can skip after the brief input guard")
	check(not skipped.request_skip(), "Duplicate touch is consumed once")
	skipped._process(0.2)
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.get_script().resource_path == "res://scripts/main.gd", "Skipping also reaches the game normally")
	current_scene.queue_free()
	await process_frame
	await process_frame
	print("V25 BOOT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
