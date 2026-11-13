extends SceneTree
## Main-scene regression tests for endless pace, swept contacts, and daylight-only
## central respites. Fixtures use the actual course geometry and 120Hz simulation.
const STEP := 1.0 / 120.0
const WORLDS := ["jungle", "canyon", "ice", "crystal", "volcano", "sky"]
var checks := 0
var failures := 0
var p: Node
var game: Node
var accepted_seed := -1

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _prepare(id: String, metres: float, seconds: float) -> void:
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.data.unlocked_worlds = WORLDS.duplicate()
	p.data.selected_world = id
	game._start_run(true)
	game._process(game.transition_duration)
	game.height_px = metres * RushTuning.PIXELS_PER_METRE
	game.max_height_px = game.height_px
	game.run_time = seconds
	game.course.ensure_ahead(game.max_height_px, seconds)
	# Replace only this test's generated objects with explicit cached fixtures.
	# No safe section or invulnerability is used in the swept-contact tests.
	game.course.hazards.clear()
	game.course.coins.clear()
	game.course.flies.clear()
	game.course.safe_sections.clear()
	game.next_center_metres = 1.0e12
	game.center_first_given = true
	game.center_pending_metres = 0.0
	game.gecko.position = game.player_position()

func _wall(height: float, half_height: float = 4.0) -> Dictionary:
	game.course.route_side = 1
	var hazard: Dictionary = game.course._wall_spikes(height, 0.0, half_height)
	# A thin legacy/custom obstacle must remain lethal even where the selected
	# world's procedural gate factory normally chooses a taller silhouette.
	hazard.half_h = half_height
	game.course._cache_geometry(hazard)
	return hazard

func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", false, true)), "", false, true)

func _run() -> void:
	p = root.get_node("Progress")
	p.save_file = "user://v24_main_regression.json"
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.settings_changed()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	_test_daylight_chance()
	_test_rejected_windows()
	_test_night_milestone_contact()
	_test_cooldown_and_long_transfer()
	_test_night_restore()
	_test_illegal_night_center_restore()
	_test_fast_wall_contacts()
	_test_fast_collection()
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.save_file + suffix))
	print("V24 MAIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_daylight_chance() -> void:
	_prepare("ice", 1500.0, 10.0)
	var accepted := 0
	var missed := 0
	for seed: int in range(200):
		game._reset_center_event()
		game.center_first_given = true
		game.next_center_metres = 3000.0
		game.center_pending_metres = 0.0
		game.height_px = 3000.0 * RushTuning.PIXELS_PER_METRE
		game.max_height_px = game.height_px
		game.course.safe_sections.clear()
		game.run_seed = seed
		game._begin_center_event()
		check(game.center_event == "preview", "full daylight permits a visible accepted or missed preview")
		check(game.center_next_allowed_time == 70.0, "every daylight attempt starts the full-cycle cooldown")
		if game.center_will_appear:
			accepted += 1
			accepted_seed = seed
			check(game.course.safe_sections.size() == 1, "accepted daylight roll protects the transfer")
		else:
			missed += 1
			check(game.course.safe_sections.is_empty(), "missed daylight roll preserves the ordinary course")
	check(accepted > 65 and accepted < 135 and missed > 65 and missed < 135 and accepted_seed >= 0, "later daylight milestones retain approximately fifty-percent acceptance")
	game.run_time = 28.19
	game.center_next_allowed_time = 0.0
	check(game._center_event_allowed(), "last complete daylight transfer still fits before dusk")
	game.run_time = 28.21
	check(not game._center_event_allowed(), "a transfer crossing the dusk margin is refused")

func _test_rejected_windows() -> void:
	for seconds: float in [28.3, 35.0, 36.0, 39.9, 40.0, 50.0, 59.9, 60.0, 62.0, 100.0]:
		_prepare("ice", 4000.0, seconds)
		game.run_seed = accepted_seed
		game.next_center_metres = 1500.0
		game.center_first_given = false
		var fixture := _wall(game.height_px + 1500.0, 40.0)
		game.course.hazards = [fixture]
		game._tick_center_event(STEP)
		check(game.center_event == "off" and not game.center_will_appear, "night/dawn/late-day milestone creates no preview at %s seconds" % seconds)
		check(game.course.safe_sections.is_empty() and game.course.hazards.size() == 1 and game.course.hazards[0] == fixture, "rejected window does not clear existing hazards at %s seconds" % seconds)
		check(game.next_center_metres > game.max_height_px / RushTuning.PIXELS_PER_METRE and game.center_pending_metres == 1500.0 and not game.center_first_given and game.center_next_allowed_time == 0.0, "rejected window preserves the guaranteed first milestone without starting cooldown")

func _test_night_milestone_contact() -> void:
	for seconds: float in [50.0, 100.0]:
		for metres: float in [1500.0, 4000.0, 12000.0]:
			_prepare("ice", metres, seconds)
			game.run_seed = accepted_seed
			game.next_center_metres = 1500.0
			game.center_first_given = false
			var start: Vector2 = game.player_position()
			var advance: float = game.current_speed() * STEP
			var fixture := _wall(game.height_px + advance * 0.5, 4.0)
			game.course.hazards = [fixture]
			game._simulate_step(STEP)
			check(game.center_event == "off" and game.course.safe_sections.is_empty(), "actual night physics grants no central respite at %sm / %ss" % [metres, seconds])
			check(game.state == game.State.DYING and game.death_kind == "ice_teeth", "night milestone leaves its crossed wall hazard lethal")
			check(game.next_center_metres > game.max_height_px / RushTuning.PIXELS_PER_METRE and game.center_pending_metres == 1500.0 and not game.center_first_given and game.center_next_allowed_time == 0.0, "night contact leaves the guaranteed first event pending rather than consuming it")
			check(game.player_position().y < start.y and p.data.runs == 1, "real night contact advances and settles one run")

func _test_cooldown_and_long_transfer() -> void:
	_prepare("sky", 50000.0, 10.0)
	game.run_seed = accepted_seed
	# Reuse the known accepted event number while starting at a much later height.
	game.next_center_metres = 1500.0
	game.center_first_given = false
	game._begin_center_event()
	check(game.center_event == "preview" and game.center_will_appear, "valid daylight still starts a high-distance central transfer")
	check(game.next_center_metres == 51000.0 and game.center_next_allowed_time == 70.0, "high-distance attempt consumes all earlier milestones and starts cooldown")
	var protected_end: float = game.course.safe_sections[0].end
	for step: int in range(910):
		game._simulate_step(STEP)
	check(game.state == game.State.RUNNING and game.center_event == "off", "real fast central transfer completes safely beyond 50km")
	check(game.max_height_px / RushTuning.PIXELS_PER_METRE > 65000.0, "fast central ride actually crosses several further 1500m milestones")
	check(protected_end > game.height_px + game.current_speed() * 0.4, "fast return retains a speed-scaled reaction margin")
	game._tick_center_event(STEP)
	check(game.center_event == "off" and game.center_pending_metres >= 1500.0 and game.center_next_allowed_time == 70.0, "crossed ride milestones wait through cooldown instead of chaining invulnerability")
	var safe_before := _canonical(game.course.safe_sections)
	game._pause_run()
	var saved: Dictionary = p.load_resume()
	check(saved.schema == 6 and saved.center.next_allowed_time == 70.0, "schema6 persists the central attempt cooldown")
	p.load_game()
	game._show_menu()
	game._restore_run()
	check(game.state == game.State.PAUSED and game.center_next_allowed_time == 70.0, "disk restore retains the real central cooldown")
	check(_canonical(game.course.safe_sections) == safe_before, "disk restore preserves the existing post-transfer safe placement")
	game._continue_run()
	game.max_height_px = game.next_center_metres * RushTuning.PIXELS_PER_METRE
	game.height_px = game.max_height_px
	game.run_time = 20.0
	game._tick_center_event(STEP)
	check(game.center_event == "off" and game.center_next_allowed_time == 70.0 and _canonical(game.course.safe_sections) == safe_before, "valid daylight inside the restored cooldown cannot create or extend a safe section")
	game.run_time = 70.0
	check(game._center_event_allowed(), "the next full daylight window becomes eligible when cooldown expires")

func _test_night_restore() -> void:
	_prepare("ice", 4000.0, 50.0)
	game.run_seed = accepted_seed
	game.next_center_metres = 1500.0
	game.center_next_allowed_time = 91.0
	var advance: float = game.current_speed() * STEP
	game.course.hazards = [_wall(game.height_px + advance * 0.5, 4.0)]
	game._pause_run()
	var speed_before: float = game.current_speed()
	p.load_game()
	game._show_menu()
	game._restore_run()
	check(game.state == game.State.PAUSED and game.run_time == 50.0 and is_equal_approx(game.current_speed(), float(RushTuning.profile_for("ice")["night_speed"])) and is_equal_approx(game.current_speed(), speed_before), "disk checkpoint retains 4km night pace and phase")
	check(game.center_event == "off" and game.center_next_allowed_time == 91.0 and game.course.safe_sections.is_empty(), "night restore retains cooldown without manufacturing protected terrain")
	game._continue_run()
	game._simulate_step(STEP)
	check(game.state == game.State.DYING and game.center_event == "off" and p.data.runs == 1, "resumed night milestone still collides with its saved thin wall")

func _test_illegal_night_center_restore() -> void:
	for phase: String in ["preview", "enter", "ride", "exit"]:
		_prepare("ice", 4000.0, 50.0)
		game.center_event = phase
		game.center_elapsed = 0.2
		game.center_will_appear = true
		game.center_origin_side = -1
		game.center_next_allowed_time = 110.0
		game.side = 1
		game.course.begin_safe_section(game.height_px - 2000.0, game.height_px + 3000.0)
		var protected_before := _canonical(game.course.safe_sections)
		game._pause_run()
		p.load_game()
		game._show_menu()
		game._restore_run()
		check(game.state == game.State.PAUSED and game.center_event == "off" and not game.center_will_appear, "illegal restored night %s cancels the central wall before continuing" % phase)
		check(game.center_next_allowed_time == 110.0 and _canonical(game.course.safe_sections) == protected_before, "night cancellation preserves safe existing placement without extending it")
		if phase != "preview":
			check(game.side == -1 and game.gecko.mode == "run" and game.player_position().x == game.LEFT_X, "cancelled transfer restores its original outer wall")
		game._continue_run()
		game.next_center_metres = 1500.0
		game._tick_center_event(STEP)
		check(game.center_event == "off" and _canonical(game.course.safe_sections) == protected_before, "resumed night cannot start another preview or extend saved protection")

func _test_fast_wall_contacts() -> void:
	for spec: Array in [["ice", 12000.0], ["sky", 50000.0]]:
		_prepare(str(spec[0]), float(spec[1]), 10.0)
		var from: Vector2 = game.player_position()
		var advance: float = game.current_speed() * STEP
		var to := from - Vector2(0.0, advance)
		game.course.hazards = [_wall(game.height_px + advance * 0.5, 4.0)]
		check(advance > 100.0 and game.course.collision_kind_at(from, 10.0).is_empty() and game.course.collision_kind_at(to, 10.0 + STEP).is_empty(), "thin-wall fixture lies strictly between real high-speed frame endpoints")
		game._simulate_step(STEP)
		check(game.state == game.State.DYING and game.death_kind == ("ice_teeth" if spec[0] == "ice" else "storm_spikes"), "Main's real 120Hz step detects a crossed thin wall beyond 12km")
		check(p.data.runs == 1 and p.data.last_result.world_id == str(spec[0]) and p.data.best_height >= float(spec[1]), "swept death settles the actual high-distance world once")
		var settled := _canonical(p.data)
		game._die()
		check(_canonical(p.data) == settled, "duplicate swept death cannot repeat rewards")

func _test_fast_collection() -> void:
	_prepare("ice", 12000.0, 10.0)
	var from: Vector2 = game.player_position()
	var advance: float = game.current_speed() * STEP
	var coin := {"x": game.LEFT_X, "h": game.height_px + advance * 0.5, "collected": false}
	game.course.coins = [coin]
	check(Vector2(float(coin.x), -float(coin.h)).distance_to(from) > 48.0 and advance > 100.0, "fast collection fixture would be missed at either point-sampled endpoint")
	game._simulate_step(STEP)
	check(game.state == game.State.RUNNING and game.run_coins == 1 and bool(coin.collected), "Main collects a crossed coin with swept movement")
	game._simulate_step(STEP)
	check(game.run_coins == 1, "crossed coin can only be collected once")
