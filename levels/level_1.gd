extends "res://levels/level_base.gd"
# Level 1：无尽混凝土大仓库（见 docs/level1_design.md）。
# 开阔大平层 + 规则柱网 + 带缺口隔断墙；满地水洼（自写湿混凝土 shader，
# 水洼区低粗糙度拉灯光高光）；荧光灯管吊架常亮/闪烁/熄灭三态；薄雾弥漫。

const WarehouseGenerator = preload("res://levels/warehouse_generator.gd")

# 湿混凝土地面：世界 XZ 平面投影采样 + 程序水洼（漂移呼吸、湿深、涟漪法线）
const WET_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear;
uniform float meters_per_tile = 2.0;
uniform float ripple_strength = 0.06;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / meters_per_tile;
	vec3 base = texture(albedo_tex, uv).rgb;

	// 水洼掩码：双频噪声 + 缓慢漂移，smoothstep 出斑块边缘
	float n = sin(uv.x * 1.7 + TIME * 0.05) * cos(uv.y * 1.3 - TIME * 0.04)
		+ 0.6 * sin(uv.x * 0.6 - uv.y * 0.9 + TIME * 0.03);
	float puddle = smoothstep(0.35, 0.75, n);

	// 涟漪法线（仅水洼区）
	float rx = cos(uv.x * 6.0 + TIME * 1.1) * cos(uv.y * 5.0 - TIME * 0.7);
	float rz = sin(uv.x * 5.0 - TIME * 0.9) * sin(uv.y * 6.0 + TIME * 1.3);
	vec3 nmap = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 n_world = normalize(vec3(
		nmap.x + rx * ripple_strength * puddle,
		1.0,
		nmap.z + rz * ripple_strength * puddle
	));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	ALBEDO = base * mix(1.0, 0.5, puddle);
	ROUGHNESS = mix(0.9, 0.04, puddle);
	SPECULAR = mix(0.4, 0.7, puddle);
}
"""

var _dead_tube_mat: StandardMaterial3D
# 家具占用（世界坐标）：货架条带矩形 + 托盘点位，供事后清理重叠地标
var _rack_rects: Array[Dictionary] = []
var _pallet_spots: Array[Vector3] = []

func _init() -> void:
	cell_size = 4.0
	wall_height = 5.0
	maze_size = 14  # 29×29 格 ≈ 116m 见方
	light_color = Color(0.9, 0.95, 1.0)
	light_energy_range = Vector2(1.4, 1.8)
	light_range = 13.0
	flicker_chance = 0.35
	fill_light_color = Color(0.42, 0.45, 0.5)
	fill_light_energy = 0.2
	volumetric_fog_density = 0.05
	dust_count = 900
	dust_extents = Vector3(16, 2.4, 16)
	hum_volume_db = -15.0
	hum_pitch = 0.85
	level_title = "Level 1"
	hint_text = "仓库没有尽头"

func _generate_maze(m) -> void:
	var w := WarehouseGenerator.new()
	w.generate(maze_size, randi())
	maze = w

func _create_materials() -> void:
	_wall_mat = MatLib.l1_wall_mat()
	_floor_mat = MatLib.l1_floor_mat()  # 占位；地面实际用湿混凝土 shader
	_ceiling_mat = MatLib.l1_ceiling_mat()
	_pillar_mat = MatLib.l1_pillar_mat()
	_light_panel_mat = _make_light_panel_mat(Color(1, 1, 1), Color(0.9, 0.95, 1.0))
	_exit_portal_mat = _make_exit_mat()
	_dead_tube_mat = StandardMaterial3D.new()
	_dead_tube_mat.albedo_color = Color(0.35, 0.35, 0.33)
	_dead_tube_mat.roughness = 0.6

# —— 湿混凝土 shader 地面（覆盖基类平面地板）——

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
	sh.code = WET_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var dir := "res://assets/textures/Concrete033/"
	var albedo: Texture2D = null
	var normal: Texture2D = null
	if ResourceLoader.exists(dir + "Concrete033_1K-JPG_Color.jpg"):
		albedo = load(dir + "Concrete033_1K-JPG_Color.jpg")
		if ResourceLoader.exists(dir + "Concrete033_1K-JPG_NormalGL.jpg"):
			normal = load(dir + "Concrete033_1K-JPG_NormalGL.jpg")
	if albedo == null:
		# 无素材回退：程序噪声贴图，水洼效果照常
		var fn := FastNoiseLite.new()
		fn.seed = 7
		fn.frequency = 0.02
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
		var nt := NoiseTexture2D.new()
		nt.noise = fn
		nt.width = 512
		nt.height = 512
		nt.as_normal_map = false
		albedo = nt
		var fn2 := FastNoiseLite.new()
		fn2.seed = 13
		fn2.frequency = 0.03
		fn2.noise_type = FastNoiseLite.TYPE_SIMPLEX
		var nn := NoiseTexture2D.new()
		nn.noise = fn2
		nn.width = 512
		nn.height = 512
		nn.as_normal_map = true
		normal = nn
	if normal == null:
		# 有彩色图但缺法线图：平坦法线（0.5,0.5,1），别拿彩色图当法线喂出垃圾凹凸
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 1.0))
		normal = ImageTexture.create_from_image(img)
	m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("normal_tex", normal)
	m.set_shader_parameter("meters_per_tile", 2.0)  # 一铺 2m 见方，与 MatLib 0.5 tiles/m 惯例一致
	return m

# —— 荧光灯管吊架：常亮 40% / 闪烁 35% / 熄灭 25% ——

func _place_lights() -> void:
	var container := Node3D.new()
	container.name = "Lights"
	add_child(container)

	var floor_cells: Array[Vector2i] = maze.get_all_floor_cells()
	var covered := {}
	var range_in_cells: float = light_range * 0.8 / cell_size
	var positions: Array[Vector2i] = []
	for cell in floor_cells:
		if covered.has(cell):
			continue
		positions.append(cell)
		for other in floor_cells:
			if covered.has(other):
				continue
			if Vector2(other.x - cell.x, other.y - cell.y).length() <= range_in_cells:
				covered[other] = true

	var y := wall_height - 1.4
	for cell in positions:
		var p := _cell_to_world(cell)
		var roll := randf()
		var along_x := (cell.x + cell.y) % 2 == 0
		if roll < 0.25:
			_tube_fixture(container, p + Vector3(0, y, 0), along_x, false, false)
		elif roll < 0.6:
			var light := FlickeringLight.new()
			light.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
			_setup_tube_light(light, p + Vector3(0, y - 0.05, 0))
			container.add_child(light)
			light.sync_material = _tube_fixture(container, p + Vector3(0, y, 0), along_x, true, true)
		else:
			var light2 := OmniLight3D.new()
			_setup_tube_light(light2, p + Vector3(0, y - 0.05, 0))
			light2.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
			container.add_child(light2)
			_tube_fixture(container, p + Vector3(0, y, 0), along_x, true, false)

func _setup_tube_light(light: OmniLight3D, at: Vector3) -> void:
	light.light_color = light_color
	light.omni_range = light_range
	light.omni_attenuation = 1.5
	light.shadow_enabled = false  # 几十盏灯全阴影吃不消，靠雾和高光撑氛围
	light.position = at
	Atmosphere.set_fog_energy(light, 0.8)

# 灯管 + 吊架：发光管（或死管）+ 深色金属支架 + 两根吊线；返回灯管材质供闪烁同步
func _tube_fixture(container: Node3D, at: Vector3, along_x: bool, on: bool, flicker: bool) -> StandardMaterial3D:
	var tube := CSGCylinder3D.new()
	tube.radius = 0.05
	tube.height = 2.4
	tube.sides = 8
	if on:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 1)
		mat.emission_enabled = true
		mat.emission = Color(0.92, 0.97, 1.0)
		mat.emission_energy_multiplier = 3.0 if not flicker else 2.2
		tube.material = mat
	else:
		tube.material = _dead_tube_mat
	if along_x:
		tube.rotation.z = PI * 0.5
	else:
		tube.rotation.x = PI * 0.5  # 圆柱默认竖直 Y 轴：沿 Z 也要横放
	tube.position = at
	tube.use_collision = false
	container.add_child(tube)

	var bracket := CSGBox3D.new()
	bracket.size = Vector3(2.6, 0.08, 0.16) if along_x else Vector3(0.16, 0.08, 2.6)
	bracket.position = at + Vector3(0, 0.1, 0)
	bracket.material = _dead_tube_mat
	bracket.use_collision = false
	container.add_child(bracket)

	for off in [-0.9, 0.9]:
		var cord := CSGCylinder3D.new()
		var cord_len: float = wall_height - at.y - 0.1
		cord.radius = 0.015
		cord.height = cord_len
		cord.sides = 5
		cord.material = _dead_tube_mat
		cord.position = at + Vector3(off if along_x else 0, cord_len * 0.5 + 0.1, 0 if along_x else off)
		cord.use_collision = false
		container.add_child(cord)
	return tube.material as StandardMaterial3D

# —— 装修：贴隔断墙的货架巷道 + 开阔地散托盘 ——

func _custom_build() -> void:
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	add_child(furniture)
	var aisle := 0
	for part in (maze as WarehouseGenerator).partitions:
		if part.b - part.a < 4 or randf() < 0.35:
			continue
		aisle += 1
		var seg_len := float(part.b - part.a + 1) * cell_size - 1.0
		var center := (float(part.a) + float(part.b + 1)) * 0.5 * cell_size
		var face := float(part.line) * cell_size
		var side := 1.0 if randf() < 0.5 else -1.0
		var off := side * (WALL_THICK * 0.5 + 0.62)
		if part.horizontal:
			var pz := face + off
			_build_rack(furniture, center, pz, true, seg_len, aisle, int(side))
			_rack_rects.append({
				"x0": center - seg_len * 0.5 - 0.7, "x1": center + seg_len * 0.5 + 0.7,
				"z0": pz - 1.3, "z1": pz + 1.3,
			})
		else:
			var px := face + off
			_build_rack(furniture, px, center, false, seg_len, aisle, int(side))
			_rack_rects.append({
				"x0": px - 1.3, "x1": px + 1.3,
				"z0": center - seg_len * 0.5 - 0.7, "z1": center + seg_len * 0.5 + 0.7,
			})
	# 散托盘堆：随机地板格（避开柱格）
	var floors: Array[Vector2i] = maze.get_all_floor_cells()
	for _i in 8:
		var cell: Vector2i = floors[randi() % floors.size()]
		if maze.pillar_cells.has(maze._index(cell.x, cell.y)):
			continue
		if randf() < 0.5:
			continue
		var at := _cell_to_world(cell)
		_pallet_spots.append(at)
		_build_pallet(furniture, at)
	# 地标先于家具放置（基类装配顺序），事后清掉撞进货架/托盘的地标
	var marks := get_node_or_null("Landmarks")
	if marks:
		for mk in marks.get_children():
			var hit := false
			for r in _rack_rects:
				if mk.position.x >= r.x0 and mk.position.x <= r.x1 \
						and mk.position.z >= r.z0 and mk.position.z <= r.z1:
					hit = true
					break
			if not hit:
				for s in _pallet_spots:
					if Vector2(mk.position.x - s.x, mk.position.z - s.z).length() < 1.4:
						hit = true
						break
			if hit:
				mk.queue_free()

# 一排贴墙货架（沿 X 或 Z），构件同旧版：橙钢柱 + 4 层板 + 货箱 + 巷道号牌
# wall_side：货架在墙的哪一侧（±1），号牌据此定向
func _build_rack(container: Node3D, px: float, pz: float, along_x: bool,
		length: float, aisle: int, wall_side: int) -> void:
	var orange := _rack_mat()
	var wood := _shelf_mat()
	var levels: Array[float] = [0.18, 0.95, 1.70, 2.45]

	var n := int(length / 3.5) + 1
	for i in n:
		var t := 0.0 if n == 1 else -length * 0.5 + length * i / float(n - 1)
		for side in [-0.5, 0.5]:
			var post := CSGBox3D.new()
			post.size = Vector3(0.12, 3.5, 0.12)
			post.position = Vector3(px + t, 1.75, pz + side) if along_x else Vector3(px + side, 1.75, pz + t)
			post.material = orange
			post.use_collision = true
			container.add_child(post)

	for lvl in levels:
		var board := CSGBox3D.new()
		board.size = Vector3(length, 0.08, 1.1) if along_x else Vector3(1.1, 0.08, length)
		board.position = Vector3(px, lvl, pz)
		board.material = wood
		board.use_collision = true
		container.add_child(board)
		if lvl > 2.0 and randf() < 0.4:
			continue
		var a := -length * 0.5 + 0.6
		while a < length * 0.5 - 0.6:
			if randf() < 0.45:
				var s := randf_range(0.45, 0.8)
				var crate := CSGBox3D.new()
				crate.size = Vector3(s, s * 0.8, s)
				crate.position = Vector3(px + a, lvl + 0.04 + s * 0.4, pz) if along_x \
						else Vector3(px, lvl + 0.04 + s * 0.4, pz + a)
				crate.rotation.y = randf_range(-0.15, 0.15)
				crate.material = _crate_mat()
				crate.use_collision = false
				container.add_child(crate)
				a += s + 0.35
			else:
				a += randf_range(0.7, 1.3)

	# 巷道号牌：高位钉在巷道尽头的隔断墙上（货架 3.5m 之上、顶棚 5.0m 之下），
	# 平面贴墙正对巷道方向——走近巷道口抬头可见，不再 billboard 贴身朝玩家。
	# 几何：墙面（朝货架侧）在货架中心线 -wall_side*0.48 处，号牌离墙 3cm；
	# Label3D 可读面朝 +Z，旋转使其指向巷道（+wall_side 方向）
	var sign := Label3D.new()
	sign.text = "A-%02d" % aisle
	sign.font_size = 64
	sign.pixel_size = 0.008
	sign.modulate = Color(1.0, 0.55, 0.15)
	sign.outline_size = 12
	if along_x:
		sign.position = Vector3(px - length * 0.5 - 0.15, 4.2, pz - wall_side * 0.45)
		sign.rotation.y = 0.0 if wall_side > 0 else PI
	else:
		sign.position = Vector3(px - wall_side * 0.45, 4.2, pz - length * 0.5 - 0.15)
		sign.rotation.y = wall_side * PI * 0.5
	container.add_child(sign)

# 散托盘 + 货箱堆
func _build_pallet(container: Node3D, at: Vector3) -> void:
	var stack := Node3D.new()
	stack.position = at
	stack.rotation.y = randf_range(0, PI)
	container.add_child(stack)

	var pallet := CSGBox3D.new()
	pallet.size = Vector3(1.35, 0.14, 1.15)
	pallet.position = Vector3(0, 0.07, 0)
	pallet.material = _pallet_mat()
	pallet.use_collision = true
	stack.add_child(pallet)

	var y := 0.14
	for _c in randi_range(1, 2):
		var s := randf_range(0.7, 1.0)
		var crate := CSGBox3D.new()
		crate.size = Vector3(s, s * 0.75, s)
		crate.position = Vector3(randf_range(-0.1, 0.1), y + s * 0.375, randf_range(-0.1, 0.1))
		crate.rotation.y = randf_range(-0.2, 0.2)
		crate.material = _crate_mat()
		crate.use_collision = true
		stack.add_child(crate)
		y += s * 0.75

# —— 材质 ——

func _rack_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.30, 0.06)
	m.roughness = 0.5
	m.metallic = 0.3
	return m

func _shelf_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.50, 0.34)
	m.roughness = 0.85
	return m

func _pallet_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.35, 0.22)
	m.roughness = 0.9
	return m

func _crate_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.42, 0.28) if randf() < 0.6 else Color(0.25, 0.35, 0.55)
	m.roughness = 0.85
	return m
