class_name JungleEnvironment
extends Node2D
## Original dense pixel scenery. All terrain artwork is rasterised once per world;
## a frame only places a small number of cached nearest-filtered textures.
## Gameplay origin: viewport_height - 520 + camera_height.

const LOGICAL_WIDTH: float = 1080.0
const WALL_LEFT: float = 270.0
const WALL_RIGHT: float = 810.0
const PIXEL_SCALE: float = 2.0
const TILE_HEIGHT: float = 320.0
const SKY_IMAGE_HEIGHT: int = 1536
const SCENERY_HEIGHT: int = 1024

var camera_height: float = 0.0
var viewport_height: float = 1920.0
var time: float = 0.0
var menu_blend: float = 1.0
var world_id: String = "jungle"
var night_amount: float = 0.0
var theme: String = "dark"
# A temporary centre wall can fade the side terrain without tinting the sky.
var side_walls_visibility: float = 1.0
var _active: Dictionary = {}
var _world_cache: Dictionary = {}
var _fly_frames: Array[Texture2D] = []
var _mosquito_frames: Array[Texture2D] = []
var _butterfly_frames: Array[Texture2D] = []

const PALETTES: Dictionary = {
	"jungle": {"sky": "75c8b7", "horizon": "d6e7a9", "far": "84ad8e", "middle": "568e78", "near": "326b65", "rock": "65776a", "light": "a7b58a", "dark": "293e3d", "leaf": "347348", "leaf_light": "86bd52", "accent": "e6cd75"},
	"canyon": {"sky": "d89e86", "horizon": "f3d99d", "far": "cf9f84", "middle": "b5816e", "near": "855f61", "rock": "a56f58", "light": "e3ae7d", "dark": "503d42", "leaf": "81734b", "leaf_light": "c1ad67", "accent": "f4ca77"},
	"ice": {"sky": "82bed4", "horizon": "e2f1df", "far": "accbd1", "middle": "85b0c1", "near": "5f8fa8", "rock": "6f9db7", "light": "c9eff1", "dark": "344c70", "leaf": "659ead", "leaf_light": "e5fbf1", "accent": "a9f2e4"},
	"crystal": {"sky": "212746", "horizon": "4f597e", "far": "42466e", "middle": "383f66", "near": "292f53", "rock": "4a4c70", "light": "8888b5", "dark": "20243e", "leaf": "547e8c", "leaf_light": "98e0d3", "accent": "76e5d9"},
	"volcano": {"sky": "754653", "horizon": "d39370", "far": "a46d69", "middle": "7b515e", "near": "513b50", "rock": "554956", "light": "9d7874", "dark": "2b293f", "leaf": "70504f", "leaf_light": "ca7d5b", "accent": "ffb45c"},
	"sky": {"sky": "6cb6d4", "horizon": "d6ead0", "far": "a7d0d0", "middle": "76adae", "near": "508e99", "rock": "6d9690", "light": "c3d3a6", "dark": "334c60", "leaf": "568661", "leaf_light": "a8ce76", "accent": "f1dca1"}
}

const NIGHT_PALETTES: Dictionary = {
	"jungle": {"sky": "0b1531", "horizon": "254458", "far": "24475b", "middle": "1b3b4d", "near": "112e3e", "rock": "2b4554", "light": "63828a", "dark": "111f36", "leaf": "24525a", "leaf_light": "5a9684", "accent": "c5eda1"},
	"canyon": {"sky": "141731", "horizon": "4c4057", "far": "4c465d", "middle": "393b55", "near": "2b3049", "rock": "58475c", "light": "8a758a", "dark": "25243e", "leaf": "56535b", "leaf_light": "9c8c83", "accent": "e4c990"},
	"ice": {"sky": "101b3d", "horizon": "34556e", "far": "345574", "middle": "2b4968", "near": "203d5c", "rock": "3b607f", "light": "83b9ce", "dark": "1b294b", "leaf": "4d7b92", "leaf_light": "b4dce2", "accent": "bbefe3"},
	"crystal": {"sky": "090d24", "horizon": "252b57", "far": "242952", "middle": "1e2448", "near": "151c39", "rock": "303553", "light": "626a93", "dark": "11162d", "leaf": "3d657c", "leaf_light": "6cc4c8", "accent": "8cfce4"},
	"volcano": {"sky": "111326", "horizon": "493247", "far": "40324a", "middle": "30273f", "near": "211f36", "rock": "3a3447", "light": "765b6d", "dark": "17192e", "leaf": "5b3b48", "leaf_light": "c26951", "accent": "ffae56"},
	"sky": {"sky": "111c3d", "horizon": "425471", "far": "405c78", "middle": "2e4a68", "near": "213c58", "rock": "3f6071", "light": "88a4a3", "dark": "1d2c47", "leaf": "3b6b73", "leaf_light": "7faaa0", "accent": "e3e7b3"}
}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_insects()
	set_world(world_id)

func set_world(id: String) -> void:
	world_id = id if PALETTES.has(id) else "jungle"
	if not _world_cache.has(world_id):
		# Keep two visited worlds, rather than retaining six full-height backgrounds.
		if _world_cache.size() >= 2:
			_world_cache.erase(_world_cache.keys()[0])
		_world_cache[world_id] = _build_world(world_id)
	_active = _world_cache[world_id]
	queue_redraw()

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _c(palette: Dictionary, key: String) -> Color:
	return Color(str(palette[key]))

func _background_palette(palette: Dictionary, night: bool) -> Dictionary:
	# Compress scenery contrast at texture-build time. Keep the untouched rock
	# palette for the playable walls, so their silhouette stays easy to read.
	var subdued: Dictionary = palette.duplicate()
	var sky: Color = _c(palette, "sky")
	var horizon: Color = _c(palette, "horizon")
	var anchor: Color = sky.lerp(horizon, 0.28)
	var brightness: float = 0.93 if night else 0.82
	anchor = Color.from_hsv(anchor.h, anchor.s * 0.64, anchor.v * brightness)
	for key: String in palette:
		var original: Color = _c(palette, key)
		var color: Color = Color.from_hsv(original.h, original.s * 0.64, original.v * brightness)
		var compression: float = 0.42 if key in ["sky", "horizon"] else 0.57
		subdued[key] = color.lerp(anchor, compression).to_html(false)
	return subdued

func _noise(value: int) -> float:
	var bits: int = (value * 1103515245 + 12345) & 0x7fffffff
	return float(bits % 65521) / 65521.0

func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	var area := Rect2i(x, y, width, height).intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if area.has_area():
		image.fill_rect(area, color)

func _line(image: Image, from: Vector2i, to: Vector2i, color: Color, thickness: int = 1) -> void:
	var x: int = from.x
	var y: int = from.y
	var dx: int = absi(to.x - x)
	var dy: int = -absi(to.y - y)
	var sx: int = 1 if x < to.x else -1
	var sy: int = 1 if y < to.y else -1
	var error: int = dx + dy
	while true:
		_rect(image, x, y, thickness, thickness, color)
		if x == to.x and y == to.y:
			break
		var doubled: int = error * 2
		if doubled >= dy:
			error += dy
			x += sx
		if doubled <= dx:
			error += dx
			y += sy

func _polygon(image: Image, points: Array[Vector2i], color: Color) -> void:
	var min_y: int = image.get_height() - 1
	var max_y: int = 0
	for point: Vector2i in points:
		min_y = mini(min_y, point.y)
		max_y = maxi(max_y, point.y)
	min_y = maxi(0, min_y)
	max_y = mini(image.get_height() - 1, max_y)
	for y in range(min_y, max_y + 1):
		var crossings: Array[int] = []
		for index in range(points.size()):
			var a: Vector2i = points[index]
			var b: Vector2i = points[(index + 1) % points.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				crossings.append(int(a.x + float(y - a.y) * float(b.x - a.x) / float(b.y - a.y)))
		crossings.sort()
		for index in range(0, crossings.size() - 1, 2):
			_rect(image, crossings[index], y, crossings[index + 1] - crossings[index] + 1, 1, color)

func _cloud(image: Image, at: Vector2i, width: int, color: Color) -> void:
	_rect(image, at.x + width / 8, at.y, width * 3 / 4, 4, color)
	_rect(image, at.x, at.y + 4, width, 7, color)
	_rect(image, at.x + width / 10, at.y + 11, width * 4 / 5, 4, color)
	_rect(image, at.x + width / 3, at.y - 7, width / 3, 10, color)

func _conifer(image: Image, x: int, y: int, height: int, color: Color) -> void:
	_rect(image, x - 2, y - height, 4, height, color.darkened(0.08))
	for tier in range(5):
		var py: int = y - height + tier * height / 6
		var half: int = 7 + tier * height / 13
		_polygon(image, [Vector2i(x, py - 10), Vector2i(x - half, py + height / 4), Vector2i(x + half, py + height / 4)], color)

func _jungle_tree(image: Image, x: int, y: int, height: int, color: Color, salt: int) -> void:
	_rect(image, x - 3, y - height + 20, 6, height, color.darkened(0.04))
	_line(image, Vector2i(x, y - height + 55), Vector2i(x - 18, y - height + 26), color, 3)
	_line(image, Vector2i(x, y - height + 37), Vector2i(x + 22, y - height + 9), color, 3)
	for crown in range(4):
		var px: int = x - 41 + crown * 24
		var py: int = y - height + int(_noise(salt + crown) * 20.0)
		_rect(image, px + 9, py - 4, 34, 8, color)
		_rect(image, px, py + 4, 52, 12, color)
		_rect(image, px + 5, py + 16, 44, 7, color)

func _sky(id: String, palette: Dictionary, night: bool) -> Texture2D:
	var image := Image.create(540, SKY_IMAGE_HEIGHT, false, Image.FORMAT_RGBA8)
	var top := _c(palette, "sky")
	var bottom := _c(palette, "horizon")
	for y in range(SKY_IMAGE_HEIGHT):
		# Ordered, close colour steps keep the atmosphere crisp at the native pixel grid.
		var fraction: float = minf(float(y) / 1080.0, 1.0)
		var tint := top.lerp(bottom, floorf(fraction * 32.0) / 32.0)
		_rect(image, 0, y, 540, 1, tint)
		if y % 12 == 0:
			for x in range(0, 540, 12):
				_rect(image, x + (y % 24) / 6, y, 2, 1, tint.lightened(0.014))
	if id == "ice":
		# Aurora is an atmospheric ribbon, never a row of triangular mountains.
		for ribbon in range(3):
			for x in range(540):
				var y: int = 136 + ribbon * 33 + int(sin(float(x) * 0.011 + ribbon * 0.7) * 47.0)
				var tint := top.lerp(_c(palette, "accent"), 0.11 if not night else 0.24)
				_rect(image, x, y, 1, 4 + ribbon * 2, tint)
				if x % 5 == 0:
					_rect(image, x, y + 6, 1, 15, tint.lerp(top, 0.5))
	if night and id in ["jungle", "canyon", "ice", "sky"]:
		for index in range(32):
			var x: int = 12 + int(_noise(index * 13 + 18) * 516.0)
			var y: int = 24 + int(_noise(index * 37 + 7) * 650.0)
			var tint := _c(palette, "light").lerp(top, 0.36)
			_rect(image, x, y, 1 + index % 2, 1, tint)
	return ImageTexture.create_from_image(image)

func _scenery(id: String, palette: Dictionary, night: bool, layer: int) -> Texture2D:
	var image := Image.create(540, SCENERY_HEIGHT * 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	match id:
		"jungle": _jungle_scenery(image, palette, layer)
		"canyon": _canyon_scenery(image, palette, layer)
		"ice": _ice_scenery(image, palette, layer)
		"crystal": _crystal_scenery(image, palette, layer)
		"volcano": _volcano_scenery(image, palette, layer)
		"sky": _sky_scenery(image, palette, layer, night)
	# Wrap overflow pixels while rasterising, so a gallery or hanging root that
	# crosses the tile boundary never develops a moving horizontal cut.
	var overflow := image.get_region(Rect2i(0, SCENERY_HEIGHT, 540, SCENERY_HEIGHT))
	image.blend_rect(overflow, Rect2i(0, 0, 540, SCENERY_HEIGHT), Vector2i.ZERO)
	image.crop(540, SCENERY_HEIGHT)
	return ImageTexture.create_from_image(image)

func _stone_detail(image: Image, at: Vector2i, width: int, height: int, color: Color, salt: int) -> void:
	# Close-valued stone chips provide detail without competing with live obstacles.
	for chip in range(maxi(6, width * height / 170)):
		var x: int = at.x + int(_noise(salt + chip * 23) * width)
		var y: int = at.y + int(_noise(salt * 7 + chip * 41) * height)
		_rect(image, x, y, 2 + chip % 5, 1, color.lightened(0.045) if chip % 3 else color.darkened(0.035))

func _leaf_crown(image: Image, at: Vector2i, width: int, color: Color, salt: int) -> void:
	for tuft in range(8):
		var x: int = at.x + tuft * width / 9
		var y: int = at.y + int(_noise(salt + tuft * 13) * 18.0)
		_rect(image, x + 4, y - 4, width / 4, 7, color)
		_rect(image, x, y + 3, width / 3, 11, color)
		_rect(image, x + 5, y + 14, width / 4, 5, color)
		_rect(image, x + 5, y + 1, width / 6, 1, color.lightened(0.045))
		if tuft % 2 == 0:
			_rect(image, x + 11, y + 19, 2, 8 + tuft, color)
		for leaf in range(7):
			var lx: int = x + 3 + int(_noise(salt + tuft * 57 + leaf * 29) * float(width / 4))
			var ly: int = y + 4 + int(_noise(salt * 3 + leaf * 19 + tuft) * 12.0)
			_rect(image, lx, ly, 3 + leaf % 4, 1, color.lightened(0.035 + float(leaf % 2) * 0.02))
			_rect(image, lx + 2, ly + 2, 2, 1, color.darkened(0.025))

func _jungle_scenery(image: Image, palette: Dictionary, layer: int) -> void:
	var stone := _c(palette, "middle" if layer == 0 else "near")
	var leaf := stone.lerp(_c(palette, "leaf"), 0.3)
	if layer == 0:
		# Continuous trunks, overlapping canopy shelves and aerial roots form a forest.
		for tree in range(9):
			var x: int = tree * 69 - 20 + int(_noise(tree * 31) * 16.0)
			var w: int = 10 + tree % 3 * 6
			_rect(image, x, 0, w, SCENERY_HEIGHT, stone)
			_rect(image, x + 3, 0, 2, SCENERY_HEIGHT, stone.lightened(0.025))
			for tier in range(4):
				var y: int = 48 + tier * 277 + int(_noise(tree * 17 + tier) * 60.0)
				_line(image, Vector2i(x + w / 2, y + 68), Vector2i(x - 38, y + 20), stone, 5)
				_line(image, Vector2i(x + w / 2, y + 71), Vector2i(x + 53, y + 7), stone, 4)
				_leaf_crown(image, Vector2i(x - 54, y), 118, leaf, tree * 43 + tier)
				_line(image, Vector2i(x + 45, y + 17), Vector2i(x + 40, y + 88), leaf, 1)
	else:
		# Abandoned lintels and broken columns are threaded with roots and ivy.
		for ruin in range(5):
			var x: int = -30 + ruin % 3 * 210
			var y: int = 205 + ruin / 3 * 490 + ruin % 3 * 57
			var w: int = 133 + ruin % 2 * 20
			_rect(image, x, y, w, 17, stone)
			_rect(image, x + 6, y - 7, w - 12, 7, stone.lightened(0.035))
			_rect(image, x + 6, y + 17, 20, 162, stone)
			_rect(image, x + w - 27, y + 17, 21, 127 + ruin % 2 * 34, stone)
			for carving in range(9):
				_rect(image, x + 9 + carving * 13, y + 5, 7, 5, stone.darkened(0.055))
				_rect(image, x + 10 + carving * 13, y + 6, 5, 1, stone.lightened(0.03))
			for seam in range(5):
				_rect(image, x + 7, y + 28 + seam * 29, 19, 2, stone.darkened(0.05))
				_rect(image, x + w - 26, y + 24 + seam * 27, 20, 1, stone.darkened(0.055))
			_stone_detail(image, Vector2i(x + 7, y + 20), 17, 150, stone, ruin * 19)
			_leaf_crown(image, Vector2i(x - 7, y - 20), w, leaf, ruin * 71)
			for vine in range(6):
				var vx: int = x + 12 + vine * 22
				var vy: int = y + 10
				_line(image, Vector2i(vx, vy), Vector2i(vx - 4 + vine % 3 * 4, vy + 38 + vine % 3 * 18), leaf, 1)
				_rect(image, vx - 3, vy + 16, 3, 2, leaf.lightened(0.04))
				_rect(image, vx + 1, vy + 27, 4, 2, leaf)
			_line(image, Vector2i(x + 13, y + 87), Vector2i(x + 55, y + 147), leaf, 3)
			_line(image, Vector2i(x + 55, y + 147), Vector2i(x + 91, y + 159), leaf, 2)

func _mesa(image: Image, at: Vector2i, width: int, height: int, color: Color, salt: int, arch: bool) -> void:
	var x: int = at.x
	var y: int = at.y
	_polygon(image, [Vector2i(x + 15, y), Vector2i(x + width - 22, y), Vector2i(x + width - 18, y + 15), Vector2i(x + width - 7, y + 15), Vector2i(x + width - 7, y + 64), Vector2i(x + width, y + 94), Vector2i(x + width - 8, y + height), Vector2i(x + 4, y + height), Vector2i(x, y + 86), Vector2i(x + 9, y + 54), Vector2i(x + 9, y + 14), Vector2i(x + 15, y + 14)], color)
	for band in range(12):
		var by: int = y + 13 + band * (height - 24) / 12
		var inset: int = 10 if band < 3 else 6
		_rect(image, x + inset, by, width - inset * 2, 2 + band % 3, color.lightened(0.03) if band % 3 else color.darkened(0.055))
		_rect(image, x + inset + 4 + band % 4 * 7, by + 4, width / 3, 1, color.lightened(0.04))
	_stone_detail(image, Vector2i(x + 13, y + 16), width - 30, height - 25, color, salt)
	if arch:
		# A stepped opening cuts through sandstone, revealing the farther scene.
		var cx: int = x + width / 2
		var roof: int = y + height / 3
		_polygon(image, [Vector2i(cx - width / 5, y + height + 1), Vector2i(cx - width / 5, roof + 31), Vector2i(cx - width / 7, roof + 10), Vector2i(cx - 6, roof), Vector2i(cx + 9, roof), Vector2i(cx + width / 6, roof + 15), Vector2i(cx + width / 5, roof + 40), Vector2i(cx + width / 5, y + height + 1)], Color.TRANSPARENT)

func _canyon_scenery(image: Image, palette: Dictionary, layer: int) -> void:
	var stone := _c(palette, "far" if layer == 0 else "middle")
	for mesa in range(7 if layer == 0 else 4):
		var x: int = -48 + mesa % 4 * 175 + int(_noise(mesa * 19 + layer) * 25.0)
		var y: int = 46 + mesa / 4 * 500 + mesa % 4 * 75 + layer * 139
		var width: int = 125 + mesa % 3 * 25
		_mesa(image, Vector2i(x, y), width, 284 + mesa % 3 * 67, stone, mesa * 97, layer == 1 or mesa % 3 == 0)
		if layer == 1:
			# Wind-scoured ledges, not vegetation-covered mountain peaks.
			_rect(image, x - 4, y + 11, width + 8, 4, stone.lightened(0.065))
			for crack in range(4):
				var p := Vector2i(x + 28 + crack * 24, y + 29)
				_line(image, p, p + Vector2i(4, 27 + crack * 8), stone.darkened(0.08))
				_line(image, p + Vector2i(4, 27 + crack * 8), p + Vector2i(-2, 42 + crack * 8), stone.darkened(0.08))

func _ice_spire(image: Image, at: Vector2i, width: int, height: int, color: Color, hanging: bool = false) -> void:
	var tip: int = -height if not hanging else height
	if height > 120 and not hanging:
		# Tall frozen columns have broken flat caps, distinct from alpine peaks.
		_polygon(image, [at + Vector2i(-width / 2, 0), at + Vector2i(-width / 2 + 6, tip + 21), at + Vector2i(-width / 5, tip + 7), at + Vector2i(-width / 6, tip), at + Vector2i(width / 4, tip + 4), at + Vector2i(width / 2 - 5, tip + 28), at + Vector2i(width / 2, 0)], color)
		_rect(image, at.x - width / 6, at.y + tip + 3, width * 2 / 5, 2, color.lightened(0.065))
	else:
		_polygon(image, [at + Vector2i(-width / 2, 0), at + Vector2i(-width / 3, tip * 3 / 4), at + Vector2i(0, tip), at + Vector2i(width / 4, tip * 4 / 5), at + Vector2i(width / 2, 0)], color)
	_polygon(image, [at + Vector2i(0, tip), at + Vector2i(width / 4, tip * 4 / 5), at + Vector2i(width / 2, 0), at + Vector2i(3, 0)], color.lightened(0.045))
	_line(image, at + Vector2i(0, tip + (5 if not hanging else -5)), at + Vector2i(3, -6 if not hanging else 6), color.lightened(0.075))
	for fracture in range(3):
		var p := at + Vector2i(-width / 4 + fracture * width / 6, tip / 5 - fracture * tip / 5)
		_line(image, p, p + Vector2i(width / 5, tip / 12), color.lightened(0.06))

func _ice_scenery(image: Image, palette: Dictionary, layer: int) -> void:
	var ice := _c(palette, "far" if layer == 0 else "middle")
	if layer == 0:
		for pillar in range(12):
			var x: int = -15 + pillar % 6 * 109
			var y: int = 465 + pillar / 6 * 540 + pillar % 3 * 32
			_ice_spire(image, Vector2i(x, y), 65 + pillar % 3 * 14, 270 + pillar % 4 * 51, ice)
			_rect(image, x - 34, y, 70, 3, ice.lightened(0.065))
	else:
		# Frozen galleries: horizontal ice roofs, descending teeth and fractured columns.
		for shelf in range(4):
			var y: int = 56 + shelf * 286
			var x: int = -15 if shelf % 2 == 0 else 312
			_rect(image, x, y, 245, 12, ice)
			_rect(image, x + 12, y - 7, 210, 7, ice.lightened(0.035))
			for tooth in range(7):
				_ice_spire(image, Vector2i(x + 17 + tooth * 33, y + 12), 20 + tooth % 3 * 9, 23 + tooth % 4 * 20, ice, true)
			_ice_spire(image, Vector2i(x + 73, y + 259), 59, 212, ice.darkened(0.035))
			_line(image, Vector2i(x + 57, y + 96), Vector2i(x + 79, y + 125), ice.lightened(0.07))

func _gem(image: Image, at: Vector2i, width: int, height: int, color: Color) -> void:
	_polygon(image, [at + Vector2i(-width / 2, 0), at + Vector2i(-width / 2, -height * 3 / 4), at + Vector2i(0, -height), at + Vector2i(width / 2, -height * 3 / 4), at + Vector2i(width / 2, 0)], color)
	_polygon(image, [at, at + Vector2i(0, -height), at + Vector2i(width / 2, -height * 3 / 4), at + Vector2i(width / 2, 0)], color.lightened(0.06))
	_line(image, at + Vector2i(0, -height + 4), at + Vector2i(0, -3), color.lightened(0.09))
	_line(image, at + Vector2i(-width / 2 + 2, -height * 3 / 4), at + Vector2i(0, -height * 2 / 3), color.darkened(0.045))

func _crystal_scenery(image: Image, palette: Dictionary, layer: int) -> void:
	var stone := _c(palette, "far" if layer == 0 else "middle")
	var gem := stone.lerp(_c(palette, "leaf_light"), 0.32)
	for arch in range(4):
		var x: int = -52 + arch % 2 * 315 + layer * 41
		var y: int = 83 + arch / 2 * 574 + arch % 2 * 116
		if layer == 0:
			# Interlocking subterranean ribs, hollow geodes and stalactite ceilings.
			_polygon(image, [Vector2i(x, y + 350), Vector2i(x + 13, y + 77), Vector2i(x + 58, y + 21), Vector2i(x + 97, y), Vector2i(x + 162, y), Vector2i(x + 220, y + 46), Vector2i(x + 245, y + 141), Vector2i(x + 260, y + 350), Vector2i(x + 221, y + 350), Vector2i(x + 208, y + 147), Vector2i(x + 188, y + 79), Vector2i(x + 151, y + 47), Vector2i(x + 100, y + 42), Vector2i(x + 63, y + 67), Vector2i(x + 46, y + 126), Vector2i(x + 35, y + 350)], stone)
			for tooth in range(7):
				var p := Vector2i(x + 50 + tooth * 24, y + 46 + absi(3 - tooth) * 8)
				_polygon(image, [p, p + Vector2i(13, 1), p + Vector2i(6, 18 + tooth % 3 * 13)], stone)
			_stone_detail(image, Vector2i(x + 12, y + 138), 20, 205, stone, arch * 63)
		else:
			var base := Vector2i(183 + arch % 2 * 143, y + 225)
			_polygon(image, [base + Vector2i(-48, 11), base + Vector2i(-43, -12), base + Vector2i(-17, -27), base + Vector2i(35, -22), base + Vector2i(58, 4), base + Vector2i(43, 18)], stone)
			for crystal in range(7):
				var tint: Color = gem if crystal % 3 else gem.lerp(Color("8c78a1"), 0.24)
				_gem(image, base + Vector2i(-36 + crystal * 13, -6), 12 + crystal % 3 * 4, 29 + crystal % 4 * 19, tint)
			# Short faceted seams describe a geode rather than a celestial skyline.
			for vein in range(3):
				_line(image, base + Vector2i(-31 + vein * 21, 13), base + Vector2i(-11 + vein * 21, 7), gem.darkened(0.08))

func _volcano_scenery(image: Image, palette: Dictionary, layer: int) -> void:
	var stone := _c(palette, "far" if layer == 0 else "near")
	var lava := stone.lerp(_c(palette, "accent"), 0.25 if layer == 0 else 0.30)
	for shelf in range(4):
		var x: int = -42 + shelf % 2 * 315
		var y: int = 64 + shelf / 2 * 578 + shelf % 2 * 146 + layer * 93
		var width: int = 283 if layer == 0 else 194
		var height: int = 235 if layer == 0 else 176
		# Hexagonal basalt columns terminate in a broken horizontal escarpment.
		for column in range(width / 21):
			var cy: int = y + int(_noise(column * 39 + shelf * 57) * 40.0)
			var cx: int = x + column * 21
			_polygon(image, [Vector2i(cx, cy + 5), Vector2i(cx + 10, cy), Vector2i(cx + 20, cy + 6), Vector2i(cx + 20, y + height), Vector2i(cx + 1, y + height - 4)], stone)
			_rect(image, cx + 2, cy + 9, 2, y + height - cy - 17, stone.lightened(0.035))
			_rect(image, cx + 18, cy + 8, 2, y + height - cy - 10, stone.darkened(0.045))
			for seam in range(3):
				_rect(image, cx + 3, cy + 28 + seam * 43, 14, 1, stone.darkened(0.055))
		var vent := Vector2i(x + width / 2, y + height - 35)
		_line(image, vent + Vector2i(-width / 3, 0), vent + Vector2i(-7, 9), lava.darkened(0.07), 3)
		_line(image, vent + Vector2i(-7, 9), vent + Vector2i(width / 3, 3), lava, 2)
		if layer == 1:
			_line(image, vent + Vector2i(8, 5), vent + Vector2i(1, 39), lava, 2)
			_line(image, vent + Vector2i(1, 39), vent + Vector2i(9, 64), lava.darkened(0.1), 1)
			for smoke in range(4):
				_cloud(image, vent + Vector2i(-28 + smoke % 2 * 9, -34 - smoke * 31), 48 + smoke * 11, stone.lightened(0.045))

func _sky_scenery(image: Image, palette: Dictionary, layer: int, night: bool) -> void:
	var cloud := _c(palette, "far" if layer == 0 else "middle")
	var stone := _c(palette, "near")
	if layer == 0:
		# Broad cloud banks and storm undersides have no solid mountain silhouette.
		for bank in range(8):
			var x: int = -75 + bank % 3 * 223
			var y: int = 71 + bank / 3 * 359 + bank % 3 * 74
			_cloud(image, Vector2i(x, y), 215 + bank % 3 * 34, cloud)
			_cloud(image, Vector2i(x + 28, y + 13), 182, cloud.darkened(0.035))
			_rect(image, x + 40, y + 3, 96, 1, cloud.lightened(0.04))
			if night:
				_rect(image, x + 71, y + 28, 77, 2, cloud.lightened(0.025))
	else:
		for island in range(6):
			var x: int = -45 + island % 3 * 217
			var y: int = 186 + island / 3 * 551 + island % 3 * 101
			var width: int = 97 + island % 3 * 19
			_polygon(image, [Vector2i(x, y), Vector2i(x + width, y), Vector2i(x + width - 8, y + 18), Vector2i(x + width / 2 + 12, y + 41), Vector2i(x + width / 2, y + 76), Vector2i(x + width / 2 - 13, y + 41), Vector2i(x + 9, y + 20)], stone)
			_rect(image, x - 3, y - 6, width + 6, 7, stone.lerp(_c(palette, "leaf"), 0.3))
			_rect(image, x + 5, y + 8, width - 10, 2, stone.lightened(0.045))
			for pillar in range(3):
				var px: int = x + 17 + pillar * 26
				_rect(image, px, y - 58 + pillar % 2 * 6, 9, 52 - pillar % 2 * 6, stone)
				_rect(image, px - 3, y - 62 + pillar % 2 * 6, 15, 5, stone.lightened(0.04))
				_rect(image, px + 2, y - 54 + pillar % 2 * 6, 1, 42 - pillar % 2 * 6, stone.lightened(0.07))
			_rect(image, x + 11, y - 68, 83, 5, stone)
			_rect(image, x + 19, y - 73, 67, 5, stone.lightened(0.025))
			# Hanging chain remnants reinforce the airborne architecture.
			for link in range(10):
				_rect(image, x + width - 11 + link % 2, y + 19 + link * 5, 2, 3, stone.lightened(0.035))
			_cloud(image, Vector2i(x - 24, y + 42), width + 42, cloud)

func _cloud_texture(palette: Dictionary, id: String) -> Texture2D:
	var image := Image.create(170, 55, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var tint := _c(palette, "light").lerp(_c(palette, "far"), 0.6)
	if id == "volcano":
		tint = _c(palette, "far")
	_cloud(image, Vector2i(8, 22), 148, tint)
	_cloud(image, Vector2i(30, 13), 95, tint.lightened(0.025))
	_rect(image, 40, 15, 37, 1, tint.lightened(0.05))
	_rect(image, 17, 37, 123, 2, tint.darkened(0.04))
	return ImageTexture.create_from_image(image)

func _brick(image: Image, at: Vector2i, width: int, height: int, palette: Dictionary, salt: int) -> void:
	var rock: Color = _c(palette, "rock").lightened((_noise(salt) - 0.5) * 0.15)
	var light := _c(palette, "light")
	var dark := _c(palette, "dark")
	_rect(image, at.x + 2, at.y, width - 4, height, dark)
	_rect(image, at.x, at.y + 3, width, height - 6, dark)
	_rect(image, at.x + 2, at.y + 2, width - 4, height - 5, rock)
	_rect(image, at.x + 1, at.y + 5, width - 2, height - 10, rock)
	_rect(image, at.x + 4, at.y + 3, width - 9, 2, light.darkened(0.12))
	_rect(image, at.x + 2, at.y + 5, 2, height - 12, light.darkened(0.20))
	_rect(image, at.x + 4, at.y + height - 5, width - 7, 2, rock.darkened(0.22))
	_rect(image, at.x + width - 5, at.y + 7, 2, height - 14, rock.darkened(0.16))
	for dot in range(16):
		var x: int = at.x + 5 + int(_noise(salt * 31 + dot * 13) * float(maxi(1, width - 11)))
		var y: int = at.y + 7 + int(_noise(salt * 17 + dot * 29) * float(maxi(1, height - 16)))
		_rect(image, x, y, 1 + dot % 3, 1, rock.lightened(0.065) if dot % 3 == 0 else rock.darkened(0.08))
	if _noise(salt + 44) > 0.55:
		var x: int = at.x + width / 2
		var y: int = at.y + 9
		_line(image, Vector2i(x, y), Vector2i(x + 5, y + 4), rock.darkened(0.26))
		_line(image, Vector2i(x + 5, y + 4), Vector2i(x + 2, y + 10), rock.darkened(0.26))

func _moss(image: Image, x: int, y: int, width: int, palette: Dictionary, salt: int) -> void:
	var leaf := _c(palette, "leaf")
	for index in range(0, width, 4):
		var drop: int = 2 + int(_noise(index + salt) * 8.0)
		_rect(image, x + index, y, 4, drop, leaf.darkened(0.22))
		_rect(image, x + index, y - 1, 4, maxi(1, drop - 3), leaf)
		if index % 12 == 0:
			_rect(image, x + index + 1, y - 1, 2, 2, _c(palette, "leaf_light"))

func _wall_tile(id: String, palette: Dictionary, variant: int) -> Texture2D:
	var image := Image.create(135, 160, false, Image.FORMAT_RGBA8)
	image.fill(_c(palette, "dark"))
	for row in range(5):
		var offset: int = -18 if row % 2 == 0 else -40
		for column in range(4):
			var at := Vector2i(offset + column * 48, row * 32)
			_brick(image, at, 47, 31, palette, variant * 117 + row * 37 + column * 19)
			if id in ["jungle", "sky"] and (column + row + variant) % 3 == 0:
				_moss(image, at.x + 3, at.y + 2, 30, palette, row + variant * 4)
			elif id == "canyon":
				_rect(image, at.x + 5, at.y + 17, 35, 1, _c(palette, "light").darkened(0.25))
				_rect(image, at.x + 8, at.y + 21, 31, 1, _c(palette, "dark").lightened(0.1))
			elif id == "ice":
				_rect(image, at.x + 3, at.y + 2, 36, 2, _c(palette, "leaf_light"))
				_line(image, at + Vector2i(16, 7), at + Vector2i(27, 18), _c(palette, "accent"))
				_line(image, at + Vector2i(27, 18), at + Vector2i(23, 28), _c(palette, "light"))
	# A shaded inner edge gives a narrow, strongly readable vertical corridor.
	_rect(image, 128, 0, 7, 160, _c(palette, "rock").lightened(0.10))
	_rect(image, 133, 0, 2, 160, _c(palette, "light").darkened(0.08))
	_rect(image, 125, 0, 3, 160, _c(palette, "dark").lightened(0.05))
	if id in ["jungle", "sky"]:
		for patch in range(6):
			var y: int = 12 + patch * 27 + variant * 3
			_moss(image, 118, y, 16, palette, patch * 17)
			_rect(image, 131, y + 4, 2, 13, _c(palette, "leaf"))
	elif id == "crystal":
		for gem in range(4):
			var p := Vector2i(97 + gem % 2 * 16, 20 + gem * 35)
			var color := _c(palette, "accent") if gem % 2 == 0 else Color("b095dd").darkened(0.15)
			_polygon(image, [p + Vector2i(-5, 14), p + Vector2i(-5, -6), p + Vector2i(0, -15), p + Vector2i(6, -5), p + Vector2i(6, 13)], color.darkened(0.12))
			_line(image, p + Vector2i(0, -12), p + Vector2i(0, 11), color.lightened(0.22), 2)
	elif id == "volcano":
		var base := Vector2i(73 + variant * 8, 22)
		var glow := _c(palette, "accent")
		_line(image, base, base + Vector2i(-15, 22), glow.darkened(0.5), 4)
		_line(image, base + Vector2i(-15, 22), base + Vector2i(4, 53), glow.darkened(0.5), 4)
		_line(image, base, base + Vector2i(-15, 22), glow, 1)
		_line(image, base + Vector2i(-15, 22), base + Vector2i(4, 53), glow, 1)
	elif id == "ice":
		for spike in range(4):
			var p := Vector2i(109 + spike % 2 * 9, 22 + spike * 36)
			_polygon(image, [p, p + Vector2i(9, 0), p + Vector2i(4, 17)], _c(palette, "light"))
	return ImageTexture.create_from_image(image)

func _ground(id: String, palette: Dictionary, frame: int) -> Texture2D:
	var image := Image.create(540, 240, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var soil := _c(palette, "dark")
	_rect(image, 0, 40, 540, 200, soil)
	for row in range(7):
		for column in range(19):
			var salt: int = row * 53 + column * 17
			var at := Vector2i(column * 31 - (13 if row % 2 else 0), 43 + row * 27)
			_brick(image, at, 29, 25, palette, salt + 631)
	# Grass and layered roots form a genuine physical-looking take-off ledge.
	for x in range(0, 540, 6):
		var height: int = 4 + int(_noise(x * 13 + 2) * 9.0)
		var light := _c(palette, "leaf_light")
		var leaf := _c(palette, "leaf")
		_rect(image, x, 36, 6, 7, leaf.darkened(0.16))
		_rect(image, x, 34, 6, 3, light if id == "ice" else leaf)
		if id in ["jungle", "sky", "canyon"]:
			_line(image, Vector2i(x + 2, 36), Vector2i(x + 1 + (frame if x % 12 == 0 else -frame), 34 - height), leaf, 1)
			if x % 24 == 0:
				_line(image, Vector2i(x + 2, 32), Vector2i(x + 7 + frame, 26 - height), light)
		elif id == "ice":
			_rect(image, x, 32, 6, 3 + x % 3, light)
		elif id == "volcano" and x % 18 == 0:
			_rect(image, x, 46 + x % 7, 7, 2, _c(palette, "accent"))
	# Stepped rocks, tufts and tiny flowers sit on the start platform.
	for rock in range(5):
		var x: int = [160, 212, 350, 410, 90][rock]
		var y: int = 34
		var w: int = [44, 19, 28, 37, 20][rock]
		var h: int = [17, 8, 11, 14, 9][rock]
		_rect(image, x + 3, y - h, w - 6, h, _c(palette, "rock"))
		_rect(image, x, y - h + 4, w, h - 4, _c(palette, "rock"))
		_rect(image, x + 6, y - h + 1, w - 12, 2, _c(palette, "light"))
		_rect(image, x + 3, y - 3, w - 6, 2, _c(palette, "dark"))
	if id in ["jungle", "sky"]:
		for flower in range(7):
			var x: int = 32 + flower * 77
			var y: int = 24 - flower % 3 * 2
			_line(image, Vector2i(x, 34), Vector2i(x + frame, y), _c(palette, "leaf"))
			_rect(image, x - 2 + frame, y - 2, 5, 1, Color("fff5bc"))
			_rect(image, x - 2 + frame, y + 2, 5, 1, Color("fff5bc"))
			_rect(image, x - 3 + frame, y - 1, 1, 3, Color("fff5bc"))
			_rect(image, x + 3 + frame, y - 1, 1, 3, Color("fff5bc"))
			_rect(image, x - 1 + frame, y - 1, 3, 3, _c(palette, "accent"))
	return ImageTexture.create_from_image(image)

func _orb(palette: Dictionary, moon: bool) -> Texture2D:
	var image := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var color := Color("cbe6d9") if moon else Color("fff2af")
	var shadow := Color("8da9b1") if moon else Color("eac676")
	for y in range(80):
		for x in range(80):
			var d: float = Vector2(float(x - 40), float(y - 40)).length()
			if d < 33.0:
				image.set_pixel(x, y, shadow if d > 30.0 else color)
	if moon:
		for crater in [Rect2i(29, 18, 9, 6), Rect2i(44, 38, 12, 9), Rect2i(26, 46, 6, 5), Rect2i(51, 26, 5, 4)]:
			image.fill_rect(crater, shadow.lightened(0.12))
	else:
		_rect(image, 19, 17, 17, 2, Color("fff9d2"))
		_rect(image, 15, 23, 5, 2, Color("fff9d2"))
	return ImageTexture.create_from_image(image)

func _build_world(id: String) -> Dictionary:
	var day: Dictionary = PALETTES[id]
	var night: Dictionary = NIGHT_PALETTES[id]
	var backdrop_day := _background_palette(day, false)
	var backdrop_night := _background_palette(night, true)
	var walls_day: Array[Texture2D] = []
	var walls_night: Array[Texture2D] = []
	var scenery_day: Array[Texture2D] = []
	var scenery_night: Array[Texture2D] = []
	for variant in range(4):
		walls_day.append(_wall_tile(id, day, variant))
		walls_night.append(_wall_tile(id, night, variant))
	for layer in range(2):
		scenery_day.append(_scenery(id, backdrop_day, false, layer))
		scenery_night.append(_scenery(id, backdrop_night, true, layer))
	return {
		"sky_day": _sky(id, backdrop_day, false),
		"sky_night": _sky(id, backdrop_night, true),
		"scenery_day": scenery_day, "scenery_night": scenery_night,
		"cloud_day": _cloud_texture(backdrop_day, id), "cloud_night": _cloud_texture(backdrop_night, id),
		"wall_day": walls_day, "wall_night": walls_night,
		"ground_day": [_ground(id, day, 0), _ground(id, day, 1)],
		"ground_night": [_ground(id, night, 0), _ground(id, night, 1)],
		"sun": _orb(day, false), "moon": _orb(night, true)
	}

func _build_insects() -> void:
	for frame in range(2):
		var fly := Image.create(12, 9, false, Image.FORMAT_RGBA8)
		fly.fill(Color.TRANSPARENT)
		var wing := Color("b1d4df")
		_rect(fly, 2, 1 + frame, 3, 2, wing)
		_rect(fly, 7, 1 + frame, 3, 2, wing)
		_rect(fly, 4, 3, 4, 4, Color("28414b"))
		_rect(fly, 4, 3, 4, 1, Color("658a80"))
		_rect(fly, 5, 7, 1, 1, Color("152b3b"))
		_fly_frames.append(ImageTexture.create_from_image(fly))
		var mosquito := Image.create(14, 11, false, Image.FORMAT_RGBA8)
		mosquito.fill(Color.TRANSPARENT)
		_rect(mosquito, 3, frame, 4, 2, wing)
		_rect(mosquito, 8, 1 - frame, 3, 2, wing)
		_line(mosquito, Vector2i(4, 4), Vector2i(9, 7), Color("182e41"), 1)
		_line(mosquito, Vector2i(3, 4), Vector2i(1, 2), Color("738f99"), 1)
		_line(mosquito, Vector2i(6, 5), Vector2i(4, 10), Color("738f99"), 1)
		_line(mosquito, Vector2i(8, 6), Vector2i(11, 9), Color("738f99"), 1)
		_mosquito_frames.append(ImageTexture.create_from_image(mosquito))
		var butterfly := Image.create(14, 12, false, Image.FORMAT_RGBA8)
		butterfly.fill(Color.TRANSPARENT)
		var outer := Color("e7b16a")
		_rect(butterfly, 2 + frame, 2, 4 - frame, 6, outer)
		_rect(butterfly, 8, 2, 4 - frame, 6, outer)
		_rect(butterfly, 3 + frame, 3, 2, 2, Color("f6dc9a"))
		_rect(butterfly, 9, 3, 2, 2, Color("f6dc9a"))
		_rect(butterfly, 6, 3, 2, 7, Color("3a5060"))
		_butterfly_frames.append(ImageTexture.create_from_image(butterfly))

func _theme_modulate() -> Color:
	return Color(0.78, 0.86, 0.94) if theme == "dark" else Color.WHITE

func _draw_pair(day: Texture2D, night: Texture2D, area: Rect2, blend: float, modulate: Color = Color.WHITE) -> void:
	var visibility: float = clampf(modulate.a, 0.0, 1.0)
	var night_opacity: float = blend * visibility
	if blend < 0.999:
		# Preserve exactly the requested total opacity during both crossfades.
		# Otherwise the two translucent day/night layers would add extra opacity.
		var day_modulate: Color = modulate
		day_modulate.a = visibility * (1.0 - blend) / maxf(1.0 - night_opacity, 0.0001)
		draw_texture_rect(day, area, false, day_modulate)
	if blend > 0.001:
		draw_texture_rect(night, area, false, Color(1.0, 1.0, 1.0, night_opacity))

func _draw_background(blend: float) -> void:
	var target := Rect2(0, 0, LOGICAL_WIDTH, viewport_height)
	var source := Rect2(0, 0, 540, minf(viewport_height / PIXEL_SCALE, float(SKY_IMAGE_HEIGHT)))
	if blend < 0.999:
		draw_texture_rect_region(_active["sky_day"], target, source, _theme_modulate())
	if blend > 0.001:
		draw_texture_rect_region(_active["sky_night"], target, source, Color(1.0, 1.0, 1.0, blend))
	# Celestial sprites stay behind the biome architecture and canopy.
	var orb_y: float = 230.0 + sin(time * 0.025) * 14.0 + minf(camera_height * 0.0005, 26.0)
	if world_id in ["jungle", "canyon", "sky"]:
		if blend < 0.999:
			draw_texture_rect(_active["sun"], Rect2(616, orb_y, 132, 132), false, Color(1, 1, 1, (1.0 - blend) * 0.28))
		if blend > 0.001:
			draw_texture_rect(_active["moon"], Rect2(614, orb_y, 132, 132), false, Color(1, 1, 1, blend * 0.46))
	# Two independently scrolling, seamless-height cached scenes provide depth.
	# Only these texture placements happen in a frame; all pixels are built once.
	var span: float = float(SCENERY_HEIGHT) * PIXEL_SCALE
	for layer in range(2):
		var speed: float = 0.009 if layer == 0 else 0.022
		var drift: float = time * (1.1 if world_id == "sky" else 0.16) * float(layer + 1)
		var offset: float = fposmod(camera_height * speed + drift, span)
		for tile in range(-1, int(ceil(viewport_height / span)) + 1):
			var area := Rect2(0, float(tile) * span + offset, LOGICAL_WIDTH, span)
			_draw_pair(_active["scenery_day"][layer], _active["scenery_night"][layer], area, blend, _theme_modulate())
	_draw_atmosphere(blend)

func _draw_atmosphere(blend: float) -> void:
	if world_id == "crystal":
		return
	var cloud_count: int = 7 if world_id == "sky" else 3
	var cloud_span: float = viewport_height + 240.0
	for index in range(cloud_count):
		var x: float = fposmod(float(index) * 307.0 + 67.0, 1000.0) - 90.0 + sin(time * 0.035 + index) * 28.0
		# Clouds move down with climbing and wrap while fully outside the view.
		var travel: float = time * (5.0 + float(index % 3)) + camera_height * (0.026 if world_id == "sky" else 0.016)
		var y: float = fposmod(float(index) * cloud_span / float(cloud_count) + travel, cloud_span) - 120.0
		var tint := _theme_modulate()
		tint.a = 0.32 if world_id == "sky" else 0.16
		_draw_pair(_active["cloud_day"], _active["cloud_night"], Rect2(x, y, 340, 110), blend, tint)

func _draw_wall(reflected: bool, blend: float) -> void:
	var visibility: float = clampf(side_walls_visibility, 0.0, 1.0)
	if visibility <= 0.001:
		return
	if reflected:
		draw_set_transform(Vector2(LOGICAL_WIDTH, 0.0), 0.0, Vector2(-1, 1))
	var origin: float = viewport_height - 520.0 + camera_height
	var offset: float = fposmod(origin, TILE_HEIGHT)
	var sector: int = int(floor(origin / TILE_HEIGHT))
	var rows: int = int(ceil(viewport_height / TILE_HEIGHT)) + 2
	var day_modulate: Color = _theme_modulate().lerp(Color.WHITE, 0.45)
	day_modulate.a = visibility
	for row in range(-1, rows):
		var index: int = posmod(row - sector + (47 if reflected else 0), 4)
		var area := Rect2(0, float(row) * TILE_HEIGHT + offset, WALL_LEFT, TILE_HEIGHT)
		_draw_pair(_active["wall_day"][index], _active["wall_night"][index], area, blend, day_modulate)
	# The inside edges stay clean and never intrude into a player's collision lane.
	draw_rect(Rect2(WALL_LEFT, 0, 6, viewport_height), Color(0.02, 0.08, 0.13, 0.20 * visibility))
	draw_set_transform(Vector2.ZERO)

func _draw_ledge(blend: float) -> void:
	var y: float = viewport_height - 445.0 + camera_height
	if y > viewport_height + 90.0:
		return
	var frame: int = int(time * 2.4) % 2
	_draw_pair(_active["ground_day"][frame], _active["ground_night"][frame], Rect2(0, y - 70, 1080, 480), blend, _theme_modulate().lerp(Color.WHITE, 0.5))

func _draw_particles(blend: float) -> void:
	if world_id == "ice":
		# Exactly six slow flakes, deliberately much sparser than the old snowfall.
		for index in range(6):
			var x: float = 288.0 + _noise(index * 17 + 7) * 500.0 + sin(time * 0.3 + index) * 14.0
			var y: float = fposmod(_noise(index * 11 + 3) * viewport_height + time * (8 + index % 3) + camera_height * 0.045, viewport_height)
			var tint := Color("effdf6").lerp(Color("bed7e6"), blend)
			tint.a = 0.65
			draw_rect(Rect2(x, y, 3, 6), tint)
			draw_rect(Rect2(x - 2, y + 2, 7, 2), tint)
		return
	var ambient: Color = Color("dfdf98").lerp(Color("b2edc3"), blend)
	if world_id == "volcano":
		ambient = Color("d29d71").lerp(Color("da9c69"), blend)
	elif world_id == "crystal":
		ambient = Color("90bfc1").lerp(Color("9fdbcc"), blend)
	elif world_id == "canyon":
		ambient = Color("d4b499").lerp(Color("ae9ca7"), blend)
	for index in range(10):
		var x: float = 280.0 + _noise(index * 29 + 5) * 520.0 + sin(time * 0.35 + index) * 10.0
		var y: float = fposmod(_noise(index * 13 + 1) * viewport_height - time * (4 + index % 3) + camera_height * 0.035, viewport_height)
		ambient.a = 0.28 + blend * 0.22
		draw_rect(Rect2(x, y, 2 + index % 2, 2 + index % 2), ambient)
	if blend > 0.02:
		for index in range(12):
			var x: float = 298.0 + _noise(index * 31 + 9) * 468.0 + sin(time * (0.7 + index % 3 * 0.11) + index * 2) * 18.0
			var y: float = fposmod(_noise(index * 67 + 8) * viewport_height - time * (7 + index % 4 * 3) + camera_height * 0.04, viewport_height)
			var frame: int = (int(time * 13.0) + index) % 2
			var texture: Texture2D = _mosquito_frames[frame] if index % 3 == 0 else _fly_frames[frame]
			draw_texture_rect(texture, Rect2(x, y, texture.get_width() * 1.6, texture.get_height() * 1.6), false, Color(1, 1, 1, blend * 0.85))
	elif world_id in ["jungle", "sky"]:
		for index in range(3):
			var x: float = 354.0 + index * 149.0 + sin(time * 0.35 + index * 2.0) * 30.0
			var y: float = 790.0 + index * 176.0 + sin(time * 0.9 + index) * 17.0
			var frame: int = (int(time * 7.0) + index) % 2
			draw_texture_rect(_butterfly_frames[frame], Rect2(x, y, 28, 24), false, Color(1, 1, 1, 0.82))

func _draw() -> void:
	if _active.is_empty():
		return
	var blend: float = clampf(night_amount, 0.0, 1.0)
	_draw_background(blend)
	_draw_wall(false, blend)
	_draw_wall(true, blend)
	_draw_ledge(blend)
	if not _fly_frames.is_empty():
		_draw_particles(blend)
