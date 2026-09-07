extends "res://levels/level_base.gd"
# Poolrooms「泳池房 / Level 37」重做（见 docs/level_poolrooms_design.md，方案①分区过渡）。
# 暖奶油瓷砖无尽水殿：齐踝静水 + 水下焦散光网；圆拱门套/拱券壁龛是本关签名；
# 约 40% 大厅抬升为干爽上层厅（台地 + 拱窗洞 + 栏墙 + 大楼梯），垂直动线一次到位；
# 下层厅高窗带 + 斜射光柱；水中干岛；方灯板与吊球灯并存；弧形隔断 + 墙上黑洞口。
# 结构：全域地面下沉 0.25m + 一整张全局水面（-0.12m），深水池 CSG 减法凿出（-1.1m）。

const PoolroomsGenerator = preload("res://levels/poolrooms_generator.gd")

const FLOOR_TOP := -0.25     # 行走面（全域下沉，脚踝没水）
const WATER_Y := -0.12       # 全局水面
const BASIN_BOTTOM := -1.1   # 深水池底（约齐胸深）
const UPPER_RAISE := 2.0     # 上层厅抬升（台面 = FLOOR_TOP + 2.0 = 1.75）
const PLAT_TOP := FLOOR_TOP + UPPER_RAISE   # 上层厅台面高度
const PLAT_BOTTOM := WATER_Y - 0.5          # 台地水下底
const ISLAND_TOP := 0.03      # 水中干岛台面（高于水面故干爽）

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec3 shallow_color : source_color = vec3(0.22, 0.52, 0.42);
uniform vec3 deep_color : source_color = vec3(0.03, 0.17, 0.13);
uniform vec2 mesh_size = vec2(10.0, 10.0);
uniform float wave_height = 0.022;
uniform float alpha_strength = 0.30;
uniform float foam_strength = 0.45;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(world_pos.x * 1.9 + TIME * 1.3) * 0.45
		+ sin(world_pos.z * 1.6 - TIME * 1.1) * 0.35
		+ sin((world_pos.x + world_pos.z) * 3.1 + TIME * 1.9) * 0.20;
	VERTEX.y += w * wave_height;
}

void fragment() {
	float n1 = sin(world_pos.x * 2.8 + TIME * 1.2) * cos(world_pos.z * 2.3 + TIME * 0.9);
	float n2 = sin(world_pos.x * -2.1 + TIME * 0.8) * cos(world_pos.z * 3.2 + TIME * 1.4);
	vec3 n_world = normalize(vec3(n1 * 0.14, 1.0, n2 * 0.14));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// abs：无论引擎把 VIEW 定义为相机→片元还是片元→相机，fres 都正确
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);

	// 岸边泡沫：距水面边缘泛白，随时间呼吸
	float edge = min(min(UV.x, 1.0 - UV.x) * mesh_size.x, min(UV.y, 1.0 - UV.y) * mesh_size.y);
	float foam = 1.0 - smoothstep(0.05, 0.45, edge);
	foam *= 0.6 + 0.4 * sin(TIME * 2.2 + world_pos.x * 2.0 + world_pos.z * 2.0);

	vec3 col = mix(deep_color, shallow_color, clamp(fres * 0.75 + 0.25, 0.0, 1.0));
	col = mix(col, vec3(0.85, 0.92, 0.90), foam * 0.8);
	ALBEDO = col;
	ROUGHNESS = mix(0.02, 0.3, fres);
	SPECULAR = 0.6;
	EMISSION = shallow_color * 0.03;
	ALPHA = clamp(alpha_strength + fres * 0.25 + foam * 0.4 * foam_strength, 0.0, 0.9);
}
"""

var _deep_rects: Array[Rect2i] = []
var _raised_rects: Array[Rect2i] = []   # 上层厅台地（内缩矩形）
var _raised_halls: Array[Rect2i] = []   # 判为上层的整大厅（柱廊/壁龛跳过）
var _stair_sides: Array[int] = []       # 每个上层厅的楼梯侧（0北1南2西3东）
var _island_rects: Array[Rect2i] = []   # 水中干岛（格坐标近似）
var _block_cells := {}                  # 禁放地标：深水池/柱/台地/干岛/楼梯
var _pickup_bad := {}                   # 禁放拾取物：深水池/柱/干岛/楼梯（台地放开）
var _lamp_mat: StandardMaterial3D
var _panel_mat: StandardMaterial3D
var _caustics: ShaderMaterial
var _black_holes := 0
var _spot_count := 0

func _init() -> void:
	cell_size = 4.5
	wall_height = 6.0
	maze_size = 17
	light_color = Color(1.0, 0.97, 0.88)
	light_energy_range = Vector2(1.8, 2.3)
	light_range = 12.0
	flicker_chance = 0.02
	fill_light_color = Color(0.55, 0.60, 0.58)
	fill_light_energy = 0.12   # 方案①：大厅亮靠主灯，环境压暗衬托深处
	volumetric_fog_density = 0.010
	dust_count = 200
	dust_extents = Vector3(11, 2.4, 11)
	hum_volume_db = -22.0
	hum_pitch = 1.1
	level_title = "Poolrooms"
	hint_text = "水面倒映着无尽的瓷砖"

# —— 生成：大厅互不重叠 → 选上层厅（避开出生/出口）→ 深水池/干岛 ——

func _generate_maze(m) -> void:
	var pool := PoolroomsGenerator.new()
	pool.generate(maze_size, randi())
	maze = pool

	var spawn: Vector2i = maze.find_nearest_floor(Vector2i(1, 1))
	var far: Vector2i = maze.find_farthest_floor(spawn)

	# 上层厅：约 40% 大厅（出生/出口所在的大厅不上层，两者强制落在下层）
	var hall_pool: Array[Rect2i] = []
	for hall in pool.halls:
		var inner := Rect2i(hall.position + Vector2i.ONE, hall.size - Vector2i(2, 2))
		if inner.has_point(spawn) or inner.has_point(far):
			continue
		hall_pool.append(hall)
	hall_pool.shuffle()
	var raised_n := 0
	if not hall_pool.is_empty():
		raised_n = maxi(1, int(ceil(hall_pool.size() * 0.4)))
	for i in mini(raised_n, hall_pool.size()):
		var hall: Rect2i = hall_pool[i]
		_raised_halls.append(hall)
		var side := randi() % 4  # 楼梯侧：台地在该侧多退 1 格，留 2 格进深放大楼梯
		_stair_sides.append(side)
		var inset_n := 1 if side != 0 else 2
		var inset_s := 1 if side != 1 else 2
		var inset_w := 1 if side != 2 else 2
		var inset_e := 1 if side != 3 else 2
		var plat := Rect2i(hall.position.x + inset_w, hall.position.y + inset_n,
			hall.size.x - inset_w - inset_e, hall.size.y - inset_n - inset_s)
		_raised_rects.append(plat)
		_mark_cells(plat, _block_cells)
		_mark_stair_footprint(plat, side)

	# 深水池：非上层大厅，70% 概率，避开出生/出口
	var fallback := Rect2i()
	for hall in pool.halls:
		if _raised_halls.has(hall):
			continue
		var rect := Rect2i(hall.position + Vector2i.ONE, hall.size - Vector2i(2, 2))
		if rect.has_point(spawn) or rect.has_point(far):
			continue
		if rect.get_area() > fallback.get_area():
			fallback = rect
		if randf() > 0.7:
			continue
		var overlap := false
		for r in _deep_rects:
			if r.intersects(rect):
				overlap = true
				break
		if overlap:
			continue
		_deep_rects.append(rect)
		_mark_cells(rect, _block_cells)
		_mark_cells(rect, _pickup_bad)
	if _deep_rects.is_empty() and fallback.size.x > 0:
		_deep_rects.append(fallback)
		_mark_cells(fallback, _block_cells)
		_mark_cells(fallback, _pickup_bad)

	# 水中干岛：12% 下层厅（非深水池厅），台面高于水面故干爽；全图一座就够
	for hall in pool.halls:
		if _raised_halls.has(hall) or randf() > 0.12:
			continue
		var c := hall.get_center()
		var island := Rect2i(Vector2i(int(c.x) - 2, int(c.y) - 2), Vector2i(5, 5))
		var clash := false
		for r in _deep_rects:
			if r.intersects(island):
				clash = true
				break
		if not clash:
			_island_rects.append(island)
			_mark_cells(island, _block_cells)
			_mark_cells(island, _pickup_bad)
			break

func _mark_cells(rect: Rect2i, target: Dictionary) -> void:
	for yy in range(rect.position.y, rect.end.y):
		for xx in range(rect.position.x, rect.end.x):
			target[maze._index(xx, yy)] = true

# 楼梯足迹（格近似）：楼梯侧的 2 格带 × 台阶宽度，地标/拾取物别落台阶上
func _mark_stair_footprint(plat: Rect2i, side: int) -> void:
	var cs := cell_size
	var rect := Rect2i()
	if side == 0 or side == 1:
		var mid: float = (plat.position.x + plat.size.x * 0.5) * cs
		var x0 := int(floor((mid - 1.4) / cs))
		var x1 := int(floor((mid + 1.4) / cs))
		if side == 0:
			rect = Rect2i(x0, plat.position.y - 2, x1 - x0 + 1, 2)
		else:
			rect = Rect2i(x0, plat.end.y, x1 - x0 + 1, 2)
	else:
		var mid: float = (plat.position.y + plat.size.y * 0.5) * cs
		var y0 := int(floor((mid - 1.4) / cs))
		var y1 := int(floor((mid + 1.4) / cs))
		if side == 2:
			rect = Rect2i(plat.position.x - 2, y0, 2, y1 - y0 + 1)
		else:
			rect = Rect2i(plat.end.x, y0, 2, y1 - y0 + 1)
	_mark_cells(rect, _block_cells)
	_mark_cells(rect, _pickup_bad)

func _create_materials() -> void:
	_wall_mat = MatLib.pool_wall_mat()
	_floor_mat = MatLib.pool_floor_mat()
	_ceiling_mat = MatLib.pool_ceiling_grid_mat()  # 防水格栅吊顶
	_pillar_mat = MatLib.pool_wall_mat()
	_light_panel_mat = _make_light_panel_mat(Color(1, 1, 1), Color(1.0, 0.97, 0.88))
	_exit_portal_mat = _make_exit_mat()
	_caustics = MatLib.caustics_mat()
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.98, 0.96, 0.88)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.95, 0.82)
	_lamp_mat.emission_energy_multiplier = 2.5
	_panel_mat = StandardMaterial3D.new()  # 嵌顶方灯板：冷白
	_panel_mat.albedo_color = Color(0.95, 0.97, 0.98)
	_panel_mat.emission_enabled = true
	_panel_mat.emission = Color(0.88, 0.94, 0.98)
	_panel_mat.emission_energy_multiplier = 2.0

# —— 装配：下沉地板（焦散）+ 深水池盆 + 踏步 + 柱廊 + 全局水面 ——

func _build_floor() -> void:
	var total_w: float = maze.width * cell_size
	var total_d: float = maze.height * cell_size

	var floor_node := CSGBox3D.new()
	floor_node.name = "Floor"
	floor_node.use_collision = true
	floor_node.size = Vector3(total_w, 1.0, total_d)
	floor_node.position = Vector3(total_w * 0.5, FLOOR_TOP - 0.5, total_d * 0.5)
	floor_node.material_override = _caustics  # 整片地板都在水下：焦散光网
	add_child(floor_node)

	var details := Node3D.new()
	details.name = "PoolDetails"
	add_child(details)

	# 深水池：在厚地板里凿盆（-0.25 → -1.1），池壁即瓷砖（只出现在下层厅）
	for rect in _deep_rects:
		var ww := rect.size.x * cell_size
		var wd := rect.size.y * cell_size
		var hole := CSGBox3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.size = Vector3(ww, 0.85, wd)
		hole.position = Vector3(
			rect.position.x * cell_size + ww * 0.5,
			-0.675,
			rect.position.y * cell_size + wd * 0.5
		)
		floor_node.add_child(hole)
		_build_pool_stairs(details, rect, true)
		if rect.size.y >= 5:
			_build_pool_stairs(details, rect, false)

	_build_colonnades(details)
	_build_global_water(details, Vector2(total_w, total_d))

# 池边踏步：6 级 × 0.14m 入池，宽 1.6m；north=false 时放南缘反向
func _build_pool_stairs(container: Node3D, rect: Rect2i, north: bool) -> void:
	var cx := (rect.position.x + rect.size.x * 0.5) * cell_size
	var z0: float = rect.position.y * cell_size if north else rect.end.y * cell_size
	for i in 6:
		var top := FLOOR_TOP - 0.14 * float(i + 1)
		var step := CSGBox3D.new()
		step.size = Vector3(1.6, top - BASIN_BOTTOM, 0.45)
		var z: float = z0 + 0.225 + i * 0.45 if north else z0 - 0.225 - i * 0.45
		step.position = Vector3(cx, (top + BASIN_BOTTOM) * 0.5, z)
		step.material = _floor_mat
		step.use_collision = true
		container.add_child(step)

# 大厅柱廊：≥5×5 的下层大厅沿长边两排圆柱，立在水中（水中柱是本关的签名景观）
func _build_colonnades(container: Node3D) -> void:
	for hall in (maze as PoolroomsGenerator).halls:
		if _raised_halls.has(hall):
			continue
		if hall.size.x < 5 or hall.size.y < 5:
			continue
		var y1: int = hall.position.y + 1
		var y2: int = hall.end.y - 2
		if y2 <= y1:
			continue
		for x in range(hall.position.x + 1, hall.end.x - 1, 2):
			_column(container, Vector2i(x, y1))
			_column(container, Vector2i(x, y2))

func _column(container: Node3D, cell: Vector2i) -> void:
	var base := _cell_to_world(cell)
	var col := CSGCylinder3D.new()
	col.radius = 0.32
	col.height = wall_height - FLOOR_TOP + 0.2
	col.sides = 16
	col.position = Vector3(base.x, (wall_height + FLOOR_TOP) * 0.5, base.z)
	col.material = _pillar_mat
	col.use_collision = true
	container.add_child(col)
	# 柱础盘：水中的圆柱有个加宽底座才像泳池房；水下段带焦散
	var foot := CSGCylinder3D.new()
	foot.radius = 0.46
	foot.height = 0.2
	foot.sides = 16
	foot.position = Vector3(base.x, FLOOR_TOP + 0.1, base.z)
	foot.material_override = _caustics
	foot.use_collision = true
	container.add_child(foot)
	_block_cells[maze._index(cell.x, cell.y)] = true
	_pickup_bad[maze._index(cell.x, cell.y)] = true

# 全局水面：一整张连续大平面盖住整张图（脚踝深），深水池水面自然连续
func _build_global_water(container: Node3D, size: Vector2) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	var mesh := MeshInstance3D.new()
	mesh.name = "Water"
	mesh.mesh = plane
	mesh.position = Vector3(size.x * 0.5, WATER_Y, size.y * 0.5)
	mesh.material_override = _water_material(size)
	container.add_child(mesh)

func _water_material(size: Vector2) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("mesh_size", size)
	m.set_shader_parameter("foam_strength", 0.45)
	return m

# —— 灯：吊球灯 / 嵌顶方灯板 各 50%（图 2/3 两种顶灯并存）——

func _place_lights() -> void:
	var light_container := Node3D.new()
	light_container.name = "Lights"
	add_child(light_container)

	var floor_cells: Array[Vector2i] = maze.get_all_floor_cells()
	var covered := {}
	var range_in_cells: float = light_range * 0.8 / cell_size
	var lamp_positions: Array[Vector2i] = []
	for cell in floor_cells:
		if covered.has(cell):
			continue
		lamp_positions.append(cell)
		for other in floor_cells:
			if covered.has(other):
				continue
			var dist: float = Vector2(other.x - cell.x, other.y - cell.y).length()
			if dist <= range_in_cells:
				covered[other] = true

	for cell_pos in lamp_positions:
		var world_pos := _cell_to_world(cell_pos)
		var is_flicker: bool = randf() < flicker_chance
		var light: OmniLight3D
		if is_flicker:
			light = FlickeringLight.new()
		else:
			light = OmniLight3D.new()
		light.light_color = light_color
		light.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
		light.omni_range = light_range
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		Atmosphere.set_fog_energy(light, 0.8)

		if randf() < 0.5:
			# 方灯板：嵌在格栅顶里的冷白方板
			light.position = world_pos + Vector3(0, wall_height - 0.35, 0)
			light_container.add_child(light)
			var panel := CSGBox3D.new()
			panel.size = Vector3(1.4, 0.08, 1.4)
			panel.position = world_pos + Vector3(0, wall_height - 0.06, 0)
			panel.material = _panel_mat
			panel.use_collision = false
			light_container.add_child(panel)
		else:
			# 吊球灯：细线 + 乳白暖光球
			var lamp_y := 3.0
			light.position = world_pos + Vector3(0, lamp_y - 0.05, 0)
			light_container.add_child(light)
			var cord_len: float = wall_height - lamp_y - 0.15
			var cord := CSGCylinder3D.new()
			cord.radius = 0.02
			cord.height = cord_len
			cord.sides = 6
			cord.position = Vector3(world_pos.x, lamp_y + 0.15 + cord_len * 0.5, world_pos.z)
			cord.material = _pillar_mat
			light_container.add_child(cord)
			var bulb := CSGSphere3D.new()
			bulb.radius = 0.17
			bulb.position = Vector3(world_pos.x, lamp_y, world_pos.z)
			bulb.material = _lamp_mat
			light_container.add_child(bulb)

# —— 墙钩子：墙上黑洞口（图 1 的未知通风口，凿穿 + 黑背板封死）——

func _emit_wall(container: Node3D, mat: StandardMaterial3D, horizontal: bool, line: int, sgn: int, a: int, b: int) -> CSGBox3D:
	var wall := super(container, mat, horizontal, line, sgn, a, b)
	if _black_holes < 3 and (b - a + 1) >= 5 and randf() < 0.08:
		_black_holes += 1
		var length: float = float(b - a + 1) * cell_size + WALL_THICK
		var t := randf_range(-length * 0.5 + 0.9, length * 0.5 - 0.9)
		var hole_h := 1.35
		var y_off: float = FLOOR_TOP + hole_h * 0.5 - wall_height * 0.5
		# 凿穿墙厚（0.28）：从走廊侧看是一个 0.9×1.35 的黑洞
		var hole := CSGBox3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.size = Vector3(0.9, hole_h, 0.34) if horizontal else Vector3(0.34, hole_h, 0.9)
		hole.position = Vector3(t, y_off, 0) if horizontal else Vector3(0, y_off, t)
		wall.add_child(hole)
		# 黑背板：albedo≈0.02，钉在墙背面把洞封死——"这里面通向哪？"
		var back := CSGBox3D.new()
		back.size = Vector3(1.04, hole_h + 0.12, 0.06) if horizontal else Vector3(0.06, hole_h + 0.12, 1.04)
		back.material = _hole_mat()
		back.use_collision = false
		if horizontal:
			back.position = Vector3(t, y_off, -sgn * (WALL_THICK * 0.5 + 0.05))
		else:
			back.position = Vector3(-sgn * (WALL_THICK * 0.5 + 0.05), y_off, t)
		container.add_child(back)
	return wall

static func _hole_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.roughness = 1.0
	return m

# —— 装修：台地 + 大楼梯 + 干岛 + 拱券门套 + 壁龛 + 高窗光柱 + 弧形隔断 ——

func _custom_build() -> void:
	var deco := Node3D.new()
	deco.name = "Deco"
	add_child(deco)

	for i in _raised_rects.size():
		_build_platform(deco, _raised_rects[i], _stair_sides[i])
		_build_grand_stairs(deco, _raised_rects[i], _stair_sides[i])
	for hall in (maze as PoolroomsGenerator).halls:
		if not _raised_halls.has(hall):
			_build_lower_hall_features(deco, hall)
	_build_hall_arches(deco)

# 上层厅台地：实心瓷砖块（顶面可走）+ 拱窗洞 + 栏墙（楼梯侧留豁口）+ 台底冷光
func _build_platform(container: Node3D, plat: Rect2i, side: int) -> void:
	var px0 := plat.position.x * cell_size
	var pz0 := plat.position.y * cell_size
	var pw := plat.size.x * cell_size
	var pd := plat.size.y * cell_size
	var cx := px0 + pw * 0.5
	var cz := pz0 + pd * 0.5
	var cy := (PLAT_TOP + PLAT_BOTTOM) * 0.5

	var block := CSGBox3D.new()
	block.name = "RaisedPlatform"
	block.size = Vector3(pw, PLAT_TOP - PLAT_BOTTOM, pd)
	block.position = Vector3(cx, cy, cz)
	block.material = _wall_mat
	block.use_collision = true
	container.add_child(block)

	# 四壁拱窗洞（SUBTRACT 矩形 + 半圆柱 = 半圆拱壁龛，3 个/面）
	var box_y: float = 0.62 - cy   # 壁龛盒中心（世界 0.62）
	var arch_y: float = 1.05 - cy  # 拱心（世界 1.05）
	for k in [-0.28, 0.0, 0.28]:
		var off: float = k * minf(pw, pd)
		for sx in [-1.0, 1.0]:
			var h1 := CSGBox3D.new()
			h1.operation = CSGShape3D.OPERATION_SUBTRACTION
			h1.size = Vector3(0.42, 0.9, 1.0)
			h1.position = Vector3(sx * (pw * 0.5 - 0.2), box_y, off)
			block.add_child(h1)
			var a1 := CSGCylinder3D.new()
			a1.operation = CSGShape3D.OPERATION_SUBTRACTION
			a1.radius = 0.5
			a1.height = 0.42
			a1.sides = 12
			a1.rotation.z = PI * 0.5
			a1.position = Vector3(sx * (pw * 0.5 - 0.2), arch_y, off)
			block.add_child(a1)
		for sz in [-1.0, 1.0]:
			var h2 := CSGBox3D.new()
			h2.operation = CSGShape3D.OPERATION_SUBTRACTION
			h2.size = Vector3(1.0, 0.9, 0.42)
			h2.position = Vector3(off, box_y, sz * (pd * 0.5 - 0.2))
			block.add_child(h2)
			var a2 := CSGCylinder3D.new()
			a2.operation = CSGShape3D.OPERATION_SUBTRACTION
			a2.radius = 0.5
			a2.height = 0.42
			a2.sides = 12
			a2.rotation.x = PI * 0.5
			a2.position = Vector3(off, arch_y, sz * (pd * 0.5 - 0.2))
			block.add_child(a2)

	# 栏墙：台面边缘 1.0m 瓷砖矮墙（楼梯口留豁口）
	_railing(container, Rect2(px0, pz0, pw, pd), side)

	# 台底冷光：给台地四周的下层水面补一点冷光
	for s in [Vector2(px0 - 1.5, cz), Vector2(px0 + pw + 1.5, cz),
			Vector2(cx, pz0 - 1.5), Vector2(cx, pz0 + pd + 1.5)]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.72, 0.78)
		l.light_energy = 0.6
		l.omni_range = 6.0
		l.omni_attenuation = 1.5
		l.shadow_enabled = false
		l.position = Vector3(s.x, 1.0, s.y)
		Atmosphere.set_fog_energy(l, 0.5)
		container.add_child(l)

# 栏墙（楼梯侧留 3.4m 豁口）；Rect2 的 y 轴当世界 Z 用
func _railing(container: Node3D, world_rect: Rect2, side: int) -> void:
	var top := PLAT_TOP + 0.5
	var inset := 0.1
	var x0 := world_rect.position.x + inset
	var x1 := world_rect.end.x - inset
	var z0 := world_rect.position.y + inset
	var z1 := world_rect.end.y - inset
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var gap := 3.4
	for zz: float in [z0, z1]:
		if (side == 0 and zz == z0) or (side == 1 and zz == z1):
			_seg(container, Rect2(x0, zz - 0.07, cx - gap * 0.5 - x0, 0.14), top)
			_seg(container, Rect2(cx + gap * 0.5, zz - 0.07, x1 - cx - gap * 0.5, 0.14), top)
		else:
			_seg(container, Rect2(x0, zz - 0.07, x1 - x0, 0.14), top)
	for xx: float in [x0, x1]:
		if (side == 2 and xx == x0) or (side == 3 and xx == x1):
			_seg(container, Rect2(xx - 0.07, z0, 0.14, cz - gap * 0.5 - z0), top)
			_seg(container, Rect2(xx - 0.07, cz + gap * 0.5, 0.14, z1 - cz - gap * 0.5), top)
		else:
			_seg(container, Rect2(xx - 0.07, z0, 0.14, z1 - z0), top)

func _seg(container: Node3D, r: Rect2, y: float) -> void:
	if r.size.x <= 0.1 or r.size.y <= 0.1:
		return
	var seg := CSGBox3D.new()
	seg.size = Vector3(r.size.x, 1.0, r.size.y)
	seg.position = Vector3(r.get_center().x, y + 0.5, r.get_center().y)
	seg.material = _wall_mat
	seg.use_collision = true
	container.add_child(seg)

# 大楼梯：12 级实心瓷砖台阶（0.167 × 12 ≈ 2m 抬升）+ 底部暖光地灯
func _build_grand_stairs(container: Node3D, plat: Rect2i, side: int) -> void:
	var px0 := plat.position.x * cell_size
	var pz0 := plat.position.y * cell_size
	var pw := plat.size.x * cell_size
	var pd := plat.size.y * cell_size
	var cx := px0 + pw * 0.5
	var cz := pz0 + pd * 0.5
	var steps := 12
	var rise := (PLAT_TOP - FLOOR_TOP) / steps
	var run := 0.35
	var width := 2.6

	for i in steps:
		var top_y := FLOOR_TOP + rise * (i + 1)
		var step := CSGBox3D.new()
		var dist := (steps - 1 - i) * run + run * 0.5
		var pos := Vector3(cx, (top_y + FLOOR_TOP) * 0.5, pz0 - dist)
		step.size = Vector3(width, top_y - FLOOR_TOP, run)
		if side == 1:
			pos = Vector3(cx, pos.y, pz0 + pd + dist)
		elif side == 2:
			step.size = Vector3(run, top_y - FLOOR_TOP, width)
			pos = Vector3(px0 - dist, (top_y + FLOOR_TOP) * 0.5, cz)
		elif side == 3:
			step.size = Vector3(run, top_y - FLOOR_TOP, width)
			pos = Vector3(px0 + pw + dist, (top_y + FLOOR_TOP) * 0.5, cz)
		step.position = pos
		step.material = _floor_mat
		step.use_collision = true
		container.add_child(step)

	# 楼梯底部的暖光地灯：照亮上楼的路（弱指引）
	var base := Vector3(cx, 0.35, pz0 - steps * run - 0.6)
	if side == 1:
		base = Vector3(cx, 0.35, pz0 + pd + steps * run + 0.6)
	elif side == 2:
		base = Vector3(px0 - steps * run - 0.6, 0.35, cz)
	elif side == 3:
		base = Vector3(px0 + pw + steps * run + 0.6, 0.35, cz)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 1.2
	l.omni_range = 7.0
	l.omni_attenuation = 1.5
	l.shadow_enabled = false
	l.position = base
	Atmosphere.set_fog_energy(l, 0.7)
	container.add_child(l)

# 下层厅特色：壁龛灯带 + 高窗光柱 + 弧形隔断 + 水中干岛
func _build_lower_hall_features(container: Node3D, hall: Rect2i) -> void:
	_build_alcoves(container, hall)
	_build_high_windows(container, hall)
	if hall.size.x >= 6 and randf() < 0.3:
		_build_arc_partition(container, hall)
	for island in _island_rects:
		if hall.intersects(island):
			_build_dry_island(container, island)
			break

# 大厅某侧的边界格遍历（normal 朝厅内；外格 = edge - normal 是墙才贴东西）
func _hall_side_cells(hall: Rect2i, normal: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if normal.x != 0:
		var x := hall.position.x if normal.x > 0 else hall.end.x - 1
		for y in range(hall.position.y, hall.end.y):
			cells.append(Vector2i(x, y))
	else:
		var y := hall.position.y if normal.y > 0 else hall.end.y - 1
		for x in range(hall.position.x, hall.end.x):
			cells.append(Vector2i(x, y))
	return cells

# 拱券壁龛（图 3）：贴墙瓷砖板 + 内凹半拱 + 暖光灯带，沿墙每 3 格一个
func _build_alcoves(container: Node3D, hall: Rect2i) -> void:
	for normal in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if randf() < 0.45:
			continue  # 四面都贴会太满
		var cells := _hall_side_cells(hall, normal)
		var i := 2
		while i < cells.size() - 1:
			var edge: Vector2i = cells[i]
			var outer: Vector2i = edge - normal
			if maze.is_wall(outer.x, outer.y):
				_alcove(container, _wall_anchor(edge, normal))
			i += 3

# 壁龛本体：锚点局部坐标（+Z 朝大厅内）
func _alcove(container: Node3D, anchor: Node3D) -> void:
	var slab := CSGBox3D.new()
	slab.size = Vector3(1.5, 2.4, 0.32)
	slab.position = Vector3(0, FLOOR_TOP + 1.2, 0.16)
	slab.material = _wall_mat
	slab.use_collision = true
	anchor.add_child(slab)
	var niche := CSGBox3D.new()
	niche.operation = CSGShape3D.OPERATION_SUBTRACTION
	niche.size = Vector3(1.0, 1.5, 0.34)
	niche.position = Vector3(0, FLOOR_TOP + 0.75, 0.03)
	slab.add_child(niche)
	var arch := CSGCylinder3D.new()
	arch.operation = CSGShape3D.OPERATION_SUBTRACTION
	arch.radius = 0.5
	arch.height = 0.34
	arch.sides = 12
	arch.rotation.x = PI * 0.5
	arch.position = Vector3(0, FLOOR_TOP + 1.5, 0.03)
	slab.add_child(arch)
	# 龛顶暖光灯带：远看是一排发光的拱形 alcove
	var strip := CSGBox3D.new()
	strip.size = Vector3(0.95, 0.07, 0.05)
	strip.position = Vector3(0, FLOOR_TOP + 1.56, 0.10)
	strip.material = _lamp_mat
	strip.use_collision = false
	anchor.add_child(strip)

# 高窗带（图 1）：4.5m 高的冷白发亮窗板 + 斜射光柱（数量克制，全图 ≤6 束）
func _build_high_windows(container: Node3D, hall: Rect2i) -> void:
	var normals := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var normal: Vector2i = normals[randi() % normals.size()]
	var cells := _hall_side_cells(hall, normal)
	var made := 0
	var i := 2
	while i < cells.size() - 1 and made < 3:
		var edge: Vector2i = cells[i]
		var outer := edge - normal
		if maze.is_wall(outer.x, outer.y):
			var anchor := _wall_anchor(edge, normal)
			var panel := CSGBox3D.new()
			panel.size = Vector3(1.7, 1.1, 0.06)
			panel.position = Vector3(0, 4.5, 0.03)
			panel.material = _cold_window_mat()
			panel.use_collision = false
			anchor.add_child(panel)
			# 斜射光柱：从窗口向厅心水面打一束窄角 SpotLight（落在柱基/水面，焦散接住）
			if _spot_count < 6 and randf() < 0.6:
				_spot_count += 1
				var spot := SpotLight3D.new()
				spot.position = anchor.position + Vector3(normal.x * 0.3, 4.4, normal.y * 0.3)
				container.add_child(spot)
				var perp := Vector2(normal.y, normal.x) * randf_range(-3.0, 3.0)
				var target := anchor.position + Vector3(
					normal.x * hall.size.x * cell_size * 0.4 + perp.x,
					FLOOR_TOP,
					normal.y * hall.size.y * cell_size * 0.4 + perp.y)
				spot.look_at(target)
				spot.spot_angle = 20.0
				spot.spot_range = 16.0
				spot.light_energy = 3.2
				spot.light_color = Color(0.75, 0.88, 0.95)
				spot.shadow_enabled = true
				Atmosphere.set_fog_energy(spot, 1.6)
			made += 1
		i += 4

static func _cold_window_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.92, 0.96)
	m.emission_enabled = true
	m.emission = Color(0.72, 0.85, 0.95)
	m.emission_energy_multiplier = 1.6
	return m

# 弧形隔断（图 2）：几段短盒近似弧排，立在水里把视线拐个弯
func _build_arc_partition(container: Node3D, hall: Rect2i) -> void:
	var c := hall.get_center()
	var cx := c.x * cell_size + randf_range(-1.0, 1.0) * cell_size
	var cz := c.y * cell_size + randf_range(-1.0, 1.0) * cell_size
	var r := 2.4
	var start := randf() * PI
	for i in 7:
		var ang := start + i * 0.36
		var seg := CSGBox3D.new()
		seg.size = Vector3(1.35, 2.6, 0.24)
		seg.position = Vector3(cx + cos(ang) * r, FLOOR_TOP + 1.3, cz + sin(ang) * r)
		seg.rotation.y = -ang
		seg.material = _wall_mat
		seg.use_collision = true
		container.add_child(seg)

# 水中干岛（经典超现实点）：厅中央 +0.03m 干爽平台 + 环形踏步 + 坐台矮墙
func _build_dry_island(container: Node3D, island: Rect2i) -> void:
	var c := island.get_center()
	var cx := c.x * cell_size
	var cz := c.y * cell_size
	# 环形踏步（一级 0.14，从水下地面登上半台）
	var ring := CSGBox3D.new()
	ring.size = Vector3(8.2, 0.14, 8.2)
	ring.position = Vector3(cx, FLOOR_TOP + 0.07, cz)
	ring.material = _floor_mat
	ring.use_collision = true
	container.add_child(ring)
	# 干岛台面（顶 +0.03，高于水面 -0.12 故干爽）
	var plat := CSGBox3D.new()
	plat.size = Vector3(7.0, 0.42, 7.0)
	plat.position = Vector3(cx, ISLAND_TOP - 0.21, cz)
	plat.material = _wall_mat
	plat.use_collision = true
	container.add_child(plat)
	# 坐台矮墙：平台边缘四段（角上留缺口）
	for d in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var w := CSGBox3D.new()
		w.size = Vector3(4.6 if d.x != 0 else 0.35, 0.38, 0.35 if d.x != 0 else 4.6)
		w.position = Vector3(cx + d.x * 3.32, ISLAND_TOP + 0.19, cz + d.y * 3.32)
		w.material = _wall_mat
		w.use_collision = true
		container.add_child(w)

# 拱券门套（图 4 签名）：通道进大厅的门洞补成半圆拱——
# 瓷砖挡板 SUBTRACT（矩形 + 半圆柱），两侧自然留下拱肩
func _build_hall_arches(container: Node3D) -> void:
	for hall in (maze as PoolroomsGenerator).halls:
		_arch_side(container, hall, Vector2i(0, -1))  # 北
		_arch_side(container, hall, Vector2i(0, 1))   # 南
		_arch_side(container, hall, Vector2i(-1, 0))  # 西
		_arch_side(container, hall, Vector2i(1, 0))   # 东

func _arch_side(container: Node3D, hall: Rect2i, dir: Vector2i) -> void:
	# 沿墙扫连续开口（大厅边界格外侧是地板 = 通道口）
	var span := hall.size.x if dir.y != 0 else hall.size.y
	var run_start := -1
	for i in span + 1:
		var open := false
		if i < span:
			var edge := _edge_cell(hall, dir, i)
			var outer := edge + dir
			open = maze.is_floor(outer.x, outer.y)
		if open and run_start < 0:
			run_start = i
		elif not open and run_start >= 0:
			_try_arch(container, hall, dir, run_start, i - 1)
			run_start = -1

func _edge_cell(hall: Rect2i, dir: Vector2i, i: int) -> Vector2i:
	if dir.y < 0:
		return Vector2i(hall.position.x + i, hall.position.y)
	if dir.y > 0:
		return Vector2i(hall.position.x + i, hall.end.y - 1)
	if dir.x < 0:
		return Vector2i(hall.position.x, hall.position.y + i)
	return Vector2i(hall.end.x - 1, hall.position.y + i)

func _try_arch(container: Node3D, hall: Rect2i, dir: Vector2i, a: int, b: int) -> void:
	var run_len := b - a + 1
	if run_len < 2 or run_len > 3:
		return  # 只包通道口（2~3 格宽）；大厅相接的大开口不包
	# 两端要有墙夹着（否则是两家大厅打通的开阔地，拱会飘在半空）
	var before := _edge_cell(hall, dir, a - 1) + dir
	var after := _edge_cell(hall, dir, b + 1) + dir
	if a - 1 >= 0 and not maze.is_wall(before.x, before.y):
		return
	if b + 1 < (hall.size.x if dir.y != 0 else hall.size.y) and not maze.is_wall(after.x, after.y):
		return

	var w := run_len * cell_size
	var spring := FLOOR_TOP + 2.3
	var r := minf((w - 1.4) * 0.5, wall_height - 0.5 - spring)
	r = minf(r, 3.4)
	var hole_w := r * 2.0

	var center := Vector3()
	var along_x := dir.y != 0
	if along_x:
		var z_line: float = hall.position.y * cell_size if dir.y < 0 else hall.end.y * cell_size
		var cx := (hall.position.x + a + run_len * 0.5) * cell_size
		center = Vector3(cx, (wall_height + FLOOR_TOP) * 0.5, z_line)
	else:
		var x_line: float = hall.position.x * cell_size if dir.x < 0 else hall.end.x * cell_size
		var cz := (hall.position.y + a + run_len * 0.5) * cell_size
		center = Vector3(x_line, (wall_height + FLOOR_TOP) * 0.5, cz)

	var board := CSGBox3D.new()
	board.size = Vector3(w, wall_height - FLOOR_TOP, WALL_THICK + 0.06) if along_x \
			else Vector3(WALL_THICK + 0.06, wall_height - FLOOR_TOP, w)
	board.position = center
	board.material = _wall_mat
	board.use_collision = true
	container.add_child(board)

	# 拱洞：矩形（到起拱线）+ 半圆柱（拱心）
	var rect_hole := CSGBox3D.new()
	rect_hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	rect_hole.size = Vector3(hole_w, spring - FLOOR_TOP, WALL_THICK + 0.1) if along_x \
			else Vector3(WALL_THICK + 0.1, spring - FLOOR_TOP, hole_w)
	rect_hole.position = Vector3(0, (spring + FLOOR_TOP) * 0.5 - center.y, 0)
	board.add_child(rect_hole)
	var cyl := CSGCylinder3D.new()
	cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
	cyl.radius = r
	cyl.height = WALL_THICK + 0.1
	cyl.sides = 16
	if along_x:
		cyl.rotation.z = PI * 0.5
	else:
		cyl.rotation.x = PI * 0.5
	cyl.position = Vector3(0, spring - center.y, 0)
	board.add_child(cyl)

# —— 墙面特征通用锚点：贴墙 + 朝厅内（局部 +Z = 朝厅内的法线）——

func _wall_anchor(edge_cell: Vector2i, normal: Vector2i) -> Node3D:
	var anchor := Node3D.new()
	var at := _cell_to_world(edge_cell)
	anchor.position = Vector3(
		at.x + normal.x * cell_size * 0.5,
		0.0,
		at.z + normal.y * cell_size * 0.5
	)
	anchor.rotation.y = atan2(float(normal.x), float(normal.y))
	add_child(anchor)
	return anchor

# —— 出生/出口强制下层；按格查层落地 ——

func _position_player() -> void:
	spawn_cell = maze.find_nearest_floor(Vector2i(1, 1))
	if _raised_rect_has(spawn_cell):
		spawn_cell = _nearest_lower(spawn_cell)
	var spawn_pos := _cell_to_world(spawn_cell)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = spawn_pos + Vector3(0, 1.0, 0)
		player.rotation.y = -PI * 0.5

func _pick_exit_cell() -> Vector2i:
	var c: Vector2i = maze.find_farthest_floor(spawn_cell)
	if _raised_rect_has(c):
		c = _nearest_lower(c)
	return c

func _nearest_lower(from: Vector2i) -> Vector2i:
	if not _raised_rect_has(from):
		return from
	var visited := {}
	var queue: Array[Vector2i] = [from]
	visited[from] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if not _raised_rect_has(cur):
			return cur
		for dir in DIRS4:
			var n: Vector2i = cur + dir
			if maze.is_floor(n.x, n.y) and not visited.has(n):
				visited[n] = true
				queue.append(n)
	return from

func _raised_rect_has(cell: Vector2i) -> bool:
	for r in _raised_rects:
		if r.has_point(cell):
			return true
	return false

func _island_rect_has(cell: Vector2i) -> bool:
	for r in _island_rects:
		if r.has_point(cell):
			return true
	return false

func _landmark_y_offset(cell: Vector2i) -> float:
	if _raised_rect_has(cell):
		return PLAT_TOP  # 上层厅台面
	if _island_rect_has(cell):
		return ISLAND_TOP  # 干岛台面
	return FLOOR_TOP

func _landmark_blocked(cell: Vector2i) -> bool:
	return _block_cells.has(maze._index(cell.x, cell.y))

func _pickup_blocked(cell: Vector2i) -> bool:
	return _pickup_bad.has(maze._index(cell.x, cell.y))
