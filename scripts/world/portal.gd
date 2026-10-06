class_name Portal
extends Node3D
# Портал вниз: відкривається на місці смерті боса, веде на наступний поверх
# (той же сід, але глибше і зліше). Підійшов ближче 2.5 м - спуск.

signal descended

var open := false
var ring: Node3D = null
var t := 0.0


func _ready() -> void:
	visible = false
	var base := Util.make_mesh(CylinderMesh.new(), Color(0.1, 0.08, 0.15))
	(base.mesh as CylinderMesh).top_radius = 1.0
	(base.mesh as CylinderMesh).bottom_radius = 1.2
	(base.mesh as CylinderMesh).height = 0.15
	(base.mesh as CylinderMesh).radial_segments = 12
	add_child(base)
	var pillar := Util.make_mesh(CylinderMesh.new(), Color(0.6, 0.3, 1.0), 2.0)
	(pillar.mesh as CylinderMesh).top_radius = 0.35
	(pillar.mesh as CylinderMesh).bottom_radius = 0.6
	(pillar.mesh as CylinderMesh).height = 2.4
	(pillar.mesh as CylinderMesh).radial_segments = 8
	pillar.position = Vector3(0, 1.3, 0)
	add_child(pillar)
	ring = Node3D.new()
	ring.position = Vector3(0, 0.4, 0)
	var torus := Util.make_mesh(TorusMesh.new(), Color(0.75, 0.45, 1.0), 2.0)
	(torus.mesh as TorusMesh).inner_radius = 0.85
	(torus.mesh as TorusMesh).outer_radius = 1.0
	(torus.mesh as TorusMesh).rings = 8
	(torus.mesh as TorusMesh).ring_segments = 24
	torus.rotation.x = PI * 0.5
	ring.add_child(torus)
	add_child(ring)


func open_at(pos: Vector3) -> void:
	position = Vector3(pos.x, pos.y - 0.5, pos.z)
	visible = true
	open = true


func tick(delta: float, player_pos: Vector3) -> void:
	if not open:
		return
	t += delta
	if ring != null:
		ring.rotation.y += delta * 3.0
		ring.position.y = 0.4 + sin(t * 3.0) * 0.15
	var dx := player_pos.x - position.x
	var dz := player_pos.z - position.z
	if dx * dx + dz * dz < 6.25:
		open = false
		visible = false
		descended.emit()
