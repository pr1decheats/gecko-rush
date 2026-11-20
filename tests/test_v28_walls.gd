extends SceneTree
## Cached wall artwork: real native contact sheet and tile/seam/cache checks.
const ENVIRONMENT = preload("res://scripts/environment.gd")
const IDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
var checks := 0
var failures := 0
var env: Node2D

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
	var args := OS.get_cmdline_user_args()
	var directory := args[0] if not args.is_empty() else "/workspace/work/v28-wall-captures"
	var baseline := args.size() > 1 and args[1] == "baseline"
	DirAccess.make_dir_recursive_absolute(directory)
	env = ENVIRONMENT.new()
	var textures: Array[Texture2D] = []
	var samples: Dictionary = {}
	for id: String in IDS:
		var expected_width := 135 if baseline else 270
		var expected_height := 160 if baseline else 320
		for night: bool in [false, true]:
			var palette: Dictionary = ENVIRONMENT.NIGHT_PALETTES[id] if night else ENVIRONMENT.PALETTES[id]
			var variants: int = 4 if baseline else 6
			for variant in range(variants):
				var texture: Texture2D = env._wall_tile(id, palette, variant)
				check(texture.get_width() == expected_width and texture.get_height() == expected_height, "%s:%d native-resolution wall texture" % [id, variant])
				if DisplayServer.get_name() != "headless":
					var img := texture.get_image()
					check(img != null and not img.is_empty(), "%s actual pixels exist" % id)
					if img != null:
						var digest := hash(img.get_data())
						check(not samples.has(digest), "%s:%d:%s wall variant/lighting is visibly distinct" % [id, variant, str(night)])
						samples[digest] = true
						check(img.get_pixel(expected_width - 1, 0).a > 0.99 and img.get_pixel(0, expected_height - 1).a > 0.99, "Solid artwork reaches the exact wall edges")
						if not baseline:
							for x in range(0, expected_width, 17):
								check(img.get_pixel(x, 0).is_equal_approx(img.get_pixel(x, expected_height - 1)), "%s:%d periodic tile endpoints match" % [id, variant])
						if variant == 0:
							check(img.save_png(directory.path_join(id + ("-night" if night else "-day") + ".png")) == OK, "Saved unmodified texture pixels")
				if not night and variant < 3:
					textures.append(texture)
	if DisplayServer.get_name() != "headless":
		await _contact_sheet(directory, textures)
		await _scene(directory)
	else:
		env.free()
	print("V28 WALLS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _contact_sheet(directory: String, textures: Array[Texture2D]) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1640, 1030)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color("172431")
	backdrop.size = viewport.size
	viewport.add_child(backdrop)
	for column in range(6):
		var label := Label.new()
		label.text = IDS[column].to_upper()
		label.add_theme_font_size_override("font_size", 21)
		label.position = Vector2(column * 270 + 18, 8)
		viewport.add_child(label)
		for row in range(3):
			var display := TextureRect.new()
			display.texture = textures[column * 3 + row]
			display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			display.position = Vector2(column * 270 + 10, row * 320 + 54)
			display.size = Vector2(270, 320)
			display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			viewport.add_child(display)
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(directory.path_join("walls-contact.png")) == OK, "Native six-biome wall contact sheet saved")
	viewport.queue_free()
	await process_frame

func _scene(directory: String) -> void:
	root.size = Vector2i(540, 960)
	root.content_scale_size = Vector2i(1080, 1920)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.add_child(env)
	env.set_process(false)
	env.viewport_height = 1920
	env.menu_blend = 0.0
	env.camera_height = 7800.25
	env.time = 11.0
	for id: String in IDS:
		var started := Time.get_ticks_usec()
		env.set_world(id)
		print("WALL_WORLD_CACHE %s: %.1f ms" % [id, (Time.get_ticks_usec() - started) / 1000.0])
		var first: Texture2D = env._active.wall_day[0]
		env.night_amount = 0.0
		env.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("scene-" + id + ".png")) == OK, "Native fullscene " + id)
		env.night_amount = 1.0
		env.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("scene-" + id + "-night.png")) == OK, "Native fullscene night " + id)
		env._process(1.0 / 240.0)
		check(env._active.wall_day[0] == first, "Scrolling reuses cached wall pixels: " + id)
		check(env._world_cache.size() <= 2, "World texture LRU stays bounded")
	# Crossing a 320-pixel repeat boundary by a subpixel must not swap the
	# visible masonry. A shuffled tile is indexed by its world position.
	env.set_world("jungle")
	env.night_amount = 0.37
	env.time = 11.0
	env.camera_height = 839.999
	env.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var before_seam: Image = root.get_texture().get_image().get_region(Rect2i(0, 0, 134, 960))
	env.camera_height = 840.001
	env.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var after_seam: Image = root.get_texture().get_image().get_region(Rect2i(0, 0, 134, 960))
	# At 540px the 1080px scene downsamples two source pixels to one; a
	# nearest sample can switch a source pixel at an exact integer boundary.
	# Bound that raster change instead of requiring bitwise equal frames.
	var before_bytes := before_seam.get_data()
	var after_bytes := after_seam.get_data()
	var difference := 0.0
	for offset in range(0, before_bytes.size(), 4):
		for channel in range(3):
			difference += absf(float(before_bytes[offset + channel]) - float(after_bytes[offset + channel]))
	var mean_difference := difference / (float(before_bytes.size() / 4) * 3.0 * 255.0)
	print("WALL_SEAM_RASTER mean channel delta %.5f" % mean_difference)
	check(mean_difference < 0.02, "Fractional vertical movement across a shuffled tile boundary has no texture jump")
	check(before_seam.save_png(directory.path_join("seam-before.png")) == OK and after_seam.save_png(directory.path_join("seam-after.png")) == OK, "Native tile wrap samples saved")
	# Hiding the side walls during a center-wall event remains a draw fade.
	env.side_walls_visibility = 0.0
	env.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join("scene-center-wall-fade.png")) == OK, "Center-wall environment fade captured")
	env.queue_free()
	await process_frame
