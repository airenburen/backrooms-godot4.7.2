class_name LandmarkBreadcrumb
extends Node3D
# 弱引导「地标」v2：沿通往出口的路径放置与环境反差的小结构，
# 靠颜色/形状的自然吸引力把玩家目光往前带——而不是直白的箭头。
# v2：每类地标多种状态（完好/残破/虚掩…），并优先贴墙摆放，
# 更像"环境本来就有"——迷路时余光被牵引，认真找路的人察觉不到规律。
#
# 贴墙约定：root 原点落在墙面上，+Z 指向墙内、-Z 朝走廊（与出口传送门一致）；
# 地面款 root 原点在格子中心，朝向行进方向。

enum Kind { MONOLITH, ARCH, BEACON }

# 有墙可用时各类选择贴墙的概率（门框必贴墙——立在走廊正中的门框太假）
const WALL_CHANCE := {
	Kind.MONOLITH: 0.35,
	Kind.ARCH: 1.0,
	Kind.BEACON: 0.65,
}

static func create(kind: int, facing: Vector2i, wall_dirs: Array[Vector2i], wall_face_dist: float) -> Node3D:
	var root := Node3D.new()
	var wall := Vector2i.ZERO
	if not wall_dirs.is_empty() and randf() < float(WALL_CHANCE.get(kind, 0.5)):
		wall = wall_dirs[randi() % wall_dirs.size()]
	if wall != Vector2i.ZERO:
		# 贴墙款：原点偏到墙根，-Z 朝走廊内侧
		root.position = Vector3(wall.x, 0, wall.y) * wall_face_dist
		root.rotation.y = atan2(float(wall.x), float(wall.y))
		match kind:
			Kind.ARCH:
				_wall_arch(root, randi() % 3)
			Kind.BEACON:
				_wall_lamp(root)
			_:
				_wall_fin(root)
	else:
		# 地面款：朝向行进方向，横向随机偏移不压正路
		if facing == Vector2i.ZERO:
			facing = Vector2i(0, -1)
		root.rotation.y = atan2(float(facing.x), float(facing.y))
		var side := Vector2(facing.y, facing.x) * randf_range(0.2, 0.8)
		if randf() < 0.5:
			side = -side
		root.position = Vector3(side.x, 0, side.y)
		match kind:
			Kind.ARCH:
				_floor_portal(root)
			Kind.BEACON:
				if randi() % 2 == 0:
					_floor_orb(root)
				else:
					_floor_bollard(root)
			_:
				_floor_monolith(root, randi() % 3)
	return root

# ── 门框（贴墙三态）──────────────────────────────────────────

static func _wall_arch(root: Node3D, variant: int) -> void:
	match variant:
		1:
			_wall_arch_ruined(root)
		2:
			_wall_arch_ajar(root)
		_:
			_wall_arch_full(root)

# ① 完好：端正的门框，门洞里一块比夜色更黑的面——装作门后有深渊
static func _wall_arch_full(root: Node3D) -> void:
	var frame := _plain_mat(Color(0.72, 0.70, 0.66))
	_box(root, Vector3(0.14, 2.3, 0.12), Vector3(-0.65, 1.15, -0.06), frame)
	_box(root, Vector3(0.14, 2.3, 0.12), Vector3(0.65, 1.15, -0.06), frame)
	_box(root, Vector3(1.44, 0.16, 0.12), Vector3(0, 2.3, -0.06), frame)
	_box(root, Vector3(1.16, 2.22, 0.06), Vector3(0, 1.11, 0.02), _void_mat())
	_box(root, Vector3(1.2, 0.04, 0.03), Vector3(0, 2.18, -0.11), _glow_mat(Color(0.95, 0.85, 0.5), 0.9))
	_guide_light(root, Color(1.0, 0.85, 0.55), Vector3(0, 1.6, -0.5), 0.45)

# ② 残破：门楣一端塌在断柱上，碎块散落脚边，断口残着一点光
static func _wall_arch_ruined(root: Node3D) -> void:
	var frame := _plain_mat(Color(0.62, 0.60, 0.56))
	_box(root, Vector3(0.14, 2.3, 0.12), Vector3(-0.65, 1.15, -0.06), frame)
	var stump := _box(root, Vector3(0.14, 1.4, 0.12), Vector3(0.65, 0.7, -0.06), frame)
	stump.rotation.z = deg_to_rad(3.0)
	var lintel := _box(root, Vector3(1.44, 0.16, 0.12), Vector3(-0.12, 1.62, -0.06), frame)
	lintel.rotation.z = deg_to_rad(-10.0)
	_box(root, Vector3(0.3, 0.18, 0.2), Vector3(0.35, 0.09, -0.45), frame, Vector3(0, deg_to_rad(30.0), 0))
	_box(root, Vector3(0.2, 0.12, 0.15), Vector3(0.85, 0.06, -0.6), frame, Vector3(0, deg_to_rad(-20.0), 0))
	_box(root, Vector3(0.14, 0.03, 0.12), Vector3(0.65, 1.42, -0.06), _glow_mat(Color(0.95, 0.85, 0.5), 0.6))
	_guide_light(root, Color(1.0, 0.85, 0.55), Vector3(0, 1.3, -0.5), 0.35)

# ③ 虚掩：门板开了一条缝，缝里漏出暖光——三态里最勾人的一个
static func _wall_arch_ajar(root: Node3D) -> void:
	var frame := _plain_mat(Color(0.72, 0.70, 0.66))
	_box(root, Vector3(0.14, 2.3, 0.12), Vector3(-0.65, 1.15, -0.06), frame)
	_box(root, Vector3(0.14, 2.3, 0.12), Vector3(0.65, 1.15, -0.06), frame)
	_box(root, Vector3(1.44, 0.16, 0.12), Vector3(0, 2.3, -0.06), frame)
	# 门板绕左门柱（铰链）向走廊内打开 30°
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.58, 0, -0.07)
	hinge.rotation.y = deg_to_rad(30.0)
	root.add_child(hinge)
	_box(hinge, Vector3(1.1, 2.1, 0.05), Vector3(0.55, 1.05, 0), _door_mat())
	_box(hinge, Vector3(0.04, 1.9, 0.06), Vector3(1.08, 1.05, 0.01), _glow_mat(Color(0.98, 0.8, 0.45), 1.3))
	# 门缝里透出的竖条幽光
	_box(root, Vector3(0.05, 2.0, 0.08), Vector3(0.47, 1.1, 0.0), _glow_mat(Color(0.95, 0.75, 0.4), 0.5))
	_guide_light(root, Color(1.0, 0.8, 0.5), Vector3(0.3, 1.2, -0.6), 0.55)

# ── 黑碑（地面三态 + 壁挂一态）─────────────────────────────

static func _floor_monolith(root: Node3D, variant: int) -> void:
	match variant:
		1:
			_mono_leaning(root)
		2:
			_mono_broken(root)
		_:
			_mono_intact(root)

# A 完好：黑色整碑 + 琥珀接缝（原设计）
static func _mono_intact(root: Node3D) -> void:
	_box(root, Vector3(0.5, 2.1, 0.28), Vector3(0, 1.05, 0), _dark_mat())
	_box(root, Vector3(0.06, 1.5, 0.30), Vector3(0, 1.0, 0), _glow_mat(Color(0.9, 0.55, 0.2), 1.1))
	_guide_light(root, Color(1.0, 0.6, 0.25), Vector3(0, 1.2, 0))

# B 倾斜：整碑歪 12°，像正在缓慢倾覆——比完好更"不对劲"
static func _mono_leaning(root: Node3D) -> void:
	var tilt := Vector3(0, 0, deg_to_rad(12.0))
	_box(root, Vector3(0.5, 2.1, 0.28), Vector3(0.12, 1.0, 0), _dark_mat(), tilt)
	_box(root, Vector3(0.06, 1.4, 0.30), Vector3(0.2, 0.95, 0), _glow_mat(Color(0.9, 0.55, 0.2), 0.85), tilt)
	_guide_light(root, Color(1.0, 0.6, 0.25), Vector3(0.35, 1.1, 0), 0.4)

# C 残断：只剩半截碑身，上半块摔在旁边，断口处微光将熄
static func _mono_broken(root: Node3D) -> void:
	_box(root, Vector3(0.5, 1.15, 0.28), Vector3(0, 0.575, 0), _dark_mat())
	_box(root, Vector3(0.5, 0.03, 0.28), Vector3(0, 1.16, 0), _glow_mat(Color(0.9, 0.55, 0.2), 0.7))
	_box(root, Vector3(0.5, 0.8, 0.28), Vector3(0.72, 0.14, 0.22), _dark_mat(),
		Vector3(deg_to_rad(88.0), deg_to_rad(18.0), 0))
	_guide_light(root, Color(1.0, 0.6, 0.25), Vector3(0, 0.9, 0), 0.4, 2.6)

# 壁挂：从墙里"长"出来的半块碑鳍——最不该出现在这里的一款
static func _wall_fin(root: Node3D) -> void:
	_box(root, Vector3(0.5, 1.7, 0.4), Vector3(0, 0.85, -0.2), _dark_mat())
	_box(root, Vector3(0.055, 1.2, 0.42), Vector3(0, 0.85, -0.21), _glow_mat(Color(0.9, 0.55, 0.2), 0.9))
	_guide_light(root, Color(1.0, 0.6, 0.25), Vector3(0, 1.1, -0.5), 0.45)

# ── 信标（地面两态 + 壁挂一态）─────────────────────────────

# A 立杆光球（原设计）：一盏不该亮着的应急灯
static func _floor_orb(root: Node3D) -> void:
	_box(root, Vector3(0.12, 0.7, 0.12), Vector3(0, 0.35, 0), _dark_mat())
	var orb := CSGSphere3D.new()
	orb.radius = 0.16
	orb.position = Vector3(0, 0.82, 0)
	orb.material = _glow_mat(Color(0.3, 0.8, 0.75), 1.4)
	orb.use_collision = false
	root.add_child(orb)
	_guide_light(root, Color(0.4, 0.85, 0.8), Vector3(0, 1.2, 0))

# B 矮柱桩灯：半米金属桩顶着冷光帽——像"有人标记过路线"
static func _floor_bollard(root: Node3D) -> void:
	_box(root, Vector3(0.18, 0.55, 0.18), Vector3(0, 0.275, 0), _metal_mat())
	_box(root, Vector3(0.26, 0.07, 0.26), Vector3(0, 0.585, 0), _glow_mat(Color(0.35, 0.8, 0.78), 1.2))
	_guide_light(root, Color(0.4, 0.85, 0.8), Vector3(0, 0.8, 0), 0.4, 2.6)

# 壁挂：埋墙应急灯，冷青色灯管——酒店走廊同款，但这层不该有人维护
static func _wall_lamp(root: Node3D) -> void:
	_box(root, Vector3(0.34, 0.2, 0.12), Vector3(0, 1.9, -0.06), _metal_mat())
	_box(root, Vector3(0.26, 0.06, 0.08), Vector3(0, 1.78, -0.09), _glow_mat(Color(0.3, 0.8, 0.75), 1.5))
	_guide_light(root, Color(0.4, 0.85, 0.8), Vector3(0, 1.9, -0.4), 0.45, 2.8)

# ── 独立门拱（无墙可贴时的门框回退款，原设计）─────────────
static func _floor_portal(root: Node3D) -> void:
	var frame := _plain_mat(Color(0.72, 0.70, 0.66))
	_box(root, Vector3(0.18, 2.6, 0.18), Vector3(-0.8, 1.3, 0), frame)
	_box(root, Vector3(0.18, 2.6, 0.18), Vector3(0.8, 1.3, 0), frame)
	_box(root, Vector3(1.78, 0.22, 0.18), Vector3(0, 2.5, 0), frame)
	_box(root, Vector3(1.4, 0.05, 0.02), Vector3(0, 2.35, -0.11), _glow_mat(Color(0.95, 0.85, 0.5), 0.9))
	_guide_light(root, Color(1.0, 0.85, 0.55), Vector3(0, 1.4, 0))

# ── 通用件 ──────────────────────────────────────────────────

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.rotation = rot
	b.material = mat
	b.use_collision = false
	parent.add_child(b)
	return b

static func _guide_light(parent: Node3D, color: Color, pos: Vector3,
		energy := 0.5, radius := 3.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 2.2
	light.shadow_enabled = false
	light.position = pos
	parent.add_child(light)
	return light

static func _dark_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.08, 0.09)
	m.roughness = 0.6
	return m

static func _metal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.16, 0.17)
	m.roughness = 0.45
	m.metallic = 0.6
	return m

static func _door_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.17, 0.12)
	m.roughness = 0.8
	return m

# "门后深渊"面板：比夜色更黑的无反光面
static func _void_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.01, 0.01, 0.012)
	m.roughness = 1.0
	return m

static func _plain_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

static func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.4
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.5
	return m
