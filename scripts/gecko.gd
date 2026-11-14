class_name GeckoVisual
extends Node2D
## Illustrated character sprites use a shared deformable mesh, with a quiet
## tail, alternating planted limbs, eyelids, and a continuous waking pose.
## Textures and mesh geometry are cached; animation never edits image pixels.
const PIXEL_SCALE := 1.6
const ORIGIN := Vector2(32, 55)
const GROUND_FEET_Y := 90.0
const ELECTRO_DURATION := 1.4
const ASH_COUNT := 44
static var _frames: Dictionary = {}
static var _skin_ground_frames: Dictionary = {}
const DETAILED_SHADER: Shader = preload("res://assets/characters/rig.gdshader")
const DETAILED_CATALOG := "res://assets/characters/catalog.json"
static var _detailed_catalog: Dictionary = {}
static var _detailed_textures: Dictionary = {}
static var _detailed_meshes: Dictionary = {}
var _detailed_root: Node2D
var _detailed_run: MeshInstance2D
var _detailed_sleep: MeshInstance2D
var _detailed_run_key := ""
var _detailed_sleep_key := ""
var _detailed_mouth := Vector2.ZERO
var _detailed_active := false
# Body colors and costume accents share a small, deterministic palette. The
# artwork is articulated with the original rig; skins never change collisions.
const SKIN_PALETTES := {
	"standard_green": ["192f32", "315c44", "70ad50", "aad969", "d8e99b", "e5f59b"],
	"neon_pulse": ["101b37", "293052", "36d9de", "aeffff", "f4c5ff", "fc53df"],
	"desert_wanderer": ["3d2c27", "87603f", "c69c62", "f0cf8b", "f8e2ae", "bd483f"],
	"shadow_jumper": ["151124", "302642", "675084", "9b7fc3", "c5acd9", "bf8cff"],
	"cosmo_gecko": ["14132f", "272263", "4e49a8", "8986ec", "c9e6ff", "87f5ff"],
	"jungle_hunter": ["253624", "48623b", "839d4b", "c4d77a", "e2efab", "d8a94c"],
	"pirate_captain": ["35282c", "7c563c", "b98658", "e3b87a", "f8dfac", "dc5044"],
	"robo_gecko": ["23323f", "5b7286", "a1b6c4", "e1eef1", "f5ffff", "62edff"],
	"electro_shock": ["151e38", "283e77", "446ba5", "7aa9ed", "c7e2ff", "ffe558"],
	"royal_pearl": ["4d4355", "9693a8", "d3d2df", "f5eff6", "fffef0", "edc367"],
	"cyber_ninja": ["191c27", "343b49", "596372", "8d9baa", "c5cdd1", "ef4d5d"],
	"rainbow_spark": ["39403d", "cd7844", "f5c15b", "ffe991", "fff4bd", "fb78db"],
	"moon_ghost": ["3d5f80", "7b9fc4", "bed9ef", "e3f6ff", "f2fdff", "a8eaff"],
	"golden_champion": ["775020", "bd882c", "e9b949", "ffe58b", "fff4bd", "fff0a0"],
	"volcanic_fighter": ["2e252d", "713b35", "b8593c", "ef9b55", "ffd49c", "f25939"],
	"pixel_gecko": ["243d1c", "4e7b28", "8ab844", "c8e773", "e7f4a2", "bbec58"],
	"frost_crystal": ["315572", "5789b1", "89c3df", "d2f6ff", "f3ffff", "b1f4ff"],
	"venom_chameleon": ["354428", "66842d", "a7c843", "dbef78", "f3f8b2", "9d51bd"],
	"star_wanderer": ["24203d", "363963", "52628a", "8899b9", "d7e7ee", "f9c66a"],
	"steel_knight": ["303746", "697588", "a3acba", "dfe4eb", "f9f9f1", "c84d50"],
	"ghost_dragon": ["42324f", "806b9e", "b49fc9", "dfd3ef", "f5eafd", "d9b6ff"]
}
var skin_id := "standard_green"
var _skin_palette: Array = SKIN_PALETTES["standard_green"]
const PALETTE_INDEX := {"ink": 0, "deep": 1, "skin": 2, "lit": 3, "pale": 4, "accent": 5}
var _skin_colors: Array[Color] = [Color("192f32"), Color("315c44"), Color("70ad50"), Color("aad969"), Color("d8e99b"), Color("e5f59b")]
var mode := "idle"
var side := -1
var jump_progress := 0.0
var launch_progress := 0.0
var stretch := 1.0
var night_amount := 0.0
var run_speed_factor := 1.0
var _clock := 0.0
var _stride_phase := 0.0
var _tail_phase := 0.0
var _visual_speed_factor := 1.0
var _landing := 0.0
var _launch := 0.0
var _hurt := 0.0
var _eat_clock := -1.0
var _eat_world := Vector2.ZERO
var electro_duration := ELECTRO_DURATION
var _electro_clock := -1.0
var _electro_direction := 1.0
var _electro_angle := 0.0
var _electro_kind := "run"
var _ash_positions := PackedVector2Array()
var _ash_velocities := PackedVector2Array()
var _ash_sizes := PackedFloat32Array()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _frames.is_empty():
		for kind in ["idle", "run", "jump", "ground"]:
			for blink in range(2):
				_frames["%s%d" % [kind, blink]] = _make_frame(kind, blink == 1)
	_ensure_detailed_nodes()

func set_skin(id: String) -> void:
	# It is valid to configure a shop preview before adding it to the tree.
	skin_id = id if SKIN_PALETTES.has(id) else "standard_green"
	_skin_palette = SKIN_PALETTES[skin_id]
	for i in range(6):
		_skin_colors[i] = Color(_skin_palette[i])
	_detailed_run_key = ""
	_detailed_sleep_key = ""
	queue_redraw()

func _c(name: String) -> Color:
	var index: int = PALETTE_INDEX.get(name, 2)
	var color := _skin_colors[index]
	if skin_id == "moon_ghost" and index in [1, 2, 3, 4]:
		color.a = 0.86
	elif skin_id == "ghost_dragon" and index in [1, 2, 3]:
		color.a = 0.93
	return color

func _ground_texture(blink: int) -> Texture2D:
	if skin_id == "standard_green":
		return _frames["ground%d" % blink]
	var key := skin_id + str(blink)
	if not _skin_ground_frames.has(key):
		var image := Image.create(64, 120, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		_make_ground_body(image, blink == 1)
		var names := ["ink", "deep", "skin", "lit", "pale"]
		var replacements: Dictionary = {}
		for i in range(5):
			replacements[Color(SKIN_PALETTES["standard_green"][i]).to_rgba32()] = _c(names[i])
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel := image.get_pixel(x, y)
				if replacements.has(pixel.to_rgba32()):
					image.set_pixel(x, y, replacements[pixel.to_rgba32()])
		_skin_ground_frames[key] = ImageTexture.create_from_image(image)
	return _skin_ground_frames[key]

func _process(delta: float) -> void:
	_clock += delta
	if mode == "electrocuted":
		if _electro_clock >= ELECTRO_DURATION:
			return
		var previous_clock := _electro_clock
		_electro_clock = minf(_electro_clock + delta, ELECTRO_DURATION)
		if _electro_clock >= 0.48:
			var ash_delta := _electro_clock - maxf(previous_clock, 0.48)
			for i in range(_ash_positions.size()):
				_ash_velocities[i] += Vector2(0.0, 180.0) * ash_delta
				_ash_positions[i] += _ash_velocities[i] * ash_delta
		queue_redraw()
		return
	# Integrate phase instead of multiplying the full elapsed clock by speed.
	# Speed changes then remain continuous rather than skipping entire strides.
	_visual_speed_factor = lerpf(_visual_speed_factor, clampf(run_speed_factor, 0.5, 3.0), 1.0 - exp(-delta * 3.5))
	var running: bool = mode == "run" or (mode in ["wake_climb", "climb_launch"] and launch_progress >= 0.58)
	var stride_hz := clampf(1.45 + (_visual_speed_factor - 1.0) * 0.26, 1.25, 1.97) if running else 0.22
	var tail_hz := clampf(0.38 + (_visual_speed_factor - 1.0) * 0.075, 0.34, 0.53) if running else (0.055 if mode == "sleep" else 0.20)
	_stride_phase = fposmod(_stride_phase + delta * TAU * stride_hz, TAU)
	_tail_phase = fposmod(_tail_phase + delta * TAU * tail_hz, TAU)
	_landing = move_toward(_landing, 0.0, delta * 7.0)
	_launch = move_toward(_launch, 0.0, delta * 10.0)
	_hurt = move_toward(_hurt, 0.0, delta * 2.5)
	if _eat_clock >= 0:
		_eat_clock += delta
		if _eat_clock >= 0.23:
			_eat_clock = -1.0
	queue_redraw()

func reset_animation() -> void:
	_clock = 0.0
	_stride_phase = 0.0
	_tail_phase = 0.0
	_visual_speed_factor = 1.0
	run_speed_factor = 1.0
	_landing = 0.0
	_launch = 0.0
	_hurt = 0.0
	_eat_clock = -1.0
	_eat_world = Vector2.ZERO
	_electro_clock = -1.0
	_electro_direction = 1.0
	_electro_angle = 0.0
	_electro_kind = "run"
	_ash_positions.clear()
	_ash_velocities.clear()
	_ash_sizes.clear()
	jump_progress = 0.0
	launch_progress = 0.0
	stretch = 1.0
	side = -1
	rotation = 0.0
	mode = "idle"
	queue_redraw()

func set_launch_pose(fraction: float) -> void:
	launch_progress = clampf(fraction, 0.0, 1.0)
	mode = "wake_climb"
	queue_redraw()

func electrocute() -> void:
	var was_jump := mode == "jump"
	_electro_clock = 0.0
	_electro_direction = float(-side)
	_electro_angle = -float(side) * sin(jump_progress * PI) * 1.08 if was_jump else 0.0
	_electro_kind = "jump" if was_jump else "run"
	if was_jump and jump_progress > 0.72:
		_electro_direction = float(side)
	mode = "electrocuted"
	_eat_clock = -1.0
	_hurt = 0.0
	_ash_positions.clear()
	_ash_velocities.clear()
	_ash_sizes.clear()
	# Fixed, deterministic pieces: no particle nodes, random calls, or allocations
	# during the effect. Their coordinates are local, so the node stays in place.
	for i in range(ASH_COUNT):
		var point: Vector2
		if i < 8:
			var angle := float(i) * TAU / 8.0
			point = Vector2(32, 26) + Vector2(cos(angle) * 7.0, sin(angle) * 10.0)
		elif i < 20:
			point = Vector2(34.0 + sin(float(i) * 2.4) * 8.0, 37.0 + float(i - 8) * 3.0)
		elif i < 32:
			var limb_index := (i - 20) / 3
			var limb := _profile_limb_points(limb_index % 2 == 0, limb_index < 2, _electro_kind)
			point = limb[0].lerp(limb[1], 0.5) if i % 3 == 2 else limb[1 + i % 3]
		else:
			var u := float(i - 31) / 12.0
			point = Vector2(35 + sin(u * PI * 1.6 + _tail_phase) * u * 10.0, 71 + u * 42.0)
		_ash_positions.append(((point - ORIGIN) * Vector2(_electro_direction, 1.0) * PIXEL_SCALE).rotated(_electro_angle))
		_ash_velocities.append(Vector2(sin(float(i) * 2.1) * 30.0, -12.0 - fposmod(float(i) * 7.0, 31.0)))
		_ash_sizes.append(2.0 + float(i % 3))
	queue_redraw()

func land() -> void:
	_landing = 1.0

func launch() -> void:
	_launch = 1.0
	_eat_clock = -1.0

func hurt() -> void:
	mode = "hit"
	_hurt = 1.0
	_eat_clock = -1.0

func eat_to(local_target: Vector2) -> void:
	if mode != "jump" and not is_eating():
		_eat_world = position + local_target
		_eat_clock = 0.0

func is_eating() -> bool:
	return _eat_clock >= 0.0

func _rect(im: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, 64, 120))
	if r.has_area():
		im.fill_rect(r, color)

func _line(im: Image, a: Vector2, b: Vector2, color: Color, width: int = 1) -> void:
	var count := maxi(1, int(a.distance_to(b) * 1.5))
	for i in range(count + 1):
		var p := a.lerp(b, float(i) / count).round()
		_rect(im, int(p.x) - width / 2, int(p.y) - width / 2, width, width, color)

func _oval(im: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	for y in range(int(center.y - radius.y), int(center.y + radius.y) + 1):
		var f := 1.0 - pow((float(y) - center.y) / radius.y, 2.0)
		if f >= 0:
			var extent := int(sqrt(f) * radius.x)
			_rect(im, int(center.x) - extent, y, extent * 2 + 1, 1, color)

func _make_frame(kind: String, blink: bool) -> Texture2D:
	var im := Image.create(64, 120, false, Image.FORMAT_RGBA8)
	im.fill(Color.TRANSPARENT)
	if kind == "ground":
		_make_ground_body(im, blink)
		return ImageTexture.create_from_image(im)
	var ink := Color("192f32")
	var deep := Color("315c44")
	var skin := Color("70ad50")
	var lit := Color("aad969")
	var pale := Color("d8e99b")
	# Narrow silhouette; the pale belly faces the wall (left).
	_oval(im, Vector2(34, 53), Vector2(12, 24), ink)
	_oval(im, Vector2(34, 52), Vector2(10, 22), deep)
	_oval(im, Vector2(32, 51), Vector2(8, 21), skin)
	_oval(im, Vector2(29, 51), Vector2(3, 19), pale)
	_line(im, Vector2(34, 34), Vector2(36, 68), lit, 3)
	for row in range(5):
		_rect(im, 38 + row % 2, 38 + row * 6, 4, 3, deep)
		_rect(im, 35, 41 + row * 6, 2, 1, pale)
	# One eye and a pointed upward muzzle make the side view unambiguous.
	_oval(im, Vector2(32, 27), Vector2(13, 16), ink)
	_oval(im, Vector2(31, 26), Vector2(11, 14), skin)
	_rect(im, 23, 11, 9, 6, ink)
	_rect(im, 23, 13, 8, 5, lit)
	_rect(im, 20, 18, 6, 11, ink)
	_rect(im, 22, 18, 5, 10, pale)
	_line(im, Vector2(26, 32), Vector2(32, 35), deep, 2)
	_rect(im, 23, 18, 2, 2, deep)
	_rect(im, 33, 13, 4, 3, lit)
	_oval(im, Vector2(35, 24), Vector2(6, 7), ink)
	if blink:
		_rect(im, 30, 24, 10, 2, lit)
	else:
		_oval(im, Vector2(35, 23), Vector2(4, 5), Color("f7f5d7"))
		_rect(im, 33, 19, 3, 7, ink)
		_rect(im, 33, 19, 2, 2, Color.WHITE)
	return ImageTexture.create_from_image(im)

func _make_ground_body(im: Image, blink: bool) -> void:
	var ink := Color("192f32")
	var deep := Color("315c44")
	var skin := Color("70ad50")
	var lit := Color("aad969")
	var pale := Color("d8e99b")
	_oval(im, Vector2(32, 77), Vector2(15, 23), ink)
	_oval(im, Vector2(32, 76), Vector2(13, 21), deep)
	_oval(im, Vector2(31, 74), Vector2(12, 20), skin)
	_oval(im, Vector2(32, 79), Vector2(8, 15), pale)
	_oval(im, Vector2(32, 58), Vector2(11, 11), skin)
	_oval(im, Vector2(32, 44), Vector2(22, 18), ink)
	_oval(im, Vector2(32, 43), Vector2(20, 16), skin)
	_oval(im, Vector2(32, 51), Vector2(18, 9), lit)
	for x: int in [18, 46]:
		_oval(im, Vector2(x, 40), Vector2(8, 10), ink)
		if blink:
			_rect(im, x - 6, 39, 13, 3, lit)
		else:
			_oval(im, Vector2(x, 39), Vector2(6, 8), Color("f7f5d7"))
			_rect(im, x - 1, 33, 3, 12, ink)
			_rect(im, x - 2, 33, 2, 3, Color.WHITE)
	_rect(im, 24, 49, 2, 2, deep)
	_rect(im, 39, 49, 2, 2, deep)
	_line(im, Vector2(20, 55), Vector2(27, 57), deep, 1)
	_line(im, Vector2(27, 57), Vector2(37, 57), deep, 1)
	_line(im, Vector2(37, 57), Vector2(44, 55), deep, 1)
	for i in range(4):
		_rect(im, 26 + i * 4, 30 + i % 2 * 3, 2, 2, lit)
		_rect(im, 21, 67 + i * 6, 2, 3, deep)
		_rect(im, 42, 67 + i * 6, 2, 3, deep)
		_rect(im, 29, 70 + i * 6, 6, 1, lit)

func _pixel_ellipse(at: Vector2, radius: Vector2, color: Color) -> void:
	var polygon := PackedVector2Array()
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		polygon.append(at - ORIGIN + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(polygon, color)

func _segment(a: Vector2, b: Vector2, width_a: float, width_b: float, color: Color) -> void:
	var normal := (b - a).normalized().orthogonal()
	draw_colored_polygon(PackedVector2Array([
		a - ORIGIN + normal * width_a * 0.5, b - ORIGIN + normal * width_b * 0.5,
		b - ORIGIN - normal * width_b * 0.5, a - ORIGIN - normal * width_a * 0.5
	]), color)

func _profile_pose() -> Dictionary:
	return {"hip": Vector2(34, 72), "chest": Vector2(32, 35), "control": Vector2(36, 53), "control2": Vector2(36, 53),
		"head": Vector2(32, 26), "head_angle": 0.0, "curl": 0.0, "unfold": 1.0,
		"rise": 1.0, "crawl": 1.0, "alert": 0.0, "eyes": 1.0}

func _mix_pose(a: Dictionary, b: Dictionary, amount: float) -> Dictionary:
	var pose: Dictionary = {}
	for key: String in ["hip", "chest", "control", "control2", "head"]:
		var point: Vector2 = a[key]
		pose[key] = point.lerp(b[key], amount)
	for key: String in ["head_angle", "curl", "unfold", "rise", "crawl", "alert", "eyes"]:
		pose[key] = lerpf(float(a[key]), float(b[key]), amount)
	return pose

func _sleep_pose() -> Dictionary:
	# The rib cage bends around the resting head; the broad tail continues that
	# curve along the belly. A slow breath moves the chest, never the planted feet.
	var breath := sin(_clock * TAU / 5.4) * 0.34
	return {"hip": Vector2(49, 93), "chest": Vector2(28, 91 + breath), "control": Vector2(49, 80 + breath), "control2": Vector2(29, 80 + breath),
		"head": Vector2(22, 95 + breath * 0.25), "head_angle": -1.72, "curl": 1.0, "unfold": 0.0,
		"rise": 0.0, "crawl": 0.0, "alert": 0.0, "eyes": 0.0}

func _wake_pose() -> Dictionary:
	var asleep := _sleep_pose()
	var awake := {"hip": Vector2(49, 93), "chest": Vector2(30, 84), "control": Vector2(49, 80), "control2": Vector2(31, 76),
		"head": Vector2(22, 78), "head_angle": -1.05, "curl": 1.0, "unfold": 0.0,
		"rise": 0.0, "crawl": 0.0, "alert": 1.0, "eyes": 1.0}
	var extended := {"hip": Vector2(47, 88), "chest": Vector2(27, 81), "control": Vector2(44, 76), "control2": Vector2(32, 75),
		"head": Vector2(15, 77), "head_angle": -1.35, "curl": 0.42, "unfold": 1.0,
		"rise": 0.0, "crawl": 0.0, "alert": 0.25, "eyes": 1.0}
	if launch_progress <= 0.20:
		return asleep
	if launch_progress < 0.42:
		var pose := _mix_pose(asleep, awake, smoothstep(0.20, 0.42, launch_progress))
		# The eye reacts first, then the chin lifts clear of the tucked forefoot.
		pose["eyes"] = smoothstep(0.205, 0.26, launch_progress)
		return pose
	if launch_progress < 0.58:
		return _mix_pose(awake, extended, smoothstep(0.42, 0.58, launch_progress))
	return _mix_pose(extended, _profile_pose(), smoothstep(0.58, 0.70, launch_progress))

func _body_point(pose: Dictionary, u: float) -> Vector2:
	var hip: Vector2 = pose["hip"]
	var control: Vector2 = pose["control"]
	var chest: Vector2 = pose["chest"]
	return hip.bezier_interpolate(control, pose["control2"], chest, u)

func _body_normal(pose: Dictionary, u: float) -> Vector2:
	var tangent := _body_point(pose, minf(1.0, u + 0.02)) - _body_point(pose, maxf(0.0, u - 0.02))
	return tangent.normalized().orthogonal()

func _body_width(pose: Dictionary, u: float) -> float:
	return lerpf(4.5 + sin(u * PI) * 7.6, 7.0 + sin(u * PI) * 5.0, float(pose["curl"]))

func _body_ribbon(pose: Dictionary, width_scale: float, offset: Vector2, color: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(17):
		var u := float(i) / 16.0
		var point := _body_point(pose, u)
		var normal := _body_normal(pose, u)
		var width := _body_width(pose, u) * width_scale
		left.append(point - ORIGIN + offset + normal * width)
		right.append(point - ORIGIN + offset - normal * width)
	for i in range(right.size() - 1, -1, -1):
		left.append(right[i])
	var curl := float(pose["curl"])
	if curl > 0.0:
		var haunch: Vector2 = pose["hip"] + Vector2(-4, 1) * curl
		for i in range(12):
			var a := TAU * float(i) / 12.0
			left.append(haunch - ORIGIN + offset + Vector2(cos(a) * 9.0, sin(a) * 7.0) * curl * width_scale)
	# The inner edge of a tight curl can fold over itself. Its hull forms one
	# solid rib cage; markings below follow the spine and stay inside that mass.
	var outline := Geometry2D.convex_hull(left)
	if outline.size() > 3:
		outline.remove_at(outline.size() - 1)
		draw_colored_polygon(outline, color)

func _neck(pose: Dictionary, width: float, color: Color) -> void:
	var chest: Vector2 = pose["chest"]
	var nape := _head_point(pose, Vector2(0, 9))
	_segment(chest, nape, width, width * 0.88, color)
	_pixel_ellipse(chest, Vector2.ONE * width * 0.5, color)
	_pixel_ellipse(nape, Vector2.ONE * width * 0.44, color)

func _rotated_ellipse(at: Vector2, radius: Vector2, angle: float, color: Color) -> void:
	var polygon := PackedVector2Array()
	for i in range(12):
		var a := TAU * float(i) / 12.0
		polygon.append(at - ORIGIN + (Vector2(cos(a), sin(a)) * radius).rotated(angle))
	draw_colored_polygon(polygon, color)

func _head_point(pose: Dictionary, offset: Vector2) -> Vector2:
	var head: Vector2 = pose["head"]
	return head + offset.rotated(float(pose["head_angle"]))

func _draw_pose_body(pose: Dictionary, tint: Color, blink: int, include_head: bool = true) -> void:
	var ink := _c("ink") * tint
	var deep := _c("deep") * tint
	var skin := _c("skin") * tint
	var lit := _c("lit") * tint
	var pale := _c("pale") * tint
	# Neck and hips overlap the same torso silhouette at every wake fraction.
	# Surface details are inset along the local rib normal, so no belly texture
	# sticks out when the spine changes from a C shape to a vertical profile.
	_neck(pose, 15.0, ink)
	_body_ribbon(pose, 1.0, Vector2.ZERO, ink)
	_neck(pose, 11.4, deep)
	_body_ribbon(pose, 0.87, Vector2.ZERO, deep)
	_neck(pose, 9.6, skin)
	_body_ribbon(pose, 0.73, Vector2(-0.7, -0.3), skin)
	var previous := Vector2.ZERO
	for i in range(11):
		var u := 0.20 + float(i) * 0.058
		var point := _body_point(pose, u) + _body_normal(pose, u) * _body_width(pose, u) * 0.35
		if i > 0:
			_segment(previous, point, 3.5, 3.5, pale)
		_pixel_ellipse(point, Vector2(1.75, 1.75), pale)
		previous = point
	for i in range(5):
		var u := 0.23 + float(i) * 0.13
		var point := _body_point(pose, u)
		var normal := _body_normal(pose, u)
		_pixel_ellipse(point - normal * _body_width(pose, u) * 0.43, Vector2(2.0, 1.5), deep)
		_pixel_ellipse(point, Vector2(1.5, 0.65), lit)
	_draw_costume_body(pose, tint)
	if include_head:
		_draw_pose_head(pose, tint, blink)

func _draw_pose_head(pose: Dictionary, tint: Color, blink: int) -> void:
	var ink := _c("ink") * tint
	var deep := _c("deep") * tint
	var skin := _c("skin") * tint
	var lit := _c("lit") * tint
	var pale := _c("pale") * tint
	var head: Vector2 = pose["head"]
	var angle := float(pose["head_angle"])
	# One closed contour includes the muzzle. All cheek/eyelid details fit
	# inside it, so a turned head cannot expose floating highlight pieces.
	var contour := PackedVector2Array([Vector2(-4, -17), Vector2(-8, -16), Vector2(-11, -13),
		Vector2(-13, -9), Vector2(-14, -4), Vector2(-13, 2), Vector2(-10, 8), Vector2(-5, 13),
		Vector2(0, 15), Vector2(5, 14), Vector2(10, 10), Vector2(12, 5), Vector2(13, 0),
		Vector2(11, -7), Vector2(7, -13), Vector2(2, -16)])
	for layer in range(2):
		var polygon := PackedVector2Array()
		for point in contour:
			polygon.append(head - ORIGIN + (point * (1.0 if layer == 0 else 0.86)).rotated(angle))
		draw_colored_polygon(polygon, ink if layer == 0 else skin)
	_rotated_ellipse(_head_point(pose, Vector2(-7, -8)), Vector2(4.4, 5.8), angle, lit)
	_rotated_ellipse(_head_point(pose, Vector2(-8, 0)), Vector2(3.1, 6.0), angle, pale)
	_segment(_head_point(pose, Vector2(-6, 6)), _head_point(pose, Vector2(0, 9)), 1.5, 1.2, deep)
	_pixel_ellipse(_head_point(pose, Vector2(-8, -7)), Vector2(1.0, 1.0), deep)
	var eye := _head_point(pose, Vector2(3, -3))
	var openness := float(pose["eyes"])
	if blink == 1 or openness < 0.08:
		# A relaxed eyelid belongs to the cheek, rather than a black empty socket.
		_rotated_ellipse(eye, Vector2(5.5, 5.0), angle, skin)
		var lid_angle := angle + float(pose["curl"]) * PI * 0.5
		_segment(eye + Vector2(-4, 0).rotated(lid_angle), eye + Vector2(0, 1).rotated(lid_angle), 1.5, 1.5, deep)
		_segment(eye + Vector2(0, 1).rotated(lid_angle), eye + Vector2(4, 0).rotated(lid_angle), 1.5, 1.0, deep)
		_segment(eye + Vector2(-3.5, -1.5).rotated(lid_angle), eye + Vector2(3.5, -1.5).rotated(lid_angle), 1.0, 1.0, lit)
	else:
		var surprise := float(pose["alert"])
		_rotated_ellipse(eye, Vector2(6, 7 * openness), angle, ink)
		_rotated_ellipse(eye + Vector2(0, -0.6).rotated(angle), Vector2(4.2 + surprise * 0.7, (5.2 + surprise * 0.6) * openness), angle, Color("f7f5d7") * tint)
		_rotated_ellipse(_head_point(pose, Vector2(2, -3 - openness)), Vector2(1.6, 4.0 * openness), angle, ink)
		_pixel_ellipse(_head_point(pose, Vector2(1.5, -3 - 3.0 * openness)), Vector2(1.1, 1.1), Color.WHITE * tint)
	_draw_costume_head(pose, tint)

func _tail_point(pose: Dictionary, u: float) -> Vector2:
	var curl := float(pose["curl"])
	var root: Vector2 = pose["hip"]
	root += Vector2(1, -1)
	var straight := Vector2(sin(u * PI * 1.6 + _tail_phase) * u * 10.0, u * 42.0)
	# Two joined curves bring the tail along the outside of the haunch, then
	# around the resting jaw. The tip stays relaxed beside the head.
	var coiled: Vector2
	if u < 0.5:
		coiled = Vector2.ZERO.bezier_interpolate(Vector2(21, 8), Vector2(13, 20), Vector2(-10, 13), u * 2.0)
	else:
		coiled = Vector2(-10, 13).bezier_interpolate(Vector2(-37, 16), Vector2(-45, -2), Vector2(-29, -5), (u - 0.5) * 2.0)
	# Sleep has an almost still tail; the running wave enters only as it uncoils.
	coiled.y += sin(_clock * TAU / 7.5 + u * 2.0) * u * 0.14
	return root + straight.lerp(coiled, curl)

func _draw_pose_tail(pose: Dictionary, tint: Color) -> void:
	var curl := float(pose["curl"])
	var ink := _c("ink") * tint
	var skin := _c("skin") * tint
	var deep := _c("deep") * tint
	# Outline and skin each form a continuous strip. Drawing the complete ink
	# pass first avoids the dark cross seams of individually outlined segments.
	for layer in range(2):
		var previous := _tail_point(pose, 0.0)
		var border := 2.0 if layer == 0 else 0.0
		var color := ink if layer == 0 else skin
		_pixel_ellipse(previous, Vector2.ONE * (lerpf(9.0, 14.0, curl) + border) * 0.5, color)
		for k in range(1, 25):
			var u := float(k) / 24.0
			var previous_u := float(k - 1) / 24.0
			var point := _tail_point(pose, u)
			var width := maxf(0.8, (1.0 - u) * lerpf(9.0, 14.0, curl))
			var previous_width := maxf(0.8, (1.0 - previous_u) * lerpf(9.0, 14.0, curl))
			_segment(previous, point, previous_width + border, width + border, color)
			_pixel_ellipse(point, Vector2.ONE * (width + border) * 0.5, color)
			previous = point
	for band in range(5):
		var u := 0.12 + float(band) * 0.16
		var point := _tail_point(pose, u)
		var tangent := (_tail_point(pose, minf(1.0, u + 0.015)) - _tail_point(pose, maxf(0.0, u - 0.015))).normalized()
		var half_width := maxf(0.6, (1.0 - u) * lerpf(9.0, 14.0, curl) * 0.42)
		_segment(point - tangent.orthogonal() * half_width, point + tangent.orthogonal() * half_width, 1.7, 1.7, _tail_mark_color(band, tint))

func _draw_tail(tint: Color, ground: bool = false) -> void:
	var ink := _c("ink") * tint
	var deep := _c("deep") * tint
	var skin := _c("skin") * tint
	var previous := Vector2(35, 71)
	if ground:
		previous = Vector2(35, 90)
	for k in range(1, 25):
		var u := float(k) / 24.0
		var point := Vector2(35.0 + sin(u * PI * 1.6 + _tail_phase) * u * 10.0, 71.0 + u * 42.0)
		if ground:
			point = Vector2(35.0 + u * 28.0, 90.0 + sin(u * PI) * 16.0 + sin(_tail_phase + u * 3.0) * u * 1.4)
		var thickness := maxf(0.8, (1.0 - u) * 9.0)
		_segment(previous, point, thickness + 1.5, thickness + 1.0, ink)
		_segment(previous + Vector2(0, -0.5), point + Vector2(0, -0.5), thickness, maxf(0.7, thickness - 0.8), skin if k % 6 < 4 else deep)
		previous = point

func _draw_hand(foot: Vector2, back: bool, tint: Color, direction: Vector2 = Vector2.LEFT) -> void:
	var ink := _c("ink") * tint
	var skin := (_c("deep") if back else _c("skin")) * tint
	var lit := (_c("skin") if back else _c("lit")) * tint
	var pale := (_c("skin") if back else _c("pale")) * tint
	_pixel_ellipse(foot, Vector2(3.7, 4.5), ink)
	_pixel_ellipse(foot - direction * 0.2, Vector2(2.7, 3.2), skin)
	# Five jointed digits: the short outer toes cup the surface beside the pads.
	for toe in range(5):
		var spread := (float(toe) - 2.0) * 0.34
		var reach := direction.rotated(spread)
		var length := 7.0 - absf(float(toe) - 2.0) * 1.2
		var joint := foot + reach * length * 0.55 + direction.orthogonal() * sin(spread) * 0.7
		var pad := joint + reach.rotated(spread * 0.22) * length * 0.45
		draw_line(foot - ORIGIN, joint - ORIGIN, ink, 2.5, false)
		draw_line(joint - ORIGIN, pad - ORIGIN, ink, 2.2, false)
		draw_line(foot - ORIGIN, joint - ORIGIN, lit, 1.25, false)
		draw_line(joint - ORIGIN, pad - ORIGIN, lit, 1.1, false)
		draw_rect(Rect2(pad - ORIGIN - Vector2(1.6, 1.5), Vector2(3.2, 3)), ink)
		draw_rect(Rect2(pad - ORIGIN - Vector2(1, 1), Vector2(2, 2)), pale)

func _profile_limb_points(front: bool, back: bool, kind: String, amount: float = 1.0) -> PackedVector2Array:
	var phase := _stride_phase + (PI if front == back else 0.0)
	var cycle := fposmod(phase / TAU, 1.0)
	var lift := 0.0
	var stride := 0.0
	if kind == "run":
		if cycle < 0.63:
			stride = lerpf(-8.0, 8.0, smoothstep(0.0, 0.63, cycle))
		else:
			var swing := (cycle - 0.63) / 0.37
			stride = lerpf(8.0, -8.0, smoothstep(0.0, 1.0, swing))
			lift = sin(swing * PI)
	else:
		stride = sin(phase) * 0.8
	stride *= amount
	lift *= amount
	var y := 43.0 if front else 66.0
	var shoulder := Vector2(30.0 if back else 35.0, y)
	var elbow := Vector2(22.0 if front else 43.0, y + (5.0 if front else 11.0) + stride * 0.28)
	var foot := Vector2((16.0 if back else 9.0) + lift * 6.0, y + (-10.0 if front else 10.0) + stride)
	if back:
		elbow.x -= 4.0
	if kind == "jump":
		elbow = Vector2(43.0 if front else 46.0, y + (-6.0 if front else 10.0))
		foot = elbow + Vector2(-8.0, -7.0 if front else 6.0)
	return PackedVector2Array([shoulder, elbow, foot])

func _draw_limb_chain(points: PackedVector2Array, front: bool, back: bool, tint: Color, hand_direction: Vector2 = Vector2.LEFT, fold: float = 0.0, hand_openness: float = 1.0) -> void:
	var ink := _c("ink") * tint
	var skin := (_c("deep") if back else _c("skin")) * tint
	var lit := (_c("skin") if back else _c("lit")) * tint
	var shoulder := points[0]
	var elbow := points[1]
	var foot := points[2]
	var thigh_width := lerpf(6.0 if front else 8.0, 5.0 if front else 7.5, fold)
	var elbow_width := lerpf(5.2, 6.0, fold)
	_segment(shoulder, elbow, thigh_width + 1.6, elbow_width, ink)
	_pixel_ellipse(elbow, Vector2.ONE * lerpf(3.2, 3.0, fold), ink)
	_segment(elbow, foot, elbow_width, lerpf(3.4, 4.8, fold), ink)
	_segment(shoulder, elbow, thigh_width, lerpf(3.5, 4.0, fold), skin)
	_pixel_ellipse(elbow, Vector2.ONE * lerpf(2.2, 2.0, fold), skin)
	_segment(elbow, foot, lerpf(3.4, 4.0, fold), lerpf(2.0, 2.8, fold), skin)
	_segment(shoulder + Vector2(0, -0.9), elbow + Vector2(0, -0.6), 1.5, 1.0, lit)
	_draw_tucked_hand(foot, back, tint, hand_openness, hand_direction)
	_draw_costume_limb(points, back, tint)

func _draw_limbs(back: bool, kind: String, tint: Color) -> void:
	for front: bool in [true, false]:
		_draw_limb_chain(_profile_limb_points(front, back, kind), front, back, tint)

func _draw_tucked_hand(foot: Vector2, back: bool, tint: Color, openness: float, direction: Vector2) -> void:
	# At rest only three folded digits are visible; the other two tuck beneath
	# the palm. They open into the same five-pad hand as the leg takes weight.
	if openness >= 0.99:
		_draw_hand(foot, back, tint, direction)
		return
	var ink := _c("ink") * tint
	var skin := (_c("deep") if back else _c("skin")) * tint
	var lit := (_c("skin") if back else _c("lit")) * tint
	_pixel_ellipse(foot, Vector2(3.0, 2.5), ink)
	_pixel_ellipse(foot, Vector2(2.1, 1.6), skin)
	for toe in range(3):
		var spread := (float(toe) - 1.0) * lerpf(0.35, 0.6, openness)
		var reach := direction.rotated(spread)
		var middle := foot + reach * lerpf(2.0, 3.8, openness)
		var tip := middle + reach.rotated(0.4 * (1.0 - openness)) * lerpf(1.3, 2.7, openness)
		_segment(foot, middle, 2.0, 1.7, ink)
		_segment(middle, tip, 1.7, 1.5, ink)
		_segment(foot, middle, 1.0, 0.9, lit)
		_pixel_ellipse(tip, Vector2(1.0, 0.9), lit)

func _draw_wake_limbs(pose: Dictionary, back: bool, tint: Color) -> void:
	for front: bool in [true, false]:
		var body_u := 0.86 if front else 0.10
		var shoulder := _body_point(pose, body_u)
		shoulder += _body_normal(pose, body_u) * _body_width(pose, body_u) * 0.3 * float(pose["curl"])
		var sleep_elbow := Vector2(35, 99) if front else Vector2(51, 99)
		var sleep_foot := Vector2(29, 98) if front else Vector2(43, 99)
		var ground_elbow := Vector2(18, 91) if front else Vector2(54, 96)
		var ground_foot := Vector2(20, 104) if front else Vector2(48, 104)
		var profile_points := _profile_limb_points(front, back, "run", float(pose["crawl"]))
		var unfold := float(pose["unfold"])
		var rise := float(pose["rise"])
		var points := PackedVector2Array([shoulder,
			sleep_elbow.lerp(ground_elbow, unfold), sleep_foot.lerp(ground_foot, unfold)])
		for i in range(3):
			if back:
				points[i] += Vector2(-2, -3)
			points[i] = points[i].lerp(profile_points[i], rise)
		var hand_direction := Vector2(-0.9, 0.45).normalized().lerp(Vector2.DOWN, unfold).lerp(Vector2.LEFT, rise).normalized()
		_draw_limb_chain(points, front, back, tint, hand_direction, 1.0 - rise, maxf(unfold, rise))

func _draw_wake(pose: Dictionary, blink: int, direction: float, tint: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(direction, 1.0) * PIXEL_SCALE)
	_draw_costume_back(pose, tint)
	_draw_pose_tail(pose, tint)
	_draw_wake_limbs(pose, true, tint)
	_draw_pose_body(pose, tint, blink, false)
	_draw_wake_limbs(pose, false, tint)
	_draw_pose_head(pose, tint, blink)
	_draw_costume_front(pose, tint)
	draw_set_transform(Vector2.ZERO)

func _draw_ground(tint: Color, blink: int, lean: float = 0.0, narrowing: float = 1.0) -> void:
	draw_set_transform(Vector2.ZERO, lean, Vector2(PIXEL_SCALE * narrowing, PIXEL_SCALE))
	var pose := _profile_pose()
	pose["head"] = Vector2(32, 44)
	pose["hip"] = Vector2(33, 92)
	pose["chest"] = Vector2(32, 65)
	pose["control"] = Vector2(32, 78)
	pose["control2"] = Vector2(32, 78)
	_draw_costume_back(pose, tint)
	_draw_tail(tint, true)
	var ink := _c("ink") * tint
	var skin := _c("skin") * tint
	var lit := _c("lit") * tint
	for direction: int in [-1, 1]:
		var hip := Vector2(32 + direction * 10, 84)
		var knee := Vector2(32 + direction * 23, 94)
		var foot := Vector2(32 + direction * 21, 104)
		_segment(hip, knee, 9, 8, ink)
		_segment(knee, foot, 7, 5, ink)
		_segment(hip, knee, 6.8, 5.8, skin)
		_segment(knee, foot, 4.8, 3, lit)
		_draw_hand(foot, false, tint, Vector2(direction * 0.5, 1).normalized())
	draw_texture_rect(_ground_texture(blink), Rect2(-ORIGIN + Vector2(0, sin(_clock * 1.6) * 0.5), Vector2(64, 120)), false, tint)
	_draw_costume_body(pose, tint)
	for direction: int in [-1, 1]:
		var shoulder := Vector2(32 + direction * 11, 66)
		var elbow := Vector2(32 + direction * 20, 77)
		var hand := Vector2(32 + direction * 15, 95)
		_segment(shoulder, elbow, 6, 5, ink)
		_segment(elbow, hand, 5, 3.7, ink)
		_segment(shoulder, elbow, 4.2, 3.2, skin)
		_segment(elbow, hand, 3.2, 2, lit)
		_draw_hand(hand, false, tint, Vector2(direction * 0.25, 1).normalized())
	_draw_costume_head(pose, tint)
	_draw_costume_front(pose, tint)
	draw_set_transform(Vector2.ZERO)

func _draw_profile(kind: String, blink: int, direction: float, angle: float, tint: Color, shift: Vector2 = Vector2.ZERO) -> void:
	var squash := _landing * 0.10
	var scale2 := Vector2(direction * (1.0 + squash), (1.0 - squash + _launch * 0.08) * stretch) * PIXEL_SCALE
	draw_set_transform(shift, angle, scale2)
	var pose := _profile_pose()
	_draw_costume_back(pose, tint)
	_draw_pose_tail(pose, tint)
	_draw_limbs(true, kind, tint)
	_draw_pose_body(pose, tint, blink)
	_draw_limbs(false, kind, tint)
	_draw_costume_front(pose, tint)
	draw_set_transform(Vector2.ZERO)

func _draw_electro_silhouette(color: Color, border: float = 0.0) -> void:
	_body_ribbon(_profile_pose(), 1.0 + border * 0.07, Vector2.ZERO, color)
	_pixel_ellipse(Vector2(32, 27), Vector2(13 + border, 16 + border), color)
	for back: bool in [true, false]:
		for front: bool in [true, false]:
			var points := _profile_limb_points(front, back, _electro_kind)
			_segment(points[0], points[1], (6.0 if front else 8.0) + border * 2.0, 5.2 + border * 2.0, color)
			_segment(points[1], points[2], 5.2 + border * 2.0, 3.4 + border * 2.0, color)
			_pixel_ellipse(points[2], Vector2(4.0 + border, 5.0 + border), color)
	var previous := Vector2(35, 71)
	for i in range(1, 18):
		var u := float(i) / 17.0
		var point := Vector2(35 + sin(u * PI * 1.6 + _tail_phase) * u * 10.0, 71 + u * 42.0)
		_segment(previous, point, maxf(0.7, (1.0 - u) * 10.0) + border, maxf(0.7, (1.0 - u) * 9.0) + border, color)
		previous = point

func _draw_skeleton() -> void:
	var bone := Color("fffdeb")
	var dark := Color("182a3f")
	var spine := PackedVector2Array([Vector2(32, 36), Vector2(34, 45), Vector2(34, 57), Vector2(34, 72)])
	for i in range(spine.size() - 1):
		_segment(spine[i], spine[i + 1], 2.2, 2.2, bone)
	for i in range(5):
		var y := 41.0 + float(i) * 5.3
		_pixel_ellipse(Vector2(33.5, y), Vector2(2.4, 1.4), bone)
		for direction: float in [-1.0, 1.0]:
			var middle := Vector2(34 + direction * 5.0, y + 1.0)
			var end := Vector2(34 + direction * 7.5, y - 2.0)
			_segment(Vector2(34, y), middle, 1.4, 1.4, bone)
			_segment(middle, end, 1.4, 1.0, bone)
	_pixel_ellipse(Vector2(32, 26), Vector2(8.7, 10.5), bone)
	_pixel_ellipse(Vector2(35, 23), Vector2(2.8, 3.5), dark)
	_pixel_ellipse(Vector2(28, 22), Vector2(1.8, 2.5), dark)
	_segment(Vector2(27, 30), Vector2(36, 31), 1.5, 1.5, dark)
	for back: bool in [true, false]:
		for front: bool in [true, false]:
			var points := _profile_limb_points(front, back, _electro_kind)
			_segment(points[0], points[1], 2.0, 1.8, bone)
			_segment(points[1], points[2], 1.8, 1.4, bone)
			_pixel_ellipse(points[1], Vector2(1.7, 1.7), bone)
			for toe in range(3):
				var tip := points[2] + Vector2(-4, (float(toe) - 1.0) * 2.5)
				_segment(points[2], tip, 1.1, 0.7, bone)
	var previous := Vector2(35, 71)
	for i in range(1, 14):
		var u := float(i) / 13.0
		var point := Vector2(35 + sin(u * PI * 1.6 + _tail_phase) * u * 10.0, 71 + u * 42.0)
		_segment(previous, point, maxf(0.6, 2.0 - u * 1.5), maxf(0.5, 1.8 - u * 1.4), bone)
		previous = point

func _draw_electro() -> void:
	if _electro_clock >= ELECTRO_DURATION:
		return
	if _electro_clock < 0.48:
		var tremble := sin(_electro_clock * 150.0) * 1.3
		draw_set_transform(Vector2(tremble, 0), _electro_angle, Vector2(_electro_direction, 1.0) * PIXEL_SCALE)
		if _electro_clock < 0.36:
			_draw_electro_silhouette(Color("63caff"), 1.7)
			_draw_electro_silhouette(Color("183859"))
			_draw_skeleton()
			var flash := 1.0 if int(_electro_clock * 45.0) % 3 != 1 else 0.55
			var blue := Color(0.48, 0.86, 1.0, flash)
			for side_index: int in [-1, 1]:
				var x := 34.0 + float(side_index) * 17.0
				var arc := PackedVector2Array([Vector2(x, 31), Vector2(x + side_index * 5, 42), Vector2(x, 46), Vector2(x + side_index * 6, 60)])
				for i in range(arc.size() - 1):
					draw_line(arc[i] - ORIGIN, arc[i + 1] - ORIGIN, blue, 1.6, false)
		else:
			_draw_electro_silhouette(Color("161c23"))
		draw_set_transform(Vector2.ZERO)
		return
	var fade := 1.0 - smoothstep(0.98, ELECTRO_DURATION, _electro_clock)
	for i in range(_ash_positions.size()):
		var size := _ash_sizes[i]
		var ash := Color("141c25" if i % 4 else "34414a")
		ash.a = fade
		draw_rect(Rect2(_ash_positions[i] - Vector2.ONE * size * 0.5, Vector2.ONE * size), ash)

func _draw() -> void:
	if _frames.is_empty():
		return
	if _sync_detailed_visual():
		_draw_detailed_tongue()
		return
	if mode == "electrocuted":
		_draw_electro()
		return
	var kind := "jump" if mode == "jump" else ("run" if mode == "run" else "idle")
	var blink := 1 if fposmod(_clock, 4.1) > 3.96 else 0
	var direction := float(-side)
	var angle := sin(_clock) * 0.025 if kind == "idle" else 0.0
	if kind == "jump":
		angle = -float(side) * sin(jump_progress * PI) * 1.08
		if jump_progress > 0.72:
			direction = float(side)
	var tint := Color.WHITE.lerp(Color("d0ecff"), night_amount * 0.1)
	if mode == "hit":
		tint = tint.lerp(Color("ff998e"), _hurt)
	if mode == "sleep":
		_draw_wake(_sleep_pose(), 1, direction, tint)
	elif mode == "ground_idle":
		_draw_ground(tint, blink)
	elif mode in ["wake_climb", "climb_launch"]:
		_draw_wake(_wake_pose(), blink, direction, tint)
	else:
		_draw_profile(kind, blink, direction, angle, tint)
	if _eat_clock >= 0.0:
		var mouth := Vector2(-float(-side) * 14.4, -59.2)
		var target := _eat_world - position
		var reach := smoothstep(0.0, 0.075, _eat_clock) if _eat_clock < 0.075 else 1.0 - smoothstep(0.075, 0.18, _eat_clock)
		var tip := mouth.lerp(target, reach)
		if _eat_clock < 0.18:
			draw_line(mouth, tip, Color("713a63"), 5, false)
			draw_line(mouth + Vector2(1, -1), tip, Color("ef8e9d"), 2, false)
			var fly := target if _eat_clock < 0.075 else tip
			draw_rect(Rect2(fly - Vector2(4, 3), Vector2(8, 6)), Color("172b3a"))
			draw_rect(Rect2(fly + Vector2(-6, -5), Vector2(5, 3)), Color("c4e5df"))
			draw_rect(Rect2(fly + Vector2(3, -5), Vector2(5, 3)), Color("c4e5df"))
		elif int(_eat_clock * 70) % 2 == 0:
			draw_rect(Rect2(mouth, Vector2(5, 3)), Color("ef8e9d"))


# Costume layers are expressed in the rig's local coordinates. In particular,
# hats follow the same sleeping/waking head and plates follow the bent spine.
func _costume_polygon(points: Array, color: Color) -> void:
	var polygon := PackedVector2Array()
	for point: Vector2 in points:
		polygon.append(point - ORIGIN)
	if polygon.size() >= 3:
		draw_colored_polygon(polygon, color)

func _head_polygon(pose: Dictionary, points: Array, color: Color) -> void:
	var transformed: Array = []
	for point: Vector2 in points:
		transformed.append(_head_point(pose, point))
	_costume_polygon(transformed, color)

func _head_stroke(pose: Dictionary, points: Array, color: Color, width: float = 1.5) -> void:
	for i in range(points.size() - 1):
		_segment(_head_point(pose, points[i]), _head_point(pose, points[i + 1]), width, width, color)

func _star(at: Vector2, radius: float, color: Color, rotation_angle: float = 0.0) -> void:
	var polygon := PackedVector2Array()
	for i in range(8):
		var angle := float(i) * PI * 0.25 + rotation_angle
		polygon.append(at - ORIGIN + Vector2(cos(angle), sin(angle)) * radius * (1.0 if i % 2 == 0 else 0.29))
	draw_colored_polygon(polygon, color)

func _torso_plate(pose: Dictionary, u: float, length: float, width: float, color: Color) -> void:
	var center := _body_point(pose, u)
	var normal := _body_normal(pose, u)
	var along := normal.orthogonal()
	_costume_polygon([center + along * length + normal * width * 0.65,
		center + along * length * 0.6 - normal * width * 0.75,
		center - along * length - normal * width,
		center - along * length * 0.8 + normal * width], color)

func _tail_mark_color(index: int, tint: Color) -> Color:
	if skin_id == "rainbow_spark":
		return Color.from_hsv(fposmod(float(index) * 0.16 + 0.05, 1.0), 0.66, 1.0) * tint
	if skin_id in ["neon_pulse", "venom_chameleon", "electro_shock", "golden_champion", "frost_crystal", "star_wanderer"]:
		return _c("accent") * tint
	return _c("deep") * tint

func _costume_cape(pose: Dictionary, color: Color, trim: Color, jagged: bool = false) -> void:
	var upper := _body_point(pose, 0.89)
	var lower := _body_point(pose, 0.10)
	var normal := -_body_normal(pose, 0.40)
	var folded := lerpf(1.0, 0.48, float(pose["curl"]))
	var sway := sin(_tail_phase * 0.7) * 2.0 * folded
	var edge := lower + normal * 21.0 * folded + Vector2(sway, 6.0 * folded)
	var shoulder := upper - _body_normal(pose, 0.85) * 11.0 * folded
	var points: Array = [upper, shoulder, edge]
	if jagged:
		points.append(edge.lerp(lower, 0.28) + Vector2(-2, -5) * folded)
		points.append(edge.lerp(lower, 0.57) + Vector2(0, 3) * folded)
	points.append(lower)
	_costume_polygon(points, _c("ink"))
	_costume_polygon([upper.lerp(shoulder, 0.3), shoulder.lerp(edge, 0.12), edge.lerp(lower, 0.10), lower.lerp(upper, 0.10)], color)
	_segment(shoulder.lerp(edge, 0.08), edge.lerp(lower, 0.05), 1.6, 1.4, trim)
	_segment(upper.lerp(lower, 0.1) + normal * 3, edge.lerp(lower, 0.55), 1.0, 1.0, trim.darkened(0.35))

func _draw_costume_back(pose: Dictionary, tint: Color) -> void:
	if skin_id == "standard_green":
		return
	var accent := _c("accent") * tint
	match skin_id:
		"royal_pearl": _costume_cape(pose, Color("765590") * tint, accent)
		"steel_knight": _costume_cape(pose, Color("aa3e49") * tint, Color("e4a18d") * tint)
		"shadow_jumper":
			_costume_cape(pose, Color("3e2d53") * tint, Color("8a64b4") * tint, true)
			_head_polygon(pose, [Vector2(-16, 8), Vector2(-16, -11), Vector2(-8, -25), Vector2(8, -20), Vector2(17, -7), Vector2(15, 13)], Color("2d223e") * tint)
		"ghost_dragon":
			_costume_cape(pose, Color(0.61, 0.47, 0.78, 0.58) * tint, accent, true)
			var root_point := _body_point(pose, 0.73)
			var hip := _body_point(pose, 0.15)
			var normal := -_body_normal(pose, 0.55)
			_costume_polygon([root_point, root_point + normal * 19, hip + normal * 27, hip + normal * 11], Color(0.61, 0.45, 0.80, 0.55) * tint)
		"cyber_ninja":
			var upper := _body_point(pose, 0.8) - _body_normal(pose, 0.8) * 12
			var lower := _body_point(pose, 0.15) - _body_normal(pose, 0.15) * 17
			_segment(upper, lower, 3.7, 2.2, _c("ink") * tint)
			_segment(upper, lower, 1.4, 0.8, Color("a5b8c9") * tint)
			_segment(upper - Vector2(0, 8), upper, 4.0, 4.0, accent)
		"cosmo_gecko", "star_wanderer":
			_draw_orbit(pose, tint, false)
		"moon_ghost":
			for i in range(3):
				var h := _body_point(pose, 0.10 + float(i) * 0.25)
				var offset := Vector2(13 + i * 2, 8 + sin(_clock * 1.3 + i) * 3)
				_rotated_ellipse(h + offset, Vector2(4.0, 11.0), -0.4, Color(0.67, 0.87, 1.0, 0.16) * tint)
	if skin_id in ["jungle_hunter", "frost_crystal"]:
		for i in range(4):
			var u := 0.22 + float(i) * 0.18
			var center := _body_point(pose, u)
			var normal := -_body_normal(pose, u)
			var along := normal.orthogonal()
			var base := center + normal * _body_width(pose, u) * 0.7
			var tip := base + normal * (10.0 if skin_id == "frost_crystal" else 8.5) - along * 4
			_costume_polygon([base - along * 5, tip, base + along * 5], _c("ink") * tint)
			_costume_polygon([base - along * 3.7, tip - normal * 1.3, base + along * 3.7], accent if skin_id == "frost_crystal" else _c("lit") * tint)
			_segment(base, tip - normal, 1.0, 0.6, Color("f0fbdf") * tint)

func _draw_costume_body(pose: Dictionary, tint: Color) -> void:
	if skin_id == "standard_green":
		return
	var accent := _c("accent") * tint
	match skin_id:
		"desert_wanderer", "pirate_captain", "jungle_hunter":
			for i in range(5):
				var u := 0.25 + float(i) * 0.12
				var center := _body_point(pose, u)
				var normal := _body_normal(pose, u)
				_pixel_ellipse(center - normal * 3.7, Vector2(2.7, 2.2), _c("deep") * tint)
				_pixel_ellipse(center + normal * 3.4, Vector2(1.3, 1.6), _c("ink") * tint)
			if skin_id == "pirate_captain":
				var a := _body_point(pose, 0.75)
				var b := _body_point(pose, 0.30)
				_segment(a + _body_normal(pose, 0.75) * 7, b - _body_normal(pose, 0.30) * 6, 4, 4, Color("704b37") * tint)
				_torso_plate(pose, 0.28, 2.2, 9.0, Color("5e3330") * tint)
				_pixel_ellipse(b, Vector2(2.4, 2.3), Color("f0ca6b") * tint)
		"robo_gecko", "steel_knight", "volcanic_fighter":
			for i in range(3):
				var u := 0.30 + float(i) * 0.21
				var shade := _c("deep") if i % 2 else _c("lit")
				_torso_plate(pose, u, 4.7, _body_width(pose, u) * 0.81, shade * tint)
				var point := _body_point(pose, u)
				_segment(point - _body_normal(pose, u) * 4, point + _body_normal(pose, u) * 3, 1, 1, _c("pale") * tint)
			if skin_id == "robo_gecko":
				var chest := _body_point(pose, 0.67)
				_pixel_ellipse(chest, Vector2(4.0, 4.2), _c("ink") * tint)
				_pixel_ellipse(chest, Vector2(2.5, 2.8), accent)
				_pixel_ellipse(chest + Vector2(-0.7, -0.8), Vector2(0.8, 0.9), Color.WHITE * tint)
		"neon_pulse":
			var previous := _body_point(pose, 0.16)
			for i in range(1, 9):
				var u := 0.16 + float(i) * 0.08
				var point := _body_point(pose, u) + _body_normal(pose, u) * (4.0 if i % 2 else -2.0)
				_segment(previous, point, 1.7, 1.7, accent if i % 2 else Color("9affff") * tint)
				previous = point
		"electro_shock":
			var a := _body_point(pose, 0.76)
			var b := _body_point(pose, 0.25)
			var n := _body_normal(pose, 0.5)
			_costume_polygon([a + n * 4, a - n * 4, a.lerp(b, 0.49) - n * 2,
				a.lerp(b, 0.38) - n * 7, b + n, a.lerp(b, 0.56) + n * 4, a.lerp(b, 0.54) + n], accent)
		"cyber_ninja", "shadow_jumper":
			_torso_plate(pose, 0.66, 5.0, 7.0, _c("deep") * tint)
			_torso_plate(pose, 0.30, 2.1, 8.0, accent.darkened(0.30))
			var chest := _body_point(pose, 0.64)
			_segment(chest - _body_normal(pose, 0.64) * 4, chest + _body_normal(pose, 0.64) * 3, 1.4, 1.4, accent)
		"rainbow_spark":
			for i in range(5):
				var u := 0.24 + float(i) * 0.13
				_torso_plate(pose, u, 3.0, _body_width(pose, u) * 0.72, Color.from_hsv(float(i) * 0.17, 0.67, 1.0) * tint)
		"venom_chameleon":
			for i in range(7):
				var u := 0.22 + float(i) * 0.09
				var point := _body_point(pose, u) + _body_normal(pose, u) * (-3.0 if i % 2 else 3.0)
				_pixel_ellipse(point, Vector2(3.6, 2.8), accent)
				_pixel_ellipse(point + Vector2(0.5, -0.3), Vector2(1.6, 1.4), _c("skin") * tint)
		"cosmo_gecko", "star_wanderer", "moon_ghost":
			for i in range(7):
				var u := 0.24 + float(i) * 0.09
				var point := _body_point(pose, u) + _body_normal(pose, u) * (-3.6 if i % 2 else 3.6)
				_star(point, 1.5 if i % 3 else 2.5, accent, float(i) * 0.2)
		"pixel_gecko":
			for i in range(6):
				var point := _body_point(pose, 0.23 + float(i) * 0.11)
				draw_rect(Rect2((point - ORIGIN - Vector2(2, 2)).round(), Vector2(4, 4)), _c("lit") * tint if i % 2 else _c("deep") * tint)
		"frost_crystal":
			for i in range(3):
				var u := 0.32 + float(i) * 0.20
				_torso_plate(pose, u, 5.2, 5.0, Color("c9f7ff") * tint)
				var point := _body_point(pose, u)
				_segment(point - Vector2(1, 3), point + Vector2(1, 3), 1, 1, Color.WHITE * tint)
		"ghost_dragon":
			for i in range(3):
				var point := _body_point(pose, 0.32 + float(i) * 0.16)
				var n := _body_normal(pose, 0.32 + float(i) * 0.16)
				_segment(point - n * 5, point + n * 4, 1.6, 1.0, accent)
	if skin_id in ["golden_champion", "royal_pearl"]:
		var medal := _body_point(pose, 0.68)
		var chain := _body_point(pose, 0.90)
		_segment(chain, medal - Vector2(1, 3), 2.0, 2.0, accent)
		_pixel_ellipse(medal, Vector2(5.0, 5.6), Color("956523") * tint)
		_pixel_ellipse(medal + Vector2(-0.3, -0.4), Vector2(3.8, 4.4), Color("ffe99b") * tint)
		_segment(medal + Vector2(0, -2.3), medal + Vector2(0, 2.3), 1.1, 1.1, Color("a76d24") * tint)

func _draw_costume_limb(points: PackedVector2Array, back: bool, tint: Color) -> void:
	if not skin_id in ["robo_gecko", "steel_knight", "volcanic_fighter", "cyber_ninja", "neon_pulse", "frost_crystal"]:
		return
	var shade := _c("deep") if back else _c("lit")
	var middle := points[1].lerp(points[2], 0.35)
	_segment(points[1], middle, 4.6, 3.9, shade * tint)
	_pixel_ellipse(points[1], Vector2(2.5, 2.5), _c("ink") * tint)
	_pixel_ellipse(points[1], Vector2(1.4, 1.4), _c("accent") * tint)

func _draw_costume_head(pose: Dictionary, tint: Color) -> void:
	if skin_id == "standard_green":
		return
	var accent := _c("accent") * tint
	var ink := _c("ink") * tint
	match skin_id:
		"desert_wanderer":
			_head_polygon(pose, [Vector2(-19, -14), Vector2(-16, -18), Vector2(19, -18), Vector2(21, -13), Vector2(9, -10), Vector2(-13, -10)], Color("765335") * tint)
			_head_polygon(pose, [Vector2(-11, -15), Vector2(-10, -27), Vector2(-2, -29), Vector2(10, -25), Vector2(12, -15)], Color("e8c88b") * tint)
			_head_stroke(pose, [Vector2(-10, -17), Vector2(11, -17)], Color("92724a") * tint, 3)
			_draw_scarf(pose, Color("af5043") * tint)
		"pirate_captain":
			_head_polygon(pose, [Vector2(-19, -14), Vector2(-15, -26), Vector2(-5, -22), Vector2(12, -27), Vector2(19, -15), Vector2(9, -11), Vector2(-10, -11)], Color("332c33") * tint)
			_head_stroke(pose, [Vector2(-17, -15), Vector2(-14, -23), Vector2(-5, -20), Vector2(11, -24), Vector2(17, -15)], Color("e8bd66") * tint, 1.6)
			_pixel_ellipse(_head_point(pose, Vector2(0, -19)), Vector2(2.7, 2.5), Color("fff3cd") * tint)
			_head_stroke(pose, [Vector2(-3, -17), Vector2(3, -14)], Color("fff3cd") * tint, 1)
			_head_stroke(pose, [Vector2(-13, -8), Vector2(12, -7)], Color("3d2b2e") * tint, 1.7)
			_rotated_ellipse(_head_point(pose, Vector2(-8, -2)), Vector2(4.0, 4.4), float(pose["head_angle"]), Color("2e252e") * tint)
			_draw_scarf(pose, accent)
		"cyber_ninja", "volcanic_fighter":
			_head_polygon(pose, [Vector2(-12, -13), Vector2(11, -14), Vector2(13, -8), Vector2(-13, -7)], accent)
			_head_stroke(pose, [Vector2(-10, -11), Vector2(8, -12)], accent.lightened(0.35), 1.2)
			if skin_id == "cyber_ninja":
				_head_polygon(pose, [Vector2(-11, 3), Vector2(11, 2), Vector2(10, 10), Vector2(-5, 12)], Color("242530") * tint)
				_head_stroke(pose, [Vector2(-6, 6), Vector2(8, 5)], accent.darkened(0.25), 1)
			_draw_scarf(pose, accent)
		"shadow_jumper":
			_head_stroke(pose, [Vector2(-13, -9), Vector2(-6, -21), Vector2(8, -18), Vector2(14, -7)], Color("a48aca") * tint, 1.5)
			_head_polygon(pose, [Vector2(-11, 4), Vector2(11, 3), Vector2(9, 11), Vector2(-4, 12)], Color("332442") * tint)
		"jungle_hunter":
			for i in range(4):
				var base := Vector2(-10 + i * 6, -13)
				_head_polygon(pose, [base + Vector2(-4, 0), base + Vector2(-3 + i * 2, -12 - i % 2 * 3), base + Vector2(4, -1)], _c("deep") * tint)
				_head_stroke(pose, [base, base + Vector2(-2 + i * 2, -10)], _c("lit") * tint, 1.1)
			_draw_scarf(pose, Color("879442") * tint)
		"royal_pearl":
			_head_polygon(pose, [Vector2(-14, -12), Vector2(-15, -25), Vector2(-7, -19), Vector2(0, -29), Vector2(7, -19), Vector2(14, -25), Vector2(12, -12)], Color("9e762c") * tint)
			_head_polygon(pose, [Vector2(-11, -14), Vector2(-12, -22), Vector2(-6, -17), Vector2(0, -25), Vector2(6, -17), Vector2(11, -22), Vector2(10, -14)], accent)
			_pixel_ellipse(_head_point(pose, Vector2(0, -17)), Vector2(2.4, 2.6), Color("a875ce") * tint)
			for i in range(5):
				_pixel_ellipse(_head_point(pose, Vector2(-9 + i * 4.5, 13 + sin(i * 0.75) * 2)), Vector2(1.8, 1.8), Color("fff1d2") * tint)
		"golden_champion":
			for direction: int in [-1, 1]:
				for i in range(4):
					var at := Vector2(direction * (12.0 - i * 1.3), -4.0 - i * 4.8)
					var leaf := _head_point(pose, at + Vector2(direction * 2.5, -2.5))
					_rotated_ellipse(leaf, Vector2(2.4, 4.0), float(pose["head_angle"]) + float(direction) * 0.55, Color("ffdc73") * tint)
				_head_stroke(pose, [Vector2(direction * 12, 0), Vector2(direction * 7, -22)], Color("a97625") * tint, 1)
		"steel_knight":
			_head_polygon(pose, [Vector2(-14, -4), Vector2(-13, -15), Vector2(-4, -22), Vector2(7, -21), Vector2(14, -12), Vector2(15, 8), Vector2(10, 12), Vector2(10, 1), Vector2(9, -9), Vector2(-9, -7), Vector2(-9, 1)], Color("697487") * tint)
			_head_stroke(pose, [Vector2(-11, -10), Vector2(-4, -18), Vector2(6, -18), Vector2(11, -10)], Color("e7edf0") * tint, 2)
			_head_polygon(pose, [Vector2(-3, -19), Vector2(-2, -31), Vector2(4, -34), Vector2(12, -29), Vector2(18, -26), Vector2(8, -23), Vector2(3, -18)], accent)
		"robo_gecko":
			_head_polygon(pose, [Vector2(-12, -11), Vector2(-8, -19), Vector2(7, -18), Vector2(13, -10), Vector2(11, -6), Vector2(-9, -5)], _c("deep") * tint)
			_head_stroke(pose, [Vector2(-9, -10), Vector2(8, -12)], _c("pale") * tint, 2)
			_rotated_ellipse(_head_point(pose, Vector2(11, 2)), Vector2(3.3, 5), float(pose["head_angle"]), _c("ink") * tint)
			_rotated_ellipse(_head_point(pose, Vector2(11, 2)), Vector2(1.9, 3.5), float(pose["head_angle"]), accent)
		"frost_crystal", "venom_chameleon", "ghost_dragon":
			if skin_id == "ghost_dragon":
				for direction: int in [-1, 1]:
					_head_polygon(pose, [Vector2(direction * 8, -12), Vector2(direction * 20, -26), Vector2(direction * 15, -12), Vector2(direction * 13, -5)], Color("6d5685") * tint)
					_head_stroke(pose, [Vector2(direction * 12, -10), Vector2(direction * 18, -23)], accent, 1.7)
			elif skin_id == "frost_crystal":
				for i in range(3):
					var at := Vector2(-9 + i * 8, -13)
					_head_polygon(pose, [at + Vector2(-3, 1), at + Vector2(0, -15 + abs(i - 1) * 5), at + Vector2(4, -1)], Color("82d2f1") * tint)
					_head_stroke(pose, [at, at + Vector2(0, -11 + abs(i - 1) * 3)], Color.WHITE * tint, 1)
			else:
				_head_polygon(pose, [Vector2(-9, -12), Vector2(-5, -24), Vector2(5, -19), Vector2(12, -9)], accent)
				_head_stroke(pose, [Vector2(-5, -12), Vector2(-3, -19), Vector2(6, -12)], _c("lit") * tint, 1.6)
		"neon_pulse", "electro_shock", "cosmo_gecko", "star_wanderer", "moon_ghost":
			var points: Array = []
			for i in range(13):
				var angle := TAU * float(i) / 12.0
				points.append(Vector2(3, -3) + Vector2(cos(angle) * 7, sin(angle) * 8))
			_head_stroke(pose, points, accent, 1.0 if skin_id == "moon_ghost" else 1.6)
			if skin_id == "neon_pulse":
				_head_stroke(pose, [Vector2(10, -1), Vector2(13, 5), Vector2(5, 12)], Color("ff72e7") * tint, 1.6)
		"pixel_gecko":
			var point := _head_point(pose, Vector2(3, -3))
			draw_rect(Rect2(point - ORIGIN - Vector2(7, 7), Vector2(14, 14)), _c("ink") * tint, false, 1.2)

func _draw_scarf(pose: Dictionary, color: Color) -> void:
	_head_polygon(pose, [Vector2(-10, 11), Vector2(11, 10), Vector2(11, 16), Vector2(-9, 16)], color)
	var root_point := _head_point(pose, Vector2(10, 13))
	var trail := root_point + Vector2(15, 12 + sin(_tail_phase * 0.7) * 2)
	_costume_polygon([root_point, root_point + Vector2(6, -1), trail, trail + Vector2(-6, 0), root_point + Vector2(0, 3)], color)

func _draw_orbit(pose: Dictionary, tint: Color, front: bool) -> void:
	var center := _body_point(pose, 0.55)
	var previous := Vector2.ZERO
	var accent := _c("accent") * tint
	for i in range(25):
		var angle := TAU * float(i) / 24.0 + _clock * 0.20
		var point := center + Vector2(cos(angle) * 23.0, sin(angle) * 8.5).rotated(-0.37)
		if i > 0 and (sin(angle) >= 0.0) == front:
			_segment(previous, point, 1.2, 1.2, accent)
		previous = point

func _draw_costume_front(pose: Dictionary, tint: Color) -> void:
	if skin_id == "standard_green":
		return
	var accent := _c("accent") * tint
	if skin_id in ["cosmo_gecko", "star_wanderer"]:
		_draw_orbit(pose, tint, true)
	if skin_id in ["cosmo_gecko", "star_wanderer", "golden_champion", "rainbow_spark", "moon_ghost", "ghost_dragon", "pixel_gecko", "electro_shock"]:
		for i in range(4):
			var anchor := _body_point(pose, 0.18 + float(i) * 0.22)
			var offset := Vector2(16.0 + float(i % 2) * 6.0, sin(_clock * 1.1 + i * 1.7) * 2)
			var point := anchor + offset
			var color := accent
			if skin_id == "rainbow_spark":
				color = Color.from_hsv(float(i) * 0.23, 0.6, 1.0) * tint
			if skin_id == "pixel_gecko":
				draw_rect(Rect2((point - ORIGIN).round(), Vector2.ONE * (2 + i % 2)), color)
			elif skin_id == "electro_shock":
				var bolt := [point + Vector2(1, -5), point + Vector2(-3, 0), point + Vector2(2, -1), point + Vector2(-1, 5)]
				for j in range(3):
					_segment(bolt[j], bolt[j + 1], 1.2, 1.2, color)
			elif skin_id == "ghost_dragon":
				_pixel_ellipse(point, Vector2(2.2, 4.4), Color(color.r, color.g, color.b, 0.38))
			else:
				var pulse := 0.75 + 0.25 * sin(_clock * 1.2 + i * 2)
				_star(point, (2.0 + float(i % 2)) * pulse, color)


# Full-resolution character art.  The older drawing helpers above also supply
# the brief electrical skeleton and a safe editor fallback when art is absent.
func _ensure_detailed_nodes() -> void:
	if is_instance_valid(_detailed_root):
		return
	_detailed_root = Node2D.new()
	_detailed_root.name = "IllustratedCharacter"
	_detailed_root.show_behind_parent = true
	add_child(_detailed_root)
	_detailed_run = MeshInstance2D.new()
	_detailed_run.name = "ClimbingPose"
	_detailed_run.material = ShaderMaterial.new()
	(_detailed_run.material as ShaderMaterial).shader = DETAILED_SHADER
	_detailed_root.add_child(_detailed_run)
	_detailed_sleep = MeshInstance2D.new()
	_detailed_sleep.name = "SleepingPose"
	_detailed_sleep.material = ShaderMaterial.new()
	(_detailed_sleep.material as ShaderMaterial).shader = DETAILED_SHADER
	_detailed_root.add_child(_detailed_sleep)
	_detailed_root.hide()

func _detailed_entry() -> Dictionary:
	if _detailed_catalog.is_empty() and FileAccess.file_exists(DETAILED_CATALOG):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DETAILED_CATALOG))
		if parsed is Dictionary:
			_detailed_catalog = parsed.get("skins", parsed)
	var entry: Variant = _detailed_catalog.get(skin_id, {})
	return entry if entry is Dictionary else {}

func _vector_from_data(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback

func _detailed_geometry(size: Vector2, anchor: Vector2) -> ArrayMesh:
	var key := "%s:%s" % [size, anchor]
	if _detailed_meshes.has(key):
		return _detailed_meshes[key]
	const COLUMNS := 24
	const ROWS := 40
	var vertices := PackedVector3Array()
	var coordinates := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in range(ROWS + 1):
		for x in range(COLUMNS + 1):
			var uv := Vector2(float(x) / COLUMNS, float(y) / ROWS)
			var point := (uv - anchor) * size
			vertices.append(Vector3(point.x, point.y, 0.0))
			coordinates.append(uv)
	for y in range(ROWS):
		for x in range(COLUMNS):
			var index := y * (COLUMNS + 1) + x
			indices.append_array(PackedInt32Array([index, index + 1, index + COLUMNS + 2,
				index, index + COLUMNS + 2, index + COLUMNS + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = coordinates
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_detailed_meshes[key] = mesh
	return mesh

func _configure_detailed_mesh(node: MeshInstance2D, data: Dictionary, asleep: bool) -> bool:
	var path: String = str(data.get("texture", data.get("image", data.get("atlas", ""))))
	var region_data: Variant = data.get("rect", data.get("region", data.get("slot_rect", [])))
	if path.is_empty() or not region_data is Array or region_data.size() < 4:
		return false
	if not _detailed_textures.has(path):
		if not ResourceLoader.exists(path):
			return false
		var resource: Resource = load(path)
		if not resource is Texture2D:
			return false
		_detailed_textures[path] = resource
	var texture: Texture2D = _detailed_textures[path]
	var region := Rect2(float(region_data[0]), float(region_data[1]), float(region_data[2]), float(region_data[3]))
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return false
	var height := float(data.get("display_height", 112.0 if asleep else 205.0))
	var size := _vector_from_data(data.get("display_size"), Vector2(region.size.x / region.size.y * height, height))
	var anchor := _vector_from_data(data.get("anchor"), Vector2(0.5, 1.0) if asleep else Vector2(0.30, 0.50))
	var eye: Variant = data.get("eye", [])
	if not eye is Array or eye.size() < 4:
		var center := _vector_from_data(data.get("eye_center_uv", data.get("eye_center")), Vector2(0.62, 0.20))
		var radius := _vector_from_data(data.get("eye_radius_uv", data.get("eye_radius")), Vector2(0.09, 0.065))
		eye = [center.x, center.y, radius.x, radius.y]
	node.mesh = _detailed_geometry(size, anchor)
	node.texture = texture
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if skin_id == "pixel_gecko" else CanvasItem.TEXTURE_FILTER_LINEAR
	node.position = _vector_from_data(data.get("offset"), Vector2(0.0, GROUND_FEET_Y) if asleep else Vector2.ZERO)
	var shader := node.material as ShaderMaterial
	shader.set_shader_parameter("atlas_rect", Vector4(region.position.x / texture.get_width(), region.position.y / texture.get_height(), region.size.x / texture.get_width(), region.size.y / texture.get_height()))
	shader.set_shader_parameter("body_size", size)
	shader.set_shader_parameter("body_anchor", anchor)
	shader.set_shader_parameter("eye_region", Vector4(float(eye[0]), float(eye[1]), float(eye[2]), float(eye[3])))
	var lid_color := _c("deep").lerp(_c("skin"), 0.40)
	if skin_id == "standard_green":
		lid_color = Color("93c92d")
	shader.set_shader_parameter("eyelid_color", lid_color)
	shader.set_shader_parameter("second_eye_region", Vector4(0.935, 0.145, 0.054, 0.086) if skin_id == "standard_green" and not asleep else Vector4.ZERO)
	shader.set_shader_parameter("sleeping", 1.0 if asleep else 0.0)
	if not asleep:
		var mouth := _vector_from_data(data.get("mouth"), Vector2(0.35, 0.29))
		_detailed_mouth = (mouth - anchor) * size + node.position
	return true

func _sync_detailed_visual() -> bool:
	_ensure_detailed_nodes()
	if mode == "electrocuted":
		_detailed_root.hide()
		_detailed_active = false
		return false
	var entry := _detailed_entry()
	if not entry.get("run", {}) is Dictionary or (entry.get("run", {}) as Dictionary).is_empty():
		_detailed_root.hide()
		_detailed_active = false
		return false
	if _detailed_run_key != skin_id:
		if not _configure_detailed_mesh(_detailed_run, entry["run"], false):
			_detailed_root.hide()
			return false
		_detailed_run_key = skin_id
	var waking: bool = mode in ["wake_climb", "climb_launch"]
	var asleep: bool = mode in ["sleep", "ground_idle"]
	var sleep_alpha := 1.0 if asleep else (1.0 - smoothstep(0.21, 0.36, launch_progress) if waking else 0.0)
	if sleep_alpha > 0.0 and _detailed_sleep_key != skin_id:
		if _configure_detailed_mesh(_detailed_sleep, entry.get("sleep", {}), true):
			_detailed_sleep_key = skin_id
		else:
			sleep_alpha = 0.0
	var direction := float(-side)
	var angle := 0.0
	if mode == "jump":
		angle = -float(side) * sin(jump_progress * PI) * 1.08
		if jump_progress > 0.72:
			direction = float(side)
	var tint := Color.WHITE.lerp(Color("d0ecff"), night_amount * 0.10)
	if mode == "hit":
		tint = tint.lerp(Color("ff998e"), _hurt)
	_detailed_root.show()
	_detailed_root.rotation = angle
	_detailed_root.scale = Vector2(direction * (1.0 + _landing * 0.045 - _launch * 0.035), stretch * (1.0 - _landing * 0.07 + _launch * 0.045))
	_detailed_run.visible = sleep_alpha < 1.0
	_detailed_sleep.visible = sleep_alpha > 0.0 and _detailed_sleep_key == skin_id
	_detailed_run.modulate = Color(tint.r, tint.g, tint.b, 1.0 - sleep_alpha)
	_detailed_sleep.modulate = Color(tint.r, tint.g, tint.b, sleep_alpha)
	var shader := _detailed_run.material as ShaderMaterial
	var blink_time := fposmod(_clock, 4.1)
	var closed := smoothstep(3.94, 3.99, blink_time) * (1.0 - smoothstep(4.035, 4.095, blink_time))
	if waking:
		closed = maxf(closed, 1.0 - smoothstep(0.22, 0.33, launch_progress))
	shader.set_shader_parameter("closed_eye", closed)
	shader.set_shader_parameter("stride_phase", _stride_phase)
	shader.set_shader_parameter("tail_phase", _tail_phase)
	shader.set_shader_parameter("crawl_amount", 1.0 if mode == "run" else (smoothstep(0.58, 0.76, launch_progress) if waking else 0.0))
	shader.set_shader_parameter("breathing", sin(_clock * TAU / 5.4) * 0.60)
	shader.set_shader_parameter("unfold", 1.0 if waking else 0.0)
	shader.set_shader_parameter("wake_curl", 1.0 - smoothstep(0.42, 0.70, launch_progress) if waking else 0.0)
	if waking:
		var pose := _wake_pose()
		var rest := _profile_pose()
		for key: String in ["hip", "control", "control2", "chest"]:
			shader.set_shader_parameter("pose_" + key, (pose[key] - ORIGIN) * PIXEL_SCALE)
		shader.set_shader_parameter("head_shift", (pose["head"] - rest["head"]) * PIXEL_SCALE)
		# A small chin lift preserves the painted face instead of rotating its
		# large illustrated eye through the neck while the torso uncurls.
		shader.set_shader_parameter("head_turn", float(pose["head_angle"]) * 0.15)
	if _detailed_sleep.visible:
		var rest_shader := _detailed_sleep.material as ShaderMaterial
		rest_shader.set_shader_parameter("breathing", sin(_clock * TAU / 5.4) * 1.4)
		# The same curled body stirs and lifts before the spine unfolds.
		_detailed_sleep.rotation = -0.035 * smoothstep(0.20, 0.35, launch_progress) if waking else 0.0
	_detailed_active = true
	return true

func _draw_detailed_tongue() -> void:
	if _eat_clock < 0.0:
		return
	var mouth := _detailed_root.transform * _detailed_mouth
	var target := _eat_world - position
	var reach := smoothstep(0.0, 0.075, _eat_clock) if _eat_clock < 0.075 else 1.0 - smoothstep(0.075, 0.18, _eat_clock)
	var tip := mouth.lerp(target, reach)
	if _eat_clock < 0.18:
		draw_line(mouth, tip, Color("713a63"), 4.0, true)
		draw_line(mouth + Vector2(0.5, -0.7), tip, Color("ef8e9d"), 1.8, true)
		var fly := target if _eat_clock < 0.075 else tip
		draw_circle(fly, 3.0, Color("172b3a"), true, -1.0, true)
		draw_ellipse(fly + Vector2(-3, -3), 3.7, 1.9, Color("c4e5df"))
		draw_ellipse(fly + Vector2(3, -3), 3.7, 1.9, Color("c4e5df"))
