class_name GeckoVisual
extends Node2D
## Compact articulated character: one continuous body and an explicit head,
## four jointed limbs and a flexible tail. Every skin uses this same live rig.
## No painted full-body sprite is stretched to simulate walking.
const PIXEL_SCALE := 1.6
const ORIGIN := Vector2(32, 55)
const GROUND_FEET_Y := 95.0
const ELECTRO_DURATION := 1.4
const ASH_COUNT := 44
const RENDERER_REVISION := 27
const MAX_TONGUE_REACH := 105.0
const TONGUE_EXTEND_SECONDS := 0.055
const TONGUE_RETRACT_SECONDS := 0.17
var _eat_offset := Vector2.ZERO
# Body colors and costume accents share a small, deterministic palette. The
# artwork is articulated with the original rig; skins never change collisions.
const SKIN_PALETTES := {
	"standard_green": ["243b2f", "416d44", "7db64d", "b5d974", "e2edb5", "e5ca73"],
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
var _skin_colors: Array[Color] = [Color("243b2f"), Color("416d44"), Color("7db64d"), Color("b5d974"), Color("e2edb5"), Color("e5ca73")]
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
# Main supplies a render-only sample; gameplay still reads mode/side/progress.
var _render_motion: Dictionary = {}

func set_render_motion(kind: String, wall_side: int, progress: float) -> void:
	_render_motion = {"mode": kind, "side": wall_side, "jump": clampf(progress, 0.0, 1.0)}
	queue_redraw()

func clear_render_motion() -> void:
	_render_motion.clear()
	queue_redraw()

func _motion_mode() -> String:
	return str(_render_motion.get("mode", mode))

func _motion_side() -> int:
	return int(_render_motion.get("side", side))

func _motion_jump() -> float:
	return float(_render_motion.get("jump", jump_progress))

func _jump_projection(progress: float, wall_side: int) -> Vector2:
	# A continuous half turn, rather than changing reflection on one frame.
	# The unprojected torso volume keeps the narrow, edge-on middle visible.
	var turn := smoothstep(0.18, 0.82, clampf(progress, 0.0, 1.0)) * PI
	return Vector2(-float(wall_side) * cos(turn), -float(wall_side) * sin(progress * PI) * 0.82)

func _ready() -> void:
	# Every visible pose is drawn from the rig, including sleep and waking.
	queue_redraw()

func set_skin(id: String) -> void:
	# It is valid to configure a shop preview before adding it to the tree.
	skin_id = id if SKIN_PALETTES.has(id) else "standard_green"
	_skin_palette = SKIN_PALETTES[skin_id]
	for i in range(6):
		_skin_colors[i] = Color(_skin_palette[i])
	queue_redraw()

func _c(name: String) -> Color:
	var index: int = PALETTE_INDEX.get(name, 2)
	var color := _skin_colors[index]
	if skin_id == "moon_ghost" and index in [1, 2, 3, 4]:
		color.a = 0.86
	elif skin_id == "ghost_dragon" and index in [1, 2, 3]:
		color.a = 0.93
	return color

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
	var stride_hz := clampf(1.65 + (_visual_speed_factor - 1.0) * 0.32, 1.45, 2.29) if running else 0.22
	var tail_hz := clampf(0.38 + (_visual_speed_factor - 1.0) * 0.075, 0.34, 0.53) if running else (0.055 if mode == "sleep" else 0.20)
	_stride_phase = fposmod(_stride_phase + delta * TAU * stride_hz, TAU)
	_tail_phase = fposmod(_tail_phase + delta * TAU * tail_hz, TAU)
	_landing = move_toward(_landing, 0.0, delta * 7.0)
	_launch = move_toward(_launch, 0.0, delta * 10.0)
	_hurt = move_toward(_hurt, 0.0, delta * 2.5)
	if mode in ["jump", "hit", "sleep", "ground_idle"]:
		_eat_clock = -1.0
	if _eat_clock >= 0:
		_eat_clock += delta
		if _eat_clock >= 0.23:
			_eat_clock = -1.0
	queue_redraw()

func reset_animation() -> void:
	clear_render_motion()
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
	_eat_offset = Vector2.ZERO
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
	var projection := _jump_projection(jump_progress, side) if was_jump else Vector2(float(-side), 0.0)
	_electro_direction = projection.x
	_electro_angle = projection.y
	_electro_kind = "jump" if was_jump else "run"
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
	if mode in ["jump", "hit", "electrocuted", "sleep", "ground_idle"] or is_eating() or not local_target.is_finite():
		return
	# Keep the captured insect relative to the moving mouth. A world-fixed
	# point would trail thousands of pixels behind the runner at high speed.
	_eat_offset = (local_target - get_mouth_position()).limit_length(MAX_TONGUE_REACH)
	_eat_world = position + local_target # retained for old save/debug consumers
	_eat_clock = 0.0

func get_render_pose() -> Dictionary:
	if mode in ["sleep", "ground_idle"]:
		return _sleep_pose()
	if mode in ["wake_climb", "climb_launch"]:
		return _wake_pose()
	return _profile_pose()

func _character_transform(rendered: bool = false) -> Transform2D:
	var visual_mode := _motion_mode() if rendered else mode
	var visual_side := _motion_side() if rendered else side
	var progress := _motion_jump() if rendered else jump_progress
	var projection := _jump_projection(progress, visual_side) if visual_mode == "jump" else Vector2(float(-visual_side), 0.0)
	var squash := _landing * 0.06
	var body_scale := Vector2(projection.x * (1.0 + squash), stretch * (1.0 - squash + _launch * 0.045)) * PIXEL_SCALE
	return Transform2D(projection.y, body_scale, 0.0, Vector2.ZERO)

func get_mouth_position(rendered: bool = false) -> Vector2:
	var pose := get_render_pose()
	return _character_transform(rendered) * (_head_point(pose, Vector2(-14.0, 5.0)) - ORIGIN)

func get_tongue_geometry() -> Dictionary:
	var mouth := get_mouth_position(true)
	var active := _eat_clock >= 0.0 and _eat_clock < TONGUE_RETRACT_SECONDS and _motion_mode() in ["run", "idle", "wake_climb", "climb_launch"]
	var reach := 0.0
	if active:
		reach = smoothstep(0.0, TONGUE_EXTEND_SECONDS, _eat_clock) if _eat_clock <= TONGUE_EXTEND_SECONDS else 1.0 - smoothstep(TONGUE_EXTEND_SECONDS, TONGUE_RETRACT_SECONDS, _eat_clock)
	var tip := mouth + _eat_offset * clampf(reach, 0.0, 1.0)
	var middle := mouth.lerp(tip, 0.50) + Vector2(0.0, sin(PI * reach) * 2.3)
	return {"active": active, "mouth": mouth, "tip": tip, "points": PackedVector2Array([mouth, middle, tip]), "caught": active and _eat_clock >= TONGUE_EXTEND_SECONDS}

func _draw_tongue() -> void:
	var geometry := get_tongue_geometry()
	if not bool(geometry["active"]):
		return
	var points: PackedVector2Array = geometry["points"]
	draw_polyline(points, Color("7f4253"), 3.5, true)
	draw_polyline(points, Color("efa1ad"), 1.6, true)
	if bool(geometry["caught"]):
		var fly: Vector2 = geometry["tip"]
		draw_ellipse(fly + Vector2(-1.8, -1.6), 2.8, 1.2, Color("cadbd4"), true, -1.0, true)
		draw_ellipse(fly + Vector2(1.8, -1.6), 2.8, 1.2, Color("cadbd4"), true, -1.0, true)
		draw_circle(fly, 2.3, Color("263630"), true, -1.0, true)

func is_eating() -> bool:
	return _eat_clock >= 0.0

func _pixel_ellipse(at: Vector2, radius: Vector2, color: Color) -> void:
	if skin_id == "pixel_gecko":
		draw_rect(Rect2((at - ORIGIN - radius).round(), (radius * 2.0).round()), color)
	else:
		draw_ellipse(at - ORIGIN, radius.x, radius.y, color, true, -1.0, true)

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
	for i in range(32):
		var a := TAU * float(i) / 32.0
		polygon.append(at - ORIGIN + (Vector2(cos(a), sin(a)) * radius).rotated(angle))
	draw_colored_polygon(polygon, color)

func _head_point(pose: Dictionary, offset: Vector2) -> Vector2:
	var head: Vector2 = pose["head"]
	return head + offset.rotated(float(pose["head_angle"]))

func _body_patch(pose: Dictionary, from_u: float, to_u: float, side: float, half_width: float, color: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(17):
		var u := lerpf(from_u, to_u, float(i) / 16.0)
		var center := _body_point(pose, u)
		var normal := _body_normal(pose, u)
		var w := _body_width(pose, u)
		left.append(center - ORIGIN + normal * w * (side + half_width))
		right.append(center - ORIGIN + normal * w * (side - half_width))
	for i in range(right.size() - 1, -1, -1):
		left.append(right[i])
	var outline := Geometry2D.convex_hull(left)
	if outline.size() > 3:
		outline.remove_at(outline.size() - 1)
		draw_colored_polygon(outline, color)

func _draw_pose_body(pose: Dictionary, tint: Color, blink: int, include_head: bool = true) -> void:
	var ink := _c("ink") * tint
	var deep := _c("deep") * tint
	var skin := _c("skin") * tint
	_neck(pose, 15.0, ink)
	_body_ribbon(pose, 1.0, Vector2.ZERO, ink)
	_neck(pose, 11.5, deep)
	_body_ribbon(pose, 0.88, Vector2.ZERO, deep)
	_neck(pose, 10.0, skin)
	_body_ribbon(pose, 0.77, Vector2(-0.35, -0.20), skin)
	# Inset patches follow the actual curved spine; none can peel away from
	# the body when it curls. The belly is a quiet continuous surface.
	_body_patch(pose, 0.13, 0.92, 0.20, 0.24, _c("lit") * tint)
	_body_patch(pose, 0.18, 0.90, 0.37, 0.18, _c("pale") * tint)
	for i in range(6):
		var u := 0.22 + float(i) * 0.11
		var center := _body_point(pose, u)
		var normal := _body_normal(pose, u)
		var w := _body_width(pose, u)
		_pixel_ellipse(center - normal * w * 0.40, Vector2(1.75, 1.10), deep)
		_pixel_ellipse(center - normal * w * 0.14 + Vector2(0.0, -1.4), Vector2(0.85, 0.70), _c("lit") * tint)
	_draw_costume_body(pose, tint)
	if include_head:
		_draw_pose_head(pose, tint, blink)

func _blink_amount() -> float:
	var phase := fposmod(_clock, 4.1)
	return smoothstep(3.92, 3.99, phase) * (1.0 - smoothstep(4.03, 4.10, phase))

func _head_contour(pose: Dictionary, factor: float, offset: Vector2) -> PackedVector2Array:
	# Rounded, compact side profile: a short muzzle, cheek and brow. The head
	# stays an independent rigid part instead of distorting an illustrated eye.
	var knots := [Vector2(-4, -16), Vector2(-11, -12), Vector2(-16, -7), Vector2(-18, -1),
		Vector2(-15, 6), Vector2(-6, 11), Vector2(3, 13), Vector2(12, 8), Vector2(15, 0), Vector2(12, -10), Vector2(5, -16)]
	var result := PackedVector2Array()
	for i in range(knots.size()):
		var a: Vector2 = knots[(i - 1 + knots.size()) % knots.size()]
		var b: Vector2 = knots[i]
		var c: Vector2 = knots[(i + 1) % knots.size()]
		var d: Vector2 = knots[(i + 2) % knots.size()]
		for j in range(4):
			var t := float(j) / 4.0
			var point := 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)
			result.append(_head_point(pose, point * factor + offset) - ORIGIN)
	return result

func _draw_pose_head(pose: Dictionary, tint: Color, _blink: int) -> void:
	var ink := _c("ink") * tint
	var skin := _c("skin") * tint
	var deep := _c("deep") * tint
	var angle := float(pose["head_angle"])
	draw_colored_polygon(_head_contour(pose, 1.0, Vector2.ZERO), ink)
	draw_colored_polygon(_head_contour(pose, 0.91, Vector2(-0.2, -0.3)), deep)
	draw_colored_polygon(_head_contour(pose, 0.84, Vector2(-0.7, -0.6)), skin)
	_rotated_ellipse(_head_point(pose, Vector2(-5.0, -8.0)), Vector2(5.5, 6.0), angle, _c("lit") * tint)
	_rotated_ellipse(_head_point(pose, Vector2(-8.7, 3.2)), Vector2(6.4, 3.5), angle - 0.10, _c("lit").lerp(_c("pale"), 0.55) * tint)
	# A short smile and one dark nostril define the muzzle at game size.
	var mouth := [_head_point(pose, Vector2(-14.0, 5.0)), _head_point(pose, Vector2(-7.0, 8.1)), _head_point(pose, Vector2(-1.3, 8.8))]
	for i in range(2):
		_segment(mouth[i], mouth[i + 1], 0.9, 0.8, deep)
	_pixel_ellipse(_head_point(pose, Vector2(-14.0, -1.2)), Vector2(0.85, 0.95), ink)
	for point: Vector2 in [Vector2(-3.8, -12.7), Vector2(-0.3, -14.0), Vector2(3.2, -13.4)]:
		_pixel_ellipse(_head_point(pose, point), Vector2(0.9, 0.65), _c("lit") * tint)
	var eye := _head_point(pose, Vector2(4.0, -4.6))
	var openness := clampf(float(pose["eyes"]) * (1.0 - _blink_amount()), 0.0, 1.0)
	_rotated_ellipse(eye, Vector2(7.0, 8.8), angle, deep)
	_rotated_ellipse(eye + Vector2(-0.25, -0.40).rotated(angle), Vector2(6.0, 7.7), angle, _c("lit") * tint)
	if openness < 0.045:
		var lid_angle := angle + float(pose["curl"]) * PI * 0.5
		var lid := PackedVector2Array()
		for i in range(13):
			var x := -5.0 + float(i) * 10.0 / 12.0
			lid.append(eye - ORIGIN + Vector2(x, 1.0 + x * x * 0.035).rotated(lid_angle))
		draw_polyline(lid, deep, 1.2, true)
	else:
		_rotated_ellipse(eye, Vector2(5.1, 6.8 * openness), angle, Color("fff9e4") * tint)
		var iris := eye + Vector2(-0.9, -0.15).rotated(angle)
		var iris_color := Color("947040") if skin_id == "standard_green" else _c("deep").lerp(_c("accent"), 0.45)
		_rotated_ellipse(iris, Vector2(3.0, 4.8 * openness), angle, iris_color * tint)
		_rotated_ellipse(iris, Vector2(1.55, 4.0 * openness), angle, Color("1c3027") * tint)
		_pixel_ellipse(iris + Vector2(-1.0, -2.3 * openness).rotated(angle), Vector2(1.20, 1.20 * openness), Color.WHITE * tint)
		_pixel_ellipse(iris + Vector2(1.0, 1.8 * openness).rotated(angle), Vector2(0.55, 0.55 * openness), Color("ffe8aa") * tint)
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
		draw_line(foot - ORIGIN, joint - ORIGIN, ink, 2.5, true)
		draw_line(joint - ORIGIN, pad - ORIGIN, ink, 2.2, true)
		draw_line(foot - ORIGIN, joint - ORIGIN, lit, 1.25, true)
		draw_line(joint - ORIGIN, pad - ORIGIN, lit, 1.1, true)
		_pixel_ellipse(pad, Vector2(1.65, 1.50), ink)
		_pixel_ellipse(pad + Vector2(-0.15, -0.25), Vector2(1.05, 0.90), pale)

func _profile_limb_points(front: bool, back: bool, kind: String, amount: float = 1.0) -> PackedVector2Array:
	var phase := _stride_phase + (PI if front == back else 0.0)
	var cycle := fposmod(phase / TAU, 1.0)
	var lift := 0.0
	var stride := 0.0
	if kind in ["run", "jump"]:
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
		var p := _motion_jump()
		var fold := smoothstep(0.0, 0.20, p) * (1.0 - smoothstep(0.75, 1.0, p))
		var tucked := Vector2(43.0 if front else 46.0, y + (-6.0 if front else 10.0))
		elbow = elbow.lerp(tucked, fold)
		foot = foot.lerp(tucked + Vector2(-8.0, -7.0 if front else 6.0), fold)
	return PackedVector2Array([shoulder, elbow, foot])

func _limb_ribbon(points: PackedVector2Array, widths: Vector3, color: Color) -> void:
	var path := PackedVector2Array()
	var profile := PackedFloat32Array()
	var shoulder := points[0]
	var elbow := points[1]
	var foot := points[2]
	var tangent := (foot - shoulder).normalized() * 3.2
	# Two joined curves bend through the real elbow. Their shared tangent and
	# one filled silhouette prevent both stick-like corners and separated joints.
	for piece in range(2):
		for i in range(9):
			if piece == 1 and i == 0:
				continue
			var t := float(i) / 8.0
			if piece == 0:
				path.append(shoulder.bezier_interpolate(shoulder.lerp(elbow, 0.55), elbow - tangent, elbow, t))
				profile.append(lerpf(widths.x, widths.y, t))
			else:
				path.append(elbow.bezier_interpolate(elbow + tangent, elbow.lerp(foot, 0.52), foot, t))
				profile.append(lerpf(widths.y, widths.z, t))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(path.size()):
		var normal := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized().orthogonal()
		left.append(path[i] - ORIGIN + normal * profile[i] * 0.5)
		right.append(path[i] - ORIGIN - normal * profile[i] * 0.5)
	# A triangle strip remains valid even when a tightly folded elbow makes
	# its inside edge cross. Whole-outline triangulation is not valid there.
	var colors := PackedColorArray([color, color, color])
	for i in range(path.size() - 1):
		draw_primitive(PackedVector2Array([left[i], left[i + 1], right[i]]), colors, PackedVector2Array())
		draw_primitive(PackedVector2Array([right[i], left[i + 1], right[i + 1]]), colors, PackedVector2Array())
	_pixel_ellipse(shoulder, Vector2.ONE * widths.x * 0.5, color)
	_pixel_ellipse(foot, Vector2.ONE * widths.z * 0.5, color)

func _draw_limb_chain(points: PackedVector2Array, front: bool, back: bool, tint: Color, hand_direction: Vector2 = Vector2.LEFT, fold: float = 0.0, hand_openness: float = 1.0) -> void:
	var ink := _c("ink") * tint
	var skin := (_c("deep") if back else _c("skin")) * tint
	var lit := (_c("skin") if back else _c("lit")) * tint
	var thigh := lerpf(7.0 if front else 10.0, 6.0 if front else 8.8, fold)
	_limb_ribbon(points, Vector3(thigh + 1.8, 6.1, 4.3), ink)
	_limb_ribbon(points, Vector3(thigh, 4.4, 2.7), skin)
	var sheen := PackedVector2Array([points[0] + Vector2(-0.6, -0.6), points[1] + Vector2(-0.5, -0.8), points[2] + Vector2(-0.4, -0.7)])
	_limb_ribbon(sheen, Vector3(1.4, 1.0, 0.6), lit)
	_draw_tucked_hand(points[2], back, tint, hand_openness, hand_direction)
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

func _draw_profile(kind: String, blink: int, direction: float, angle: float, tint: Color, shift: Vector2 = Vector2.ZERO) -> void:
	var squash := _landing * 0.06
	var scale2 := Vector2(direction * (1.0 + squash), (1.0 - squash + _launch * 0.045) * stretch) * PIXEL_SCALE
	var pose := _profile_pose()
	if kind == "jump":
		# The gecko turns in depth. Its profile narrows while a rounded body
		# remains visible behind it, including at the exact half-turn frame.
		var volume := sin(smoothstep(0.18, 0.82, _motion_jump()) * PI)
		if volume > 0.01:
			draw_set_transform(shift, angle, Vector2(volume * 0.52, scale2.y / PIXEL_SCALE) * PIXEL_SCALE)
			_draw_pose_tail(pose, tint)
			_draw_pose_body(pose, tint, blink, false)
			_draw_pose_head(pose, tint, blink)
	draw_set_transform(shift, angle, scale2)
	_draw_costume_back(pose, tint)
	_draw_pose_tail(pose, tint)
	_draw_limbs(true, kind, tint)
	_draw_pose_body(pose, tint, blink, false)
	_draw_limbs(false, kind, tint)
	_draw_pose_head(pose, tint, blink)
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
	if mode == "electrocuted":
		_draw_electro()
		return
	var visual_mode := _motion_mode()
	var kind := "jump" if visual_mode == "jump" else ("run" if visual_mode == "run" else "idle")
	var blink := 1 if _blink_amount() > 0.95 else 0
	var projection := _jump_projection(_motion_jump(), _motion_side()) if kind == "jump" else Vector2(float(-_motion_side()), 0.0)
	var direction := projection.x
	var angle := projection.y
	var tint := Color.WHITE.lerp(Color("d0ecff"), night_amount * 0.1)
	if mode == "hit":
		tint = tint.lerp(Color("ff998e"), _hurt)
	if mode in ["sleep", "ground_idle"]:
		_draw_wake(_sleep_pose(), 1, direction, tint)
	elif mode in ["wake_climb", "climb_launch"]:
		_draw_wake(_wake_pose(), blink, direction, tint)
	else:
		_draw_profile(kind, blink, direction, angle, tint)
	_draw_tongue()


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
		# Frayed hems use the cape's own basis. Fixed screen offsets turn the
		# folded sleeping cape into a bow-tie polygon when its spine rotates.
		var along := (lower - edge).normalized()
		var inward := along.orthogonal()
		if inward.dot(upper - edge.lerp(lower, 0.5)) < 0.0:
			inward = -inward
		var depth := minf(2.5 * folded * (1.0 - float(pose["curl"])), edge.distance_to(lower) * 0.08)
		if depth > 0.20:
			points.append(edge.lerp(lower, 0.28) + inward * depth)
			points.append(edge.lerp(lower, 0.57) - inward * depth * 0.35)
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
