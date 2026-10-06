class_name Effects
# Ефекти зброї: накладання при влучанні та щокадрові статуси ворогів.
# Параметри ефектів - у data.gd (EFFECT). Новий ефект = рядок у data.gd + гілка тут.
# Увесь урон, що списується поза Enemies.hit (DoT, ланцюги), рахується в
# extra_dealt/extra_fx через track() - для статистики забігу.

static var extra_dealt := 0.0
static var extra_fx := {}


static func reset_stats() -> void:
	extra_dealt = 0.0
	extra_fx = {}


static func track(dmg: float, fx: String) -> void:
	extra_dealt += dmg
	extra_fx[fx] = float(extra_fx.get(fx, 0.0)) + dmg


# Накласти ефект на ворога (основну шкоду вже нанесено).
static func apply(enemy_list: Array, e: Dictionary, fx: String, dmg: float, origin: Vector3) -> void:
	var p: Dictionary = GameData.EFFECT[fx]
	var bm: Dictionary = GameData.BIOME[e["biome"]]   # біом ворога підсилює або послаблює ефект
	var rs := 1.0 - float(e["resist"].get(fx, 0.0))   # стійкість (режим адаптації)
	match fx:
		"fire":
			e["burn"] = float(p["time"]) * float(bm["fire"]) * rs
		"ice":
			e["slow"] = float(p["time"]) * float(bm["ice"]) * rs
		"poison":
			e["poison"] = float(p["time"]) * float(bm["poison"]) * rs
			e["pstack"] = mini(e["pstack"] + 1, p["max_stacks"])
		"shock":
			# кристали проводять струм: +1 стрибок у кришталевому лісі
			var jumps: int = p["chain_count"] + (1 if e["biome"] == "crystal" else 0)
			chain(enemy_list, e, dmg * float(p["chain_mult"]) * rs, jumps, p["chain_range"])
		"force":
			var dir: Vector3 = e["node"].position - origin
			dir.y = 0.0
			if dir.length() < 0.01:
				dir = Vector3.FORWARD
			e["push"] = dir.normalized() * float(p["push"]) * rs
		"stun":
			e["stun"] = float(p["time"]) * rs
		"mark":
			e["mark"] = float(p["time"]) * rs


# Щокадрово: DOT-шкода, таймери, множник швидкості та колір ворога.
static func tick(e: Dictionary, delta: float) -> void:
	var speed := 1.0
	var tint: Color = e.get("base", GameData.ENEMY["color"])

	if e["poison"] > 0.0:
		e["poison"] -= delta
		var pdot: float = float(GameData.EFFECT["poison"]["dps"]) * float(e["pstack"]) * delta
		e["hp"] -= pdot
		track(pdot, "poison")
		tint = GameData.EFFECT["poison"]["color"]
		if e["poison"] <= 0.0:
			e["pstack"] = 0
	if e["burn"] > 0.0:
		e["burn"] -= delta
		var bdot := float(GameData.EFFECT["fire"]["dps"]) * delta
		e["hp"] -= bdot
		track(bdot, "fire")
		tint = GameData.EFFECT["fire"]["color"]
	if e["slow"] > 0.0:
		e["slow"] -= delta
		speed = GameData.EFFECT["ice"]["slow"]
		tint = GameData.EFFECT["ice"]["color"]
	if e["stun"] > 0.0:
		e["stun"] -= delta
		speed = 0.0
		tint = GameData.EFFECT["stun"]["color"]
	if e["mark"] > 0.0:
		e["mark"] -= delta

	e["speed_mult"] = speed
	e["tint"] = tint


# Блискавка: ланцюг по найближчих ворогах (кожен наступний - від попереднього).
static func chain(enemy_list: Array, src: Dictionary, dmg: float, count: int, reach: float, fx := "shock") -> void:
	var used: Array = [src["node"]]
	var from: Vector3 = src["node"].position
	for i in count:
		var best = null
		var best_d := reach * reach
		for o in enemy_list:
			if o["node"] in used:
				continue
			var d: float = o["node"].position.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = o
		if best == null:
			break
		best["hp"] -= dmg
		track(dmg, fx)
		used.append(best["node"])
		from = best["node"].position
