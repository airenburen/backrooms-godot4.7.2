extends Node
# 场景切换加载遮罩：掩盖关卡程序化生成的卡顿帧 + 氛围过渡。
# 用法（任何地方，不必 await）：Loader.go_to("res://main/main.tscn")
# 流程：遮罩秒显 → 等 2 帧确保渲染 → 切场景 → 再等 2 帧让关卡 _ready
# 完成 → 停留片刻 → 淡出。autoload 常驻，切场景不销毁。

const HOLD := 0.25
const FADE_OUT := 0.45

var _root: Control
var _tween: Tween
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停态也能切场景
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_root = Control.new()
	_root.name = "FadeRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 挡住按钮连点
	_root.visible = false
	layer.add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.008)
	_root.add_child(dim)

	var title := Label.new()
	title.text = "B A C K R O O M S"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -220
	title.offset_right = 220
	title.offset_top = -30
	title.offset_bottom = 10
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	var hint := Label.new()
	hint.text = "正在进入下一层…"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	hint.set_anchors_preset(Control.PRESET_CENTER)
	hint.offset_left = -160
	hint.offset_right = 160
	hint.offset_top = 14
	hint.offset_bottom = 44
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(hint)

func go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	if _tween:
		_tween.kill()
	_root.visible = true
	_root.modulate.a = 1.0
	# 等 2 帧：遮罩先画出来，再干重活（切场景那一帧必卡，遮罩盖住它）
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(path)
	# 再等 2 帧：新场景 _ready（关卡全程同步构建）完成、首帧渲染后再淡出
	await get_tree().process_frame
	await get_tree().process_frame
	_tween = create_tween()
	_tween.tween_interval(HOLD)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(func() -> void:
		_root.visible = false
		_busy = false)
