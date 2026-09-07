extends Node

func _ready() -> void:
	GameState.reset()
	# 按 GameState.current_level 动态装配关卡场景（关卡内部用 group "player" 找玩家）
	var idx := clampi(GameState.current_level, 0, GameState.LEVEL_SCENES.size() - 1)
	var level_scene: PackedScene = load(GameState.LEVEL_SCENES[idx])
	if level_scene:
		$Level.add_child(level_scene.instantiate())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
