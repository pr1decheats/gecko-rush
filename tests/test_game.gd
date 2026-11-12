extends SceneTree
## End-to-end tests drive the real scene and the same 120 Hz simulation as play.

var checks: int = 0
var failures: int = 0
var game: Node
var progress: Node
var launched: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	progress = root.get_node("Progress")
	progress.save_file = "user://integration_test.json"
	progress.data = progress._defaults()
	progress.data.settings = {"music": false, "sfx": false}
	progress.settings_changed()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	check(game.state == game.State.MENU, "main menu loads")
	check(game.gecko.mode == "sleep" and is_equal_approx(game.gecko.position.y + GeckoVisual.GROUND_FEET_Y, 73.0), "curled-up gecko sleeps on the starting floor")
	check(game.course.visible == false, "no run obstacles obscure menu")
	game._on_action("shop")
	check(game.state == game.State.PANEL, "shop opens")
	game._on_action("profile")
	game._on_action("daily")
	game._on_action("settings")
	game._on_action("setting", {"key": "music", "value": false})
	check(not bool(progress.data.settings.music), "sound preference persists")
	game._on_action("menu")
	game._on_action("play")
	check(game.state == game.State.TRANSITION, "play begins continuous launch")
	game._process(0.95)
	check(game.gecko.position.x < 365 and game.gecko.position.x >= 296 and game.gecko.mode == "wake_climb", "same gecko wakes and crawls toward its wall during launch")
	check(game.state == game.State.TRANSITION, "launch has no hard scene switch")
	game._process(0.95)
	check(game.state == game.State.RUNNING, "launch becomes a running game")
	check(is_equal_approx(game.height_px, 120.0), "launch and run share the same world position")
	check(game.jump(), "a grounded press launches immediately")
	check(not game.jump(), "second press during flight is rejected")
	for index in 32:
		game._simulate_step(1.0 / 120.0)
	check(game.side == 1 and game.jump_elapsed < 0, "flight lands on opposite wall")
	check(game.run_jumps == 1, "successful landing counts once")
	check(game.height_px > 120.0, "auto climb continues throughout flight")
	check(game.jump(), "next press jumps back")
	for index in 32:
		game._simulate_step(1.0 / 120.0)
	check(game.side == -1 and game.run_jumps == 2, "backward crossing works")

	# Save during a flight, then restore the real course, phases and collection state.
	game.jump()
	for index in 20:
		game._simulate_step(1.0 / 120.0)
	game._pause_run()
	var saved: Dictionary = progress.load_resume()
	var frozen_height: float = game.height_px
	var frozen_time: float = game.run_time
	game._physics_process(0.2)
	game._process(0.2)
	check(game.height_px == frozen_height and game.run_time == frozen_time, "pause freezes run physics and clock")
	check(saved.has("course") and float(saved.jump_elapsed) > 0, "checkpoint includes in-flight state and course")
	progress.load_game()
	game._show_menu()
	game._restore_run()
	check(game.state == game.State.PAUSED, "restart restores to a safe pause")
	check(absf(game.height_px - frozen_height) < 0.0000001, "restored position retains precision")
	check(absf(game.run_time - frozen_time) < 0.0000001, "restored moving-hazard clock retains precision")
	check(game.course.snapshot().hazards.size() == saved.course.hazards.size(), "course obstacles survive checkpoint")
	game._continue_run()
	for index in 12:
		game._simulate_step(1.0 / 120.0)
	check(game.side == 1 and game.run_jumps == 3, "restored flight lands exactly once")
	# Return to the certified initial wall while the opening remains obstacle-free.
	game.jump()
	for index in 32:
		game._simulate_step(1.0 / 120.0)
	check(game.side == -1, "initial corridor permits practice jumps")

	# Follow only the generator's public route certificate, without invulnerability.
	var max_steps: int = 60000
	var steps: int = 0
	while game.state == game.State.RUNNING and game.max_height_px < 3000.0 * RushTuning.PIXELS_PER_METRE and steps < max_steps:
		_follow_route()
		game._simulate_step(1.0 / 120.0)
		steps += 1
	check(game.state == game.State.RUNNING, "certified route survives a real 3000 m run")
	check(game.max_height_px >= 3000.0 * RushTuning.PIXELS_PER_METRE, "run actually reaches 3000 m")
	check(game.run_coins >= 3 and game.run_coins < 60, "real run collects route coins")
	check(game.run_passed > 10 and game.run_jumps > 10, "real hazards and successful jumps are counted")
	check(game.course.hazards.size() < 35, "behind-camera obstacles are removed")
	var expected_height: float = game.max_height_px / RushTuning.PIXELS_PER_METRE
	# Settle a respite, if the 3000m checkpoint coincided with its warning.
	game.center_event = "off"
	game.next_center_metres = 1.0e9
	game.course.safe_sections.clear()
	game.course.setup(441, game.world_id)
	game.course.ensure_ahead(game.max_height_px + 3500.0, game.run_time)
	var expected_jumps: int = game.run_jumps
	# Deliberately enter a real spike triangle to verify the collision/death pipeline.
	var spike: Dictionary = {}
	for hazard: Dictionary in game.course.hazards:
		if hazard.kind == "spikes" and float(hazard.h) > game.max_height_px:
			spike = hazard
			break
	check(not spike.is_empty(), "course provides a visible wall hazard")
	if not spike.is_empty():
		game.side = -1 if int(spike.side) == 0 else 1
		game.jump_elapsed = -1.0
		game.height_px = float(spike.h)
		game._simulate_step(1.0 / 120.0)
	check(game.state == game.State.DYING, "hazard contact ends run")
	var balance_after: int = int(progress.data.coins)
	var runs_after: int = int(progress.data.runs)
	check(balance_after > 0 and runs_after == 1, "collision credits currency once")
	check(float(progress.data.best_height) >= expected_height, "best height updates")
	check(int(progress.data.jumps) >= expected_jumps and int(progress.data.xp) > 0, "XP and lifetime jump count update")
	check(progress.load_resume().is_empty(), "completed run checkpoint clears")
	game._die()
	check(int(progress.data.coins) == balance_after and int(progress.data.runs) == runs_after, "duplicate death cannot double rewards")
	game._process(0.7)
	check(game.state == game.State.RESULTS, "death animation reveals results")
	progress.load_game()
	check(int(progress.data.coins) == balance_after and float(progress.data.best_height) >= expected_height, "currency and record persist through reload")
	game._on_action("retry")
	check(game.state == game.State.TRANSITION and game.run_coins == 0, "retry resets temporary run state")
	game._process(1.4)
	check(game.state == game.State.RUNNING and game.run_time == 0.0, "retry starts without a long splash")
	check(int(progress.data.coins) == balance_after, "retry preserves earned currency")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.state == game.State.PAUSED and not progress.load_resume().is_empty(), "app backgrounding pauses and checkpoints")
	game._on_action("menu")
	check(game.state == game.State.MENU, "pause can return to menu")
	check(int(progress.data.runs) == 2, "abandoned run is settled once")
	check(progress.load_resume().is_empty(), "settled run cannot resume for duplicate rewards")

	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_file + suffix))
	print("GAME: %d checks, %d failures; certified 3000 m in %d simulation steps" % [checks, failures, steps])
	quit(1 if failures > 0 else 0)

func _follow_route() -> void:
	if game.jump_elapsed >= 0.0 or game.center_event in ["enter", "ride", "exit"]:
		return
	for item: Dictionary in game.course.get_witness():
		var key: String = str(item.cell_start)
		if launched.has(key):
			continue
		if game.height_px >= float(item.height_px) and game.height_px < float(item.cell_end):
			var wanted_side: int = -1 if int(item.to_side) == 0 else 1
			if game.side != wanted_side:
				if game.jump():
					launched[key] = true
			else:
				launched[key] = true
