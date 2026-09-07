extends "res://levels/level_base.gd"
# Level 0：经典黄色迷宫重做（见 docs/level0_design.md）。
# 房间簇 + 方形门洞（Level0Generator）；掉格吊顶 + 嵌入式灯板三态
# （常亮/闪烁/熄灭）；踢脚线；mono-yellow 三色带；墙皮撕裂露水泥；
# 靠墙装饰梯子；黑暗洞口出口（替换绿光 EXIT 面板）。

const Level0Generator = preload("res://levels/level0_generator.gd")

var _zone_mats: Array[StandardMaterial3D] = []
var _dead_panel_mat: StandardMaterial3D
var _cement_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _baseboard_mat: StandardMaterial3D
var _switch_mat: StandardMaterial3D
var _dark_exit_mat: StandardMaterial3D
var _exit_glow_mat: StandardMaterial3D

func _init() -> void:
	# 材质/雾/音效仍用基类默认（就是经典黄墙那套），只覆盖布局相关参数
	maze_size = 12                        # 25×25 格房间簇（装得下 8~14 个房间）
	light_range = 8.5                     # 房间多，灯更碎
	light_panel_size = Vector2(0.6, 1.2)  # 2×4 英尺格栅灯
	flicker_chance = 0.30

func _generate_maze(m) -> void:
	var g := Level0Generator.new()
	g.generate(maze_size, randi())
	maze = g

func _create_materials() -> void:
	_zone_mats = MatLib.wall_zone_mats()
	_floor_mat = MatLib.floor_mat()
	_ceiling_mat = MatLib.ceiling_grid_mat()
	_pillar_mat = MatLib.pillar_mat()
	_light_panel_mat = _make_light_panel_mat(Color(1, 1, 0.95), Color(1.0, 0.97, 0.88))
	_exit_portal_mat = _make_exit_mat()
	_dead_panel_mat = StandardMaterial3D.new()
	_dead_panel_mat.albedo_color = Color(0.55, 0.54, 0.50)
	_dead_panel_mat.roughness = 0.7
	# 撕裂破洞的水泥基底：复用已有 Concrete030，压暗
	_cement_mat = MatLib.make_mat("res://assets/textures/Concrete030/", "Concrete030_1K-JPG",
		0.8, Color(0.38, 0.37, 0.35), Color(0.16, 0.16, 0.15), Color(0.34, 0.34, 0.33), 0.08, 0.3)
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.55, 0.42, 0.26)
	_wood_mat.roughness = 0.85
	_baseboard_mat = StandardMaterial3D.new()
	_baseboard_mat.albedo_color = Color(0.35, 0.30, 0.20)
	_baseboard_mat.roughness = 0.8
	_switch_mat = StandardMaterial3D.new()
	_switch_mat.albedo_color = Color(0.92, 0.91, 0.88)
	_switch_mat.roughness = 0.4
	_dark_exit_mat = StandardMaterial3D.new()
	_dark_exit_mat.albedo_color = Color(0.02, 0.02, 0.02)
	_dark_exit_mat.roughness = 1.0
	_exit_glow_mat = StandardMaterial3D.new()
	_exit_glow_mat.albedo_color = Color(0.25, 0.22, 0.12)
	_exit_glow_mat.emission_enabled = true
	_exit_glow_mat.emission = Color(0.45, 0.40, 0.22)
	_exit_glow_mat.emission_energy_multiplier = 0.3

# ── 墙面：色区 tint + 踢脚线 + 撕裂破洞 + 开关插座 ──────────

# 覆盖：按墙段所在色区选壁纸 tint（mono-yellow 分区悄悄变调）
func _emit_wall(container: Node3D, mat: StandardMaterial3D, horizontal: bool,
		line: int, sgn: int, a: int, b: int) -> CSGBox3D:
	var zone := int(floor(((a + b) * 0.5) / 7.0 + float(line) / 7.0)) % 3
	var wall := super._emit_wall(container, _zone_mats[zone], horizontal, line, sgn, a, b)
	_decorate_wall_face(container, zone, horizontal, line, sgn, a, b)
	return wall

func _decorate_wall_face(container: Node3D, zone: int, horizontal: bool,
		line: int, sgn: int, a: int, b: int) -> void:
	var span := float(b - a + 1) * cell_size
	var along := (float(a) + float(b + 1)) * 0.5 * cell_size
	var wall_c := float(line) * cell_size - float(sgn) * WALL_THICK * 0.5
	var wall_face := wall_c + float(sgn) * WALL_THICK * 0.5  # 朝地板侧的墙面精确位置
	var s := float(sgn)

	# 踢脚线：0.14m 高深色带，两端各缩 0.02m 防转角 z-fight
	var bb := CSGBox3D.new()
	bb.name = "Baseboard"
	var bb_len := span - 0.04
	if horizontal:
		bb.size = Vector3(bb_len, 0.14, 0.06)
		bb.position = Vector3(along, 0.07, wall_face + s * 0.033)
	else:
		bb.size = Vector3(0.06, 0.14, bb_len)
		bb.position = Vector3(wall_face + s * 0.033, 0.07, along)
	bb.material = _baseboard_mat
	bb.use_collision = false
	container.add_child(bb)

	# 撕裂破洞（≥3 格长墙 8%）：水泥基底 + 翘起壁纸条
	if span >= cell_size * 3.0 and randf() < 0.08:
		var t := randf_range(0.15, 0.85)
		var px := along - span * 0.5 + span * t
		var hy := clampf(randf_range(1.4, 1.9), 0.65, wall_height - 0.65)
		var patch := CSGBox3D.new()
		patch.name = "TearPatch"
		patch.size = Vector3(1.2, 1.0, 0.05) if horizontal else Vector3(0.05, 1.0, 1.2)
		patch.position = Vector3(px, hy, wall_face + s * 0.028) if horizontal \
				else Vector3(wall_face + s * 0.028, hy, px)
		patch.material = _cement_mat
		patch.use_collision = false
		container.add_child(patch)
		var strips := randi_range(3, 5)
		for _k in strips:
			var strip := CSGBox3D.new()
			strip.name = "PeelStrip"
			strip.size = Vector3(randf_range(0.12, 0.22), randf_range(0.5, 0.9), 0.02)
			var ox := randf_range(-0.55, 0.55)
			var oy := randf_range(-0.45, 0.45)
			if horizontal:
				strip.position = Vector3(px + ox, hy + oy, wall_face + s * 0.05)
				strip.rotation = Vector3(s * randf_range(0.25, 0.5), randf_range(-0.6, 0.6), 0)
			else:
				strip.position = Vector3(wall_face + s * 0.05, hy + oy, px + ox)
				strip.rotation = Vector3(0, randf_range(-0.6, 0.6), -s * randf_range(0.25, 0.5))
			strip.material = _zone_mats[zone]
			strip.use_collision = false
			container.add_child(strip)

	# 墙面开关（≥2 格墙 30%）
	if span >= cell_size * 2.0 and randf() < 0.3:
		var sw := CSGBox3D.new()
		sw.name = "WallSwitch"
		var st := randf_range(0.1, 0.9)
		var sx := along - span * 0.5 + span * st
		sw.size = Vector3(0.09, 0.13, 0.03)
		sw.position = Vector3(sx, 1.1, wall_face + s * 0.017) if horizontal \
				else Vector3(wall_face + s * 0.017, 1.1, sx)
		sw.material = _switch_mat
		sw.use_collision = false
		container.add_child(sw)

# ── 灯光：嵌入格栅的灯板三态（常亮/闪烁/熄灭）───────────────

func _place_lights() -> void:
	var light_container := Node3D.new()
	light_container.name = "Lights"
	add_child(light_container)

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

	var panel_y := wall_height - 0.05  # 嵌平吊顶，不再悬吊
	for cell_pos in positions:
		var p := _cell_to_world(cell_pos)
		var roll := randf()
		if roll < 0.15:
			# 熄灭：死面板，无光
			_panel(light_container, p + Vector3(0, panel_y, 0), _dead_panel_mat)
		elif roll < 0.45:
			# 闪烁：灯光与面板自发光同步熄灭（sync_material）
			var light := FlickeringLight.new()
			light.light_color = light_color
			light.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
			light.omni_range = light_range
			light.omni_attenuation = 1.5
			light.shadow_enabled = true
			Atmosphere.set_fog_energy(light, 0.8)
			light.position = p + Vector3(0, panel_y - 0.1, 0)
			light_container.add_child(light)
			var pm := (_light_panel_mat as StandardMaterial3D).duplicate()
			_panel(light_container, p + Vector3(0, panel_y, 0), pm)
			light.sync_material = pm
		else:
			# 常亮
			var light2 := OmniLight3D.new()
			light2.light_color = light_color
			light2.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
			light2.omni_range = light_range
			light2.omni_attenuation = 1.5
			light2.shadow_enabled = true
			Atmosphere.set_fog_energy(light2, 0.8)
			light2.position = p + Vector3(0, panel_y - 0.1, 0)
			light_container.add_child(light2)
			_panel(light_container, p + Vector3(0, panel_y, 0), _light_panel_mat)

func _panel(container: Node3D, at: Vector3, mat: Material) -> void:
	var panel := CSGBox3D.new()
	panel.name = "Panel"
	panel.size = Vector3(light_panel_size.x, 0.06, light_panel_size.y)
	panel.position = at
	panel.material = mat
	panel.use_collision = false
	container.add_child(panel)

# ── 装饰：靠墙梯子（纯环境叙事，不可攀爬）───────────────────

func _custom_build() -> void:
	var decor := Node3D.new()
	decor.name = "Decor"
	add_child(decor)
	for rect in (maze as Level0Generator).rooms:
		if randf() >= 0.15:
			continue
		for _try in 6:
			var cell := Vector2i(randi_range(rect.position.x, rect.end.x - 1),
					randi_range(rect.position.y, rect.end.y - 1))
			if not maze.is_floor(cell.x, cell.y):
				continue
			var dirs := _wall_dirs_of(cell)
			if dirs.is_empty():
				continue
			_build_ladder(decor, cell, dirs[randi() % dirs.size()])
			break

func _build_ladder(container: Node3D, cell: Vector2i, dir: Vector2i) -> void:
	var ladder := Node3D.new()
	ladder.name = "Ladder"
	var base := _cell_to_world(cell)
	var normal := Vector3(dir.x, 0, dir.y)
	var tangent := Vector3(-dir.y, 0, dir.x)
	# 墙面在格边界线上；梯子贴墙立着（出墙 7cm）
	ladder.position = base + normal * (cell_size * 0.5 - 0.07)
	ladder.rotation.y = atan2(tangent.x, tangent.z)
	container.add_child(ladder)

	var h := wall_height - 0.05  # 顶着吊顶（3.0m 层高，梯子 2.95m）
	# 注意轴向：旋转后局部 X = 墙法线（厚度方向）、局部 Z = 墙切线（展开方向），
	# 立柱间距和横档长度都要摆在 Z 上，摆在 X 上会整架戳进墙里
	for side in [-0.225, 0.225]:
		var post := CSGBox3D.new()
		post.size = Vector3(0.05, h, 0.05)
		post.position = Vector3(0, h * 0.5, side)
		post.material = _wood_mat
		post.use_collision = false
		ladder.add_child(post)
	for i in 6:
		var rung := CSGBox3D.new()
		rung.size = Vector3(0.05, 0.045, 0.5)
		rung.position = Vector3(0, 0.42 + i * (h - 0.55) / 5.0, 0)
		rung.material = _wood_mat
		rung.use_collision = false
		ladder.add_child(rung)

# ── 出口：黑暗洞口（纯黑背板 + 暗黄微光内框，替换绿光面板）──

func _place_exit() -> void:
	exit_cell = maze.find_farthest_floor(spawn_cell)
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

	# 纯黑背板：一个"比夜色更黑"的洞口
	var portal := CSGBox3D.new()
	portal.size = Vector3(cell_size * 0.6, wall_height * 0.9, 0.15)
	portal.position = Vector3(0, 0, 0.1)
	portal.material = _dark_exit_mat
	portal.use_collision = false
	exit_area.add_child(portal)

	# 洞口内框：暗黄微光边条（暗示"里面有东西"而不是"这里有 UI"）
	var pw := cell_size * 0.6
	var ph := wall_height * 0.9
	var strips := [
		[Vector3(pw + 0.1, 0.06, 0.17), Vector3(0, ph * 0.5 + 0.02, 0.1)],
		[Vector3(pw + 0.1, 0.06, 0.17), Vector3(0, -ph * 0.5 - 0.02, 0.1)],
		[Vector3(0.06, ph + 0.1, 0.17), Vector3(-pw * 0.5 - 0.02, 0, 0.1)],
		[Vector3(0.06, ph + 0.1, 0.17), Vector3(pw * 0.5 + 0.02, 0, 0.1)],
	]
	for s in strips:
		var strip := CSGBox3D.new()
		strip.size = s[0]
		strip.position = s[1]
		strip.material = _exit_glow_mat
		strip.use_collision = false
		exit_area.add_child(strip)

	# EXIT 标牌：暗黄减半（可辨识性兜底）
	var label := Label3D.new()
	label.text = "EXIT"
	label.font_size = 96
	label.pixel_size = 0.004
	label.double_sided = true
	label.modulate = Color(0.8, 0.72, 0.45)
	label.outline_size = 12
	label.position = Vector3(0, wall_height * 0.35, -0.3)
	exit_area.add_child(label)

	add_child(exit_area)
	exit_area.body_entered.connect(_on_exit_door_entered)
	maze.compute_distance_field(exit_cell)
