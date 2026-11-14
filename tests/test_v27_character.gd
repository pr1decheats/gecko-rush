extends SceneTree
## Behaviour and native pixel checks for the compact, genuinely articulated rig.
## Native captures: DISPLAY=:99 godot --path . --script tests/test_v27_character.gd -- /absolute/output
const GECKO = preload("res://scripts/gecko.gd")
var checks: int = 0
var failures: int = 0
var specimens: Array[Node2D] = []

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
	check(GECKO.RENDERER_REVISION == 27, "Actual character uses the articulated renderer revision")
	check(is_equal_approx(GECKO.MAX_TONGUE_REACH, 105.0), "Tongue has a compact explicit reach in logical pixels")
	var progress: Node = root.get_node("Progress")
	check(progress.SKINS.size() == 21, "Default and all twenty purchased outfits remain available")
	for skin: Dictionary in progress.SKINS:
		var id: String = skin["id"]
		var gecko: Node2D = GECKO.new()
		gecko.set_skin(id)
		root.add_child(gecko)
		gecko.set_process(false)
		gecko.mode = "run"
		check(gecko.skin_id == id, "Every existing outfit configures the live rig: " + id)
		var first_mouth: Vector2 = gecko.get_mouth_position()
		check(first_mouth.is_finite() and first_mouth.length() < 125.0, "Mouth anchor belongs to the compact head: " + id)
		gecko._stride_phase = 0.0
		var first_foot: Vector2 = gecko._profile_limb_points(true, false, "run")[2]
		gecko._stride_phase = PI * 0.5
		var other_foot: Vector2 = gecko._profile_limb_points(true, false, "run")[2]
		check(first_foot.distance_to(other_foot) > 4.0, "Feet visibly advance through a planted step: " + id)
		gecko._tail_phase = 0.0
		var first_tail: Vector2 = gecko._tail_point(gecko._profile_pose(), 0.9)
		gecko._tail_phase = PI * 0.5
		check(first_tail.distance_to(gecko._tail_point(gecko._profile_pose(), 0.9)) > 3.0, "Tail is articulated separately from the torso: " + id)
		gecko.side = -1
		var left: Vector2 = gecko.get_mouth_position()
		gecko.side = 1
		var right: Vector2 = gecko.get_mouth_position()
		check(absf(left.x + right.x) < 0.01 and absf(left.y - right.y) < 0.01, "Mouth mirrors exactly with the head: " + id)
		check(left.x < 0.0 and right.x > 0.0, "Mouth points toward the occupied wall: " + id)
		gecko.run_speed_factor = 100.0
		gecko._process(0.4)
		check(gecko._visual_speed_factor <= 3.01, "High game speed does not make the rig twitch: " + id)
		var stride: float = gecko._stride_phase
		var tail: float = gecko._tail_phase
		await process_frame
		check(is_equal_approx(gecko._stride_phase, stride) and is_equal_approx(gecko._tail_phase, tail), "Pausing freezes both articulation clocks: " + id)
		gecko.reset_animation()
		check(gecko.skin_id == id and gecko._stride_phase == 0.0 and gecko._tail_phase == 0.0 and gecko._visual_speed_factor == 1.0, "Retry resets speed and phase without losing the outfit: " + id)
		await _tongue(gecko, id)
		for boundary: float in [0.20, 0.42, 0.58, 0.70]:
			gecko.set_launch_pose(boundary - 0.001)
			var before: Vector2 = gecko.get_mouth_position()
			gecko.set_launch_pose(boundary + 0.001)
			var after: Vector2 = gecko.get_mouth_position()
			check(before.is_finite() and after.is_finite() and before.distance_to(after) < 3.0, "One continuous waking head at %.2f: %s" % [boundary, id])
		gecko.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _native()
	print("V27 CHARACTER: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _tongue(gecko: Node2D, id: String) -> void:
	for wall: int in [-1, 1]:
		gecko.mode = "run"
		gecko.side = wall
		gecko.eat_to(Vector2(float(wall) * 900.0, -9000.0))
		check(gecko.is_eating(), "A wall catch starts once: " + id)
		var caught: bool = false
		for frame in range(12):
			gecko.position.y -= 18000.0 * 0.02
			gecko._process(0.02)
			var geometry: Dictionary = gecko.get_tongue_geometry()
			if not bool(geometry.get("active", false)):
				continue
			var mouth: Vector2 = geometry["mouth"]
			var tip: Vector2 = geometry["tip"]
			caught = caught or bool(geometry.get("caught", false))
			check(mouth.is_finite() and tip.is_finite(), "Finite tongue geometry while climbing at 18k px/s: " + id)
			check(mouth.distance_to(gecko.get_mouth_position()) < 0.01, "Tongue remains attached to its actual moving mouth: " + id)
			check(mouth.distance_to(tip) <= GECKO.MAX_TONGUE_REACH + 0.1, "Tongue never stretches behind the climbing character: " + id)
			var points: PackedVector2Array = geometry["points"]
			check(points.size() >= 2 and points[0].distance_to(mouth) < 0.01 and points[points.size() - 1].distance_to(tip) < 0.01, "Drawn tongue path uses the tested mouth/tip: " + id)
		check(caught, "Extension transitions into caught-fly retraction: " + id)
		gecko._process(0.3)
		check(not gecko.is_eating() and not bool(gecko.get_tongue_geometry().get("active", false)), "Catch finishes and leaves no tongue: " + id)
		gecko.eat_to(Vector2(-30.0 * wall, -95.0))
		gecko.launch()
		check(not bool(gecko.get_tongue_geometry().get("active", false)), "Jump cancels a catch: " + id)
		gecko.mode = "run"
		gecko.eat_to(Vector2(-30.0 * wall, -95.0))
		gecko.hurt()
		check(not bool(gecko.get_tongue_geometry().get("active", false)), "Collision cancels a catch: " + id)
		gecko.mode = "run"
		gecko.eat_to(Vector2(-30.0 * wall, -95.0))
		gecko.reset_animation()
		check(not gecko.is_eating() and not bool(gecko.get_tongue_geometry().get("active", false)), "Retry clears a catch: " + id)
	gecko.position = Vector2.ZERO

func _native() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var directory: String = arguments[0] if not arguments.is_empty() else ProjectSettings.globalize_path("res://../v27-character-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(320, 320)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var gecko: Node2D = GECKO.new()
	gecko.position = Vector2(160, 160)
	viewport.add_child(gecko)
	gecko.set_process(false)
	gecko.mode = "run"
	gecko._clock = 1.0
	var previous: Image
	for index in range(4):
		gecko._stride_phase = TAU * float(index) / 4.0
		gecko._tail_phase = TAU * float(index) / 4.0
		gecko.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var rect: Rect2i = image.get_used_rect()
		check(rect.size.x >= 60 and rect.size.x <= 110 and rect.size.y >= 150 and rect.size.y <= 190, "Native default stays near the old 76×169 footprint: " + str(rect))
		check(image.save_png(directory.path_join("run-%d.png" % index)) == OK, "Native stride frame saved")
		if previous != null:
			var changed: int = 0
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					if previous.get_pixel(x, y) != image.get_pixel(x, y):
						changed += 1
			check(changed >= 300, "Rendered limbs and tail visibly move between stride frames (%d changed pixels)" % changed)
		check(_major_components(image) == 1, "Run body, head, limbs and tail remain one attached silhouette")
		previous = image
	gecko._clock = 4.0
	gecko.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var blink: Image = viewport.get_texture().get_image()
	check(blink.get_data() != previous.get_data(), "Native eye actually blinks instead of only advancing a timer")
	blink.save_png(directory.path_join("blink.png"))
	gecko.mode = "sleep"
	gecko.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var sleep_image: Image = viewport.get_texture().get_image()
	var rest: Rect2i = sleep_image.get_used_rect()
	check(rest.size.x >= 80 and rest.size.x <= 130 and rest.size.y >= 45 and rest.size.y <= 95, "Sleeping body stays compact near the old 101×66 footprint: " + str(rest))
	check(_major_components(sleep_image) == 1, "Sleeping head, tucked feet and tail stay attached to the same curled body")
	sleep_image.save_png(directory.path_join("sleep.png"))
	gecko.mode = "run"
	gecko._clock = 1.0
	gecko.eat_to(Vector2(-70, -125))
	gecko._process(0.06)
	gecko.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(directory.path_join("tongue.png"))
	# Folded jagged hems previously self-intersected only at intermediate wake
	# fractions. Draw the actual cape at every fraction, not merely endpoints.
	for outfit: String in ["shadow_jumper", "ghost_dragon"]:
		gecko.set_skin(outfit)
		for sample in range(101):
			gecko.set_launch_pose(float(sample) / 100.0)
			gecko.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			check(gecko.get_mouth_position().is_finite(), "Dense native wake head stays finite: %s %.2f" % [outfit, float(sample) / 100.0])
		viewport.get_texture().get_image().save_png(directory.path_join("wake-" + outfit + ".png"))
	print("V27 DENSE CAPES: 202 native wake samples rendered across both jagged outfits")
	viewport.queue_free()
	await process_frame
	await process_frame

func _major_components(image: Image) -> int:
	# Ignore tiny antialias specks, but reject a detached hand/head/tail section.
	var remaining: Dictionary = {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.10:
				remaining[Vector2i(x, y)] = true
	var major: int = 0
	while not remaining.is_empty():
		var queue: Array[Vector2i] = [remaining.keys()[0]]
		remaining.erase(queue[0])
		var cursor: int = 0
		while cursor < queue.size():
			var current: Vector2i = queue[cursor]
			cursor += 1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var neighbour: Vector2i = current + Vector2i(dx, dy)
					if remaining.has(neighbour):
						remaining.erase(neighbour)
						queue.append(neighbour)
		if queue.size() >= 16:
			major += 1
	return major
