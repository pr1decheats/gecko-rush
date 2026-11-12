class_name RushCenterWall
extends Node2D
## Presentation only. The run controller owns the event clock, chance and lanes.

const WALL_X: float = RushTuning.CENTER_WALL_LEFT
const WALL_WIDTH: float = RushTuning.CENTER_WALL_WIDTH
const TILE_HEIGHT: float = 192.0
const VIEW_ABOVE: float = 1800.0
const VIEW_BELOW: float = 900.0
const SHARD_LIMIT: int = 48

var phase: String = "off" # off / preview / enter / ride / exit / miss
var phase_elapsed: float = 0.0
var ride_elapsed: float = 0.0
var player_height: float = 0.0
var wall_alpha: float = 1.0
var night_amount: float = 0.0
var animation_enabled: bool = true

static var _brick_texture: Texture2D
var _shards: Array[Dictionary] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_texture()

func reset_visual() -> void:
	phase = "off"
	phase_elapsed = 0.0
	ride_elapsed = 0.0
	player_height = 0.0
	wall_alpha = 1.0
	night_amount = 0.0
	_shards.clear()
	queue_redraw()

func _noise(value: int) -> float:
	return float((value * 1103515245 + 12345) & 0x7fffffff) / 2147483647.0

func _ensure_texture() -> void:
	if _brick_texture != null:
		return
	var image := Image.create(48, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color("617e79"))
	# Six softly lit masonry courses. The outer two pixels remain a crisp edge.
	for row in range(6):
		var y: int = row * 16
		image.fill_rect(Rect2i(2, y + 1, 44, 14), Color("77938a"))
		image.fill_rect(Rect2i(3, y + 2, 42, 2), Color("8aa599"))
		image.fill_rect(Rect2i(3, y + 13, 42, 2), Color("516d6b"))
		var seam: int = 16 if row % 2 == 0 else 31
		image.fill_rect(Rect2i(seam, y + 2, 2, 13), Color("526f6c"))
		for chip in range(4):
			var x: int = 5 + int(_noise(row * 19 + chip * 7 + 13) * 35.0)
			var cy: int = y + 5 + int(_noise(row * 23 + chip * 11 + 41) * 6.0)
			image.fill_rect(Rect2i(x, cy, 2 + chip % 2, 1), Color("6a887e"))
	image.fill_rect(Rect2i(0, 0, 2, 96), Color("3e5c60"))
	image.fill_rect(Rect2i(2, 0, 1, 96), Color("a2b3a0"))
	image.fill_rect(Rect2i(45, 0, 1, 96), Color("a2b3a0"))
	image.fill_rect(Rect2i(46, 0, 2, 96), Color("3e5c60"))
	_brick_texture = ImageTexture.create_from_image(image)

func _visible_alpha() -> float:
	var alpha: float = clampf(wall_alpha, 0.0, 1.0)
	match phase:
		"preview":
			var pulse: float = 0.5 + 0.5 * sin(phase_elapsed * TAU * 2.3)
			return alpha * smoothstep(0.0, 0.25, phase_elapsed) * lerpf(0.12, 0.40, pulse)
		"miss":
			var previous := lerpf(0.12, 0.40, 0.5 + 0.5 * sin(RushTuning.CENTER_PREVIEW_SECONDS * TAU * 2.3))
			return alpha * previous * (1.0 - smoothstep(0.0, 0.5, phase_elapsed))
		"enter":
			var previous := lerpf(0.12, 0.40, 0.5 + 0.5 * sin(RushTuning.CENTER_PREVIEW_SECONDS * TAU * 2.3))
			return alpha * lerpf(previous, 1.0, smoothstep(0.0, 0.45, phase_elapsed))
		"ride":
			return alpha
	return 0.0

func _draw() -> void:
	_ensure_texture()
	var alpha: float = _visible_alpha()
	if alpha > 0.001:
		var tint: Color = Color.WHITE.lerp(Color("91a7c3"), clampf(night_amount, 0.0, 1.0) * 0.5)
		tint.a = alpha
		var top: float = -player_height - VIEW_ABOVE
		var bottom: float = -player_height + VIEW_BELOW
		var first_tile: int = int(floor(top / TILE_HEIGHT))
		var last_tile: int = int(ceil(bottom / TILE_HEIGHT))
		for tile in range(first_tile, last_tile + 1):
			var y: float = float(tile) * TILE_HEIGHT
			draw_texture_rect(_brick_texture, Rect2(WALL_X, y, WALL_WIDTH, TILE_HEIGHT), false, tint)
			if phase == "ride" and ride_elapsed > 4.0:
				_draw_cracks(y, tile, clampf(ride_elapsed - 4.0, 0.0, 1.0), alpha)
	_draw_shards()

func _draw_cracks(y: float, tile: int, amount: float, alpha: float) -> void:
	var points := PackedVector2Array()
	var start_x: float = WALL_X + WALL_WIDTH * (0.30 + _noise(tile * 13 + 71) * 0.40)
	for index in range(9):
		var x: float = start_x + (_noise(tile * 31 + index * 23 + 53) - 0.5) * WALL_WIDTH * 0.65
		points.append(Vector2(clampf(x, WALL_X + 6.0, WALL_X + WALL_WIDTH - 6.0), y + index * 24.0))
	var length: float = amount * 8.0
	var color := Color(0.11, 0.20, 0.24, alpha * smoothstep(0.0, 0.15, amount))
	for index in range(8):
		var segment: float = clampf(length - index, 0.0, 1.0)
		if segment <= 0.0:
			break
		var endpoint: Vector2 = points[index].lerp(points[index + 1], segment)
		draw_line(points[index], endpoint, color, 3.0, false)
		if index in [2, 5] and segment > 0.6:
			var branch: Vector2 = points[index] + Vector2(-24.0 if index == 2 else 24.0, 17.0)
			draw_line(points[index], points[index].lerp(branch, amount), color, 2.0, false)

func shatter() -> void:
	# Fixed formulas keep visual debris independent from the course RNG.
	_shards.clear()
	for index in range(SHARD_LIMIT):
		var column: int = index % 6
		var row: int = index / 6
		var center := Vector2(WALL_X + (float(column) + 0.5) * WALL_WIDTH / 6.0, -player_height - 1150.0 + row * 260.0)
		var size := Vector2(6.0 + _noise(index * 11 + 23) * 6.0, 32.0 + _noise(index * 17 + 71) * 65.0)
		var outward: float = float(column) - 2.5
		_shards.append({
			"p": center,
			"v": Vector2(outward * 32.0 + (_noise(index * 29 + 13) - 0.5) * 56.0, 45.0 + _noise(index * 37 + 31) * 150.0),
			"size": size,
			"angle": (_noise(index * 41 + 53) - 0.5) * 0.20,
			"spin": (_noise(index * 43 + 17) - 0.5) * 3.4,
			"life": 2.0,
			"shade": 0.82 + _noise(index * 7 + 61) * 0.18,
		})
	phase = "exit"
	phase_elapsed = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not animation_enabled or _shards.is_empty():
		return
	for index in range(_shards.size() - 1, -1, -1):
		var shard: Dictionary = _shards[index]
		shard.life = float(shard.life) - delta
		shard.p += Vector2(shard.v) * delta
		shard.v.y += 710.0 * delta
		shard.angle = float(shard.angle) + float(shard.spin) * delta
		if float(shard.life) <= 0.0:
			_shards.remove_at(index)
	queue_redraw()

func _draw_shards() -> void:
	var night: float = clampf(night_amount, 0.0, 1.0)
	for shard in _shards:
		var color: Color = Color("77938a").lerp(Color("526f87"), night * 0.5) * float(shard.shade)
		color.a = minf(float(shard.life) / 0.45, 1.0)
		var size: Vector2 = shard.size
		draw_set_transform(shard.p, float(shard.angle))
		draw_rect(Rect2(-size * 0.5, size), Color(0.18, 0.30, 0.32, color.a))
		draw_rect(Rect2(-size * 0.5 + Vector2(2, 2), size - Vector2(4, 4)), color)
		var highlight: Color = color.lightened(0.18)
		highlight.a = color.a
		draw_rect(Rect2(-size * 0.5 + Vector2(2, 2), Vector2(size.x - 4.0, 3)), highlight)
	draw_set_transform(Vector2.ZERO)
