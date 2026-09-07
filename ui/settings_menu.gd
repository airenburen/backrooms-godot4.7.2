extends CanvasLayer

signal closed

@onready var mouse_sens_slider: HSlider = $CenterContainer/Panel/VBox/MouseSensRow/MouseSensSlider
@onready var mouse_sens_value: Label = $CenterContainer/Panel/VBox/MouseSensRow/MouseSensValue
@onready var fov_slider: HSlider = $CenterContainer/Panel/VBox/FOVRow/FOVSlider
@onready var fov_value: Label = $CenterContainer/Panel/VBox/FOVRow/FOVValue
@onready var volume_slider: HSlider = $CenterContainer/Panel/VBox/VolumeRow/VolumeSlider
@onready var volume_value: Label = $CenterContainer/Panel/VBox/VolumeRow/VolumeValue
@onready var fullscreen_check: CheckBox = $CenterContainer/Panel/VBox/FullscreenCheck
@onready var volumetric_check: CheckBox = $CenterContainer/Panel/VBox/VolumetricCheck
@onready var dust_check: CheckBox = $CenterContainer/Panel/VBox/DustCheck
@onready var aa_option: OptionButton = $CenterContainer/Panel/VBox/AARow/AAOption
@onready var ssao_check: CheckBox = $CenterContainer/Panel/VBox/SSAORow/SSAOCheck
@onready var ssao_quality_option: OptionButton = $CenterContainer/Panel/VBox/SSAORow/SSAOQualityOption
@onready var back_button: Button = $CenterContainer/Panel/VBox/BackButton

# 抗锯齿选项（索引对应 GameState.anti_aliasing_mode）
const AA_OPTIONS := [
	"关闭", "FXAA", "SMAA 1x", "MSAA 2×", "MSAA 4×", "MSAA 8×",
	"TAA", "MSAA 4× + TAA", "FSR2（原生）", "SSAA 2.25×", "SSAA 4×",
]
const SSAO_OPTIONS := ["低", "中", "高"]

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in AA_OPTIONS.size():
		aa_option.add_item(AA_OPTIONS[i], i)
	for i in SSAO_OPTIONS.size():
		ssao_quality_option.add_item(SSAO_OPTIONS[i], i)
	_load_values()
	mouse_sens_slider.value_changed.connect(_on_mouse_sens_changed)
	fov_slider.value_changed.connect(_on_fov_changed)
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	volumetric_check.toggled.connect(_on_volumetric_toggled)
	dust_check.toggled.connect(_on_dust_toggled)
	aa_option.item_selected.connect(_on_aa_selected)
	ssao_check.toggled.connect(_on_ssao_toggled)
	ssao_quality_option.item_selected.connect(_on_ssao_quality_selected)
	back_button.pressed.connect(_on_back)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_button.grab_focus()

func close() -> void:
	# 统一在此落盘：滑条拖动不写磁盘（此前音量每帧写一次，灵敏度/FOV 却不存，行为分裂）
	GameState.save_settings()
	visible = false
	closed.emit()

func _load_values() -> void:
	mouse_sens_slider.value = GameState.mouse_sensitivity
	fov_slider.value = GameState.fov
	volume_slider.value = GameState.master_volume
	fullscreen_check.button_pressed = GameState.fullscreen
	volumetric_check.button_pressed = GameState.volumetric_light
	dust_check.button_pressed = GameState.dust_particles
	aa_option.selected = clampi(GameState.anti_aliasing_mode, 0, AA_OPTIONS.size() - 1)
	ssao_check.button_pressed = GameState.ssao_enabled
	ssao_quality_option.selected = clampi(GameState.ssao_quality, 0, SSAO_OPTIONS.size() - 1)
	ssao_quality_option.disabled = not GameState.ssao_enabled
	_update_labels()

func _update_labels() -> void:
	mouse_sens_value.text = "%.4f" % GameState.mouse_sensitivity
	fov_value.text = "%d" % int(GameState.fov)
	volume_value.text = "%d%%" % int(GameState.master_volume * 100)

func _on_mouse_sens_changed(value: float) -> void:
	GameState.mouse_sensitivity = value
	GameState.settings_changed.emit()
	_update_labels()

func _on_fov_changed(value: float) -> void:
	GameState.fov = value
	GameState.settings_changed.emit()
	_update_labels()

func _on_volume_changed(value: float) -> void:
	GameState.master_volume = value
	GameState.apply_settings()
	_update_labels()

func _on_fullscreen_toggled(pressed: bool) -> void:
	GameState.fullscreen = pressed
	GameState.apply_settings()

func _on_volumetric_toggled(pressed: bool) -> void:
	GameState.volumetric_light = pressed
	GameState.settings_changed.emit()

func _on_dust_toggled(pressed: bool) -> void:
	GameState.dust_particles = pressed
	GameState.settings_changed.emit()

func _on_aa_selected(index: int) -> void:
	GameState.anti_aliasing_mode = index
	GameState.apply_anti_aliasing()

func _on_ssao_toggled(pressed: bool) -> void:
	GameState.ssao_enabled = pressed
	ssao_quality_option.disabled = not pressed
	GameState.settings_changed.emit()

func _on_ssao_quality_selected(index: int) -> void:
	GameState.ssao_quality = index
	GameState.settings_changed.emit()

func _on_back() -> void:
	close()
