extends SceneTree
## Render the production character API, then encode the frames with MovieWriter.
## --write-movie /absolute/gecko-motion.avi --fixed-fps 60 --script tests/capture_v27_motion.gd
const GECKO = preload("res://scripts/gecko.gd")
const SIZE := Vector2i(1280, 720)
const FRAMES := 180
const DELTA := 1.0 / 60.0
var actors: Array[Node2D] = []
var moving_holder: Node2D
var frame: int = 0
var ready_to_capture: bool = false

static func _static_init() -> void:
	if not "--write-movie" in OS.get_cmdline_args():
		return
	# MovieWriter reads these settings before SceneTree._initialize; CLI window
	# resolution alone does not override the recorded canvas dimensions.
	# These are process-local settings, never saved to project.godot.
	ProjectSettings.set_setting("display/window/size/viewport_width", 1280)
	ProjectSettings.set_setting("display/window/size/viewport_height", 720)
	ProjectSettings.set_setting("display/window/size/window_width_override", 1280)
	ProjectSettings.set_setting("display/window/size/window_height_override", 720)

class Stage extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color("0c1722"))
		for index in range(4):
			var box := StyleBoxFlat.new()
			box.bg_color = Color("172938")
			box.border_color = Color("2c4450")
			box.set_border_width_all(2)
			box.set_corner_radius_all(18)
			draw_style_box(box, Rect2(Vector2(14 + index * 320, 96), Vector2(292, 574)))
		for x: float in [49.0, 594.0, 689.0]:
			draw_rect(Rect2(x, 194, 13, 386), Color("42594d"))
			for y in range(200, 570, 25):
				draw_line(Vector2(x, y), Vector2(x + 13, y), Color("69816b"), 2.0, true)
		draw_line(Vector2(994, 578), Vector2(1242, 578), Color("69816b"), 3.0, true)
		draw_rect(Rect2(1018, 194, 13, 384), Color("42594d"))
		for y in range(200, 570, 25):
			draw_line(Vector2(1018, y), Vector2(1031, y), Color("69816b"), 2.0, true)

func _initialize() -> void:
	call_deferred("_setup")

func _label(text: String, at: Vector2, font_size: int, color: Color, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = Vector2(width, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://assets/fonts/OpenSans-Bold.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	root.add_child(label)

func _actor(id: String, at: Vector2, wall: int, parent: Node = null) -> Node2D:
	var gecko: Node2D = GECKO.new()
	gecko.set_skin(id)
	gecko.position = at
	gecko.scale = Vector2.ONE * 2.0
	gecko.side = wall
	gecko.mode = "run"
	gecko._clock = 2.8
	gecko.run_speed_factor = 1.0
	(parent if parent != null else root).add_child(gecko)
	gecko.set_process(false)
	actors.append(gecko)
	return gecko

func _setup() -> void:
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
	root.size = SIZE
	root.content_scale_size = SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.add_child(Stage.new())
	_label("GECKO RUSH · Новая анимация", Vector2(0, 20), 30, Color("dbedb4"), 1280)
	var names := ["Бег по стене", "Скины тоже двигаются", "Короткий язык", "Сон и пробуждение"]
	for index in range(4):
		_label(names[index], Vector2(index * 320 + 18, 120), 19, Color("e1ebdf"), 284)
	_actor("standard_green", Vector2(156, 383), -1)
	_actor("pirate_captain", Vector2(488, 383), 1)
	moving_holder = Node2D.new()
	moving_holder.position = Vector2(796, 383)
	root.add_child(moving_holder)
	_actor("standard_green", Vector2.ZERO, -1, moving_holder)
	_actor("standard_green", Vector2(1120, 390), -1)
	actors[3].mode = "sleep"
	_label("Живые лапы и хвост", Vector2(20, 617), 17, Color("a9c3b2"), 280)
	_label("Единый подвижный персонаж", Vector2(340, 617), 17, Color("a9c3b2"), 280)
	_label("Без растягивания за спиной", Vector2(660, 617), 17, Color("a9c3b2"), 280)
	_label("Одна цельная модель", Vector2(980, 617), 17, Color("a9c3b2"), 280)
	ready_to_capture = true
	process_frame.connect(_advance)

func _advance() -> void:
	if not ready_to_capture:
		return
	var time := float(frame) * DELTA
	actors[0]._process(DELTA)
	actors[1]._process(DELTA)
	# Reproduce rapid world travel while a following camera keeps the actor
	# on screen. The real tongue geometry must stay bounded in this situation.
	actors[2].position.y -= 18000.0 * DELTA
	moving_holder.position.y = 383.0 - actors[2].position.y
	if frame % 62 == 8:
		actors[2].eat_to(actors[2].get_mouth_position() + Vector2(-7, -82))
	actors[2]._process(DELTA)
	if time < 0.62:
		actors[3].mode = "sleep"
	elif time < 1.66:
		actors[3].set_launch_pose((time - 0.62) / 1.04)
	else:
		actors[3].mode = "run"
		actors[3].position.y = 390.0 - (time - 1.66) * 27.0
	actors[3]._process(DELTA)
	frame += 1
	if frame >= FRAMES:
		print("V27_MOTION: 180 native frames; production GeckoVisual, four live rigs, fixed60fps animation clock")
		quit(0)
	return
