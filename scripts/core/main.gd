extends Node3D
# Точка входу: меню, збирання світу та виклик модулів. Уся логіка - у scripts/.
# Керування: WASD - рух, миша - камера, Space - стрибок, Ctrl - ковзання з гірки,
# Tab - статистика, C - скопіювати код світу, Esc - пауза, R - до меню після смерті.
# Вся зброя - тільки з меню рівнів, випадкових видач немає.

var menu: StartMenu
var world: WorldSeed
var terrain: Terrain
var player: Player
var enemies: Enemies
var elements: Elements
var decor: Decor
var adaptive: Adaptive
var adaptive_mode := false
var weapons: Weapons
var shrines: Shrines
var pickups: Pickups
var trader: Trader
var portal: Portal
var hp_bar: ProgressBar
var hp_label: Label
var xp_bar: ProgressBar
var level_label: Label
var info_label: Label
var gold_label: Label = null
var stats_panel: PanelContainer
var stats_label: Label
var hud_layer: CanvasLayer
var minimap_card: PanelContainer = null
var pause_menu: PauseMenu = null
var boss_card: PanelContainer = null
var boss_bar: ProgressBar = null
var boss_title: Label = null
var banner_label: Label = null
var banner_t := 0.0
var vignette: ColorRect = null
var last_hp := 0.0
var flash := 0.0
var slowmo_t := 0.0
var hint_slide_done := false
var hint_shrine_done := false
var level_menu: LevelUpMenu = null
var choosing := false
var level_opts: Array = []
var started := false
var mode_label := ""
var elapsed := 0.0
var level := 1     # рівень гравця (XP за вбивства, вибір нагороди в меню)
var xp := 0
var gold := 0      # монети з ворогів (торговець)
var depth := 1     # поверх: портал вниз поглиблює і злить ворогів
var copied_t := 0.0
var recorded := false
var best_before := 0
var hud_t := 0.0   # HUD оновлюється 5 разів на секунду, а не щокадру
var event_t := 0.0   # таймер випадкових подій
var pending_booms: Array = []   # відкладені вибухи метеоритного дощу: {pos, t, fx}


func _ready() -> void:
	Engine.time_scale = 1.0
	Settings.load_all()
	Settings.apply_runtime()
	_setup_environment()
	menu = StartMenu.new()
	add_child(menu)
	menu.start_requested.connect(_on_start_requested)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_start_requested(seed_value: int, mode: String) -> void:
	adaptive_mode = menu.is_adaptive()
	menu.queue_free()
	world = WorldSeed.new(seed_value)
	mode_label = mode + (Lang.t("mode_adaptive") if adaptive_mode else "")
	_build_world()
	started = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_world() -> void:
	Util.warmup()   # прогріти shared-меші/матеріали до першого спавна, щоб не фризило в кадрі
	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup(world.value)

	decor = Decor.new()
	add_child(decor)
	decor.setup(terrain, world.value)

	player = Player.new()
	add_child(player)
	player.setup(terrain, decor.statics_grid, decor.lava_pools)
	var cls: Dictionary = GameData.CLASS[Settings.cls]
	player.max_hp = float(cls["hp"])
	player.hp = float(cls["hp"])
	player.speed_mult = float(cls["spd"])
	last_hp = player.max_hp

	enemies = Enemies.new()
	add_child(enemies)
	enemies.setup(terrain, player, decor.statics_grid, decor.lava_pools)
	enemies.rng = world.spawn_rng
	enemies.enemy_killed.connect(_on_enemy_killed)
	enemies.boss_killed.connect(_on_boss_killed)
	enemies.boss_spawned.connect(_on_boss_spawned)
	if adaptive_mode:
		adaptive = Adaptive.new()
		enemies.adaptive = adaptive

	elements = Elements.new()
	add_child(elements)
	elements.setup(enemies.list)
	enemies.elements = elements
	Effects.reset_stats()

	weapons = Weapons.new()
	add_child(weapons)
	weapons.setup(terrain, player, enemies)
	weapons.rng = world.loot_rng
	var cw: Array = GameData.CLASS[Settings.cls]["w"]
	weapons.add_weapon(cw[0], cw[1], cw[2])   # стартовий набір класу

	shrines = Shrines.new()
	add_child(shrines)
	shrines.setup(terrain, world.value)
	shrines.shrine_used.connect(_on_shrine)

	pickups = Pickups.new()
	add_child(pickups)
	pickups.setup(terrain)
	pickups.picked.connect(_on_pickup)
	enemies.drops = pickups

	trader = Trader.new()
	add_child(trader)
	trader.setup(terrain, world.value)
	trader.trade_requested.connect(_on_trade)

	portal = Portal.new()
	add_child(portal)
	portal.descended.connect(_on_descend)

	event_t = float(GameData.EVENT["first"])
	_setup_hud()
	_setup_minimap()


func _process(delta: float) -> void:
	if not started:
		return
	if slowmo_t > 0.0:
		slowmo_t -= delta
		if slowmo_t <= 0.0:
			Engine.time_scale = 1.0
	copied_t = maxf(copied_t - delta, 0.0)
	if player.is_dead():
		if not recorded:
			recorded = true
			best_before = RunHistory.best_kills(world.value)
			RunHistory.record(world.value, mode_label, enemies.kills, elapsed)
			RunHistory.record_run(enemies.kills, elapsed, level)
			_show_death_panel()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.tick_dead(delta)
		return
	elapsed += delta
	player.tick(delta)
	enemies.tick(delta)
	elements.tick(delta)
	decor.tick(delta)
	shrines.tick(delta, player.position)
	pickups.tick(delta, player.position)
	trader.tick(delta, player.position, gold)
	portal.tick(delta, player.position)
	_update_vignette(delta)
	_update_hints()
	if adaptive != null:
		adaptive.tick(delta)
	weapons.tick(delta)
	if banner_t > 0.0:
		banner_t -= delta
		var a := clampf(banner_t / 2.5, 0.0, 1.0)
		banner_label.modulate = Color(1, 1, 1, a)
		if banner_t <= 0.0:
			banner_label.visible = false
	event_t -= delta
	if event_t <= 0.0:
		_fire_event()
	for i in range(pending_booms.size() - 1, -1, -1):
		var pb: Dictionary = pending_booms[i]
		pb["t"] = float(pb["t"]) - delta
		if float(pb["t"]) <= 0.0:
			weapons.detonate(pb["pos"], pb["fx"], float(GameData.EVENT["meteor_dmg"]), float(GameData.EVENT["meteor_radius"]))
			pending_booms.remove_at(i)
	hud_t += delta
	if hud_t >= 0.2:
		hud_t = 0.0
		_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not started:
		return
	if event is InputEventMouseMotion:
		player.handle_mouse(event)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if started and not player.is_dead() and not choosing:
				_toggle_pause()
		elif event.keycode == KEY_R and player.is_dead():
			Engine.time_scale = 1.0
			get_tree().paused = false
			get_tree().reload_current_scene()
		elif event.keycode == KEY_C:
			DisplayServer.clipboard_set(world.code())
			copied_t = 2.0
		elif event.keycode == KEY_TAB:
			stats_panel.visible = not stats_panel.visible


func _toggle_pause() -> void:
	if pause_menu == null:
		pause_menu = PauseMenu.new()
		add_child(pause_menu)
		pause_menu.resume_requested.connect(_toggle_pause)
		pause_menu.quit_requested.connect(_quit_to_menu)
	if get_tree().paused:
		pause_menu.visible = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		pause_menu.visible = true
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _quit_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func _show_death_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.02, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.06, 0.06, 0.97)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 28.0
	sb.content_margin_right = 28.0
	sb.content_margin_top = 24.0
	sb.content_margin_bottom = 24.0
	sb.border_color = Color(0.9, 0.3, 0.3, 0.6)
	sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var title := Label.new()
	title.text = Lang.t("d_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	box.add_child(title)
	var stats := Label.new()
	stats.text = _game_over_text()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats)
	var b := Button.new()
	b.text = Lang.t("d_menu")
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(_quit_to_menu)
	box.add_child(b)


# XP за вбивства + золото; поріг XP - у _xp_need.
func _on_enemy_killed(_total: int, g: int) -> void:
	_gain_xp(1)
	gold += g


# Червона виньєтка: спалах при отриманні шкоди + пульс на низькому HP.
func _update_vignette(delta: float) -> void:
	if player.hp < last_hp:
		flash = 0.45
	last_hp = player.hp
	flash = maxf(flash - delta * 1.5, 0.0)
	var frac := player.hp / player.max_hp
	var low := 0.0
	if frac < 0.4:
		low = (0.4 - frac) / 0.4 * (0.22 + 0.08 * sin(elapsed * 6.0))
	var c := vignette.color
	c.a = minf(maxf(low, flash), 0.5)
	vignette.color = c


# Контекстні підказки для новачків (по разу за забіг, поверх банерів не лізуть).
func _update_hints() -> void:
	if banner_t > 0.0:
		return
	if not hint_slide_done and elapsed > 10.0 and player.slope_now > 0.35 and not player.sliding:
		hint_slide_done = true
		_show_banner(Lang.t("hint_slide"))
		return
	if not hint_shrine_done:
		for s in shrines.list:
			if not s["used"] and player.position.distance_squared_to(s["pos"]) < 144.0:
				hint_shrine_done = true
				_show_banner(Lang.t("hint_shrine"))
				return


func _on_boss_killed(pos: Vector3) -> void:
	_gain_xp(int(GameData.RELIC["boss_xp"]))
	Engine.time_scale = 0.3   # слоу-мо на вбивство боса (~0.6 с реального часу)
	slowmo_t = 0.2
	portal.open_at(pos)


func _on_boss_spawned() -> void:
	_show_banner(Lang.t("boss_warn"))


func _gain_xp(n: int) -> void:
	xp += n
	if not choosing and not player.is_dead() and xp >= _xp_need():
		_open_level_menu()


func _on_pickup(kind: String, pos: Vector3) -> void:
	var p: Dictionary = GameData.PICKUP
	match kind:
		"heart":
			player.hp = minf(player.hp + float(p["heart_heal"]), player.max_hp)
			Fx.burst(self, pos, Color(0.3, 1.0, 0.4), 10, 4.0)
			elements.popup_at(pos + Vector3(0, 0.8, 0), Lang.t("pick_heart"), Color(0.3, 1.0, 0.4))
		"magnet":
			pickups.magnetize()
			Fx.burst(self, pos, Color(0.4, 0.9, 1.0), 12, 5.0)
			elements.popup_at(pos + Vector3(0, 0.8, 0), Lang.t("pick_magnet"), Color(0.4, 0.9, 1.0))
		"bomb":
			weapons.detonate(player.position + Vector3(0, 0.8, 0), "fire", float(p["bomb_dmg"]), float(p["bomb_radius"]))
			elements.popup_at(pos + Vector3(0, 0.8, 0), Lang.t("pick_bomb"), Color(1.0, 0.6, 0.2))
	_update_hud()


# Спуск порталом: той же сід, поверх глибше, вороги зліші.
# Гравець, зброя, рівні і статистика лишаються; світ перезбирається.
func _on_descend() -> void:
	depth += 1
	var keep_kills := enemies.kills
	var keep_dealt := enemies.dealt
	var keep_fx := enemies.dealt_fx.duplicate()
	terrain.queue_free()
	decor.queue_free()
	enemies.queue_free()
	elements.queue_free()
	shrines.queue_free()
	pickups.queue_free()
	trader.queue_free()
	portal.queue_free()
	minimap_card.queue_free()
	pending_booms.clear()
	weapons.clear_field()
	player.position = Vector3(0, 0, 0)
	player.vel_y = 0.0

	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup(world.value)

	decor = Decor.new()
	add_child(decor)
	decor.setup(terrain, world.value)

	player.position = Vector3(0, terrain.height(0, 0), 0)

	enemies = Enemies.new()
	add_child(enemies)
	enemies.setup(terrain, player, decor.statics_grid, decor.lava_pools)
	enemies.rng = world.spawn_rng
	enemies.depth = depth
	enemies.kills = keep_kills
	enemies.dealt = keep_dealt
	enemies.dealt_fx = keep_fx
	enemies.enemy_killed.connect(_on_enemy_killed)
	enemies.boss_killed.connect(_on_boss_killed)
	enemies.boss_spawned.connect(_on_boss_spawned)
	enemies.adaptive = adaptive

	elements = Elements.new()
	add_child(elements)
	elements.setup(enemies.list)
	enemies.elements = elements

	shrines = Shrines.new()
	add_child(shrines)
	shrines.setup(terrain, world.value)
	shrines.shrine_used.connect(_on_shrine)

	pickups = Pickups.new()
	add_child(pickups)
	pickups.setup(terrain)
	pickups.picked.connect(_on_pickup)
	enemies.drops = pickups

	trader = Trader.new()
	add_child(trader)
	trader.setup(terrain, world.value)
	trader.trade_requested.connect(_on_trade)

	portal = Portal.new()
	add_child(portal)
	portal.descended.connect(_on_descend)

	event_t = randf_range(float(GameData.EVENT["min"]), float(GameData.EVENT["max"]))
	_show_banner(Lang.t("depth_banner") % depth)
	_setup_minimap()
	_update_hud()


func _on_trade(pos: Vector3) -> void:
	var cost := int(GameData.TRADER["cost"])
	if gold < cost:
		return
	gold -= cost
	var opts := _level_options()
	if opts.is_empty():
		return
	_apply_level_pick(opts[0])
	Fx.burst(self, pos, Color(1.0, 0.85, 0.4), 20, 6.0)
	_update_hud()
	if not choosing and xp >= _xp_need():
		_open_level_menu()


func _on_shrine(pos: Vector3) -> void:
	var opts := _level_options()
	if opts.is_empty():
		return
	_apply_level_pick(opts[0])
	Fx.burst(self, pos, Color(0.5, 0.95, 1.0), 24, 6.0)
	elements.popup_at(pos + Vector3(0, 1.0, 0), Lang.t("shrine_pop"), Color(0.5, 0.95, 1.0))
	_update_hud()
	if not choosing and xp >= _xp_need():
		_open_level_menu()


# XP для наступного рівня: росте з кожним рівнем, щоб темп нагород не зривався.
func _xp_need() -> int:
	return 6 + (level - 1) * 4


func _show_banner(text: String) -> void:
	banner_label.text = text
	banner_label.modulate = Color(1, 1, 1, 1)
	banner_label.visible = true
	banner_t = 2.5


# Випадкова подія: метеорити, зграя або золота лихоманка. Далі таймер по новій.
func _fire_event() -> void:
	var ev: Dictionary = GameData.EVENT
	event_t = randf_range(float(ev["min"]), float(ev["max"]))
	var roll := randf()
	if roll < 0.34:
		_show_banner(Lang.t("evt_meteors"))
		var fxs := ["fire", "shock", "force"]
		for i in int(ev["meteors"]):
			var a := randf() * TAU
			var r := randf_range(5.0, 14.0)
			var pos := player.position + Vector3(cos(a) * r, 0, sin(a) * r)
			pos.y = terrain.height(pos.x, pos.z) + 0.5
			pending_booms.append({"pos": pos, "t": randf_range(0.8, 2.4), "fx": fxs[randi() % fxs.size()]})
	elif roll < 0.67:
		_show_banner(Lang.t("evt_pack"))
		enemies.spawn_pack("runner", int(ev["pack"]))
	else:
		_show_banner(Lang.t("evt_gold"))
		var kinds := ["heart", "heart", "bomb", "heart", "magnet"]
		for i in int(ev["gold"]):
			var a := randf() * TAU
			var r := randf_range(3.0, 8.0)
			var pos := player.position + Vector3(cos(a) * r, 0, sin(a) * r)
			pickups.spawn_at(kinds[randi() % kinds.size()], pos)


func _setup_environment() -> void:
	# основне сонце: тепле, з м'якими тінями
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.25
	sun.shadow_enabled = Settings.shadows
	sun.directional_shadow_max_distance = 160.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_blend_splits = true   # м'які переходи каскадів тіней
	add_child(sun)

	# підсвітка: холодний fill-light знизу для глибини
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 150, 0)
	fill.light_color = Color(0.6, 0.72, 0.92)
	fill.light_energy = 0.3
	fill.shadow_enabled = false
	add_child(fill)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.88)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.95)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.62, 0.7, 0.65)
	sky_mat.ground_bottom_color = Color(0.2, 0.24, 0.26)
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 35.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	# bloom/glow: кілька шарів для «магічного» сяйва
	env.glow_enabled = Settings.glow
	env.glow_intensity = 0.65
	env.glow_strength = 1.05
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.set_glow_level(0, true)    # дрібна деталь
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, true)    # широке сяйво
	env.set_glow_level(4, false)

	# SSAO: контактні тіні між об'єктами
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.8
	env.ssao_power = 1.5
	env.ssao_light_affect = 0.3

	# SSIL: непряме освітлення
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.6

	# колірна корекція
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.04
	env.adjustment_brightness = 1.02

	# туман: глибинний + повітряний для атмосфери
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.68, 0.78, 0.9)
	env.fog_light_energy = 1.1
	env.fog_sun_scatter = 0.3   # сонце «просвічує» крізь туман
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.4
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 200.0

	# волюметричний туман (Forward+ renderer)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.95)
	env.volumetric_fog_emission = Color(0.1, 0.12, 0.18)
	env.volumetric_fog_emission_energy = 0.5
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_gi_inject = 0.5
	env.volumetric_fog_sky_affect = 0.3

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	Settings.bind_world(sun, env)
	Settings.apply_world()


func _setup_hud() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	hud_layer = ui
	# червона виньєтка шкоди (під текстом, кліки крізь неї)
	vignette = ColorRect.new()
	vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(vignette)
	# компактна панель: рівень + XP, HP, вбивства/час
	var panel := _card_panel(Vector2(12, 12))
	ui.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 8)
	vbox.add_child(lvl_row)
	level_label = Label.new()
	level_label.add_theme_font_size_override("font_size", 15)
	lvl_row.add_child(level_label)
	xp_bar = _make_bar(lvl_row, Color(0.95, 0.75, 0.25), 150, 10)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	vbox.add_child(hp_row)
	hp_bar = _make_bar(hp_row, Color(0.85, 0.25, 0.25), 150, 10)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 13)
	hp_row.add_child(hp_label)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(info_label)
	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 13)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(gold_label)
	var hint := Label.new()
	hint.text = Lang.t("hud_tab")
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)
	# деталі (біом, зброя, код) - окремо, щоб не займати екран
	stats_panel = _card_panel(Vector2(12, 148))
	stats_panel.visible = false
	ui.add_child(stats_panel)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_panel.add_child(stats_label)
	# полоса босса зверху по центру (показується, поки бос живий)
	boss_card = _card_panel(Vector2.ZERO)
	boss_card.anchor_left = 0.5
	boss_card.anchor_right = 0.5
	boss_card.offset_left = -150.0
	boss_card.offset_right = 150.0
	boss_card.offset_top = 12.0
	boss_card.offset_bottom = 64.0
	boss_card.visible = false
	ui.add_child(boss_card)
	var bvb := VBoxContainer.new()
	bvb.add_theme_constant_override("separation", 4)
	boss_card.add_child(bvb)
	boss_title = Label.new()
	boss_title.text = Lang.t("boss_name")
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_title.add_theme_font_size_override("font_size", 15)
	boss_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	bvb.add_child(boss_title)
	boss_bar = _make_bar(bvb, Color(0.9, 0.2, 0.2), 280, 12)
	# банер-подія по центру (попередження про боса)
	banner_label = Label.new()
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 34)
	banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	banner_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.position = Vector2(-300, 120)
	banner_label.custom_minimum_size = Vector2(600, 0)
	banner_label.visible = false
	ui.add_child(banner_label)


func _setup_minimap() -> void:
	var card := _card_panel(Vector2.ZERO)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -204.0
	card.offset_top = 12.0
	card.offset_right = -12.0
	card.offset_bottom = 204.0
	hud_layer.add_child(card)
	var mm := Minimap.new()
	card.add_child(mm)
	mm.setup(terrain, player, enemies, shrines, trader, portal, world.value)
	minimap_card = card

func _card_panel(pos: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.6)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _make_bar(parent: Control, fill: Color, w := 180.0, h := 12.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(w, h)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fg)
	parent.add_child(bar)
	return bar


func _update_hud() -> void:
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.hp
	hp_label.text = "%d/%d" % [int(player.hp), int(player.max_hp)]
	xp_bar.max_value = _xp_need()
	xp_bar.value = xp
	level_label.text = Lang.t("hud_level") % level
	var combo_txt := ""
	if elements.combo >= 2:
		combo_txt = " · " + Lang.t("hud_combo") % elements.combo
	var slide_txt := ""
	if player.sliding:
		slide_txt = " · " + Lang.t("hud_slide")
	info_label.text = (Lang.t("hud_info") % [enemies.kills, _fmt_time(elapsed)]) + slide_txt + combo_txt
	gold_label.text = "%s · %s" % [Lang.t("hud_gold") % gold, Lang.t("d_depth") % depth]
	var code_txt := Lang.t("hud_copied") if copied_t > 0.0 else Lang.t("hud_copy")
	var lines: Array = [
		"%s   %s: %s   %s" % [mode_label, Lang.t("w_code"), world.code(), code_txt],
		Lang.t("hud_xp") % [xp, _xp_need(), weapons.global_mult, player.speed_mult],
		Lang.t("hud_diff") % _diff_name(),
	]
	var b: Dictionary = GameData.BIOME[terrain.biome_at(player.position.x, player.position.z)]
	lines.append(Lang.t("hud_biome") % [Lang.t(b["name_id"]), b["fire"], b["ice"], b["poison"], b["speed"]])
	if adaptive != null:
		lines.append(adaptive.hud_line())
	if Settings.show_fps:
		lines.append("FPS: %d" % Engine.get_frames_per_second())
	if int(player.relics["crit"]) + int(player.relics["vamp"]) + int(player.relics["thorns"]) > 0:
		lines.append(Lang.t("hud_relics") % [int(player.crit_ch * 100.0), int(player.lifesteal), int(player.thorns)])
	for n in weapons.names():
		lines.append("• " + n)
	stats_label.text = "\n".join(lines)
	var boss = null
	for e in enemies.list:
		if str(e.get("etype", "")) == "boss":
			boss = e
			break
	if boss != null:
		boss_card.visible = true
		boss_bar.max_value = float(boss["hp_max"])
		boss_bar.value = maxf(float(boss["hp"]), 0.0)
	else:
		boss_card.visible = false


func _fmt_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func _game_over_text() -> String:
	var lines: Array = [
		Lang.t("d_over"),
		Lang.t("d_stats") % [level, enemies.kills, _fmt_time(elapsed)],
		Lang.t("hud_diff") % _diff_name(),
		Lang.t("d_dmg") % int(enemies.dealt + Effects.extra_dealt),
		Lang.t("d_gold") % gold,
		Lang.t("d_depth") % depth,
		Lang.t("d_combo") % elements.max_combo,
		Lang.t("d_fav") % _fav_element(),
	]
	if best_before > 0:
		lines.append(Lang.t("d_best") % maxi(best_before, enemies.kills))
	lines.append((Lang.t("d_code") % world.code()) + "   " + (Lang.t("hud_copied") if copied_t > 0.0 else Lang.t("hud_copy")))
	return "\n".join(lines)


func _diff_name() -> String:
	return [Lang.t("diff_easy"), Lang.t("diff_normal"), Lang.t("diff_hard")][clampi(Settings.diff, 0, 2)]


func _fav_element() -> String:
	var merged := {}
	for fx in enemies.dealt_fx:
		merged[fx] = float(enemies.dealt_fx[fx])
	for fx in Effects.extra_fx:
		merged[fx] = float(merged.get(fx, 0.0)) + float(Effects.extra_fx[fx])
	var best_fx := ""
	var best_dmg := 0.0
	for fx in merged:
		if float(merged[fx]) > best_dmg:
			best_dmg = float(merged[fx])
			best_fx = str(fx)
	if best_fx == "":
		return "—"
	if best_fx == "none":
		return Lang.t("a_pure")
	return Lang.t(GameData.EFFECT[best_fx]["name_id"])


# ---------- Рівні ----------

func _open_level_menu() -> void:
	choosing = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	level_opts = _level_options()
	level_menu = LevelUpMenu.new()
	add_child(level_menu)
	level_menu.show_choices(level + 1, level_opts)
	level_menu.picked.connect(_on_level_pick)
	get_tree().paused = true


func _on_level_pick(i: int) -> void:
	_apply_level_pick(level_opts[i])
	xp -= _xp_need()
	level += 1
	Fx.burst(self, player.position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.3), 24, 6.0)
	level_menu.queue_free()
	level_menu = null
	choosing = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hud()
	if xp >= _xp_need():
		_open_level_menu()


# 3 різні варіанти: зброя (якщо є куди) + характеристики. Зброя не ламається:
# нова - тільки у вільний слот, покращення - тільки не в максимум.
func _level_options() -> Array:
	var opts: Array = []
	if weapons.list.size() < GameData.MAX_WEAPONS:
		var c := weapons.roll_combo()
		opts.append({"kind": "new", "combo": c, "title": Lang.t("o_new_t"), "desc": weapons.combo_name(c)})
	var up = weapons.random_upgradable()
	if up != null:
		opts.append({"kind": "up", "w": up, "title": Lang.t("o_up_t"),
			"desc": Lang.t("o_up_d") % [weapons.weapon_name(up), up["lvl"] + 1]})
	opts.append({"kind": "hp", "title": Lang.t("o_hp_t"), "desc": Lang.t("o_hp_d")})
	opts.append({"kind": "dmg", "title": Lang.t("o_dmg_t"), "desc": Lang.t("o_dmg_d")})
	opts.append({"kind": "spd", "title": Lang.t("o_spd_t"), "desc": Lang.t("o_spd_d")})
	opts.append({"kind": "regen", "title": Lang.t("o_regen_t"), "desc": Lang.t("o_regen_d")})
	var rc: Dictionary = GameData.RELIC
	if int(player.relics["crit"]) < int(rc["crit_max"]):
		opts.append({"kind": "rel_crit", "title": Lang.t("o_rel_crit_t"), "desc": Lang.t("o_rel_crit_d")})
	if int(player.relics["vamp"]) < int(rc["vamp_max"]):
		opts.append({"kind": "rel_vamp", "title": Lang.t("o_rel_vamp_t"), "desc": Lang.t("o_rel_vamp_d")})
	if int(player.relics["thorns"]) < int(rc["thorns_max"]):
		opts.append({"kind": "rel_thorns", "title": Lang.t("o_rel_thorns_t"), "desc": Lang.t("o_rel_thorns_d")})
	var pair := weapons.fusion_pair()
	if not pair.is_empty():
		opts.append({"kind": "evo", "w1": pair[0], "w2": pair[1],
			"title": Lang.t("o_evo_t"),
			"desc": Lang.t("o_evo_d") % [weapons.weapon_name(pair[0]), weapons.weapon_name(pair[1])]})
	opts.shuffle()
	return opts.slice(0, 3)


func _apply_level_pick(o: Dictionary) -> void:
	match o["kind"]:
		"new":
			var c: Dictionary = o["combo"]
			weapons.add_weapon(c["d"], c["p"], c["f"])
		"up":
			weapons.level_up_weapon(o["w"])
		"hp":
			player.max_hp += 25.0
			player.hp = minf(player.hp + 50.0, player.max_hp)
		"dmg":
			weapons.global_mult *= 1.1
		"spd":
			player.speed_mult *= 1.08
		"regen":
			player.regen_mult += 0.6
		"rel_crit":
			player.crit_ch += float(GameData.RELIC["crit_step"])
			player.relics["crit"] = int(player.relics["crit"]) + 1
		"rel_vamp":
			player.lifesteal += float(GameData.RELIC["vamp_step"])
			player.relics["vamp"] = int(player.relics["vamp"]) + 1
		"rel_thorns":
			player.thorns += float(GameData.RELIC["thorns_step"])
			player.relics["thorns"] = int(player.relics["thorns"]) + 1
		"evo":
			weapons.evolve(o["w1"], o["w2"])
