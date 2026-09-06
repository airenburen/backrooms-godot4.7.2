extends Node

signal stamina_changed(current: float, max_value: float)
signal flashlight_changed(is_on: bool, battery: float)
signal hint_changed(text: String)
signal settings_changed

var current_level: int = 0
var stamina: float = 100.0
var max_stamina: float = 100.0
var flashlight_on: bool = false
var flashlight_battery: float = 100.0
var max_flashlight_battery: float = 100.0

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
	load_settings()

func reset() -> void:
	current_level = 0
	stamina = max_stamina
	flashlight_on = false
	flashlight_battery = max_flashlight_battery

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
	apply_settings()
