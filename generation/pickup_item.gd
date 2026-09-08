extends Area3D
# 拾取物：杏仁水（靠近按 E 拾取，带屏幕提示）/ 手电电池（触碰自动拾取）。
# level_base 负责选点生成；视觉上带缓慢旋转 + 上下浮动 + 微光，方便在暗处发现。

const SoundGen = preload("res://generation/sound_generator.gd")

enum Kind { ALMOND, BATTERY }

const PICKUP_RANGE := 2.6   # 杏仁水 E 拾取半径（米）
const BATTERY_AMOUNT := 35.0

# 描边色：杏仁水暖奶金 / 电池电光青（粒子同色系）
const OUTLINE_ALMOND := Color(1.0, 0.92, 0.62)
const OUTLINE_BATTERY := Color(0.45, 0.95, 1.0)

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
	_add_sparkles()

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
		glass.next_pass = _outline_mat(OUTLINE_ALMOND)
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
		cap_mat.next_pass = _outline_mat(OUTLINE_ALMOND)
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
		shell_mat.next_pass = _outline_mat(OUTLINE_BATTERY)
		holder.add_child(shell)
		var tip := CSGBox3D.new()
		tip.size = Vector3(0.05, 0.03, 0.05)
		tip.position = Vector3(0, 0.235, 0)
		var tip_mat := StandardMaterial3D.new()
		tip_mat.albedo_color = Color(0.85, 0.8, 0.5)
		tip_mat.metallic = 0.8
		tip_mat.roughness = 0.3
		tip.material = tip_mat
		tip_mat.next_pass = _outline_mat(OUTLINE_BATTERY)
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

# ── 描边与小粒子 ───────────────────────────────────────────

# 反转法线描边：同一网格沿法线微膨胀 + 只渲染背面，留下一圈不透光轮廓壳
func _outline_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = 0.015
	m.albedo_color = color
	return m

# 环绕小粒子（挂在根节点上，不随瓶子旋转/浮动）：杏仁水 = 缓缓上浮的暖光尘；电池 = 蹦跳的小电花
func _add_sparkles() -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	if kind == Kind.ALMOND:
		p.amount = 10
		p.lifetime = 1.6
		p.speed_scale = 0.7
		pm.gravity = Vector3(0, 0.25, 0)
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.15
		pm.spread = 60.0
		pm.emission_sphere_radius = 0.16
	else:
		p.amount = 8
		p.lifetime = 0.7
		pm.gravity = Vector3(0, -0.9, 0)
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 0.8
		pm.spread = 85.0
		pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0, 1, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = OUTLINE_ALMOND if kind == Kind.ALMOND else OUTLINE_BATTERY
	# 渐隐曲线：淡入 → 满亮 → 淡出（additive 下像呼吸的星光）
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex

	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.vertex_color_use_as_albedo = true
	quad.material = qm

	p.process_material = pm
	p.draw_pass_1 = quad
	p.position = Vector3(0, 0.28, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
