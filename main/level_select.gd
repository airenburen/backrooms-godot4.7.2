extends CanvasLayer
# 关卡选择界面：左侧「继续游戏 / 重新开始 / 返回」，右侧关卡卡片（自选起点）。
# 全开放不锁关——自用项目，想从哪关蹦跶就从哪关蹦跶。

signal closed

@onready var continue_button: Button = $Root/Margin/HBox/LeftCol/ContinueButton
@onready var continue_hint: Label = $Root/Margin/HBox/LeftCol/ContinueHint
@onready var restart_button: Button = $Root/Margin/HBox/LeftCol/RestartButton
@onready var back_button: Button = $Root/Margin/HBox/LeftCol/BackButton
@onready var cards_box: VBoxContainer = $Root/Margin/HBox/Cards

func _ready() -> void:
	visible = false
	continue_button.pressed.connect(_on_continue)
	restart_button.pressed.connect(_on_restart)
	back_button.pressed.connect(_on_back)
	_build_cards()

func _build_cards() -> void:
	for i in GameState.LEVEL_SCENES.size():
		var card := Button.new()
		card.text = "  " + GameState.LEVEL_TITLES[i]
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.custom_minimum_size = Vector2(420, 52)
		card.set("theme_override_font_sizes/font_size", 19)
		var desc := Label.new()
		desc.text = "    " + GameState.LEVEL_DESCS[i]
		desc.set("theme_override_font_sizes/font_size", 13)
		desc.modulate = Color(0.7, 0.68, 0.62)
		var idx := i
		card.pressed.connect(func() -> void: _start(idx, true))
		cards_box.add_child(card)
		cards_box.add_child(desc)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	continue_hint.text = "当前进度：%s" % GameState.LEVEL_TITLES[GameState.current_level]
	continue_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back()

func _start(level: int, fresh: bool = false) -> void:
	# 点关卡卡片 = 重新开始这一关（换新布局种子）；「继续游戏」仍回上次布局
	if fresh:
		GameState.regenerate_level_seed(level)
	GameState.start_level(level)
	Loader.go_to("res://main/main.tscn")

func _on_continue() -> void:
	_start(GameState.current_level)

func _on_restart() -> void:
	# 重新开始 = 新的一局：新 Level 0 布局
	_start(0, true)

func _on_back() -> void:
	visible = false
	closed.emit()
