class_name Fx
# Одноразові ефекти: вибух кольорових іскор у точці. Вузол сам видаляється,
# одночасно живе не більше MAX_ACTIVE (захист від просадок при масових вбивствах).

const MAX_ACTIVE := 24

static var active := 0


static func burst(parent: Node3D, pos: Vector3, color: Color, amount := 12, speed := 5.0) -> void:
	if active >= MAX_ACTIVE:
		return
	active += 1
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.12
	pm.scale_max = 0.24
	pm.color = color
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	quad.material = Util.shared_mat(color, 1.5, 1.0, true)
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(1.2).timeout.connect(_on_done.bind(p))


static func _on_done(p: GPUParticles3D) -> void:
	if is_instance_valid(p):
		p.queue_free()
	active = maxi(0, active - 1)
