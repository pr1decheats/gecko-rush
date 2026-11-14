extends SceneTree
## Render an ordinary generated frost encounter near the requested milestones.
## The fixture does not move, inject or resize generated obstacles.
var game: Node
var output: String
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _prepare(height: float, seconds: float, seed_value: int = 41) -> void:
	game.state = game.State.RUNNING
	game.world_id = "ice"
	game.height_px = height
	game.max_height_px = height
	game.camera_height = height - 130.0
	game.run_time = seconds
	game.jump_elapsed = -1.0
	game._reset_center_event()
	game.center_first_given = true
	game.next_center_metres = 1.0e12
	game.course.setup(seed_value, "ice")
	game.course.ensure_ahead(height, seconds)
	game.course.visible = true
	game.side = -1
	if game.course.collision_at(Vector2(game.LEFT_X, -height), seconds):
		game.side = 1
	game.gecko.side = game.side
	game.gecko.mode = "run"
	game.gecko.position = game.player_position()
	game.gecko.run_speed_factor = game.current_speed() / RushTuning.START_SPEED
	game.environment.set_world("ice")
	game.environment.menu_blend = 0.0
	game.ui.show_hud()
	game.ui.set_hint_visible(false)
	game._process(0.0)
	game.course.queue_redraw()

func _run() -> void:
	await process_frame
	var progress := root.get_node("Progress")
	progress.save_file = "user://v26_visibility_capture.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.settings_changed()
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../v26-visibility-captures")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(540, 960)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	for fixture in [[575.0, 10.0, "frost_near_575_day"], [4000.0, 10.0, "frost_near_4000_day"], [4000.0, 50.0, "frost_near_4000_night"]]:
		var target: float = fixture[0] * RushTuning.PIXELS_PER_METRE
		var height := -1.0
		var distance := INF
		var chosen_seed := 41
		for seed_value in range(32):
			game.course.setup(seed_value, "ice")
			game.course.ensure_ahead(target, float(fixture[1]))
			for action: Dictionary in game.course.witness:
				if int(action.get("layout", -1)) != 8 or bool(action.get("breathing", false)):
					continue
				for item: Dictionary in game.course.hazards:
					if str(item["kind"]) != "frost" or float(item["h"]) < float(action["cell_start"]) or float(item["h"]) > float(action["cell_end"]):
						continue
					var candidate: float = float(item["h"]) - (root.get_visible_rect().size.y - 650.0 - 900.0)
					if absf(candidate - target) < distance:
						distance = absf(candidate - target)
						height = candidate
						chosen_seed = seed_value
		if height <= 0.0:
			push_error("No ordinary frost encounter near requested milestone")
			failures += 1
			continue
		_prepare(height, float(fixture[1]), chosen_seed)
		await create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		var visible_frost := 0
		var dims: Array = []
		for item: Dictionary in game.course.hazards:
			if str(item["kind"]) == "frost" and (game.course.get_global_transform() * item["_bounds"]).intersects(root.get_visible_rect()):
				visible_frost += 1
				dims.append([float(item["r"]), float(item["half_length"])])
		var captured := root.get_texture().get_image()
		if visible_frost == 0 or captured.is_empty() or captured.save_png(output.path_join(str(fixture[2]) + ".png")) != OK:
			push_error("Generated frost fixture did not render")
			failures += 1
		print("FROST_CAPTURE %s metres=%.3f seed=%d speed=%.2f visible_frost=%d dimensions=%s" % [fixture[2], height / RushTuning.PIXELS_PER_METRE, chosen_seed, game.current_speed(), visible_frost, dims])
	game.queue_free()
	await process_frame
	await process_frame
	print("V26 visibility captures: 3 frames, %d failures" % failures)
	quit(1 if failures else 0)
