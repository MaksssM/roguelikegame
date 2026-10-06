class_name Terrain
extends Node3D
# Процедурний low-poly ландшафт: висота (фрактальний шум) + біоми (див. biomes.gd).
# Вершинні кольори тепер із мікро-варіацією і плавним переходом до скельних схилів.

const SIZE := 180

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()   # мілкий шум для мікрорельєфу
var color_noise := FastNoiseLite.new()   # шум для мікроваріації кольору
var biomes := Biomes.new()


func setup(seed_value: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.2
	noise.fractal_gain = 0.45
	noise.frequency = 0.025
	noise.seed = seed_value

	detail.noise_type = FastNoiseLite.TYPE_PERLIN
	detail.frequency = 0.12
	detail.seed = seed_value + 777

	color_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	color_noise.frequency = 0.06
	color_noise.seed = seed_value + 444

	biomes.setup(seed_value)
	_build_mesh()


func height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 9.0
	h += detail.get_noise_2d(x, z) * 1.5   # мікрорельєф
	# край карти плавно опускається, щоб не було різкої стіни
	var lim := SIZE / 2.0
	var dx := absf(x) / lim
	var dz := absf(z) / lim
	var edge := maxf(dx, dz)
	if edge > 0.85:
		h -= (edge - 0.85) / 0.15 * 6.0
	return h


func biome_at(x: float, z: float) -> String:
	return biomes.biome_at(x, z)


# Межа, далі якої ходити не можна.
func limit() -> float:
	return SIZE / 2.0 - 2.0


# Колір вершини: колір біому з мікроваріацією + висотний градієнт + схилова скеля.
func _color(x: float, z: float, h: float) -> Color:
	var b: Dictionary = GameData.BIOME[biomes.biome_at(x, z)]
	var low: Color = b["low"]
	var high: Color = b["high"]
	var t := clampf((h + 5.0) / 12.0, 0.0, 1.0)
	var c := low.lerp(high, t)
	# мікроваріація кольору: невеликий зсув яскравості від клітинного шуму
	var cn := color_noise.get_noise_2d(x, z) * 0.08
	c = Color(clampf(c.r + cn, 0.0, 1.0), clampf(c.g + cn * 0.7, 0.0, 1.0), clampf(c.b + cn * 0.5, 0.0, 1.0))
	# схили: плавний перехід до скельного кольору (тепліший, з відтінком біому)
	var slope := maxf(absf(height(x + 0.8, z) - h), absf(height(x, z + 0.8) - h))
	var rock := Color(0.42, 0.4, 0.38).lerp(low.darkened(0.3), 0.25)
	c = c.lerp(rock, clampf((slope - 0.35) * 1.6, 0.0, 0.8))
	return c


func _build_mesh() -> void:
	# спочатку рахуємо вершини й кольори сітки один раз
	var n := SIZE + 1
	var half := SIZE / 2
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	cols.resize(n * n)
	for iz in n:
		for ix in n:
			var x := ix - half
			var z := iz - half
			var h := height(x, z)
			verts[iz * n + ix] = Vector3(x, h, z)
			cols[iz * n + ix] = _color(x, z, h)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # плоске затінення, low-poly вигляд
	for iz in SIZE:
		for ix in SIZE:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			for idx in [a, b, c, b, d, c]:
				st.set_color(cols[idx])
				st.add_vertex(verts[idx])
	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.82   # трохи блиску на мокрих/снігових поверхнях
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON   # чіткіший спекуляр для low-poly
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
