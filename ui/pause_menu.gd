extends CanvasLayer

@onready var resume_button: Button = $CenterContainer/VBox/ResumeButton
@onready var settings_button: Button = $CenterContainer/VBox/SettingsButton
@onready var restart_button: Button = $CenterContainer/VBox/RestartButton
@onready var main_menu_button: Button = $CenterContainer/VBox/MainMenuButton
@onready var quit_button: Button = $CenterContainer/VBox/QuitButton
@onready var settings_menu: CanvasLayer = $SettingsMenu

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(_on_resume)
	settings_button.pressed.connect(_on_settings)
	restart_button.pressed.connect(_on_restart)
	main_menu_button.pressed.connect(_on_main_menu)
	quit_button.pressed.connect(_on_quit)
	settings_menu.closed.connect(_on_settings_closed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if settings_menu.visible:
			# 设置界面打开时，Esc 应先关闭设置界面（并保存），而不是跳过它直接恢复游戏
			settings_menu.close()
		elif get_tree().paused:
			_resume()
		else:
			_pause()

func _pause() -> void:
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()

func _resume() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume() -> void:
	_resume()

func _on_settings() -> void:
	$CenterContainer.visible = false
	settings_menu.open()

func _on_settings_closed() -> void:
	$CenterContainer.visible = true
	resume_button.grab_focus()

func _on_restart() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Loader.go_to("res://main/main.tscn")

func _on_main_menu() -> void:
	get_tree().paused = false
	visible = false
	# 回主菜单保持鼠标可见（主菜单 _ready 也会再设一次，这里防中间帧闪烁）
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Loader.go_to("res://main/main_menu.tscn")

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()
