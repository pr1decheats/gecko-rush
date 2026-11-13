class_name TriadaBoot
extends Node2D
## A short studio intro. The source artwork remains unchanged; only the
## symbol's atlas region rotates, while the wordmark stays upright.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LOGO: Texture2D = preload("res://assets/triada-games.png")
const LOGO_SHADER: Shader = preload("res://assets/triada-logo.gdshader")
const SOURCE_SIZE := Vector2(1170, 1075)
const SYMBOL_HEIGHT := 707.0
const SYMBOL_PIVOT := Vector2(585, 490)
const BACKGROUND := Color(1.0 / 255.0, 3.0 / 255.0, 15.0 / 255.0, 1.0)
const WIDTH_FRACTION := 0.55
const START_OPACITY := 0.18
const FADE_IN := 0.70
const FADE_OUT_START := 2.0
const DURATION := 2.5
const SKIP_AFTER := 0.3
const SKIP_FADE := 0.18
const SYMBOL_RADIANS_PER_SECOND := PI / 30.0 # Six degrees per second.

var elapsed := 0.0
var logo_opacity := START_OPACITY
var _skip_elapsed := -1.0
var _skip_start_opacity := 0.0
var _completed := false
var _background: ColorRect
var _logo_root: Node2D
var _symbol: Node2D
var _wordmark: Sprite2D
var _material: ShaderMaterial

func _ready() -> void:
	_background = ColorRect.new()
	_background.color = BACKGROUND
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_logo_root = Node2D.new()
	_logo_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_logo_root)
	_material = ShaderMaterial.new()
	_material.shader = LOGO_SHADER
	_symbol = Node2D.new()
	_symbol.position = SYMBOL_PIVOT - SOURCE_SIZE * 0.5
	_logo_root.add_child(_symbol)
	var symbol_texture := AtlasTexture.new()
	symbol_texture.atlas = LOGO
	symbol_texture.region = Rect2(0, 0, SOURCE_SIZE.x, SYMBOL_HEIGHT)
	var symbol_sprite := Sprite2D.new()
	symbol_sprite.texture = symbol_texture
	symbol_sprite.centered = false
	symbol_sprite.position = -SYMBOL_PIVOT
	symbol_sprite.material = _material
	_symbol.add_child(symbol_sprite)
	var wordmark_texture := AtlasTexture.new()
	wordmark_texture.atlas = LOGO
	wordmark_texture.region = Rect2(0, SYMBOL_HEIGHT, SOURCE_SIZE.x, SOURCE_SIZE.y - SYMBOL_HEIGHT)
	_wordmark = Sprite2D.new()
	_wordmark.texture = wordmark_texture
	_wordmark.centered = false
	_wordmark.position = Vector2(0, SYMBOL_HEIGHT) - SOURCE_SIZE * 0.5
	_wordmark.material = _material
	_logo_root.add_child(_wordmark)
	get_viewport().size_changed.connect(_layout)
	_layout()
	update_visuals(0.0)

func _layout() -> void:
	var frame := get_viewport_rect().size
	if frame.x <= 0.0 or frame.y <= 0.0:
		return
	_background.size = frame
	_logo_root.position = frame * 0.5
	var ratio := frame.x * WIDTH_FRACTION / SOURCE_SIZE.x
	_logo_root.scale = Vector2.ONE * ratio

static func opacity_at(seconds: float) -> float:
	if seconds < FADE_IN:
		return lerpf(START_OPACITY, 1.0, smoothstep(0.0, FADE_IN, seconds))
	if seconds < FADE_OUT_START:
		return 1.0
	return 1.0 - smoothstep(FADE_OUT_START, DURATION, seconds)

func update_visuals(seconds: float) -> void:
	logo_opacity = opacity_at(seconds)
	if _skip_elapsed >= 0.0:
		logo_opacity = _skip_start_opacity * (1.0 - smoothstep(0.0, SKIP_FADE, _skip_elapsed))
	_material.set_shader_parameter("opacity", logo_opacity)
	_symbol.rotation = SYMBOL_RADIANS_PER_SECOND * maxf(seconds, 0.0)
	# The lower atlas region is never rotated with the crystal symbol.
	_wordmark.rotation = 0.0

func _process(delta: float) -> void:
	if _completed:
		return
	elapsed += maxf(delta, 0.0)
	if _skip_elapsed >= 0.0:
		_skip_elapsed += maxf(delta, 0.0)
	update_visuals(elapsed)
	if elapsed >= DURATION or (_skip_elapsed >= SKIP_FADE):
		_completed = true
		set_process(false)
		_enter_game.call_deferred()

func request_skip() -> bool:
	if _completed or elapsed < SKIP_AFTER or _skip_elapsed >= 0.0:
		return false
	_skip_start_opacity = logo_opacity
	_skip_elapsed = 0.0
	return true

func _unhandled_input(event: InputEvent) -> void:
	var skip: bool = event is InputEventScreenTouch and event.pressed and event.index == 0
	skip = skip or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	skip = skip or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE])
	if skip and request_skip():
		get_viewport().set_input_as_handled()

func _enter_game() -> void:
	var error := get_tree().change_scene_to_packed(MAIN_SCENE)
	if error != OK:
		push_error("Could not open Gecko Rush after the studio intro: %s" % error)
		get_tree().quit(1)
