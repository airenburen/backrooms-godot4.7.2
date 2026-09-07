extends CanvasLayer

@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var battery_label: Label = $MarginContainer/VBoxContainer/BatteryLabel
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HintLabel
@onready var almond_label: Label = $TaskPanel/AlmondLabel
@onready var task_panel: VBoxContainer = $TaskPanel
@onready var pickup_prompt: Label = $PickupPrompt
@onready var crosshair: ColorRect = $Crosshair
@onready var vignette: ColorRect = $Vignette

var _hint_tween: Tween
# 追逐红脉冲（Level !）：由关卡 set_chase_pulse 驱动，越接近出口边缘越红、心跳越快
var _chase_strength := 0.0
var _chase_time := 0.0

func _ready() -> void:
	GameState.stamina_changed.connect(_on_stamina_changed)
	GameState.flashlight_changed.connect(_on_flashlight_changed)
	GameState.hint_changed.connect(_on_hint_changed)
	GameState.almond_changed.connect(_on_almond_changed)
	GameState.pickup_prompt_changed.connect(_on_pickup_prompt_changed)
	stamina_bar.value = 100.0
	battery_label.text = "手电筒 [F] | 电量: --"
	hint_label.text = ""
	pickup_prompt.text = ""
	vignette.visible = false  # 非追逐关不挂全屏暗角

func _on_stamina_changed(current: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = current
	stamina_bar.visible = current < max_value * 0.99

func _on_flashlight_changed(is_on: bool, battery: float) -> void:
	if is_on:
		battery_label.text = "手电筒 [F] 开启 | 电量: %d%%" % int(battery)
	else:
		battery_label.text = "手电筒 [F] 关闭"

func _on_almond_changed(count: int, required: int) -> void:
	# 任务面板：进度 + 集齐变绿；需求 0（理论配置）时整块隐藏
	task_panel.visible = required > 0
	if count >= required and required > 0:
		almond_label.text = "杏仁水 %d/%d ✓" % [count, required]
		almond_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.55, 0.95))
	else:
		almond_label.text = "杏仁水 %d/%d" % [count, required]
		almond_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65, 0.9))

func _on_pickup_prompt_changed(text: String) -> void:
	pickup_prompt.text = text

func _on_hint_changed(text: String) -> void:
	hint_label.text = text
	hint_label.modulate.a = 1.0
	if text == "":
		return
	# 旧 tween 不 kill 的话，会在新提示显示期间把透明度拉没
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(4.0)
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 1.0)

# Level ! 追逐反馈：progress 0→1（出生→出口）。非追逐关卡从不调用。
func set_chase_pulse(progress: float) -> void:
	_chase_strength = clampf(progress, 0.0, 1.0)
	vignette.visible = _chase_strength > 0.01
	if _chase_strength <= 0.01:
		return
	# 亮灯状态不归 HUD 管，这里只驱动暗角 shader
	var mat: ShaderMaterial = vignette.material
	mat.set_shader_parameter("vignette_strength", _chase_strength)

func _process(delta: float) -> void:
	if _chase_strength <= 0.01 or not is_instance_valid(vignette) or vignette.material == null:
		return
	_chase_time += delta
	# 心跳：越接近出口频率越快（strength 越大）、波幅越高
	var rate := 6.0 + 16.0 * _chase_strength
	var pulse := 0.5 + 0.5 * sin(_chase_time * rate * TAU)
	(vignette.material as ShaderMaterial).set_shader_parameter("pulse", pulse)
