class_name Elements
extends Node3D
# Взаємодія стихій. Числа - у data.gd (REACTION, SPREAD, COMBO).
# Серія реакцій без пауз (до 3 с) множить їх шкоду: +15% за ланку, стеля x2.5.
#  - Пара: лід на палаючого або вогонь на сповільненого -> вибух пари по області
#  - Вибух газу: вогонь на отруєного -> вибух, шкода за кожен стак отрути, підпал
#  - Розбиття: поштовх на сповільненого -> бонусна шкода
#  - Надпровідність: блискавка на сповільненого -> ланцюг довший і сильніший
#  - Вогонь поширюється між ворогами, отрута переходить на сусідів після смерті
# Нова реакція = запис у data.gd + гілка в react().

var enemy_list: Array = []   # той самий масив, що й Enemies.list
var fxs: Array = []          # {node, life, rise}
var spread_t := 0.0
var combo := 0      # довжина поточної серії реакцій (множить їх шкоду)
var combo_t := 0.0  # скільки ще живе серія
var max_combo := 0  # рекорд серії за забіг (для статистики)


func setup(list: Array) -> void:
	enemy_list = list


func tick(delta: float) -> void:
	for e in enemy_list:
		e["react_cd"] = maxf(e["react_cd"] - delta, 0.0)
	combo_t -= delta
	if combo_t <= 0.0:
		combo = 0
	_spread_fire(delta)
	_update_fx(delta)


# Множник шкоди поточної серії (рахуй ПІСЛЯ _combo_bump).
func combo_mult() -> float:
	return minf(1.0 + (combo - 1) * float(GameData.COMBO["step"]), float(GameData.COMBO["max"]))


# Викликається ДО накладання ефекту: перевіряє, чи ворог уже має "парний" статус.
func react(e: Dictionary, fx: String, dmg: float) -> void:
	if e["react_cd"] > 0.0:
		return
	var burning: bool = e["burn"] > 0.0
	var slowed: bool = e["slow"] > 0.0
	var poisoned: bool = e["pstack"] > 0
	if (fx == "ice" and burning) or (fx == "fire" and slowed):
		_steam(e, dmg * _combo_bump(), fx)
	elif fx == "fire" and poisoned:
		_gas(e, _combo_bump(), fx)
	elif fx == "force" and slowed:
		_shatter(e, dmg * _combo_bump(), fx)
	elif fx == "shock" and slowed:
		_superconduct(e, dmg * _combo_bump(), fx)


# Реакція сталася: подовжити серію і повернути її множник шкоди.
func _combo_bump() -> float:
	if combo_t > 0.0:
		combo += 1
	else:
		combo = 1
	combo_t = float(GameData.COMBO["window"])
	max_combo = maxi(max_combo, combo)
	return combo_mult()


# Ворог помирає: отрута переходить на сусідів.
func on_death(e: Dictionary) -> void:
	if e["pstack"] <= 0:
		return
	var radius: float = GameData.SPREAD["poison_radius"]
	var r2 := radius * radius
	var pos: Vector3 = e["node"].position
	var p: Dictionary = GameData.EFFECT["poison"]
	for o in enemy_list:
		if o["node"] != e["node"] and o["node"].position.distance_squared_to(pos) < r2:
			o["poison"] = float(p["time"]) * float(GameData.BIOME[o["biome"]]["poison"])
			o["pstack"] = mini(o["pstack"] + 1, p["max_stacks"])
	_burst(pos, radius, p["color"])


# ---------- Реакції ----------

func _steam(e: Dictionary, dmg: float, fx: String) -> void:
	var r: Dictionary = GameData.REACTION["steam"]
	var pos: Vector3 = e["node"].position
	e["burn"] = 0.0
	e["slow"] = 0.0
	_aoe(pos, r["radius"], maxf(float(r["min_dmg"]), dmg * float(r["dmg_mult"])), fx)
	_show(e, r)


func _gas(e: Dictionary, mult: float, fx: String) -> void:
	var r: Dictionary = GameData.REACTION["gas"]
	var pos: Vector3 = e["node"].position
	var total: float = float(r["dmg_per_stack"]) * e["pstack"] * mult
	e["poison"] = 0.0
	e["pstack"] = 0
	var burn_time: float = GameData.EFFECT["fire"]["time"]
	for o in _aoe(pos, r["radius"], total, fx):
		o["burn"] = maxf(o["burn"], burn_time)
	_show(e, r)


func _shatter(e: Dictionary, dmg: float, fx: String) -> void:
	var r: Dictionary = GameData.REACTION["shatter"]
	e["slow"] = 0.0
	var bonus := dmg * float(r["dmg_mult"])
	e["hp"] -= bonus
	Effects.track(bonus, fx)
	_show(e, r)


func _superconduct(e: Dictionary, dmg: float, fx: String) -> void:
	var r: Dictionary = GameData.REACTION["superconduct"]
	Effects.chain(enemy_list, e, dmg * float(r["dmg_mult"]), r["count"], r["reach"], fx)
	_show(e, r)


func popup_at(pos: Vector3, text: String, col: Color, important := true) -> void:
	if not important and fxs.size() > 28:
		return   # дрібні цифри шкоди не спамлять понад ліміт
	_popup(pos, text, col)


func _show(e: Dictionary, r: Dictionary) -> void:
	var pos: Vector3 = e["node"].position
	if r.has("radius"):
		_burst(pos, r["radius"], r["color"])
	var title: String = Lang.t(r["name_id"])
	if combo >= 2:
		title += " x%.1f" % combo_mult()
	_popup(pos, title, r["color"])
	e["react_cd"] = GameData.REACTION_CD


func _aoe(pos: Vector3, radius: float, dmg: float, fx: String) -> Array:
	var victims: Array = []
	var r2 := radius * radius
	for o in enemy_list:
		if o["node"].position.distance_squared_to(pos) < r2:
			o["hp"] -= dmg
			Effects.track(dmg, fx)
			victims.append(o)
	return victims


# ---------- Поширення вогню ----------

func _spread_fire(delta: float) -> void:
	spread_t -= delta
	if spread_t > 0.0:
		return
	var s: Dictionary = GameData.SPREAD
	spread_t = s["fire_interval"]
	var radius: float = s["fire_radius"]
	var r2 := radius * radius
	var chance: float = s["fire_chance"]
	var time: float = s["fire_time"]
	for e in enemy_list:
		if e["burn"] <= 0.0:
			continue
		var pos: Vector3 = e["node"].position
		for o in enemy_list:
			if o["burn"] > 0.0 or o["hp"] <= 0.0:
				continue
			var fm: float = GameData.BIOME[o["biome"]]["fire"]   # на луках вогонь поширюється легше, на снігу гірше
			if o["node"].position.distance_squared_to(pos) < r2 and randf() < chance * fm:
				o["burn"] = time * fm


# ---------- Візуальні ефекти ----------

func _burst(pos: Vector3, radius: float, col: Color) -> void:
	var f := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 10, 6), Util.shared_mat(col, 2.0, 0.3))
	f.scale = Vector3.ONE * radius * 2.0
	f.position = pos
	add_child(f)
	fxs.append({"node": f, "life": 0.2, "rise": false})


func _popup(pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.01
	l.outline_size = 10
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(0, 1.5, 0)
	add_child(l)
	fxs.append({"node": l, "life": 0.9, "rise": true})


func _update_fx(delta: float) -> void:
	for i in range(fxs.size() - 1, -1, -1):
		var f: Dictionary = fxs[i]
		f["life"] -= delta
		var node: Node3D = f["node"]
		if f["rise"]:
			node.position.y += 1.5 * delta
			var lbl := node as Label3D
			lbl.modulate.a = clampf(f["life"] / 0.9, 0.0, 1.0)
		if f["life"] <= 0.0:
			node.queue_free()
			fxs.remove_at(i)
