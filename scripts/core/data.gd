class_name GameData
# ВСІ числа гри (баланс) зібрані тут. Міняй їх - код чіпати не треба.
#
# Шкода пострілу = dmg способу * dmg_mult форми * dmg_mult ефекту * (1 + LEVEL_DMG * (рівень - 1))
# Перезарядка    = cd способу * (1 - LEVEL_CD) ^ (рівень - 1)
#
# Логіка балансу:
# - Ефект "коштує" шкоди: чиста шкода (none) найсильніша, ефекти трохи слабші, але дають користь.
# - Форма з багатьма снарядами зменшує шкоду кожного: проти натовпу разом дає більше, проти одного - менше.
# - Орбіта використовує orbit_mult, бо її кулі не множать шкоду по одному ворогу (спільна пауза між ударами).

# ---------- Прогресія ----------
const MAX_WEAPONS = 5      # різних зброй одночасно
const MAX_LEVEL = 5        # максимальний рівень зброї
const LEVEL_DMG = 0.20     # +20% шкоди за рівень
const LEVEL_CD = 0.06      # -6% перезарядки за рівень
# Рівні гравця: поріг XP = 6 + (рівень-1)*4 (див. main.gd _xp_need).
# Нова зброя і стихії видаються ТІЛЬКИ через меню рівня, випадкових видач немає.

# ---------- Гравець і вороги ----------
const PLAYER = {"max_hp": 100.0, "regen": 0.5}

const ENEMY = {
	"hp": 20.0,
	"hp_per_kill": 0.015,    # HP ворога росте: hp * (1 + hp_per_kill * вбивства)
	"speed": 3.5,
	"contact_dps": 6.0,      # шкода гравцю від одного ворога впритул
	"contact_cap": 30.0,     # максимум шкоди за секунду від усіх разом
	"spawn_start": 0.9,      # пауза між появами ворогів...
	"spawn_step": 0.005,     # ...зменшується на це за кожне вбивство...
	"spawn_min": 0.35,       # ...але не менше за це
	"max_alive": 60,         # стеля одночасно живих (захист від просадок)
	"color": Color(0.9, 0.2, 0.2),
}

# ---------- Типи ворогів і бос (enemies.gd) ----------
# need - зі скількох вбивств тип з'являється; weight - вага в рулетці спавну.
const ENEMY_TYPES = {
	"grunt": {"hp": 1.0, "spd": 1.0, "scale": 1.0, "need": 0, "weight": 60, "color": Color(0.9, 0.2, 0.2)},
	"runner": {"hp": 0.5, "spd": 1.7, "scale": 0.7, "need": 8, "weight": 25, "color": Color(1.0, 0.55, 0.15)},
	"tank": {"hp": 3.0, "spd": 0.65, "scale": 1.5, "need": 20, "weight": 15, "color": Color(0.6, 0.22, 0.4)},
	"spitter": {"hp": 0.7, "spd": 1.0, "scale": 0.9, "need": 15, "weight": 20, "color": Color(0.4, 0.8, 0.3)},
}
const BOSS_EVERY = 75   # кожен N-й спавн - бос
const BOSS = {"hp": 12.0, "spd": 0.8, "scale": 2.2, "color": Color(0.95, 0.7, 0.2)}

# Плювки далекобійних: кулдаун, шкода, швидкість снаряда, дальність.
const SPIT = {"cd": 2.5, "dmg": 8.0, "speed": 14.0, "range": 22.0}

# Підбори з ворогів: шанси, сила, час життя, радіус збору.
const PICKUP = {
	"heart": 0.06, "magnet": 0.02, "bomb": 0.02,
	"heart_heal": 15.0, "bomb_radius": 8.0, "bomb_dmg": 40.0,
	"life": 25.0, "collect": 1.2, "pull_speed": 12.0,
}

# ---------- Складність (читається наживо: діє і при зміні з паузи) ----------
# Індекс = Settings.diff: 0 легко, 1 норма, 2 складно.
const DIFF = {
	"ehp": [0.75, 1.0, 1.4],    # HP ворогів
	"edmg": [0.7, 1.0, 1.4],    # шкода ворогів впритул
	"pdmg": [1.1, 1.0, 0.9],    # шкода гравця
}

# ---------- Випадкові події (main.gd) ----------
const EVENT = {
	"first": 75.0, "min": 60.0, "max": 100.0,   # перша і наступні паузи між подіями
	"meteors": 8, "pack": 8, "gold": 5,        # кількість за подію
	"meteor_dmg": 30.0, "meteor_radius": 3.5,
}

# ---------- Еволюція зброї (дві макс. не-EVO -> одна EVO) ----------
const EVOLVE = {"dmg": 1.8, "cd": 0.85}

# ---------- Реліквії (третій тип нагород рівня) ----------
const RELIC = {
	"crit_step": 0.1, "crit_max": 3,     # +10% шанс x2 шкоди, макс 3
	"vamp_step": 1.0, "vamp_max": 5,     # +1 HP за вбивство, макс 5
	"thorns_step": 4.0, "thorns_max": 5,   # +4 шкоди в відповідь, макс 5
	"boss_xp": 5,                        # скільки XP дає бос
}

# ---------- Способи (DELIVERY) ----------
const DELIVERY = {
	"bolt": {"name_id": "del_bolt", "cd": 0.7, "dmg": 12.0},
	"beam": {"name_id": "del_beam", "cd": 1.0, "dmg": 8.0, "length": 18.0, "width": 0.9},   # пробиває всіх на лінії
	"orbit": {"name_id": "del_orbit", "cd": 0.0, "dmg": 14.0, "radius": 2.4, "speed": 2.8, "hit_radius": 1.4, "hit_gap": 0.4},
	"mine": {"name_id": "del_mine", "cd": 1.6, "dmg": 20.0, "radius": 4.0},
	"meteor": {"name_id": "del_meteor", "cd": 2.6, "dmg": 34.0, "radius": 3.5, "delay": 0.8, "range": 22.0},
	"nova": {"name_id": "del_nova", "cd": 2.2, "dmg": 16.0, "radius": 5.0},   # вибух навколо себе; форма розширює радіус
	"chain": {"name_id": "del_chain", "cd": 1.0, "dmg": 9.0, "range": 20.0, "jumps": 3, "reach": 7.0, "mult": 0.7},   # б'є першого, далі стрибає; форма додає стрибки
}

# ---------- Форми (PATTERN) ----------
# count - скільки снарядів / променів / куль / мін / метеорів за раз
const PATTERN = {
	"single": {"name_id": "pat_single", "count": 1, "spread": 0.0, "dmg_mult": 1.0, "orbit_mult": 1.0},
	"twin": {"name_id": "pat_twin", "count": 2, "spread": 0.12, "dmg_mult": 0.65, "orbit_mult": 0.85},
	"wide": {"name_id": "pat_wide", "count": 2, "spread": 0.6, "dmg_mult": 0.6, "orbit_mult": 0.8},
	"fan": {"name_id": "pat_fan", "count": 3, "spread": 0.40, "dmg_mult": 0.55, "orbit_mult": 0.75},
	"cross": {"name_id": "pat_cross", "count": 4, "spread": TAU, "dmg_mult": 0.45, "orbit_mult": 0.65},
	"pent": {"name_id": "pat_pent", "count": 5, "spread": TAU, "dmg_mult": 0.4, "orbit_mult": 0.55},
	"ring": {"name_id": "pat_ring", "count": 8, "spread": TAU, "dmg_mult": 0.35, "orbit_mult": 0.5},
}

# ---------- Ефекти (EFFECT) ----------
const EFFECT = {
	"none": {"name_id": "eff_none", "color": Color(1.0, 1.0, 1.0), "dmg_mult": 1.15},
	"fire": {"name_id": "eff_fire", "color": Color(1.0, 0.45, 0.1), "dmg_mult": 0.75,
		"dps": 3.5, "time": 3.0},                                    # підпал, оновлюється
	"ice": {"name_id": "eff_ice", "color": Color(0.4, 0.8, 1.0), "dmg_mult": 0.8,
		"slow": 0.55, "time": 2.0},                                  # швидкість ворога x0.55
	"shock": {"name_id": "eff_shock", "color": Color(1.0, 0.95, 0.3), "dmg_mult": 0.75,
		"chain_count": 2, "chain_range": 6.0, "chain_mult": 0.6},    # перескакує на 2 найближчих
	"poison": {"name_id": "eff_poison", "color": Color(0.5, 0.9, 0.2), "dmg_mult": 0.7,
		"dps": 1.6, "max_stacks": 4, "time": 5.0},                   # стакається до 4 разів
	"force": {"name_id": "eff_force", "color": Color(0.8, 0.5, 1.0), "dmg_mult": 0.9,
		"push": 12.0},                                               # відкидає на ~2 м
	"stun": {"name_id": "eff_stun", "color": Color(1.0, 0.6, 0.9), "dmg_mult": 0.85,
		"time": 1.2},                                                 # ворог стоїть на місці
	"mark": {"name_id": "eff_mark", "color": Color(1.0, 0.2, 0.5), "dmg_mult": 0.9,
		"time": 4.0, "bonus": 1.25},                                  # +25% всієї шкоди по міченому
}

# ---------- Взаємодія стихій (elements.gd) ----------
const REACTION_CD = 0.6   # пауза між реакціями на одному ворогові

# Комбо реакцій: кожна наступна реакція в межах вікна сильніша.
const COMBO = {
	"window": 3.0,   # скільки секунд живе серія між реакціями
	"step": 0.15,    # +15% шкоди реакції за кожну ланку серії
	"max": 2.5,      # стеля множника
}

const REACTION = {
	"steam": {"name_id": "react_steam", "radius": 3.5, "dmg_mult": 1.5, "min_dmg": 10.0,
		"color": Color(0.9, 0.95, 1.0)},                       # лід+вогонь: вибух пари по області
	"gas": {"name_id": "react_gas", "radius": 4.0, "dmg_per_stack": 8.0,
		"color": Color(0.7, 1.0, 0.3)},                        # вогонь на отруєного: шкода за кожен стак
	"shatter": {"name_id": "react_shatter", "dmg_mult": 2.0,
		"color": Color(0.6, 0.9, 1.0)},                        # поштовх на сповільненого: +200% шкоди удару
	"superconduct": {"name_id": "react_superconduct", "count": 3, "reach": 9.0, "dmg_mult": 1.0,
		"color": Color(1.0, 1.0, 0.5)},                        # блискавка на сповільненого: довгий ланцюг
}

const SPREAD = {
	"fire_interval": 0.5,    # як часто перевіряємо поширення вогню
	"fire_chance": 0.35,     # шанс підпалити сусіда за перевірку
	"fire_radius": 2.5,
	"fire_time": 2.0,
	"poison_radius": 3.5,    # отрута після смерті переходить на сусідів у цьому радіусі
}

# ---------- Ландшафт (terrain.gd, biomes.gd, ground.gd, decor.gd) ----------
# Біоми: кожен підсилює одні стихії й послаблює інші (множники до тривалості ефекту)
# та змінює швидкість руху - і гравця, і ворогів.
const BIOME = {
	"meadow": {"name_id": "bio_meadow", "low": Color(0.22, 0.48, 0.18), "high": Color(0.48, 0.62, 0.25),
		"speed": 1.0, "fire": 1.4, "ice": 1.0, "poison": 1.0},
	"sand": {"name_id": "bio_sand", "low": Color(0.74, 0.64, 0.35), "high": Color(0.9, 0.8, 0.55),
		"speed": 0.85, "fire": 1.0, "ice": 0.6, "poison": 1.0},
	"snow": {"name_id": "bio_snow", "low": Color(0.75, 0.82, 0.9), "high": Color(0.98, 0.98, 1.0),
		"speed": 0.9, "fire": 0.5, "ice": 1.5, "poison": 0.8},
	"swamp": {"name_id": "bio_swamp", "low": Color(0.15, 0.28, 0.18), "high": Color(0.28, 0.4, 0.22),
		"speed": 0.8, "fire": 0.7, "ice": 1.0, "poison": 1.5},
	"volcano": {"name_id": "bio_volcano", "low": Color(0.2, 0.14, 0.16), "high": Color(0.52, 0.2, 0.08),
		"speed": 0.95, "fire": 1.6, "ice": 0.5, "poison": 1.0},
	"crystal": {"name_id": "bio_crystal", "low": Color(0.18, 0.26, 0.38), "high": Color(0.58, 0.8, 0.92),
		"speed": 1.05, "fire": 1.0, "ice": 1.0, "poison": 1.0},
}

const LAVA_DPS := 1.5   # урон лави в секунду всем, кто стоит на вулкане

# Генерація біомів: порогові значення шуму (шум Перліна приблизно в межах -0.7..0.7).
const BIOME_GEN = {
	"freq": 0.012,           # менше - більші біоми
	"safe_radius": 14.0,     # навколо старту завжди луки
	"cold": -0.18,           # температура нижче - сніг
	"hot": 0.2,              # температура вище й сухо - пустеля
	"dry": 0.05,
	"wet": 0.18,             # вологість вище - болото (або кристали, якщо прохолодно)
	"magma": 0.3,            # магма вище - вулкан (рідкісні плями)
	"cwet": 0.28,            # для кристалів треба сиріше, ніж для болота
	"ctemp": 0.05,           # ...і прохолодніше за це
}

# Схили та висота.
const GROUND = {
	"slope_step": 0.6,       # на якій відстані міряємо схил
	"slope_effect": 0.6,     # як сильно схил впливає на швидкість
	"slope_min": 0.6,        # найповільніше (круто вгору)
	"slope_max": 1.4,        # найшвидше (круто вниз)
	"high_per_meter": 0.04,  # +4% шкоди за кожен метр висоти над ціллю
	"high_gain_cap": 0.35,   # максимум бонусу зверху
	"high_lose_cap": 0.15,   # максимум штрафу знизу
}

# Декорації: скільки спроб розкладки та що росте в якому біомі.
const DECOR = {
	"count": 380,
	"by_biome": {
		"meadow": ["tree", "tree", "rock"],
		"sand": ["cactus", "rock"],
		"snow": ["pine", "pine", "rock"],
		"swamp": ["dead", "tree"],
		"volcano": ["obsidian", "rock"],
		"crystal": ["crystree", "shard", "rock"],
	},
}

# ---------- Режим адаптивних ворогів (adaptive.gd) ----------
const ADAPTIVE = {
	"half_life": 25.0,    # як швидко "забувається" шкода (с)
	"min_total": 40.0,    # поки шкоди менше - адаптації немає
	"fair_share": 0.30,   # частка шкоди одного типу, до якої вороги не адаптуються
	"strength": 0.9,      # стійкість = (частка - fair_share) * strength
	"max_resist": 0.55,   # стеля стійкості
	"badge_min": 0.12,    # від якої стійкості ворог отримує кольоровий значок
}
