extends Area3D
# 拾取物：杏仁水（靠近按 E 拾取，带屏幕提示）/ 手电电池（触碰自动拾取）。
# level_base 负责选点生成；视觉上带缓慢旋转 + 上下浮动 + 微光，方便在暗处发现。

const SoundGen = preload("res://generation/sound_generator.gd")

enum Kind { ALMOND, BATTERY }

const PICKUP_RANGE := 2.6   # 杏仁水 E 拾取半径（米）
const BATTERY_AMOUNT := 35.0

var kind: int = Kind.ALMOND
var _player: Node3D
var _visual: Node3D
var _time := 0.0
var _in_range := false

static func create(item_kind: int, at: Vector3) -> Area3D:
	var item: Area3D = load("res://generation/pickup_item.gd").new()
	item.kind = item_kind
	item.position = at
	return item

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	collision_layer = 0
	collision_mask = 1  # 玩家 CharacterBody3D 用默认 layer 1

	_visual = _build_visual(kind)
	add_child(_visual)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55 if kind == Kind.BATTERY else 0.8
	col.shape = shape
	col.position = Vector3(0, 0.4, 0)
	add_child(col)

	if kind == Kind.BATTERY:
		body_entered.connect(_on_body_entered)

func _build_visual(k: int) -> Node3D:
	var holder := Node3D.new()
	if k == Kind.ALMOND:
		# 玻璃瓶：半透明白瓶身 + 蓝盖 + 内液
		var body := CSGCylinder3D.new()
		body.radius = 0.07
		body.height = 0.26
		body.sides = 12
		body.position = Vector3(0, 0.13, 0)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.9, 0.93, 0.88, 0.55)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.15
		body.material = glass
		holder.add_child(body)
		var cap := CSGCylinder3D.new()
		cap.radius = 0.045
		cap.height = 0.05
		cap.sides = 10
		cap.position = Vector3(0, 0.285, 0)
		var cap_mat := StandardMaterial3D.new()
		cap_mat.albedo_color = Color(0.2, 0.35, 0.6)
		cap_mat.roughness = 0.4
		cap.material = cap_mat
		holder.add_child(cap)
		# 微光：暗处也能瞥见的一点暖光
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.95, 0.8)
		glow.light_energy = 0.5
		glow.omni_range = 2.2
		glow.shadow_enabled = false
		glow.position = Vector3(0, 0.35, 0)
		holder.add_child(glow)
	else:
		# 电池：深色方壳 + 浅色正极头
		var shell := CSGBox3D.new()
		shell.size = Vector3(0.12, 0.22, 0.12)
		shell.position = Vector3(0, 0.11, 0)
		var shell_mat := StandardMaterial3D.new()
		shell_mat.albedo_color = Color(0.15, 0.15, 0.17)
		shell_mat.roughness = 0.35
		shell_mat.metallic = 0.6
		shell.material = shell_mat
		holder.add_child(shell)
		var tip := CSGBox3D.new()
		tip.size = Vector3(0.05, 0.03, 0.05)
		tip.position = Vector3(0, 0.235, 0)
		var tip_mat := StandardMaterial3D.new()
		tip_mat.albedo_color = Color(0.85, 0.8, 0.5)
		tip_mat.metallic = 0.8
		tip_mat.roughness = 0.3
		tip.material = tip_mat
		holder.add_child(tip)
	return holder

func _physics_process(delta: float) -> void:
	_time += delta
	if _visual:
		_visual.rotation.y += delta * 1.2
		_visual.position.y = 0.06 * sin(_time * 2.0)
	if kind != Kind.ALMOND or _player == null:
		return
	var dist: float = _player.global_position.distance_to(global_position)
	var now_in_range: bool = dist <= PICKUP_RANGE
	if now_in_range != _in_range:
		_in_range = now_in_range
		GameState.show_pickup_prompt("按 [E] 拾取杏仁水" if _in_range else "")

func _unhandled_input(event: InputEvent) -> void:
	# E 拾取：仅在近处响应（提示由 _physics_process 驱动，这里只管按键）
	if kind == Kind.ALMOND and _in_range and event.is_action_pressed("interact"):
		_collect()

func _on_body_entered(body: Node3D) -> void:
	# 电池：玩家碰到即充能
	if body is CharacterBody3D and body.is_in_group("player"):
		body.add_battery(BATTERY_AMOUNT)
		GameState.show_hint("拾取电池：手电筒电量 +%d%%" % int(BATTERY_AMOUNT))
		_play_click(body)
		queue_free()

func _collect() -> void:
	GameState.add_almond_water()
	GameState.show_pickup_prompt("")
	GameState.show_hint("杏仁水（%d/%d）" % [GameState.almond_water, GameState.almond_required])
	if _player:
		_play_click(_player)
	queue_free()

func _play_click(listener: Node3D) -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = SoundGen.create_click()
	audio.volume_db = -6.0
	listener.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
