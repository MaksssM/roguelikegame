class_name PauseMenu
extends CanvasLayer
# Пауза по Esc: продовжити або покинути світ. Працює на паузі (ALWAYS),
# Esc для виходу з паузи ловить сама (main на паузі ввід не чує).

signal resume_requested
signal quit_requested

var settings_holder: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.7)
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
	sb.border_color = Color(0.3, 0.5, 0.9, 0.5)
	sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var title := Label.new()
	title.text = Lang.t("p_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var rc := Button.new()
	rc.text = Lang.t("p_resume")
	rc.custom_minimum_size = Vector2(0, 40)
	rc.pressed.connect(func(): resume_requested.emit())
	box.add_child(rc)
	var st := Button.new()
	st.text = Lang.t("m_settings")
	st.custom_minimum_size = Vector2(0, 40)
	st.pressed.connect(_on_toggle_settings)
	box.add_child(st)
	settings_holder = VBoxContainer.new()
	settings_holder.visible = false
	box.add_child(settings_holder)
	var sp := SettingsPanel.new()
	settings_holder.add_child(sp)
	sp.build(false)
	var hint := Label.new()
	hint.text = Lang.t("p_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	var q := Button.new()
	q.text = Lang.t("p_quit")
	q.custom_minimum_size = Vector2(0, 40)
	q.pressed.connect(func(): quit_requested.emit())
	box.add_child(q)


func _on_toggle_settings() -> void:
	settings_holder.visible = not settings_holder.visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		resume_requested.emit()
		get_viewport().set_input_as_handled()
