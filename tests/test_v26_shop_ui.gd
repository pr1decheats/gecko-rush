extends SceneTree
## Actual shop purchase/equip controls, translated unlock labels and desktop240.
## Optional native captures: -- --capture /absolute/path
var checks := 0
var failures := 0
var p: Node
var locale: Node
var ui: Node
var capture_directory := ""
var appearances: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Label or node is Button:
		result.append(node.text)
	for child: Node in node.get_children():
		result.append_array(texts(child))
	return result

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func scroll_under(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child: Node in node.get_children():
		var found := scroll_under(child)
		if found != null:
			return found
	return null

func scroll_to(name_value: String) -> void:
	var target: Control = ui._content.find_child(name_value, true, false)
	var scroll := scroll_under(ui._content)
	check(target != null and scroll != null, "Scroll target exists: " + name_value)
	if target != null and scroll != null:
		scroll.scroll_vertical += roundi(target.get_global_rect().position.y - scroll.get_global_rect().position.y)
		await settle()

func capture(name_value: String) -> void:
	if capture_directory.is_empty():
		return
	await create_timer(0.18).timeout
	await RenderingServer.frame_post_draw
	# Native captures must use the detailed texture rig, not the old fallback.
	for preview: Control in ui._content.find_children("Preview_*", "Control", true, false):
		if preview.gecko.is_processing():
			check(preview.gecko._detailed_active, "Visible shop preview uses detailed art: " + str(preview.gecko.skin_id))
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png(capture_directory.path_join(name_value + ".png")) == OK, "Capture " + name_value)

func fresh(language: String, coins: int = 20000) -> void:
	p.data = p._defaults()
	p.data.settings.music = false
	p.data.settings.sfx = false
	p.data.settings.language = language
	p.data.coins = coins
	p.settings_changed()

func _run() -> void:
	await process_frame
	p = root.get_node("Progress")
	locale = root.get_node("L10n")
	p.save_file = "user://v26_shop_ui.json"
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--capture":
		capture_directory = args[1]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	root.size = Vector2i(540, 960)
	fresh("ru")
	ui = load("res://scripts/ui.gd").new()
	root.add_child(ui)
	ui.action.connect(func(name_value: String, payload: Variant) -> void:
		if name_value == "appearance":
			appearances.append(str(payload)))
	await settle()
	for language: String in ["ru", "en", "uk"]:
		fresh(language)
		ui.show_panel("shop")
		await settle()
		var all_text := "\n".join(texts(ui._content))
		check(not all_text.contains("Скоро здесь") and not all_text.contains("coming soon"), language + ": real shop replaces placeholder")
		for rarity: Dictionary in ui.SKIN_RARITIES:
			var heading: Label = ui._content.find_child("Rarity_" + str(rarity.id), true, false)
			check(heading != null and heading.text == locale.text(str(rarity.name)), language + ": translated rarity " + str(rarity.id))
		for skin: Dictionary in p.SKINS:
			var id := str(skin.id)
			var card: Control = ui._content.find_child("Skin_" + id, true, false)
			check(card != null, language + ": catalogue contains " + id)
			if card == null:
				continue
			var title: Label = card.find_child("SkinTitle", true, false)
			check(title.text == locale.text(str(skin.name)), language + ": skin name translated " + id)
			var preview: Control = card.find_child("Preview_" + id, true, false)
			check(preview != null and preview.gecko.skin_id == id, language + ": card previews the actual outfit " + id)
			var buy: Button = card.find_child("SkinAction_" + id, true, false)
			check(buy.disabled == (id == "standard_green"), language + ": exact affordability and selected status " + id)
			check(buy.get_global_rect().size.y >= 90, language + ": skin control is comfortably tall " + id)
		await scroll_to("Rarity_common")
		await capture("shop_" + language + "_common")
		var first_preview: Control = ui._content.find_child("Preview_standard_green", true, false)
		var scroll := scroll_under(ui._content)
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await settle()
		check(not first_preview.gecko.is_processing(), language + ": offscreen previews stop animating")
		var last_preview: Control = ui._content.find_child("Preview_rainbow_spark", true, false)
		check(last_preview.gecko.is_processing(), language + ": newly visible outfit animates")
		await capture("shop_" + language + "_mythic")
		# Purchase every requested rarity through actual buttons, not backend shortcuts.
		for id: String in ["desert_wanderer", "neon_pulse", "steel_knight", "royal_pearl", "rainbow_spark"]:
			var before: int = int(p.data.coins)
			var price: int = int(p.get_skin(id).price)
			var buy: Button = ui._content.find_child("SkinAction_" + id, true, false)
			buy.pressed.emit()
			await settle()
			check(p.owns_skin(id) and p.data.skin_id == id, language + ": real buy equips " + id)
			check(int(p.data.coins) == before - price, language + ": exact rarity price charged " + id)
			check(appearances.back() == id, language + ": main receives appearance change " + id)
			var selected: Button = ui._content.find_child("SkinAction_" + id, true, false)
			check(selected.disabled and selected.text == locale.text("ВЫБРАН"), language + ": purchased outfit becomes selected " + id)
		var before_equip: int = int(p.data.coins)
		ui._content.find_child("SkinAction_desert_wanderer", true, false).pressed.emit()
		await settle()
		check(p.data.skin_id == "desert_wanderer" and int(p.data.coins) == before_equip, language + ": equipping owned outfit costs nothing")
		ui._dispatch_action("skin_buy", "desert_wanderer")
		check(int(p.data.coins) == before_equip, language + ": duplicate queued buy does not charge twice")
		fresh(language, 149)
		ui.show_panel("shop")
		await settle()
		var blocked: Button = ui._content.find_child("SkinAction_desert_wanderer", true, false)
		check(blocked.disabled and blocked.tooltip_text == locale.text("Недостаточно монет"), language + ": insufficient balance is clear")
		ui.show_panel("profile")
		await settle()
		for world: Dictionary in p.WORLDS:
			var card: Control = ui._content.find_child("World_" + str(world.id), true, false)
			var level: Label = card.find_child("WorldUnlockLevel", true, false)
			check(level != null and level.text == locale.format_text("С уровня %d", [int(world.unlock)]), language + ": unlock level shown " + str(world.id))
			var requirement: Label = card.find_child("WorldUnlockRecord", true, false)
			check((requirement != null) == not p.is_world_unlocked(str(world.id)), language + ": locked record gate is explained " + str(world.id))
		await scroll_to("World_jungle")
		await capture("worlds_" + language)
		ui._settings_tab = "graphics"
		ui.show_panel("settings")
		await settle()
		for rate: int in p.available_fps():
			var control: Button = ui._content.find_child("FPS_" + str(rate), true, false)
			check(control != null and control.text == locale.format_text("%d FPS", [rate]), language + ": rate available " + str(rate))
		await capture("graphics_" + language)
	# Landscape PC layout uses four columns; narrow mobile keeps readable two-column cards.
	for size_value in [Vector2i(1280, 720), Vector2i(360, 800)]:
		root.size = size_value
		fresh("ru")
		ui.show_panel("shop")
		await settle()
		await scroll_to("Rarity_epic")
		await capture("shop_" + str(size_value.x) + "x" + str(size_value.y))
		ui.show_panel("profile")
		await settle()
		await scroll_to("World_jungle")
		await capture("worlds_" + str(size_value.x) + "x" + str(size_value.y))
	ui.queue_free()
	await process_frame
	await process_frame
	print("V26 SHOP UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
