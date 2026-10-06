class_name StartMenu
extends CanvasLayer
# Стартове меню: випадковий світ, щоденний ран, свій код/seed, останні світи.

signal start_requested(seed_value: int, mode: String)

var seed_edit: LineEdit
var message: Label
var adaptive_check: CheckBox
var settings_box: VBoxContainer
var codex_box: VBoxContainer
var bestiary_box: VBoxContainer
var title: Label
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if title != null:
		var k := 0.94 + 0.06 * sin(_t * 2.0)
		title.modulate = Color(k, k * 0.99, k * 0.96)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.14, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	card_sb.set_corner_radius_all(12)
	card_sb.content_margin_left = 28.0
	card_sb.content_margin_right = 28.0
	card_sb.content_margin_top = 24.0
	card_sb.content_margin_bottom = 24.0
	card_sb.border_color = Color(0.3, 0.5, 0.9, 0.5)
	card_sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	title = Label.new()
	title.text = "ROGUELIKE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.0))
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = Lang.t("m_tagline")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	box.add_child(subtitle)
	box.add_child(HSeparator.new())

	adaptive_check = CheckBox.new()
	adaptive_check.text = Lang.t("m_adaptive")
	box.add_child(adaptive_check)

	_add_header(box, Lang.t("m_world"))
	_add_button(box, Lang.t("m_random"), _on_random)
	_add_button(box, Lang.t("m_daily") % WorldSeed.daily_label(), _on_daily)
	_add_button(box, Lang.t("m_settings"), _on_toggle_settings)

	settings_box = VBoxContainer.new()
	settings_box.visible = false
	settings_box.add_theme_constant_override("separation", 6)
	box.add_child(settings_box)
	_build_settings(settings_box)

	_add_button(box, Lang.t("m_codex"), _on_toggle_codex)
	codex_box = VBoxContainer.new()
	codex_box.visible = false
	codex_box.add_theme_constant_override("separation", 6)
	box.add_child(codex_box)
	_build_codex(codex_box)

	_add_button(box, Lang.t("m_bestiary"), _on_toggle_bestiary)
	bestiary_box = VBoxContainer.new()
	bestiary_box.visible = false
	bestiary_box.add_theme_constant_override("separation", 6)
	box.add_child(bestiary_box)
	_build_bestiary(bestiary_box)

	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = Lang.t("m_custom_ph")
	seed_edit.text_submitted.connect(func(_t): _on_custom())
	box.add_child(seed_edit)
	_add_button(box, Lang.t("m_custom_btn"), _on_custom)

	message = Label.new()
	message.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)

	_add_recent(box)

	box.add_child(HSeparator.new())
	var controls := Label.new()
	controls.text = Lang.t("m_controls")
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	controls.add_theme_font_size_override("font_size", 12)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(controls)
	var ver := Label.new()
	ver.text = Lang.t("m_version")
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55))
	ver.add_theme_font_size_override("font_size", 11)
	box.add_child(ver)


func _add_recent(box: VBoxContainer) -> void:
	var runs := RunHistory.recent(5)
	if runs.is_empty():
		return
	var head := Label.new()
	head.text = Lang.t("m_recent")
	box.add_child(head)
	for r in runs:
		var s := int(r["seed"])
		var t := int(r["time"])
		var text := Lang.t("m_recent_row") % [WorldSeed.to_code(s), r["mode"], int(r["kills"]), t / 60, t % 60]
		_add_button(box, text, _start_recent.bind(s, str(r["mode"])))


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.55))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.2, 0.3, 1.0)
	normal.set_corner_radius_all(8)
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0
	b.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.24, 0.32, 0.48, 1.0)
	hover.border_color = Color(1.0, 0.85, 0.4, 0.8)
	hover.set_border_width_all(1)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.1, 0.13, 0.2, 1.0)
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(callback)
	parent.add_child(b)


func _add_header(box: VBoxContainer, text: String) -> void:
	var h := Label.new()
	h.text = text
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	h.add_theme_font_size_override("font_size", 14)
	box.add_child(h)


func _start_recent(seed_value: int, mode: String) -> void:
	start_requested.emit(seed_value, mode)


func _on_random() -> void:
	var s := WorldSeed.random_seed()
	start_requested.emit(s, Lang.t("mode_random"))


func _on_daily() -> void:
	start_requested.emit(WorldSeed.daily(), Lang.t("mode_daily") + " " + WorldSeed.daily_label())


func _on_custom() -> void:
	var text := seed_edit.text.strip_edges()
	if text.is_empty():
		_on_random()
		return
	var s := WorldSeed.from_text(text)
	if s < 0:
		message.text = Lang.t("m_err_code")
		return
	start_requested.emit(s, WorldSeed.mode_for(s))


func is_adaptive() -> bool:
	return adaptive_check.button_pressed


func _build_settings(box: VBoxContainer) -> void:
	var sp := SettingsPanel.new()
	box.add_child(sp)
	sp.build(true)


func _on_toggle_settings() -> void:
	settings_box.visible = not settings_box.visible


func _on_toggle_codex() -> void:
	codex_box.visible = not codex_box.visible


func _on_toggle_bestiary() -> void:
	bestiary_box.visible = not bestiary_box.visible


func _build_bestiary(box: VBoxContainer) -> void:
	var title := Label.new()
	title.text = Lang.t("bx_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	for key in ["grunt", "runner", "tank", "spitter"]:
		var t: Dictionary = GameData.ENEMY_TYPES[key]
		var line := Lang.t("bx_row") % [Lang.t("et_" + key), float(t["hp"]), float(t["spd"])]
		if int(t["need"]) > 0:
			line += Lang.t("bx_unlock") % int(t["need"])
		_codex_text(box, "• " + line)
	_codex_text(box, Lang.t("bx_spit") % int(GameData.SPIT["range"]))
	_codex_text(box, "• " + Lang.t("bx_boss") % [float(GameData.BOSS["hp"]), int(GameData.BOSS_EVERY), int(GameData.RELIC["boss_xp"])])


func _build_codex(box: VBoxContainer) -> void:
	var title := Label.new()
	title.text = Lang.t("cx_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_codex_head(box, Lang.t("cx_eff_h"))
	var effs: Array = []
	for fx in GameData.EFFECT:
		effs.append(Lang.t(GameData.EFFECT[fx]["name_id"]))
	_codex_text(box, " · ".join(effs))
	_codex_head(box, Lang.t("cx_react_h"))
	for r in ["cx_r_steam", "cx_r_gas", "cx_r_shatter", "cx_r_superconduct"]:
		_codex_text(box, "• " + Lang.t(r))
	_codex_text(box, Lang.t("cx_note"))


func _codex_head(box: VBoxContainer, text: String) -> void:
	var h := Label.new()
	h.text = text
	h.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	h.add_theme_font_size_override("font_size", 15)
	box.add_child(h)


func _codex_text(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
