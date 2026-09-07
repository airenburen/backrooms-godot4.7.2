extends Node

signal stamina_changed(current: float, max_value: float)
signal flashlight_changed(is_on: bool, battery: float)
signal hint_changed(text: String)
signal settings_changed
# 杏仁水收集进度（count, required）；拾取提示（靠近可拾取物时非空）
signal almond_changed(count: int, required: int)
signal pickup_prompt_changed(text: String)

# ── 关卡系统 ──────────────────────────────────────────────
# 关卡顺序（线性推进）：0 黄色迷宫 → 1 仓库 → 2 管道层 → 泳室 → 红色狂奔
const LEVEL_SCENES := [
	"res://levels/level_0.tscn",
	"res://levels/level_1.tscn",
	"res://levels/level_2.tscn",
	"res://levels/level_poolrooms.tscn",
	"res://levels/level_run.tscn",
]
const LEVEL_TITLES := [
	"Level 0 · 黄色迷宫",
	"Level 1 · 仓库",
	"Level 2 · 管道层",
	"Poolrooms · 泳室",
	"Level ! · 红色狂奔",
]
const LEVEL_DESCS := [
	"潮湿的地毯、单调的嗡鸣——一切的起点",
	"混凝土立柱与成堆货箱的漫无边库房",
	"狭窄维修隧道，绿色服务灯与沿墙管线",
	"无尽白瓷砖大厅与静水",
	"一条路，别回头",
]

var current_level: int = 0
# 每关布局种子：首次进入某关时生成并落盘，之后同关一律复用 → 「继续游戏」回到一模一样的布局
var level_seeds: Array[int] = []
var stamina: float = 100.0
var max_stamina: float = 100.0
var flashlight_on: bool = false
var flashlight_battery: float = 100.0
var max_flashlight_battery: float = 100.0
# 杏仁水：进关清零，集齐 required 瓶才能触发出口
var almond_water: int = 0
var almond_required: int = 3

var mouse_sensitivity: float = 0.002
var fov: float = 75.0
var master_volume: float = 0.8
var fullscreen: bool = false
var volumetric_light: bool = true
var dust_particles: bool = true
# 抗锯齿模式索引（0=关 … 10=SSAA 4×），详见 settings_menu 的 AA_OPTIONS
var anti_aliasing_mode: int = 4
var ssao_enabled: bool = true
var ssao_quality: int = 1

# 彩蛋（科乐美秘技）：运行时变量，刻意不进 save/load → 重启游戏自动关闭
var bhop_enabled: bool = false

func _ready() -> void:
	level_seeds.resize(LEVEL_SCENES.size())
	level_seeds.fill(-1)  # -1 = 该关尚未生成过布局种子
	load_settings()

func reset() -> void:
	# 只重置局内状态；current_level 由关卡系统管理（reset 不动进度）
	stamina = max_stamina
	flashlight_on = false
	flashlight_battery = max_flashlight_battery
	almond_water = 0
	almond_changed.emit(almond_water, almond_required)

# 从指定关卡开始（关卡选择界面调用）
func start_level(level: int) -> void:
	current_level = clampi(level, 0, LEVEL_SCENES.size() - 1)
	save_settings()

# 本关布局种子：未生成过则现场生成并落盘；已存在则复用（继续游戏/选关都回到同一布局）
func get_level_seed(level: int) -> int:
	var idx := clampi(level, 0, LEVEL_SCENES.size() - 1)
	if level_seeds.size() <= idx:
		level_seeds.resize(LEVEL_SCENES.size())
		level_seeds.fill(-1)
	if level_seeds[idx] < 0:
		level_seeds[idx] = randi()
		save_settings()
	return level_seeds[idx]

# 强制换新种子（「重新开始」= 新的一局 → 新布局）
func regenerate_level_seed(level: int) -> int:
	var idx := clampi(level, 0, LEVEL_SCENES.size() - 1)
	level_seeds[idx] = randi()
	save_settings()
	return level_seeds[idx]

# 出口触发后推进关卡；返回 false 表示已通关（回主菜单）
func advance_level() -> bool:
	if current_level >= LEVEL_SCENES.size() - 1:
		current_level = 0  # 通关归零：继续游戏=从头再来
		save_settings()
		return false
	current_level += 1
	save_settings()
	return true

func set_stamina(value: float) -> void:
	stamina = clampf(value, 0.0, max_stamina)
	stamina_changed.emit(stamina, max_stamina)

func set_flashlight(is_on: bool) -> void:
	flashlight_on = is_on
	flashlight_changed.emit(flashlight_on, flashlight_battery)

func set_flashlight_battery(value: float) -> void:
	flashlight_battery = clampf(value, 0.0, max_flashlight_battery)
	flashlight_changed.emit(flashlight_on, flashlight_battery)

func show_hint(text: String) -> void:
	hint_changed.emit(text)

func add_almond_water() -> void:
	almond_water += 1
	almond_changed.emit(almond_water, almond_required)

func reset_almond_progress(required: int) -> void:
	# 进关调用：清零计数并设定本关需求
	almond_required = maxi(required, 0)
	almond_water = 0
	almond_changed.emit(almond_water, almond_required)

func show_pickup_prompt(text: String) -> void:
	pickup_prompt_changed.emit(text)

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	apply_anti_aliasing()

# 把抗锯齿选择应用到根视口（所有 AA 都是 Viewport 属性，可实时切换）
func apply_anti_aliasing() -> void:
	var vp: Viewport = get_tree().root
	if vp == null:
		return
	# 先全部复位，再按模式叠加（多种 AA 可共存）
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	match anti_aliasing_mode:
		1:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		2:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		3:
			vp.msaa_3d = Viewport.MSAA_2X
		4:
			vp.msaa_3d = Viewport.MSAA_4X
		5:
			vp.msaa_3d = Viewport.MSAA_8X
		6:
			vp.use_taa = true
		7:
			vp.use_taa = true
			vp.msaa_3d = Viewport.MSAA_4X
		8:
			# FSR2 以原生分辨率跑，仅取其时域抗锯齿（开销高，需高端显卡）
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		9:
			# 超采样：双线性模式 + 缩放因子 > 1.0（1.5≈每像素 2.25 次，2.0≈4 次）
			vp.scaling_3d_scale = 1.5
		10:
			vp.scaling_3d_scale = 2.0

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("settings", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("settings", "fov", fov)
	config.set_value("settings", "master_volume", master_volume)
	config.set_value("settings", "fullscreen", fullscreen)
	config.set_value("settings", "volumetric_light", volumetric_light)
	config.set_value("settings", "dust_particles", dust_particles)
	config.set_value("settings", "anti_aliasing_mode", anti_aliasing_mode)
	config.set_value("settings", "ssao_enabled", ssao_enabled)
	config.set_value("settings", "ssao_quality", ssao_quality)
	# 进度与设置同文件分节存（自用项目，不单独开档）
	config.set_value("progress", "current_level", current_level)
	for i in level_seeds.size():
		config.set_value("progress", "seed_%d" % i, level_seeds[i])
	config.save("user://settings.cfg")

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		mouse_sensitivity = config.get_value("settings", "mouse_sensitivity", 0.002)
		fov = config.get_value("settings", "fov", 75.0)
		master_volume = config.get_value("settings", "master_volume", 0.8)
		fullscreen = config.get_value("settings", "fullscreen", false)
		volumetric_light = config.get_value("settings", "volumetric_light", true)
		dust_particles = config.get_value("settings", "dust_particles", true)
		anti_aliasing_mode = config.get_value("settings", "anti_aliasing_mode", 4)
		ssao_enabled = config.get_value("settings", "ssao_enabled", true)
		ssao_quality = config.get_value("settings", "ssao_quality", 1)
		current_level = clampi(int(config.get_value("progress", "current_level", 0)),
			0, LEVEL_SCENES.size() - 1)
		for i in LEVEL_SCENES.size():
			level_seeds[i] = int(config.get_value("progress", "seed_%d" % i, -1))
	apply_settings()
