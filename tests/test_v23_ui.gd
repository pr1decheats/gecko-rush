extends SceneTree
## Compact biome selectors and portrait layout in the original two locales.
## Optional native captures: -- --capture /absolute/output/path
var checks := 0
var failures := 0
var game: Node
var p: Node
var ui: Node
var locale: Node
var capture_directory := ""

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _labels(node: Node) -> Array[Label]:
	var result: Array[Label] = []
	if node is Label:
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_labels(child))
	return result

func _scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child: Node in node.get_children():
		var found := _scroll(child)
		if found != null:
			return found
	return null

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _capture(name_value: String) -> void:
	if capture_directory.is_empty():
		return
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty(), "native capture has pixels: " + name_value)
	if not image.is_empty():
		check(image.save_png(capture_directory.path_join(name_value + ".png")) == OK, "saved native capture: " + name_value)

func _fresh(level: int = 1, best_metres: float = 0.0) -> void:
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.data.xp = p.xp_for_level(level)
	p.data.world_stats["jungle"] = {"best_height": best_metres}
	if level >= 50:
		for world: Dictionary in p.WORLDS:
			p.data.unlocked_worlds.append(str(world.id))

func _run() -> void:
	p = root.get_node("Progress")
	locale = root.get_node("L10n")
	p.save_file = "user://v23_ui_regression.json"
	_fresh()
	root.get_node("Audio").set_music_enabled(false)
	root.get_node("Audio").set_sfx_enabled(false)
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
	var cyrillic := RegEx.new()
	cyrillic.compile("[А-Яа-яЁё]")
	for language: String in ["ru", "en"]:
		locale.set_language(language)
		for scenario: String in ["new", "practice", "veteran"]:
			_fresh(1 if scenario == "new" else (5 if scenario == "practice" else 50), 225.0 if scenario == "practice" else 0.0)
			ui.show_menu()
			await _settle()
			var cards: Node = ui._content.find_child("RunDistanceCards", true, false)
			check(cards != null and cards.get_child_count() == 3, language + " " + scenario + ": three distance cards remain")
			var actions: Control = ui._content.find_child("MenuActions", true, false)
			check(cards.get_global_rect().end.y + 20.0 < actions.get_global_rect().position.y, language + " " + scenario + ": summary clears play/navigation buttons")
			var world_button: Button = ui._content.find_child("MenuWorld", true, false)
			check(world_button.text.begins_with(locale.text(str(p.current_world().get("world_name", p.current_world().theme_name))).to_upper()), language + ": biome is the primary menu name")
			var summary: Node = ui._content.find_child("MenuWorldInfo", true, false)
			check(summary == null, language + " " + scenario + ": menu XP/requirements component is absent")
			for label: Label in _labels(ui._content):
				check(not label.text.contains("XP"), language + ": menu contains no XP text")
			await _capture("menu_" + language + "_" + scenario)
			ui.show_panel("profile")
			await _settle()
			for world: Dictionary in p.WORLDS:
				var card: Control = ui._content.find_child("World_" + str(world.id), true, false)
				check(card != null, "selector includes " + str(world.id))
				var button: Button = card.find_child("Select_" + str(world.id), true, false)
				check(button.disabled == not p.is_world_unlocked(str(world.id)), "selector reflects unlock status: " + str(world.id))
				check(_labels(card).size() == 2, "selector contains only world and difficulty labels: " + str(world.id))
				check(card.find_child("WorldTitle", true, false).text == locale.text(str(world.get("world_name", world.theme_name))), "selector title names the biome: " + str(world.id))
				check(card.find_child("WorldDifficulty", true, false).text == locale.text(str(world.name)), "selector shows difficulty as secondary label: " + str(world.id))
				for label: Label in _labels(card):
					check(label.get_global_rect().end.x <= card.get_global_rect().end.x + 1.0, "wrapped card label stays within width: " + label.text)
					check(label.get_global_rect().end.y <= card.get_global_rect().end.y + 1.0, "wrapped card label stays within height: " + label.text)
					if language == "en":
						check(cyrillic.search(label.text) == null, "English selector label fully translated: " + label.text)
			if scenario == "practice":
				_scroll(ui._content).scroll_vertical = 780
				await _settle()
				await _capture("profile_" + language + "_difficulty")
	game.queue_free()
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.save_file + suffix))
	print("V23 UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
