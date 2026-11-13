extends SceneTree
## Actual late-run rendering; fixtures do not simulate a player's record.
var game: Node
var directory: String
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _prepare_fixture(metres: float, seconds: float, seed_value: int) -> void:
	game.state = game.State.RUNNING
	game.world_id = "ice"
	game.height_px = metres * RushTuning.PIXELS_PER_METRE
	game.max_height_px = game.height_px
	# In steady climbing the camera's speed compensation cancels follow lag,
	# leaving the gecko at the same screen height as an ordinary running frame.
	game.camera_height = game.height_px - 130.0
	game.run_time = seconds
	game.jump_elapsed = -1.0
	game._reset_center_event()
	game.course.setup(seed_value, "ice")
	game.course.ensure_ahead(game.height_px, game.run_time)
	game.course.visible = true
	game.side = -1
	var next_gate_height := INF
	for hazard: Dictionary in game.course.hazards:
		if bool(hazard.get("gate", false)) and float(hazard["h"]) > game.height_px and float(hazard["h"]) < next_gate_height:
			next_gate_height = float(hazard["h"])
			game.side = 1 if int(hazard["side"]) == 0 else -1
	if game.course.collision_at(Vector2(game.LEFT_X, -game.height_px), game.run_time):
		game.side = 1
	game.gecko.side = game.side
	game.gecko.mode = "run"
	game.gecko.position = game.player_position()
	game.gecko.run_speed_factor = game.current_speed() / RushTuning.START_SPEED
	game.environment.set_world("ice")
	game.environment.menu_blend = 0.0
	game._process(0.0)
	game.course.queue_redraw()

func _visible_hazards(wall_only: bool, playfield_only: bool = false) -> int:
	var count := 0
	var view: Rect2 = root.get_visible_rect()
	if playfield_only:
		# Leave the HUD and the runner unobscured by the representative gate.
		view = Rect2(0.0, 280.0, view.size.x, 850.0)
	for hazard: Dictionary in game.course.hazards:
		if wall_only and str(hazard.get("shape", "")) != "spikes":
			continue
		var screen_bounds: Rect2 = game.course.get_global_transform() * hazard["_bounds"]
		if screen_bounds.intersects(view):
			count += 1
	return count

func _representative_position(metres: float, seconds: float) -> float:
	# At late-run speed a full gate interval can be taller than the viewport.
	# Lookahead counts alone therefore cannot establish visible wall pressure.
	# Keep the original deterministic course and select its nearest real frame
	# with a gate in the forward view. The HUD reports that actual height.
	# Never inject, move, enlarge or otherwise modify generated hazards.
	_prepare_fixture(metres, seconds, 41)
	var nearest_height := -1.0
	var nearest_distance := INF
	var runner_screen_y := root.get_visible_rect().size.y - 650.0
	for hazard: Dictionary in game.course.hazards:
		if not bool(hazard.get("gate", false)):
			continue
		var candidate_height := float(hazard["h"]) - (runner_screen_y - 900.0)
		var distance := absf(candidate_height - metres * RushTuning.PIXELS_PER_METRE)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_height = candidate_height
	return nearest_height / RushTuning.PIXELS_PER_METRE

func _run() -> void:
	await process_frame
	var p := root.get_node("Progress")
	p.save_file = "user://v24_pressure_visual.json"
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.settings_changed()
	var args := OS.get_cmdline_user_args()
	directory = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../v24-qa")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(540, 960)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var four_km_position := _representative_position(4000.0, 10.0)
	var twelve_km_position := _representative_position(12000.0, 10.0)
	check(four_km_position > 0.0 and twelve_km_position > 0.0, "ordinary generated course provides representative positions near the milestones")
	if failures > 0:
		quit(1)
		return
	for fixture in [[four_km_position, 10.0, "hard_4000_day"], [four_km_position, 50.0, "hard_4000_night"], [twelve_km_position, 10.0, "hard_12000_day"]]:
		_prepare_fixture(float(fixture[0]), float(fixture[1]), 41)
		game.ui.show_hud()
		game.ui.set_hint_visible(false)
		game._process(0.0)
		check(game.course.animation_time == game.run_time, "render and collision share the fixture clock")
		check(_visible_hazards(true, true) > 0, "forward viewport contains an actual generated wall gate")
		check(not game.course.collision_at(game.player_position(), game.run_time), "representative runner occupies a safe wall")
		var before := JSON.stringify(game.course.snapshot(), "", false, true)
		await create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		check(JSON.stringify(game.course.snapshot(), "", false, true) == before, "capture leaves generated geometry and collision state unchanged")
		var captured := root.get_texture().get_image()
		if captured.is_empty() or captured.save_png(directory.path_join(String(fixture[2]) + ".png")) != OK:
			push_error("Could not capture late-run fixture")
			quit(1)
			return
		print("CAPTURED %s metres=%.3f seed=41 speed=%.2f visible_hazards=%d visible_wall_gates=%d streamed_hazards=%d" % [fixture[2], fixture[0], game.current_speed(), _visible_hazards(false), _visible_hazards(true, true), game.course.hazards.size()])
	game.queue_free()
	await process_frame
	await process_frame
	print("V24 pressure visual: 3 native captures, %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
