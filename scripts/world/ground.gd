class_name Ground
# Правила ландшафту для геймплею. Числа - у data.gd (GROUND, BIOME).
#  - схили: вгору повільніше, вниз швидше (можна з'їжджати)
#  - біом: свій множник швидкості
#  - висота: удар зверху вниз сильніший, знизу вгору слабший
#  - колайдери декору: кола {x, z, r} з Decor.statics_grid виштовхують назовні


# Множник швидкості руху в точці pos у напрямку dir (горизонтальний вектор).
static func speed_mult(terrain: Terrain, pos: Vector3, dir: Vector3) -> float:
	var biome: Dictionary = GameData.BIOME[terrain.biome_at(pos.x, pos.z)]
	var base: float = biome["speed"]
	if dir.length() < 0.01:
		return base
	var g: Dictionary = GameData.GROUND
	var step: float = g["slope_step"]
	var h0 := terrain.height(pos.x, pos.z)
	var h1 := terrain.height(pos.x + dir.x * step, pos.z + dir.z * step)
	var slope := (h1 - h0) / step   # > 0 - вгору
	var m := clampf(1.0 - slope * float(g["slope_effect"]), float(g["slope_min"]), float(g["slope_max"]))
	return base * m


# Множник шкоди за різницю висот між тим, хто б'є, і ціллю.
static func high_ground_mult(terrain: Terrain, attacker: Vector3, target: Vector3) -> float:
	var g: Dictionary = GameData.GROUND
	var diff := terrain.height(attacker.x, attacker.z) - terrain.height(target.x, target.z)
	return clampf(1.0 + diff * float(g["high_per_meter"]), 1.0 - float(g["high_lose_cap"]), 1.0 + float(g["high_gain_cap"]))


# Круглі колайдери декору: виштовхує точку назовні.
# Працює по просторовій сітці (див. Decor.statics_grid), а не перебором усіх:
# складність O(кілька сусідів), а не O(всі статики × всі сутності).
# Фізичних тіл у грі немає (рух ручний), тож колізії - проста 2D-геометрія.
const GRID_CELL := 8.0
const GRID_PAD := 6.0   # запас пошуку: більший за найбільший радіус (гори ~4.2 + тіло)


static func collide_grid(pos: Vector3, radius: float, grid: Dictionary) -> Vector3:
	var p := pos
	var x0 := floori((p.x - GRID_PAD) / GRID_CELL)
	var x1 := floori((p.x + GRID_PAD) / GRID_CELL)
	var z0 := floori((p.z - GRID_PAD) / GRID_CELL)
	var z1 := floori((p.z + GRID_PAD) / GRID_CELL)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var cell = grid.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for c in cell:
				var dx: float = p.x - float(c["x"])
				var dz: float = p.z - float(c["z"])
				var rr: float = float(c["r"]) + radius
				var d2 := dx * dx + dz * dz
				if d2 < rr * rr and d2 > 0.0001:
					var d := sqrt(d2)
					var push := (rr - d) / d
					p.x += dx * push
					p.z += dz * push
				elif d2 <= 0.0001:
					p.x += rr
	return p
