class_name LevelUpMenu
extends CanvasLayer
# Меню рівня: пауза гри й 3 варіанти нагороди на вибір.
# Працює на паузі (process_mode ALWAYS), вибір повертає сигналом picked.

signal picked(index: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func show_choices(level: int, options: Array) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.97)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 28.0
	sb.content_margin_right = 28.0
	sb.content_margin_top = 24.0
	sb.content_margin_bottom = 24.0
	sb.border_color = Color(1.0, 0.8, 0.3, 0.6)
	sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	var title := Label.new()
	title.text = Lang.t("l_title") % level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	for i in options.size():
		box.add_child(_option_card(options[i], i))


func _option_card(o: Dictionary, i: int) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.15, 0.22, 1.0)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	var t := Label.new()
	t.text = str(o["title"])
	t.add_theme_font_size_override("font_size", 18)
	texts.add_child(t)
	var d := Label.new()
	d.text = str(o["desc"])
	d.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	d.add_theme_font_size_override("font_size", 13)
	texts.add_child(d)
	var b := Button.new()
	b.text = Lang.t("l_take")
	b.custom_minimum_size = Vector2(90, 48)
	b.pressed.connect(_on_press.bind(i))
	row.add_child(b)
	return card


func _on_press(i: int) -> void:
	picked.emit(i)
