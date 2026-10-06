class_name Util
# Спільні допоміжні функції + кеш спільних мешів/матеріалів.
# Динаміка (вороги, снаряди, вибухи, частинки) НЕ створює нові меші/матеріали,
# а бере готові з кешу: немає алокацій і компіляцій шейдерів у кадрі.
# Один раз за забіг викликається warmup() (див. main.gd).

static var _mesh_cache := {}
static var _mat_cache := {}
static var _quad: QuadMesh = null


static func make_mesh(mesh: Mesh, color: Color, emission := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	m.material_override = mat
	return m


# MeshInstance без свого матеріалу (матеріал дає власник/кеш).
static func mesh_instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	return m


static func shared_box(size: Vector3) -> BoxMesh:
	var key := "box:%s" % str(size)
	if not _mesh_cache.has(key):
		var b := BoxMesh.new()
		b.size = size
		_mesh_cache[key] = b
	return _mesh_cache[key]


static func shared_sphere(radius: float, height: float, radial := 10, rings := 6) -> SphereMesh:
	var key := "sph:%s|%s|%d|%d" % [radius, height, radial, rings]
	if not _mesh_cache.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = height
		s.radial_segments = radial
		s.rings = rings
		_mesh_cache[key] = s
	return _mesh_cache[key]


static func shared_cyl(top: float, bottom: float, h: float, radial := 8) -> CylinderMesh:
	var key := "cyl:%s|%s|%s|%d" % [top, bottom, h, radial]
	if not _mesh_cache.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = radial
		_mesh_cache[key] = c
	return _mesh_cache[key]


static func shared_torus(inner: float, outer: float, rings := 8, segs := 16) -> TorusMesh:
	var key := "tor:%s|%s|%d|%d" % [inner, outer, rings, segs]
	if not _mesh_cache.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = rings
		t.ring_segments = segs
		_mesh_cache[key] = t
	return _mesh_cache[key]


static func shared_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.25, 0.25)
	return _quad


static func shared_mat(color: Color, emission := 0.0, alpha := 1.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), emission, alpha, unshaded]
	if not _mat_cache.has(key):
		_mat_cache[key] = _build_mat(color, emission, alpha, unshaded)
	return _mat_cache[key]


# Свіжий матеріал з уже скомпільованим шейдером (для тих, хто міняє
# свої параметри в кадрі, як кільця вибухів). Дешево: тільки алокація ресурсу.
static func fresh_mat(color: Color, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	return _build_mat(color, emission, alpha, false)


static func _build_mat(color: Color, emission: float, alpha: float, unshaded: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var a := minf(color.a, alpha)
	var c := color
	c.a = a
	mat.albedo_color = c
	mat.roughness = 0.9
	if a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = emission
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return mat


# Прогріти кеш на старті забігу: все, що далі береться динамічно.
static func warmup() -> void:
	for bulk in [1.0, 0.85, 1.35, 1.4]:
		shared_box(Vector3(0.7 * bulk, 0.55 * bulk, 0.65 * bulk))
	shared_box(Vector3(0.16, 0.5, 0.16))
	shared_box(Vector3(0.22, 0.5, 0.24))
	shared_box(Vector3(1, 1, 1))
	shared_cyl(0.0, 0.1, 0.3)
	shared_cyl(0.0, 0.09, 0.35)
	shared_cyl(0.0, 0.08, 0.28)
	shared_cyl(0.3, 0.3, 0.18)
	shared_cyl(0.0, 0.06, 0.22)
	shared_cyl(0.5, 0.5, 2.0, 8)
	shared_cyl(0.5, 0.5, 2.0, 6)
	shared_cyl(0.5, 0.5, 2.0, 12)
	shared_cyl(0.4, 0.4, 0.02)
	shared_sphere(0.28, 0.5, 10, 6)
	shared_sphere(0.09, 0.18, 8, 4)
	shared_sphere(0.045, 0.09, 8, 4)
	shared_sphere(0.5, 1.0, 10, 6)
	shared_sphere(0.5, 1.0, 8, 4)
	shared_sphere(0.5, 1.0, 6, 4)
	shared_sphere(0.5, 1.0, 7, 5)
	shared_sphere(0.5, 1.0, 4, 2)   # октаедри льоду/стана/мітки
	shared_cyl(0.0, 0.12, 0.5)   # шипи мін
	shared_cyl(0.0, 0.3, 1.2)   # хвіст метеора
	shared_torus(0.7, 0.85, 8, 16)
	shared_torus(0.85, 1.0, 8, 28)
	shared_quad()
	var cols: Array = [Color.WHITE, Color(0.05, 0.05, 0.07), Color(0.25, 0.2, 0.18),
		Color(0.95, 0.75, 0.2), Color(0, 0, 0, 0.25), Color(0.22, 0.18, 0.18)]
	for key in GameData.EFFECT:
		cols.append(GameData.EFFECT[key]["color"])
	for c in cols:
		shared_mat(c)
		shared_mat(c, 1.0)
		shared_mat(c, 1.2)
		shared_mat(c, 1.5)
		shared_mat(c, 2.0)
		shared_mat(c, 2.5)
		shared_mat(c, 0.8, 0.3)
		shared_mat(c, 2.0, 0.35)
		shared_mat(c, 1.5, 0.45)
		shared_mat(c, 2.0, 0.8)
		shared_mat(c, 1.5, 1.0, true)
		shared_mat(c, 2.0, 0.4)   # ореоли вогню/блискавки
		shared_mat(c, 3.0)   # спалахи променів
	shared_mat(Color(1.0, 0.5, 0.15), 2.5, 0.6)   # хвіст метеора
		shared_mat(c.darkened(0.55))
	for key in GameData.EFFECT:
		shared_mat(Color(1, 1, 1).lerp(GameData.EFFECT[key]["color"], 0.35), 3.0)
