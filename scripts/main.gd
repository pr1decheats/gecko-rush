extends Node2D
## One continuous world: the menu's little clearing becomes the endless climb.
## Simulation is independent of rendering, and all flight checks use <= 1/120 s steps.

enum State { MENU, TRANSITION, RUNNING, DYING, RESULTS, PAUSED, PANEL }

const LEFT_X: float = RushTuning.PLAYER_LEFT
const RIGHT_X: float = RushTuning.PLAYER_RIGHT
const JUMP_DURATION: float = RushTuning.JUMP_DURATION
const JUMP_ARC: float = RushTuning.JUMP_ARC
const PIXELS_PER_METRE: float = RushTuning.PIXELS_PER_METRE
const PLAYER_RADIUS: float = 20.0
const RESUME_SCHEMA: int = 4
const CENTER_WALL_LEFT := RushTuning.CENTER_WALL_LEFT
const CENTER_WALL_RIGHT := RushTuning.CENTER_WALL_RIGHT

var state: State = State.MENU
var environment: JungleEnvironment
var world: Node2D
var course: RushCourse
var gecko: GeckoVisual
var effects: RushEffects
var center_wall: RushCenterWall
var ui: RushUI

var height_px: float = 0.0
var max_height_px: float = 0.0
var side: int = -1
var from_side: int = -1
var target_side: int = 1
var jump_elapsed: float = -1.0
var run_time: float = 0.0
var run_coins: int = 0
var run_jumps: int = 0
var run_passed: int = 0
var run_seed: int = 0
var run_id: String = ""
var world_id: String = "jungle"
var camera_height: float = 0.0
var record_announced: bool = false
var save_clock: float = 0.0
var transition_clock: float = 0.0
var transition_duration: float = 1.05
var death_clock: float = 0.0
var death_kind: String = "impact"
var camera_shake: float = 0.0
var last_result: Dictionary = {}
var previous_state: State = State.MENU
var next_center_metres: float = RushTuning.CENTER_EVERY_METRES
var center_event: String = "off"
var center_elapsed: float = 0.0
var center_will_appear: bool = false
var center_origin_side: int = -1
var center_entry_x: float = LEFT_X
var center_lane_x: float = CENTER_WALL_LEFT - 26.0

func _ready() -> void:
	get_tree().auto_accept_quit = false
	randomize()
	environment = JungleEnvironment.new()
	add_child(environment)
	world = Node2D.new()
	add_child(world)
	course = RushCourse.new()
	world.add_child(course)
	center_wall = RushCenterWall.new()
	world.add_child(center_wall)
	effects = RushEffects.new()
	world.add_child(effects)
	gecko = GeckoVisual.new()
	world.add_child(gecko)
	ui = RushUI.new()
	add_child(ui)
	ui.action.connect(_on_action)
	Progress.changed.connect(_apply_settings)
	_apply_settings()
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_show_menu()
	_refresh_display_rate.call_deferred()

func _update_layout() -> void:
	if environment != null:
		environment.viewport_height = get_viewport_rect().size.y
	_update_camera(0.0)

func speed_at(height: float) -> float:
	return RushTuning.speed_at(height)

func current_speed() -> float:
	return RushTuning.run_speed_at(max_height_px, run_time)

func _apply_settings() -> void:
	if environment != null:
		environment.theme = str(Progress.data.settings.get("theme", "dark"))

func _refresh_display_rate() -> void:
	Progress.ANDROID_REFRESH.request_rate(int(Progress.data.settings.get("fps", 60)))
	if OS.has_feature("android"):
		# A recreated Android Surface can become valid after the focus notification.
		get_tree().create_timer(0.4).timeout.connect(func() -> void:
			Progress.ANDROID_REFRESH.request_rate(int(Progress.data.settings.get("fps", 60))))

func player_position() -> Vector2:
	var x: float = LEFT_X if side == -1 else RIGHT_X
	if center_event == "enter":
		x = lerpf(center_entry_x, center_lane_x, smoothstep(0.0, RushTuning.CENTER_ENTER_SECONDS, center_elapsed))
	elif center_event == "ride":
		x = center_lane_x
	elif center_event == "exit":
		var outer_x := LEFT_X if center_origin_side == -1 else RIGHT_X
		x = lerpf(center_lane_x, outer_x, smoothstep(0.0, RushTuning.CENTER_EXIT_SECONDS, center_elapsed))
	elif jump_elapsed >= 0.0:
		var progress: float = clampf(jump_elapsed / JUMP_DURATION, 0.0, 1.0)
		var eased: float = (1.0 - cos(progress * PI)) * 0.5
		var start: float = LEFT_X if from_side == -1 else RIGHT_X
		var finish: float = LEFT_X if target_side == -1 else RIGHT_X
		x = lerpf(start, finish, eased)
	return Vector2(x, -height_px)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			if state == State.RUNNING:
				_pause_run()
			elif state == State.PAUSED:
				_continue_run()
			elif state == State.PANEL:
				_show_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE and state == State.RUNNING:
			jump()
			get_viewport().set_input_as_handled()
			return
	if state != State.RUNNING:
		return
	# Godot routes touch through mouse emulation so native GUI buttons consume it.
	# Only the resulting unhandled mouse press reaches gameplay, exactly once.
	if event is InputEventScreenTouch and event.pressed and event.index == 0 and not Input.emulate_mouse_from_touch:
		jump()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		jump()
		get_viewport().set_input_as_handled()

func jump() -> bool:
	# No buffering of flight taps: one press always means at most one jump.
	if state != State.RUNNING or jump_elapsed >= 0.0 or center_event in ["enter", "ride", "exit"]:
		return false
	from_side = side
	target_side = -side
	jump_elapsed = 0.0
	gecko.mode = "jump"
	gecko.launch()
	Audio.play_sound("jump")
	effects.burst(player_position(), Color("d4f3a3"), 9)
	ui.set_hint_visible(false)
	return true

func _physics_process(delta: float) -> void:
	if state != State.RUNNING:
		return
	var remaining: float = minf(delta, 0.2)
	while remaining > 0.00001 and state == State.RUNNING:
		var step: float = minf(remaining, 1.0 / 120.0)
		_simulate_step(step)
		remaining -= step
	save_clock += delta
	if save_clock >= 5.0 and state == State.RUNNING:
		save_clock = 0.0
		_store_resume()

func _simulate_step(delta: float) -> void:
	run_time += delta
	height_px += current_speed() * delta
	if jump_elapsed >= 0.0:
		var old_fraction: float = clampf(jump_elapsed / JUMP_DURATION, 0.0, 1.0)
		jump_elapsed = minf(jump_elapsed + delta, JUMP_DURATION)
		var new_fraction: float = jump_elapsed / JUMP_DURATION
		height_px += (sin(new_fraction * PI) - sin(old_fraction * PI)) * JUMP_ARC
		gecko.jump_progress = new_fraction
		if jump_elapsed >= JUMP_DURATION - 0.000001:
			side = target_side
			jump_elapsed = -1.0
			run_jumps += 1
			gecko.side = side
			gecko.mode = "run"
			gecko.land()
			Audio.play_sound("land")
			effects.burst(player_position(), Color("e3e5b7"), 7)
	max_height_px = maxf(max_height_px, height_px)
	_tick_center_event(delta)
	course.ensure_ahead(max_height_px, run_time)
	var at: Vector2 = player_position()
	gecko.position = at
	gecko.run_speed_factor = current_speed() / RushTuning.START_SPEED
	if not center_event in ["enter", "ride", "exit"]:
		var contact: String = course.collision_kind_at(at, run_time, PLAYER_RADIUS)
		if not contact.is_empty():
			_die(contact)
			return
	var picked: int = course.collect_at(at, run_time)
	if picked > 0:
		run_coins += picked
		Audio.play_sound("coin")
		effects.burst(at, Color("ffe18c"), 13)
		effects.popup(at + Vector2(26, -55), "+%d" % picked)
	run_passed += course.count_passed(max_height_px)
	if jump_elapsed < 0.0 and not center_event in ["enter", "ride", "exit"] and not gecko.is_eating():
		var fly: Dictionary = course.take_fly(at, side)
		if not fly.is_empty():
			gecko.eat_to(fly.position - at)
			Audio.play_sound("eat")
	var metres: float = max_height_px / PIXELS_PER_METRE
	if not record_announced and metres > maxf(float(Progress.data.best_height), 20.0):
		record_announced = true
		Audio.play_sound("record")
		ui.toast("НОВЫЙ РЕКОРД!")
		effects.burst(at, Color("d9f8a0"), 24)

func _reset_center_event() -> void:
	next_center_metres = RushTuning.CENTER_EVERY_METRES
	center_event = "off"
	center_elapsed = 0.0
	center_will_appear = false
	center_origin_side = -1
	center_entry_x = LEFT_X
	center_lane_x = CENTER_WALL_LEFT - 26.0
	center_wall.reset_visual()
	environment.side_walls_visibility = 1.0

func _begin_center_event() -> void:
	var event_number := maxi(1, roundi(next_center_metres / RushTuning.CENTER_EVERY_METRES))
	var event_rng := RandomNumberGenerator.new()
	event_rng.seed = run_seed + event_number * 104729
	center_will_appear = event_rng.randf() < 0.5
	next_center_metres += RushTuning.CENTER_EVERY_METRES
	center_event = "preview"
	center_elapsed = 0.0
	if center_will_appear:
		# Predict the complete transfer using the same height/night speed curve.
		# A max-speed bound would leave a very long empty course after a slow night.
		var predicted_height := max_height_px
		var duration := RushTuning.CENTER_PREVIEW_SECONDS + RushTuning.CENTER_ENTER_SECONDS + RushTuning.CENTER_RIDE_SECONDS + RushTuning.CENTER_EXIT_SECONDS + 0.65
		for step in range(ceili(duration * 60.0)):
			predicted_height += RushTuning.run_speed_at(predicted_height, run_time + float(step) / 60.0) / 60.0
		course.begin_safe_section(max_height_px - 900.0, predicted_height + 350.0)

func _tick_center_event(delta: float) -> void:
	if center_event == "off":
		if max_height_px / PIXELS_PER_METRE >= next_center_metres:
			_begin_center_event()
		return
	center_elapsed += delta
	match center_event:
		"preview":
			if center_elapsed >= RushTuning.CENTER_PREVIEW_SECONDS:
				if center_will_appear:
					center_entry_x = player_position().x
					center_origin_side = -1 if center_entry_x < 540.0 else 1
					center_lane_x = CENTER_WALL_LEFT - 26.0 if center_origin_side == -1 else CENTER_WALL_RIGHT + 26.0
					side = center_origin_side
					jump_elapsed = -1.0
					gecko.side = side
					gecko.mode = "jump"
					gecko.launch()
					gecko.jump_progress = 0.0
					center_event = "enter"
				else:
					center_event = "miss"
				center_elapsed = 0.0
		"enter":
			gecko.jump_progress = clampf(center_elapsed / RushTuning.CENTER_ENTER_SECONDS, 0.0, 1.0)
			if center_elapsed >= RushTuning.CENTER_ENTER_SECONDS:
				center_event = "ride"
				center_elapsed = 0.0
				side = -center_origin_side
				gecko.side = side
				gecko.mode = "run"
				gecko.land()
		"ride":
			if center_elapsed >= RushTuning.CENTER_RIDE_SECONDS:
				center_wall.player_height = height_px
				center_wall.shatter()
				center_event = "exit"
				center_elapsed = 0.0
				gecko.mode = "jump"
				gecko.launch()
				gecko.jump_progress = 0.0
		"exit":
			gecko.jump_progress = clampf(center_elapsed / RushTuning.CENTER_EXIT_SECONDS, 0.0, 1.0)
			if center_elapsed >= RushTuning.CENTER_EXIT_SECONDS:
				side = center_origin_side
				from_side = side
				target_side = -side
				gecko.side = side
				gecko.mode = "run"
				gecko.land()
				center_event = "off"
				center_elapsed = 0.0
		"miss":
			if center_elapsed >= 0.5:
				center_event = "off"
				center_elapsed = 0.0

func _update_center_visual(night: float) -> void:
	center_wall.phase = center_event
	center_wall.phase_elapsed = center_elapsed
	center_wall.ride_elapsed = center_elapsed if center_event == "ride" else 0.0
	center_wall.player_height = height_px
	center_wall.night_amount = night
	center_wall.animation_enabled = state != State.PAUSED
	center_wall.visible = not state in [State.MENU, State.PANEL]
	center_wall.queue_redraw()
	match center_event:
		"enter": environment.side_walls_visibility = 1.0 - smoothstep(0.0, RushTuning.CENTER_ENTER_SECONDS, center_elapsed)
		"ride": environment.side_walls_visibility = 0.0
		"exit": environment.side_walls_visibility = smoothstep(0.0, RushTuning.CENTER_EXIT_SECONDS, center_elapsed)
		_: environment.side_walls_visibility = 1.0

func _process(delta: float) -> void:
	if environment == null:
		return
	var night := RushTuning.night_amount(run_time) if state != State.MENU and state != State.PANEL else 0.0
	environment.night_amount = night
	course.night_amount = night
	gecko.night_amount = night
	_update_center_visual(night)
	if state == State.RUNNING:
		ui.update_hud(max_height_px / PIXELS_PER_METRE, run_coins)
		ui.update_cycle(RushTuning.is_night(run_time), RushTuning.cycle_remaining(run_time))
	if state == State.TRANSITION:
		transition_clock += delta
		var fraction: float = clampf(transition_clock / transition_duration, 0.0, 1.0)
		var approach: float = smoothstep(0.42, 0.78, fraction)
		gecko.position.x = lerpf(365.0, LEFT_X, approach)
		height_px = smoothstep(0.70, 1.0, fraction) * 120.0
		max_height_px = height_px
		gecko.position.y = lerpf(73.0 - GeckoVisual.GROUND_FEET_Y, -120.0, smoothstep(0.58, 1.0, fraction))
		gecko.set_launch_pose(fraction)
		environment.menu_blend = 1.0 - fraction
		if fraction >= 1.0:
			state = State.RUNNING
			gecko.mode = "run"
			gecko.position = player_position()
			ui.show_hud()
			ui.fade_in(0.3)
			_store_resume()
	elif state == State.DYING:
		death_clock += delta
		if death_kind != "electric":
			gecko.position += Vector2(side * -45.0, 130.0) * delta * 0.3
			gecko.rotation += side * delta * 1.3
		camera_shake = maxf(0.0, camera_shake - delta * 22.0)
		var death_duration := GeckoVisual.ELECTRO_DURATION if death_kind == "electric" else 0.68
		if death_clock >= death_duration:
			state = State.RESULTS
			gecko.visible = false
			ui.show_results(last_result)
			if int(last_result.get("level", 1)) > int(last_result.get("old_level", 1)):
				Audio.play_sound("level")
			elif bool(last_result.get("new_best", false)):
				Audio.play_sound("record")
	_update_camera(delta)
	effects.enabled = state != State.PAUSED
	# Idle menus remain alive; the run itself freezes completely during a pause.
	gecko.set_process(state != State.PAUSED)
	environment.set_process(state != State.PAUSED)

func _update_camera(delta: float) -> void:
	if world == null or environment == null:
		return
	var target_height: float = maxf(max_height_px - 130.0, 0.0)
	if state == State.RUNNING:
		var bob := sin(clampf(jump_elapsed / JUMP_DURATION, 0.0, 1.0) * PI) * JUMP_ARC if jump_elapsed >= 0.0 else 0.0
		# Cancel the speed-dependent follow lag, while retaining the visible jump arc.
		target_height += current_speed() / 7.5 - bob
	if state == State.MENU or state == State.PANEL:
		target_height = 0.0
	if delta > 0.0 and state != State.PAUSED:
		camera_height = lerpf(camera_height, target_height, 1.0 - exp(-delta * 7.5))
	var shake := Vector2.ZERO
	if state == State.DYING and camera_shake > 0.0:
		shake = Vector2(sin(death_clock * 91.0), cos(death_clock * 107.0)) * camera_shake
	elif state == State.TRANSITION:
		var fraction := clampf(transition_clock / transition_duration, 0.0, 1.0)
		var strength := smoothstep(0.0, 0.025, fraction) * (1.0 - smoothstep(0.12, 0.31, fraction)) * 9.0
		shake = Vector2(sin(transition_clock * 73.0), cos(transition_clock * 89.0) * 0.65) * strength
	var horizontal_offset: float = maxf(0.0, (get_viewport_rect().size.x - 1080.0) * 0.5)
	world.position = Vector2(horizontal_offset, get_viewport_rect().size.y - 520.0 + camera_height) + shake
	environment.position = Vector2(horizontal_offset, 0.0) + (shake if state == State.TRANSITION else Vector2.ZERO)
	environment.camera_height = camera_height

func _on_action(name: String, payload: Variant = null) -> void:
	if name != "setting":
		Audio.play_sound("button")
	match name:
		"play":
			_cash_out_saved_run()
			_start_run(false)
		"retry":
			_start_run(true)
		"resume":
			_restore_run()
		"menu":
			if state == State.PAUSED:
				_cash_out_current_run()
			_show_menu()
		"shop", "profile", "daily", "settings":
			if state == State.MENU or state == State.PANEL:
				state = State.PANEL
				ui.show_panel(name)
		"pause":
			_pause_run()
		"continue":
			_continue_run()
		"world":
			if Progress.select_world(str(payload)):
				world_id = str(payload)
				environment.set_world(world_id)
				ui.show_panel("profile")
		"claim":
			if Progress.claim_daily(str(payload)):
				Audio.play_sound("coin")
				ui.show_panel("daily")
		"setting":
			if payload is Dictionary:
				var key: String = str(payload.get("key", ""))
				if key in ["music", "sfx", "jump_sfx", "theme", "language", "fps"]:
					Progress.data.settings[key] = payload.get("value")
					Progress.settings_changed()
					ui.show_panel("settings")

func _show_menu() -> void:
	var previous_save: Dictionary = Progress.load_resume()
	if not previous_save.is_empty() and int(previous_save.get("schema", 0)) != RESUME_SCHEMA:
		_cash_out_saved_run()
	state = State.MENU
	height_px = 0.0
	max_height_px = 0.0
	camera_height = 0.0
	camera_shake = 0.0
	run_time = 0.0
	_reset_center_event()
	world_id = str(Progress.current_world().id)
	environment.set_world(world_id)
	environment.menu_blend = 1.0
	course.visible = false
	gecko.visible = true
	gecko.reset_animation()
	gecko.position = Vector2(365.0, 73.0 - GeckoVisual.GROUND_FEET_Y)
	gecko.mode = "sleep"
	gecko.side = -1
	effects.clear()
	ui.show_menu()
	ui.fade_in(0.25)
	_update_camera(0.0)

func _start_run(quick: bool) -> void:
	Progress.clear_resume()
	world_id = str(Progress.current_world().id)
	environment.set_world(world_id)
	height_px = 0.0
	max_height_px = 0.0
	side = -1
	from_side = -1
	target_side = 1
	jump_elapsed = -1.0
	run_time = 0.0
	_reset_center_event()
	run_coins = 0
	run_jumps = 0
	run_passed = 0
	record_announced = false
	death_kind = "impact"
	save_clock = 0.0
	camera_height = 0.0
	run_seed = int(randi())
	run_id = "%d-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), run_seed]
	course.challenge_level = Progress.get_level()
	course.setup(run_seed, world_id)
	course.ensure_ahead(0.0, 0.0)
	course.visible = true
	gecko.visible = true
	gecko.reset_animation()
	gecko.side = -1
	gecko.position = Vector2(365.0, 73.0 - GeckoVisual.GROUND_FEET_Y)
	gecko.mode = "sleep"
	effects.clear()
	state = State.TRANSITION
	transition_clock = 0.0
	transition_duration = 1.35 if quick else 1.85
	ui.set_hint_visible(true)
	ui.fade_out(0.15 if quick else 0.35)
	Audio.play_sound("quake")

func _summary() -> Dictionary:
	return {"run_id": run_id, "height": max_height_px / PIXELS_PER_METRE, "coins": run_coins, "jumps": run_jumps, "passed": run_passed}

func _die(cause: String = "impact") -> void:
	if state != State.RUNNING:
		return
	state = State.DYING
	death_clock = 0.0
	death_kind = cause
	camera_shake = 7.0 if cause == "electric" else 13.0
	if cause == "electric":
		gecko.electrocute()
		Audio.play_sound("electric")
	else:
		gecko.hurt()
		Audio.play_sound("hit")
		effects.burst(player_position(), Color("edf6bd"), 23)
	last_result = _summary()
	last_result.merge(Progress.finish_run(last_result), true)
	ui.set_hint_visible(false)
	ui.fade_out(0.2)

func _pause_run() -> void:
	if state != State.RUNNING:
		return
	state = State.PAUSED
	_store_resume()
	ui.show_pause()

func _continue_run() -> void:
	if state != State.PAUSED:
		return
	state = State.RUNNING
	ui.show_hud()
	ui.update_hud(max_height_px / PIXELS_PER_METRE, run_coins)
	ui.set_hint_visible(run_jumps == 0)
	ui.fade_in(0.15)

func _store_resume() -> void:
	if state != State.RUNNING and state != State.PAUSED:
		return
	Progress.save_resume({
		"schema": RESUME_SCHEMA, "run_id": run_id, "world_id": world_id,
		"pixels_per_metre": PIXELS_PER_METRE,
		"height_px": height_px, "max_height_px": max_height_px,
		"side": side, "from_side": from_side, "target_side": target_side,
		"jump_elapsed": jump_elapsed, "time": run_time, "seed": run_seed,
		"coins": run_coins, "jumps": run_jumps, "passed": run_passed,
		"camera_height": camera_height, "record_announced": record_announced,
		"center": {"next_metres": next_center_metres, "event": center_event, "elapsed": center_elapsed,
			"will_appear": center_will_appear, "origin_side": center_origin_side, "entry_x": center_entry_x, "lane_x": center_lane_x},
		"course": course.snapshot()
	})

func _restore_run() -> void:
	var saved: Dictionary = Progress.load_resume()
	if int(saved.get("schema", 0)) != RESUME_SCHEMA or not saved.get("course", {}) is Dictionary:
		Progress.clear_resume()
		ui.toast("Сохранённый забег недоступен")
		return
	world_id = str(saved.get("world_id", "jungle"))
	run_id = str(saved.get("run_id", ""))
	height_px = maxf(0.0, float(saved.get("height_px", 0.0)))
	max_height_px = maxf(height_px, float(saved.get("max_height_px", height_px)))
	side = -1 if int(saved.get("side", -1)) < 0 else 1
	from_side = -1 if int(saved.get("from_side", side)) < 0 else 1
	target_side = -from_side
	jump_elapsed = clampf(float(saved.get("jump_elapsed", -1.0)), -1.0, JUMP_DURATION)
	run_time = maxf(0.0, float(saved.get("time", 0.0)))
	run_seed = int(saved.get("seed", 0))
	run_coins = maxi(0, int(saved.get("coins", 0)))
	run_jumps = maxi(0, int(saved.get("jumps", 0)))
	run_passed = maxi(0, int(saved.get("passed", 0)))
	camera_height = maxf(0.0, float(saved.get("camera_height", 0.0)))
	record_announced = bool(saved.get("record_announced", false))
	_reset_center_event()
	var saved_center: Dictionary = saved.get("center", {}) if saved.get("center", {}) is Dictionary else {}
	next_center_metres = maxf(RushTuning.CENTER_EVERY_METRES, float(saved_center.get("next_metres", (floorf(max_height_px / PIXELS_PER_METRE / RushTuning.CENTER_EVERY_METRES) + 1.0) * RushTuning.CENTER_EVERY_METRES)))
	center_event = str(saved_center.get("event", "off"))
	if not center_event in ["off", "preview", "enter", "ride", "exit", "miss"]:
		center_event = "off"
	center_elapsed = clampf(float(saved_center.get("elapsed", 0.0)), 0.0, RushTuning.CENTER_RIDE_SECONDS)
	center_will_appear = bool(saved_center.get("will_appear", false))
	center_origin_side = -1 if int(saved_center.get("origin_side", -1)) < 0 else 1
	center_entry_x = clampf(float(saved_center.get("entry_x", LEFT_X)), LEFT_X, RIGHT_X)
	center_lane_x = CENTER_WALL_LEFT - 26.0 if center_origin_side == -1 else CENTER_WALL_RIGHT + 26.0
	save_clock = 0.0
	course.challenge_level = Progress.get_level()
	course.setup(run_seed, world_id)
	course.restore(saved.course)
	course.ensure_ahead(max_height_px, run_time)
	course.visible = true
	environment.set_world(world_id)
	environment.menu_blend = 0.0
	gecko.reset_animation()
	gecko.visible = true
	gecko.side = side
	gecko.mode = "jump" if jump_elapsed >= 0.0 or center_event in ["enter", "exit"] else "run"
	gecko.jump_progress = maxf(jump_elapsed / JUMP_DURATION, 0.0)
	if center_event in ["enter", "exit"]:
		gecko.jump_progress = clampf(center_elapsed / (RushTuning.CENTER_ENTER_SECONDS if center_event == "enter" else RushTuning.CENTER_EXIT_SECONDS), 0.0, 1.0)
	gecko.run_speed_factor = current_speed() / RushTuning.START_SPEED
	gecko.position = player_position()
	effects.clear()
	state = State.PAUSED
	_update_center_visual(RushTuning.night_amount(run_time))
	ui.show_pause()
	_update_camera(0.0)

func _cash_out_current_run() -> void:
	if run_id.is_empty():
		return
	Progress.finish_run(_summary())

func _cash_out_saved_run() -> void:
	var saved: Dictionary = Progress.load_resume()
	if saved.is_empty():
		return
	Progress.finish_run({
		"run_id": str(saved.get("run_id", "")),
		"height": float(saved.get("max_height_px", 0.0)) / float(saved.get("pixels_per_metre", 28.0)),
		"coins": int(saved.get("coins", 0)), "jumps": int(saved.get("jumps", 0)),
		"passed": int(saved.get("passed", 0))
	})

func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_refresh_display_rate.call_deferred()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_pause_run()
		if state == State.TRANSITION:
			# Commit the short launch to a safe, resumable running state.
			state = State.RUNNING
			height_px = 120.0
			max_height_px = 120.0
			gecko.mode = "run"
			gecko.side = side
			gecko.position = player_position()
			_pause_run()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_store_resume()
		Progress.save_game()
		get_tree().quit()
