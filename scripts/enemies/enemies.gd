class_name Enemies
extends Node3D
# Вороги: спавн, рух, статуси (див. effects.gd), смерть. Числа - у data.gd (ENEMY).
# Модель - low-poly гоблін, збирається в _build_creature (ноги/лапи анімуються в _move).

signal enemy_killed(total_kills: int)
signal boss_killed
signal boss_spawned

var terrain: Terrain
var player: Player
var col_grid := {}
var list: Array = []   # {node, hp, burn, slow, poison, pstack, stun, mark, push, speed_mult, type_mult, tint, base, last_tint, mat, darkmat, hit_cd, react_cd, thorn_cd, biome, resist, etype, ...}
var elements: Elements   # задається з main.gd
var adaptive: Adaptive   # null, якщо режим адаптації вимкнено
var rng := RandomNumberGenerator.new()   # seed-генератор спавну (див. world_seed.gd)
var kills := 0
var spawned := 0
var spawn_t := 0.0
var dealt := 0.0        # всього шкоди за забіг (для статистики)
var dealt_fx := {}      # шкода по стихіях (для улюбленої)
var drops: Pickups = null   # підбори: шанс дропу при смерті (ставить main.gd)
var eshots: Array = []  # снаряди плювальників: {node, dir, life}


func setup(t: Terrain, p: Player, g: Dictionary) -> void:
	terrain = t
	player = p
	col_grid = g


func tick(delta: float) -> void:
	_spawn(delta)
	_move(delta)
	_update_shots(delta)
	_cleanup()


# Найближчий ворог у радіусі від точки (або null).
func nearest(pos: Vector3, radius: float):
	var best = null
	var best_d := radius * radius
	for e in list:
		var d: float = e["node"].position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return best


# Влучання: шкода + ефект. origin - звідки прийшов удар (для поштовху).
func hit(e: Dictionary, dmg: float, fx: String, origin: Vector3) -> void:
	dmg *= Ground.high_ground_mult(terrain, player.position, e["node"].position)
	if adaptive != null:
		adaptive.record(fx, dmg)
	dmg *= 1.0 - float(e["resist"].get(fx, 0.0))   # стійкість до цього типу шкоди
	if float(e.get("mark", 0.0)) > 0.0:
		dmg *= float(GameData.EFFECT["mark"]["bonus"])   # мічений отримує більше всієї шкоди
	if player != null and float(player.crit_ch) > 0.0 and randf() < float(player.crit_ch):
		dmg *= 2.0   # реліквія криту
		if elements != null:
			elements.popup_at(e["node"].position + Vector3(0, 1.6, 0), Lang.t("crit_pop"), Color(1.0, 0.85, 0.2))
	e["hp"] -= dmg
	e["squash"] = 1.0
	dealt += dmg
	dealt_fx[fx] = float(dealt_fx.get(fx, 0.0)) + dmg
	if elements != null and Settings.show_dmg and dmg >= 1.0:
		var jitter := Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3))
		elements.popup_at(e["node"].position + jitter, "%d" % int(dmg), Color(1, 1, 1), false)
	if elements != null:
		elements.react(e, fx, dmg)
	Effects.apply(list, e, fx, dmg, origin)


func _spawn(delta: float) -> void:
	spawn_t -= delta
	if spawn_t > 0.0:
		return
	var start: float = GameData.ENEMY["spawn_start"]
	var step: float = GameData.ENEMY["spawn_step"]
	var floor_t: float = GameData.ENEMY["spawn_min"]
	spawn_t = maxf(floor_t, start - kills * step)
	if list.size() >= int(GameData.ENEMY["max_alive"]):
		spawn_t = 0.5   # ліміт живих: зачекати, а не штампувати в нікуди
		return

	var a := rng.randf() * TAU
	var pos := player.position + Vector3(cos(a), 0, sin(a)) * 30.0
	var lim := terrain.limit()
	pos.x = clamp(pos.x, -lim, lim)
	pos.z = clamp(pos.z, -lim, lim)
	_spawn_one(_pick_type(), pos)


# Пак примусово: стая одного типу кільцем навколо гравця (подія).
func spawn_pack(etype: String, count: int) -> void:
	var lim := terrain.limit()
	for i in count:
		if list.size() >= int(GameData.ENEMY["max_alive"]):
			return
		var a := TAU * i / count
		var pos := player.position + Vector3(cos(a), 0, sin(a)) * 20.0
		pos.x = clamp(pos.x, -lim, lim)
		pos.z = clamp(pos.z, -lim, lim)
		_spawn_one(etype, pos)


func _spawn_one(etype: String, pos: Vector3) -> void:
	var hp_max: float = float(GameData.ENEMY["hp"]) * (1.0 + float(GameData.ENEMY["hp_per_kill"]) * kills)
	hp_max *= float(GameData.DIFF["ehp"][Settings.diff])
	var tcfg: Dictionary = GameData.BOSS if etype == "boss" else GameData.ENEMY_TYPES[etype]
	hp_max *= float(tcfg["hp"])
	var built := _build_creature(etype)
	var n: Node3D = built["root"]
	n.position = pos
	var sc: float = float(tcfg["scale"]) * rng.randf_range(0.9, 1.1)
	n.scale = Vector3.ONE * sc
	add_child(n)
	spawned += 1
	var res: Dictionary = adaptive.resists() if adaptive != null else {}
	_add_badge(n, res)
	if etype == "boss":
		boss_spawned.emit()
	list.append({
		"node": n, "hp": hp_max, "hp_max": hp_max, "hit_cd": 0.0, "react_cd": 0.0, "thorn_cd": 0.0,
		"shot_cd": rng.randf_range(1.0, 2.0),
		"burn": 0.0, "slow": 0.0, "poison": 0.0, "pstack": 0, "stun": 0.0, "mark": 0.0,
		"push": Vector3.ZERO, "speed_mult": 1.0, "type_mult": float(tcfg["spd"]),
		"tint": tcfg["color"], "base": tcfg["color"], "etype": etype, "hit_r": 1.2 * sc,
		"last_tint": Color(-1, -1, -1, -1), "mat": built["mat"], "darkmat": built["darkmat"],
		"biome": terrain.biome_at(pos.x, pos.z), "resist": res,
		"rig": built["rig"], "leg_l": built["leg_l"], "leg_r": built["leg_r"],
		"arm_l": built["arm_l"], "arm_r": built["arm_r"],
		"phase": rng.randf() * TAU, "squash": 0.0,
	})


# Рулетка типу: бос кожен BOSS_EVERY-й спавн, інші - за вагою серед відкритих.
func _pick_type() -> String:
	if (spawned + 1) % int(GameData.BOSS_EVERY) == 0:
		return "boss"
	var pool: Array = []
	var total := 0
	for key in GameData.ENEMY_TYPES:
		var t: Dictionary = GameData.ENEMY_TYPES[key]
		if kills < int(t["need"]):
			continue
		pool.append([key, int(t["weight"])])
		total += int(t["weight"])
	if pool.is_empty():
		return "grunt"
	var roll := rng.randi() % total
	for p in pool:
		roll -= p[1]
		if roll < 0:
			return p[0]
	return "grunt"


func _move(delta: float) -> void:
	var contact := 0.0
	var base_speed: float = GameData.ENEMY["speed"]
	var lim := terrain.limit()
	for e in list:
		var n: Node3D = e["node"]
		e["biome"] = terrain.biome_at(n.position.x, n.position.z)
		if e["biome"] == "volcano":
			var ldot := float(GameData.LAVA_DPS) * delta
			e["hp"] -= ldot
			Effects.track(ldot, "fire")
		Effects.tick(e, delta)
		e["hit_cd"] = max(e["hit_cd"] - delta, 0.0)
		e["thorn_cd"] = maxf(float(e["thorn_cd"]) - delta, 0.0)
		# статусні кольори: пишемо в 2 спільні матеріали моба і тільки коли колір змінився
		if e["tint"] != e["last_tint"]:
			e["last_tint"] = e["tint"]
			(e["mat"] as StandardMaterial3D).albedo_color = e["tint"]
			(e["darkmat"] as StandardMaterial3D).albedo_color = (e["tint"] as Color).darkened(0.45)
		# сплющування при влучанні
		e["squash"] = maxf(float(e["squash"]) - delta * 5.0, 0.0)
		var sq: float = e["squash"]
		var rig: Node3D = e["rig"]
		rig.scale = Vector3(1.0 + 0.3 * sq, 1.0 - 0.35 * sq, 1.0 + 0.3 * sq)

		var to: Vector3 = player.position - n.position
		to.y = 0.0
		var dist2 := to.x * to.x + to.z * to.z
		if str(e["etype"]) == "spitter":
			contact += _spitter_move(e, n, to, dist2, delta, base_speed)
		elif dist2 > 1.69:
			var dir := to.normalized()
			n.position += dir * base_speed * float(e["type_mult"]) * float(e["speed_mult"]) * Ground.speed_mult(terrain, n.position, dir) * delta
			n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), minf(delta * 8.0, 1.0))
		else:
			contact += float(GameData.ENEMY["contact_dps"]) * float(GameData.DIFF["edmg"][Settings.diff])
			if dist2 > 0.0001:
				n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(delta * 8.0, 1.0))
			if player != null and float(player.thorns) > 0.0 and float(e["thorn_cd"]) <= 0.0:
				e["thorn_cd"] = 0.6
				hit(e, float(player.thorns), "none", player.position)

		# семенящая походка: ноги й лапи качаються, тіло підстрибує
		e["phase"] = float(e["phase"]) + delta * 9.0
		var sw := sin(float(e["phase"]))
		(e["leg_l"] as Node3D).rotation.x = sw * 0.6
		(e["leg_r"] as Node3D).rotation.x = -sw * 0.6
		(e["arm_l"] as Node3D).rotation.x = -sw * 0.4
		(e["arm_r"] as Node3D).rotation.x = sw * 0.4
		rig.position.y = absf(cos(float(e["phase"]))) * 0.05

		# поштовх (ефект "force") згасає за ~0.33 с
		var push: Vector3 = e["push"]
		if push != Vector3.ZERO:
			n.position += push * delta
			e["push"] = push.move_toward(Vector3.ZERO, 36.0 * delta)

		n.position.x = clamp(n.position.x, -lim, lim)
		n.position.z = clamp(n.position.z, -lim, lim)
		var cp := Ground.collide_grid(n.position, 0.45, col_grid)
		n.position.x = cp.x
		n.position.z = cp.z
		n.position.y = terrain.height(n.position.x, n.position.z) + 0.5

	_separate()

	if contact > 0.0:
		player.damage(minf(contact, float(GameData.ENEMY["contact_cap"])) * delta)


# Розштовхування: вороги не злипаються в одну купу.
# O(n²) по парах, але тільки квадрати дистанцій; MAX_ALIVE обмежує зверху.
func _separate() -> void:
	var n := list.size()
	for i in n:
		var a: Dictionary = list[i]
		var na: Node3D = a["node"]
		for j in range(i + 1, n):
			var b: Dictionary = list[j]
			var nb: Node3D = b["node"]
			var dx := na.position.x - nb.position.x
			var dz := na.position.z - nb.position.z
			var rr := 0.35 * (na.scale.x + nb.scale.x)
			var d2 := dx * dx + dz * dz
			if d2 < rr * rr and d2 > 0.000001:
				var d := sqrt(d2)
				var push := (rr - d) / d * 0.5
				na.position.x += dx * push
				na.position.z += dz * push
				nb.position.x -= dx * push
				nb.position.z -= dz * push


# Плювальник: тримає 10-14 м (підходить здалеку, тікає зблизька, в кільці стрейфиться),
# стріляє отруйними плювками. Повертає контактну шкоду за кадр.
func _spitter_move(e: Dictionary, n: Node3D, to: Vector3, dist2: float, delta: float, base_speed: float) -> float:
	var contact := 0.0
	var dist := sqrt(maxf(dist2, 0.0001))
	var dir := Vector3.ZERO
	if dist > 0.01:
		dir = to / dist
		n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), minf(delta * 8.0, 1.0))
	if dist2 < 1.69:
		contact = float(GameData.ENEMY["contact_dps"])
	else:
		var want := Vector3.ZERO
		if dist > 14.0:
			want = dir
		elif dist < 10.0:
			want = -dir
		else:
			var side := Vector3(-dir.z, 0.0, dir.x)
			want = side * (1.0 if sin(float(e["phase"])) >= 0.0 else -1.0)
		if want.length() > 0.01:
			var wn := want.normalized()
			n.position += wn * base_speed * float(e["type_mult"]) * float(e["speed_mult"]) * Ground.speed_mult(terrain, n.position, wn) * delta
	e["shot_cd"] = float(e["shot_cd"]) - delta
	if e["shot_cd"] <= 0.0 and dist < float(GameData.SPIT["range"]):
		e["shot_cd"] = float(GameData.SPIT["cd"]) * randf_range(0.9, 1.1)
		_fire_spit(e, n)
	return contact


func _fire_spit(_e: Dictionary, n: Node3D) -> void:
	var from: Vector3 = n.position + Vector3(0, 0.8, 0)
	var target: Vector3 = player.position + Vector3(0, 1.0, 0)
	var dir := (target - from).normalized()
	var node := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 8, 6), Util.shared_mat(Color(0.5, 1.0, 0.3), 2.0))
	node.scale = Vector3.ONE * 0.45
	node.position = from
	add_child(node)
	eshots.append({"node": node, "dir": dir, "life": 3.0})


func _update_shots(delta: float) -> void:
	var chest_y := 1.0
	for i in range(eshots.size() - 1, -1, -1):
		var s: Dictionary = eshots[i]
		var node: Node3D = s["node"]
		node.position += s["dir"] * float(GameData.SPIT["speed"]) * delta
		s["life"] = float(s["life"]) - delta
		var dead := float(s["life"]) <= 0.0
		var dx := node.position.x - player.position.x
		var dz := node.position.z - player.position.z
		var dy := node.position.y - (player.position.y + chest_y)
		if not dead and dx * dx + dz * dz < 1.0 and absf(dy) < 1.2:
			player.damage(float(GameData.SPIT["dmg"]))
			Fx.burst(self, player.position + Vector3(0, 1.0, 0), Color(0.6, 1.0, 0.3), 8, 4.0)
			dead = true
		if not dead and node.position.y < terrain.height(node.position.x, node.position.z) + 0.1:
			dead = true
		if dead:
			node.queue_free()
			eshots.remove_at(i)


func _cleanup() -> void:
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if e["hp"] > 0.0:
			continue
		if elements != null:
			elements.on_death(e)
		Fx.burst(self, e["node"].position + Vector3(0, 0.5, 0), e["tint"], 14, 5.0)
		if drops != null:
			drops.maybe_drop(e["node"].position)
		e["node"].queue_free()
		list.remove_at(i)
		kills += 1
		if player != null and float(player.lifesteal) > 0.0:
			player.hp = minf(player.hp + float(player.lifesteal), player.max_hp)
		enemy_killed.emit(kills)
		if str(e["etype"]) == "boss":
			Fx.burst(self, e["node"].position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.3), 24, 8.0)
			boss_killed.emit()


# Значок над ворогом: колір стихії, до якої він найбільш стійкий.
func _add_badge(n: Node3D, res: Dictionary) -> void:
	var top := ""
	var best := float(GameData.ADAPTIVE["badge_min"])
	for fx in res:
		if res[fx] >= best:
			best = res[fx]
			top = fx
	if top == "":
		return
	var b := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 10, 6), Util.shared_mat(GameData.EFFECT[top]["color"], 1.5))
	b.scale = Vector3.ONE * 0.35
	b.position = Vector3(0, 1.1, 0)
	n.add_child(b)


# Low-poly гоблін: куб-тулуб із шипами, голова, злі очі, лапи й ноги на шарнірах.
# Початок - центр тіла (ноги дістають до -0.5). Тип міняє вигляд:
# grunt - червоний (роги або гребінь), runner - помаранчевий з гребенем,
# tank - фіолетовий з рогами і ширшим торсом, boss - золотий з короною.
# parts фарбуються статусом, darkparts - затемненим статусом, очі/роги завжди свої.
func _build_creature(etype: String) -> Dictionary:
	var tcfg: Dictionary = GameData.BOSS if etype == "boss" else GameData.ENEMY_TYPES[etype]
	var base: Color = tcfg["color"]
	var variant := "random"
	var bulk := 1.0
	match etype:
		"runner":
			variant = "crest"
			bulk = 0.85
		"tank":
			variant = "horns"
			bulk = 1.35
		"spitter":
			variant = "maw"
			bulk = 1.0
		"boss":
			variant = "crown"
			bulk = 1.4
		_:
			variant = "horns" if rng.randi() % 2 == 0 else "crest"
	var horn_mat := Util.shared_mat(Color(0.25, 0.2, 0.18))
	var white_mat := Util.shared_mat(Color(1, 1, 1))
	var pupil_mat := Util.shared_mat(Color(0.05, 0.05, 0.07))
	var gold_mat := Util.shared_mat(Color(0.95, 0.75, 0.2), 1.0)
	var gold_hot := Util.shared_mat(Color(0.95, 0.75, 0.2), 1.5)
	var main_mat := StandardMaterial3D.new()
	main_mat.albedo_color = base
	main_mat.roughness = 0.9
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = base.darkened(0.45)
	dark_mat.roughness = 0.9
	var root := Node3D.new()
	var rig := Node3D.new()
	root.add_child(rig)

	var blob := Util.mesh_instance(Util.shared_cyl(0.4, 0.4, 0.02), Util.shared_mat(Color(0, 0, 0, 0.25)))
	blob.position = Vector3(0, -0.48, 0)
	root.add_child(blob)

	var torso := Util.mesh_instance(Util.shared_box(Vector3(0.7 * bulk, 0.55 * bulk, 0.65 * bulk)), main_mat)
	rig.add_child(torso)
	for i in 3:
		var spike := Util.mesh_instance(Util.shared_cyl(0.0, 0.1, 0.3), dark_mat)
		spike.position = Vector3(0, 0.1 + 0.12 * i, -0.32)
		spike.rotation.x = -0.5
		rig.add_child(spike)

	var head := Util.mesh_instance(Util.shared_sphere(0.28, 0.5, 10, 6), main_mat)
	head.position = Vector3(0, 0.52, 0.08)
	rig.add_child(head)
	var eye_mesh := Util.shared_sphere(0.09, 0.18, 8, 4)
	var pupil_mesh := Util.shared_sphere(0.045, 0.09, 8, 4)
	for sx in [-1.0, 1.0]:
		var white := Util.mesh_instance(eye_mesh, white_mat)
		white.position = Vector3(0.13 * sx, 0.58, 0.3)
		rig.add_child(white)
		var pupil := Util.mesh_instance(pupil_mesh, pupil_mat)
		pupil.position = Vector3(0.13 * sx, 0.56, 0.37)
		rig.add_child(pupil)

	if variant == "horns":
		var horn_mesh := Util.shared_cyl(0.0, 0.09, 0.35)
		for sx in [-1.0, 1.0]:
			var horn := Util.mesh_instance(horn_mesh, horn_mat)
			horn.position = Vector3(0.2 * sx, 0.84, 0.05)
			horn.rotation.z = -0.5 * sx
			rig.add_child(horn)
	elif variant == "crest":
		var crest_mesh := Util.shared_cyl(0.0, 0.08, 0.28)
		for i in 3:
			var crest := Util.mesh_instance(crest_mesh, horn_mat)
			crest.position = Vector3(0, 0.8, 0.2 - 0.16 * i)
			rig.add_child(crest)
	elif variant == "maw":
		var crest_mesh := Util.shared_cyl(0.0, 0.08, 0.28)
		for i in 2:
			var crest := Util.mesh_instance(crest_mesh, horn_mat)
			crest.position = Vector3(0, 0.82, 0.1 - 0.16 * i)
			rig.add_child(crest)
		var mouth := Util.mesh_instance(Util.shared_sphere(0.12, 0.1, 8, 4), pupil_mat)
		mouth.position = Vector3(0, 0.44, 0.3)
		rig.add_child(mouth)
	elif variant == "crown":
		var band := Util.mesh_instance(Util.shared_cyl(0.3, 0.3, 0.18), gold_mat)
		band.position = Vector3(0, 0.86, 0.05)
		rig.add_child(band)
		var tooth_mesh := Util.shared_cyl(0.0, 0.06, 0.22)
		for i in 5:
			var a := TAU * i / 5.0
			var tooth := Util.mesh_instance(tooth_mesh, gold_hot)
			tooth.position = Vector3(cos(a) * 0.26, 1.02, 0.05 + sin(a) * 0.26)
			rig.add_child(tooth)

	var arm_mesh := Util.shared_box(Vector3(0.16, 0.5, 0.16))
	var leg_mesh := Util.shared_box(Vector3(0.22, 0.5, 0.24))
	var arm_l := _enemy_limb(rig, Vector3(-0.45, 0.12, 0.05), arm_mesh, main_mat)
	var arm_r := _enemy_limb(rig, Vector3(0.45, 0.12, 0.05), arm_mesh, main_mat)
	var leg_l := _enemy_limb(rig, Vector3(-0.2, -0.2, 0), leg_mesh, dark_mat)
	var leg_r := _enemy_limb(rig, Vector3(0.2, -0.2, 0), leg_mesh, dark_mat)

	return {"root": root, "rig": rig, "leg_l": leg_l, "leg_r": leg_r,
		"arm_l": arm_l, "arm_r": arm_r, "mat": main_mat, "darkmat": dark_mat}


func _enemy_limb(parent: Node3D, pivot_pos: Vector3, mesh: Mesh, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	parent.add_child(pivot)
	var mi := Util.mesh_instance(mesh, mat)
	mi.position = Vector3(0, -0.05, 0)
	pivot.add_child(mi)
	return pivot
