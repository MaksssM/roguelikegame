class_name Adaptive
# Режим адаптивних ворогів: нові вороги стійкі до того, чим ти б'єш найчастіше.
# Шкода по типах (ефект або "none") накопичується із затуханням. Частка вище "справедливої"
# перетворюється на стійкість нових ворогів. Урізноманітнюй стихії - і стійкість спадає.
# Числа - у data.gd (ADAPTIVE).

var damage := {}   # ефект -> зважена шкода


func record(fx: String, dmg: float) -> void:
	damage[fx] = float(damage.get(fx, 0.0)) + dmg


func tick(delta: float) -> void:
	var k := pow(0.5, delta / float(GameData.ADAPTIVE["half_life"]))
	for fx in damage:
		damage[fx] *= k


# Стійкість для нових ворогів: ефект -> від 0 до max_resist.
func resists() -> Dictionary:
	var out := {}
	var total := 0.0
	for fx in damage:
		total += damage[fx]
	var a: Dictionary = GameData.ADAPTIVE
	if total < float(a["min_total"]):
		return out
	for fx in damage:
		var share: float = damage[fx] / total
		var r := clampf((share - float(a["fair_share"])) * float(a["strength"]), 0.0, float(a["max_resist"]))
		if r > 0.0:
			out[fx] = r
	return out


func hud_line() -> String:
	var res := resists()
	if res.is_empty():
		return Lang.t("a_none")
	var keys := res.keys()
	keys.sort_custom(func(a, b): return res[a] > res[b])
	var parts: Array = []
	for fx in keys:
		var title: String = Lang.t("a_pure") if fx == "none" else Lang.t(GameData.EFFECT[fx]["name_id"])
		parts.append("%s %d%%" % [title, int(res[fx] * 100.0)])
	return Lang.t("a_resist") + " · ".join(parts)
