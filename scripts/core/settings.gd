class_name Settings
# Налаштування гравця: чутливість миші, камера, тіні, FPS.
# Зберігаються в user://settings.cfg, читаються при старті (див. main.gd).

const PATH = "user://settings.cfg"

static var mouse_sens := 1.0
static var camera_dist := 10.0
static var invert_y := false
static var shadows := true
static var show_fps := false
static var lang := "en"
const LANGS := ["uk", "ru", "en"]
const LANG_NAMES := ["Українська", "Русский", "English"]
static var msaa := 2          # 0 вимк, 1 MSAA 2x, 2 MSAA 4x, 3 MSAA 8x (= Viewport.MSAA_*)
static var glow := true       # світіння магії (bloom)
static var max_fps := 0       # кап FPS: 0 без ліміту, інакше 30/60/120/144
const FPS_CHOICES := [30, 60, 120, 144, 0]
static var show_dmg := true   # цифри шкоди над ворогами
static var diff := 1          # складність: 0 легко, 1 норма, 2 складно
static var vsync := 1         # 0 вимк, 1 увімк, 2 адаптивний (= DisplayServer.VSYNC_*)
static var fov := 65.0        # поле зору камери
static var cls := "ranger"    # клас забігу (вибір на старті)


static func reset() -> void:
	mouse_sens = 1.0
	camera_dist = 10.0
	invert_y = false
	shadows = true
	show_fps = false
	msaa = 2
	glow = true
	max_fps = 0
	show_dmg = true
	diff = 1
	vsync = 1
	fov = 65.0
	cls = "ranger"


static func load_all() -> void:
	reset()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sens = clampf(float(cfg.get_value("game", "mouse_sens", 1.0)), 0.2, 3.0)
	camera_dist = clampf(float(cfg.get_value("game", "camera_dist", 10.0)), 6.0, 16.0)
	invert_y = bool(cfg.get_value("game", "invert_y", false))
	shadows = bool(cfg.get_value("game", "shadows", true))
	show_fps = bool(cfg.get_value("game", "show_fps", false))
	lang = str(cfg.get_value("game", "lang", "en"))
	if not LANGS.has(lang):
		lang = "en"
	Lang.code = lang
	msaa = clampi(int(cfg.get_value("game", "msaa", 2)), 0, 3)
	glow = bool(cfg.get_value("game", "glow", true))
	max_fps = int(cfg.get_value("game", "max_fps", 0))
	if not FPS_CHOICES.has(max_fps):
		max_fps = 0
	show_dmg = bool(cfg.get_value("game", "show_dmg", true))
	diff = clampi(int(cfg.get_value("game", "diff", 1)), 0, 2)
	vsync = clampi(int(cfg.get_value("game", "vsync", 1)), 0, 2)
	fov = clampf(float(cfg.get_value("game", "fov", 65.0)), 55.0, 90.0)
	cls = str(cfg.get_value("game", "cls", "ranger"))
	if not GameData.CLASS.has(cls):
		cls = "ranger"


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "mouse_sens", mouse_sens)
	cfg.set_value("game", "camera_dist", camera_dist)
	cfg.set_value("game", "invert_y", invert_y)
	cfg.set_value("game", "shadows", shadows)
	cfg.set_value("game", "show_fps", show_fps)
	cfg.set_value("game", "lang", lang)
	cfg.set_value("game", "msaa", msaa)
	cfg.set_value("game", "glow", glow)
	cfg.set_value("game", "max_fps", max_fps)
	cfg.set_value("game", "show_dmg", show_dmg)
	cfg.set_value("game", "diff", diff)
	cfg.set_value("game", "vsync", vsync)
	cfg.set_value("game", "fov", fov)
	cfg.set_value("game", "cls", cls)
	cfg.save(PATH)


# Застосувати те, що працює наживо (кап FPS + MSAA + VSync вікна).
static func apply_runtime() -> void:
	Engine.max_fps = max_fps
	var vsync_mode := DisplayServer.VSYNC_ENABLED
	if vsync == 0:
		vsync_mode = DisplayServer.VSYNC_DISABLED
	elif vsync == 2:
		vsync_mode = DisplayServer.VSYNC_ADAPTIVE
	DisplayServer.window_set_vsync_mode(vsync_mode)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.msaa_3d = msaa   # 0..3 збігається з Viewport.MSAA_DISABLED..MSAA_8X


static var _sun: DirectionalLight3D = null
static var _env: Environment = null


# Прив'язати світло/небо поточного забігу, щоб тіні й bloom мінялись і з паузи.
static func bind_world(sun: DirectionalLight3D, env: Environment) -> void:
	_sun = sun
	_env = env


static func apply_world() -> void:
	if is_instance_valid(_sun):
		_sun.shadow_enabled = shadows
	if is_instance_valid(_env):
		_env.glow_enabled = glow
