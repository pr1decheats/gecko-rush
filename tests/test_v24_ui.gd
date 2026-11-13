extends SceneTree
## v2.4: biome titles, compact world cards and three language controls.
## Native captures: -- --capture /absolute/output/path
var checks := 0
var failures := 0
var p: Node
var locale: Node
var game: Node
var ui: Node
var capture_directory := ""

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	if node is Label:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_labels(child))
	return found

func _buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	if node is Button:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_buttons(child))
	return found

func _has_progress_bar(node: Node) -> bool:
	if node is ProgressBar:
		return true
	for child: Node in node.get_children():
		if _has_progress_bar(child):
			return true
	return false

func _scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child: Node in node.get_children():
		var found := _scroll(child)
		if found != null:
			return found
	return null

func _fresh(language: String, unlock_all: bool = false) -> void:
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.data.settings.language = language
	if unlock_all:
		p.data.xp = p.xp_for_level(50)
		for world: Dictionary in p.WORLDS:
			if not str(world.id) in p.data.unlocked_worlds:
				p.data.unlocked_worlds.append(str(world.id))
	p.settings_changed()
	check(locale.language == language, "settings apply locale " + language)

func _world_title(world: Dictionary) -> String:
	return locale.text(str(world.world_name))

func _check_menu(language: String) -> void:
	var title: Button = ui._content.find_child("MenuWorld", true, false)
	check(title != null and title.text == _world_title(p.current_world()).to_upper() + "   ›", language + ": menu names the current biome")
	check(ui._content.find_child("MenuWorldInfo", true, false) == null, language + ": XP block was removed entirely")
	check(ui._content.find_child("MenuDifficulty", true, false) == null, language + ": old difficulty-only title is gone")
	check(not _has_progress_bar(ui._content), language + ": menu has no progression panel")
	for label: Label in _labels(ui._content):
		check(not label.text.contains("XP") and not label.text.contains("×"), language + ": menu contains no XP/multiplier explanation")
	var cards: HBoxContainer = ui._content.find_child("RunDistanceCards", true, false)
	var actions: Control = ui._content.find_child("MenuActions", true, false)
	check(cards != null and cards.get_child_count() == 3, language + ": all three distance cards remain")
	check(title.get_global_rect().end.y + 5.0 < cards.get_global_rect().position.y, language + ": world title clears distance cards")
	check(cards.get_global_rect().end.y + 20.0 < actions.get_global_rect().position.y, language + ": distance cards clear play/navigation controls")
	for card: Control in cards.get_children():
		check(absf(card.size.x - card.size.y) < 1.0, language + ": distance card remains square")

func _check_world_cards(language: String) -> void:
	for world: Dictionary in p.WORLDS:
		var id := str(world.id)
		var card: Control = ui._content.find_child("World_" + id, true, false)
		check(card != null, language + ": selector includes biome " + id)
		var labels := _labels(card)
		var buttons := _buttons(card)
		check(labels.size() == 2 and buttons.size() == 1, language + ": world card has only biome, difficulty and status/control: " + id)
		check(card.find_child("WorldTitle", true, false).text == _world_title(world), language + ": biome is primary: " + id)
		check(card.find_child("WorldDifficulty", true, false).text == locale.text(str(world.name)), language + ": difficulty is secondary: " + id)
		check(not _has_progress_bar(card), language + ": world card has no unlock progress panel: " + id)
		var unlocked: bool = p.is_world_unlocked(id)
		var selected := str(p.data.selected_world) == id
		check(buttons[0].disabled == not unlocked, language + ": compact card still respects the backend gate: " + id)
		check(buttons[0].text == locale.text("ВЫБРАН" if selected else ("ВЫБРАТЬ" if unlocked else "ЗАКРЫТО")), language + ": selection/locked status stays concise: " + id)
		check(card.size.y <= 270.0, language + ": world card stays compact in portrait: " + id)
		for label: Label in labels:
			check(not label.text.contains("XP") and not label.text.contains("×"), language + ": no XP/pace/requirement text in world card: " + id)
			check(label.get_global_rect().end.x <= card.get_global_rect().end.x + 1.0 and label.get_global_rect().end.y <= card.get_global_rect().end.y + 1.0, language + ": wrapped title/difficulty stays in card: " + id)
		check(buttons[0].get_global_rect().position.y > labels[-1].get_global_rect().end.y, language + ": wrapped title never covers select control: " + id)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _capture(filename: String) -> void:
	if capture_directory.is_empty():
		return
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty(), "native capture has pixels: " + filename)
	if not image.is_empty():
		check(image.save_png(capture_directory.path_join(filename + ".png")) == OK, "native capture saved: " + filename)

func _run() -> void:
	p = root.get_node("Progress")
	locale = root.get_node("L10n")
	p.save_file = "user://v24_ui_regression.json"
	_fresh("ru")
	root.size = Vector2i(540, 960)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--capture":
		capture_directory = args[1]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _settle()
	game.set_process(false)
	game.set_physics_process(false)
	ui = game.ui
	for language: String in ["ru", "en", "uk"]:
		_fresh(language)
		game._show_menu()
		await _settle()
		_check_menu(language)
		await _capture("menu_" + language + "_new")
		game._on_action("profile")
		await _settle()
		_check_world_cards(language)
		_scroll(ui._content).scroll_vertical = 650
		await _settle()
		await _capture("profile_" + language + "_worlds")

		_fresh(language, true)
		game._show_menu()
		for world: Dictionary in p.WORLDS:
			game._on_action("profile")
			await _settle()
			var select: Button = ui._content.find_child("Select_" + str(world.id), true, false)
			select.pressed.emit()
			await _settle()
			check(str(p.data.selected_world) == str(world.id) and game.environment.world_id == str(world.id), language + ": real select control updates current world: " + str(world.id))
			_check_world_cards(language)
			game._on_action("menu")
			await _settle()
			_check_menu(language)
			if str(world.id) == "crystal":
				await _capture("menu_" + language + "_crystal")

		# Saved-run world can differ from the selected menu world. Returning to
		# the menu must always show the current selection rather than an old label.
		p.select_world("ice")
		game._start_run(true)
		game._process(game.transition_duration)
		game._pause_run()
		game._show_menu()
		game._on_action("world", "volcano")
		game._restore_run()
		check(game.state == game.State.PAUSED and game.world_id == "ice", language + ": resume restores its saved biome")
		game._on_action("menu")
		await _settle()
		_check_menu(language)
		game._on_action("retry")
		game._process(game.transition_duration)
		check(game.world_id == "volcano", language + ": retry uses current selected biome")
		game._pause_run()
		game._on_action("menu")
		await _settle()
		_check_menu(language)

		game._on_action("settings")
		ui._settings_tab = "language"
		ui.show_panel("settings")
		await _settle()
		for code: String in ["ru", "en", "uk"]:
			var button: Button = ui._content.find_child("Language_" + code, true, false)
			check(button != null and not button.disabled and button.size.y == 112.0, language + ": language control remains available and compact: " + code)
		check(ui._content.find_child("Language_uk", true, false).text == "Українська", language + ": Ukrainian option preserves its autonym")
		await _capture("settings_" + language + "_languages")
		ui._content.find_child("Language_uk", true, false).pressed.emit()
		await _settle()
		check(locale.language == "uk" and p.data.settings.language == "uk", language + ": Ukrainian language control applies immediately")
		p.load_game()
		check(locale.language == "uk" and p.data.settings.language == "uk", language + ": Ukrainian setting survives disk reload")
		ui._settings_tab = "graphics"
		ui.show_panel("settings")
		await _settle()
		var graphic_text: Array[String] = []
		for button: Button in _buttons(ui._content):
			graphic_text.append(button.text)
		check(graphic_text.has(locale.text("60 Гц")) and graphic_text.has(locale.text("120 Гц")) and graphic_text.has(locale.text("Тёмная")) and graphic_text.has(locale.text("Светлая")), language + ": frame-rate and appearance controls remain")
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.save_file + suffix))
	print("V24 UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
