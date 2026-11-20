extends Node2D
## One continuous world: the menu's little clearing becomes the endless climb.
## Simulation is independent of rendering, and all flight checks use <= 1/120 s steps.

enum State { MENU, TRANSITION, RUNNING, DYING, RESULTS, PAUSED, PANEL, RESUMING }

const LEFT_X: float = RushTuning.PLAYER_LEFT
const RIGHT_X: float = RushTuning.PLAYER_RIGHT
const JUMP_DURATION: float = RushTuning.JUMP_DURATION
const JUMP_ARC: float = RushTuning.JUMP_ARC
const PIXELS_PER_METRE: float = RushTuning.PIXELS_PER_METRE
const PLAYER_RADIUS: float = 20.0
const RESUME_SCHEMA: int = 6
const CENTER_WALL_LEFT := RushTuning.CENTER_WALL_LEFT
const CENTER_WALL_RIGHT := RushTuning.CENTER_WALL_RIGHT
const RESUME_COUNTDOWN_SECONDS := 3.0
const COUNTDOWN_FONT: Font = preload("res://assets/fonts/OpenSans-Bold.ttf")

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
var center_next_allowed_time: float = 0.0
var center_pending_metres: float = 0.0
var center_first_given: bool = false
var center_active_metres: float = 0.0
var resume_elapsed: float = 0.0
var _application_active: bool = true
var _resume_layer: CanvasLayer
var _resume_backdrop: ColorRect
var _resume_panel: Panel
var _resume_label: Label
# Rendering follows the last two completed simulation steps. Physics and saves
# always read player_position(), never the interpolated Node2D transform.
var _motion_previous: Dictionary = {}
var _motion_current: Dictionary = {}
var _motion_rendered: Dictionary = {}
var _motion_waiting_resume := false

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
	_layout_resume_countdown()

func speed_at(height: float) -> float:
	return RushTuning.speed_at(height, world_id)

func current_speed() -> float:
	return RushTuning.run_speed_at(max_height_px, run_time, world_id)

func _apply_settings() -> void:
	if environment != null:
		environment.theme = str(Progress.data.settings.get("theme", "dark"))
	if gecko != null and gecko.has_method("set_skin"):
		gecko.call("set_skin", str(Progress.data.get("skin_id", "standard_green")))

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

func _capture_motion() -> Dictionary:
	return {"position": player_position(), "height": max_height_px,
		"time": run_time, "speed": current_speed(), "mode": gecko.mode,
		"side": gecko.side, "jump": gecko.jump_progress,
		"bob": sin(clampf(jump_elapsed / JUMP_DURATION, 0.0, 1.0) * PI) * JUMP_ARC if jump_elapsed >= 0.0 else 0.0}

func _reset_motion_interpolation() -> void:
	_motion_current = _capture_motion()
	_motion_previous = _motion_current.duplicate()
	_motion_rendered = _motion_current.duplicate()
	_motion_waiting_resume = false
	gecko.clear_render_motion()

func _begin_motion_step() -> void:
	if _motion_current.is_empty():
		_reset_motion_interpolation()
	_motion_previous = _capture_motion()
	if _motion_waiting_resume:
		# Resume from exactly the image held throughout 3, 2, 1. The world
		# simulation remains at its saved point; only this first visual span
		# includes the fraction of a tick that was still pending on pause.
		_motion_previous = _motion_rendered.duplicate()
		_motion_previous["position"] = gecko.position
		_motion_waiting_resume = false

func _sample_motion(alpha: float) -> Dictionary:
	var weight := clampf(alpha, 0.0, 1.0)
	var a := _motion_previous
	var b := _motion_current
	var sample := {"position": (a["position"] as Vector2).lerp(b["position"], weight)}
	for key: String in ["height", "time", "speed", "bob"]:
		sample[key] = lerpf(float(a[key]), float(b[key]), weight)
	sample["mode"] = b["mode"]
	sample["side"] = b["side"]
	sample["jump"] = float(b["jump"])
	if a["mode"] == "jump" and b["mode"] != "jump":
		# Landing may happen between rendered frames. Complete the turn at
		# the same instant as the interpolated contact with the other wall.
		sample["mode"] = "jump" if weight < 1.0 else b["mode"]
		sample["side"] = a["side"] if weight < 1.0 else b["side"]
		sample["jump"] = lerpf(float(a["jump"]), 1.0, weight)
	elif b["mode"] == "jump":
		var start := float(a["jump"]) if a["mode"] == "jump" else 0.0
		sample["jump"] = lerpf(start, float(b["jump"]), weight)
	return sample

func _motion_matches_simulation() -> bool:
	return not _motion_current.is_empty() and absf(float(_motion_current["time"]) - run_time) <= 0.000001 and (_motion_current["position"] as Vector2).distance_to(player_position()) <= 0.01

func _render_motion(alpha: float) -> void:
	if _motion_waiting_resume:
		return
	if not _motion_matches_simulation():
		# A restored checkpoint or an externally positioned debug fixture is
		# a new trajectory, not a span across an entire world's height.
		_reset_motion_interpolation()
	_motion_rendered = _sample_motion(alpha)
	gecko.position = _motion_rendered["position"]
	gecko.set_render_motion(str(_motion_rendered["mode"]), int(_motion_rendered["side"]), float(_motion_rendered["jump"]))
	course.render_time = float(_motion_rendered["time"])
	course.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			if state == State.RUNNING or state == State.RESUMING:
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
	gecko.jump_progress = 0.0
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
	if state != State.RUNNING:
		return
	_begin_motion_step()
	var previous_at := player_position()
	var previous_time := run_time
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
	_motion_current = _capture_motion()
	if not center_event in ["enter", "ride", "exit"]:
		var contact: String = course.collision_kind_along(previous_at, at, previous_time, run_time, PLAYER_RADIUS)
		if not contact.is_empty():
			_die(contact)
			return
	var picked: int = course.collect_along(previous_at, at)
	if picked > 0:
		run_coins += picked
		Audio.play_sound("coin")
		effects.burst(at, Color("ffe18c"), 13)
		effects.popup(at + Vector2(26, -55), "+%d" % picked)
	run_passed += course.count_passed(max_height_px)
	if jump_elapsed < 0.0 and not center_event in ["enter", "ride", "exit"] and not gecko.is_eating():
		var mouth: Vector2 = gecko.get_mouth_position()
		var fly: Dictionary = course.take_fly(at + mouth, side, GeckoVisual.MAX_TONGUE_REACH, previous_at + mouth)
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
	center_next_allowed_time = 0.0
	center_pending_metres = 0.0
	center_first_given = false
	center_active_metres = 0.0
	center_wall.reset_visual()
	environment.side_walls_visibility = 1.0

func _center_event_allowed() -> bool:
	# The complete preview/ride/return must fit in full daylight. Night and
	# dusk/dawn get neither a wall nor a translucent preview.
	if run_time < center_next_allowed_time or RushTuning.night_amount(run_time) > 0.001:
		return false
	var phase := fposmod(maxf(run_time, 0.0), RushTuning.CYCLE_SECONDS)
	var duration := RushTuning.CENTER_PREVIEW_SECONDS + RushTuning.CENTER_ENTER_SECONDS + RushTuning.CENTER_RIDE_SECONDS + RushTuning.CENTER_EXIT_SECONDS
	return phase + duration + 0.25 <= RushTuning.DAY_SECONDS - RushTuning.CYCLE_FADE_SECONDS

func _cancel_center_for_night() -> void:
	if center_active_metres == RushTuning.CENTER_EVERY_METRES and center_event in ["preview", "enter"]:
		center_pending_metres = RushTuning.CENTER_EVERY_METRES
		center_first_given = false
		center_next_allowed_time = 0.0
	if center_event in ["enter", "ride", "exit"]:
		side = center_origin_side
		from_side = side
		target_side = -side
		jump_elapsed = -1.0
		gecko.side = side
		gecko.mode = "run"
	center_event = "off"
	center_elapsed = 0.0
	center_will_appear = false
	center_active_metres = 0.0
	center_wall.reset_visual()
	environment.side_walls_visibility = 1.0
	gecko.position = player_position()

func _queue_center_milestone() -> void:
	# Keep one pending milestone while night/cooldown prevents an attempt.
	# Coalescing later crossed heights cannot erase the guaranteed first wall.
	if center_pending_metres <= 0.0:
		center_pending_metres = RushTuning.CENTER_EVERY_METRES if not center_first_given else next_center_metres
	next_center_metres = maxf(next_center_metres + RushTuning.CENTER_EVERY_METRES, (floorf(max_height_px / PIXELS_PER_METRE / RushTuning.CENTER_EVERY_METRES) + 1.0) * RushTuning.CENTER_EVERY_METRES)

func _begin_center_event() -> void:
	if center_event != "off":
		return
	if center_pending_metres <= 0.0:
		_queue_center_milestone()
	# Refusing night, dawn, late daylight or cooldown preserves the milestone.
	if not _center_event_allowed():
		center_will_appear = false
		return
	center_active_metres = center_pending_metres
	center_pending_metres = 0.0
	var event_number := maxi(1, roundi(center_active_metres / RushTuning.CENTER_EVERY_METRES))
	center_next_allowed_time = run_time + RushTuning.CYCLE_SECONDS
	var event_rng := RandomNumberGenerator.new()
	event_rng.seed = run_seed + event_number * 104729
	center_will_appear = event_number == 1 or event_rng.randf() < 0.5
	if event_number == 1:
		center_first_given = true
	center_event = "preview"
	center_elapsed = 0.0
	if center_will_appear:
		# Predict the complete transfer using the same height/night speed curve.
		# A max-speed bound would leave a very long empty course after a slow night.
		var predicted_height := max_height_px
		var duration := RushTuning.CENTER_PREVIEW_SECONDS + RushTuning.CENTER_ENTER_SECONDS + RushTuning.CENTER_RIDE_SECONDS + RushTuning.CENTER_EXIT_SECONDS + 0.65
		for step in range(ceili(duration * 60.0)):
			predicted_height += RushTuning.run_speed_at(predicted_height, run_time + float(step) / 60.0, world_id) / 60.0
		var entry_margin := maxf(900.0, RushTuning.max_speed_at(max_height_px, world_id) * 0.25)
		var return_margin := maxf(350.0, RushTuning.max_speed_at(predicted_height, world_id) * 0.45)
		course.begin_safe_section(max_height_px - entry_margin, predicted_height + return_margin)

func _tick_center_event(delta: float) -> void:
	if center_event != "off" and RushTuning.night_amount(run_time) > 0.001:
		_cancel_center_for_night()
		return
	if center_event == "off":
		var metres := max_height_px / PIXELS_PER_METRE
		if metres >= next_center_metres:
			_queue_center_milestone()
		elif not center_first_given and center_pending_metres <= 0.0 and metres >= RushTuning.CENTER_EVERY_METRES:
			center_pending_metres = RushTuning.CENTER_EVERY_METRES
		if center_pending_metres > 0.0:
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
				center_active_metres = 0.0
		"miss":
			if center_elapsed >= 0.5:
				center_event = "off"
				center_elapsed = 0.0
				center_active_metres = 0.0

func _update_center_visual(night: float) -> void:
	center_wall.phase = center_event
	center_wall.phase_elapsed = center_elapsed
	center_wall.ride_elapsed = center_elapsed if center_event == "ride" else 0.0
	center_wall.player_height = height_px
	center_wall.night_amount = night
	center_wall.animation_enabled = not state in [State.PAUSED, State.RESUMING]
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
	if state == State.RUNNING:
		_render_motion(Engine.get_physics_interpolation_fraction())
	var visual_time := float(_motion_rendered.get("time", run_time)) if state in [State.RUNNING, State.PAUSED, State.RESUMING] else run_time
	var night := RushTuning.night_amount(visual_time) if state != State.MENU and state != State.PANEL else 0.0
	environment.night_amount = night
	course.night_amount = night
	gecko.night_amount = night
	_update_center_visual(night)
	if state == State.RESUMING:
		_tick_resume_countdown(delta)
		_set_run_visuals_frozen(state in [State.PAUSED, State.RESUMING])
		_update_camera(0.0)
		return
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
			_reset_motion_interpolation()
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
	# Menus remain alive; pausing and the entire resume countdown freeze the run.
	_set_run_visuals_frozen(state in [State.PAUSED, State.RESUMING])

func _update_camera(delta: float) -> void:
	if world == null or environment == null:
		return
	var target_height: float = maxf(max_height_px - 130.0, 0.0)
	if state == State.RUNNING:
		var visual := _motion_rendered if _motion_matches_simulation() and not _motion_rendered.is_empty() else _capture_motion()
		# The camera and runner sample the same time. Mixing a 120 Hz body
		# with a per-frame camera caused a visible sawtooth at 240 Hz.
		target_height = maxf(float(visual["height"]) - 130.0, 0.0)
		target_height += float(visual["speed"]) / 7.5 - float(visual["bob"])
	if state == State.MENU or state == State.PANEL:
		target_height = 0.0
	if delta > 0.0 and not state in [State.PAUSED, State.RESUMING]:
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
		"appearance":
			_apply_settings()
		"play":
			_cash_out_saved_run()
			_start_run(false)
		"retry":
			_start_run(true)
		"resume":
			_restore_run()
		"menu":
			if state in [State.PAUSED, State.RESUMING]:
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
	_hide_resume_countdown()
	_set_run_visuals_frozen(false)
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
	_motion_previous.clear()
	_motion_current.clear()
	_motion_rendered.clear()
	_motion_waiting_resume = false
	effects.clear()
	ui.show_menu()
	ui.fade_in(0.25)
	_update_camera(0.0)

func _start_run(quick: bool) -> void:
	_hide_resume_countdown()
	_set_run_visuals_frozen(false)
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
	course.setup(run_seed, world_id)
	course.ensure_ahead(0.0, 0.0)
	course.visible = true
	gecko.visible = true
	gecko.reset_animation()
	gecko.side = -1
	gecko.position = Vector2(365.0, 73.0 - GeckoVisual.GROUND_FEET_Y)
	gecko.mode = "sleep"
	_motion_previous.clear()
	_motion_current.clear()
	_motion_rendered.clear()
	_motion_waiting_resume = false
	effects.clear()
	state = State.TRANSITION
	transition_clock = 0.0
	transition_duration = 1.35 if quick else 1.85
	ui.set_hint_visible(true)
	ui.fade_out(0.15 if quick else 0.35)
	Audio.play_sound("quake")

func _summary() -> Dictionary:
	return {"run_id": run_id, "world_id": world_id, "height": max_height_px / PIXELS_PER_METRE, "coins": run_coins, "jumps": run_jumps, "passed": run_passed}

func _die(cause: String = "impact") -> void:
	if state != State.RUNNING:
		return
	state = State.DYING
	gecko.clear_render_motion()
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
	if not state in [State.RUNNING, State.RESUMING]:
		return
	_hide_resume_countdown()
	state = State.PAUSED
	_set_run_visuals_frozen(true)
	_store_resume()
	ui.show_pause()

func _continue_run() -> void:
	if state != State.PAUSED or not _application_active:
		return
	state = State.RESUMING
	resume_elapsed = 0.0
	ui.show_hud()
	ui.update_hud(max_height_px / PIXELS_PER_METRE, run_coins)
	ui.update_cycle(RushTuning.is_night(run_time), RushTuning.cycle_remaining(run_time))
	ui.set_hint_visible(false)
	_set_run_visuals_frozen(true)
	_show_resume_countdown()

func _set_run_visuals_frozen(frozen: bool) -> void:
	if gecko != null:
		gecko.set_process(not frozen)
	if environment != null:
		environment.set_process(not frozen)
	if effects != null:
		effects.enabled = not frozen
	if center_wall != null:
		center_wall.animation_enabled = not frozen

func _show_resume_countdown() -> void:
	if _resume_layer == null:
		_resume_layer = CanvasLayer.new()
		_resume_layer.name = "ResumeCountdown"
		_resume_layer.layer = 64
		add_child(_resume_layer)
		_resume_backdrop = ColorRect.new()
		_resume_backdrop.name = "InputGuard"
		_resume_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_resume_layer.add_child(_resume_backdrop)
		_resume_panel = Panel.new()
		_resume_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resume_layer.add_child(_resume_panel)
		_resume_label = Label.new()
		_resume_label.name = "ResumeDigit"
		_resume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_resume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_resume_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resume_label.add_theme_font_override("font", COUNTDOWN_FONT)
		_resume_panel.add_child(_resume_label)
	var light := str(Progress.data.settings.get("theme", "dark")) == "light"
	_resume_backdrop.color = Color(0.03, 0.08, 0.09, 0.35 if light else 0.55)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff6db") if light else Color("102133")
	style.set_corner_radius_all(32)
	style.set_border_width_all(3)
	style.border_color = Color("7d9f53") if light else Color("8eaf65")
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 7)
	_resume_panel.add_theme_stylebox_override("panel", style)
	_resume_label.add_theme_color_override("font_color", Color("153d33") if light else Color("d2f391"))
	_resume_layer.visible = true
	_layout_resume_countdown()
	_update_resume_digit()

func _layout_resume_countdown() -> void:
	if _resume_layer == null:
		return
	var frame := get_viewport_rect().size
	_resume_backdrop.position = Vector2.ZERO
	_resume_backdrop.size = frame
	var extent := clampf(minf(frame.x, frame.y) * 0.29, 280.0, 390.0)
	_resume_panel.size = Vector2.ONE * extent
	_resume_panel.position = (frame - _resume_panel.size) * 0.5
	_resume_label.position = Vector2.ZERO
	_resume_label.size = _resume_panel.size
	_resume_label.pivot_offset = _resume_label.size * 0.5
	_resume_label.add_theme_font_size_override("font_size", int(extent * 0.66))

func _update_resume_digit() -> void:
	if _resume_label == null:
		return
	_resume_label.text = str(clampi(3 - floori(resume_elapsed), 1, 3))
	var beat := fposmod(resume_elapsed, 1.0)
	var pulse := lerpf(1.10, 1.0, smoothstep(0.0, 0.22, beat))
	_resume_label.scale = Vector2.ONE * pulse
	_resume_label.modulate.a = 1.0 - 0.25 * smoothstep(0.72, 1.0, beat)

func _hide_resume_countdown() -> void:
	resume_elapsed = 0.0
	if _resume_layer != null:
		_resume_layer.visible = false

func _tick_resume_countdown(delta: float) -> void:
	if not _application_active:
		_pause_run()
		return
	resume_elapsed = minf(RESUME_COUNTDOWN_SECONDS, resume_elapsed + maxf(delta, 0.0))
	if resume_elapsed >= RESUME_COUNTDOWN_SECONDS:
		_hide_resume_countdown()
		state = State.RUNNING
		_motion_waiting_resume = true
		ui.set_hint_visible(run_jumps == 0)
		return
	_update_resume_digit()

func _store_resume() -> void:
	if not state in [State.RUNNING, State.PAUSED, State.RESUMING]:
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
			"will_appear": center_will_appear, "origin_side": center_origin_side, "entry_x": center_entry_x, "lane_x": center_lane_x,
			"next_allowed_time": center_next_allowed_time, "pending_metres": center_pending_metres,
			"first_given": center_first_given, "active_metres": center_active_metres},
		"course": course.snapshot()
	})

func _restore_run() -> void:
	_hide_resume_countdown()
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
	center_next_allowed_time = maxf(0.0, float(saved_center.get("next_allowed_time", 0.0)))
	center_pending_metres = maxf(0.0, float(saved_center.get("pending_metres", 0.0)))
	center_active_metres = maxf(0.0, float(saved_center.get("active_metres", 0.0)))
	if saved_center.has("first_given"):
		center_first_given = bool(saved_center["first_given"])
	else:
		# Existing schema-6 checkpoints do not record whether the first roll
		# was skipped. Preserve accepted transfers already in progress; repair
		# ambiguous off/missed saves with one guaranteed daytime opportunity.
		var accepted_active := center_will_appear and center_event in ["preview", "enter", "ride", "exit"]
		center_first_given = accepted_active
		if accepted_active:
			center_active_metres = RushTuning.CENTER_EVERY_METRES
		elif max_height_px / PIXELS_PER_METRE >= RushTuning.CENTER_EVERY_METRES:
			center_pending_metres = RushTuning.CENTER_EVERY_METRES
			center_next_allowed_time = 0.0
	center_origin_side = -1 if int(saved_center.get("origin_side", -1)) < 0 else 1
	center_entry_x = clampf(float(saved_center.get("entry_x", LEFT_X)), LEFT_X, RIGHT_X)
	center_lane_x = CENTER_WALL_LEFT - 26.0 if center_origin_side == -1 else CENTER_WALL_RIGHT + 26.0
	save_clock = 0.0
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
	if center_event != "off" and RushTuning.night_amount(run_time) > 0.001:
		_cancel_center_for_night()
	effects.clear()
	_reset_motion_interpolation()
	state = State.PAUSED
	_set_run_visuals_frozen(true)
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
		"world_id": str(saved.get("world_id", "jungle")),
		"height": float(saved.get("max_height_px", 0.0)) / float(saved.get("pixels_per_metre", 28.0)),
		"coins": int(saved.get("coins", 0)), "jumps": int(saved.get("jumps", 0)),
		"passed": int(saved.get("passed", 0))
	})

func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_application_active = true
		_refresh_display_rate.call_deferred()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_application_active = false
		_pause_run()
		if state == State.TRANSITION:
			# Commit the short launch to a safe, resumable running state.
			state = State.RUNNING
			height_px = 120.0
			max_height_px = 120.0
			gecko.mode = "run"
			gecko.side = side
			gecko.position = player_position()
			_reset_motion_interpolation()
			_pause_run()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state in [State.RUNNING, State.RESUMING]:
			_pause_run()
		elif state == State.PAUSED:
			_continue_run()
		elif state == State.PANEL:
			_show_menu()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_store_resume()
		Progress.save_game()
		get_tree().quit()
