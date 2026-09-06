extends Node3D

const FlickeringLight = preload("res://generation/flickering_light.gd")
const SoundGen = preload("res://generation/sound_generator.gd")
const MatLib = preload("res://generation/material_lib.gd")
const DustField = preload("res://generation/dust_field.gd")
const Atmosphere = preload("res://generation/atmosphere.gd")

@onready var camera: Camera3D = $Camera3D
@onready var start_button: Button = $UI/CenterContainer/VBox/StartButton
@onready var settings_button: Button = $UI/CenterContainer/VBox/SettingsButton
@onready var quit_button: Button = $UI/CenterContainer/VBox/QuitButton
@onready var settings_menu: CanvasLayer = $SettingsMenu
@onready var bhop_toggle: CheckBox = $UI/BhopToggle
@onready var cheat_toast: PanelContainer = $UI/CheatToast
@onready var cheat_toast_label: Label = $UI/CheatToast/Label

# ── 彩蛋：科乐美秘技变体「上上下下左右左右 BABA」──────────────────
# 方向键两组都认（独立方向键区 / 小键盘数字 8246，NumLock 开关均可），A/B 用主键盘。
# 试错宽容：每步间隔 3 秒超时才清进度；打错不清零而是回退到前缀匹配；
# 连续失败 3 次开始给提示，之后每失败 3 次显示当前进度。
const SEQUENCE: Array[String] = ["U", "U", "D", "D", "L", "R", "L", "R", "B", "A", "B", "A"]
const STEP_TIMEOUT_MS := 3000
const HINT_EVERY_FAILS := 3

var _seq_pos: int = 0
var _seq_last_ms: int = 0
var _fail_count: int = 0
var _toast_tween: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background_room()
	_setup_atmosphere()
	_add_dust()
	GameState.settings_changed.connect(_on_settings_changed)
	start_button.pressed.connect(_on_start)
	settings_button.pressed.connect(_on_settings)
	quit_button.pressed.connect(_on_quit)
	settings_menu.closed.connect(_on_settings_closed)
	bhop_toggle.toggled.connect(_on_bhop_toggled)
	# 同一局内已解锁过（回主菜单再进），开关保持可见可用
	bhop_toggle.visible = GameState.bhop_enabled
	bhop_toggle.button_pressed = GameState.bhop_enabled

# _input 先于 GUI 焦点导航执行，方向键不会被按钮抢焦点干扰
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_feed_cheat(_key_token(event))

static func _key_token(event: InputEventKey) -> String:
	match event.keycode:
		KEY_UP, KEY_KP_8: return "U"
		KEY_DOWN, KEY_KP_2: return "D"
		KEY_LEFT, KEY_KP_4: return "L"
		KEY_RIGHT, KEY_KP_6: return "R"
	match event.physical_keycode:
		KEY_B: return "B"
		KEY_A: return "A"
	return ""

func _feed_cheat(token: String) -> void:
	if token.is_empty():
		return
	var now := Time.get_ticks_msec()
	if _seq_pos > 0 and now - _seq_last_ms > STEP_TIMEOUT_MS:
		_seq_pos = 0  # 超时静默重来，不算失败
	if token == SEQUENCE[_seq_pos]:
		_seq_pos += 1
		_seq_last_ms = now
		if _seq_pos >= SEQUENCE.size():
			_seq_pos = 0
			_fail_count = 0
			_unlock_bhop()
		return
	# 打错：回退重匹配（支持重叠前缀，如 UUDU 的最后一个 U）
	_fail_count += 1
	_seq_pos = 0 if token != SEQUENCE[0] else 1
	_seq_last_ms = now
	if _fail_count % HINT_EVERY_FAILS == 0:
		if _fail_count == HINT_EVERY_FAILS:
			_show_toast("嗯… 方向键（小键盘也行）+ B / A，试试看？", 2.5)
		else:
			_show_toast("秘技进度 %d/%d" % [_seq_pos, SEQUENCE.size()], 1.6)

func _unlock_bhop() -> void:
	GameState.bhop_enabled = true
	bhop_toggle.visible = true
	bhop_toggle.button_pressed = true
	_show_toast("★ 秘技成功 —「连跳」已解锁，左下角可随时开关", 4.0)

func _on_bhop_toggled(pressed: bool) -> void:
	GameState.bhop_enabled = pressed

# 底部小弹窗：淡入 → 停留 → 淡出
func _show_toast(text: String, hold: float) -> void:
	cheat_toast_label.text = text
	cheat_toast.visible = true
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	cheat_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(cheat_toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(hold)
	_toast_tween.tween_property(cheat_toast, "modulate:a", 0.0, 0.45)

func _setup_atmosphere() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		Atmosphere.configure(world_env.environment)

func _add_dust() -> void:
	# 菜单背景走廊固定，浮尘静止布置即可，无需跟随相机
	var dust := DustField.new()
	dust.name = "DustField"
	dust.setup(null, 250, Vector3(1.8, 1.4, 6.0))
	dust.position = Vector3(0, 1.5, 0)
	dust.visible = GameState.dust_particles
	add_child(dust)

func _on_settings_changed() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		Atmosphere.configure(world_env.environment)
	var dust := get_node_or_null("DustField")
	if dust:
		dust.visible = GameState.dust_particles

func _build_background_room() -> void:
	var wall_mat := MatLib.wall_mat()
	var floor_mat := MatLib.floor_mat()
	var ceiling_mat := MatLib.ceiling_mat()

	var floor_node := CSGBox3D.new()
	floor_node.size = Vector3(4, 0.2, 14)
	floor_node.position = Vector3(0, -0.1, 0)
	floor_node.material = floor_mat
	add_child(floor_node)

	var ceiling := CSGBox3D.new()
	ceiling.size = Vector3(4, 0.2, 14)
	ceiling.position = Vector3(0, 3.1, 0)
	ceiling.material = ceiling_mat
	add_child(ceiling)

	var left_wall := CSGBox3D.new()
	left_wall.size = Vector3(0.3, 3, 14)
	left_wall.position = Vector3(-2, 1.5, 0)
	left_wall.material = wall_mat
	add_child(left_wall)

	var right_wall := CSGBox3D.new()
	right_wall.size = Vector3(0.3, 3, 14)
	right_wall.position = Vector3(2, 1.5, 0)
	right_wall.material = wall_mat
	add_child(right_wall)

	var back_wall := CSGBox3D.new()
	back_wall.size = Vector3(4.6, 3, 0.3)
	back_wall.position = Vector3(0, 1.5, -7)
	back_wall.material = wall_mat
	add_child(back_wall)

	var light1 := OmniLight3D.new()
	light1.position = Vector3(0, 2.6, -2)
	light1.light_color = Color(1, 0.95, 0.8)
	light1.light_energy = 1.2
	light1.omni_range = 8.0
	light1.omni_attenuation = 1.5
	add_child(light1)

	var light2 := FlickeringLight.new()
	light2.position = Vector3(0, 2.6, 2)
	light2.light_color = Color(1, 0.95, 0.8)
	light2.light_energy = 0.8
	light2.omni_range = 6.0
	light2.omni_attenuation = 2.0
	add_child(light2)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.35, 0.32, 0.22)
	fill.light_energy = 0.15
	fill.rotation_degrees = Vector3(-55, 25, 0)
	add_child(fill)

	var hum := AudioStreamPlayer.new()
	hum.stream = SoundGen.create_ambient_hum()
	hum.volume_db = -18.0
	add_child(hum)
	hum.play()

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	camera.rotation.z = sin(t * 0.4) * 0.008
	camera.position.y = 1.5 + sin(t * 0.3) * 0.015

func _on_start() -> void:
	get_tree().change_scene_to_file("res://main/main.tscn")

func _on_settings() -> void:
	settings_menu.open()

func _on_settings_closed() -> void:
	start_button.grab_focus()

func _on_quit() -> void:
	get_tree().quit()
