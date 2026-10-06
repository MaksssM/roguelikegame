class_name SettingsPanel
extends VBoxContainer
# Усі налаштування одним блоком: стартовое меню і пауза використовують його,
# щоб не розходитись. build(true) - з вибором мови (меню), build(false) - без
# (пауза: зміна мови перезавантажує сцену і вбила б забіг).

var _include_lang := true


func build(include_lang := true) -> void:
	_include_lang = include_lang
	for c in get_children():
		remove_child(c)
		c.queue_free()
	add_theme_constant_override("separation", 6)
	_add_slider(Lang.t("s_sens"), 0.2, 3.0, 0.1, Settings.mouse_sens, _on_sens)
	_add_slider(Lang.t("s_dist"), 6.0, 16.0, 0.5, Settings.camera_dist, _on_dist)
	_add_check(Lang.t("s_invert"), Settings.invert_y, _on_invert)
	_add_check(Lang.t("s_shadows"), Settings.shadows, _on_shadows)
	_add_check(Lang.t("s_glow"), Settings.glow, _on_glow)
	_add_check(Lang.t("s_fps"), Settings.show_fps, _on_fps)
	_add_check(Lang.t("s_dmg"), Settings.show_dmg, _on_dmg)
	_add_msaa()
	_add_fps_limit()
	_add_diff()
	_add_vsync()
	_add_slider(Lang.t("s_fov"), 55.0, 90.0, 1.0, Settings.fov, _on_fov)
	if _include_lang:
		_add_lang()
	var rb := Button.new()
	rb.text = Lang.t("m_reset")
	rb.pressed.connect(_on_reset)
	add_child(rb)


func _add_slider(caption: String, lo: float, hi: float, step: float, val: float, cb: Callable) -> void:
	var l := Label.new()
	l.text = "%s: %.1f" % [caption, val]
	add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float): l.text = "%s: %.1f" % [caption, v]; cb.call(v))
	add_child(s)


func _add_check(caption: String, val: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = caption
	c.button_pressed = val
	c.toggled.connect(func(v: bool): cb.call(v))
	add_child(c)


func _add_selector(caption: String, items: Array, current: int, cb: Callable) -> void:
	var ll := Label.new()
	ll.text = caption
	add_child(ll)
	var sel := OptionButton.new()
	for i in items.size():
		sel.add_item(str(items[i][0]), items[i][1])
	sel.selected = current
	sel.item_selected.connect(cb)
	add_child(sel)


func _add_msaa() -> void:
	_add_selector(Lang.t("s_msaa"),
		[[Lang.t("opt_off"), 0], ["MSAA 2x", 1], ["MSAA 4x", 2], ["MSAA 8x", 3]],
		clampi(Settings.msaa, 0, 3), _on_msaa)


func _add_fps_limit() -> void:
	var items: Array = []
	for v in Settings.FPS_CHOICES:
		items.append([Lang.t("opt_unlimited") if v == 0 else str(v), v])
	_add_selector(Lang.t("s_fps_limit"), items,
		Settings.FPS_CHOICES.find(Settings.max_fps), _on_fps_limit)


func _add_lang() -> void:
	var items: Array = []
	for i in Settings.LANGS.size():
		items.append([Settings.LANG_NAMES[i], i])
	_add_selector(Lang.t("s_lang"), items,
		Settings.LANGS.find(Settings.lang), _on_lang)


func _on_sens(v: float) -> void:
	Settings.mouse_sens = v
	Settings.save()


func _on_dist(v: float) -> void:
	Settings.camera_dist = v
	Settings.save()


func _on_invert(v: bool) -> void:
	Settings.invert_y = v
	Settings.save()


func _on_shadows(v: bool) -> void:
	Settings.shadows = v
	Settings.save()
	Settings.apply_world()


func _on_glow(v: bool) -> void:
	Settings.glow = v
	Settings.save()
	Settings.apply_world()


func _on_fps(v: bool) -> void:
	Settings.show_fps = v
	Settings.save()


func _on_dmg(v: bool) -> void:
	Settings.show_dmg = v
	Settings.save()


func _on_msaa(i: int) -> void:
	Settings.msaa = clampi(i, 0, 3)
	Settings.save()
	Settings.apply_runtime()


func _on_fps_limit(i: int) -> void:
	Settings.max_fps = Settings.FPS_CHOICES[clampi(i, 0, Settings.FPS_CHOICES.size() - 1)]
	Settings.save()
	Settings.apply_runtime()


func _add_diff() -> void:
	_add_selector(Lang.t("s_diff"),
		[[Lang.t("diff_easy"), 0], [Lang.t("diff_normal"), 1], [Lang.t("diff_hard"), 2]],
		clampi(Settings.diff, 0, 2), _on_diff)


func _on_diff(i: int) -> void:
	Settings.diff = clampi(i, 0, 2)
	Settings.save()


func _add_vsync() -> void:
	_add_selector(Lang.t("s_vsync"),
		[[Lang.t("vsync_off"), 0], [Lang.t("vsync_on"), 1], [Lang.t("vsync_adaptive"), 2]],
		clampi(Settings.vsync, 0, 2), _on_vsync)


func _on_vsync(i: int) -> void:
	Settings.vsync = clampi(i, 0, 2)
	Settings.save()
	Settings.apply_runtime()


func _on_fov(v: float) -> void:
	Settings.fov = v
	Settings.save()


func _on_lang(i: int) -> void:
	Settings.lang = Settings.LANGS[clampi(i, 0, Settings.LANGS.size() - 1)]
	Lang.code = Settings.lang
	Settings.save()
	get_tree().reload_current_scene()


func _on_reset() -> void:
	Settings.reset()
	Settings.save()
	Settings.apply_runtime()
	Settings.apply_world()
	build(_include_lang)
