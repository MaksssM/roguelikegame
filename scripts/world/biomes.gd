class_name Biomes
# Біоми: три карти шуму (температура, вологість, магма) визначають біом у точці.
# Правила генерації - у data.gd (BIOME_GEN), властивості біомів - там же (BIOME).

var temp := FastNoiseLite.new()
var wet := FastNoiseLite.new()
var mag := FastNoiseLite.new()


func setup(seed_value: int) -> void:
	var freq: float = GameData.BIOME_GEN["freq"]
	for n in [temp, wet, mag]:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.frequency = freq
	temp.seed = seed_value + 101
	wet.seed = seed_value + 202
	mag.seed = seed_value + 303


func biome_at(x: float, z: float) -> String:
	var g: Dictionary = GameData.BIOME_GEN
	var safe: float = g["safe_radius"]
	if x * x + z * z < safe * safe:
		return "meadow"   # старт завжди на луках
	if mag.get_noise_2d(x, z) > float(g["magma"]):
		return "volcano"   # рідкісні гарячі плями поверх усього
	var t := temp.get_noise_2d(x, z)
	var w := wet.get_noise_2d(x, z)
	if t < float(g["cold"]):
		return "snow"
	if w > float(g["wet"]):
		if w > float(g["cwet"]) and t < float(g["ctemp"]):
			return "crystal"   # прохолодний вологий ліс
		return "swamp"
	if t > float(g["hot"]) and w < float(g["dry"]):
		return "sand"
	return "meadow"
