class_name RunHistory
# Історія забігів: останні світи (код, режим, вбивства, час) для швидкого повтору та рекордів.
# Зберігається у файлі user://runs.json.

const PATH := "user://runs.json"
const MAX_ENTRIES := 20


static func load_all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return []
	var data = JSON.parse_string(f.get_as_text())
	if data is Array:
		return data
	return []


# Останні забіги (найновіші першими).
static func recent(count: int) -> Array:
	var all := load_all()
	return all.slice(0, mini(count, all.size()))


# Рекорд вбивств на цьому seed (0, якщо ще не грав).
static func best_kills(seed_value: int) -> int:
	var best := 0
	for r in load_all():
		if int(r["seed"]) == seed_value:
			best = maxi(best, int(r["kills"]))
	return best


static func record(seed_value: int, mode: String, kills: int, seconds: float) -> void:
	var all := load_all()
	all.push_front({"seed": seed_value, "mode": mode, "kills": kills, "time": int(seconds)})
	if all.size() > MAX_ENTRIES:
		all.resize(MAX_ENTRIES)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all))
