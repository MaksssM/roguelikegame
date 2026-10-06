class_name WorldSeed
# Seed світу: одне 32-бітне число визначає ландшафт, появи ворогів і нагороди.
# Окремі генератори для спавну та нагород - щоб однаковий seed давав однакові послідовності
# незалежно від того, як саме ти граєш.
#
# Код світу - короткий запис seed для обміну, наприклад K7QF-29MD:
# 7 символів несуть число, 8-й - контрольний (ловить помилки при переписуванні).
# Алфавіт без плутанини між O/0 та I/L/1.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const MASK := 0xFFFFFFFF

var value: int
var spawn_rng := RandomNumberGenerator.new()
var loot_rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	value = seed_value & MASK
	spawn_rng.seed = hash(str(value) + "spawn")
	loot_rng.seed = hash(str(value) + "loot")


func code() -> String:
	return to_code(value)


static func random_seed() -> int:
	return randi() & MASK


# Щоденний ран: однаковий seed для всіх у межах доби (за UTC).
static func daily() -> int:
	return daily_label().hash() & MASK


static func daily_label() -> String:
	return Time.get_date_string_from_system(true)


# Підпис режиму для seed (щоб збіг із щоденним seed теж показувався як щоденний).
static func mode_for(seed_value: int) -> String:
	if (seed_value & MASK) == daily():
		return Lang.t("mode_daily") + " " + daily_label()
	return Lang.t("mode_seed")


# Що завгодно -> seed: код світу, число або довільний текст.
# Повертає -1, якщо введено схоже на код, але контрольний символ не збігається.
static func from_text(text: String) -> int:
	var t := text.strip_edges()
	if _looks_like_code(t):
		return from_code(t)
	if t.is_valid_int():
		return t.to_int() & MASK
	return t.hash() & MASK


static func to_code(seed_value: int) -> String:
	var v := seed_value & MASK
	var chars := ""
	var sum := 0
	for i in 7:
		var digit := (v >> (5 * (6 - i))) & 31
		chars += ALPHABET[digit]
		sum += digit * (i + 1)
	chars += ALPHABET[sum % 32]
	return chars.substr(0, 4) + "-" + chars.substr(4)


# Код -> seed, або -1 при помилці.
static func from_code(text: String) -> int:
	var t := _normalize(text)
	if t.length() != 8:
		return -1
	var v := 0
	var sum := 0
	for i in 7:
		var digit := ALPHABET.find(t[i])
		if digit < 0:
			return -1
		v = (v << 5) | digit
		sum += digit * (i + 1)
	var check := ALPHABET.find(t[7])
	if check < 0 or check != sum % 32 or v > MASK:
		return -1
	return v


static func _normalize(text: String) -> String:
	var t := text.to_upper().replace("-", "").replace(" ", "")
	return t.replace("O", "0").replace("I", "1").replace("L", "1")


# Код має дефіс і після нормалізації - рівно 8 символів алфавіту.
static func _looks_like_code(text: String) -> bool:
	if not text.contains("-"):
		return false
	var t := _normalize(text)
	if t.length() != 8:
		return false
	for i in t.length():
		if ALPHABET.find(t[i]) < 0:
			return false
	return true
