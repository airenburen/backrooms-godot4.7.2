extends Node
# 开发者控制台（自用调试工具）：` 或 F1 呼出 → 输入命令回车执行 → Esc 关闭
#   ↑/↓ 翻历史，Tab 补全命令名
# 打开时只停玩家的物理帧、**不暂停游戏**（灯光氛围照常），避免和 Esc 暂停菜单抢暂停状态。
# 与 loader.gd 同一路子：纯代码搭 UI，不存档、不进 UI 主题。

const MAX_HISTORY := 64
const COLOR_SYS := "#7fd8a0"
const COLOR_ERR := "#e0857f"
const COLOR_DIM := "#8a8676"

var _open := false
var _layer: CanvasLayer
var _root: Control
var _log: RichTextLabel
var _input_field: LineEdit
# 命令表：name -> {"args": String, "desc": String, "fn": Callable}
var _commands: Dictionary = {}
var _history: Array[String] = []
var _history_idx := 0
# 打开控制台前的玩家物理状态，关闭时按原样还回去
var _player_was_processing := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停态也能呼出
	_build_ui()
	_register_commands()

# ── UI ─────────────────────────────────────────────────────

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128  # 高于 Loader 的 100：切场景遮罩盖不住控制台
	add_child(_layer)

	_root = Control.new()
	_root.name = "ConsoleRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 别抢 LineEdit 的焦点
	_root.visible = false
	_layer.add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.015, 0.85)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.focus_mode = Control.FOCUS_NONE
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", Color(0.88, 0.87, 0.80))
	box.add_child(_log)

	var row := HBoxContainer.new()
	box.add_child(row)

	var caret := Label.new()
	caret.text = "> "
	caret.add_theme_color_override("font_color", Color(0.50, 0.85, 0.60))
	row.add_child(caret)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "输入命令后回车，help 列出全部（Tab 补全 / ↑↓ 历史）"
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.text_submitted.connect(_on_submit)
	row.add_child(_input_field)

	_append("开发者控制台就绪 · 输入 help 查看命令", COLOR_SYS)

# ── 开关与输入 ─────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		if _open:
			_close()
		else:
			_open_console()
		get_viewport().set_input_as_handled()
		return
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()
		KEY_UP:
			_history_step(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_history_step(1)
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_autocomplete()
			get_viewport().set_input_as_handled()

func _open_console() -> void:
	_open = true
	_root.visible = true
	_input_field.clear()
	_input_field.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Input.is_action_pressed 是原始状态查询，按键事件被 LineEdit 吃掉也照样为真，
	# 所以必须直接停掉玩家物理帧，否则打字时人还在原地走
	var p := _player()
	if p:
		_player_was_processing = p.is_physics_processing()
		p.set_physics_process(false)

func _close() -> void:
	_open = false
	_root.visible = false
	var p := _player()
	if p and _player_was_processing:
		p.set_physics_process(true)
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── 输出与执行 ─────────────────────────────────────────────

func _append(text: String, color := "") -> void:
	var safe := text.replace("[", "[lb]")
	if color.is_empty():
		_log.append_text(safe + "\n")
	else:
		_log.append_text("[color=%s]%s[/color]\n" % [color, safe])

func _on_submit(text: String) -> void:
	_input_field.clear()
	var line := text.strip_edges()
	if line.is_empty():
		return
	_append("> " + line, COLOR_SYS)
	if _history.is_empty() or _history[-1] != line:
		_history.append(line)
		if _history.size() > MAX_HISTORY:
			_history.pop_front()
	_history_idx = _history.size()
	_execute(line)

func _execute(line: String) -> void:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return
	var name := parts[0].to_lower()
	if not _commands.has(name):
		_append("未知命令：%s（输入 help 查看全部）" % name, COLOR_ERR)
		return
	var out: Variant = (_commands[name]["fn"] as Callable).call(parts.slice(1))
	if out is String and not (out as String).is_empty():
		_append(out)

func _history_step(step: int) -> void:
	if _history.is_empty():
		return
	_history_idx = clampi(_history_idx + step, 0, _history.size())
	_input_field.text = "" if _history_idx == _history.size() else _history[_history_idx]
	_input_field.caret_column = _input_field.text.length()

func _autocomplete() -> void:
	var word := _input_field.text.strip_edges()
	if word.contains(" "):
		return
	var matches: Array[String] = []
	for key in _commands.keys():
		if (key as String).begins_with(word):
			matches.append(key)
	matches.sort()
	if matches.size() == 1:
		_input_field.text = matches[0] + " "
		_input_field.caret_column = _input_field.text.length()
	elif matches.size() > 1:
		_append("候选：" + ", ".join(matches), COLOR_DIM)

# ── 命令注册 ───────────────────────────────────────────────

func register(name: String, args: String, desc: String, fn: Callable) -> void:
	_commands[name] = {"args": args, "desc": desc, "fn": fn}

func _register_commands() -> void:
	register("help", "[命令]", "列出全部命令，或查看某条命令", _cmd_help)
	register("clear", "", "清空控制台输出", _cmd_clear)
	register("level", "[0-4]", "查看当前关卡，或跳到指定关卡（刷新本关布局）", _cmd_level)
	register("reload", "", "重载当前关卡（沿用本关种子，布局不变）", _cmd_reload)
	register("seed", "[整数]", "查看或设置当前关卡布局种子并重载", _cmd_seed)
	register("exit", "", "把玩家传送到本关出口格", _cmd_exit)
	register("almond", "[数量]", "补齐当前关卡所需的杏仁水", _cmd_almond)
	register("stamina", "", "体力回满", _cmd_stamina)
	register("battery", "", "手电电量回满", _cmd_battery)
	register("noclip", "", "开关穿墙飞行（空格升 / Ctrl 降 / Shift 加速）", _cmd_noclip)
	register("speed", "[倍率]", "查看或设置移动速度倍率", _cmd_speed)
	register("bhop", "[on|off]", "开关连跳彩蛋（本局有效，不存档）", _cmd_bhop)
	register("fov", "[角度]", "查看或设置视野 FOV", _cmd_fov)
	register("volume", "[0-1]", "查看或设置主音量", _cmd_volume)
	register("dust", "[on|off]", "开关空气中的灰尘粒子", _cmd_dust)
	register("volumetric", "[on|off]", "开关体积雾/体积光", _cmd_volumetric)
	register("menu", "", "返回主菜单", _cmd_menu)
	register("quit", "", "退出游戏", _cmd_quit)

# ── 命令实现 ───────────────────────────────────────────────

func _cmd_help(args: PackedStringArray) -> String:
	if not args.is_empty():
		var key := args[0].to_lower()
		if not _commands.has(key):
			return "没有这条命令：%s" % key
		var one: Dictionary = _commands[key]
		return "%s %s\n    %s" % [key, one["args"], one["desc"]]
	var lines: Array[String] = ["可用命令（%d 条）：" % _commands.size()]
	var names := _commands.keys()
	names.sort()
	for n in names:
		var c: Dictionary = _commands[n]
		lines.append("  %-11s %-12s %s" % [n, c["args"], c["desc"]])
	return "\n".join(lines)

func _cmd_clear(_args: PackedStringArray) -> String:
	_log.clear()
	return ""

func _cmd_level(args: PackedStringArray) -> String:
	if args.is_empty():
		return "当前关卡：%d（%s）" % [GameState.current_level,
			GameState.LEVEL_TITLES[GameState.current_level]]
	if not args[0].is_valid_int():
		return "用法：level [0-%d]" % (GameState.LEVEL_SCENES.size() - 1)
	var idx := int(args[0])
	if idx < 0 or idx >= GameState.LEVEL_SCENES.size():
		return "关卡编号范围是 0~%d" % (GameState.LEVEL_SCENES.size() - 1)
	GameState.start_level(idx)
	GameState.regenerate_level_seed(idx)  # 直接跳关按"新的一局"处理，刷新布局
	_goto_scene("res://main/main.tscn")
	return "进入 %s" % GameState.LEVEL_TITLES[idx]

func _cmd_reload(_args: PackedStringArray) -> String:
	_goto_scene("res://main/main.tscn")
	return "重载当前关卡"

func _cmd_seed(args: PackedStringArray) -> String:
	var idx := GameState.current_level
	if args.is_empty():
		return "当前关卡种子：%d" % GameState.get_level_seed(idx)
	if not args[0].is_valid_int():
		return "用法：seed [整数]"
	GameState.get_level_seed(idx)  # 保证种子数组已初始化
	GameState.level_seeds[idx] = int(args[0])
	GameState.save_settings()
	_goto_scene("res://main/main.tscn")
	return "种子设为 %d，重载关卡" % int(args[0])

func _cmd_exit(_args: PackedStringArray) -> String:
	var lv := _level()
	var p := _player()
	if lv == null or p == null:
		return "当前不在关卡里"
	# 落在出口格中心：门贴在格子边缘，站中心不会被检测盒立刻吞掉（走进门才算过关）
	var cell: Vector2i = lv.get("exit_cell")
	p.global_position = lv.call("_cell_to_world", cell) + Vector3(0, 1.0, 0)
	return "已传送到出口（杏仁水 %d/%d）" % [GameState.almond_water, GameState.almond_required]

func _cmd_almond(args: PackedStringArray) -> String:
	var target := GameState.almond_required
	if not args.is_empty():
		if not args[0].is_valid_int():
			return "用法：almond [数量]（不给参数 = 补齐到本关需求）"
		target = maxi(int(args[0]), 0)
	while GameState.almond_water < target:
		GameState.add_almond_water()
	if GameState.almond_water > target:
		GameState.almond_water = target
		GameState.almond_changed.emit(GameState.almond_water, GameState.almond_required)
	return "杏仁水 %d/%d" % [GameState.almond_water, GameState.almond_required]

func _cmd_stamina(_args: PackedStringArray) -> String:
	var p := _player()
	if p == null:
		return "找不到玩家"
	p.call("restore_stamina", 100.0)
	return "体力回满"

func _cmd_battery(_args: PackedStringArray) -> String:
	var p := _player()
	if p == null:
		return "找不到玩家"
	p.call("add_battery", 100.0)
	return "手电电量回满"

func _cmd_noclip(_args: PackedStringArray) -> String:
	var p := _player()
	if p == null:
		return "找不到玩家（主菜单里没有玩家）"
	var on: bool = not p.get("noclip")
	p.set("noclip", on)
	return "穿墙飞行：%s（空格升 / Ctrl 降 / Shift 加速）" % ("开" if on else "关")

func _cmd_speed(args: PackedStringArray) -> String:
	var p := _player()
	if p == null:
		return "找不到玩家"
	if args.is_empty():
		return "移动速度倍率：%.2f" % float(p.get("speed_multiplier"))
	if not args[0].is_valid_float():
		return "用法：speed [倍率]"
	var mult := maxf(float(args[0]), 0.1)
	p.set("speed_multiplier", mult)
	return "移动速度倍率：%.2f" % mult

func _cmd_bhop(args: PackedStringArray) -> String:
	GameState.bhop_enabled = _toggle_bool(args, GameState.bhop_enabled)
	return "连跳彩蛋：%s" % ("开" if GameState.bhop_enabled else "关")

func _cmd_fov(args: PackedStringArray) -> String:
	if args.is_empty():
		return "当前 FOV：%.1f" % GameState.fov
	if not args[0].is_valid_float():
		return "用法：fov [角度]"
	GameState.fov = clampf(float(args[0]), 30.0, 140.0)
	GameState.save_settings()
	GameState.settings_changed.emit()  # 玩家相机在这里同步
	return "FOV：%.1f" % GameState.fov

func _cmd_volume(args: PackedStringArray) -> String:
	if args.is_empty():
		return "当前主音量：%.2f" % GameState.master_volume
	if not args[0].is_valid_float():
		return "用法：volume [0-1]"
	GameState.master_volume = clampf(float(args[0]), 0.0, 1.0)
	GameState.save_settings()
	GameState.apply_settings()
	return "主音量：%.2f" % GameState.master_volume

func _cmd_dust(args: PackedStringArray) -> String:
	GameState.dust_particles = _toggle_bool(args, GameState.dust_particles)
	GameState.save_settings()
	GameState.settings_changed.emit()  # 关卡在这里重挂 DustField 可见性
	return "灰尘粒子：%s" % ("开" if GameState.dust_particles else "关")

func _cmd_volumetric(args: PackedStringArray) -> String:
	GameState.volumetric_light = _toggle_bool(args, GameState.volumetric_light)
	GameState.save_settings()
	GameState.settings_changed.emit()
	return "体积雾/体积光：%s" % ("开" if GameState.volumetric_light else "关")

func _cmd_menu(_args: PackedStringArray) -> String:
	_goto_scene("res://main/main_menu.tscn")
	return "返回主菜单"

func _cmd_quit(_args: PackedStringArray) -> String:
	get_tree().quit()
	return ""

# ── 小工具 ─────────────────────────────────────────────────

# args 为空 = 取反；给了 on/off 之类的词按其解析
func _toggle_bool(args: PackedStringArray, current: bool) -> bool:
	if args.is_empty():
		return not current
	return args[0].to_lower() in ["on", "1", "true", "yes", "开"]

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

# main.tscn 的 Level 节点下挂着唯一的关卡实例
func _level() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var holder := scene.get_node_or_null("Level")
	if holder == null:
		return null
	return holder.get_child(0) if holder.get_child_count() > 0 else null

func _goto_scene(path: String) -> void:
	_close()
	Loader.go_to(path)