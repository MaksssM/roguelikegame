class_name Shrines
extends Node3D
# Святилища: 3 світні стовпи на карту (seed-розкладка, подалі від старту).
# Підійшов ближче 2.5 м - отримав випадкову нагороду рівня, стовп гасне.

signal shrine_used(pos: Vector3)

var list: Array = []   # {node, crystal, base_y, pos, used}


func setup(terrain: Terrain, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + "shrines")
	var lim := terrain.limit()
	var tries := 0
	while list.size() < 3 and tries < 200:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(25.0, lim)
		var x := cos(a) * r
		var z := sin(a) * r
		var ok := true
		for s in list:
			var sp: Vector3 = s["pos"]
			if Vector2(x - sp.x, z - sp.z).length() < 30.0:
				ok = false
				break
		if ok:
			_spawn(Vector3(x, terrain.height(x, z), z))


func tick(delta: float, player_pos: Vector3) -> void:
	for s in list:
		if s["used"]:
			continue
		var c: Node3D = s["crystal"]
		c.rotation.y += delta * 2.0
		c.position.y = float(s["base_y"]) + sin(Time.get_ticks_msec() / 1000.0 * 2.0 + float(s["pos"].x)) * 0.2
		var sp: Vector3 = s["pos"]
		if Vector2(player_pos.x - sp.x, player_pos.z - sp.z).length() < 2.5:
			s["used"] = true
			s["node"].visible = false
			shrine_used.emit(sp + Vector3(0, 1.5, 0))


func _spawn(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	var base := Util.make_mesh(CylinderMesh.new(), Color(0.3, 0.32, 0.38))
	(base.mesh as CylinderMesh).top_radius = 0.5
	(base.mesh as CylinderMesh).bottom_radius = 0.6
	(base.mesh as CylinderMesh).height = 0.4
	(base.mesh as CylinderMesh).radial_segments = 8
	base.position = Vector3(0, 0.2, 0)
	root.add_child(base)
	var pillar := Util.make_mesh(CylinderMesh.new(), Color(0.4, 0.9, 1.0), 1.5)
	(pillar.mesh as CylinderMesh).top_radius = 0.18
	(pillar.mesh as CylinderMesh).bottom_radius = 0.24
	(pillar.mesh as CylinderMesh).height = 2.0
	(pillar.mesh as CylinderMesh).radial_segments = 6
	pillar.position = Vector3(0, 1.4, 0)
	root.add_child(pillar)
	var crystal := Util.make_mesh(SphereMesh.new(), Color(0.6, 0.95, 1.0), 2.5)
	(crystal.mesh as SphereMesh).radius = 0.22
	(crystal.mesh as SphereMesh).height = 0.44
	(crystal.mesh as SphereMesh).radial_segments = 6
	(crystal.mesh as SphereMesh).rings = 3
	crystal.position = Vector3(0, 2.8, 0)
	root.add_child(crystal)
	add_child(root)
	list.append({"node": root, "crystal": crystal, "base_y": 2.8, "pos": pos, "used": false})
