class_name Player
extends Node3D
# Гравець: рух, стрибок, камера від третьої особи, HP.
# Вигляд - процедурний low-poly шукач пригод: туніка, капюшон, руки/ноги з ходьбою.
# Початок координат - ступні (земля), груди ~ +1.2 м.

const CHEST_H = 1.25

const SKIN = Color(0.96, 0.76, 0.58)
const TUNIC = Color(0.22, 0.47, 0.9)
const TUNIC_DARK = Color(0.16, 0.35, 0.7)
const PANTS = Color(0.26, 0.29, 0.36)
const BOOTS = Color(0.42, 0.29, 0.17)
const HOOD = Color(0.28, 0.56, 0.32)
const EYE = Color(0.08, 0.08, 0.1)

var terrain: Terrain
var col_grid := {}
var body: Node3D          # повертається за yaw (все тіло)
var rig: Node3D           # нахил/присідання/смерть
var cam: Camera3D
var max_hp: float = GameData.PLAYER["max_hp"]
var hp: float = GameData.PLAYER["max_hp"]
var yaw := 0.0
var pitch := -0.5
var vel_y := 0.0
var speed_mult := 1.0   # бонус швидкості з рівнів
var regen_mult := 1.0   # бонус регенерації з рівнів
var crit_ch := 0.0      # шанс криту x2 (реліквія)
var lifesteal := 0.0    # HP за вбивство (реліквія)
var thorns := 0.0       # шкода у відповідь (реліквія)
var relics := {"crit": 0, "vamp": 0, "thorns": 0}   # стеки реліквій
var sliding := false    # ковзання з гірки (Ctrl): поза + пил + бонус швидкості
var slope_now := 0.0    # поточний схил попереду (плюс униз), для підказок
var _was_grounded := true
var _slide_dir := Vector3.ZERO   # куди реально несеться слайд (інерція, повертає повільно)
var _slide_fx := 0.0
var walk_phase := 0.0
var idle_t := 0.0
var dead_pose := 0.0
var _cam_ready := false
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _head: Node3D


func setup(t: Terrain, g: Dictionary) -> void:
	terrain = t
	col_grid = g
	body = Node3D.new()
	add_child(body)
	_build_character()
	cam = Camera3D.new()
	cam.fov = float(Settings.fov)
	add_child(cam)
	position = Vector3(0, terrain.height(0, 0), 0)


func aim_origin() -> Vector3:
	return global_position + Vector3(0, CHEST_H, 0)


func handle_mouse(event: InputEventMouseMotion) -> void:
	var s := Settings.mouse_sens
	yaw -= event.relative.x * 0.003 * s
	var dy := event.relative.y * 0.003 * s
	if Settings.invert_y:
		pitch = clampf(pitch + dy, -1.2, -0.1)
	else:
		pitch = clampf(pitch - dy, -1.2, -0.1)


func damage(amount: float) -> void:
	hp -= amount


func is_dead() -> bool:
	return hp <= 0.0


func tick(delta: float) -> void:
	if is_dead():
		return
	hp = minf(hp + float(GameData.PLAYER["regen"]) * regen_mult * delta, max_hp)
	if terrain.biome_at(position.x, position.z) == "volcano":
		hp -= float(GameData.LAVA_DPS) * delta   # лава палить усіх однаково
	_move(delta)
	_update_camera(delta)


func tick_dead(delta: float) -> void:
	dead_pose = minf(dead_pose + delta * 3.0, 1.0)
	rig.rotation.x = lerpf(0.0, -1.45, dead_pose)
	rig.position.y = lerpf(0.0, -0.55, dead_pose)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.2, delta * 4.0)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.2, delta * 4.0)
	_update_camera(delta)


func _move(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S): dir.z += 1
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1
	dir = dir.normalized().rotated(Vector3.UP, yaw)

	var speed := 8.0
	var move_dir := dir
	sliding = false
	slope_now = 0.0
	if _was_grounded and dir.length() > 0.1:
		var dn := dir.normalized()
		slope_now = terrain.height(position.x, position.z) - terrain.height(position.x + dn.x * 1.2, position.z + dn.z * 1.2)
		if Input.is_physical_key_pressed(KEY_CTRL) and slope_now > -0.12:
			# слайд тільки з гірки або по прямій; вгору не ковзає
			sliding = true
			speed *= clampf(1.35 + slope_now * 1.5, 1.0, 1.9)
			if _slide_dir.length() < 0.01:
				_slide_dir = dn
			# інерція: напрям слайду доганяє введення повільно - відчуття ковзання
			_slide_dir = (_slide_dir.lerp(dn, minf(delta * 2.5, 1.0))).normalized()
			move_dir = _slide_dir
		else:
			_slide_dir = Vector3.ZERO
	else:
		_slide_dir = Vector3.ZERO
	speed *= speed_mult * Ground.speed_mult(terrain, position, move_dir)
	var p := position + move_dir * speed * delta
	var lim := terrain.limit()
	p.x = clamp(p.x, -lim, lim)
	p.z = clamp(p.z, -lim, lim)
	p = Ground.collide_grid(p, 0.4, col_grid)

	var ground := terrain.height(p.x, p.z)
	vel_y -= 25.0 * delta
	p.y += vel_y * delta
	var grounded := false
	if p.y <= ground:
		p.y = ground
		vel_y = 0.0
		grounded = true
		if Input.is_physical_key_pressed(KEY_SPACE):
			vel_y = 9.0
	_was_grounded = grounded
	position = p
	body.rotation.y = yaw
	_animate(delta, dir, speed, grounded)


func _animate(delta: float, dir: Vector3, speed: float, grounded: bool) -> void:
	idle_t += delta
	var moving := dir.length() > 0.1
	if not grounded:
		# стрибок: ноги підібгані, руки вгору, нахил уперед
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -0.55, delta * 10.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.35, delta * 10.0)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.0, delta * 8.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.0, delta * 8.0)
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, 0.0, delta * 8.0)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.0, delta * 8.0)
		rig.rotation.x = lerpf(rig.rotation.x, -0.22, delta * 8.0)
		rig.position.y = lerpf(rig.position.y, 0.0, delta * 8.0)
	elif sliding:
		# ковзання: присів, ноги вперед, руки в боки, корпус назад + пил
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -0.95, delta * 8.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.8, delta * 8.0)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.5, delta * 8.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.5, delta * 8.0)
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, 0.7, delta * 8.0)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, -0.7, delta * 8.0)
		rig.rotation.x = lerpf(rig.rotation.x, 0.32, delta * 8.0)
		rig.position.y = lerpf(rig.position.y, -0.3, delta * 8.0)
		_head.rotation.x = lerpf(_head.rotation.x, -0.25, delta * 8.0)
		_slide_fx -= delta
		if _slide_fx <= 0.0:
			_slide_fx = 0.3
			var parent3d := get_parent() as Node3D
			if parent3d != null:
				Fx.burst(parent3d, global_position + Vector3(0, 0.15, 0), Color(0.85, 0.84, 0.8), 5, 2.0)
	elif moving:
		walk_phase += delta * (4.0 + speed * 0.9)
		var s := sin(walk_phase)
		_leg_l.rotation.x = s * 0.7
		_leg_r.rotation.x = -s * 0.7
		_arm_l.rotation.x = -s * 0.6
		_arm_r.rotation.x = s * 0.6
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, 0.0, delta * 10.0)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.0, delta * 10.0)
		rig.position.y = absf(cos(walk_phase)) * 0.07
		rig.rotation.x = lerpf(rig.rotation.x, -0.1, delta * 10.0)
		_head.rotation.y = lerpf(_head.rotation.y, 0.0, delta * 8.0)
		_head.rotation.x = lerpf(_head.rotation.x, 0.0, delta * 8.0)
	else:
		# спокій: дихання + голова озирається
		var b := sin(idle_t * 2.2)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, delta * 10.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, delta * 10.0)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, b * 0.05, delta * 8.0)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -b * 0.05, delta * 8.0)
		_arm_l.rotation.z = lerpf(_arm_l.rotation.z, 0.0, delta * 8.0)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.0, delta * 8.0)
		rig.position.y = lerpf(rig.position.y, b * 0.025, delta * 8.0)
		rig.rotation.x = lerpf(rig.rotation.x, 0.0, delta * 8.0)
		_head.rotation.y = sin(idle_t * 0.7) * 0.25
		_head.rotation.x = lerpf(_head.rotation.x, 0.0, delta * 8.0)


func _update_camera(delta: float) -> void:
	var target := global_position + Vector3(0, CHEST_H, 0)
	var offset := Vector3(0, 0, Settings.camera_dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	var cp := target + offset
	cp.y = maxf(cp.y, terrain.height(cp.x, cp.z) + 0.6)
	# піднімаємо камеру, поки весь промінь до гравця не вийде з-під землі
	for i in 6:
		var t := float(i + 1) / 7.0
		var sp := target.lerp(cp, t)
		var need := terrain.height(sp.x, sp.z) + 0.5
		if sp.y < need:
			cp.y += need - sp.y
	if not _cam_ready:
		_cam_ready = true
		cam.global_position = cp
	else:
		cam.global_position = cam.global_position.lerp(cp, minf(delta * 7.0, 1.0))
	if cam.fov != float(Settings.fov):
		cam.fov = float(Settings.fov)   # живе застосування з паузи
	cam.look_at(target)


# ---------- Збірка персонажа ----------

func _build_character() -> void:
	rig = Node3D.new()
	body.add_child(rig)

	# тінь-пляма під ногами
	var blob := _mesh(CylinderMesh.new(), Color(0, 0, 0, 0.28))
	(blob.mesh as CylinderMesh).top_radius = 0.42
	(blob.mesh as CylinderMesh).bottom_radius = 0.42
	(blob.mesh as CylinderMesh).height = 0.02
	var blob_mat := blob.material_override as StandardMaterial3D
	blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob.position = Vector3(0, 0.03, 0)
	_no_cull(blob)
	body.add_child(blob)

	# торс (туніка) + ремінь
	var torso := _mesh(BoxMesh.new(), TUNIC)
	(torso.mesh as BoxMesh).size = Vector3(0.62, 0.68, 0.36)
	torso.position = Vector3(0, 1.12, 0)
	rig.add_child(torso)
	var belt := _mesh(BoxMesh.new(), BOOTS)
	(belt.mesh as BoxMesh).size = Vector3(0.64, 0.12, 0.38)
	belt.position = Vector3(0, 0.8, 0)
	rig.add_child(belt)
	# наплічники
	for sx in [-1.0, 1.0]:
		var pad := _mesh(SphereMesh.new(), TUNIC_DARK)
		(pad.mesh as SphereMesh).radius = 0.13
		(pad.mesh as SphereMesh).height = 0.26
		pad.position = Vector3(0.36 * sx, 1.42, 0)
		rig.add_child(pad)

	# голова + очі + капюшон
	_head = Node3D.new()
	_head.position = Vector3(0, 1.62, 0)
	rig.add_child(_head)
	var head := _mesh(SphereMesh.new(), SKIN)
	(head.mesh as SphereMesh).radius = 0.26
	(head.mesh as SphereMesh).height = 0.52
	head.position = Vector3(0, 0.14, 0)
	_head.add_child(head)
	for sx in [-1.0, 1.0]:
		var eye := _mesh(SphereMesh.new(), EYE)
		(eye.mesh as SphereMesh).radius = 0.045
		(eye.mesh as SphereMesh).height = 0.09
		eye.position = Vector3(0.1 * sx, 0.17, -0.215)
		_head.add_child(eye)
	var hood := _mesh(CylinderMesh.new(), HOOD)
	(hood.mesh as CylinderMesh).top_radius = 0.04
	(hood.mesh as CylinderMesh).bottom_radius = 0.32
	(hood.mesh as CylinderMesh).height = 0.55
	(hood.mesh as CylinderMesh).radial_segments = 8
	hood.position = Vector3(0, 0.32, 0.09)
	hood.rotation.x = 0.18
	_head.add_child(hood)

	# руки (плече -> вниз, кисть) + посох у правій
	_arm_l = _make_limb(Vector3(-0.43, 1.4, 0), TUNIC, SKIN, 0.6, 0.17)
	_arm_r = _make_limb(Vector3(0.43, 1.4, 0), TUNIC, SKIN, 0.6, 0.17)
	var staff := _mesh(CylinderMesh.new(), Color(0.45, 0.32, 0.18))
	(staff.mesh as CylinderMesh).top_radius = 0.04
	(staff.mesh as CylinderMesh).bottom_radius = 0.04
	(staff.mesh as CylinderMesh).height = 1.25
	staff.position = Vector3(0, -0.62, -0.18)
	staff.rotation.x = 0.35
	_arm_r.add_child(staff)
	var crystal := _mesh(SphereMesh.new(), Color(0.5, 0.9, 1.0), 2.5)
	(crystal.mesh as SphereMesh).radius = 0.09
	(crystal.mesh as SphereMesh).height = 0.18
	crystal.position = Vector3(0, -0.62, -0.4)
	_arm_r.add_child(crystal)

	# ноги (стегно -> чобіт)
	_leg_l = _make_leg(Vector3(-0.16, 0.76, 0))
	_leg_r = _make_leg(Vector3(0.16, 0.76, 0))


func _make_limb(pivot_pos: Vector3, sleeve: Color, skin: Color, length: float, thick: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	rig.add_child(pivot)
	var arm := _mesh(BoxMesh.new(), sleeve)
	(arm.mesh as BoxMesh).size = Vector3(thick, length, thick)
	arm.position = Vector3(0, -length * 0.5, 0)
	pivot.add_child(arm)
	var hand := _mesh(SphereMesh.new(), skin)
	(hand.mesh as SphereMesh).radius = 0.09
	(hand.mesh as SphereMesh).height = 0.18
	hand.position = Vector3(0, -length - 0.04, 0)
	pivot.add_child(hand)
	return pivot


func _make_leg(pivot_pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	rig.add_child(pivot)
	var leg := _mesh(BoxMesh.new(), PANTS)
	(leg.mesh as BoxMesh).size = Vector3(0.22, 0.58, 0.24)
	leg.position = Vector3(0, -0.29, 0)
	pivot.add_child(leg)
	var boot := _mesh(BoxMesh.new(), BOOTS)
	(boot.mesh as BoxMesh).size = Vector3(0.24, 0.16, 0.32)
	boot.position = Vector3(0, -0.64, -0.03)
	pivot.add_child(boot)
	return pivot


func _mesh(m: Mesh, color: Color, emission := 0.0) -> MeshInstance3D:
	var mi := Util.make_mesh(m, color, emission)
	_no_cull(mi)
	return mi


func _no_cull(mi: MeshInstance3D) -> void:
	var mat := mi.material_override as StandardMaterial3D
	if mat != null:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
