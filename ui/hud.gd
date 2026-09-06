extends CanvasLayer

@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var battery_label: Label = $MarginContainer/VBoxContainer/BatteryLabel
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HintLabel
@onready var crosshair: ColorRect = $Crosshair

func _ready() -> void:
	GameState.stamina_changed.connect(_on_stamina_changed)
	GameState.flashlight_changed.connect(_on_flashlight_changed)
	GameState.hint_changed.connect(_on_hint_changed)
	stamina_bar.value = 100.0
	battery_label.text = "手电筒 [F] | 电量: --"
	hint_label.text = ""

func _on_stamina_changed(current: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = current
	stamina_bar.visible = current < max_value * 0.99

func _on_flashlight_changed(is_on: bool, battery: float) -> void:
	if is_on:
		battery_label.text = "手电筒 [F] 开启 | 电量: %d%%" % int(battery)
	else:
		battery_label.text = "手电筒 [F] 关闭"

func _on_hint_changed(text: String) -> void:
	hint_label.text = text
	hint_label.modulate.a = 1.0
	if text != "":
		var tween := create_tween()
		tween.tween_interval(4.0)
		tween.tween_property(hint_label, "modulate:a", 0.0, 1.0)
