extends SceneTree
## Android 2.2: wake-up, collision-specific death, tempo, HUD and thin wall.
var checks := 0
var failures := 0
var game: Node
var progress: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	progress = root.get_node("Progress")
	progress.save_file = "user://v22_game_regression.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.settings_changed()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	check(game.gecko.mode == "sleep", "menu starts with a curled sleeping gecko")
	check(RushTuning.speed_at(0) > 700 and RushTuning.speed_at(0) < 1000, "initial tempo is a moderate increase")
	check(RushTuning.speed_at(250 * 64) == 1013.25 and RushTuning.speed_at(1000 * 64) == 1662.0, "Easy accelerates continuously with its distance curve")
	check(RushTuning.NIGHT_SPEED < RushTuning.START_SPEED, "night is slower than even the opening daytime pace")
	for second: float in [40.0, 45.0, 59.99, 100.0, 119.99]:
		check(is_equal_approx(RushTuning.run_speed_at(100000.0, second), float(RushTuning.profile_for("jungle")["night_speed"])), "Easy night restores its fixed selected slow pace")
	check(RushCenterWall.WALL_WIDTH == 56 and game.CENTER_WALL_RIGHT - game.CENTER_WALL_LEFT == 56, "render and physical centre wall use the same thinner width")
	game._start_run(false)
	game._process(game.transition_duration * 0.1)
	var base := Vector2(0.0, root.get_visible_rect().size.y - 520.0)
	var horizontal_offset := maxf(0.0, (root.get_visible_rect().size.x - 1080.0) * 0.5)
	check(game.state == game.State.TRANSITION and game.gecko.mode == "wake_climb", "play begins a wake-up before the climb")
	check(game.environment.position.distance_to(Vector2(horizontal_offset, 0)) > 0.1, "earthquake moves the scenery")
	check((game.world.position - base - Vector2(horizontal_offset, 0)).distance_to(game.environment.position - Vector2(horizontal_offset, 0)) < 0.01, "earthquake keeps the gecko and floor together")
	game._process(game.transition_duration * 0.5)
	check(game.gecko.launch_progress > 0.5 and game.gecko.launch_progress < 0.7, "same-body uncoiling reaches the turn pose")
	check(game.environment.position == Vector2(horizontal_offset, 0), "earthquake ends before wall climbing")
	game._process(game.transition_duration * 0.5)
	check(game.state == game.State.RUNNING and game.gecko.mode == "run", "wake-up ends in the normal running profile")
	game.ui.show_hud()
	var capsule: PanelContainer = game.ui._content.get_node("HeightCapsule")
	var panel: StyleBoxFlat = capsule.get_theme_stylebox("panel")
	check(is_equal_approx(panel.bg_color.a, 0.56), "height HUD is translucent")
	check(panel.corner_radius_top_left == 14 and panel.corner_radius_bottom_right == 14, "height HUD has gently rounded corners")
	check(game.course.FIRST_CELL == 1050, "first hazards start sooner")
	var first: Dictionary = game.course.get_witness()[0]
	check(float(first.cell_end) > float(first.cell_start) and game.course.gate_interval_at(float(first.cell_start)) > game.course.gate_interval_at(4000.0 * 64.0), "introductory gates allow more reaction time than the later course")
	var electrode: Dictionary = game.course._central_hazard("electric", 0.0)
	electrode.x = game.LEFT_X
	electrode.h = 2000.0
	electrode.amplitude = 0.0
	game.course._cache_geometry(electrode)
	game.course.hazards = [electrode]
	game.height_px = 2000.0
	game.max_height_px = 2000.0
	game.run_time = 0.0
	game.side = -1
	game.jump_elapsed = -1.0
	game.gecko.side = -1
	var before_runs: int = progress.data.runs
	game._simulate_step(1.0 / 120.0)
	check(game.state == game.State.DYING and game.death_kind == "electric", "real electrical contact selects its own death effect")
	check(game.gecko.mode == "electrocuted" and game.gecko._ash_positions.size() == 44, "electrical death initializes bounded ash")
	var death_position: Vector2 = game.gecko.position
	game._process(0.2)
	check(game.gecko.position == death_position and game.gecko.rotation == 0.0, "electrical death does not use the ordinary falling rotation")
	var initial_ash: PackedVector2Array = game.gecko._ash_positions.duplicate()
	game.gecko._process(0.6)
	check(game.gecko._ash_positions != initial_ash, "ash moves and falls after the skeleton flash")
	game._process(0.5)
	check(game.state == game.State.DYING, "results do not cut off the ash effect after the old death timeout")
	game._die("electric")
	check(progress.data.runs == before_runs + 1, "electrical death pays a run only once")
	game._process(0.71)
	check(game.state == game.State.RESULTS, "results appear after the full electrical animation")
	game._start_run(true)
	check(game.gecko._ash_positions.is_empty() and game.gecko._electro_clock < 0 and game.gecko.mode == "sleep", "retry clears ash and returns to sleep")
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_file + suffix))
	print("V22: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
