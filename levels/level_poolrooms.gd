extends "res://levels/level_base.gd"
# Poolrooms「泳池房 / Level 37」v3 重做（.trae/documents/poolrooms_redesign_plan.md）：
# 明亮暖阳白瓷砖 + 下沉泳池盆 + 干爽走道。水只存在于池盆里——
# 每舱内缩 2 格是干走道，中间下沉池盆（缘圈浅台 -0.35、盆心深水 -1.2、水面 -0.18），
# 罗马阶梯下水；池底焦散衬板、盆顶天花焦散光网、拱窗斜射光柱 + 斜射暖阳；
# 池中柱列、宽桥圆角大拱门、最大舱二层回廊是签名元素。布局：开阔池舱 + 4~6 格宽直通桥。

const PoolroomsGenerator = preload("res://levels/poolrooms_generator.gd")

const DECK_TOP := 0.0        # 干走道面（全域基准）
const WATER_Y := -0.18       # 水面
const SHELF_Y := -0.35       # 浅台面（盆缘一圈，水面下 0.17m）
const BASIN_BOTTOM := -1.2   # 池底（水深 ~1.02m ≈ 齐腰）
const GALLERY_H := 2.2       # 二层回廊台面（仅最大舱）

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec3 shallow_color : source_color = vec3(0.30, 0.60, 0.52);
uniform vec3 deep_color : source_color = vec3(0.05, 0.26, 0.21);
uniform vec2 mesh_size = vec2(10.0, 10.0);
uniform float wave_height = 0.02;
uniform float alpha_strength = 0.32;
uniform float foam_strength = 0.7;

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

	// 池缘泡沫：距盆边泛白，随时间呼吸（每盆独立 quad，UV 边距自动贴池缘）
	float edge = min(min(UV.x, 1.0 - UV.x) * mesh_size.x, min(UV.y, 1.0 - UV.y) * mesh_size.y);
	float foam = 1.0 - smoothstep(0.05, 0.45, edge);
	foam *= 0.6 + 0.4 * sin(TIME * 2.2 + world_pos.x * 2.0 + world_pos.z * 2.0);

	vec3 col = mix(deep_color, shallow_color, clamp(fres * 0.75 + 0.25, 0.0, 1.0));
	col = mix(col, vec3(0.88, 0.94, 0.92), foam * 0.8);
	ALBEDO = col;
	ROUGHNESS = mix(0.02, 0.3, fres);
	SPECULAR = 0.6;
	EMISSION = shallow_color * 0.03;
	ALPHA = clamp(alpha_strength + fres * 0.25 + foam * 0.4 * foam_strength, 0.0, 0.9);
}
"""

var _spot_count := 0
var _black_holes := 0
var _lamp_mat: StandardMaterial3D
var _panel_mat: StandardMaterial3D
var _caustics: ShaderMaterial
var _glow_mat: ShaderMaterial
var _gallery_cells := {}     # 回廊/楼梯投影格（地标/拾取物避开）
var _gallery_hall: Rect2i    # 最大舱（盖回廊用）

func _init() -> void:
	cell_size = 4.5
	wall_height = 7.0
	maze_size = 19
	light_color = Color(1.0, 0.97, 0.88)
	light_energy_range = Vector2(2.0, 2.6)
	light_range = 13.0
	flicker_chance = 0.02
	fill_light_color = Color(0.60, 0.64, 0.62)
	fill_light_energy = 0.35
	volumetric_fog_density = 0.004
	dust_count = 150
	dust_extents = Vector3(11, 2.4, 11)
	hum_volume_db = -22.0
	hum_pitch = 1.1
	level_title = "Poolrooms"
	hint_text = "阳光落在无尽的泳池上"

# —— 生成：舱室图生成器 + 记录最大舱（回廊） ——

func _generate_maze(m) -> void:
	var pool := PoolroomsGenerator.new()
	pool.generate(maze_size, randi())
	maze = pool
	var biggest := Rect2i()
	for hall in pool.halls:
		if hall.get_area() > biggest.get_area():
			biggest = hall
	_gallery_hall = biggest

func _gen() -> PoolroomsGenerator:
	return maze as PoolroomsGenerator

func _create_materials() -> void:
	_wall_mat = MatLib.pool_wall_mat()
	_floor_mat = MatLib.pool_floor_mat()
	_ceiling_mat = MatLib.pool_ceiling_grid_mat()
	_pillar_mat = MatLib.pool_wall_mat()
	_light_panel_mat = _make_light_panel_mat(Color(1, 1, 1), Color(1.0, 0.97, 0.88))
	_exit_portal_mat = _make_exit_mat()
	_caustics = MatLib.caustics_mat()
	_glow_mat = MatLib.caustics_glow_mat()
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.98, 0.96, 0.88)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.95, 0.82)
	_lamp_mat.emission_energy_multiplier = 2.5
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.albedo_color = Color(0.95, 0.97, 0.98)
	_panel_mat.emission_enabled = true
	_panel_mat.emission = Color(0.90, 0.94, 0.97)
	_panel_mat.emission_energy_multiplier = 2.0

# —— 装配：整张厚地板 + 每盆减法凿池 + 浅台/罗马阶/水面/池底焦散/顶焦散 ——

func _build_floor() -> void:
	var total_w: float = maze.width * cell_size
	var total_d: float = maze.height * cell_size
	var gen := _gen()

	# 全图一张厚地板（顶 0 / 底 -1.4），池盆用 CSG 减法凿出
	var slab := CSGBox3D.new()
	slab.name = "Floor"
	slab.use_collision = true
	slab.size = Vector3(total_w, 1.4, total_d)
	slab.position = Vector3(total_w * 0.5, DECK_TOP - 0.7, total_d * 0.5)
	slab.material = _floor_mat
	add_child(slab)

	var pools := Node3D.new()
	pools.name = "Pools"
	add_child(pools)

	for basin in gen.basins:
		_build_basin(slab, pools, basin)

	# 池中柱列：从池底直通天花板（生成器已保证落在深水区）
	for idx in gen.col_cells:
		var x: int = idx % gen.width
		var y: int = int(idx / gen.width)
		var col := CSGCylinder3D.new()
		col.radius = 0.45
		col.height = wall_height - BASIN_BOTTOM
		col.sides = 16
		col.position = Vector3(x * cell_size + cell_size * 0.5,
				(wall_height + BASIN_BOTTOM) * 0.5, y * cell_size + cell_size * 0.5)
		col.material = _pillar_mat
		col.use_collision = true
		pools.add_child(col)

	# 二层回廊：仅最大舱且够长（≥12 格 ≈ 54m）
	if maxi(_gallery_hall.size.x, _gallery_hall.size.y) >= 12:
		_build_gallery(pools, _gallery_hall)

func _build_basin(slab: CSGBox3D, container: Node3D, basin: Rect2i) -> void:
	var cs := cell_size
	var x0 := basin.position.x * cs
	var z0 := basin.position.y * cs
	var w := basin.size.x * cs
	var d := basin.size.y * cs
	var cx := x0 + w * 0.5
	var cz := z0 + d * 0.5

	# ① 减法凿盆：走道面凿到池底（slab 底 -1.4，留 0.2 底板）。
	#    hole 是 slab 的子节点，必须用 slab 局部坐标（世界坐标会把盒子甩到地图外，坑凿不出来）
	var hole := CSGBox3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.size = Vector3(w, DECK_TOP - BASIN_BOTTOM + 0.1, d)
	hole.position = Vector3(cx, (BASIN_BOTTOM + DECK_TOP + 0.1) * 0.5, cz) - slab.position
	slab.add_child(hole)

	# ② 浅台：盆缘一圈（1 格宽）ADD 盒补回 -0.35，四面各一根通长盒
	var ring_h := SHELF_Y - BASIN_BOTTOM
	var ring_cy := (SHELF_Y + BASIN_BOTTOM) * 0.5
	for side in 4:
		var box := CSGBox3D.new()
		var pos: Vector3
		if side == 0:
			box.size = Vector3(w, ring_h, cs)
			pos = Vector3(cx, ring_cy, z0 + cs * 0.5)
		elif side == 1:
			box.size = Vector3(w, ring_h, cs)
			pos = Vector3(cx, ring_cy, z0 + d - cs * 0.5)
		elif side == 2:
			box.size = Vector3(cs, ring_h, d - 2 * cs)
			pos = Vector3(x0 + cs * 0.5, ring_cy, cz)
		else:
			box.size = Vector3(cs, ring_h, d - 2 * cs)
			pos = Vector3(x0 + w - cs * 0.5, ring_cy, cz)
		box.position = pos
		box.material = _floor_mat
		box.use_collision = true
		container.add_child(box)

	# ③ 池底焦散衬板（MeshInstance，不占 CSG 预算）
	var bottom := PlaneMesh.new()
	bottom.size = Vector2(maxf(w - 2 * cs, 0.5), maxf(d - 2 * cs, 0.5))
	var bmesh := MeshInstance3D.new()
	bmesh.mesh = bottom
	bmesh.position = Vector3(cx, BASIN_BOTTOM + 0.02, cz)
	bmesh.material_override = _caustics
	container.add_child(bmesh)

	# ④ 水面：每盆一张独立 quad，泡沫贴池缘
	var water := PlaneMesh.new()
	water.size = Vector2(w, d)
	water.subdivide_width = 24
	water.subdivide_depth = 24
	var wmesh := MeshInstance3D.new()
	wmesh.mesh = water
	wmesh.position = Vector3(cx, WATER_Y, cz)
	wmesh.material_override = _water_material(Vector2(w, d))
	container.add_child(wmesh)

	# ⑤ 盆顶焦散光网：天花下 0.05m 的 additive 发光 quad（朝下投在白天花上）
	var glow := PlaneMesh.new()
	glow.size = Vector2(w, d)
	var gmesh := MeshInstance3D.new()
	gmesh.mesh = glow
	gmesh.rotation.x = PI
	gmesh.position = Vector3(cx, wall_height - 0.05, cz)
	gmesh.material_override = _glow_mat
	container.add_child(gmesh)

	# ⑥ 罗马阶梯：南北各一条
	_build_roman_stairs(container, basin, true)
	_build_roman_stairs(container, basin, false)

# 入池罗马阶梯：6 级 ADD 盒（踏高 1.2/7 ≈ 0.171，玩家胶囊可攀），
# 最后一级落差由池底补齐；north=true 贴北缘向南下，反之贴南缘向北下
func _build_roman_stairs(container: Node3D, basin: Rect2i, north: bool) -> void:
	var cs := cell_size
	var x0 := basin.position.x * cs
	var z0 := basin.position.y * cs
	var w := basin.size.x * cs
	var d := basin.size.y * cs
	var cx := x0 + w * 0.5
	var steps := 6
	var rise := (DECK_TOP - BASIN_BOTTOM) / float(steps + 1)
	var tread := 0.5
	var width := 2.4
	for i in steps:
		var top := DECK_TOP - rise * float(i + 1)
		var step := CSGBox3D.new()
		step.size = Vector3(width, top - BASIN_BOTTOM, tread)
		var z: float = z0 + tread * 0.5 + i * tread if north else z0 + d - tread * 0.5 - i * tread
		step.position = Vector3(cx, (top + BASIN_BOTTOM) * 0.5, z)
		step.material = _floor_mat
		step.use_collision = true
		container.add_child(step)

# 二层回廊：最大舱沿北墙 +2.2m 台面 + 临池栏墙 + 支撑柱，直跑楼梯收在段内。
# 北边界按"外侧是墙"分段建——桥口上方不停板（否则板悬在拱门洞中间挡路）
func _build_gallery(container: Node3D, hall: Rect2i) -> void:
	var cs := cell_size
	var z0 := hall.position.y * cs
	var walk_d := 2.2
	var top := DECK_TOP + GALLERY_H
	var rail_h := 1.0

	# 扫北边界：外侧是墙且本格不是桥带的连续段（≥6 格才有板 + 楼梯的余地）。
	# 水平桥带可能贴着舱北行横穿——只看外侧一行会漏判，板会压住桥带
	var gen := _gen()
	var runs: Array[Vector2i] = []
	var run_start := -1
	for i in hall.size.x + 1:
		var solid := false
		if i < hall.size.x:
			var cx := hall.position.x + i
			solid = maze.is_wall(cx, hall.position.y - 1) \
					and not gen.is_bridge_cell(cx, hall.position.y)
		if solid and run_start < 0:
			run_start = i
		elif not solid and run_start >= 0:
			if i - run_start >= 6:
				runs.append(Vector2i(run_start, i))
			run_start = -1

	for run in runs:
		var x0: float = (hall.position.x + run.x) * cs
		var slab_x0: float = x0 + 4.8   # 西端留 4.8m 空档给楼梯
		var x1: float = (hall.position.x + run.y) * cs

		var slab := CSGBox3D.new()
		slab.size = Vector3(x1 - slab_x0, 0.3, walk_d)
		slab.position = Vector3((slab_x0 + x1) * 0.5, top - 0.15, z0 + walk_d * 0.5)
		slab.material = _floor_mat
		slab.use_collision = true
		container.add_child(slab)

		# 栏墙：临池侧整段 + 两端
		for rr in 3:
			var rail := CSGBox3D.new()
			if rr == 0:
				rail.size = Vector3(x1 - slab_x0, rail_h, 0.12)
				rail.position = Vector3((slab_x0 + x1) * 0.5, top + rail_h * 0.5, z0 + walk_d - 0.06)
			elif rr == 1:
				rail.size = Vector3(0.12, rail_h, walk_d)
				rail.position = Vector3(slab_x0 + 0.06, top + rail_h * 0.5, z0 + walk_d * 0.5)
			else:
				rail.size = Vector3(0.12, rail_h, walk_d)
				rail.position = Vector3(x1 - 0.06, top + rail_h * 0.5, z0 + walk_d * 0.5)
			rail.material = _wall_mat
			rail.use_collision = true
			container.add_child(rail)

		# 直跑楼梯：段内西端空档，从地面向东升到板西端（贴板最高，不出段不插墙）
		var steps := 12
		var rise := GALLERY_H / float(steps)
		for i in steps:
			var step_top := top - rise * float(i + 1)
			var step := CSGBox3D.new()
			step.size = Vector3(0.35, step_top - DECK_TOP, walk_d)
			step.position = Vector3(slab_x0 - (i + 0.5) * 0.35, (step_top + DECK_TOP) * 0.5, z0 + walk_d * 0.5)
			step.material = _floor_mat
			step.use_collision = true
			container.add_child(step)

		# 支撑柱：板下每 3 格一根
		var span := x1 - slab_x0
		var cols := maxi(int(span / (cs * 3.0)), 1)
		for i in cols + 1:
			var px := slab_x0 + span * float(i) / float(cols)
			var col := CSGCylinder3D.new()
			col.radius = 0.28
			col.height = top - 0.3
			col.sides = 12
			col.position = Vector3(px, (top - 0.3) * 0.5, z0 + walk_d * 0.5)
			col.material = _pillar_mat
			col.use_collision = true
			container.add_child(col)

	# 投影格禁放地标/拾取物：回廊北行整行
	for xx in range(hall.position.x + 1, hall.end.x - 1):
		_gallery_cells[maze._index(xx, hall.position.y)] = true
	_gallery_cells[maze._index(hall.position.x, hall.position.y)] = true

func _water_material(size: Vector2) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("mesh_size", size)
	m.set_shader_parameter("foam_strength", 0.7)
	m.set_shader_parameter("wave_height", 0.02)
	return m

# —— 灯：暖阳平行光 + 方灯板/吊球灯 50/50 ——

func _place_lights() -> void:
	var light_container := Node3D.new()
	light_container.name = "Lights"
	add_child(light_container)

	# 暖阳：斜射平行光（拱窗光柱的“光源本体”），全关唯一带影灯
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.94, 0.80)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-35, 28, 0)
	sun.shadow_enabled = true
	Atmosphere.set_fog_energy(sun, 0.0)
	light_container.add_child(sun)

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
			# 方灯板：嵌顶暖白方板
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

# —— 墙钩子：墙上黑洞口（保留：凿穿 + 黑背板封死） ——

func _emit_wall(container: Node3D, mat: StandardMaterial3D, horizontal: bool, line: int, sgn: int, a: int, b: int) -> CSGBox3D:
	var wall := super(container, mat, horizontal, line, sgn, a, b)
	if _black_holes < 3 and (b - a + 1) >= 5 and randf() < 0.08:
		_black_holes += 1
		var length: float = float(b - a + 1) * cell_size + WALL_THICK
		var t := randf_range(-length * 0.5 + 0.9, length * 0.5 - 0.9)
		var hole_h := 1.35
		var y_off: float = DECK_TOP + hole_h * 0.5 - wall_height * 0.5
		var hole := CSGBox3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.size = Vector3(0.9, hole_h, 0.34) if horizontal else Vector3(0.34, hole_h, 0.9)
		hole.position = Vector3(t, y_off, 0) if horizontal else Vector3(0, y_off, t)
		wall.add_child(hole)
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

# —— 装修：拱窗光柱 + 宽桥圆角大拱门 ——

func _custom_build() -> void:
	var deco := Node3D.new()
	deco.name = "Deco"
	add_child(deco)
	for hall in _gen().halls:
		_build_high_windows(deco, hall)
	_build_hall_arches(deco)

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

# 高窗带：暖白发亮窗板 + 斜射光柱（数量克制，全图 ≤6 束）
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
			panel.position = Vector3(0, 5.0, 0.03)
			panel.material = _warm_window_mat()
			panel.use_collision = false
			anchor.add_child(panel)
			# 斜射光柱：从窗口向厅心打窄角 SpotLight（暖阳色，volumetric 接住成光柱）
			if _spot_count < 6 and randf() < 0.6:
				_spot_count += 1
				var spot := SpotLight3D.new()
				spot.position = anchor.position + Vector3(normal.x * 0.3, 4.9, normal.y * 0.3)
				container.add_child(spot)
				var perp := Vector2(normal.y, normal.x) * randf_range(-3.0, 3.0)
				var target := anchor.position + Vector3(
					normal.x * hall.size.x * cell_size * 0.4 + perp.x,
					DECK_TOP,
					normal.y * hall.size.y * cell_size * 0.4 + perp.y)
				spot.look_at(target)
				spot.spot_angle = 18.0
				spot.spot_range = 18.0
				spot.light_energy = 3.0
				spot.light_color = Color(1.0, 0.9, 0.72)
				spot.shadow_enabled = true
				Atmosphere.set_fog_energy(spot, 1.2)
			made += 1
		i += 4

static func _warm_window_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.97, 0.88)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.92, 0.72)
	m.emission_energy_multiplier = 1.8
	return m

# —— 拱门套：桥口（4~8 格宽开口）立洞顶 5.2m 的圆角大拱门 ——
# 板 + 大矩形洞 + 两角半圆柱，两侧自然留下 0.9m 门垛

func _build_hall_arches(container: Node3D) -> void:
	for hall in _gen().halls:
		_arch_side(container, hall, Vector2i(0, -1))
		_arch_side(container, hall, Vector2i(0, 1))
		_arch_side(container, hall, Vector2i(-1, 0))
		_arch_side(container, hall, Vector2i(1, 0))

func _arch_side(container: Node3D, hall: Rect2i, dir: Vector2i) -> void:
	# 沿墙扫连续开口（大厅边界格外侧是地板 = 桥口）
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
	if run_len < 4 or run_len > 8:
		return
	# 两端必须有实墙夹着（桥口凿在墙带上）；贴舱界的开口不立拱，板会悬空在界外
	var span := hall.size.x if dir.y != 0 else hall.size.y
	if a - 1 < 0 or b + 1 >= span:
		return
	var before := _edge_cell(hall, dir, a - 1) + dir
	if not maze.is_wall(before.x, before.y):
		return
	var after := _edge_cell(hall, dir, b + 1) + dir
	if not maze.is_wall(after.x, after.y):
		return

	var w := run_len * cell_size
	var hole_top := DECK_TOP + 5.2
	var corner_r := minf(2.0, w * 0.12)
	var hole_w := w - 1.8
	var rect_bottom := hole_top - corner_r

	var center := Vector3()
	var along_x := dir.y != 0
	if along_x:
		var z_line: float = hall.position.y * cell_size if dir.y < 0 else hall.end.y * cell_size
		var cx := (hall.position.x + a + run_len * 0.5) * cell_size
		center = Vector3(cx, wall_height * 0.5, z_line)
	else:
		var x_line: float = hall.position.x * cell_size if dir.x < 0 else hall.end.x * cell_size
		var cz := (hall.position.y + a + run_len * 0.5) * cell_size
		center = Vector3(x_line, wall_height * 0.5, cz)

	var board := CSGBox3D.new()
	board.size = Vector3(w, wall_height, WALL_THICK + 0.06) if along_x \
			else Vector3(WALL_THICK + 0.06, wall_height, w)
	board.position = center
	board.material = _wall_mat
	board.use_collision = true
	container.add_child(board)

	# 大矩形洞（走到圆角起点）
	var rect_h := rect_bottom - DECK_TOP
	var rect_hole := CSGBox3D.new()
	rect_hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	rect_hole.size = Vector3(hole_w, rect_h, WALL_THICK + 0.12) if along_x \
			else Vector3(WALL_THICK + 0.12, rect_h, hole_w)
	rect_hole.position = Vector3(0, DECK_TOP + rect_h * 0.5 - wall_height * 0.5, 0)
	board.add_child(rect_hole)

	# 两角半圆柱（轴沿墙厚方向打穿）
	var off := hole_w * 0.5 - corner_r
	for s in [-1.0, 1.0]:
		var cyl := CSGCylinder3D.new()
		cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
		cyl.radius = corner_r
		cyl.height = WALL_THICK + 0.14
		cyl.sides = 16
		if along_x:
			cyl.rotation.x = PI * 0.5
		else:
			cyl.rotation.z = PI * 0.5
		cyl.position = Vector3(s * off, rect_bottom - wall_height * 0.5, 0)
		board.add_child(cyl)

# —— 墙面特征通用锚点：贴墙 + 朝厅内（局部 +Z = 朝厅内的法线） ——

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

# —— 落位：出生/出口只落干走道；地标/拾取物避开深水与柱 ——

func _is_walkway(cell: Vector2i) -> bool:
	var g := _gen()
	return g.depth_at(cell) == 0 and not g.col_cells.has(g._index(cell.x, cell.y))

func _position_player() -> void:
	spawn_cell = _nearest_walkway(maze.find_nearest_floor(Vector2i(1, 1)))
	var spawn_pos := _cell_to_world(spawn_cell)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = spawn_pos + Vector3(0, 1.0, 0)
		player.rotation.y = -PI * 0.5

func _pick_exit_cell() -> Vector2i:
	return _nearest_walkway(maze.find_farthest_floor(spawn_cell))

# BFS 找最近的干走道格（池盆缘/柱格不算）
func _nearest_walkway(from: Vector2i) -> Vector2i:
	if _is_walkway(from):
		return from
	var visited := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if _is_walkway(cur):
			return cur
		for dir in DIRS4:
			var n: Vector2i = cur + dir
			if maze.is_floor(n.x, n.y) and not visited.has(n):
				visited[n] = true
				queue.append(n)
	return from

func _landmark_blocked(cell: Vector2i) -> bool:
	return not _is_walkway(cell) or _gallery_cells.has(maze._index(cell.x, cell.y))

func _pickup_blocked(cell: Vector2i) -> bool:
	return _landmark_blocked(cell)

# 拾取物：2 杏仁水 + 4 电池落干走道（间距规则沿用基类），
# 第 3 瓶泡在最大盆中心的深水里、浮在水面（设计亮点：得下水捞）
func _spawn_pickups() -> void:
	GameState.reset_almond_progress(almond_count)
	var container := Node3D.new()
	container.name = "Pickups"
	add_child(container)

	var walkways: Array[Vector2i] = []
	for cell in maze.get_all_floor_cells():
		if not _pickup_blocked(cell):
			walkways.append(cell)
	walkways.shuffle()

	var used: Array[Vector2i] = []
	var almond_placed := 0
	var battery_placed := 0
	var want_almond := almond_count - 1   # 留一瓶泡水
	var want_battery := battery_count
	for cell in walkways:
		if almond_placed >= want_almond and battery_placed >= want_battery:
			break
		if cell == spawn_cell or cell == exit_cell:
			continue
		if Vector2(cell.x - spawn_cell.x, cell.y - spawn_cell.y).length() < 3.0:
			continue
		if Vector2(cell.x - exit_cell.x, cell.y - exit_cell.y).length() < 2.0:
			continue
		var too_close := false
		for u in used:
			if Vector2(cell.x - u.x, cell.y - u.y).length() < 4.0:
				too_close = true
				break
		if too_close:
			continue
		used.append(cell)
		var at := _cell_to_world(cell) + Vector3(0, 0.15, 0)
		if almond_placed < want_almond:
			container.add_child(PickupItem.create(PickupItem.Kind.ALMOND, at))
			almond_placed += 1
		else:
			container.add_child(PickupItem.create(PickupItem.Kind.BATTERY, at))
			battery_placed += 1
	# 兜底：间距放宽也要把走道杏仁水放满（需求优先于电池）
	if almond_placed < want_almond:
		for cell in walkways:
			if almond_placed >= want_almond:
				break
			if cell == spawn_cell or cell == exit_cell or used.has(cell):
				continue
			used.append(cell)
			var at2 := _cell_to_world(cell) + Vector3(0, 0.15, 0)
			container.add_child(PickupItem.create(PickupItem.Kind.ALMOND, at2))
			almond_placed += 1

	# 泡水杏仁水：最大盆中心深水格，浮在水面
	var wet_cell := _submerged_cell()
	var wet_pos := _cell_to_world(wet_cell) + Vector3(0, WATER_Y + 0.08, 0)
	container.add_child(PickupItem.create(PickupItem.Kind.ALMOND, wet_pos))

func _submerged_cell() -> Vector2i:
	var basin := Rect2i()
	for b in _gen().basins:
		if b.get_area() > basin.get_area():
			basin = b
	var g := _gen()
	# 盆内深水且非柱格中取离盆心最近者（柱网加密后盆心可能被柱占）
	var best := Vector2i(-1, -1)
	var best_d := 99999999.0
	var center := basin.get_center()
	for yy in range(basin.position.y, basin.end.y):
		for xx in range(basin.position.x, basin.end.x):
			if g.depth_at(Vector2i(xx, yy)) != g.DEEP_DEPTH or g.col_cells.has(g._index(xx, yy)):
				continue
			var d: float = float((Vector2i(xx, yy) - center).length_squared())
			if d < best_d:
				best_d = d
				best = Vector2i(xx, yy)
	if best.x >= 0:
		return best
	return center
