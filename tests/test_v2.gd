extends SceneTree
var checks := 0
var failures := 0
var progress: Node
var game: Node

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(title)

func texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Label or node is Button:
		result.append(node.text)
	for child in node.get_children():
		result.append_array(texts(child))
	return result

func _run() -> void:
	progress = root.get_node("Progress")
	var audio: Node = root.get_node("Audio")
	var locale: Node = root.get_node("L10n")
	progress.save_file = "user://v2_settings_test.json"
	progress.data = progress._defaults()
	var old: Dictionary = progress._sanitize({"version": 3, "coins": 123, "xp": 570, "settings": {"music": false, "sfx": true}})
	check(old.coins == 123 and old.xp == 570, "old progress survives settings migration")
	check(old.settings.theme == "dark" and old.settings.fps == 60 and old.settings.jump_sfx, "old saves get new settings defaults")
	var invalid: Dictionary = progress._sanitize({"settings": {"theme": "wrong", "language": "xx", "fps": 999, "jump_sfx": "false"}})
	check(invalid.settings.theme == "dark" and invalid.settings.fps == 60 and invalid.settings.language == "ru" and invalid.settings.jump_sfx, "invalid settings are normalized")
	progress.data.settings = {"music": false, "sfx": true, "jump_sfx": false, "theme": "dark", "language": "en", "fps": 120}
	progress.settings_changed()
	check(Engine.max_fps == 120 and locale.language == "en", "120fps and English apply immediately")
	audio.play_sound("jump")
	audio.play_sound("land")
	check(not audio._players.jump.playing and not audio._players.land.playing, "jump toggle silences jump and landing independently")
	audio.play_sound("coin")
	await process_frame
	check(audio._players.coin.playing, "other effects remain audible when jump sound is off")
	progress.data.settings.sfx = false
	progress.settings_changed()
	progress.load_game()
	check(progress.data.settings.fps == 120 and progress.data.settings.language == "en" and not progress.data.settings.jump_sfx, "new settings survive disk reload")
	check(locale.text("Рекорд: 1 000 м") == "Best: 1 000 m", "dynamic record localization")
	check(locale.text("УРОВЕНЬ 3  ·  Скалолаз") == "LEVEL 3  ·  Cliff Climber", "dynamic rank localization")
	check(locale.text("ЗАБРАТЬ +7 МОНЕТ") == "CLAIM +7 COINS", "daily reward localization")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var cyrillic := RegEx.new()
	cyrillic.compile("[А-Яа-яЁё]")
	for panel in ["menu", "profile", "shop", "daily", "settings"]:
		if panel == "menu":
			game.ui.show_menu()
		else:
			game.ui.show_panel(panel)
		for value in texts(game.ui._content):
			check(cyrillic.search(value) == null, "English UI still has Cyrillic: " + value)
	for tab in ["sound", "graphics", "language", "creators"]:
		game.ui._settings_tab = tab
		game.ui.show_panel("settings")
		for value in texts(game.ui._content):
			check(cyrillic.search(value) == null, "English settings still has Cyrillic: " + value)
	var credits := texts(game.ui._content)
	check(credits.has("pr1de. tg:@ceoVist") and credits.has("romantic. tg:@ikdie"), "both exact credit lines are present")
	game.ui._settings_tab = "graphics"
	game.state = game.State.PANEL
	game._on_action("setting", {"key": "theme", "value": "light"})
	check(game.environment.theme == "light" and game.ui._settings_tab == "graphics", "theme changes without losing selected settings tab")
	check(game.ui.INK.get_luminance() < 0.3, "light theme has dark readable text")
	game._on_action("setting", {"key": "theme", "value": "dark"})
	check(game.ui.INK.get_luminance() > 0.7 and game.environment.theme == "dark", "dark theme applies to UI and environment")
	check(is_equal_approx(RushTuning.speed_at(0), 820), "start speed has a moderate faster baseline")
	check(is_equal_approx(RushTuning.speed_at(1000 * RushTuning.PIXELS_PER_METRE), 2200), "1000 metres has fast reaction speed")
	check(RushTuning.speed_at(300000) == 2700, "top speed remains capped")
	check(RushTuning.PLAYER_RIGHT - RushTuning.PLAYER_LEFT < 500, "corridor is narrower")
	for pair in [[0, 0], [35, 0], [40, 1], [59, 1], [60, 1], [64, 0], [80, 0], [100, 1], [120, 1], [124, 0]]:
		check(is_equal_approx(RushTuning.night_amount(pair[0]), pair[1]), "40-second day / 20-second night phase at %d" % pair[0])
	game.state = game.State.RUNNING
	game.run_time = 40.0
	game._process(0)
	check(game.environment.night_amount == 1 and game.course.night_amount == 1, "night affects background and course")
	game.state = game.State.PAUSED
	game._physics_process(0.5)
	check(game.run_time == 40, "pause freezes day/night clock")
	game.course.setup(14, "jungle")
	check(not game.course.flies.is_empty(), "wall flies spawn")
	var fly: Dictionary = game.course.flies[0]
	var side := -1 if int(fly.side) == 0 else 1
	var point := Vector2(RushTuning.PLAYER_LEFT if side < 0 else RushTuning.PLAYER_RIGHT, -float(fly.h) + 210)
	var eaten: Dictionary = game.course.take_fly(point, side)
	check(not eaten.is_empty() and game.course.take_fly(point, side).is_empty(), "wall fly is eaten only once")
	game.gecko.mode = "run"
	game.gecko.eat_to(Vector2(-10, -160))
	game.gecko._process(0.07)
	check(game.gecko.is_eating(), "tongue animation starts")
	game.gecko._process(0.20)
	check(not game.gecko.is_eating(), "tongue retracts and swallowing finishes")
	game.gecko.eat_to(Vector2(-10, -100))
	game.gecko.launch()
	check(not game.gecko.is_eating(), "eating never delays a jump")
	game.course.ensure_ahead(5000, 0)
	var before: int = game.course.maintenance_runs
	for i in range(1000):
		game.course.ensure_ahead(5000 + i * 0.1, i / 120.0)
	check(game.course.maintenance_runs - before <= 1, "no per-physics-step array maintenance")
	game.state = game.State.RUNNING
	game.run_time = 10.0
	game.height_px = 65000.0
	game.max_height_px = 65000.0
	game.jump_elapsed = -1.0
	game.camera_height = 65000.0 - 130.0
	for frame in range(240):
		game.height_px += game.current_speed() / 120.0
		game.max_height_px = game.height_px
		game.gecko.position = game.player_position()
		game._update_camera(1.0 / 120.0)
	var screen_y: float = game.world.position.y + game.gecko.position.y
	var desired_y: float = root.get_visible_rect().size.y - 650.0
	check(absf(screen_y - desired_y) < 45.0, "fast camera preserves forward visibility")
	game.ui.show_hud()
	await process_frame
	var capsule: Control = game.ui._content.get_node("HeightCapsule")
	check(capsule.get_global_rect().position.x > 326 + maxf(0.0, (root.get_visible_rect().size.x - 1080) * 0.5) and capsule.get_global_rect().end.x < 754 + maxf(0.0, (root.get_visible_rect().size.x - 1080) * 0.5), "HUD never hides either wall lane: %s viewport=%s" % [capsule.get_global_rect(), root.get_visible_rect()])
	game.queue_free()
	audio.set_music_enabled(false)
	audio.set_sfx_enabled(false)
	await process_frame
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_file + suffix))
	print("V2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
