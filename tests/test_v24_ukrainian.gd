extends SceneTree
## Complete Ukrainian coverage, dynamic strings, live UI and isolated persistence.
var checks := 0
var failures := 0
var locale: Node
var progress: Node
var ui: Node

# These are spelled identically in Russian/Ukrainian, or are language autonyms/units.
const IDENTICAL: Array[String] = [
	"Кошмар", "Небо", "Темп: %s → %s м/с", "Пауза", "ГОТОВО", "Рекорд:",
	"Вулкан", "Звук", "English", "ДЕНЬ", "60 Гц", "120 Гц", "Українська",
	"Рекорд: %s м", "%s м", "%d Гц"
]
const WORLD_NAMES: Array[String] = ["Джунглі", "Каньйон", "Крижані скелі", "Кришталеві печери", "Вулкан", "Небесні острови"]
const DIFFICULTIES: Array[String] = ["Легкий", "Звичайний", "Складний", "Експерт", "Кошмар", "Безумство"]
const CREDITS: Array[String] = ["pr1de. tg:@ceoVist", "romantic. tg:@ikdie"]

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Label or node is Button:
		result.append(node.text)
	if node is Control and not node.tooltip_text.is_empty():
		result.append(node.tooltip_text)
	for child: Node in node.get_children():
		result.append_array(_texts(child))
	return result

func _check_ukrainian_screen(screen: String) -> void:
	var russian_only := RegEx.new()
	russian_only.compile("[ыэъёЫЭЪЁ]")
	var latin := RegEx.new()
	latin.compile("[A-Za-z]{2,}")
	for value: String in _texts(ui._content):
		check(russian_only.search(value) == null, screen + ": no Russian-only letters: " + value)
		if value in CREDITS:
			continue
		for word: RegExMatch in latin.search_all(value):
			check(word.get_string() in ["GECKO", "RUSH", "English", "XP", "FPS", "Esc"], screen + ": no English fallback: " + value)
		for source: String in locale.UK:
			if source != str(locale.UK[source]) and source.length() >= 4:
				check(not value.contains(source), screen + ": no untranslated known Russian label: " + source)

func _check_dictionary() -> void:
	check(locale.UK.size() == locale.EN.size() and locale.UK.size() >= 174, "Ukrainian covers every English source key")
	var forbidden := RegEx.new()
	forbidden.compile("[ыэъёЫЭЪЁ]")
	var placeholders := RegEx.new()
	placeholders.compile("%[sdf]")
	var latin := RegEx.new()
	latin.compile("[A-Za-z]{2,}")
	for source: String in locale.EN:
		check(locale.UK.has(source), "Ukrainian dictionary contains: " + source)
		if not locale.UK.has(source):
			continue
		var translated: String = locale.text(source)
		check(not translated.is_empty() and translated == str(locale.UK[source]), "known key uses Ukrainian dictionary: " + source)
		check(forbidden.search(translated) == null, "Ukrainian key has no Russian-only letters: " + source)
		for word: RegExMatch in latin.search_all(translated):
			check(word.get_string() in ["English", "XP", "FPS", "Esc"], "Ukrainian dictionary has no English fallback: " + source)
		check(translated != source or source in IDENTICAL, "known key does not fall back to Russian: " + source)
		check(placeholders.search_all(source).size() == placeholders.search_all(translated).size(), "template retains its substitutions: " + source)
		if source.contains("%"):
			for number in [0, 7, 1024, 98765]:
				var values: Array = []
				for placeholder: RegExMatch in placeholders.search_all(source):
					values.append(str(number) if placeholder.get_string() == "%s" else number)
				var formatted: String = locale.format_text(source, values)
				check(not formatted.contains("%") and formatted.contains(str(number)), "template supports changing numeric values: " + source)
				check(forbidden.search(formatted) == null, "formatted template stays Ukrainian: " + source)

func _check_dynamic() -> void:
	var examples: Dictionary = {
		"УРОВЕНЬ 3  ·  Скалолаз": "РІВЕНЬ 3  ·  Скелелаз",
		"УР. 25  ·  ПОКОРИТЕЛЬ ВЫСОТ": "РІВ. 25  ·  ПІДКОРЮВАЧ ВИСОТ",
		"125 / 400 XP до следующего уровня": "125 / 400 XP до наступного рівня",
		"Сейчас: Каньон": "Зараз: Каньйон",
		"ДОСТИЖЕНИЯ   4 / 10": "ДОСЯГНЕННЯ   4 / 10",
		"Откроется на 25 уровне": "Відкриється на 25-му рівні",
		"Рекорд: 1 000 м": "Рекорд: 1 000 м",
		"Новое достижение: Первый прыжок": "Нове досягнення: Перший стрибок",
		"Мир «Сложный»": "Світ «Складний»",
		"Звание «Небесный дракон»": "Звання «Небесний дракон»"
	}
	for source: String in examples:
		check(locale.text(source) == examples[source], "legacy dynamic label: " + source)
	var coin_words := {0: "МОНЕТ", 1: "МОНЕТУ", 2: "МОНЕТИ", 3: "МОНЕТИ", 4: "МОНЕТИ", 5: "МОНЕТ", 11: "МОНЕТ", 14: "МОНЕТ", 21: "МОНЕТУ", 22: "МОНЕТИ", 25: "МОНЕТ", 101: "МОНЕТУ", 111: "МОНЕТ"}
	for amount: int in coin_words:
		var expected := "ЗАБРАТИ +%d %s" % [amount, coin_words[amount]]
		check(locale.text("ЗАБРАТЬ +%d МОНЕТ" % amount) == expected, "legacy reward uses Ukrainian number agreement: " + str(amount))
		check(locale.format_text("ЗАБРАТЬ +%d МОНЕТ", [amount]) == expected, "formatted reward uses Ukrainian number agreement: " + str(amount))
	for number in [0, 12, 1200, 250000]:
		check(locale.text("%s м" % number) == "%s м" % number, "Ukrainian metre abbreviation remains Cyrillic")
		check(locale.format_text("XP ×%s · до уровня %d", ["1,35", number]) == "XP ×1,35 · до рівня %d" % number, "XP template preserves decimal and level")
		check(locale.format_text("Рекорд мира «%s»: %s / %s м", [locale.text("Каньон"), str(number), "1100"]) == "Рекорд світу «Каньйон»: %s / 1100 м" % number, "world template translates name and preserves numeric values")

func _run() -> void:
	await process_frame
	locale = root.get_node("L10n")
	progress = root.get_node("Progress")
	var audio: Node = root.get_node("Audio")
	audio.set_music_enabled(false)
	audio.set_sfx_enabled(false)
	progress.save_file = "user://v24_ukrainian_test.json"
	progress.data = progress._defaults()
	progress.data.settings.music = false
	progress.data.settings.sfx = false
	progress.data.settings.language = "uk"
	progress.settings_changed()
	check(locale.language == "uk", "Ukrainian setting applies immediately")
	check(progress._sanitize({"settings": {"language": "uk"}}).settings.language == "uk", "sanitizer accepts Ukrainian")
	progress.load_game()
	check(progress.data.settings.language == "uk" and locale.language == "uk", "Ukrainian persists through real disk save/reload")
	_check_dictionary()
	_check_dynamic()
	for path in ["res://assets/fonts/OpenSans-Regular.ttf", "res://assets/fonts/OpenSans-Bold.ttf"]:
		var font: Font = load(path)
		for letter: String in "ҐґЄєІіЇї’":
			check(font.has_char(letter.unicode_at(0)), "bundled font supports Ukrainian character " + letter)
	for index in range(progress.WORLDS.size()):
		var world: Dictionary = progress.WORLDS[index]
		check(locale.text(str(world.world_name)) == WORLD_NAMES[index], "full Ukrainian biome name: " + str(world.id))
		check(locale.text(str(world.name)) == DIFFICULTIES[index], "Ukrainian difficulty name: " + str(world.id))
	for item: Dictionary in progress.ACHIEVEMENTS:
		for field in ["name", "title", "description"]:
			check(locale.UK.has(item[field]) and locale.text(item[field]) != item[field], "achievement translates: " + str(item[field]))
	for item: Dictionary in progress.DAILY_DEFINITIONS:
		check(locale.UK.has(item.title) and locale.text(item.title) != item.title, "quest translates: " + str(item.title))
	for item: Dictionary in progress.MILESTONES:
		check(locale.text(item.name) != item.name, "milestone translates: " + str(item.name))
	# Real UI construction checks labels, status badges, tooltips and runtime values.
	ui = load("res://scripts/ui.gd").new()
	root.add_child(ui)
	await process_frame
	ui.show_menu()
	_check_ukrainian_screen("menu")
	var menu := _texts(ui._content)
	for expected in ["ГРАТИ", "КРАМНИЦЯ", "ПРОФІЛЬ", "ЗАВДАННЯ"]:
		check(expected in menu, "menu contains Ukrainian action: " + expected)
	for panel in ["profile", "shop", "daily"]:
		ui.show_panel(panel)
		_check_ukrainian_screen(panel)
	progress.data.daily.jumps = 30
	progress.data.daily.coins = 20
	progress.data.daily.height = 300
	ui.show_panel("daily")
	var daily := _texts(ui._content)
	for expected in ["ЗАБРАТИ +3 МОНЕТИ", "ЗАБРАТИ +5 МОНЕТ", "ЗАБРАТИ +7 МОНЕТ"]:
		check(expected in daily, "completed daily reward is localized: " + expected)
	for tab in ["sound", "graphics", "language", "creators"]:
		ui._settings_tab = tab
		ui.show_panel("settings")
		_check_ukrainian_screen("settings " + tab)
		if tab == "language":
			var languages := _texts(ui._content)
			check("Російська" in languages and "English" in languages and "Українська" in languages, "all language choices remain recognizable")
		if tab == "creators":
			var credits := _texts(ui._content)
			check(CREDITS[0] in credits and CREDITS[1] in credits, "creator nicknames and Telegram handles remain exact")
	ui.show_pause()
	_check_ukrainian_screen("pause")
	check("ПЕРЕПОЧИНОК" in _texts(ui._content), "pause heading is Ukrainian")
	ui.show_results({"height": 1234, "xp": 34, "reward_coins": 7, "new_best": true, "old_level": 1, "level": 3, "new_achievements": ["first_jump"]})
	_check_ukrainian_screen("results")
	check("Нове досягнення: Перший стрибок" in _texts(ui._content), "result achievement dynamic is fully translated")
	ui.show_hud()
	ui.update_cycle(true, 18.2)
	check(ui._cycle_label.text == "НІЧ · 19 с", "night label and seconds are Ukrainian")
	ui.update_cycle(false, 39.0)
	check(ui._cycle_label.text == "ДЕНЬ · 39 с", "day label remains correct")
	_check_ukrainian_screen("HUD/help")
	# Switching locales clears dynamic caches without changing existing EN/RU behavior.
	locale.set_language("en")
	check(locale.text("УРОВЕНЬ 3  ·  Скалолаз") == "LEVEL 3  ·  Cliff Climber", "English rank remains unchanged")
	check(locale.text("ЗАБРАТЬ +7 МОНЕТ") == "CLAIM +7 COINS", "English reward remains unchanged")
	check(locale.text("Рекорд: 1 000 м") == "Best: 1 000 m", "English units remain unchanged")
	locale.set_language("ru")
	check(locale.text("ЗАБРАТЬ +7 МОНЕТ") == "ЗАБРАТЬ +7 МОНЕТ", "Russian stays a literal passthrough")
	locale.set_language("uk")
	check(locale.text("ЗАБРАТЬ +7 МОНЕТ") == "ЗАБРАТИ +7 МОНЕТ", "switching back never reuses English cached output")
	locale.set_language("invalid")
	check(locale.language == "ru", "unknown language still falls back to Russian")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_file + suffix))
	ui.queue_free()
	await process_frame
	await process_frame
	print("V24_UKRAINIAN_%s: %d checks, %d failures" % ["OK" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
