class_name LandmarkBreadcrumb
extends Node3D
# 弱引导「地标」：沿通往出口的路径，间隔放置几种与环境反差的小结构，
# 靠颜色/形状的自然吸引力把玩家目光往前带——而不是直白的箭头。
# 刻意做得很弱：数量少、间隔大、发光柔和、且不完全压在正路上，
# 认真找路的人几乎注意不到它们是「指引」，只有迷路时余光会被它们牵引。

enum Kind { MONOLITH, ARCH, BEACON }

static func create(kind: int, facing: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = atan2(float(facing.x), float(facing.y))
	match kind:
		Kind.MONOLITH:
			_make_monolith(root)
		Kind.ARCH:
			_make_arch(root)
		_:
			_make_beacon(root)
	return root

# A 孤独黑色碑体 + 微弱琥珀色接缝：后室式的「不该出现在这里的东西」
static func _make_monolith(root: Node3D) -> void:
	var body := CSGBox3D.new()
	body.size = Vector3(0.5, 2.1, 0.28)
	body.position = Vector3(0, 1.05, 0)
	body.material = _dark_mat()
	body.use_collision = false
	root.add_child(body)

	var seam := CSGBox3D.new()
	seam.size = Vector3(0.06, 1.5, 0.30)
	seam.position = Vector3(0, 1.0, 0)
	seam.material = _glow_mat(Color(0.9, 0.55, 0.2), 1.1)
	seam.use_collision = false
	root.add_child(seam)

	root.add_child(_guide_light(Color(1.0, 0.6, 0.25)))

# B 独立门框：暗示「有条路」的结构，比箭头含蓄得多
static func _make_arch(root: Node3D) -> void:
	var frame := Color(0.72, 0.70, 0.66)
	for side in [-1, 1]:
		var post := CSGBox3D.new()
		post.size = Vector3(0.18, 2.6, 0.18)
		post.position = Vector3(side * 0.8, 1.3, 0)
		post.material = _plain_mat(frame)
		post.use_collision = false
		root.add_child(post)
	var lintel := CSGBox3D.new()
	lintel.size = Vector3(1.78, 0.22, 0.18)
	lintel.position = Vector3(0, 2.5, 0)
	lintel.material = _plain_mat(frame)
	lintel.use_collision = false
	root.add_child(lintel)

	var glow_strip := CSGBox3D.new()
	glow_strip.size = Vector3(1.4, 0.05, 0.02)
	glow_strip.position = Vector3(0, 2.35, -0.11)
	glow_strip.material = _glow_mat(Color(0.95, 0.85, 0.5), 0.9)
	glow_strip.use_collision = false
	root.add_child(glow_strip)

	root.add_child(_guide_light(Color(1.0, 0.85, 0.55)))

# C 低矮冷光信标：一盏不该亮着的应急灯，勾着人往前探
static func _make_beacon(root: Node3D) -> void:
	var post := CSGBox3D.new()
	post.size = Vector3(0.12, 0.7, 0.12)
	post.position = Vector3(0, 0.35, 0)
	post.material = _dark_mat()
	post.use_collision = false
	root.add_child(post)

	var orb := CSGSphere3D.new()
	orb.radius = 0.16
	orb.position = Vector3(0, 0.82, 0)
	orb.material = _glow_mat(Color(0.3, 0.8, 0.75), 1.4)
	orb.use_collision = false
	root.add_child(orb)

	root.add_child(_guide_light(Color(0.4, 0.85, 0.8)))

# 极弱的点光：只照亮脚下小范围，保证在暗处也可见，但不足以「照亮通路」
static func _guide_light(color: Color) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.5
	light.omni_range = 3.0
	light.omni_attenuation = 2.2
	light.shadow_enabled = false
	light.position = Vector3(0, 1.2, 0)
	return light

static func _dark_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.08, 0.09)
	m.roughness = 0.6
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
