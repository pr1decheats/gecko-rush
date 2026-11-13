class_name RushUI
extends CanvasLayer
## A responsive, entirely custom mobile interface. Gameplay remains visible
## through the menu and HUD; all input leaves through the action signal.

signal action(name: String, payload: Variant)

var CREAM := Color("fff6db")
var PAPER := Color("fffaf0")
var INK := Color("153d33")
var MUTED := Color("688373")
var LIME := Color("c9ed7a")
var GOLD := Color("f4c66c")
var LINE := Color("d9e3c8")

var _root: Control
var _content: Control
var _toast_root: Control
var _toast_tween: Tween
var _fade_tween: Tween
var _font: Font
var _bold: Font
var _screen := ""
var _settings_tab := "sound"
var _cycle_label: Label
var _result: Dictionary = {}
var _height_label: Label
var _record_label: Label
var _coins_label: Label
var _hint: Control
var _hud_height := 0.0
var _hud_coins := 0
var _hint_visible := true
var _safe_top := 64.0
var _safe_bottom := 50.0


class CoinArt extends Control:

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		draw_circle(c + Vector2(0, r * 0.12), r, Color("bd8a37"))
		draw_circle(c, r, Color("f4c66c"))
		draw_arc(c, r * 0.71, 0, TAU, 32, Color("dca344"), r * 0.12, true)
		var stamp := Color("836329")
		draw_rect(Rect2(c + Vector2(-r * 0.12, -r * 0.24), Vector2(r * 0.24, r * 0.48)), stamp)
		draw_rect(Rect2(c + Vector2(-r * 0.20, -r * 0.43), Vector2(r * 0.4, r * 0.25)), stamp)
		for side in [-1.0, 1.0]:
			for y in [-0.13, 0.12]:
				draw_line(c + Vector2(0, r * y), c + Vector2(side * r * 0.36, r * (y - 0.12)), stamp, r * 0.09, false)
		draw_line(c + Vector2(0, r * 0.20), c + Vector2(r * 0.23, r * 0.44), stamp, r * 0.09, false)
		draw_arc(c + Vector2(-r * 0.12, -r * 0.12), r * 0.63, PI * 1.1, PI * 1.7, 12, Color("fff2bc"), r * 0.09, true)


class ChestArt extends Control:

	func _draw() -> void:
		var s := minf(size.x / 500.0, size.y / 360.0)
		var origin := Vector2(size.x * 0.5, size.y * 0.5)
		draw_set_transform(origin, 0.0, Vector2(s, s))
		draw_circle(Vector2(0, 0), 155, Color("edf0d1"))
		draw_circle(Vector2(-95, -80), 22, Color("dfebbd"))
		draw_circle(Vector2(135, 25), 16, Color("dfebbd"))
		draw_ellipse_shadow()
		var lid := PackedVector2Array([Vector2(-138, -18), Vector2(-138, -67), Vector2(-111, -109), Vector2(-66, -132), Vector2(66, -132), Vector2(111, -109), Vector2(138, -67), Vector2(138, -18)])
		draw_colored_polygon(lid, Color("b88949"))
		draw_polyline(PackedVector2Array([Vector2(-133, -25), Vector2(-133, -65), Vector2(-108, -103), Vector2(-63, -125), Vector2(63, -125), Vector2(108, -103), Vector2(133, -65), Vector2(133, -25)]), Color("e3b65f"), 14, true)
		draw_rect(Rect2(-138, -25, 276, 131), Color("8b653c"))
		draw_rect(Rect2(-123, -6, 246, 95), Color("ac8248"))
		draw_line(Vector2(-119, 35), Vector2(119, 35), Color("98703e"), 5, true)
		draw_line(Vector2(-119, 70), Vector2(119, 70), Color("98703e"), 5, true)
		draw_rect(Rect2(-143, -31, 286, 20), Color("efc473"))
		draw_rect(Rect2(-143, 91, 286, 17), Color("efc473"))
		for x in [-99.0, 78.0]:
			draw_rect(Rect2(x, -109, 21, 210), Color("efc473"))
			for y in [-19.0, 76.0]:
				draw_circle(Vector2(x + 10, y), 4, Color("b88949"))
		draw_rect(Rect2(-29, -40, 58, 79), Color("ffe0a1"))
		draw_circle(Vector2(0, -2), 11, Color("345c45"))
		draw_colored_polygon(PackedVector2Array([Vector2(-5, 1), Vector2(-9, 22), Vector2(9, 22), Vector2(5, 1)]), Color("345c45"))
		for p in [Vector2(-180, -82), Vector2(174, -100), Vector2(160, 94)]:
			draw_line(p - Vector2(0, 11), p + Vector2(0, 11), Color("d4b76b"), 3, true)
			draw_line(p - Vector2(11, 0), p + Vector2(11, 0), Color("d4b76b"), 3, true)
		draw_set_transform(Vector2.ZERO)

	func draw_ellipse_shadow() -> void:
		draw_set_transform(Vector2(size.x * 0.5, size.y * 0.5 + 119.0 * minf(size.x / 500.0, size.y / 360.0)), 0, Vector2(minf(size.x / 500.0, size.y / 360.0), minf(size.x / 500.0, size.y / 360.0) * 0.20))
		draw_circle(Vector2.ZERO, 150, Color(0.08, 0.24, 0.17, 0.12))
		var s := minf(size.x / 500.0, size.y / 360.0)
		draw_set_transform(Vector2(size.x * 0.5, size.y * 0.5), 0, Vector2(s, s))


class WorldArt extends Control:
	var world_id := "jungle"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.44
		var colors := {"jungle": Color("648b4c"), "canyon": Color("c38151"), "ice": Color("86bdcd"), "crystal": Color("6474ac"), "volcano": Color("bb7351"), "sky": Color("8dbdc5")}
		var color: Color = colors.get(world_id, Color("648b4c"))
		draw_circle(c, r, color.lightened(0.68))
		if world_id == "jungle":
			for i in range(3):
				var p := c + Vector2((i - 1) * r * 0.42, r * 0.23)
				draw_line(p, p - Vector2(0, r * 0.55), color.darkened(0.15), 4, true)
				draw_colored_polygon(PackedVector2Array([p - Vector2(0, r), p + Vector2(r * 0.35, -r * 0.21), p + Vector2(-r * 0.35, -r * 0.21)]), color)
		elif world_id == "crystal" or world_id == "ice":
			for i in range(3):
				var p := c + Vector2((i - 1) * r * 0.48, r * 0.5)
				var h := r * (1.3 if i == 1 else 0.9)
				draw_colored_polygon(PackedVector2Array([p - Vector2(r * 0.22, 0), p - Vector2(r * 0.28, h * 0.65), p - Vector2(0, h), p + Vector2(r * 0.28, -h * 0.65), p + Vector2(r * 0.22, 0)]), color)
				draw_line(p - Vector2(0, h), p, color.lightened(0.35), 3, true)
		elif world_id == "sky":
			draw_circle(c + Vector2(-r * 0.4, 0), r * 0.36, Color("fffaf0"))
			draw_circle(c + Vector2(0, -r * 0.16), r * 0.48, Color("fffaf0"))
			draw_circle(c + Vector2(r * 0.4, 0), r * 0.33, Color("fffaf0"))
			draw_rect(Rect2(c + Vector2(-r * 0.42, 0), Vector2(r * 0.84, r * 0.27)), Color("fffaf0"))
		else:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.77, r * 0.5), c + Vector2(-r * 0.28, -r * 0.72), c + Vector2(r * 0.08, -r * 0.15), c + Vector2(r * 0.44, -r * 0.58), c + Vector2(r * 0.82, r * 0.5)]), color)
			if world_id == "volcano":
				draw_line(c + Vector2(-r * 0.28, -r * 0.72), c + Vector2(-r * 0.12, r * 0.2), Color("ffcc79"), r * 0.14, true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_font = load("res://assets/fonts/OpenSans-Regular.ttf") if ResourceLoader.exists("res://assets/fonts/OpenSans-Regular.ttf") else ThemeDB.fallback_font
	_bold = load("res://assets/fonts/OpenSans-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/OpenSans-Bold.ttf") else _font
	_root = Control.new()
	_root.name = "ResponsiveUI"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toast_root = Control.new()
	_toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_root)
	_toast_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_on_viewport_changed)
	_update_safe_area()


func _update_safe_area() -> void:
	_safe_top = 64.0
	_safe_bottom = 50.0
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var window_size := DisplayServer.window_get_size()
		if window_size.y > 0 and safe.size.y > 0:
			var ratio := get_viewport().get_visible_rect().size.y / float(window_size.y)
			_safe_top = maxf(52.0, safe.position.y * ratio + 20.0)
			_safe_bottom = maxf(40.0, (window_size.y - safe.end.y) * ratio + 20.0)


func _on_viewport_changed() -> void:
	_update_safe_area()
	match _screen:
		"menu": show_menu()
		"hud":
			show_hud()
			update_hud(_hud_height, _hud_coins)
		"results": show_results(_result)
		"pause": show_pause()
		"profile", "shop", "daily", "settings": show_panel(_screen)


func _clear(screen_name: String) -> void:
	_refresh_palette()
	_cycle_label = null
	_screen = screen_name
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.modulate = Color.WHITE
	_height_label = null
	_record_label = null
	_coins_label = null
	_hint = null


func _emit(name_value: String, payload: Variant = null) -> void:
	# Screen transitions can free the pressed button. Dispatch after the GUI
	# finishes processing its input so BaseButton never leaves the tree mid-event.
	_dispatch_action.call_deferred(name_value, payload)


func _dispatch_action(name_value: String, payload: Variant = null) -> void:
	if name_value == "settings_tab":
		_settings_tab = str(payload)
		Audio.play_sound("button")
		show_panel("settings")
		return
	action.emit(name_value, payload)


func _refresh_palette() -> void:
	var dark := str(Progress.data.settings.get("theme", "dark")) == "dark"
	CREAM = Color("101b2b") if dark else Color("fff6db")
	PAPER = Color("1b2a3c") if dark else Color("fffaf0")
	INK = Color("eff4e4") if dark else Color("153d33")
	MUTED = Color("a2b6c2") if dark else Color("688373")
	LINE = Color("3a4e61") if dark else Color("d9e3c8")
	LIME = Color("b8e96b")
	GOLD = Color("f4c66c")

func _is_dark() -> bool:
	return str(Progress.data.settings.get("theme", "dark")) == "dark"

func _style(color: Color, radius: int = 30, border: Color = Color.TRANSPARENT, shadow: bool = false) -> StyleBoxFlat:
	if _is_dark() and color.a > 0.05 and color.get_luminance() > 0.58 and color.s < 0.4:
		color = Color("203347").lerp(color.darkened(0.67), 0.3)
	radius = mini(radius, 9)
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.anti_aliasing = false
	box.border_color = border
	if border.a > 0:
		box.set_border_width_all(3)
	if shadow:
		box.shadow_color = Color(0.06, 0.16, 0.10, 0.16)
		box.shadow_size = 3
		box.shadow_offset = Vector2(0, 5)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	return box


func _label(text_value: String, font_size: int = 32, color: Color = Color(-1, -1, -1, 0), bold: bool = false, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	if color.r < 0:
		color = INK
	elif _is_dark() and color.get_luminance() < 0.55:
		color = color.lightened(0.40)
	var label := Label.new()
	label.text = L10n.text(text_value)
	if _is_dark() and _screen == "menu":
		label.add_theme_color_override("font_outline_color", Color("172a31"))
		label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_override("font", _bold if bold else _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 7)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(text_value: String, action_name: String, payload: Variant = null, height: float = 100, primary: bool = false, font_size: int = 31) -> Button:
	var button := Button.new()
	button.text = L10n.text(text_value)
	button.custom_minimum_size = Vector2(0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", _bold)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color("173529") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("173529") if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color("173529") if primary else INK)
	button.add_theme_color_override("font_focus_color", Color("173529") if primary else INK)
	button.add_theme_color_override("font_disabled_color", Color("8c9c85"))
	var color := LIME if primary else PAPER
	button.add_theme_stylebox_override("normal", _style(color, 32, Color.TRANSPARENT if primary else LINE, primary))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.06), 32, Color("95b17c"), primary))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.07), 32))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, 32, Color("678c4c")))
	button.add_theme_stylebox_override("disabled", _style(Color("e9ecd9"), 32, Color("dce3cf")))
	button.pressed.connect(func() -> void: _emit(action_name, payload))
	return button


func _vbox(parent: Node, separation: int = 22) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box


func _row(parent: Node, separation: int = 20) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box


func _spacer(parent: Node, min_height: float = 18, expand: bool = false) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = min_height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)
	return spacer


func _card(parent: Node, color: Color = Color(-1, -1, -1, 0), padding: int = 30) -> VBoxContainer:
	if color.r < 0:
		color = PAPER
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color, 30, LINE))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var margins := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, maxi(0, padding - 18))
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margins)
	return _vbox(margins, 14)


func _progress(value: float, maximum: float, color: Color = Color("82b66a"), bar_height: float = 18) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxf(1.0, maximum)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size.y = bar_height
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(Color("e1e8d3"), 12))
	bar.add_theme_stylebox_override("fill", _style(color, 12))
	return bar


func _coin_balance(parent: Node, amount: int, font_size: int = 32, color: Color = Color(-1, -1, -1, 0)) -> Label:
	if color.r < 0:
		color = INK
	var row := _row(parent, 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var coin := CoinArt.new()
	coin.custom_minimum_size = Vector2(font_size * 1.3, font_size * 1.3)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin)
	var label := _label(str(amount), font_size, color, true)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return label


func _positioned(parent: Node, rect: Rect2) -> Control:
	var control := Control.new()
	control.position = rect.position
	control.size = rect.size
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	return control


func show_menu() -> void:
	_clear("menu")
	var top := HBoxContainer.new()
	_content.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 58
	top.offset_right = -58
	top.offset_top = _safe_top
	top.offset_bottom = _safe_top + 86
	top.add_theme_constant_override("separation", 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_button := _button("УР. %d  ·  %s" % [Progress.get_level(), Progress.level_title().to_upper()], "profile", null, 86, false, 23)
	level_button.custom_minimum_size.x = 300
	level_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(level_button)
	_spacer(top, 0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var coin_button := _button("", "shop", null, 86, false, 28)
	coin_button.custom_minimum_size.x = 174
	coin_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(coin_button)
	var coin_center := CenterContainer.new()
	coin_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_button.add_child(coin_center)
	coin_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_coin_balance(coin_center, int(Progress.data.get("coins", 0)), 31)
	var settings := _button("☷", "settings", null, 86, false, 44)
	settings.tooltip_text = L10n.text("Настройки")
	settings.custom_minimum_size.x = 86
	settings.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(settings)

	var title_group := VBoxContainer.new()
	_content.add_child(title_group)
	title_group.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_group.offset_left = 60
	title_group.offset_right = -60
	title_group.offset_top = _safe_top + 185
	title_group.offset_bottom = _safe_top + 620
	title_group.add_theme_constant_override("separation", -19)
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gecko_title := _label("GECKO", 112, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	gecko_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	gecko_title.add_theme_constant_override("shadow_offset_y", 6)
	title_group.add_child(gecko_title)
	var rush_title := _label("RUSH", 152, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	rush_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	rush_title.add_theme_constant_override("shadow_offset_y", 7)
	title_group.add_child(rush_title)
	_spacer(title_group, 35)
	title_group.add_child(_label("ВЫШЕ С КАЖДЫМ ПРЫЖКОМ", 24, Color("567854"), true, HORIZONTAL_ALIGNMENT_CENTER))

	var record_group := VBoxContainer.new()
	record_group.name = "MenuRunSummary"
	_content.add_child(record_group)
	record_group.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	record_group.offset_left = 140
	record_group.offset_right = -140
	record_group.offset_top = _safe_top + 640
	record_group.offset_bottom = _safe_top + 1220
	record_group.add_theme_constant_override("separation", 10)
	record_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var world := Progress.current_world()
	var world_button := _button(str(world.get("name", "Лёгкий")).to_upper() + "   ›", "profile", null, 70, false, 25)
	world_button.name = "MenuDifficulty"
	record_group.add_child(world_button)
	_menu_world_info(record_group, world)
	var distance_row := _row(record_group, 14)
	distance_row.name = "RunDistanceCards"
	distance_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var card_size := minf(236.0, (get_viewport().get_visible_rect().size.x - 368.0) / 3.0)
	var distances := Progress.run_distances()
	_menu_distance_card(distance_row, "LastRunDistance", distances.last, "ПОСЛЕДНИЙ\nЗАБЕГ", card_size)
	_menu_distance_card(distance_row, "BestRunDistance", distances.best, "РЕКОРД\nЗАБЕГА", card_size)
	_menu_distance_card(distance_row, "TotalRunDistance", distances.total, "ВСЕГО\nПРОЙДЕНО", card_size)

	var bottom := VBoxContainer.new()
	bottom.name = "MenuActions"
	_content.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 88
	bottom.offset_right = -88
	bottom.offset_bottom = -_safe_bottom
	var has_resume := not Progress.load_resume().is_empty()
	bottom.offset_top = -_safe_bottom - (382 if has_resume else 310)
	bottom.add_theme_constant_override("separation", 17)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var play := _button("ПРОДОЛЖИТЬ" if has_resume else "ИГРАТЬ", "resume" if has_resume else "play", null, 122, true, 42)
	bottom.add_child(play)
	if has_resume:
		bottom.add_child(_button("НОВЫЙ ЗАБЕГ", "play", null, 62, false, 25))
	var nav := _row(bottom, 16)
	for entry in [["МАГАЗИН", "shop"], ["ПРОФИЛЬ", "profile"], ["ЗАДАНИЯ", "daily"]]:
		nav.add_child(_button(str(entry[0]), str(entry[1]), null, 92, false, 25))
	bottom.add_child(_label("ОДНО КАСАНИЕ — ЦЕЛЫЙ МИР", 21, Color(1, 0.97, 0.84, 0.80), false, HORIZONTAL_ALIGNMENT_CENTER))
	fade_in(0.35)


func _world_name(id: String) -> String:
	for item: Dictionary in Progress.WORLDS:
		if str(item.get("id", "")) == id:
			return L10n.text(str(item.get("name", "")))
	return ""


func _decimal(value: float, digits: int = 2) -> String:
	var result := ("%." + str(digits) + "f") % value
	while result.ends_with("0") and result.contains("."):
		result = result.left(-1)
	result = result.trim_suffix(".")
	return result.replace(".", ",") if L10n.language == "ru" else result


func _world_xp_text(id: String) -> String:
	var status: Dictionary = Progress.world_xp_status(id)
	var multiplier := _decimal(float(status.get("multiplier", 1.0)))
	var cap := int(status.get("cap_level", 0))
	if cap > 0:
		return L10n.format_text("XP ×%s · до уровня %d", [multiplier, cap])
	return L10n.format_text("XP ×%s · без ограничения уровня", [multiplier])


func _world_record_requirement(status: Dictionary) -> String:
	return L10n.format_text("Рекорд мира «%s»: %s / %s м", [
		_world_name(str(status.get("previous_world", ""))),
		_number(float(status.get("best_metres", 0.0))),
		_number(float(status.get("required_metres", 0.0)))])


func _menu_world_info(parent: Node, world: Dictionary) -> void:
	var info := _card(parent, PAPER, 18)
	info.get_parent().get_parent().name = "MenuWorldInfo"
	info.add_theme_constant_override("separation", 6)
	var id := str(world.get("id", "jungle"))
	info.add_child(_label(_world_xp_text(id), 23, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	var capped := bool(Progress.world_xp_status(id).get("capped", false))
	if capped:
		info.add_child(_label("Тренировка · XP за забег: 0", 22, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER))
	var next_world: Dictionary = {}
	for item: Dictionary in Progress.WORLDS:
		if not Progress.is_world_unlocked(str(item.get("id", ""))):
			next_world = item
			break
	if not next_world.is_empty():
		var status: Dictionary = Progress.world_unlock_status(str(next_world["id"]))
		var goal := L10n.format_text("Далее: «%s» · уровень %d", [_world_name(str(next_world["id"])), int(status["level_required"])])
		info.add_child(_label(goal + "\n" + _world_record_requirement(status), 21, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	elif capped:
		for item: Dictionary in Progress.WORLDS:
			if not bool(Progress.world_xp_status(str(item["id"])).get("capped", false)):
				info.add_child(_label(L10n.format_text("Для XP выбери: «%s»", [_world_name(str(item["id"]))]), 21, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
				break


func _menu_distance_card(parent: HBoxContainer, card_name: String, metres: float, caption: String, side_length: float) -> void:
	var panel := PanelContainer.new()
	panel.name = card_name
	panel.custom_minimum_size = Vector2(side_length, side_length)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(PAPER, 9, LINE)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := _vbox(panel, 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var value_text := "%s м" % _number(metres)
	# Keep long lifetime totals inside the same square instead of widening it.
	var font_size := mini(43, int((side_length - 34.0) / maxf(1.0, float(value_text.length()) * 0.62)))
	var value := _label(value_text, maxi(18, font_size), LIME, true, HORIZONTAL_ALIGNMENT_CENTER)
	value.name = "Metres"
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	column.add_child(value)
	var description := _label(caption, 22, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	description.add_theme_constant_override("line_spacing", 4)
	column.add_child(description)


func show_hud() -> void:
	_clear("hud")
	var pause_button := _button("Ⅱ", "pause", null, 86, false, 34)
	_content.add_child(pause_button)
	pause_button.position = Vector2(54, _safe_top)
	pause_button.size = Vector2(88, 86)
	pause_button.tooltip_text = L10n.text("Пауза")
	var height_capsule := PanelContainer.new()
	height_capsule.name = "HeightCapsule"
	_content.add_child(height_capsule)
	height_capsule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	height_capsule.anchor_left = 0.5
	height_capsule.anchor_right = 0.5
	height_capsule.offset_left = -180
	height_capsule.offset_right = 180
	height_capsule.offset_top = _safe_top - 10
	height_capsule.offset_bottom = _safe_top + 146
	var height_style := _style(Color(1, 0.98, 0.91, 0.56), 14)
	# Keep this HUD backdrop translucent in both themes without changing cards.
	height_style.bg_color.a = 0.56
	height_style.set_corner_radius_all(14)
	height_style.anti_aliasing = true
	height_capsule.add_theme_stylebox_override("panel", height_style)
	height_capsule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := VBoxContainer.new()
	_content.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_left = 210
	center.offset_right = -210
	center.offset_top = _safe_top - 14
	center.offset_bottom = _safe_top + 180
	center.add_theme_constant_override("separation", -3)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_height_label = _label("0 м", 76, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	_height_label.add_theme_color_override("font_outline_color", CREAM)
	_height_label.add_theme_constant_override("outline_size", 10)
	center.add_child(_height_label)
	_record_label = _label("Рекорд: %s м" % _number(Progress.data.get("best_height", 0)), 25, Color("456c52"), true, HORIZONTAL_ALIGNMENT_CENTER)
	_record_label.add_theme_color_override("font_outline_color", CREAM)
	_record_label.add_theme_constant_override("outline_size", 7)
	center.add_child(_record_label)
	_cycle_label = _label("ДЕНЬ", 20, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	_cycle_label.add_theme_color_override("font_outline_color", CREAM)
	_cycle_label.add_theme_constant_override("outline_size", 3)
	center.add_child(_cycle_label)
	var coin_card := PanelContainer.new()
	_content.add_child(coin_card)
	coin_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	coin_card.offset_left = -220
	coin_card.offset_right = -54
	coin_card.offset_top = _safe_top
	coin_card.offset_bottom = _safe_top + 86
	coin_card.add_theme_stylebox_override("panel", _style(Color(1, 0.98, 0.91, 0.93), 30))
	coin_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_label = _coin_balance(coin_card, _hud_coins, 32)
	_hint = PanelContainer.new()
	_content.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 190
	_hint.offset_right = -190
	_hint.offset_top = -_safe_bottom - 90
	_hint.offset_bottom = -_safe_bottom
	(_hint as PanelContainer).add_theme_stylebox_override("panel", _style(Color(1, 0.98, 0.91, 0.86), 28))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(_label("КАСАНИЕ — ПРЫЖОК", 28, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	_hint.visible = _hint_visible
	update_hud(_hud_height, _hud_coins)


func update_hud(height: float, coins: int) -> void:
	_hud_height = height
	_hud_coins = coins
	if is_instance_valid(_height_label):
		var next_text := L10n.text("%s м" % _number(height))
		if _height_label.text != next_text:
			_height_label.text = next_text
	if is_instance_valid(_coins_label):
		if _coins_label.text != str(coins):
			_coins_label.text = str(coins)


func set_hint_visible(value: bool) -> void:
	_hint_visible = value
	if is_instance_valid(_hint):
		_hint.visible = value


func _panel_shell(title: String, subtitle: String = "") -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.17, 0.12, 0.42)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	_content.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 44
	panel.offset_right = -44
	panel.offset_top = _safe_top
	panel.offset_bottom = -_safe_bottom
	panel.add_theme_stylebox_override("panel", _style(CREAM, 44, Color.TRANSPARENT, true))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var all := _vbox(panel, 27)
	var header := _row(all, 20)
	var back := _button("‹", "menu", null, 80, false, 54)
	back.custom_minimum_size.x = 80
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.tooltip_text = L10n.text("Главное меню")
	header.add_child(back)
	header.add_child(_label(title, 45, INK, true))
	_coin_balance(header, int(Progress.data.get("coins", 0)), 30)
	if not subtitle.is_empty():
		all.add_child(_label(subtitle, 27, MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	all.add_child(scroll)
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 7
	for item in [["scroll", Color.TRANSPARENT], ["grabber", Color("c1d0ad")], ["grabber_highlight", Color("93af7c")], ["grabber_pressed", Color("779a61")]]:
		var scrollbar_style := _style(item[1], 4)
		scrollbar_style.content_margin_left = 0
		scrollbar_style.content_margin_right = 0
		scrollbar_style.content_margin_top = 0
		scrollbar_style.content_margin_bottom = 0
		scrollbar.add_theme_stylebox_override(str(item[0]), scrollbar_style)
	var body := _vbox(scroll, 25)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return body


func show_panel(name_value: String) -> void:
	_clear(name_value)
	match name_value:
		"shop": _show_shop()
		"profile": _show_profile()
		"daily": _show_daily()
		"settings": _show_settings()
		_: show_menu()
	fade_in(0.22)


func _show_shop() -> void:
	var body := _panel_shell("МАГАЗИН", "Новые образы для новых высот")
	_spacer(body, 100)
	var chest := ChestArt.new()
	chest.custom_minimum_size = Vector2(0, 450)
	chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(chest)
	_spacer(body, 35)
	body.add_child(_label("Скоро здесь\nпоявятся скины!", 53, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(_label("Пока здесь тихо. Исследуй миры,\nсобирай монеты и покоряй новые высоты.", 29, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(body, 20)
	var price := _card(body, Color("edf1d9"), 34)
	price.add_child(_label("Случайный скин — 100 монет", 29, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	price.add_child(_label("Покупки появятся в будущем обновлении", 24, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(body, 50, true)
	body.add_child(_button("В ГЛАВНОЕ МЕНЮ", "menu", null, 106, true, 31))
	_spacer(body, 12)


func _show_profile() -> void:
	var body := _panel_shell("ПРОФИЛЬ", "Каждый забег оставляет след")
	var hero := _card(body, Color("eaf0d4"), 38)
	var hero_row := _row(hero, 28)
	var avatar := Control.new()
	avatar.custom_minimum_size = Vector2(176, 225)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_row.add_child(avatar)
	if ResourceLoader.exists("res://scripts/gecko.gd"):
		var gecko_script: Script = load("res://scripts/gecko.gd")
		var gecko: Node2D = Node2D.new()
		gecko.set_script(gecko_script)
		avatar.add_child(gecko)
		gecko.position = Vector2(88, 127)
		gecko.scale = Vector2(1.2, 1.2)
	var hero_info := _vbox(hero_row, 6)
	hero_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_info.add_child(_label("УРОВЕНЬ %d" % Progress.get_level(), 45, INK, true))
	hero_info.add_child(_label(Progress.level_title(), 31, Color("638147"), true))
	hero_info.add_child(_label("Стандартный зелёный геккон", 23, MUTED))
	hero.add_child(_progress(Progress.xp_in_level(), Progress.xp_required()))
	hero.add_child(_label("%s / %s XP до следующего уровня" % [_number(Progress.xp_in_level()), _number(Progress.xp_required())], 24, MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	body.add_child(grid)
	_stat(grid, "%s м" % _number(Progress.data.get("best_height", 0)), "ЛУЧШИЙ РЕКОРД")
	_stat(grid, "%s м" % _number(Progress.data.get("total_distance", 0)), "ВСЕГО ПРОЙДЕНО")
	_stat(grid, _number(Progress.data.get("runs", 0)), "ЗАБЕГОВ")
	_stat(grid, _number(Progress.data.get("lifetime_coins", 0)), "МОНЕТ ЗА ВСЁ ВРЕМЯ")
	_spacer(body, 10)
	body.add_child(_label("СЛОЖНОСТЬ", 30, INK, true))
	body.add_child(_label("Сейчас: " + str(Progress.current_world().get("name", "Лёгкий")), 26, MUTED))
	body.add_child(_label("Сложнее забеги — больше XP. Для открытия нужны уровень и рекорд забега в предыдущей сложности.", 23, MUTED))
	var worlds := GridContainer.new()
	worlds.columns = 2
	worlds.add_theme_constant_override("h_separation", 18)
	worlds.add_theme_constant_override("v_separation", 18)
	worlds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(worlds)
	for item in Progress.WORLDS:
		_world_button(worlds, item)
	body.add_child(_label("На указанном уровне забеги становятся тренировочными: без XP. Выбирай следующую сложность для роста.", 23, MUTED))
	_spacer(body, 10)
	var unlocked: Array = Progress.data.get("achievements", [])
	body.add_child(_label("ДОСТИЖЕНИЯ   %d / %d" % [unlocked.size(), Progress.ACHIEVEMENTS.size()], 30, INK, true))
	for item in Progress.ACHIEVEMENTS:
		var achievement: Dictionary = item
		var done := unlocked.has(str(achievement.get("id", "")))
		var unlock_level := int(achievement.get("unlock", 1))
		var available := Progress.get_level() >= unlock_level
		var achievement_card := _card(body, Color("e9f0d7") if done else PAPER, 26)
		var row := _row(achievement_card)
		row.add_child(_label(str(achievement.get("title", achievement.get("name", ""))), 30, INK if available else MUTED, true))
		var badge := _label("✓" if done else "○", 33, Color("6a974f") if done else Color("a3b297"), true)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(badge)
		achievement_card.add_child(_label(str(achievement.get("description", "")), 24, MUTED))
		if not available:
			achievement_card.add_child(_label("Откроется на %d уровне" % unlock_level, 22, Color("a08a56"), true))
	_spacer(body, 15)


func _stat(parent: Node, value: String, caption: String) -> void:
	var cell := _card(parent, PAPER, 28)
	cell.add_child(_label(value, 40, INK, true))
	cell.add_child(_label(caption, 21, MUTED, true))


func _world_button(parent: Node, item: Dictionary) -> void:
	var id := str(item.get("id", "jungle"))
	var status: Dictionary = Progress.world_unlock_status(id)
	var unlocked := bool(status.get("unlocked", false))
	var selected := str(Progress.data.get("selected_world", "jungle")) == id
	# Let containers determine card height from wrapped text in either language.
	# Anchored labels inside fixed-height buttons could overlap the next row.
	var card := _card(parent, Color("eaf0d4") if selected else PAPER, 20)
	card.get_parent().get_parent().name = "World_" + id
	card.add_theme_constant_override("separation", 10)
	var row := _row(card, 12)
	var icon := WorldArt.new()
	icon.world_id = id
	icon.custom_minimum_size = Vector2(54, 66)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate.a = 1.0 if unlocked else 0.5
	row.add_child(icon)
	var info := _vbox(row, 3)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(_label(str(item.get("name", "")), 27, INK if unlocked else MUTED, true))
	info.add_child(_label(str(item.get("theme_name", "")), 20, MUTED))
	card.add_child(_label(_world_xp_text(id), 22, INK, true))
	if bool(Progress.world_xp_status(id).get("capped", false)):
		card.add_child(_label("Тренировка · XP за забег: 0", 21, GOLD, true))
	var profile := RushTuning.profile_for(id)
	card.add_child(_label(L10n.format_text("Темп: %s → %s м/с", [
		_decimal(float(profile["start_speed"]) / RushTuning.PIXELS_PER_METRE, 1),
		_decimal(float(profile["max_speed"]) / RushTuning.PIXELS_PER_METRE, 1)]), 21, MUTED))
	card.add_child(_label(L10n.format_text("Максимальный темп: с %s м", [_number(profile["cap_metres"])]), 21, MUTED))
	if not unlocked:
		card.add_child(_label(L10n.format_text("Нужен уровень %d · сейчас %d", [int(status["level_required"]), Progress.get_level()]), 22, MUTED, true))
		if not str(status.get("previous_world", "")).is_empty():
			card.add_child(_label(_world_record_requirement(status), 21, MUTED))
			card.add_child(_progress(float(status["best_metres"]), float(status["required_metres"]), LIME, 10))
	_spacer(card, 0, true)
	var caption := "ВЫБРАН" if selected else ("ВЫБРАТЬ" if unlocked else "ЗАКРЫТО")
	var button := _button(caption, "world", id, 64, selected, 22)
	button.name = "Select_" + id
	button.disabled = not unlocked
	card.add_child(button)


func _show_daily() -> void:
	var body := _panel_shell("ЗАДАНИЯ", "Небольшая цель на каждый день")
	var intro := _card(body, Color("eaf0d4"), 34)
	intro.add_child(_label("ЕЖЕДНЕВНЫЕ ЗАДАНИЯ", 34, INK, true))
	intro.add_child(_label("Играй в своём ритме. Прогресс сохраняется между забегами, а награды можно забрать здесь.", 27, MUTED))
	_spacer(body, 8)
	for item in Progress.daily_tasks():
		var task: Dictionary = item
		var claimed := bool(task.get("claimed", false))
		var complete := bool(task.get("complete", false))
		var task_card := _card(body, Color("edf3dc") if complete else PAPER, 34)
		var header := _row(task_card, 20)
		header.add_child(_label(str(task.get("title", "")), 31, INK, true))
		var reward := _label("+%d" % int(task.get("reward", 0)), 34, Color("9c762e"), true)
		reward.autowrap_mode = TextServer.AUTOWRAP_OFF
		reward.size_flags_horizontal = Control.SIZE_SHRINK_END
		header.add_child(reward)
		var value := float(task.get("value", 0))
		var target := float(task.get("target", 1))
		task_card.add_child(_progress(value, target, Color("83af66"), 20))
		var progress_text := "%s / %s" % [_number(minf(value, target)), _number(target)]
		task_card.add_child(_label(progress_text, 25, MUTED))
		var claim := _button("ПОЛУЧЕНО" if claimed else ("ЗАБРАТЬ +%d МОНЕТ" % int(task.get("reward", 0)) if complete else "В ПРОЦЕССЕ"), "claim", str(task.get("id", "")), 84, complete and not claimed, 27)
		claim.disabled = claimed or not complete
		task_card.add_child(claim)
	_spacer(body, 16)
	body.add_child(_label("Обновляются каждый день. Для задания на высоту учитывается один лучший забег за сегодня.", 25, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(body, 40, true)
	body.add_child(_button("В ГЛАВНОЕ МЕНЮ", "menu", null, 104, false, 29))
	_spacer(body, 12)


func _show_settings() -> void:
	var body := _panel_shell("НАСТРОЙКИ", "Пусть игра звучит по-твоему")
	var tabs := _row(body, 8)
	for entry in [["Звук", "sound"], ["Графика", "graphics"], ["Язык", "language"], ["Создатели", "creators"]]:
		tabs.add_child(_button(entry[0], "settings_tab", entry[1], 82, _settings_tab == entry[1], 24))
	_spacer(body, 20)
	match _settings_tab:
		"sound":
			_setting_row(body, "Музыка", "Спокойный ритм джунглей", "music")
			_setting_row(body, "Звуковые эффекты", "Монеты, рекорды и интерфейс", "sfx")
			_setting_row(body, "Звук прыжка", "Прыжок и приземление", "jump_sfx")
		"graphics":
			var fps_card := _card(body)
			fps_card.add_child(_label("Частота кадров", 35, INK, true))
			var fps_row := _row(fps_card)
			for rate in [60, 120]:
				fps_row.add_child(_button("%d Гц" % rate, "setting", {"key": "fps", "value": rate}, 94, int(Progress.data.settings.get("fps", 60)) == rate))
			fps_card.add_child(_label("На экранах 120 Гц можно выбрать 120 FPS.", 25, MUTED))
			var theme_card := _card(body)
			theme_card.add_child(_label("Тема оформления", 35, INK, true))
			var theme_row := _row(theme_card)
			for item in [["Тёмная", "dark"], ["Светлая", "light"]]:
				theme_row.add_child(_button(item[0], "setting", {"key": "theme", "value": item[1]}, 94, str(Progress.data.settings.get("theme", "dark")) == item[1]))
			theme_card.add_child(_label("День и ночь сменяются каждые 40 секунд.", 25, MUTED))
		"language":
			var language_card := _card(body)
			language_card.add_child(_label("Язык интерфейса", 35, INK, true))
			for item in [["Русский", "ru"], ["English", "en"]]:
				language_card.add_child(_button(item[0], "setting", {"key": "language", "value": item[1]}, 112, str(Progress.data.settings.get("language", "ru")) == item[1]))
		"creators":
			var credits := _card(body)
			credits.add_child(_label("pr1de. tg:@ceoVist", 37, INK, true))
			credits.add_child(_label("romantic. tg:@ikdie", 37, INK, true))
	_spacer(body, 40, true)
	body.add_child(_button("ГОТОВО", "menu", null, 105, true, 32))
	_spacer(body, 12)


func _setting_row(parent: Node, title: String, subtitle: String, key: String) -> void:
	var card := _card(parent, PAPER, 34)
	var row := _row(card, 25)
	var text_box := _vbox(row, 7)
	text_box.add_child(_label(title, 34, INK, true))
	text_box.add_child(_label(subtitle, 24, MUTED))
	var settings: Dictionary = Progress.data.get("settings", {})
	var enabled := bool(settings.get(key, true))
	var toggle := _button("ВКЛ." if enabled else "ВЫКЛ.", "setting", {"key": key, "value": not enabled}, 90, enabled, 28)
	toggle.custom_minimum_size.x = 160
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(toggle)


func show_results(summary: Dictionary) -> void:
	_result = summary.duplicate(true)
	_clear("results")
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.17, 0.12, 0.54)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	_content.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 72
	panel.offset_right = -72
	panel.offset_top = _safe_top + 85
	panel.offset_bottom = -_safe_bottom - 55
	panel.add_theme_stylebox_override("panel", _style(CREAM, 46, Color.TRANSPARENT, true))
	var box := _vbox(panel, 20)
	_spacer(box, 8)
	box.add_child(_label("ОТЛИЧНЫЙ ПОДЪЁМ", 28, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("%s м" % _number(summary.get("height", 0)), 120, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	if bool(summary.get("new_best", false)):
		var record := _card(box, Color("f5e6b1"), 16)
		record.add_child(_label("НОВЫЙ РЕКОРД!", 30, Color("8b6a2e"), true, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		box.add_child(_label("Рекорд: %s м" % _number(Progress.data.get("best_height", 0)), 29, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(box, 10)
	var rewards := _row(box, 18)
	var coins := _card(rewards, PAPER, 30)
	coins.add_child(_label("МОНЕТЫ", 23, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER))
	_coin_balance(coins, int(summary.get("reward_coins", 0)), 47)
	var xp := _card(rewards, PAPER, 30)
	xp.add_child(_label("ОПЫТ", 23, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER))
	xp.add_child(_label("+%s XP" % _number(summary.get("xp", 0)), 43, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(box, 10)
	var old_level := int(summary.get("old_level", Progress.get_level()))
	var new_level := int(summary.get("level", Progress.get_level()))
	if new_level > old_level:
		var promotion := _card(box, Color("e5edc5"), 24)
		promotion.add_child(_label("НОВЫЙ УРОВЕНЬ!", 29, Color("638147"), true, HORIZONTAL_ALIGNMENT_CENTER))
		promotion.add_child(_label("УРОВЕНЬ %d  ·  %s" % [new_level, Progress.level_title()], 28, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
		promotion.modulate.a = 0
		create_tween().tween_property(promotion, "modulate:a", 1.0, 0.45).set_delay(0.30)
	else:
		box.add_child(_label("УРОВЕНЬ %d  ·  %s" % [new_level, Progress.level_title()], 28, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_progress(Progress.xp_in_level(), Progress.xp_required(), Color("8cb86b"), 22))
	box.add_child(_label("%s / %s XP" % [_number(Progress.xp_in_level()), _number(Progress.xp_required())], 24, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	var achievements: Array = summary.get("new_achievements", [])
	if not achievements.is_empty():
		box.add_child(_label("Новое достижение: %s" % _achievement_title(str(achievements[0])), 26, Color("7b8d48"), true, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(box, 25, true)
	box.add_child(_button("ЕЩЁ РАЗ", "retry", null, 118, true, 38))
	box.add_child(_button("ГЛАВНОЕ МЕНЮ", "menu", null, 90, false, 28))
	_spacer(box, 4)
	fade_in(0.35)


func show_pause() -> void:
	_clear("pause")
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.17, 0.12, 0.52)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_content.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_content.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(850, 680)
	panel.add_theme_stylebox_override("panel", _style(CREAM, 44, Color.TRANSPARENT, true))
	center.add_child(panel)
	var box := _vbox(panel, 25)
	_spacer(box, 14)
	box.add_child(_label("ПЕРЕДЫШКА", 63, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("Высота подождёт.", 31, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(box, 30, true)
	box.add_child(_button("ПРОДОЛЖИТЬ", "continue", null, 114, true, 36))
	box.add_child(_button("ЗАВЕРШИТЬ И В МЕНЮ", "menu", null, 90, false, 28))
	box.add_child(_label("При закрытии игры забег сохранится для продолжения.", 23, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	_spacer(box, 10)
	fade_in(0.18)


func toast(text_value: String) -> void:
	if not is_instance_valid(_toast_root):
		return
	if is_instance_valid(_toast_tween):
		_toast_tween.kill()
	for child in _toast_root.get_children():
		child.queue_free()
	var toast_panel := PanelContainer.new()
	_toast_root.add_child(toast_panel)
	toast_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.offset_left = -200
	toast_panel.offset_right = 200
	toast_panel.offset_top = _safe_top + 225
	toast_panel.offset_bottom = _safe_top + 325
	toast_panel.add_theme_stylebox_override("panel", _style(Color("153d33"), 30, Color.TRANSPARENT, true))
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(_label(text_value, 30, CREAM, true, HORIZONTAL_ALIGNMENT_CENTER))
	toast_panel.modulate.a = 0
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(1.9)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(toast_panel.queue_free)


func fade_out(duration: float = 0.35) -> void:
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_content, "modulate:a", 0.0, duration)


func fade_in(duration: float = 0.35) -> void:
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_content.modulate.a = 0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_content, "modulate:a", 1.0, duration)


func _achievement_title(id: String) -> String:
	for item in Progress.ACHIEVEMENTS:
		if str(item.get("id", "")) == id:
			return str(item.get("title", item.get("name", id)))
	return id


func _number(value: Variant) -> String:
	var raw := str(maxi(0, int(value)))
	var result := ""
	for i in range(raw.length()):
		if i > 0 and (raw.length() - i) % 3 == 0:
			result += " "
		result += raw[i]
	return result

func update_cycle(night: bool, seconds_left: float) -> void:
	if is_instance_valid(_cycle_label):
		var value := "%s · %d %s" % [L10n.text("НОЧЬ" if night else "ДЕНЬ"), ceili(seconds_left), "s" if L10n.language == "en" else "с"]
		if _cycle_label.text != value:
			_cycle_label.text = value
