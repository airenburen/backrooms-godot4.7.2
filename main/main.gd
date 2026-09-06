extends Node

func _ready() -> void:
	GameState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
