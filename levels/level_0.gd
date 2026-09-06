extends Node3D

const FlickeringLight = preload("res://generation/flickering_light.gd")
const SoundGen = preload("res://generation/sound_generator.gd")
const Landmark = preload("res://generation/landmark_breadcrumb.gd")
const MatLib = preload("res://generation/material_lib.gd")
const DustField = preload("res://generation/dust_field.gd")
const Atmosphere = preload("res://generation/atmosphere.gd")

const CELL_SIZE := 4.0
const WALL_HEIGHT := 3.0
const MAZE_SIZE := 11
const LIGHT_RANGE := 10.0
const FLICKER_CHANCE := 0.12
# 薄墙厚度：走廊两侧不再使用 4m 实心块，而是真实隔墙
const WALL_THICK := 0.28
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# 弱引导：沿通往出口的路，每隔 N 格放一个吸引性地标（不用箭头，间隔故意放大以保持“弱”）
const GUIDE_STEP := 7

const MazeGenerator = preload("res://generation/maze_generator.gd")
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
	_create_materials()
	_setup_atmosphere()
	GameState.settings_changed.connect(_on_settings_changed)
	maze = MazeGenerator.new()
	maze.generate(MAZE_SIZE, randi())
	_build_floor_and_ceiling()
	_build_walls()
	_place_lights()
	_add_ambient_fill_light()
	_position_player()
	_place_exit()
	_place_landmarks(spawn_cell)
	_add_dust_field()
	_play_ambient_hum()
	GameState.show_hint("Level 0 - 找到出口")

func _setup_atmosphere() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		Atmosphere.configure(world_env.environment)

func _add_dust_field() -> void:
	var dust := DustField.new()
	dust.name = "DustField"
	var player := get_node_or_null("../Player")
	dust.setup(player, 700, Vector3(14, 1.7, 14))
	dust.visible = GameState.dust_particles
	add_child(dust)

func _on_settings_changed() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		Atmosphere.configure(world_env.environment)
	var dust := get_node_or_null("DustField")
	if dust:
		dust.visible = GameState.dust_particles

func _create_materials() -> void:
	_wall_mat = MatLib.wall_mat()
	_floor_mat = MatLib.floor_mat()
	_ceiling_mat = MatLib.ceiling_mat()
	_pillar_mat = MatLib.pillar_mat()

	_light_panel_mat = StandardMaterial3D.new()
	_light_panel_mat.albedo_color = Color(1, 1, 0.95)
	_light_panel_mat.emission_enabled = true
	_light_panel_mat.emission = Color(1.0, 0.95, 0.8)
	_light_panel_mat.emission_energy_multiplier = 2.0

	_exit_portal_mat = StandardMaterial3D.new()
	_exit_portal_mat.albedo_color = Color(0.0, 0.4, 0.1)
	_exit_portal_mat.emission_enabled = true
	_exit_portal_mat.emission = Color(0.1, 0.9, 0.3)
	_exit_portal_mat.emission_energy_multiplier = 1.5

func _play_ambient_hum() -> void:
	var hum := AudioStreamPlayer.new()
	hum.name = "AmbientHum"
	hum.stream = SoundGen.create_ambient_hum()
	hum.volume_db = -15.0
	hum.autoplay = true
	add_child(hum)
	hum.play()

func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		cell.x * CELL_SIZE + CELL_SIZE * 0.5,
		0.0,
		cell.y * CELL_SIZE + CELL_SIZE * 0.5
	)

func _build_floor_and_ceiling() -> void:
	var total_w: float = maze.width * CELL_SIZE
	var total_d: float = maze.height * CELL_SIZE

	var floor_node := CSGBox3D.new()
	floor_node.name = "Floor"
	floor_node.use_collision = true
	floor_node.size = Vector3(total_w, 0.2, total_d)
	floor_node.position = Vector3(total_w * 0.5, -0.1, total_d * 0.5)
	floor_node.material = _floor_mat
	add_child(floor_node)

	var ceiling_node := CSGBox3D.new()
	ceiling_node.name = "Ceiling"
	ceiling_node.use_collision = true
	ceiling_node.size = Vector3(total_w, 0.2, total_d)
	ceiling_node.position = Vector3(total_w * 0.5, WALL_HEIGHT + 0.1, total_d * 0.5)
	ceiling_node.material = _ceiling_mat
	add_child(ceiling_node)

func _build_walls() -> void:
	var wall_container := Node3D.new()
	wall_container.name = "Walls"
	add_child(wall_container)
	_build_thin_walls(wall_container)
	_build_pillars(wall_container)

# 薄墙：不再逐格堆 4m 实心块，而是收集每个 WALL 格面向 FLOOR 的边，
# 将同一条线上连续的边合并成整段隔墙，转角处端头外扩半厚以闭合缝隙。
# 开阔区柱体（pillar_cells）除外——它们是四面通透的独立柱子，单独处理。
func _build_thin_walls(container: Node3D) -> void:
	# h_faces[网格线][方向符号] -> { 格子坐标: true }（水平边，沿 X 延伸）；v_faces 同理
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
			_add_merged_wall_runs(container, h_faces[line][sgn], line, sgn, true, _wall_mat)
	for line in v_faces:
		for sgn in v_faces[line]:
			_add_merged_wall_runs(container, v_faces[line][sgn], line, sgn, false, _wall_mat)

# 开阔区柱体：在每个柱体格中心放一根居中的小方柱（带倒角感）
func _build_pillars(container: Node3D) -> void:
	for idx in maze.pillar_cells:
		var x: int = idx % maze.width
		var y: int = int(idx / maze.width)
		var pillar := CSGBox3D.new()
		pillar.use_collision = true
		pillar.size = Vector3(1.2, WALL_HEIGHT + 0.2, 1.2)
		pillar.position = Vector3(
			x * CELL_SIZE + CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.5,
			y * CELL_SIZE + CELL_SIZE * 0.5
		)
		pillar.material = _pillar_mat
		container.add_child(pillar)

# 把一条线上连续格子的边合并成长墙段。horizontal=true 时沿 X 延伸。
func _add_merged_wall_runs(container: Node3D, cells: Dictionary, line: int, sgn: int, horizontal: bool, mat: StandardMaterial3D) -> void:
	var coords: Array = cells.keys()
	coords.sort()
	var run_start: int = coords[0]
	var run_end: int = coords[0]
	for i in range(1, coords.size() + 1):
		if i < coords.size() and coords[i] == run_end + 1:
			run_end = coords[i]
			continue
		_emit_wall(container, mat, horizontal, line, sgn, run_start, run_end)
		if i < coords.size():
			run_start = coords[i]
			run_end = coords[i]

func _emit_wall(container: Node3D, mat: StandardMaterial3D, horizontal: bool, line: int, sgn: int, a: int, b: int) -> void:
	var span_cells: float = float(b - a + 1) * CELL_SIZE
	var wall := CSGBox3D.new()
	wall.use_collision = true
	# 端头各外扩半厚，保证与垂直方向墙段在转角处重叠闭合
	var length: float = span_cells + WALL_THICK
	if horizontal:
		wall.size = Vector3(length, WALL_HEIGHT + 0.2, WALL_THICK)
		var cx: float = (float(a) + float(b - a + 1) * 0.5) * CELL_SIZE
		var cz: float = float(line) * CELL_SIZE - float(sgn) * WALL_THICK * 0.5
		wall.position = Vector3(cx, WALL_HEIGHT * 0.5, cz)
	else:
		wall.size = Vector3(WALL_THICK, WALL_HEIGHT + 0.2, length)
		var cz2: float = (float(a) + float(b - a + 1) * 0.5) * CELL_SIZE
		var cx2: float = float(line) * CELL_SIZE - float(sgn) * WALL_THICK * 0.5
		wall.position = Vector3(cx2, WALL_HEIGHT * 0.5, cz2)
	wall.material = mat
	container.add_child(wall)

func _place_lights() -> void:
	var light_container := Node3D.new()
	light_container.name = "Lights"
	add_child(light_container)

	var floor_cells: Array[Vector2i] = maze.get_all_floor_cells()
	var covered := {}
	var range_in_cells: float = LIGHT_RANGE * 0.8 / CELL_SIZE
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
		var is_flicker: bool = randf() < FLICKER_CHANCE

		var light: OmniLight3D
		if is_flicker:
			light = FlickeringLight.new()
		else:
			light = OmniLight3D.new()
		light.position = world_pos + Vector3(0, WALL_HEIGHT - 0.4, 0)
		light.light_color = Color(1.0, 0.95, 0.8)
		light.light_energy = randf_range(1.0, 1.5)
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 1.5
		light.shadow_enabled = true
		Atmosphere.set_fog_energy(light, 0.8)
		light_container.add_child(light)

		var panel := CSGBox3D.new()
		panel.size = Vector3(1.8, 0.08, 0.6)
		panel.position = Vector3(0, 0.25, 0)
		panel.material = _light_panel_mat
		panel.use_collision = false
		light.add_child(panel)

func _add_ambient_fill_light() -> void:
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "AmbientFill"
	fill_light.light_color = Color(0.35, 0.32, 0.22)
	fill_light.light_energy = 0.18
	fill_light.rotation_degrees = Vector3(-55, 25, 0)
	fill_light.shadow_enabled = false
	Atmosphere.set_fog_energy(fill_light, 0.0)  # 补光不参与体积雾，避免整体发灰
	add_child(fill_light)

func _place_exit() -> void:
	# 出口选在距玩家最远的可贴门格，最大化探索路程
	exit_cell = maze.find_farthest_floor(spawn_cell)
	var world_pos := _cell_to_world(exit_cell)

	# 传送门贴墙放置：找出口格相邻的墙格作为"背景墙"
	var mount_dir := _exit_door_dir()

	exit_area = Area3D.new()
	exit_area.name = "ExitDoor"
	var offset := Vector3(mount_dir.x, 0, mount_dir.y) * (CELL_SIZE * 0.5 - 0.2)
	exit_area.position = world_pos + offset + Vector3(0, WALL_HEIGHT * 0.5, 0)
	# 让传送门 -Z 朝向走廊内侧（玩家来向）
	if mount_dir != Vector2i.ZERO:
		exit_area.rotation.y = atan2(float(mount_dir.x), float(mount_dir.y))

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL_SIZE * 0.8, WALL_HEIGHT, CELL_SIZE * 0.8)
	col_shape.shape = box
	exit_area.add_child(col_shape)

	var portal := CSGBox3D.new()
	portal.size = Vector3(CELL_SIZE * 0.6, WALL_HEIGHT * 0.9, 0.15)
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
	# 门板在 +Z（贴墙侧），EXIT 标签放 -Z（走廊侧），正面朝 -Z
	label.position = Vector3(0, WALL_HEIGHT * 0.35, -0.3)
	exit_area.add_child(label)

	add_child(exit_area)
	exit_area.body_entered.connect(_on_exit_door_entered)
	# 出口确定后构建 BFS 距离场，地标引导据此沿路放置
	maze.compute_distance_field(exit_cell)

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

# 沿通往出口的路放置吸引性地标（黑碑/门框/信标）。
# 时机：① 三岔/四岔路口（最容易犹豫的地方，必放）② 直行段每 GUIDE_STEP 格兜底。
# 仍保持"弱"：路口最少隔 3 格、直行大间隔、随机侧偏，不形成明显规律。
func _place_landmarks(from_cell: Vector2i) -> void:
	var container := Node3D.new()
	container.name = "Landmarks"
	add_child(container)

	var path := _trace_path(from_cell)
	if path.size() < 3:
		return
	var kind := randi() % 3
	var since := GUIDE_STEP  # 从起点就开始计时，首个地标在 GUIDE_STEP 格后
	for i in path.size():
		# 起点附近与出口前一格不放（避开太显眼 / 不抢传送门的戏）
		if i < 2 or i > path.size() - 2:
			continue
		var cell: Vector2i = path[i]
		var is_junction := _opening_count(cell) >= 3
		var due := since >= GUIDE_STEP or (is_junction and since >= 3)
		if not due:
			since += 1
			continue
		since = 0
		var nxt: Vector2i = path[mini(i + 1, path.size() - 1)]
		var facing: Vector2i = nxt - cell
		if facing == Vector2i.ZERO:
			facing = Vector2i(0, -1)
		var marker := Landmark.create(kind, facing)
		# 横向轻微偏移 + 随机角度，弱化到"像是环境本来就有"
		var side := Vector2(facing.y, facing.x) * randf_range(0.2, 0.8)
		if randf() < 0.5:
			side = -side
		marker.position = _cell_to_world(cell) + Vector3(side.x, 0, side.y)
		container.add_child(marker)
		kind = (kind + 1) % 3

# 统计某格的开放方向数（≥3 即三岔/四岔路口）
func _opening_count(cell: Vector2i) -> int:
	var n := 0
	for dir in DIRS4:
		if maze.is_floor(cell.x + dir.x, cell.y + dir.y):
			n += 1
	return n

# 出口格内指向门所在墙的方向
func _exit_door_dir() -> Vector2i:
	for dir in DIRS4:
		if maze.is_wall(exit_cell.x + dir.x, exit_cell.y + dir.y):
			return dir
	return Vector2i.ZERO

func _position_player() -> void:
	spawn_cell = maze.find_nearest_floor(Vector2i(1, 1))
	var spawn_pos := _cell_to_world(spawn_cell)

	var player := get_node_or_null("../Player")
	if player:
		player.global_position = spawn_pos + Vector3(0, 1.0, 0)
		player.rotation.y = atan2(-1, -1) + PI * 0.25

func _on_exit_door_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		GameState.show_hint("你找到了出口...")
		exit_area.set_deferred("monitoring", false)
		await get_tree().create_timer(2.0).timeout
		get_tree().reload_current_scene()
