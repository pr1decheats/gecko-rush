class_name GeckoVisual
extends Node2D
## Original pixel bodies with continuously articulated limbs and a slow tail.
## Only the small body textures are cached; no images are generated per frame.
const PIXEL_SCALE := 1.6
const ORIGIN := Vector2(32, 55)
const GROUND_FEET_Y := 90.0
const ELECTRO_DURATION := 1.4
const ASH_COUNT := 44
static var _frames: Dictionary = {}
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
	var tail_hz := clampf(0.38 + (_visual_speed_factor - 1.0) * 0.075, 0.34, 0.53) if running else 0.20
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
	return {"hip": Vector2(34, 72), "chest": Vector2(32, 35), "control": Vector2(36, 53),
		"head": Vector2(32, 26), "head_angle": 0.0, "curl": 0.0, "unfold": 1.0,
		"rise": 1.0, "crawl": 1.0, "alert": 0.0, "eyes": 1.0}

func _mix_pose(a: Dictionary, b: Dictionary, amount: float) -> Dictionary:
	var pose: Dictionary = {}
	for key: String in ["hip", "chest", "control", "head"]:
		var point: Vector2 = a[key]
		pose[key] = point.lerp(b[key], amount)
	for key: String in ["head_angle", "curl", "unfold", "rise", "crawl", "alert", "eyes"]:
		pose[key] = lerpf(float(a[key]), float(b[key]), amount)
	return pose

func _sleep_pose() -> Dictionary:
	var breath := sin(_clock * 1.6) * 0.42
	return {"hip": Vector2(42, 91), "chest": Vector2(28, 84 + breath), "control": Vector2(37, 76 + breath),
		"head": Vector2(20, 94 + breath * 0.4), "head_angle": -1.9, "curl": 1.0, "unfold": 0.0,
		"rise": 0.0, "crawl": 0.0, "alert": 0.0, "eyes": 0.0}

func _wake_pose() -> Dictionary:
	var asleep := _sleep_pose()
	var awake := {"hip": Vector2(42, 91), "chest": Vector2(27, 83), "control": Vector2(37, 76),
		"head": Vector2(20, 77), "head_angle": -1.1, "curl": 0.95, "unfold": 0.0,
		"rise": 0.0, "crawl": 0.0, "alert": 1.0, "eyes": 1.0}
	var extended := {"hip": Vector2(47, 88), "chest": Vector2(25, 81), "control": Vector2(37, 79),
		"head": Vector2(14, 76), "head_angle": -1.35, "curl": 0.48, "unfold": 1.0,
		"rise": 0.0, "crawl": 0.35, "alert": 0.25, "eyes": 1.0}
	if launch_progress <= 0.20:
		return asleep
	if launch_progress < 0.42:
		return _mix_pose(asleep, awake, smoothstep(0.20, 0.42, launch_progress))
	if launch_progress < 0.58:
		return _mix_pose(awake, extended, smoothstep(0.42, 0.58, launch_progress))
	return _mix_pose(extended, _profile_pose(), smoothstep(0.58, 0.70, launch_progress))

func _body_point(pose: Dictionary, u: float) -> Vector2:
	var hip: Vector2 = pose["hip"]
	var control: Vector2 = pose["control"]
	var chest: Vector2 = pose["chest"]
	return hip.bezier_interpolate(control, control, chest, u)

func _body_ribbon(pose: Dictionary, width_scale: float, offset: Vector2, color: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(11):
		var u := float(i) / 10.0
		var point := _body_point(pose, u)
		var tangent := _body_point(pose, minf(1.0, u + 0.02)) - _body_point(pose, maxf(0.0, u - 0.02))
		var normal := tangent.normalized().orthogonal()
		var width := (4.5 + sin(u * PI) * 7.6) * width_scale
		left.append(point - ORIGIN + offset + normal * width)
		right.append(point - ORIGIN + offset - normal * width)
	for i in range(right.size() - 1, -1, -1):
		left.append(right[i])
	# A curled spine can bend more sharply than its outer radius. Its hull keeps
	# the sleeping body solid instead of making a self-intersecting ribbon.
	var outline := Geometry2D.convex_hull(left)
	if outline.size() > 3:
		outline.remove_at(outline.size() - 1)
		draw_colored_polygon(outline, color)

func _rotated_ellipse(at: Vector2, radius: Vector2, angle: float, color: Color) -> void:
	var polygon := PackedVector2Array()
	for i in range(12):
		var a := TAU * float(i) / 12.0
		polygon.append(at - ORIGIN + (Vector2(cos(a), sin(a)) * radius).rotated(angle))
	draw_colored_polygon(polygon, color)

func _head_point(pose: Dictionary, offset: Vector2) -> Vector2:
	var head: Vector2 = pose["head"]
	return head + offset.rotated(float(pose["head_angle"]))

func _draw_pose_body(pose: Dictionary, tint: Color, blink: int) -> void:
	var ink := Color("192f32") * tint
	var deep := Color("315c44") * tint
	var skin := Color("70ad50") * tint
	var lit := Color("aad969") * tint
	var pale := Color("d8e99b") * tint
	_body_ribbon(pose, 1.0, Vector2.ZERO, ink)
	_body_ribbon(pose, 0.87, Vector2.ZERO, deep)
	_body_ribbon(pose, 0.73, Vector2(-1.3, -0.3), skin)
	var previous := _body_point(pose, 0.12) + Vector2(-5, 0)
	for i in range(1, 8):
		var u := 0.12 + float(i) * 0.095
		var point := _body_point(pose, u) + Vector2(-5, 0)
		_segment(previous, point, 4.4, 4.4, pale)
		previous = point
	for i in range(5):
		var point := _body_point(pose, 0.22 + float(i) * 0.13)
		_pixel_ellipse(point + Vector2(4.5, 0), Vector2(2.3, 1.6), deep)
		_pixel_ellipse(point + Vector2(0, -1.3), Vector2(1.6, 0.65), lit)
	var head: Vector2 = pose["head"]
	var angle := float(pose["head_angle"])
	_rotated_ellipse(head + Vector2(0, 1).rotated(angle), Vector2(13, 16), angle, ink)
	_rotated_ellipse(head, Vector2(11, 14), angle, skin)
	_rotated_ellipse(_head_point(pose, Vector2(-6, -8)), Vector2(5.5, 7.8), angle, lit)
	_rotated_ellipse(_head_point(pose, Vector2(-8, 0)), Vector2(3.8, 7.0), angle, pale)
	_segment(_head_point(pose, Vector2(-6, 6)), _head_point(pose, Vector2(0, 9)), 1.5, 1.2, deep)
	_pixel_ellipse(_head_point(pose, Vector2(-8, -7)), Vector2(1.0, 1.0), deep)
	var eye := _head_point(pose, Vector2(3, -3))
	_rotated_ellipse(eye, Vector2(6, 7), angle, ink)
	if blink == 1 or float(pose["eyes"]) < 0.35:
		_rotated_ellipse(eye, Vector2(5.3, 6.0), angle, skin)
		_segment(_head_point(pose, Vector2(-1, -2)), _head_point(pose, Vector2(7, -2)), 1.8, 1.8, deep)
		_segment(_head_point(pose, Vector2(-1, -3.4)), _head_point(pose, Vector2(7, -3.4)), 1.0, 1.0, lit)
	else:
		var surprise := float(pose["alert"])
		_rotated_ellipse(eye + Vector2(0, -0.6).rotated(angle), Vector2(4.2 + surprise * 0.7, 5.2 + surprise * 0.6), angle, Color("f7f5d7") * tint)
		_rotated_ellipse(_head_point(pose, Vector2(2, -4)), Vector2(1.6, 4.0), angle, ink)
		_pixel_ellipse(_head_point(pose, Vector2(1.5, -6)), Vector2(1.1, 1.1), Color.WHITE * tint)

func _draw_pose_tail(pose: Dictionary, tint: Color) -> void:
	var curl := float(pose["curl"])
	var root: Vector2 = pose["hip"]
	root += Vector2(1, -1).lerp(Vector2(2, 2), curl)
	var previous := root
	for k in range(1, 25):
		var u := float(k) / 24.0
		var straight := Vector2(sin(u * PI * 1.6 + _tail_phase) * u * 10.0, u * 42.0)
		var coiled := Vector2.ZERO.bezier_interpolate(Vector2(38, 26), Vector2(29, -43), Vector2(-7, -19), u)
		coiled.y += sin(_tail_phase + u * 3.0) * u * 0.6
		var point := root + straight.lerp(coiled, curl)
		var thickness := maxf(0.8, (1.0 - u) * 9.0)
		_segment(previous, point, thickness + 1.5, thickness + 1.0, Color("192f32") * tint)
		_segment(previous + Vector2(0, -0.5), point + Vector2(0, -0.5), thickness, maxf(0.7, thickness - 0.8), Color("70ad50" if k % 6 < 4 else "315c44") * tint)
		previous = point

func _draw_tail(tint: Color, ground: bool = false) -> void:
	var ink := Color("192f32") * tint
	var deep := Color("315c44") * tint
	var skin := Color("70ad50") * tint
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
	var ink := Color("192f32") * tint
	var skin := Color("315c44" if back else "70ad50") * tint
	var lit := Color("70ad50" if back else "aad969") * tint
	var pale := Color("70ad50" if back else "d8e99b") * tint
	_pixel_ellipse(foot, Vector2(3.7, 4.5), ink)
	_pixel_ellipse(foot - direction * 0.2, Vector2(2.7, 3.2), skin)
	# Four splayed, jointed digits end in the broad adhesive pads of a gecko.
	for toe in range(4):
		var spread := (float(toe) - 1.5) * 0.42
		var reach := direction.rotated(spread)
		var length := 6.0 + (1.0 if toe in [1, 2] else 0.0)
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

func _draw_limb_chain(points: PackedVector2Array, front: bool, back: bool, tint: Color, hand_direction: Vector2 = Vector2.LEFT) -> void:
	var ink := Color("192f32") * tint
	var skin := Color("315c44" if back else "70ad50") * tint
	var lit := Color("70ad50" if back else "aad969") * tint
	var shoulder := points[0]
	var elbow := points[1]
	var foot := points[2]
	var thigh_width := 6.0 if front else 8.0
	_segment(shoulder, elbow, thigh_width + 1.6, 5.2, ink)
	_pixel_ellipse(elbow, Vector2(3.2, 3.2), ink)
	_segment(elbow, foot, 5.2, 3.4, ink)
	_segment(shoulder, elbow, thigh_width, 3.5, skin)
	_pixel_ellipse(elbow, Vector2(2.2, 2.2), skin)
	_segment(elbow, foot, 3.4, 2.0, skin)
	_segment(shoulder + Vector2(0, -0.9), elbow + Vector2(0, -0.6), 1.5, 1.0, lit)
	_draw_hand(foot, back, tint, hand_direction)

func _draw_limbs(back: bool, kind: String, tint: Color) -> void:
	for front: bool in [true, false]:
		_draw_limb_chain(_profile_limb_points(front, back, kind), front, back, tint)

func _draw_wake_limbs(pose: Dictionary, back: bool, tint: Color) -> void:
	for front: bool in [true, false]:
		var sleep_points := PackedVector2Array([
			Vector2(27, 86) if front else Vector2(43, 91),
			Vector2(31, 99) if front else Vector2(48, 99),
			Vector2(25, 104) if front else Vector2(43, 104)])
		var ground_points := PackedVector2Array([
			Vector2(25, 81) if front else Vector2(45, 87),
			Vector2(13, 91) if front else Vector2(54, 95),
			Vector2(18, 104) if front else Vector2(48, 104)])
		var profile_points := _profile_limb_points(front, back, "run", float(pose["crawl"]))
		var points := PackedVector2Array()
		for i in range(3):
			var point := sleep_points[i].lerp(ground_points[i], float(pose["unfold"]))
			if back:
				point += Vector2(-2, -4)
			points.append(point.lerp(profile_points[i], float(pose["rise"])))
		var hand_direction := Vector2.DOWN.lerp(Vector2.LEFT, float(pose["rise"])).normalized()
		_draw_limb_chain(points, front, back, tint, hand_direction)

func _draw_wake(pose: Dictionary, blink: int, direction: float, tint: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(direction, 1.0) * PIXEL_SCALE)
	_draw_pose_tail(pose, tint)
	_draw_wake_limbs(pose, true, tint)
	_draw_pose_body(pose, tint, blink)
	_draw_wake_limbs(pose, false, tint)
	draw_set_transform(Vector2.ZERO)

func _draw_ground(tint: Color, blink: int, lean: float = 0.0, narrowing: float = 1.0) -> void:
	draw_set_transform(Vector2.ZERO, lean, Vector2(PIXEL_SCALE * narrowing, PIXEL_SCALE))
	_draw_tail(tint, true)
	var ink := Color("192f32") * tint
	var skin := Color("70ad50") * tint
	var lit := Color("aad969") * tint
	for direction: int in [-1, 1]:
		var hip := Vector2(32 + direction * 10, 84)
		var knee := Vector2(32 + direction * 23, 94)
		var foot := Vector2(32 + direction * 21, 104)
		_segment(hip, knee, 9, 8, ink)
		_segment(knee, foot, 7, 5, ink)
		_segment(hip, knee, 6.8, 5.8, skin)
		_segment(knee, foot, 4.8, 3, lit)
		_draw_hand(foot, false, tint, Vector2(direction * 0.5, 1).normalized())
	draw_texture_rect(_frames["ground%d" % blink], Rect2(-ORIGIN + Vector2(0, sin(_clock * 1.6) * 0.5), Vector2(64, 120)), false, tint)
	for direction: int in [-1, 1]:
		var shoulder := Vector2(32 + direction * 11, 66)
		var elbow := Vector2(32 + direction * 20, 77)
		var hand := Vector2(32 + direction * 15, 95)
		_segment(shoulder, elbow, 6, 5, ink)
		_segment(elbow, hand, 5, 3.7, ink)
		_segment(shoulder, elbow, 4.2, 3.2, skin)
		_segment(elbow, hand, 3.2, 2, lit)
		_draw_hand(hand, false, tint, Vector2(direction * 0.25, 1).normalized())
	draw_set_transform(Vector2.ZERO)

func _draw_profile(kind: String, blink: int, direction: float, angle: float, tint: Color, shift: Vector2 = Vector2.ZERO) -> void:
	var squash := _landing * 0.10
	var scale2 := Vector2(direction * (1.0 + squash), (1.0 - squash + _launch * 0.08) * stretch) * PIXEL_SCALE
	draw_set_transform(shift, angle, scale2)
	var pose := _profile_pose()
	_draw_pose_tail(pose, tint)
	_draw_limbs(true, kind, tint)
	_draw_pose_body(pose, tint, blink)
	_draw_limbs(false, kind, tint)
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
