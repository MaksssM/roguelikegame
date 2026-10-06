class_name Trader
extends Node3D
# Торговець-відлюдник: один на карту (seed-позиція, подалі від старту).
# Підійшов ближче 2.5 м і маєш більше TRADER.cost HP - міняє їх на
# випадкову нагороду рівня. Кулдаун між угодами, щоб не злити все HP.

signal trade_requested(pos: Vector3)

var pos := Vector3.ZERO
var cd := 0.0
var done := false   # true після побудови (завжди один)


func setup(terrain: Terrain, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + "trader")
	var lim := terrain.limit()
	var tries := 0
	while not done and tries < 100:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(25.0, lim)
		var x := cos(a) * r
		var z := sin(a) * r
		pos = Vector3(x, terrain.height(x, z), z)
		done = true
	if not done:
		return
	_build()


func tick(delta: float, player_pos: Vector3, gold: int) -> void:
	if not done:
		return
	cd = maxf(cd - delta, 0.0)
	var dx := player_pos.x - pos.x
	var dz := player_pos.z - pos.z
	if cd <= 0.0 and dx * dx + dz * dz < 6.25 and gold >= int(GameData.TRADER["cost"]):
		cd = float(GameData.TRADER["cd"])
		trade_requested.emit(pos + Vector3(0, 1.5, 0))


func _build() -> void:
	var root := Node3D.new()
	root.position = pos
	var robe := Util.make_mesh(CylinderMesh.new(), Color(0.25, 0.2, 0.35))
	(robe.mesh as CylinderMesh).top_radius = 0.25
	(robe.mesh as CylinderMesh).bottom_radius = 0.55
	(robe.mesh as CylinderMesh).height = 1.6
	(robe.mesh as CylinderMesh).radial_segments = 7
	robe.position = Vector3(0, 0.8, 0)
	root.add_child(robe)
	var head := Util.make_mesh(SphereMesh.new(), Color(0.9, 0.72, 0.55))
	(head.mesh as SphereMesh).radius = 0.2
	(head.mesh as SphereMesh).height = 0.4
	head.position = Vector3(0, 1.75, 0)
	root.add_child(head)
	var brim := Util.make_mesh(CylinderMesh.new(), Color(0.3, 0.24, 0.15))
	(brim.mesh as CylinderMesh).top_radius = 0.55
	(brim.mesh as CylinderMesh).bottom_radius = 0.55
	(brim.mesh as CylinderMesh).height = 0.06
	(brim.mesh as CylinderMesh).radial_segments = 8
	brim.position = Vector3(0, 1.95, 0)
	root.add_child(brim)
	var lamp := Util.make_mesh(SphereMesh.new(), Color(1.0, 0.8, 0.35), 2.5)
	(lamp.mesh as SphereMesh).radius = 0.12
	(lamp.mesh as SphereMesh).height = 0.24
	lamp.position = Vector3(0.45, 1.2, 0)
	root.add_child(lamp)
	var tag := Label3D.new()
	tag.text = Lang.t("trade_cost")
	tag.font_size = 42
	tag.pixel_size = 0.01
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.85, 0.4)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.6, 0)
	root.add_child(tag)
	add_child(root)
