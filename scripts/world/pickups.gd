class_name Pickups
extends Node3D
# Підбори з ворогів: серце лікує, магніт стягує решту до гравця,
# бомба вибухає. Одноразові, живуть PICKUP.life секунд. Сигнал ловить main.

signal picked(kind: String, pos: Vector3)

var terrain: Terrain
var list: Array = []   # {node, kind, life, homing, gy, sc, ph}


func setup(t: Terrain) -> void:
	terrain = t


func maybe_drop(pos: Vector3) -> void:
	var p: Dictionary = GameData.PICKUP
	var roll := randf()
	var kind := ""
	if roll < float(p["heart"]):
		kind = "heart"
	elif roll < float(p["heart"]) + float(p["magnet"]):
		kind = "magnet"
	elif roll < float(p["heart"]) + float(p["magnet"]) + float(p["bomb"]):
		kind = "bomb"
	if kind == "":
		return
	spawn_at(kind, Vector3(pos.x, terrain.height(pos.x, pos.z) + 0.5, pos.z))


func magnetize() -> void:
	for s in list:
		s["homing"] = true


func tick(delta: float, player_pos: Vector3) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var collect: float = GameData.PICKUP["collect"]
	var pull_r2 := collect * collect
	for i in range(list.size() - 1, -1, -1):
		var s: Dictionary = list[i]
		var n: Node3D = s["node"]
		n.rotation.y += delta * 2.0
		n.position.y = float(s["gy"]) + sin(t * 3.0 + float(s["ph"])) * 0.15
		s["life"] = float(s["life"]) - delta
		if s["life"] <= 2.0:
			n.scale = Vector3.ONE * float(s["sc"]) * maxf(float(s["life"]) / 2.0, 0.01)
		if s["homing"]:
			var chest := player_pos + Vector3(0, 1.0, 0)
			n.position = n.position.move_toward(chest, float(GameData.PICKUP["pull_speed"]) * delta)
		var dx := n.position.x - player_pos.x
		var dz := n.position.z - player_pos.z
		if dx * dx + dz * dz < pull_r2 and absf(n.position.y - player_pos.y) < 2.0:
			picked.emit(str(s["kind"]), n.position)
			n.queue_free()
			list.remove_at(i)
		elif s["life"] <= 0.0:
			n.queue_free()
			list.remove_at(i)


func spawn_at(kind: String, pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	match kind:
		"heart":
			var h := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 8, 6), Util.shared_mat(Color(1.0, 0.3, 0.5), 1.5))
			h.scale = Vector3.ONE * 0.5
			root.add_child(h)
			for off in [Vector3(0.14, 0, 0.28), Vector3(0, 0, 0.28)]:
				var plus := Util.mesh_instance(Util.shared_box(Vector3(1, 1, 1)), Util.shared_mat(Color(1, 1, 1)))
				plus.scale = Vector3(0.22, 0.08, 0.06) if off.x > 0.0 else Vector3(0.08, 0.22, 0.06)
				plus.position = off
				root.add_child(plus)
		"magnet":
			var ring := Util.mesh_instance(Util.shared_torus(0.25, 0.4, 8, 16), Util.shared_mat(Color(1.0, 0.3, 0.3), 1.5))
			root.add_child(ring)
			var core := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 8, 6), Util.shared_mat(Color(1, 1, 1)))
			core.scale = Vector3.ONE * 0.25
			root.add_child(core)
		"bomb":
			var shell := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 8, 6), Util.shared_mat(Color(0.2, 0.18, 0.2)))
			shell.scale = Vector3.ONE * 0.45
			root.add_child(shell)
			var spark := Util.mesh_instance(Util.shared_sphere(0.5, 1.0, 8, 6), Util.shared_mat(Color(1.0, 0.55, 0.15), 2.5))
			spark.scale = Vector3.ONE * 0.18
			spark.position = Vector3(0, 0.3, 0)
			root.add_child(spark)
	add_child(root)
	list.append({"node": root, "kind": kind, "life": float(GameData.PICKUP["life"]),
		"homing": false, "gy": pos.y, "sc": 1.0, "ph": randf() * TAU})
