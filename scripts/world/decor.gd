class_name Decor
extends Node3D
# Декорації за біомами (дерева, каміння, кактуси, пеньки). Лише візуал, без колізій.
# Розкладка залежить від seed світу, тож у всіх на однаковому seed вона однакова.
# Дрібнота (трава, сугроби) - через MultiMesh одним draw call, хмари дрейфують у tick.

var clouds: Array = []   # вузли хмар (по 3 пластини), повільно пливуть у tick
var statics_grid := {}    # Vector2i -> Array колайдерів {x, z, r}, крок Ground.GRID_CELL
var lava_mat: StandardMaterial3D = null   # спільний матеріал лавових калюж (пульсує в tick)
var lava_pools: Array = []   # центри калюж {x, z, r} - там лава б'є (див. main.gd)
var monolith_mats: Array = []   # матеріали рун на монолітах (пульсують)


func setup(terrain: Terrain, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + "decor")
	var lim := terrain.limit()
	var count: int = GameData.DECOR["count"]
	for i in count:
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		if x * x + z * z < 36.0:
			continue   # чисто навколо старту
		var kinds: Array = GameData.DECOR["by_biome"][terrain.biome_at(x, z)]
		var kind: String = kinds[rng.randi() % kinds.size()]
		_spawn(kind, Vector3(x, terrain.height(x, z), z), rng)
	_scatter_ground(rng, terrain)
	_spawn_clouds(rng)
	_spawn_mountains(rng, terrain)
	_spawn_monoliths(rng, terrain)


func tick(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for c in clouds:
		c.position.x += 0.55 * delta
		# невеликий вертикальний дрейф для об'ємності
		c.position.y += sin(t * 0.3 + c.position.z * 0.1) * 0.02 * delta
		if c.position.x > 110.0:
			c.position.x = -110.0
	if lava_mat != null:
		lava_mat.emission_energy_multiplier = 2.8 + sin(t * 2.5) * 0.8
	# пульсація рун на монолітах
	for mm in monolith_mats:
		(mm as StandardMaterial3D).emission_energy_multiplier = 1.5 + sin(t * 1.8) * 0.6


func _spawn(kind: String, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf() * TAU
	var sc := rng.randf_range(0.8, 1.5)
	root.scale = Vector3.ONE * sc
	# варіація кольору для кожного об'єкта: ±5% яскравості
	var cv := rng.randf_range(0.92, 1.08)
	match kind:
		"tree":
			_part(root, _cyl(0.28, 0.32, 1.4), Color(0.42 * cv, 0.3 * cv, 0.16 * cv), 0.7)
			# невеликі коріння
			for sx in [-1.0, 1.0]:
				var rt := Util.make_mesh(_cyl(0.08, 0.14, 0.5), Color(0.38 * cv, 0.26 * cv, 0.14 * cv))
				rt.position = Vector3(0.15 * sx, 0.15, 0.12 * sx)
				rt.rotation.z = 0.4 * sx
				root.add_child(rt)
			_part(root, _cyl(0.0, 1.2, 2.6), Color(0.18 * cv, 0.48 * cv, 0.18 * cv), 2.5)
			_part(root, _cyl(0.0, 0.8, 1.6), Color(0.24 * cv, 0.55 * cv, 0.22 * cv), 3.6)
			_part(root, _cyl(0.0, 0.35, 0.8), Color(0.3 * cv, 0.58 * cv, 0.28 * cv), 4.6)   # верхівка
			_solid(pos, 0.35 * sc)
		"pine":
			_part(root, _cyl(0.22, 0.22, 1.2), Color(0.38 * cv, 0.27 * cv, 0.16 * cv), 0.6)
			_part(root, _cyl(0.0, 1.1, 3.0), Color(0.72 * cv, 0.86 * cv, 0.82 * cv), 2.5)
			_part(root, _cyl(0.0, 0.7, 2.0), Color(0.78 * cv, 0.9 * cv, 0.85 * cv), 3.8)
			_part(root, _cyl(0.0, 0.35, 1.0), Color(0.85 * cv, 0.95 * cv, 0.92 * cv), 4.8)
			_solid(pos, 0.28 * sc)
		"cactus":
			_part(root, _cyl(0.32, 0.32, 2.4), Color(0.28 * cv, 0.56 * cv, 0.22 * cv), 1.2)
			_cactus_arm(root, 0.4, 1.3, cv)
			_cactus_arm(root, -0.35, 1.5, cv)   # другий відросток
			_solid(pos, 0.38 * sc)
		"dead":
			_part(root, _cyl(0.1, 0.32, 2.0), Color(0.32 * cv, 0.28 * cv, 0.22 * cv), 1.0)
			_dead_branch(root, cv)
			_dead_branch_2(root, cv)   # другий сук
			_solid(pos, 0.32 * sc)
		"rock":
			var s := SphereMesh.new()
			s.radius = 0.85
			s.height = 1.2
			s.radial_segments = 7   # low-poly
			s.rings = 5
			_part(root, s, Color(0.48 * cv, 0.48 * cv, 0.5 * cv), 0.35)
			var s2 := SphereMesh.new()
			s2.radius = 0.48
			s2.height = 0.75
			s2.radial_segments = 6
			s2.rings = 4
			_part_off(root, s2, Color(0.53 * cv, 0.53 * cv, 0.55 * cv), Vector3(0.52, 0.16, 0.22))
			# мох на камені у вологих біомах
			var s3 := SphereMesh.new()
			s3.radius = 0.35
			s3.height = 0.25
			s3.radial_segments = 6
			_part_off(root, s3, Color(0.25 * cv, 0.42 * cv, 0.2 * cv), Vector3(-0.1, 0.7, -0.15))
			_solid(pos, 0.75 * sc)
		"obsidian":
			_part(root, _cyl(0.0, 0.58, 2.4), Color(0.14 * cv, 0.11 * cv, 0.18 * cv), 1.2)
			_part(root, _cyl(0.0, 0.32, 1.6), Color(0.18 * cv, 0.13 * cv, 0.22 * cv), 0.8)
			_part(root, _cyl(0.14, 0.32, 0.6), Color(1.0, 0.42, 0.12), 2.4, 2.0)   # розжарений шматок
			_part(root, _cyl(0.0, 0.18, 0.4), Color(1.0, 0.3, 0.05), 3.0, 2.5)   # іскриста верхівка
			_solid(pos, 0.52 * sc)
		"crystree":
			_part(root, _cyl(0.22, 0.26, 1.8), Color(0.78 * cv, 0.78 * cv, 0.85 * cv), 0.9)
			_part(root, _cyl(0.0, 1.1, 2.6), Color(0.42 * cv, 0.72 * cv, 0.85 * cv), 2.8, 0.8)
			# кристалічне сяйво верхівки
			_part(root, _cyl(0.0, 0.5, 1.2), Color(0.55 * cv, 0.85 * cv, 0.95 * cv), 4.0, 1.2)
			_solid(pos, 0.38 * sc)
		"shard":
			_part(root, _cyl(0.0, 0.28, 1.4), Color(0.52 * cv, 0.82 * cv, 0.95 * cv), 0.7, 1.5)
			_part(root, _cyl(0.0, 0.16, 0.8), Color(0.68 * cv, 0.48 * cv, 0.95 * cv), 0.4, 1.5)
			# маленький осколок збоку
			var sh := Util.make_mesh(_cyl(0.0, 0.12, 0.55), Color(0.6 * cv, 0.75 * cv, 0.95 * cv), 1.0)
			sh.position = Vector3(0.2, 0.3, 0.1)
			sh.rotation.z = 0.35
			root.add_child(sh)
	add_child(root)


func _solid(pos: Vector3, r: float) -> void:
	var c := {"x": pos.x, "z": pos.z, "r": r}
	var k := Vector2i(floori(pos.x / Ground.GRID_CELL), floori(pos.z / Ground.GRID_CELL))
	if not statics_grid.has(k):
		statics_grid[k] = []
	(statics_grid[k] as Array).append(c)


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 6   # low-poly вигляд
	return m


# Відросток кактуса вбік і вгору.
func _cactus_arm(root: Node3D, x: float, y: float, cv := 1.0) -> void:
	var horiz := Util.make_mesh(BoxMesh.new(), Color(0.28 * cv, 0.53 * cv, 0.23 * cv))
	(horiz.mesh as BoxMesh).size = Vector3(0.5, 0.22, 0.22)
	horiz.position = Vector3(x, y, 0)
	root.add_child(horiz)
	var vert := Util.make_mesh(CylinderMesh.new(), Color(0.3 * cv, 0.56 * cv, 0.25 * cv))
	(vert.mesh as CylinderMesh).top_radius = 0.18
	(vert.mesh as CylinderMesh).bottom_radius = 0.22
	(vert.mesh as CylinderMesh).height = 0.75
	(vert.mesh as CylinderMesh).radial_segments = 6
	vert.position = Vector3(x + 0.25 * signf(x), y + 0.42, 0)
	root.add_child(vert)


# Косий сук на сухому стовбурі.
func _dead_branch(root: Node3D, cv := 1.0) -> void:
	var b := Util.make_mesh(CylinderMesh.new(), Color(0.32 * cv, 0.28 * cv, 0.22 * cv))
	(b.mesh as CylinderMesh).top_radius = 0.05
	(b.mesh as CylinderMesh).bottom_radius = 0.12
	(b.mesh as CylinderMesh).height = 1.1
	(b.mesh as CylinderMesh).radial_segments = 5
	b.position = Vector3(0.4, 1.4, 0)
	b.rotation.z = -0.7
	root.add_child(b)


# Другий менший сук під іншим кутом.
func _dead_branch_2(root: Node3D, cv := 1.0) -> void:
	var b := Util.make_mesh(CylinderMesh.new(), Color(0.3 * cv, 0.26 * cv, 0.2 * cv))
	(b.mesh as CylinderMesh).top_radius = 0.04
	(b.mesh as CylinderMesh).bottom_radius = 0.1
	(b.mesh as CylinderMesh).height = 0.7
	(b.mesh as CylinderMesh).radial_segments = 5
	b.position = Vector3(-0.25, 1.1, 0.15)
	b.rotation.z = 0.6
	b.rotation.y = 0.8
	root.add_child(b)


func _part_off(root: Node3D, mesh: Mesh, color: Color, at: Vector3) -> void:
	var mi := Util.make_mesh(mesh, color)
	mi.position = at
	root.add_child(mi)


func _part(root: Node3D, mesh: Mesh, color: Color, y: float, emission := 0.0) -> void:
	var mi := Util.make_mesh(mesh, color, emission)
	mi.position.y = y
	root.add_child(mi)


# Трава, квіти, сугроби, гриби, галька, очерет, сухостій, крига, кущі, світлячки.
# Все - сотнями штук по одному draw call через MultiMesh.
func _scatter_ground(rng: RandomNumberGenerator, terrain: Terrain) -> void:
	# === Луки ===
	_patch(rng, terrain, "meadow", _cone(), 900, 0.22, Color(0.28, 0.55, 0.22))   # трава (більше)
	_patch(rng, terrain, "meadow", _cone(), 350, 0.18, Color(0.35, 0.6, 0.3))     # світліша трава
	_patch(rng, terrain, "meadow", _ball(), 180, 0.05, Color(0.95, 0.85, 0.3))    # жовті квіти
	_patch(rng, terrain, "meadow", _ball(), 90, 0.05, Color(0.95, 0.95, 0.9))     # білі квіти
	_patch(rng, terrain, "meadow", _ball(), 70, 0.05, Color(0.9, 0.35, 0.25))     # червоні квіти
	_patch(rng, terrain, "meadow", _ball(), 50, 0.05, Color(0.6, 0.4, 0.85))      # фіолетові квіти
	_patch(rng, terrain, "meadow", _ball(), 75, 0.32, Color(0.2, 0.42, 0.22), 2.5, 4.0)   # кущі
	# === Сніг ===
	_patch(rng, terrain, "snow", _ball(), 350, 0.06, Color(0.92, 0.95, 0.98))     # сугроби (більше)
	_patch(rng, terrain, "snow", _ball(), 120, 0.04, Color(0.82, 0.88, 0.95))     # льодяна крихта
	_patch(rng, terrain, "snow", _cone(), 110, 0.1, Color(0.55, 0.78, 0.95), 0.7, 1.3, 0.5)   # крижані шипи
	# === Болото ===
	_patch(rng, terrain, "swamp", _cone(), 130, 0.16, Color(0.82, 0.26, 0.18))    # гриби
	_patch(rng, terrain, "swamp", _cone(), 50, 0.12, Color(0.7, 0.85, 0.3), 0.5, 0.8, 0.8)  # фосфорні гриби
	_patch(rng, terrain, "swamp", _cone(), 250, 0.38, Color(0.23, 0.44, 0.22), 1.2, 2.4)   # очерет
	_patch(rng, terrain, "swamp", _dot(), 70, 0.85, Color(1.0, 0.85, 0.4), 0.8, 1.2, 3.0)  # світлячки
	_patch(rng, terrain, "swamp", _dot(), 40, 0.6, Color(0.4, 1.0, 0.5), 0.6, 1.0, 2.0)    # зелені світлячки
	# === Пустеля ===
	_patch(rng, terrain, "sand", _ball(), 240, 0.05, Color(0.58, 0.55, 0.48))     # галька (більше)
	_patch(rng, terrain, "sand", _cone(), 250, 0.16, Color(0.72, 0.62, 0.32))     # сухостій
	_patch(rng, terrain, "sand", _cone(), 80, 0.08, Color(0.85, 0.78, 0.55))      # суха трава
	# === Вулкан ===
	_patch(rng, terrain, "volcano", _disc(), 55, 0.06, Color(1.0, 0.45, 0.1), 2.0, 4.5, 2.8, lava_pools, 0.5)   # лава
	_patch(rng, terrain, "volcano", _dot(), 30, 0.5, Color(1.0, 0.6, 0.2), 0.6, 1.0, 3.5)      # іскри
	# === Кристали ===
	_patch(rng, terrain, "crystal", _cone(), 100, 0.12, Color(0.5, 0.8, 0.95), 0.6, 1.1, 0.6)  # крист. шипи
	_patch(rng, terrain, "crystal", _dot(), 40, 0.7, Color(0.6, 0.9, 1.0), 0.5, 0.9, 1.8)      # крист. світлячки


func _cone() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.09
	m.height = 0.5
	m.radial_segments = 5
	return m


func _ball() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.15
	m.height = 0.2
	return m


func _dot() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	return m


func _disc() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.5
	m.bottom_radius = 0.5
	m.height = 0.06
	m.radial_segments = 10
	return m


func _patch(rng: RandomNumberGenerator, terrain: Terrain, biome: String, mesh: Mesh, count: int, lift: float, color: Color, s_lo := 0.7, s_hi := 1.4, emission := 0.0, out: Array = [], out_r := 0.0) -> void:
	var lim := terrain.limit()
	var poses: Array = []
	var shades: Array = []
	var radii: Array = []
	var tries := 0
	while poses.size() < count and tries < count * 8:
		tries += 1
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		if x * x + z * z < 36.0:
			continue
		if terrain.biome_at(x, z) != biome:
			continue
		var s := rng.randf_range(s_lo, s_hi)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		poses.append(Transform3D(b, Vector3(x, terrain.height(x, z) + lift * s, z)))
		radii.append(out_r * s)
		var v := rng.randf_range(0.85, 1.08)
		shades.append(Color(v, v, v))
	if poses.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = poses.size()
	for i in poses.size():
		mm.set_instance_transform(i, poses[i])
		mm.set_instance_color(i, shades[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	mmi.material_override = mat
	add_child(mmi)
	if biome == "volcano":
		lava_mat = mat
	for i in poses.size():
		if float(radii[i]) > 0.0:
			var pp: Vector3 = poses[i].origin
			out.append({"x": pp.x, "z": pp.z, "r": float(radii[i])})


# Об'ємніші напівпрозорі хмари високо над картою.
func _spawn_clouds(rng: RandomNumberGenerator) -> void:
	for i in 12:
		var root := Node3D.new()
		root.position = Vector3(rng.randf_range(-105, 105), rng.randf_range(24, 36), rng.randf_range(-105, 105))
		# 4-5 пластин різних розмірів і прозоростей — більше об'єму
		var parts := rng.randi_range(4, 5)
		for pi in parts:
			var alpha := rng.randf_range(0.45, 0.75)
			var cloud_col := Color(0.94, 0.96, 1.0, alpha)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = cloud_col
			mat.roughness = 1.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			var bm := BoxMesh.new()
			bm.size = Vector3(rng.randf_range(3.5, 7.0), rng.randf_range(0.6, 1.5), rng.randf_range(2.5, 4.5))
			var c := MeshInstance3D.new()
			c.mesh = bm
			c.material_override = mat
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.position = Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-2.0, 2.0))
			root.add_child(c)
		root.scale = Vector3.ONE * rng.randf_range(0.9, 2.0)
		add_child(root)
		clouds.append(root)


# Кільце гір на горизонті: скельна основа + середня частина + сніжна верхівка.
func _spawn_mountains(rng: RandomNumberGenerator, terrain: Terrain) -> void:
	var n := 28   # більше гір для щільнішого кільця
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.12, 0.12)
		var r := rng.randf_range(76, 88)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := rng.randf_range(18, 30)
		var w := rng.randf_range(9, 14)
		var cv := rng.randf_range(0.9, 1.1)   # варіація кольору
		var root := Node3D.new()
		root.position = Vector3(x, terrain.height(x, z) - 5.0, z)
		root.rotation.y = rng.randf() * TAU
		# скельна основа
		var base := _cyl(0.0, w * 0.52, h)
		(base as CylinderMesh).radial_segments = 5
		_part(root, base, Color(0.34 * cv, 0.38 * cv, 0.45 * cv), h * 0.5)
		# середня скельна частина (трохи темніша)
		var mid := _cyl(0.0, w * 0.32, h * 0.45)
		(mid as CylinderMesh).radial_segments = 5
		_part(root, mid, Color(0.4 * cv, 0.42 * cv, 0.5 * cv), h * 0.7)
		# сніжна шапка (ширша і з плавним переходом)
		var cap := _cyl(0.0, w * 0.24, 7.0)
		(cap as CylinderMesh).radial_segments = 5
		_part(root, cap, Color(0.9 * cv, 0.93 * cv, 0.97 * cv), h - 3.5)
		# тонка льодяна верхівка з легким сяйвом
		var tip := _cyl(0.0, w * 0.08, 2.5)
		(tip as CylinderMesh).radial_segments = 4
		_part(root, tip, Color(0.95, 0.97, 1.0), h + 0.5, 0.2)
		add_child(root)
		_solid(Vector3(x, 0, z), w * 0.38)


# Поодинокі темні моноліти-орієнтири з рунами (легке сяйво).
func _spawn_monoliths(rng: RandomNumberGenerator, terrain: Terrain) -> void:
	var lim := terrain.limit()
	for i in 7:
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		if x * x + z * z < 900.0:
			continue   # не поруч зі стартом
		var root := Node3D.new()
		root.position = Vector3(x, terrain.height(x, z), z)
		root.rotation.y = rng.randf() * TAU
		root.rotation.x = rng.randf_range(-0.06, 0.06)
		# основне тіло моноліту
		var m := BoxMesh.new()
		m.size = Vector3(1.6, 7.0, 1.6)
		_part(root, m, Color(0.2, 0.21, 0.28), 3.0)
		# тонкі руни (вертикальні смуги з емісією на гранях)
		var rune_colors := [Color(0.4, 0.85, 0.95), Color(0.7, 0.5, 0.95), Color(0.5, 0.95, 0.6)]
		var rune_col: Color = rune_colors[rng.randi() % rune_colors.size()]
		var rune_mat := StandardMaterial3D.new()
		rune_mat.albedo_color = rune_col
		rune_mat.emission_enabled = true
		rune_mat.emission = rune_col
		rune_mat.emission_energy_multiplier = 1.5
		rune_mat.roughness = 0.3
		monolith_mats.append(rune_mat)
		for ri in 3:
			var rune := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.08, rng.randf_range(1.5, 3.5), 1.62)
			rune.mesh = rm
			rune.material_override = rune_mat
			rune.position = Vector3(0.82, 2.5 + ri * 1.2, 0)
			root.add_child(rune)
		# камені біля підніжжя
		for si in 3:
			var stone := Util.make_mesh(SphereMesh.new(), Color(0.25, 0.26, 0.32))
			(stone.mesh as SphereMesh).radius = rng.randf_range(0.2, 0.4)
			(stone.mesh as SphereMesh).height = rng.randf_range(0.25, 0.5)
			(stone.mesh as SphereMesh).radial_segments = 5
			var sa := TAU * si / 3.0 + rng.randf_range(-0.3, 0.3)
			stone.position = Vector3(cos(sa) * 1.2, 0.1, sin(sa) * 1.2)
			root.add_child(stone)
		add_child(root)
		_solid(Vector3(x, 0, z), 1.1)
