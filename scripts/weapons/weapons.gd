class_name Weapons
extends Node3D
# Модульна зброя: спосіб + форма + ефект. Усі числа та баланс - у data.gd, ефекти - у effects.gd.
# Така сама зброя при повторній нагороді підвищує рівень; коли слоти повні - рівень випадкової.

const MAX_MINES := 16
const BULLET_SPEED := 25.0
const BULLET_RANGE := 25.0

var terrain: Terrain
var player: Player
var enemies: Enemies
var list: Array = []      # {d, p, f, cd, lvl, orbs}
var bullets: Array = []   # {node, dir, life, fx, dmg}
var mines: Array = []     # {node, rune, fx, dmg, radius}
var meteors: Array = []   # {pos, t, total, fx, dmg, radius, marker, rock}
var fxs: Array = []       # {node, life}
var rings: Array = []     # ударні хвилі вибухів: {node, life, maxr}
var orbit_t := 0.0
var global_mult := 1.0   # бонус шкоди з рівнів (множить _damage)
var rng := RandomNumberGenerator.new()   # seed-генератор нагород (див. world_seed.gd)


func setup(t: Terrain, p: Player, e: Enemies) -> void:
	terrain = t
	player = p
	enemies = e


func tick(delta: float) -> void:
	orbit_t += delta
	for w in list:
		if w["d"] == "orbit":
			_update_orbit(w, delta)
		else:
			w["cd"] -= delta
			if w["cd"] <= 0.0 and _fire(w):
				w["cd"] = _cooldown(w)
	_update_bullets(delta)
	_update_mines(delta)
	_update_meteors(delta)
	_update_fx(delta)
	_update_rings(delta)


# ---------- Керування списком зброї ----------

func names() -> Array:
	var out: Array = []
	for w in list:
		out.append(weapon_name(w))
	return out


func weapon_name(w: Dictionary) -> String:
	return "%s · %s · %s  Lv.%d%s" % [
		Lang.t(GameData.DELIVERY[w["d"]]["name_id"]),
		Lang.t(GameData.PATTERN[w["p"]]["name_id"]),
		Lang.t(GameData.EFFECT[w["f"]]["name_id"]),
		w["lvl"],
		" EVO" if w.get("evo", false) else "",
	]


func add_weapon(d: String, p: String, f: String) -> void:
	for w in list:
		if w["d"] == d and w["p"] == p and w["f"] == f:
			_level_up(w)
			return
	var nw := {"d": d, "p": p, "f": f, "cd": 0.0, "lvl": 1, "orbs": [], "evo": false}
	if d == "orbit":
		var cnt: int = GameData.PATTERN[p]["count"]
		var ocol: Color = GameData.EFFECT[f]["color"]
		var orb_mesh := Util.shared_sphere(0.5, 1.0, 6, 4)
		var orb_mat := Util.shared_mat(ocol, 2.0)
		for i in cnt:
			var orb := Util.mesh_instance(orb_mesh, orb_mat)
			orb.scale = Vector3.ONE * 0.6
			orb.add_child(_orb_ring(ocol))
			add_child(orb)
			nw["orbs"].append(orb)
	list.append(nw)


func _pick(items: Array):
	return items[rng.randi() % items.size()]


# Згенерувати комбо, не додаючи (для превʼю в меню рівня).
func roll_combo() -> Dictionary:
	return {"d": _pick(GameData.DELIVERY.keys()), "p": _pick(GameData.PATTERN.keys()), "f": _pick(GameData.EFFECT.keys())}


func combo_name(c: Dictionary) -> String:
	return "%s · %s · %s" % [Lang.t(GameData.DELIVERY[c["d"]]["name_id"]), Lang.t(GameData.PATTERN[c["p"]]["name_id"]), Lang.t(GameData.EFFECT[c["f"]]["name_id"])]


func level_up_weapon(w: Dictionary) -> void:
	_level_up(w)


# Випадкова зброя, яку ще можна качати (або null, якщо всі в максимумі).
func random_upgradable():
	var u := list.filter(func(w): return w["lvl"] < GameData.MAX_LEVEL)
	if u.is_empty():
		return null
	return _pick(u)


# Пара для еволюції: дві макс. не-EVO (або пусто, якщо нема пари).
func fusion_pair() -> Array:
	var full := list.filter(func(w): return w["lvl"] >= GameData.MAX_LEVEL and not w.get("evo", false))
	if full.size() < 2:
		return []
	return [full[0], full[1]]


# Сплавити: перша стає EVO, друга зникає (разом зі своїми орбами).
func evolve(w1: Dictionary, w2: Dictionary) -> void:
	w1["evo"] = true
	for o in w2["orbs"]:
		o.queue_free()
	list.erase(w2)


func _level_up(w: Dictionary) -> void:
	if w["lvl"] < GameData.MAX_LEVEL:
		w["lvl"] += 1


# ---------- Баланс (формули; числа - у data.gd) ----------

func _damage(w: Dictionary) -> float:
	var base: float = GameData.DELIVERY[w["d"]]["dmg"]
	var key := "orbit_mult" if w["d"] == "orbit" else "dmg_mult"
	var pattern_mult: float = GameData.PATTERN[w["p"]][key]
	var effect_mult: float = GameData.EFFECT[w["f"]]["dmg_mult"]
	return base * pattern_mult * effect_mult * (1.0 + GameData.LEVEL_DMG * (w["lvl"] - 1)) * global_mult * float(GameData.DIFF["pdmg"][Settings.diff]) * (float(GameData.EVOLVE["dmg"]) if w.get("evo", false) else 1.0)


func _cooldown(w: Dictionary) -> float:
	var base: float = GameData.DELIVERY[w["d"]]["cd"]
	var cd := base * pow(1.0 - GameData.LEVEL_CD, w["lvl"] - 1)
	if w.get("evo", false):
		cd *= float(GameData.EVOLVE["cd"])
	return cd


# ---------- Допоміжне ----------

# Кут i-го пострілу: рівномірно по колу (кільце, хрест) або віялом.
func _angle(i: int, cnt: int, spread: float) -> float:
	if spread >= TAU:
		return TAU * i / cnt
	if cnt > 1:
		return lerpf(-spread, spread, float(i) / (cnt - 1))
	return 0.0


# Напрямок на найближчого ворога (горизонтальний) або null.
func _aim_dir(radius: float):
	var target = enemies.nearest(player.position, radius)
	if target == null:
		return null
	var d: Vector3 = target["node"].position - player.position
	d.y = 0.0
	return d.normalized()


func _flash(node: Node3D, life: float) -> void:
	fxs.append({"node": node, "life": life})


# ---------- Спосіб: орбіта ----------

func _orb_ring(col: Color) -> MeshInstance3D:
	var ring := Util.mesh_instance(Util.shared_torus(0.7, 0.85, 8, 16), Util.shared_mat(col, 1.2))
	ring.rotation = Vector3(1.1, 0.4, 0.0)
	return ring


func _update_orbit(w: Dictionary, delta: float) -> void:
	var d: Dictionary = GameData.DELIVERY["orbit"]
	var radius: float = d["radius"]
	var speed: float = d["speed"]
	var hit_r: float = d["hit_radius"]
	var gap: float = float(d["hit_gap"]) * pow(1.0 - GameData.LEVEL_CD, w["lvl"] - 1)
	var dmg := _damage(w)
	var col: Color = GameData.EFFECT[w["f"]]["color"]
	var orbs: Array = w["orbs"]
	var n := orbs.size()
	for i in n:
		var ang := orbit_t * speed + TAU * i / n
		var o: Node3D = orbs[i]
		o.position = player.aim_origin() + Vector3(cos(ang), 0, sin(ang)) * radius
		o.rotation.y += delta * 3.0
		if o.get_child_count() > 0:
			o.get_child(0).rotation.x += delta * 2.0
		for e in enemies.list:
			var er: float = hit_r + 0.5 * float(e["hit_r"])
			if e["hit_cd"] <= 0.0 and e["node"].position.distance_squared_to(o.position) < er * er:
				enemies.hit(e, dmg, w["f"], o.position)
				e["hit_cd"] = gap


# ---------- Спосіб: стрільба ----------

func _fire(w: Dictionary) -> bool:
	match w["d"]:
		"bolt":
			return _fire_bolt(w)
		"beam":
			return _fire_beam(w)
		"mine":
			return _fire_mine(w)
		"meteor":
			return _fire_meteor(w)
		"nova":
			return _fire_nova(w)
		"chain":
			return _fire_chain(w)
	return false


func _fire_bolt(w: Dictionary) -> bool:
	var base = _aim_dir(BULLET_RANGE)
	if base == null:
		return false
	var pat: Dictionary = GameData.PATTERN[w["p"]]
	var cnt: int = pat["count"]
	var spread: float = pat["spread"]
	var dmg := _damage(w)
	var col: Color = GameData.EFFECT[w["f"]]["color"]
	for i in cnt:
		# гранований кристал, витягнутий за польотом (меш і матеріал спільні)
		var b := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 8, 4), Util.shared_mat(col, 2.5))
		b.scale = Vector3(0.32, 0.32, 0.85)
		b.position = player.aim_origin()
		add_child(b)
		var dir: Vector3 = base.rotated(Vector3.UP, _angle(i, cnt, spread))
		b.look_at(b.position + dir)
		bullets.append({"node": b, "dir": dir, "life": 2.0, "fx": w["f"], "dmg": dmg})
	return true


func _fire_beam(w: Dictionary) -> bool:
	var d: Dictionary = GameData.DELIVERY["beam"]
	var length: float = d["length"]
	var half_w: float = d["width"]
	var base = _aim_dir(length)
	if base == null:
		return false
	var pat: Dictionary = GameData.PATTERN[w["p"]]
	var cnt: int = pat["count"]
	var spread: float = pat["spread"]
	var dmg := _damage(w)
	var col: Color = GameData.EFFECT[w["f"]]["color"]
	for i in cnt:
		var dir: Vector3 = base.rotated(Vector3.UP, _angle(i, cnt, spread))
		# пробиває всіх, хто стоїть на лінії (відстань до відрізка < width)
		var half_w2 := half_w * half_w
		for e in enemies.list:
			var rel: Vector3 = e["node"].position - player.aim_origin()
			rel.y = 0.0
			var t := clampf(rel.dot(dir), 0.0, length)
			if (rel - dir * t).length_squared() < half_w2:
				enemies.hit(e, dmg, w["f"], player.aim_origin())
		var v := Util.mesh_instance(Util.shared_box(Vector3(1, 1, 1)), Util.shared_mat(col, 1.5, 0.45))
		add_child(v)
		var mid := player.aim_origin() + dir * length * 0.5
		v.look_at_from_position(mid, mid + dir)
		v.scale = Vector3(0.5, 0.5, length)
		_flash(v, 0.12)
		# біле гаряче ядро всередині
		var core := Util.mesh_instance(Util.shared_box(Vector3(1, 1, 1)), Util.shared_mat(Color(1, 1, 1).lerp(col, 0.35), 3.0))
		add_child(core)
		core.look_at_from_position(mid, mid + dir)
		core.scale = Vector3(0.16, 0.16, length)
		_flash(core, 0.12)
	return true


func _fire_mine(w: Dictionary) -> bool:
	var pat: Dictionary = GameData.PATTERN[w["p"]]
	var cnt: int = pat["count"]
	if enemies.nearest(player.position, 20.0) == null or mines.size() + cnt > MAX_MINES:
		return false
	var dmg := _damage(w)
	var radius: float = GameData.DELIVERY["mine"]["radius"]
	var col: Color = GameData.EFFECT[w["f"]]["color"]
	for i in cnt:
		var ang := 0.0
		if cnt > 1:
			ang = TAU * i / cnt
		var pos := player.position + Vector3(cos(ang), 0, sin(ang)) * (3.0 if cnt > 1 else 0.0)
		pos.y = terrain.height(pos.x, pos.z) + 0.15
		# темна основа + світна руна, що крутиться (меші/матеріали спільні)
		var m := Util.mesh_instance(Util.shared_cyl(0.5, 0.5, 2.0, 8), Util.shared_mat(col.darkened(0.55)))
		m.scale = Vector3(0.7, 0.15, 0.7)
		m.position = pos
		add_child(m)
		var rune := Util.mesh_instance(Util.shared_cyl(0.5, 0.5, 2.0, 6), Util.shared_mat(col, 2.5))
		rune.scale = Vector3(0.4, 0.1, 0.4)
		rune.position = pos + Vector3(0, 0.16, 0)
		add_child(rune)
		mines.append({"node": m, "rune": rune, "fx": w["f"], "dmg": dmg, "radius": radius})
	return true


func _fire_meteor(w: Dictionary) -> bool:
	var d: Dictionary = GameData.DELIVERY["meteor"]
	var radius: float = d["radius"]
	var delay: float = d["delay"]
	var reach2 := float(d["range"]) * float(d["range"])
	var pool: Array = []
	for e in enemies.list:
		if e["node"].position.distance_squared_to(player.position) < reach2:
			pool.append(e)
	if pool.is_empty():
		return false
	pool.shuffle()

	var cnt: int = GameData.PATTERN[w["p"]]["count"]
	var dmg := _damage(w)
	var col: Color = GameData.EFFECT[w["f"]]["color"]
	for i in cnt:
		var target: Dictionary = pool[i % pool.size()]
		var ep: Vector3 = target["node"].position
		# цілимось з упередженням: туди, куди ворог дійде за час затримки
		var to: Vector3 = player.position - ep
		to.y = 0.0
		var speed: float = float(GameData.ENEMY["speed"]) * float(target["speed_mult"])
		var lead := minf(to.length(), speed * delay)
		var pos := ep + to.normalized() * lead
		pos.y = terrain.height(pos.x, pos.z) + 0.1

		var marker := Util.mesh_instance(Util.shared_cyl(0.5, 0.5, 2.0, 12), Util.shared_mat(col, 0.8, 0.3))
		marker.scale = Vector3(radius * 2.0, 0.05, radius * 2.0)
		marker.position = pos
		add_child(marker)
		# палаючий камінь падає з неба весь час затримки
		var rock := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 7, 5), Util.shared_mat(Color(0.22, 0.18, 0.18), 1.0))
		rock.scale = Vector3.ONE * 0.7
		rock.position = pos + Vector3(0, 16, 0)
		add_child(rock)
		meteors.append({"pos": pos, "t": delay, "total": delay, "fx": w["f"], "dmg": dmg, "radius": radius, "marker": marker, "rock": rock})
	return true


func _fire_nova(w: Dictionary) -> bool:
	var d: Dictionary = GameData.DELIVERY["nova"]
	var cnt: int = GameData.PATTERN[w["p"]]["count"]
	if enemies.nearest(player.position, float(d["radius"])) == null:
		return false
	# форма розширює радіус, шкода вже враховує множник форми (див. _damage)
	_explode(player.aim_origin(), w["f"], _damage(w), float(d["radius"]) * (1.0 + 0.15 * (cnt - 1)))
	return true


func _fire_chain(w: Dictionary) -> bool:
	var d: Dictionary = GameData.DELIVERY["chain"]
	var target = enemies.nearest(player.position, float(d["range"]))
	if target == null:
		return false
	var from: Vector3 = player.aim_origin()
	var dmg := _damage(w)
	enemies.hit(target, dmg, w["f"], from)
	_flash(_bolt_link(from, target["node"].position, w["f"]), 0.15)
	# форма додає стрибки: віяло б'є далі по натовпу, одиночний - точніше й сильніше
	var jumps: int = int(d["jumps"]) + GameData.PATTERN[w["p"]]["count"]
	Effects.chain(enemies.list, target, dmg * float(d["mult"]), jumps, float(d["reach"]))
	return true


# Тонка світна перемичка між двома точками (для ланцюга).
func _bolt_link(a: Vector3, b: Vector3, fx: String) -> MeshInstance3D:
	var v := Util.mesh_instance(Util.shared_box(Vector3(1, 1, 1)), Util.shared_mat(GameData.EFFECT[fx]["color"], 2.5))
	add_child(v)
	var mid := (a + b) * 0.5
	v.position = mid
	if a.distance_to(b) > 0.05:
		v.look_at_from_position(mid, b)
	v.scale = Vector3(0.12, 0.12, maxf(a.distance_to(b), 0.1))
	return v


# ---------- Оновлення снарядів, мін, метеорів ----------

func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		var node: Node3D = b["node"]
		node.position += b["dir"] * BULLET_SPEED * delta
		node.position.y = terrain.height(node.position.x, node.position.z) + 0.8
		b["life"] -= delta
		var target = null
		for e in enemies.list:
			var hr: float = e["hit_r"]
			if e["node"].position.distance_squared_to(node.position) < hr * hr:
				target = e
				break
		if target != null:
			enemies.hit(target, b["dmg"], b["fx"], node.position)
		if target != null or b["life"] <= 0.0:
			node.queue_free()
			bullets.remove_at(i)


func _update_mines(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in range(mines.size() - 1, -1, -1):
		var m: Dictionary = mines[i]
		var mp: Vector3 = m["node"].position
		m["node"].rotation.y += delta * 1.5
		m["rune"].rotation.y -= delta * 3.0
		m["rune"].position.y = mp.y + 0.16 + sin(t * 5.0 + mp.x) * 0.04
		var triggered := false
		for e in enemies.list:
			if e["node"].position.distance_squared_to(mp) < 4.0:
				triggered = true
				break
		if triggered:
			_explode(mp, m["fx"], m["dmg"], m["radius"])
			m["node"].queue_free()
			m["rune"].queue_free()
			mines.remove_at(i)


func _update_meteors(delta: float) -> void:
	for i in range(meteors.size() - 1, -1, -1):
		var m: Dictionary = meteors[i]
		m["t"] -= delta
		var k := clampf(float(m["t"]) / float(m["total"]), 0.0, 1.0)
		m["rock"].position = m["pos"] + Vector3(0, 16.0 * k, 0)
		m["rock"].rotation.x += delta * 6.0
		if m["t"] <= 0.0:
			_explode(m["pos"], m["fx"], m["dmg"], m["radius"])
			m["marker"].queue_free()
			m["rock"].queue_free()
			meteors.remove_at(i)


# Публічний вибух для чужих систем (бомба-підбір): та ж картинка, що у мін.
func detonate(pos: Vector3, fx: String, dmg: float, radius: float) -> void:
	_explode(pos, fx, dmg, radius)


func _explode(pos: Vector3, fx: String, dmg: float, radius: float) -> void:
	var r2 := radius * radius
	for e in enemies.list:
		if e["node"].position.distance_squared_to(pos) < r2:
			enemies.hit(e, dmg, fx, pos)
	var f := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 10, 6), Util.shared_mat(GameData.EFFECT[fx]["color"], 2.0, 0.35))
	f.scale = Vector3.ONE * radius * 2.0
	f.position = pos
	add_child(f)
	Fx.burst(self, pos + Vector3(0, 0.5, 0), GameData.EFFECT[fx]["color"], 18, 7.0)
	_flash(f, 0.15)
	# плоске кільце ударної хвилі (матеріал свіжий: прозорість анімується окремо у кожного)
	var ring := Util.mesh_instance(Util.shared_torus(0.85, 1.0, 8, 28), Util.fresh_mat(GameData.EFFECT[fx]["color"], 2.0, 0.8))
	ring.position = pos + Vector3(0, 0.3, 0)
	ring.rotation.x = PI * 0.5
	ring.scale = Vector3.ONE * 0.5
	add_child(ring)
	rings.append({"node": ring, "life": 0.25, "maxr": radius})


func _update_rings(delta: float) -> void:
	for i in range(rings.size() - 1, -1, -1):
		var r: Dictionary = rings[i]
		r["life"] -= delta
		var k := clampf(float(r["life"]) / 0.25, 0.0, 1.0)
		var s := lerpf(float(r["maxr"]), 0.5, k)
		var rnode: MeshInstance3D = r["node"]
		rnode.scale = Vector3.ONE * s
		(rnode.material_override as StandardMaterial3D).albedo_color.a = 0.8 * k
		if r["life"] <= 0.0:
			rnode.queue_free()
			rings.remove_at(i)


func _update_fx(delta: float) -> void:
	for i in range(fxs.size() - 1, -1, -1):
		var f: Dictionary = fxs[i]
		f["life"] -= delta
		if f["life"] <= 0.0:
			f["node"].queue_free()
			fxs.remove_at(i)
