extends SceneTree
## Native contact sheet of all 24 actual hazard drawings, at unchanged game size.
var courses: Array[RushCourse] = []
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _label(text: String, point: Vector2, size: int, tint: Color = Color("b9cdd2")) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size", size)
	label.modulate = tint
	root.add_child(label)

func _run() -> void:
	await process_frame
	root.size = Vector2i(1200, 1040)
	root.content_scale_size = root.size
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	var args := OS.get_cmdline_user_args()
	var output: String = args[0] if not args.is_empty() else "/tmp/v28-hazards"
	DirAccess.make_dir_recursive_absolute(output)
	var background := ColorRect.new()
	background.color = Color("152530")
	background.size = Vector2(1200, 1040)
	root.add_child(background)
	_label("GECKO RUSH  /  24 THEMATIC HAZARDS", Vector2(30, 12), 26, Color("e9f4ef"))
	var row := 0
	for world: String in RushCourse.WORLD_TYPES:
		_label(world.to_upper(), Vector2(30, 65 + row * 160), 19, Color("88a3af"))
		var column := 0
		for kind: String in RushCourse.WORLD_TYPES[world]:
			var course := RushCourse.new()
			root.add_child(course)
			course.setup(41, world)
			course.coins.clear()
			course.flies.clear()
			var item: Dictionary
			if kind == String(RushCourse.WORLD_WALL_KIND[world]):
				item = course._wall_spikes(0, 0, 48)
				item["side"] = 0
			else:
				item = course._central_hazard(kind, 0)
				item["amplitude"] = 0.0
				item["motion_x"] = 0.0
				item["motion_y"] = 0.0
				item["angle_sway"] = 0.0
				item["spin"] = 0.0
				item["phase"] = 0.0
			item["x"] = 540.0
			item["h"] = 0.0
			course._cache_geometry(item)
			course.hazards = [item]
			course.position = Vector2(220 + column * 250 - 540, 120 + row * 160)
			courses.append(course)
			_label(kind, Vector2(160 + column * 250, 177 + row * 160), 16)
			check(not course._art.is_empty(), world + ": native cached art exists")
			column += 1
		row += 1
	for phase: float in [0.15, 0.50, 0.90]:
		for course: RushCourse in courses:
			course.animation_time = phase
			course.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var captured := root.get_texture().get_image()
		check(not captured.is_empty(), "native frame exists")
		check(captured.save_png(output.path_join("hazards_%.2f.png" % phase)) == OK, "native contact sheet saves")
	print("V28 native hazards: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
