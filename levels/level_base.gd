extends Node3D
# 关卡基类：封装"迷宫类关卡"的完整装配流程（生成→墙体→灯光→出口→地标→氛围）。
# 子类通过覆盖 var 配置改变观感，通过钩子定制行为：
#   _generate_maze(m)  生成网格（默认 MazeGenerator；狂奔关手填、泳室换生成器）
#   _create_materials() 材质（默认 = Level 0 黄色壁纸套装）
#   _emit_wall(...)    每段合并墙（Level 2 覆盖此钩子沿墙挂管线）
#   _place_lights()    布灯（狂奔关覆盖为侧壁红灯）
#   _custom_build()    附加装修（仓库货箱、泳室水面），调用时机在出口/出生点确定之后

const FlickeringLight = preload("res://generation/flickering_light.gd")
const SoundGen = preload("res://generation/sound_generator.gd")
const Landmark = preload("res://generation/landmark_breadcrumb.gd")
const MatLib = preload("res://generation/material_lib.gd")
const DustField = preload("res://generation/dust_field.gd")
const Atmosphere = preload("res://generation/atmosphere.gd")
const MazeGenerator = preload("res://generation/maze_generator.gd")
const PickupItem = preload("res://generation/pickup_item.gd")

const WALL_THICK := 0.28
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# 弱引导：沿通往出口的路，每隔 N 格放一个吸引性地标
var guide_step := 5

# —— 子类配置（var，子类覆盖默认值）——
var cell_size := 4.0
var wall_height := 3.0
var maze_size := 11
var light_range := 10.0
var light_color := Color(1.0, 0.95, 0.8)
var light_energy_range := Vector2(1.0, 1.5)
var light_panel_size := Vector2(1.8, 0.6)
var flicker_chance := 0.12
var fill_light_color := Color(0.35, 0.32, 0.22)
var fill_light_energy := 0.18
var volumetric_fog_density := 0.02
var dust_count := 700
var dust_extents := Vector3(14, 1.7, 14)
var hum_volume_db := -15.0
var hum_pitch := 1.0
var level_title := "Level 0"
var hint_text := "找到出口"
# 拾取物：本关杏仁水需求（集齐才能触发出口）与电池刷点数
var almond_count := 3
var battery_count := 4

var maze
var exit_area: Area3D
var exit_cell: Vector2i
var spawn_cell: Vector2i

var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceiling_mat: StandardMaterial3D
var _pillar_mat: StandardMaterial3D
var _light_panel_mat: StandardMaterial3D
var _exit_portal_mat: StandardMaterial3D

func _ready() -> void:
	# 布局复现：用本关持久化种子重置全局 RNG → 继续游戏时与上次一模一样的布局
	seed(GameState.get_level_seed(GameState.current_level))
	_create_materials()
	_setup_atmosphere()
	GameState.settings_changed.connect(_on_settings_changed)
	maze = MazeGenerator.new()
	_generate_maze(maze)
	_build_floor_and_ceiling()
	_build_walls()
	_place_lights()
	_add_ambient_fill_light()
	_position_player()
	_place_exit()
	_place_landmarks(spawn_cell)
	_spawn_pickups()
	_add_dust_field()
	_custom_build()
	_play_ambient_hum()
	GameState.show_hint("%s - %s" % [level_title, hint_text])

# ── 钩子（子类按需覆盖）─────────────────────────────────────

func _generate_maze(m) -> void:
	m.generate(maze_size, randi())

func _create_materials() -> void:
	_wall_mat = MatLib.wall_mat()
	_floor_mat = MatLib.floor_mat()
	_ceiling_mat = MatLib.ceiling_mat()
	_pillar_mat = MatLib.pillar_mat()
	_light_panel_mat = _make_light_panel_mat(Color(1, 1, 0.95), Color(1.0, 0.95, 0.8))
	_exit_portal_mat = _make_exit_mat()

func _custom_build() -> void:
	pass

# ── 氛围与音频 ─────────────────────────────────────────────

func _setup_atmosphere() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		Atmosphere.configure(world_env.environment, volumetric_fog_density)

func _on_settings_changed() -> void:
	_setup_atmosphere()
	var dust := get_node_or_null("DustField")
	if dust:
		dust.visible = GameState.dust_particles

func _add_dust_field() -> void:
	if dust_count <= 0:
		return
	var dust := DustField.new()
	dust.name = "DustField"
	dust.setup(get_tree().get_first_node_in_group("player") as Node3D, dust_count, dust_extents)
	dust.visible = GameState.dust_particles
	add_child(dust)

func _play_ambient_hum() -> void:
	var hum := AudioStreamPlayer.new()
	hum.name = "AmbientHum"
	hum.stream = SoundGen.create_ambient_hum()
	hum.volume_db = hum_volume_db
	hum.pitch_scale = hum_pitch
	hum.autoplay = true
	add_child(hum)
	hum.play()

# ── 几何装配 ────────────────────────────────────────────────

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		cell.x * cell_size + cell_size * 0.5,
		0.0,
		cell.y * cell_size + cell_size * 0.5
	)

func _build_floor_and_ceiling() -> void:
	_build_floor()
	_build_ceiling()

# 地板（Poolrooms 覆盖为厚板 + CSG 减法凿出下沉泳池）
func _build_floor() -> void:
	var total_w: float = maze.width * cell_size
	var total_d: float = maze.height * cell_size

	var floor_node := CSGBox3D.new()
	floor_node.name = "Floor"
	floor_node.use_collision = true
	floor_node.size = Vector3(total_w, 0.2, total_d)
	floor_node.position = Vector3(total_w * 0.5, -0.1, total_d * 0.5)
	floor_node.material = _floor_mat
	add_child(floor_node)

func _build_ceiling() -> void:
	var total_w: float = maze.width * cell_size
	var total_d: float = maze.height * cell_size

	var ceiling_node := CSGBox3D.new()
	ceiling_node.name = "Ceiling"
	ceiling_node.use_collision = true
	ceiling_node.size = Vector3(total_w, 0.2, total_d)
	ceiling_node.position = Vector3(total_w * 0.5, wall_height + 0.1, total_d * 0.5)
	ceiling_node.material = _ceiling_mat
	add_child(ceiling_node)

func _build_walls() -> void:
	var wall_container := Node3D.new()
	wall_container.name = "Walls"
	add_child(wall_container)
	_build_thin_walls(wall_container)
	_build_pillars(wall_container)

# 薄墙：收集每个 WALL 格面向 FLOOR 的边，同一条线上合并成整段隔墙。
# 开阔区柱体（pillar_cells）除外——四面通透的独立柱子，单独处理。
func _build_thin_walls(container: Node3D) -> void:
	var h_faces := {}
	var v_faces := {}
	for y in maze.height:
		for x in maze.width:
			if not maze.is_wall(x, y):
				continue
			if maze.pillar_cells.has(maze._index(x, y)):
				continue
			for dir in DIRS4:
				var nx: int = x + dir.x
				var ny: int = y + dir.y
				if not maze.is_floor(nx, ny):
					continue
				if dir.y != 0:
					var line: int = y + (1 if dir.y > 0 else 0)
					if not h_faces.has(line):
						h_faces[line] = {}
					if not h_faces[line].has(dir.y):
						h_faces[line][dir.y] = {}
					h_faces[line][dir.y][x] = true
				else:
					var vline: int = x + (1 if dir.x > 0 else 0)
					if not v_faces.has(vline):
						v_faces[vline] = {}
					if not v_faces[vline].has(dir.x):
						v_faces[vline][dir.x] = {}
					v_faces[vline][dir.x][y] = true

	for line in h_faces:
		for sgn in h_faces[line]:
			_add_merged_wall_runs(container, h_faces[line][sgn], line, sgn, true)
	for line in v_faces:
		for sgn in v_faces[line]:
			_add_merged_wall_runs(container, v_faces[line][sgn], line, sgn, false)

# 开阔区柱体：每个柱体格中心放一根小方柱
func _build_pillars(container: Node3D) -> void:
	for idx in maze.pillar_cells:
		var x: int = idx % maze.width
		var y: int = int(idx / maze.width)
		var pillar := CSGBox3D.new()
		pillar.use_collision = true
		pillar.size = Vector3(1.2, wall_height + 0.2, 1.2)
		pillar.position = Vector3(
			x * cell_size + cell_size * 0.5,
			wall_height * 0.5,
			y * cell_size + cell_size * 0.5
		)
		pillar.material = _pillar_mat
		container.add_child(pillar)

# 把一条线上连续格子的边合并成长墙段。horizontal=true 时沿 X 延伸。
func _add_merged_wall_runs(container: Node3D, cells: Dictionary, line: int, sgn: int, horizontal: bool) -> void:
	var coords: Array = cells.keys()
	coords.sort()
	var run_start: int = coords[0]
	var run_end: int = coords[0]
	for i in range(1, coords.size() + 1):
		if i < coords.size() and coords[i] == run_end + 1:
			run_end = coords[i]
			continue
		_emit_wall(container, _wall_mat, horizontal, line, sgn, run_start, run_end)
		if i < coords.size():
			run_start = coords[i]
			run_end = coords[i]

# 生成一段墙（Level 2 覆盖此钩子在墙面上加管线）。返回墙节点：子类可往上面
# 挂 CSG SUBTRACT 子节点（如泳室的拱券/黑洞口要在墙上凿洞）。
func _emit_wall(container: Node3D, mat: StandardMaterial3D, horizontal: bool, line: int, sgn: int, a: int, b: int) -> CSGBox3D:
	var span_cells: float = float(b - a + 1) * cell_size
	var wall := CSGBox3D.new()
	wall.use_collision = true
	# 端头各外扩半厚，保证与垂直方向墙段在转角处重叠闭合
	var length: float = span_cells + WALL_THICK
	if horizontal:
		wall.size = Vector3(length, wall_height + 0.2, WALL_THICK)
		var cx: float = (float(a) + float(b - a + 1) * 0.5) * cell_size
		var cz: float = float(line) * cell_size - float(sgn) * WALL_THICK * 0.5
		wall.position = Vector3(cx, wall_height * 0.5, cz)
	else:
		wall.size = Vector3(WALL_THICK, wall_height + 0.2, length)
		var cz2: float = (float(a) + float(b - a + 1) * 0.5) * cell_size
		var cx2: float = float(line) * cell_size - float(sgn) * WALL_THICK * 0.5
		wall.position = Vector3(cx2, wall_height * 0.5, cz2)
	wall.material = mat
	container.add_child(wall)
	# 遮挡剔除（全关卡基础优化）：墙是天然遮板，长廊深处视线被挡后，
	# 身后的装饰/灯/管线实例直接剔除——治"走远就掉帧/卡死"
	var occ := OccluderInstance3D.new()
	var occ_box := BoxOccluder3D.new()
	occ_box.size = wall.size + (Vector3(0.12, 0.0, 0.04) if horizontal else Vector3(0.04, 0.0, 0.12))
	occ.occluder = occ_box
	occ.position = wall.position
	container.add_child(occ)
	return wall

# ── 灯光 ───────────────────────────────────────────────────

func _place_lights() -> void:
	var light_container := Node3D.new()
	light_container.name = "Lights"
	add_child(light_container)

	var floor_cells: Array[Vector2i] = maze.get_all_floor_cells()
	var covered := {}
	var range_in_cells: float = light_range * 0.8 / cell_size
	var light_positions: Array[Vector2i] = []

	for cell in floor_cells:
		if covered.has(cell):
			continue
		light_positions.append(cell)
		for other in floor_cells:
			if covered.has(other):
				continue
			var dist: float = Vector2(other.x - cell.x, other.y - cell.y).length()
			if dist <= range_in_cells:
				covered[other] = true

	for cell_pos in light_positions:
		var world_pos := _cell_to_world(cell_pos)
		var is_flicker: bool = randf() < flicker_chance

		var light: OmniLight3D
		if is_flicker:
			light = FlickeringLight.new()
		else:
			light = OmniLight3D.new()
		light.position = world_pos + Vector3(0, wall_height - 0.4, 0)
		light.light_color = light_color
		light.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
		light.omni_range = light_range
		light.omni_attenuation = 1.5
		light.shadow_enabled = true
		Atmosphere.set_fog_energy(light, 0.8)
		light_container.add_child(light)

		var panel := CSGBox3D.new()
		panel.size = Vector3(light_panel_size.x, 0.08, light_panel_size.y)
		panel.position = Vector3(0, 0.25, 0)
		panel.material = _light_panel_mat
		panel.use_collision = false
		light.add_child(panel)

func _add_ambient_fill_light() -> void:
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "AmbientFill"
	fill_light.light_color = fill_light_color
	fill_light.light_energy = fill_light_energy
	fill_light.rotation_degrees = Vector3(-55, 25, 0)
	fill_light.shadow_enabled = false
	Atmosphere.set_fog_energy(fill_light, 0.0)
	add_child(fill_light)

# ── 拾取物：杏仁水（E 拾取）/ 电池（自动）──────────────────

# 随机刷点：杏仁水 3 瓶 + 电池若干。
# 约束：离出生点 ≥3 格、离出口 ≥2 格、互相 ≥4 格（别扎堆）、避开阻挡格（泳池/柱）。
func _spawn_pickups() -> void:
	GameState.reset_almond_progress(almond_count)
	if almond_count <= 0 and battery_count <= 0:
		return
	var container := Node3D.new()
	container.name = "Pickups"
	add_child(container)

	var floors: Array[Vector2i] = maze.get_all_floor_cells()
	floors.shuffle()
	var used: Array[Vector2i] = []
	var almond_placed := 0
	var battery_placed := 0
	for cell in floors:
		if almond_placed >= almond_count and battery_placed >= battery_count:
			break
		if cell == spawn_cell or cell == exit_cell or _pickup_blocked(cell):
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
		var at := _cell_to_world(cell) + Vector3(0, 0.15 + _landmark_y_offset(cell), 0)
		if almond_placed < almond_count:
			container.add_child(PickupItem.create(PickupItem.Kind.ALMOND, at))
			almond_placed += 1
		else:
			container.add_child(PickupItem.create(PickupItem.Kind.BATTERY, at))
			battery_placed += 1
	# 地板格太少兜底：放宽间距塞完剩余杏仁水（需求优先于电池）
	if almond_placed < almond_count:
		for cell in floors:
			if almond_placed >= almond_count:
				break
			if cell == spawn_cell or cell == exit_cell or used.has(cell):
				continue
			used.append(cell)
			var at := _cell_to_world(cell) + Vector3(0, 0.15 + _landmark_y_offset(cell), 0)
			container.add_child(PickupItem.create(PickupItem.Kind.ALMOND, at))
			almond_placed += 1

# ── 出口 / 出生点 ──────────────────────────────────────────

func _place_exit() -> void:
	exit_cell = _pick_exit_cell()
	var world_pos := _cell_to_world(exit_cell)

	var mount_dir := _exit_door_dir()

	exit_area = Area3D.new()
	exit_area.name = "ExitDoor"
	var offset := Vector3(mount_dir.x, 0, mount_dir.y) * (cell_size * 0.5 - 0.2)
	exit_area.position = world_pos + offset + Vector3(0, wall_height * 0.5, 0)
	if mount_dir != Vector2i.ZERO:
		exit_area.rotation.y = atan2(float(mount_dir.x), float(mount_dir.y))

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(cell_size * 0.8, wall_height, cell_size * 0.8)
	col_shape.shape = box
	exit_area.add_child(col_shape)

	var portal := CSGBox3D.new()
	portal.size = Vector3(cell_size * 0.6, wall_height * 0.9, 0.15)
	portal.position = Vector3(0, 0, 0.1)
	portal.material = _exit_portal_mat
	portal.use_collision = false
	exit_area.add_child(portal)

	var label := Label3D.new()
	label.text = "EXIT"
	label.font_size = 96
	label.pixel_size = 0.004
	label.double_sided = true
	label.modulate = Color(0.2, 1.0, 0.3)
	label.outline_size = 12
	label.position = Vector3(0, wall_height * 0.35, -0.3)
	exit_area.add_child(label)

	add_child(exit_area)
	exit_area.body_entered.connect(_on_exit_door_entered)
	maze.compute_distance_field(exit_cell)

func _exit_door_dir() -> Vector2i:
	for dir in DIRS4:
		if maze.is_wall(exit_cell.x + dir.x, exit_cell.y + dir.y):
			return dir
	return Vector2i.ZERO

func _position_player() -> void:
	spawn_cell = maze.find_nearest_floor(Vector2i(1, 1))
	var spawn_pos := _cell_to_world(spawn_cell)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = spawn_pos + Vector3(0, 1.0, 0)
		player.rotation.y = -PI * 0.5  # 面向 +X，从出生角看向迷宫内部

func _on_exit_door_entered(body: Node3D) -> void:
	# 只认玩家：出口检测盒与墙体 StaticBody3D 重叠，早返回防止任何杂物触发重载
	if not body is CharacterBody3D:
		return
	# 闸门：杏仁水没集齐，出口不放行（提示后直接返回，等待补齐）
	if GameState.almond_water < GameState.almond_required:
		var missing: int = GameState.almond_required - GameState.almond_water
		GameState.show_hint("出口纹丝不动…似乎还差 %d 瓶杏仁水" % missing)
		return
	GameState.show_hint("你找到了出口...")
	exit_area.set_deferred("monitoring", false)
	await get_tree().create_timer(2.0).timeout
	# timer 暂停时照走：若玩家在 2 秒内按了 Esc，reload 会带着 paused=true 冻住新场景
	get_tree().paused = false
	if GameState.advance_level():
		Loader.go_to("res://main/main.tscn")
	else:
		Loader.go_to("res://main/main_menu.tscn")

# ── 弱引导地标 ─────────────────────────────────────────────

# 追踪从 from_cell 沿梯度最短路到出口的格序列
func _trace_path(from_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cell := from_cell
	var guard := 0
	while guard < 4096:
		guard += 1
		path.append(cell)
		var dir: Vector2i = maze.get_guidance_dir(cell)
		if dir == Vector2i.ZERO:
			break
		cell += dir
	return path

# 沿通往出口的路放置吸引性地标（黑碑/门框/信标，各类多状态）。
# 时机：① 三岔/四岔路口 ② 直行段每 guide_step 格兜底。
func _place_landmarks(from_cell: Vector2i) -> void:
	var container := Node3D.new()
	container.name = "Landmarks"
	add_child(container)

	var path := _trace_path(from_cell)
	if path.size() < 3:
		return
	var kind := randi() % 3
	var since := guide_step
	for i in path.size():
		if i < 2 or i > path.size() - 2:
			continue
		var cell: Vector2i = path[i]
		if _landmark_blocked(cell):
			since += 1
			continue
		var is_junction := _opening_count(cell) >= 3
		var due := since >= guide_step or (is_junction and since >= 2)
		if not due:
			since += 1
			continue
		since = 0
		var nxt: Vector2i = path[mini(i + 1, path.size() - 1)]
		var facing: Vector2i = nxt - cell
		if facing == Vector2i.ZERO:
			facing = Vector2i(0, -1)
		# 贴墙款自带墙根偏移，地面款自带横向偏移；均以格子中心为基准叠加
		var marker := Landmark.create(kind, facing, _wall_dirs_of(cell), cell_size * 0.5 - 0.02)
		marker.position = _cell_to_world(cell) + marker.position + Vector3(0, _landmark_y_offset(cell), 0)
		container.add_child(marker)
		kind = (kind + 1) % 3

# 钩子：地标基座的 Y 偏移，按格查层（泳室：下层 FLOOR_TOP、上层厅 +UPPER_RAISE）
func _landmark_y_offset(_cell: Vector2i) -> float:
	return 0.0

# 钩子：出口选格（泳室覆盖：上层厅台地上不去会 3D 死局，强制选下层格）
func _pick_exit_cell() -> Vector2i:
	return maze.find_farthest_floor(spawn_cell)

# 钩子：该格是否禁止放地标（如泳室泳池格——地标会悬在水面上）
func _landmark_blocked(_cell: Vector2i) -> bool:
	return false

# 钩子：该格是否禁止放拾取物（默认与地标一致；泳室放开上层厅台地）
func _pickup_blocked(cell: Vector2i) -> bool:
	return _landmark_blocked(cell)

# 某格邻接的可贴墙方向（开阔区柱体不算——柱面不在格线上，贴上去会悬空）
func _wall_dirs_of(cell: Vector2i) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	for dir in DIRS4:
		var nx: int = cell.x + dir.x
		var ny: int = cell.y + dir.y
		if maze.is_wall(nx, ny) and not maze.pillar_cells.has(maze._index(nx, ny)):
			dirs.append(dir)
	return dirs

# 统计某格的开放方向数（≥3 即三岔/四岔路口）
func _opening_count(cell: Vector2i) -> int:
	var n := 0
	for dir in DIRS4:
		if maze.is_floor(cell.x + dir.x, cell.y + dir.y):
			n += 1
	return n

# ── 通用小材质 ─────────────────────────────────────────────

func _make_light_panel_mat(albedo: Color, emission: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = 2.0
	return m

func _make_exit_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.0, 0.4, 0.1)
	m.emission_enabled = true
	m.emission = Color(0.1, 0.9, 0.3)
	m.emission_energy_multiplier = 1.5
	return m
