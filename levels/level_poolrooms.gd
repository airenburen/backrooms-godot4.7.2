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

# —— 上下层体系（一楼走道 0 / 二楼楼板顶面 UPPER_Y）——
const UPPER_Y := 6.0         # 二楼楼板顶面（二楼地面）；一楼净高 = UPPER_Y - T_SLAB = 5.6
const T_SLAB := 0.4          # 楼板/天桥板厚（板底 5.6）
const RAIL_H := 1.1          # 二层栏墙高（跳 0.8m 翻不过去，只准走跳板下水）
const RAIL_T := 0.14         # 栏墙厚
const ARCH_MANTEL := 5.6     # 拱上通行洞底 = 楼板底；洞顶见 ARCH_PASS_TOP
const ARCH_PASS_TOP := 8.4   # 拱上通行洞顶（净高 2.8，上方留 1.1 门楣）
const ARCH_PASS_W_PAD := 0.5 # 通行洞比天桥宽出的余量
const DIVE_LEN := 9.0        # 跳板长度（2 格）
const DIVE_W := 1.4          # 跳板宽

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
var _arches: Array[Dictionary] = []   # {board, along_x, center}：桥口拱门板，供天桥凿通行洞
var _upper_root: Node3D               # 上层几何容器
var _dives: Array[Dictionary] = []    # 跳板规划（栏墙据此留下水口）
var _ground_blocked := {}             # 一楼禁放格（楼梯投影 + 跳板投影）
var _reach := {}                      # 3D 可达图：Vector3i(格x, 格y, 层) -> 步数
var _upper_exit := false              # 出口是否落在二楼（_exit_base_y 用）

func _init() -> void:
	cell_size = 4.5
	wall_height = 9.5
	maze_size = 19
	light_color = Color(1.0, 0.97, 0.88)
	light_energy_range = Vector2(2.0, 2.6)
	light_range = 13.0
	flicker_chance = 0.02
	fill_light_color = Color(0.60, 0.64, 0.62)
	fill_light_energy = 0.35
	volumetric_fog_density = 0.003
	dust_count = 150
	dust_extents = Vector3(11, 3.2, 11)
	hum_volume_db = -22.0
	hum_pitch = 1.1
	level_title = "Poolrooms"
	hint_text = "阳光落在无尽的泳池上"

# —— 生成：舱室图生成器（上层图层由生成器的 _plan_upper 一并产出） ——

func _generate_maze(m) -> void:
	var pool := PoolroomsGenerator.new()
	pool.generate(maze_size, randi())
	maze = pool
	_build_ground_blocked()

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

	# 二层几何在 _custom_build 里建：天桥要穿过拱门板，得等拱门先立好

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

# ── 二层系统：楼板 / 栏墙 / 楼梯 / 天桥（全 Mesh + StaticBody3D，不占 CSG 预算）──

func _build_upper() -> void:
	var gen := _gen()
	_dives = _dive_specs()
	# ① 楼板：按上层图层把连续格并成大矩形（整圈框被切成若干条，不逐格铺）
	for r in _slab_rects():
		var size := Vector3(r.size.x * cell_size, T_SLAB, r.size.y * cell_size)
		var pos := Vector3((r.position.x + r.size.x * 0.5) * cell_size,
				UPPER_Y - T_SLAB * 0.5,
				(r.position.y + r.size.y * 0.5) * cell_size)
		_add_box_mesh(_upper_root, size, pos, _floor_mat)
	# ② 栏墙：沿每块挑空边界（跳板根部留缺口，别把下水口封死）
	for w in gen.upper_wells:
		_build_rails_around(w)
	# ③ 楼梯（每舱一条，可达性的生命线）
	for spec in gen.upper_stairs:
		_build_upper_stairs(spec)
	# ④ 天桥：把各舱二层连成通路网络，并在拱门板上凿通行洞
	for b in gen.upper_bridges:
		_build_upper_bridge(b)

# 上层图层 → 大矩形（贪婪合并，行优先向右扩、再整行向下扩）
func _slab_rects() -> Array[Rect2i]:
	var gen := _gen()
	var used := {}
	var rects: Array[Rect2i] = []
	for y in gen.height:
		for x in gen.width:
			if gen.upper[gen._index(x, y)] != PoolroomsGenerator.UP_SLAB \
					or used.has(gen._index(x, y)):
				continue
			var w := 0
			while x + w < gen.width \
					and gen.upper[gen._index(x + w, y)] == PoolroomsGenerator.UP_SLAB \
					and not used.has(gen._index(x + w, y)):
				w += 1
			var h := 1
			while y + h < gen.height:
				var row_ok := true
				for k in w:
					var i2 := gen._index(x + k, y + h)
					if gen.upper[i2] != PoolroomsGenerator.UP_SLAB or used.has(i2):
						row_ok = false
						break
				if not row_ok:
					break
				h += 1
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					used[gen._index(xx, yy)] = true
			rects.append(Rect2i(x, y, w, h))
	return rects

# 跳板规划：取最大的两块挑空，各选一条长边的中点伸出（栏墙据此留缺口）
func _dive_specs() -> Array[Dictionary]:
	var wells := _gen().upper_wells.duplicate()
	wells.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.get_area() > b.get_area())
	var out: Array[Dictionary] = []
	for i in mini(wells.size(), 2):
		var w: Rect2i = wells[i]
		if maxi(w.size.x, w.size.y) < 5:
			continue
		if w.size.x >= w.size.y:
			out.append({"well": w, "side": 0, "mid": (w.position.x + w.size.x * 0.5) * cell_size})
		else:
			out.append({"well": w, "side": 2, "mid": (w.position.y + w.size.y * 0.5) * cell_size})
	return out

func _build_rails_around(w: Rect2i) -> void:
	var cs := cell_size
	var x0 := w.position.x * cs
	var x1 := w.end.x * cs
	var z0 := w.position.y * cs
	var z1 := w.end.y * cs
	var gap0 := 0.0
	var gap1 := 0.0
	var gap_side := -1
	for d in _dives:
		if d["well"] == w:
			gap_side = int(d["side"])
			var mid: float = d["mid"]
			gap0 = mid - (DIVE_W + 0.6) * 0.5
			gap1 = mid + (DIVE_W + 0.6) * 0.5
	_rail_run(true, z0, x0, x1, gap0, gap1, gap_side == 0)
	_rail_run(true, z1, x0, x1, gap0, gap1, gap_side == 1)
	_rail_run(false, x0, z0, z1, gap0, gap1, gap_side == 2)
	_rail_run(false, x1, z0, z1, gap0, gap1, gap_side == 3)

# 一条边上的栏墙；hole=true 时在 [gap0,gap1] 断开（跳板下水口）
func _rail_run(along_x: bool, fixed: float, a: float, b: float,
		gap0: float, gap1: float, hole: bool) -> void:
	var segs: Array[Vector2] = []
	if hole and gap1 > gap0 and gap0 < b and gap1 > a:
		if gap0 > a:
			segs.append(Vector2(a, minf(gap0, b)))
		if gap1 < b:
			segs.append(Vector2(maxf(gap1, a), b))
	else:
		segs.append(Vector2(a, b))
	for s in segs:
		var length := s.y - s.x
		if length < 0.25:
			continue
		var size := Vector3(length, RAIL_H, RAIL_T) if along_x else Vector3(RAIL_T, RAIL_H, length)
		var pos := Vector3((s.x + s.y) * 0.5, UPPER_Y + RAIL_H * 0.5, fixed) if along_x \
				else Vector3(fixed, UPPER_Y + RAIL_H * 0.5, (s.x + s.y) * 0.5)
		_add_box_mesh(_upper_root, size, pos, _wall_mat)

# ── 楼梯：用世界向量搭几何（uvec 上行方向 / cvec 横向），回廊舱折返、双层舱直跑 ──

func _build_upper_stairs(spec: Dictionary) -> void:
	var cs := cell_size
	var rect: Rect2i = spec["rect"]
	var ud: Vector2i = spec["up_dir"]
	var edge: Vector2i = spec["edge_dir"]
	var along_x := ud.x != 0
	var sign_along := float(ud.x) if along_x else float(ud.y)
	var length := (float(rect.size.x) if along_x else float(rect.size.y)) * cs
	var width := (float(rect.size.y) if along_x else float(rect.size.x)) * cs
	var base_along: float
	if along_x:
		base_along = (float(rect.position.x) if sign_along > 0 else float(rect.end.x)) * cs
	else:
		base_along = (float(rect.position.y) if sign_along > 0 else float(rect.end.y)) * cs
	var cross_center := (float(rect.position.y) + float(rect.size.y) * 0.5) * cs if along_x \
			else (float(rect.position.x) + float(rect.size.x) * 0.5) * cs
	var origin := Vector3(base_along, 0.0, cross_center) if along_x \
			else Vector3(cross_center, 0.0, base_along)
	var uvec := Vector3(sign_along, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, sign_along)
	var cvec := Vector3(0.0, 0.0, 1.0) if along_x else Vector3(1.0, 0.0, 0.0)
	var e_sign := float(edge.y) if along_x else float(edge.x)

	if spec["kind"] == "straight":
		_build_straight_flight(origin, uvec, cvec, length, width, along_x)
	else:
		_build_switch_flight(origin, uvec, cvec, length, width, along_x)
	# 朝舱内一侧的护栏（靠墙侧有墙，不用栏）
	var rpos := origin + cvec * (-e_sign * (width * 0.5 + RAIL_T * 0.5)) \
			+ uvec * (length * 0.5) + Vector3(0.0, UPPER_Y + 0.5, 0.0)
	var rsize := Vector3(length, 1.0, RAIL_T) if along_x else Vector3(RAIL_T, 1.0, length)
	_add_box_mesh(_upper_root, rsize, rpos, _wall_mat)

# 回廊舱：两跑折返（各 17 级，踏高 6.0/34≈0.176；第二跑折回起端，出口在起端外侧）
func _build_switch_flight(origin: Vector3, uvec: Vector3, cvec: Vector3,
		length: float, width: float, along_x: bool) -> void:
	var steps := 17
	var half_h := UPPER_Y * 0.5
	var run_len := length - 1.0
	var td := run_len / float(steps)
	var rise := half_h / float(steps)
	var lane := (width - 0.3) * 0.5
	var lat := lane * 0.5 + 0.075
	for i in steps:
		var top := rise * float(i + 1)
		var d := (float(i) + 0.5) * td
		_add_flight_step(origin + uvec * d + cvec * -lat, top, td, lane, along_x)
	_add_flight_step(origin + uvec * (run_len + 0.5), half_h, 1.0, width, along_x)
	for i in steps:
		var top := half_h + rise * float(i + 1)
		var d := run_len - (float(i) + 0.5) * td
		_add_flight_step(origin + uvec * d + cvec * lat, top, td, lane, along_x)

# 双层舱：单跑直上 34 级（踏深 13.5/34≈0.4，踏高 6.0/34≈0.176），出口在末端外侧
func _build_straight_flight(origin: Vector3, uvec: Vector3, cvec: Vector3,
		length: float, width: float, along_x: bool) -> void:
	var steps := 34
	var td := length / float(steps)
	var rise := UPPER_Y / float(steps)
	var lane := minf(2.4, width - 0.6)
	for i in steps:
		var top := rise * float(i + 1)
		var d := (float(i) + 0.5) * td
		_add_flight_step(origin + uvec * d, top, td, lane, along_x)

# 一级踏面：从走道面实心砌到该级顶面（侧面看是混凝土实心梯）
func _add_flight_step(center_xz: Vector3, top: float, along_size: float,
		cross_size: float, along_x: bool) -> void:
	var size := Vector3(along_size, top - DECK_TOP, cross_size) if along_x \
			else Vector3(cross_size, top - DECK_TOP, along_size)
	_add_box_mesh(_upper_root, size, Vector3(center_xz.x, (top + DECK_TOP) * 0.5, center_xz.z), _floor_mat)

# ── 天桥：桥面只铺"不在任何舱内"的间隙段（两端舱内已有楼板，不重叠免 z-fighting）──

func _build_upper_bridge(b: Dictionary) -> void:
	var along_y: bool = b["axis"]
	var cells: Array = b["cells"]
	var seg: Array[Vector2i] = []
	for c in cells:
		if not _in_any_hall(c):
			seg.append(c)
	if seg.is_empty():
		return
	var cs := cell_size
	var c0: Vector2i = seg[0]
	var c1: Vector2i = seg[seg.size() - 1]
	var length: float
	var size: Vector3
	var cx := 0.0
	var cz := 0.0
	if along_y:
		length = float(c1.y - c0.y + 1) * cs
		cx = (c0.x + 0.5) * cs
		cz = float(c0.y + c1.y + 1) * 0.5 * cs
		size = Vector3(cs, T_SLAB, length)
	else:
		length = float(c1.x - c0.x + 1) * cs
		cx = float(c0.x + c1.x + 1) * 0.5 * cs
		cz = (c0.y + 0.5) * cs
		size = Vector3(length, T_SLAB, cs)
	_add_box_mesh(_upper_root, size, Vector3(cx, UPPER_Y - T_SLAB * 0.5, cz), _floor_mat)
	# 两侧栏墙
	if along_y:
		for s in [-1.0, 1.0]:
			_add_box_mesh(_upper_root, Vector3(RAIL_T, RAIL_H, length),
					Vector3(cx + s * (cs * 0.5 - RAIL_T * 0.5), UPPER_Y + RAIL_H * 0.5, cz), _wall_mat)
	else:
		for s in [-1.0, 1.0]:
			_add_box_mesh(_upper_root, Vector3(length, RAIL_H, RAIL_T),
					Vector3(cx, UPPER_Y + RAIL_H * 0.5, cz + s * (cs * 0.5 - RAIL_T * 0.5)), _wall_mat)
	# 上桥要穿过拱门板：不凿洞就是撞隐形墙
	_punch_arch(along_y, cx, cz)

func _in_any_hall(cell: Vector2i) -> bool:
	for hall in _gen().halls:
		if hall.has_point(cell):
			return true
	return false

# 在拱门板上凿通行洞（5.6~8.4，净高 2.8）。洞必须用 board 的局部坐标
func _punch_arch(along_y: bool, cx: float, cz: float) -> void:
	for arch in _arches:
		if bool(arch["along_x"]) != along_y:
			continue
		var center: Vector3 = arch["center"]
		var dist := absf(center.x - cx) if along_y else absf(center.z - cz)
		if dist > cell_size * 0.5:
			continue
		var board: CSGBox3D = arch["board"]
		var pass_h := ARCH_PASS_TOP - ARCH_MANTEL
		var hole := CSGBox3D.new()
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		var y_local := ARCH_MANTEL + pass_h * 0.5 - board.position.y
		if along_y:
			hole.size = Vector3(cell_size + ARCH_PASS_W_PAD, pass_h, WALL_THICK + 0.2)
			hole.position = Vector3(cx - board.position.x, y_local, 0.0)
		else:
			hole.size = Vector3(WALL_THICK + 0.2, pass_h, cell_size + ARCH_PASS_W_PAD)
			hole.position = Vector3(0.0, y_local, cz - board.position.z)
		board.add_child(hole)

# ── 跳板：从挑空长边中点伸向水面上空（只下不上），根部栏墙已留缺口 ──

func _build_diving_boards() -> void:
	var cs := cell_size
	for d in _dives:
		var w: Rect2i = d["well"]
		var side: int = d["side"]
		var mid: float = d["mid"]
		var size: Vector3
		var pos: Vector3
		if side == 0:
			size = Vector3(DIVE_W, 0.16, DIVE_LEN)
			pos = Vector3(mid, UPPER_Y - 0.08, w.position.y * cs + DIVE_LEN * 0.5)
		else:
			size = Vector3(DIVE_LEN, 0.16, DIVE_W)
			pos = Vector3(w.position.x * cs + DIVE_LEN * 0.5, UPPER_Y - 0.08, mid)
		_add_box_mesh(_upper_root, size, pos, _floor_mat)
		_build_dive_brace(pos, size, side)

# 跳板下的斜撑：从远端板底斜拉到根部下方的池壁，别让 9m 悬臂凭空悬着
func _build_dive_brace(pos: Vector3, size: Vector3, side: int) -> void:
	var span := DIVE_LEN * 0.85
	var rise := 1.9
	var blen := sqrt(span * span + rise * rise)
	var angle := atan2(span, rise)
	var off := (size.x if side == 2 else size.z) * 0.5
	for s in [-1.0, 1.0]:
		var brace := _add_box_mesh(_upper_root, Vector3(0.14, blen, 0.14), Vector3.ZERO, _pillar_mat, true)
		if side == 0:
			brace.position = Vector3(pos.x + s * 0.45, pos.y - rise * 0.5, pos.z - off + span * 0.5)
			brace.rotation.x = angle
		else:
			brace.position = Vector3(pos.x - off + span * 0.5, pos.y - rise * 0.5, pos.z + s * 0.45)
			brace.rotation.z = -angle

# 通用 Mesh 盒（+ 可选静态碰撞）；二层几何一律走这里，绝不新建 CSG
func _add_box_mesh(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		collide := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		mi.add_child(body)
	return mi

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

	var gen := _gen()
	var floor_cells: Array[Vector2i] = maze.get_all_floor_cells()
	# 地面层：上方有板的格改挂板底——天花 9.5 的光全被楼板挡死，不补就是黑胡同
	_place_layer_lights(light_container, floor_cells, false)
	# 二层：只有上方有板的格才站得住人
	var upper_cells: Array[Vector2i] = []
	for cell in floor_cells:
		if gen.upper_slab(cell):
			upper_cells.append(cell)
	_place_layer_lights(light_container, upper_cells, true)

# 一层的灯：复用原贪心覆盖；is_upper 时改挂二层天花、覆盖半径放宽 1.6 倍（灯更稀更省）
func _place_layer_lights(container: Node3D, cells: Array[Vector2i], is_upper: bool) -> void:
	var gen := _gen()
	var covered := {}
	var density := 1.6 if is_upper else 0.8
	var range_in_cells: float = light_range * density / cell_size
	var picks: Array[Vector2i] = []
	for cell in cells:
		if covered.has(cell):
			continue
		picks.append(cell)
		for other in cells:
			if covered.has(other):
				continue
			if Vector2(other.x - cell.x, other.y - cell.y).length() <= range_in_cells:
				covered[other] = true

	for cell_pos in picks:
		var world_pos := _cell_to_world(cell_pos)
		var ceil_y := wall_height
		var lamp_y := 3.0
		if is_upper:
			lamp_y = UPPER_Y + 2.5
		elif gen.upper_slab(cell_pos):
			ceil_y = UPPER_Y - T_SLAB   # 板底就是一层的新"天花"

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
			light.position = Vector3(world_pos.x, ceil_y - 0.35, world_pos.z)
			container.add_child(light)
			_add_box_mesh(container, Vector3(1.4, 0.08, 1.4),
					Vector3(world_pos.x, ceil_y - 0.06, world_pos.z), _panel_mat, false)
		else:
			# 吊球灯：细线 + 乳白暖光球（灯具改 Mesh，省下 CSG 额度给拱门通行洞）
			light.position = Vector3(world_pos.x, lamp_y - 0.05, world_pos.z)
			container.add_child(light)
			var cord_len: float = ceil_y - lamp_y - 0.15
			if cord_len > 0.2:
				var cord := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.02
				cyl.bottom_radius = 0.02
				cyl.height = cord_len
				cyl.radial_segments = 6
				cord.mesh = cyl
				cord.material_override = _pillar_mat
				cord.position = Vector3(world_pos.x, lamp_y + 0.15 + cord_len * 0.5, world_pos.z)
				container.add_child(cord)
			var bulb := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.17
			sph.height = 0.34
			bulb.mesh = sph
			bulb.material_override = _lamp_mat
			bulb.position = Vector3(world_pos.x, lamp_y, world_pos.z)
			container.add_child(bulb)

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
		# back 挂在 container（墙容器，位于原点）下，坐标得补上 wall 的位置；
		# 直接写局部值会把背板甩到地图角落、埋进地板厚板里（等于没封）
		if horizontal:
			back.position = wall.position + Vector3(t, y_off, -sgn * (WALL_THICK * 0.5 + 0.05))
		else:
			back.position = wall.position + Vector3(-sgn * (WALL_THICK * 0.5 + 0.05), y_off, t)
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
	# 二层几何必须放在拱门之后：天桥要在已立好的拱门板上凿通行洞
	_upper_root = Node3D.new()
	_upper_root.name = "Upper"
	add_child(_upper_root)
	_build_upper()
	_build_diving_boards()

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
			panel.position = Vector3(0, 7.3, 0.03)   # 二层窗：5.0 会被回廊板埋进墙里
			panel.material = _warm_window_mat()
			panel.use_collision = false
			anchor.add_child(panel)
			# 斜射光柱：从二层窗口向厅心挑空打窄角 SpotLight（暖阳色，volumetric 接住成光柱）
			if _spot_count < 6 and randf() < 0.6:
				_spot_count += 1
				var spot := SpotLight3D.new()
				spot.position = anchor.position + Vector3(normal.x * 0.3, 7.2, normal.y * 0.3)
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
	# 记下来：二层天桥要穿过这块通高板，得在上面凿通行洞（否则上桥撞隐形墙）
	_arches.append({"board": board, "along_x": along_x, "center": center})

	# 大矩形洞：直接凿到洞顶（圆角交给下面的补角块，不能对板直接减圆柱）
	var rect_h := hole_top - DECK_TOP
	var rect_hole := CSGBox3D.new()
	rect_hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	rect_hole.size = Vector3(hole_w, rect_h, WALL_THICK + 0.12) if along_x \
			else Vector3(WALL_THICK + 0.12, rect_h, hole_w)
	rect_hole.position = Vector3(0, DECK_TOP + rect_h * 0.5 - wall_height * 0.5, 0)
	board.add_child(rect_hole)

	# 两角圆角：先并集补回一个 corner_r 见方的实心角，再从这块角里减掉同半径圆柱，
	# 剩下的"圆外三角"正好把矩形洞的直角磨圆。
	# 顺序不可颠倒：补角块必须在矩形洞之后添加，否则会被洞一并减掉；
	# 若像原先那样直接对板减圆柱，洞顶以上会被凿出两个圆龛，门洞变成两头圆弧、
	# 中间反而矮一截的平顶（既不圆角也不连通）
	var off := hole_w * 0.5 - corner_r
	for s in [-1.0, 1.0]:
		var corner := CSGBox3D.new()
		corner.operation = CSGShape3D.OPERATION_UNION
		corner.size = Vector3(corner_r, corner_r, WALL_THICK + 0.12) if along_x \
				else Vector3(WALL_THICK + 0.12, corner_r, corner_r)
		var cx: float = s * (off + corner_r * 0.5)
		var cy: float = rect_bottom + corner_r * 0.5 - wall_height * 0.5
		corner.position = Vector3(cx, cy, 0) if along_x else Vector3(0, cy, cx)
		corner.material = _wall_mat
		board.add_child(corner)

		# 圆心落在洞顶线上：角块中心在 (s*(off+r/2), rect_bottom+r/2)，圆心在 (s*off, rect_bottom)
		var cyl := CSGCylinder3D.new()
		cyl.operation = CSGShape3D.OPERATION_SUBTRACTION
		cyl.radius = corner_r
		cyl.height = WALL_THICK + 0.14
		cyl.sides = 16
		if along_x:
			cyl.rotation.x = PI * 0.5
		else:
			cyl.rotation.z = PI * 0.5
		cyl.position = Vector3(-s * corner_r * 0.5, -corner_r * 0.5, 0) if along_x \
				else Vector3(0, -corner_r * 0.5, -s * corner_r * 0.5)
		corner.add_child(cyl)

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
	_build_reach()

# 楼梯投影格：一层地面被楼梯压住，不许放地标/拾取物
func _build_ground_blocked() -> void:
	_ground_blocked.clear()
	var gen := _gen()
	for s in gen.upper_stairs:
		var rect: Rect2i = s["rect"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_ground_blocked[gen._index(x, y)] = true

# ── 3D 可达图：节点 =(格, 层)。地面 4 邻接 + 二层板 4 邻接 + 楼梯上下 +（天桥面已算二层板）──

func _blocked_at(cell: Vector2i, layer: int) -> bool:
	var gen := _gen()
	if _ground_blocked.has(gen._index(cell.x, cell.y)):
		return true
	if layer == 1:
		return not gen.upper_slab(cell)
	return not _is_walkway(cell)

func _is_blocked_ground(cell: Vector2i) -> bool:
	# 池中柱是实体；池盆内的浅台/深水可蹚
	return _gen().col_cells.has(_gen()._index(cell.x, cell.y))

func _neighbors_3d(node: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var cell := Vector2i(node.x, node.y)
	var gen := _gen()
	for dir in DIRS4:
		var n: Vector2i = cell + dir
		if node.z == 0:
			if maze.is_floor(n.x, n.y) and not _is_blocked_ground(n):
				out.append(Vector3i(n.x, n.y, 0))
		elif gen.upper_slab(n):
			out.append(Vector3i(n.x, n.y, 1))
	# 楼梯：底层格 ↔ 顶层格（这是"上楼"唯一的正规通道）
	for s in gen.upper_stairs:
		var b: Vector2i = s["bottom"]
		var t: Vector2i = s["top"]
		if node.z == 0 and cell == b:
			out.append(Vector3i(t.x, t.y, 1))
		elif node.z == 1 and cell == t:
			out.append(Vector3i(b.x, b.y, 0))
	return out

func _build_reach() -> void:
	_reach.clear()
	if spawn_cell.x < 0:
		return
	var start := Vector3i(spawn_cell.x, spawn_cell.y, 0)
	_reach[start] = 0
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		var cd: int = _reach[cur]
		for n in _neighbors_3d(cur):
			if _reach.has(n):
				continue
			_reach[n] = cd + 1
			queue.append(n)

# 3D 梯度下降：从任意可达点一路走到出生点（地标/引导用；2D 距离场会指错楼层）
func _reach_next(node: Vector3i) -> Vector3i:
	var here: int = _reach.get(node, -1)
	if here <= 0:
		return Vector3i(-1, -1, -1)
	var best := here - 1
	var best_node := Vector3i(-1, -1, -1)
	for n in _neighbors_3d(node):
		var d: int = _reach.get(n, -1)
		if d == best:
			return n
		if d >= 0 and d < best:
			best = d
			best_node = n
	return best_node

func _trace_path_3d(from_cell: Vector2i) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var cur := Vector3i(from_cell.x, from_cell.y, 0)
	var guard := 0
	while guard < 4096:
		guard += 1
		path.append(cur)
		var nxt := _reach_next(cur)
		if nxt.x < 0:
			break
		cur = nxt
	return path

func _pick_exit_cell() -> Vector2i:
	_upper_exit = false
	# 出口搬到二楼：在"从出生点 3D 可达的二层格"里选 3D 步数最远的贴墙格
	var best := Vector2i(-1, -1)
	var best_d := -1
	for key in _reach:
		var k: Vector3i = key
		if k.z != 1:
			continue
		var cell := Vector2i(k.x, k.y)
		if not _has_wall_neighbor(cell) or _wall_all_bridge(cell):
			continue
		var d: int = _reach[key]
		if d > best_d:
			best_d = d
			best = cell
	if best.x >= 0:
		_upper_exit = true
		return best
	# 兜底：二层没有可达位置 → 退回一层走道，绝不留 3D 死局
	push_warning("Poolrooms: 二层无可达出口位，退回一层出口")
	return _nearest_walkway(maze.find_farthest_floor(spawn_cell), true)

# 邻墙全是桥带格 → 门会立进桥口/拱门洞里，不能用
func _wall_all_bridge(cell: Vector2i) -> bool:
	var any := false
	for dir in DIRS4:
		if not maze.is_wall(cell.x + dir.x, cell.y + dir.y):
			continue
		if not _gen().is_bridge_cell(cell.x + dir.x, cell.y + dir.y):
			return false
		any = true
	return any

# 出口楼层钩子（基类 _place_exit 里读）
func _exit_base_y() -> float:
	return UPPER_Y if _upper_exit else 0.0

func _exit_box_h() -> float:
	return 2.6 if _upper_exit else wall_height

func _has_wall_neighbor(cell: Vector2i) -> bool:
	for dir in DIRS4:
		if maze.is_wall(cell.x + dir.x, cell.y + dir.y):
			return true
	return false

# BFS 找最近的干走道格（池盆缘/柱格不算）；need_wall 时只认有邻墙的格
func _nearest_walkway(from: Vector2i, need_wall := false) -> Vector2i:
	if _is_walkway(from) and (not need_wall or _has_wall_neighbor(from)):
		return from
	var visited := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if _is_walkway(cur) and (not need_wall or _has_wall_neighbor(cur)):
			return cur
		for dir in DIRS4:
			var n: Vector2i = cur + dir
			if maze.is_floor(n.x, n.y) and not visited.has(n):
				visited[n] = true
				queue.append(n)
	return from

func _landmark_blocked(cell: Vector2i) -> bool:
	return _blocked_at(cell, 0)

func _pickup_blocked(cell: Vector2i) -> bool:
	return _blocked_at(cell, 0)

# 地标：基类走的是 2D 距离场，出口在二楼时会把玩家引到出口正下方的一层打转，
# 所以这里换成 3D 路径——顺着真实上楼路线铺地标，并在楼梯口立信标。
func _place_landmarks(from_cell: Vector2i) -> void:
	var container := Node3D.new()
	container.name = "Landmarks"
	add_child(container)
	_place_stair_beacons(container)

	var path := _trace_path_3d(from_cell)
	if path.size() < 3:
		return
	var kind := randi() % 3
	var since := guide_step
	for i in path.size():
		if i < 2 or i > path.size() - 2:
			continue
		var p: Vector3i = path[i]
		var cell := Vector2i(p.x, p.y)
		if _blocked_at(cell, p.z):
			since += 1
			continue
		var is_junction := p.z == 0 and _opening_count(cell) >= 3
		if not (since >= guide_step or (is_junction and since >= 2)):
			since += 1
			continue
		since = 0
		var nxt: Vector3i = path[mini(i + 1, path.size() - 1)]
		var facing := Vector2i(nxt.x - p.x, nxt.y - p.y)
		# 跨层的那一步（楼梯）没有平面朝向，用默认朝北
		if facing == Vector2i.ZERO:
			facing = Vector2i(0, -1)
		var y := UPPER_Y if p.z == 1 else 0.0
		var marker := Landmark.create(kind, facing, _wall_dirs_of(cell), cell_size * 0.5 - 0.02)
		marker.position = _cell_to_world(cell) + marker.position + Vector3(0, y, 0)
		container.add_child(marker)
		kind = (kind + 1) % 3

# 楼梯口信标：二楼要上楼这件事必须被明确指出来，否则玩家在一层绕不出来
func _place_stair_beacons(container: Node3D) -> void:
	for s in _gen().upper_stairs:
		var t: Vector2i = s["top"]
		var at := _cell_to_world(t) + Vector3(0, UPPER_Y + 0.9, 0)
		_add_box_mesh(container, Vector3(0.45, 1.8, 0.45), at, _lamp_mat, false)
		var beacon := OmniLight3D.new()
		beacon.light_color = Color(1.0, 0.96, 0.86)
		beacon.light_energy = 3.0
		beacon.omni_range = 9.0
		beacon.shadow_enabled = false
		beacon.position = at
		Atmosphere.set_fog_energy(beacon, 1.0)
		container.add_child(beacon)

# 拾取物：一层 1 杏仁水 + 2 电池、二层 1 杏仁水 + 2 电池（上楼变成必须），
# 第 3 瓶杏仁水泡在最大盆中心的深水里、浮在水面（得下水捞）
func _spawn_pickups() -> void:
	GameState.reset_almond_progress(almond_count)
	var container := Node3D.new()
	container.name = "Pickups"
	add_child(container)

	var ground: Array[Vector2i] = []
	var upper: Array[Vector2i] = []
	for cell in maze.get_all_floor_cells():
		if not _blocked_at(cell, 0):
			ground.append(cell)
		if not _blocked_at(cell, 1):
			upper.append(cell)
	ground.shuffle()
	upper.shuffle()

	var used: Array[Vector2i] = []
	var on_upper := _place_pickups(container, upper, used, 1, 2, UPPER_Y)
	var want_almond: int = maxi(almond_count - 1 - on_upper.x, 0)
	var want_batt: int = maxi(battery_count - on_upper.y, 0)
	_place_pickups(container, ground, used, want_almond, want_batt, 0.0)

	# 泡水杏仁水：最大盆中心深水格，浮在水面
	var wet_cell := _submerged_cell()
	var wet_pos := _cell_to_world(wet_cell) + Vector3(0, WATER_Y + 0.08, 0)
	container.add_child(PickupItem.create(PickupItem.Kind.ALMOND, wet_pos))

# 在候选格里按基类间距规则刷 n_almond / n_batt，返回实际刷出的 (杏仁, 电池)
func _place_pickups(container: Node3D, cells: Array[Vector2i], used: Array[Vector2i],
		n_almond: int, n_batt: int, y_off: float) -> Vector2i:
	var a := 0
	var b := 0
	for cell in cells:
		if a >= n_almond and b >= n_batt:
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
		var at := _cell_to_world(cell) + Vector3(0, 0.15 + y_off, 0)
		if a < n_almond:
			container.add_child(PickupItem.create(PickupItem.Kind.ALMOND, at))
			a += 1
		else:
			container.add_child(PickupItem.create(PickupItem.Kind.BATTERY, at))
			b += 1
	return Vector2i(a, b)

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
