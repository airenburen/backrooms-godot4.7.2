extends "res://levels/level_base.gd"
# Level !「红色狂奔」重做（见 docs/level_run_design.md，方案 A 纯氛围追逐）。
# 一条 165m 的酒店长廊：暗红应急灯、湿黑镜面地面（红灯拉成长条反光）、
# 翻倒的文件柜/长桌路障、两侧永远打不开的客房门、墙裙腰线；
# 尽头一扇门 + 绿光 EXIT 牌。身后——灯一盏盏熄灭，低吼渐强，暗角红脉冲。
# 没有实体，没有寻路，只有"看不见的追逐"。

const RUN_WIDTH := 4    # 网格宽（含两侧墙格）：中间 2 格 = 7m 逃命通道
const RUN_LENGTH := 49  # 网格长（含两端墙格）：47 格 ≈ 165m
const CHASE_GAP := 7.0  # 落后玩家多少米熄灯（黑暗追着脚步蔓延）

# 湿黑镜面地面：近黑基色 + 近乎全湿（均匀的湿，不是 L1 的斑驳水洼），
# 粗糙度 0.03 镜面高光拉满——红灯在地面拉出连续长条反光
const RUN_WET_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float meters_per_tile = 2.0;
uniform float ripple_strength = 0.05;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / meters_per_tile;
	vec3 base = texture(albedo_tex, uv).rgb * vec3(0.22, 0.10, 0.09);  // 压到近黑红

	// 水洼掩码：阈值压低 → 整片地面近乎全湿
	float n = sin(uv.x * 1.7 + TIME * 0.05) * cos(uv.y * 1.3 - TIME * 0.04)
		+ 0.6 * sin(uv.x * 0.6 - uv.y * 0.9 + TIME * 0.03);
	float puddle = smoothstep(0.05, 0.35, n);

	float rx = cos(uv.x * 6.0 + TIME * 1.1) * cos(uv.y * 5.0 - TIME * 0.7);
	float rz = sin(uv.x * 5.0 - TIME * 0.9) * sin(uv.y * 6.0 + TIME * 1.3);
	vec3 n_world = normalize(vec3(rx * ripple_strength * puddle, 1.0, rz * ripple_strength * puddle));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	ALBEDO = base * mix(1.0, 0.45, puddle);
	ROUGHNESS = mix(0.25, 0.03, puddle);
	SPECULAR = mix(0.5, 0.9, puddle);
}
"""

var _chase_lights: Array[OmniLight3D] = []
var _growl: AudioStreamPlayer
var _start_z := 0.0
var _end_z := 10.0

func _init() -> void:
	cell_size = 3.5
	wall_height = 3.2
	guide_step = 7  # 直线上地标当"里程标"用，间隔放大保持速度感
	flicker_chance = 0.0  # 布灯走 _place_lights 覆盖，此值不用
	volumetric_fog_density = 0.028  # 血色薄雾，增强灯光体积感
	dust_count = 300
	dust_extents = Vector3(3, 1.4, 3)
	hum_volume_db = -13.0
	hum_pitch = 0.9
	level_title = "Level !"
	hint_text = "RUN. IT'S BEHIND YOU."

func _ready() -> void:
	super._ready()
	# 追逐低吼：音量随"玩家已跑距离"线性增大，靠近出口音高上扬（它追上来了）
	_growl = AudioStreamPlayer.new()
	_growl.name = "Growl"
	_growl.stream = SoundGen.create_entity_growl()
	_growl.volume_db = -38.0
	_growl.autoplay = true
	add_child(_growl)
	_start_z = _cell_to_world(spawn_cell).z
	_end_z = _cell_to_world(exit_cell).z

func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		return
	var pz := player.global_position.z
	# 灯光熄灭逼近：玩家身后的灯一盏盏灭掉，黑暗追着脚步蔓延
	for l in _chase_lights:
		if is_instance_valid(l) and l.visible and l.global_position.z < pz - CHASE_GAP:
			l.visible = false
	# 追逐进度：低吼渐强渐尖 + 屏幕边缘红脉冲（心跳感）
	var progress := clampf((pz - _start_z) / maxf(_end_z - _start_z, 1.0), 0.0, 1.0)
	if _growl:
		_growl.volume_db = lerpf(-38.0, -7.0, progress)
		_growl.pitch_scale = lerpf(0.9, 1.18, progress)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_chase_pulse"):
		hud.set_chase_pulse(progress)

# 不用迷宫：手填一条直线走廊（中间 2×47 全 FLOOR，四周 WALL）
func _generate_maze(m) -> void:
	m.width = RUN_WIDTH
	m.height = RUN_LENGTH
	m.grid = PackedByteArray()
	m.grid.resize(RUN_WIDTH * RUN_LENGTH)
	m.grid.fill(MazeGenerator.Cell.WALL)
	for y in range(1, RUN_LENGTH - 1):
		for x in range(1, RUN_WIDTH - 1):
			m.grid[y * RUN_WIDTH + x] = MazeGenerator.Cell.FLOOR
	m.pillar_cells.clear()
	m.room_cells.clear()

func _position_player() -> void:
	spawn_cell = maze.find_nearest_floor(Vector2i(1, 1))
	var spawn_pos := _cell_to_world(spawn_cell)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = spawn_pos + Vector3(0, 1.0, 0)
		player.rotation.y = PI  # 面向 +Z：走廊的纵深方向

func _create_materials() -> void:
	_wall_mat = MatLib.run_wall_mat()
	_floor_mat = MatLib.run_floor_mat()  # 占位；地面实际用湿黑 shader
	_ceiling_mat = MatLib.run_ceiling_mat()
	_pillar_mat = MatLib.run_wall_mat()
	_light_panel_mat = _make_light_panel_mat(Color(1.0, 0.3, 0.25), Color(1.0, 0.1, 0.05))
	_exit_portal_mat = _make_exit_mat()

# —— 湿黑镜面地面 ——
func _build_floor() -> void:
	var total_w: float = maze.width * cell_size
	var total_d: float = maze.height * cell_size
	var floor_node := CSGBox3D.new()
	floor_node.name = "Floor"
	floor_node.use_collision = true
	floor_node.size = Vector3(total_w, 0.2, total_d)
	floor_node.position = Vector3(total_w * 0.5, -0.1, total_d * 0.5)
	floor_node.material_override = _wet_floor_material()
	add_child(floor_node)

func _wet_floor_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = RUN_WET_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var dir := "res://assets/textures/Concrete033/"
	var albedo: Texture2D = null
	if ResourceLoader.exists(dir + "Concrete033_1K-JPG_Color.jpg"):
		albedo = load(dir + "Concrete033_1K-JPG_Color.jpg")
	else:
		var fn := FastNoiseLite.new()
		fn.seed = 5
		fn.frequency = 0.02
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
		var nt := NoiseTexture2D.new()
		nt.noise = fn
		nt.width = 512
		nt.height = 512
		albedo = nt
	m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("meters_per_tile", 2.0)
	return m

# —— 墙面：墙裙腰线 + 客房假门（打不开，纯压迫）——

func _emit_wall(container: Node3D, mat: StandardMaterial3D, horizontal: bool, line: int, sgn: int, a: int, b: int) -> CSGBox3D:
	var wall := super(container, mat, horizontal, line, sgn, a, b)
	if horizontal:
		return wall  # 两端横墙不装修
	var span := float(b - a + 1) * cell_size
	var surf := float(line) * cell_size
	var cz := (float(a) + float(b - a + 1) * 0.5) * cell_size
	# 墙裙：墙根到 1.1m 深色带（比主墙暗 40%）+ 3cm 腰线——酒店走廊的分层感
	var skirt := CSGBox3D.new()
	skirt.size = Vector3(0.02, 1.1, span - 0.04)
	skirt.position = Vector3(surf + sgn * 0.006, 0.55, cz)
	skirt.material = _skirt_mat()
	skirt.use_collision = false
	container.add_child(skirt)
	var belt := CSGBox3D.new()
	belt.size = Vector3(0.035, 0.035, span - 0.04)
	belt.position = Vector3(surf + sgn * 0.012, 1.1, cz)
	belt.material = _wood_mat()
	belt.use_collision = false
	container.add_child(belt)
	# 客房门：每 2 格一扇（假门，无碰撞不可进入）
	for c in range(a, b + 1, 2):
		if randf() < 0.78:
			_guest_door(container, surf, sgn, (float(c) + 0.5) * cell_size)
	return wall

func _guest_door(container: Node3D, surf: float, sgn: int, z: float) -> void:
	var x := surf + sgn * 0.045
	# 门板：暗红木纹（带把手）
	var door := CSGBox3D.new()
	door.size = Vector3(0.06, 2.1, 1.0)
	door.position = Vector3(x, 1.05, z)
	door.material = _door_mat()
	door.use_collision = false
	container.add_child(door)
	var knob := CSGSphere3D.new()
	knob.radius = 0.045
	knob.position = Vector3(x + sgn * 0.055, 1.05, z + 0.38)
	knob.material = _skirt_mat()
	knob.use_collision = false
	container.add_child(knob)
	# 门框：深色金属，出墙 6cm
	for dz in [-0.56, 0.56]:
		var jamb := CSGBox3D.new()
		jamb.size = Vector3(0.09, 2.26, 0.1)
		jamb.position = Vector3(x, 1.13, z + dz)
		jamb.material = _skirt_mat()
		jamb.use_collision = false
		container.add_child(jamb)
	var lintel := CSGBox3D.new()
	lintel.size = Vector3(0.09, 0.1, 1.22)
	lintel.position = Vector3(x, 2.31, z)
	lintel.material = _skirt_mat()
	lintel.use_collision = false
	container.add_child(lintel)
	# 门牌：房间号
	var plate := Label3D.new()
	plate.text = "%d" % (110 + randi() % 480)
	plate.font_size = 48
	plate.pixel_size = 0.004
	plate.modulate = Color(0.85, 0.6, 0.3)
	plate.outline_size = 8
	plate.position = Vector3(x + sgn * 0.06, 2.5, z)
	plate.rotation.y = PI * 0.5 * sgn
	container.add_child(plate)

# —— 灯：两侧壁挂应急灯 + 天花板红灯板（全部纳入熄灭序列）——

func _place_lights() -> void:
	var container := Node3D.new()
	container.name = "Lights"
	add_child(container)
	var red := Color(1.0, 0.15, 0.1)
	# 走廊内壁：左墙面在格线 1、右墙面在格线 RUN_WIDTH-1（薄墙生成规则）
	var wall_left := cell_size * 1.0
	var wall_right := cell_size * (RUN_WIDTH - 1)
	for zi in range(2, maze.height - 1, 3):
		for side_x in [wall_left + 0.35, wall_right - 0.35]:
			var light: OmniLight3D
			if randf() < 0.2:
				light = FlickeringLight.new()
			else:
				light = OmniLight3D.new()
			light.light_color = red
			light.light_energy = 1.3
			light.omni_range = 7.0
			light.omni_attenuation = 1.2
			light.shadow_enabled = false  # 灯多（30+），关阴影保帧率
			light.position = Vector3(side_x, wall_height - 0.6, (zi + 0.5) * cell_size)
			Atmosphere.set_fog_energy(light, 0.9)
			container.add_child(light)
			_chase_lights.append(light)

			var panel := CSGBox3D.new()
			panel.size = Vector3(0.5, 0.28, 0.1)
			panel.position = Vector3(0, -0.18, 0)
			panel.material = _light_panel_mat
			panel.use_collision = false
			light.add_child(panel)
	# 天花板红灯板：每隔几格一块，与壁灯错开（也参与熄灭）
	for zi in range(4, maze.height - 2, 5):
		var cl := OmniLight3D.new()
		cl.light_color = red
		cl.light_energy = 1.1
		cl.omni_range = 6.5
		cl.omni_attenuation = 1.2
		cl.shadow_enabled = false
		cl.position = Vector3(cell_size * 2.0, wall_height - 0.4, (zi + 0.5) * cell_size)
		Atmosphere.set_fog_energy(cl, 0.9)
		container.add_child(cl)
		_chase_lights.append(cl)
		var cpanel := CSGBox3D.new()
		cpanel.size = Vector3(1.8, 0.06, 0.5)
		cpanel.position = Vector3(cell_size * 2.0, wall_height - 0.04, (zi + 0.5) * cell_size)
		cpanel.material = _light_panel_mat
		cpanel.use_collision = false
		container.add_child(cpanel)

# —— 出口：尽头门 + 绿光 EXIT（闸门逻辑沿用基类）——

func _place_exit() -> void:
	super()
	# 把基类的绿光传送门改造成"尽头那扇门"：暗红门板 + 中缝 + 门楣
	for child in exit_area.get_children():
		if child is CSGBox3D and child.name == "":
			var portal := child as CSGBox3D
			portal.material = _door_mat()
			portal.size = Vector3(cell_size * 0.62, wall_height * 0.72, 0.14)
			portal.position = Vector3(0, -wall_height * 0.09, 0.1)
			var seam := CSGBox3D.new()
			seam.size = Vector3(0.03, wall_height * 0.72, 0.16)
			seam.position = portal.position
			seam.material = _skirt_mat()
			seam.use_collision = false
			exit_area.add_child(seam)
			break

# —— 路障：翻倒的文件柜/长桌 + 散落纸张（无碰撞，纯视觉擦身）——

func _custom_build() -> void:
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	add_child(furniture)
	var wall_left := cell_size * 1.0
	var wall_right := cell_size * (RUN_WIDTH - 1)
	var zi := 6
	while zi < maze.height - 5:  # 避开出口前 3 格，别挡终点观感
		if randf() < 0.85:
			var side: float = 1.0 if randf() < 0.5 else -1.0
			var near_wall: float = wall_left + 1.25 if side > 0 else wall_right - 1.25
			if randf() < 0.55:
				_fallen_cabinet(furniture, near_wall, side, (zi + 0.5) * cell_size)
			else:
				_fallen_table(furniture, near_wall, side, (zi + 0.5) * cell_size)
			# 散落纸张
			for _p in randi_range(3, 6):
				var paper := CSGBox3D.new()
				paper.size = Vector3(0.2, 0.005, 0.28)
				paper.position = Vector3(
					near_wall - side * randf_range(0.3, 2.2),
					0.005,
					(zi + 0.5) * cell_size + randf_range(-1.5, 1.5))
				paper.rotation.y = randf_range(0, PI)
				paper.material = _paper_mat()
				paper.use_collision = false
				furniture.add_child(paper)
		zi += randi_range(6, 9)

# 文件柜：柜体侧倒 80°斜插向墙 + 两层抽屉面板（略拉开）
func _fallen_cabinet(container: Node3D, x: float, side: float, z: float) -> void:
	var g := Node3D.new()
	g.position = Vector3(x, 0.0, z)
	g.rotation.y = PI * 0.5
	container.add_child(g)
	var body := CSGBox3D.new()
	body.size = Vector3(0.48, 1.35, 0.62)
	body.position = Vector3(0, 0.62, side * 0.5)
	body.rotation.x = side * 1.4  # 侧倒 80°，斜插向墙
	body.material = _cabinet_mat()
	body.use_collision = false
	g.add_child(body)
	for i in 2:
		var drawer := CSGBox3D.new()
		drawer.size = Vector3(0.4, 0.5, 0.06)
		drawer.position = Vector3(0, 0.62, side * (0.5 + 0.28 + i * 0.02))
		drawer.position += Vector3(0, i * 0.05, side * i * 0.12).rotated(Vector3(1, 0, 0), side * 1.4)
		drawer.rotation.x = side * 1.4
		drawer.material = _skirt_mat()
		drawer.use_collision = false
		g.add_child(drawer)

# 长条桌：桌面 + 四腿，翻倒横陈，靠墙一侧抬起
func _fallen_table(container: Node3D, x: float, side: float, z: float) -> void:
	var g := Node3D.new()
	g.position = Vector3(x, 0.0, z)
	g.rotation.y = randf_range(-0.3, 0.3)
	container.add_child(g)
	var top := CSGBox3D.new()
	top.size = Vector3(1.6, 0.06, 0.8)
	top.position = Vector3(0, 0.42, side * 0.7)
	top.rotation.x = side * 0.5  # 靠墙一侧抬起
	top.material = _wood_mat()
	top.use_collision = false
	g.add_child(top)
	for dz in [-0.6, 0.6]:
		var leg := CSGBox3D.new()
		leg.size = Vector3(0.06, 0.75, 0.06)
		leg.position = Vector3(0, 0.35, side * 0.7 + dz)
		leg.rotation.x = side * 0.5
		leg.material = _skirt_mat()
		leg.use_collision = false
		g.add_child(leg)

# —— 材质 ——

func _skirt_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.07, 0.06)
	m.roughness = 0.7
	m.metallic = 0.3
	return m

func _wood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.14, 0.10)
	m.roughness = 0.8
	return m

func _door_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.26, 0.11, 0.09)
	m.roughness = 0.75
	return m

func _cabinet_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.10, 0.09)
	m.roughness = 0.55
	m.metallic = 0.4
	return m

static func _paper_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.80, 0.74)
	m.roughness = 0.9
	return m
