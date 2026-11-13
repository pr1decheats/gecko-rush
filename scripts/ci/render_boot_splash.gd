extends SceneTree
## Render the native launch handoff with the same atlas/shader/layout as the intro.
## Run using the native renderer; this utility is excluded from mobile packages.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	var args := OS.get_cmdline_user_args()
	var directory := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../v25-branding-research")
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1080, 1920)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var boot = load("res://scenes/boot.tscn").instantiate()
	viewport.add_child(boot)
	boot.set_process(false)
	for fixture in [[0.0, "start"], [0.35, "fade"], [0.7, "full"], [1.9, "rotate"], [2.25, "out"]]:
		boot.update_visuals(float(fixture[0]))
		await process_frame
		await RenderingServer.frame_post_draw
		var captured := viewport.get_texture().get_image()
		if captured.is_empty() or captured.get_size() != Vector2i(1080, 1920):
			push_error("Native intro render is empty or has the wrong dimensions")
			quit(1)
			return
		if captured.save_png(directory.path_join("boot-" + String(fixture[1]) + ".png")) != OK:
			quit(1)
			return
		if fixture[0] == 0.0 and captured.save_png("res://assets/triada-games-launch.png") != OK:
			quit(1)
			return
		print("BOOT_RENDER time=%.2f opacity=%.3f radians=%.4f" % [fixture[0], boot.logo_opacity, boot._symbol.rotation])
	boot.queue_free()
	viewport.queue_free()
	await process_frame
	await process_frame
	print("BOOT_RENDER_PASS: five native frames and compact launch handoff")
	quit(0)
