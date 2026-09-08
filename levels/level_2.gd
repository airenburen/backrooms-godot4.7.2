extends "res://levels/level_base.gd"
# Level 2「管道之梦」：无限延伸的混凝土维护隧道（见 docs/level2_design.md）。
# 低顶棚窄廊，墙面管道簇（巨管+次管+细缆）/电缆桥架/留白，红手轮阀嘶嘶喷蒸汽；
# 老旧荧光灯管三态（常亮/闪烁/熄灭），斑驳石膏墙 + 霉斑墙裙 + 水渍顶带；
# 全局混响 + 滴水声 = 隧道回声。远处陷入黑暗。

const STEAM_MAX := 12  # 全图蒸汽源上限（克制，不是烟囱）

var _steam_count := 0
var _drip_timer: Timer
var _drip_player: AudioStreamPlayer
var _reverb: AudioEffectReverb

func _init() -> void:
	cell_size = 3.4
	wall_height = 2.4
	maze_size = 13
	light_color = Color(0.72, 0.82, 0.66)
	light_energy_range = Vector2(0.9, 1.3)
	light_range = 7.0
	light_panel_size = Vector2(1.0, 0.28)
	flicker_chance = 0.35
	fill_light_color = Color(0.25, 0.30, 0.25)
	fill_light_energy = 0.08
	volumetric_fog_density = 0.035
	dust_count = 400
	dust_extents = Vector3(8, 1.0, 8)
	hum_volume_db = -16.0
	hum_pitch = 0.88
	level_title = "Level 2"
	hint_text = "蒸汽里传来脚步声的回音"

func _ready() -> void:
	super._ready()
	_setup_tunnel_reverb()
	_start_drip()

func _generate_maze(m) -> void:
	m.loop_wall_chance = 0.3
	m.room_count_min = 1
	m.room_count_max = 2
	m.room_size_min = 2
	m.room_size_max = 3
	m.generate(maze_size, randi())

func _create_materials() -> void:
	_wall_mat = MatLib.l2_wall_mat()          # Plaster001 斑驳石膏，tint 压暗
	_floor_mat = MatLib.l2_floor_mat()
	_ceiling_mat = MatLib.l2_ceiling_mat()
	_pillar_mat = MatLib.l2_wall_mat()
	_light_panel_mat = _make_light_panel_mat(Color(0.72, 0.82, 0.66), Color(0.72, 0.82, 0.66))
	_exit_portal_mat = _make_exit_mat()

# —— 墙面：管线四态 + 霉斑墙裙 + 顶部水渍带（_emit_wall 钩子）——

func _emit_wall(container: Node3D, mat: StandardMaterial3D, horizontal: bool, line: int, sgn: int, a: int, b: int) -> CSGBox3D:
	var wall: CSGBox3D = super(container, mat, horizontal, line, sgn, a, b)
	var len := float(b - a + 1) * cell_size - 0.6
	if len < 1.6:
		return wall
	# 近地 0.9m 霉斑墙裙带（潮湿在墙根留下的痕迹）
	_wall_band(container, horizontal, line, sgn, a, b, 0.9, Color(0.20, 0.21, 0.18))
	# 顶部 0.3m 暗黄水渍带（渗水/蒸汽冷凝）
	_wall_band(container, horizontal, line, sgn, a, b, 0.3, Color(0.30, 0.27, 0.18), true)

	var roll := randf()
	if roll < 0.12:
		return wall  # 留白：密而不塞
	# 墙体走廊侧表面在 line*cs 处，走廊朝 +sgn 方向（对照基类 _emit_wall 的墙盒几何）
	var surf := float(line) * cell_size
	var along := (float(a) + float(b - a + 1) * 0.5) * cell_size
	if roll < 0.55:
		_pipe_cluster(container, horizontal, along, surf, sgn, len)
	elif roll < 0.82:
		# 平行管束：2-3 根中细管
		var h := wall_height - 0.32
		var n_p := 3 if randf() < 0.4 else 2
		for i in n_p:
			_pipe_line(container, horizontal, along, surf, sgn, h - i * 0.19,
				randf_range(0.055, 0.09), len, false)
	else:
		_cable_tray(container, horizontal, along, surf, sgn, len)
	return wall

# 贴墙色带：高 0.9m 深色霉斑 / 顶部 0.3m 水渍（薄板凸出墙面 1cm）
func _wall_band(container: Node3D, horizontal: bool, line: int, sgn: int,
		a: int, b: int, h: float, color: Color, top := false) -> void:
	var span: float = float(b - a + 1) * cell_size - 0.3
	if span < 0.8:
		return
	var surf := float(line) * cell_size
	var along := (float(a) + float(b - a + 1) * 0.5) * cell_size
	var band := CSGBox3D.new()
	var y: float = h * 0.5 + 0.01 if not top else wall_height - h * 0.5 - 0.01
	band.size = Vector3(span, h, 0.02) if horizontal else Vector3(0.02, h, span)
	band.position = Vector3(along, y, surf + sgn * 0.005) if horizontal \
			else Vector3(surf + sgn * 0.005, y, along)
	band.material = _band_mat(color)
	band.use_collision = false
	container.add_child(band)

func _band_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m

# 管道簇：主管（r 0.25~0.35 巨管）+ 伴行次管 + 细缆管——"把人挤在中间"的管线丛林
func _pipe_cluster(container: Node3D, horizontal: bool, along: float, surf: float, sgn: int, len: float) -> void:
	var r_main := randf_range(0.25, 0.35)
	var h_main := wall_height - r_main - 0.10
	var with_valve := randf() < 0.30
	var valve_at := _pipe_line(container, horizontal, along, surf, sgn, h_main, r_main, len, with_valve)
	if with_valve and valve_at != Vector3.INF:
		_steam_source(container, valve_at)
	var r_sec := randf_range(0.10, 0.15)
	var h_sec := h_main - r_main - r_sec - 0.07
	if h_sec - r_sec > 0.3:
		_pipe_line(container, horizontal, along, surf, sgn, h_sec, r_sec, len, false)
	var h_thin := h_sec - r_sec - 0.10
	if h_thin > 0.15:
		_pipe_line(container, horizontal, along, surf, sgn, h_thin, 0.05, len, false)

# 返回阀门位置（供挂蒸汽）；无阀返回 Vector3.INF
func _pipe_line(container: Node3D, horizontal: bool, along: float, surf: float, sgn: int,
		height: float, radius: float, len: float, with_valve: bool) -> Vector3:
	var pipe := CSGCylinder3D.new()
	pipe.radius = radius
	pipe.height = len
	pipe.sides = 12
	pipe.material = _pipe_mat()
	var d := radius + 0.06  # 管心距墙面：管壁刚好贴墙
	if horizontal:
		pipe.rotation.z = PI * 0.5
		pipe.position = Vector3(along, height, surf + sgn * d)
	else:
		pipe.rotation.x = PI * 0.5
		pipe.position = Vector3(surf + sgn * d, height, along)
	container.add_child(pipe)
	if not with_valve:
		return Vector3.INF
	# 阀门：短杆 + 锈红手轮，从管子垂直探进走廊（巨管用大手轮）
	var t := randf_range(-len * 0.3, len * 0.3)
	var stem_len := 0.18 + radius * 0.3
	var disc_r := 0.10 + radius * 0.35
	var stem := CSGCylinder3D.new()
	stem.radius = 0.022
	stem.height = stem_len
	stem.material = _valve_mat()
	var disc := CSGCylinder3D.new()
	disc.radius = disc_r
	disc.height = 0.05
	disc.sides = 12
	disc.material = _valve_mat()
	var valve_pos := Vector3.INF
	if horizontal:
		stem.rotation.x = PI * 0.5
		stem.position = Vector3(along + t, height, surf + sgn * (d + stem_len * 0.5))
		disc.rotation.x = PI * 0.5
		disc.position = Vector3(along + t, height, surf + sgn * (d + stem_len))
		valve_pos = disc.position
	else:
		stem.rotation.z = PI * 0.5
		stem.position = Vector3(surf + sgn * (d + stem_len * 0.5), height, along + t)
		disc.rotation.z = PI * 0.5
		disc.position = Vector3(surf + sgn * (d + stem_len), height, along + t)
		valve_pos = disc.position
	container.add_child(stem)
	container.add_child(disc)
	return valve_pos

func _cable_tray(container: Node3D, horizontal: bool, along: float, surf: float, sgn: int, len: float) -> void:
	var h := wall_height - 0.28
	var d := 0.26  # 托盘中心距墙
	var tray := CSGBox3D.new()
	tray.size = Vector3(len, 0.06, 0.4) if horizontal else Vector3(0.4, 0.06, len)
	tray.material = _tray_mat()
	if horizontal:
		tray.position = Vector3(along, h, surf + sgn * d)
	else:
		tray.position = Vector3(surf + sgn * d, h, along)
	container.add_child(tray)
	for off in [-0.1, 0.08]:
		var cable := CSGCylinder3D.new()
		cable.radius = 0.035
		cable.height = len - 0.4
		cable.sides = 8
		cable.material = _tray_mat()
		if horizontal:
			cable.rotation.z = PI * 0.5
			cable.position = Vector3(along, h + 0.07, surf + sgn * (d + off))
		else:
			cable.rotation.x = PI * 0.5
			cable.position = Vector3(surf + sgn * (d + off), h + 0.07, along)
		container.add_child(cable)

# —— 蒸汽：白雾粒子 + 嘶嘶声，"某几处管道在喘气" ——

func _steam_source(container: Node3D, at: Vector3) -> void:
	if _steam_count >= STEAM_MAX:
		return
	_steam_count += 1
	var p := GPUParticles3D.new()
	p.name = "Steam"
	p.amount = 10
	p.lifetime = 2.6
	p.preprocess = 2.6
	p.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.08, 0.05, 0.08)
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 14.0
	proc.initial_velocity_min = 0.35
	proc.initial_velocity_max = 0.8
	proc.gravity = Vector3(0, 0.05, 0)
	proc.scale_min = 0.8
	proc.scale_max = 2.4
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 0.15
	proc.turbulence_noise_scale = 2.0
	p.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	quad.material = _steam_material()
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 3.0, 2.4))
	p.position = at
	container.add_child(p)

	var hiss := AudioStreamPlayer3D.new()
	hiss.stream = SoundGen.create_hiss()
	hiss.volume_db = -14.0
	hiss.unit_size = 5.0
	hiss.autoplay = true
	hiss.position = at
	container.add_child(hiss)

static func _steam_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.92, 0.94, 0.93, 0.16)
	m.roughness = 1.0
	m.specular = 0.0
	return m

# —— 顶棚干线：大管成排（r 0.18~0.3），22 条，15% 漏蒸汽 ——

func _custom_build() -> void:
	var container := Node3D.new()
	container.name = "CeilingPipes"
	add_child(container)
	# Vector4i(cross, a, b, axis)，axis=1 沿 X / 0 沿 Z。
	var candidates: Array[Vector4i] = []
	for y in maze.height:
		var run := -1
		for x in maze.width + 1:
			var open: bool = x < maze.width and maze.is_floor(x, y)
			if open and run < 0:
				run = x
			elif not open and run >= 0:
				if x - run >= 4:
					candidates.append(Vector4i(y, run, x - 1, 1))
				run = -1
	for x in maze.width:
		var run := -1
		for y in maze.height + 1:
			var open: bool = y < maze.height and maze.is_floor(x, y)
			if open and run < 0:
				run = y
			elif not open and run >= 0:
				if y - run >= 4:
					candidates.append(Vector4i(x, run, y - 1, 0))
				run = -1
	candidates.shuffle()
	var built := 0
	for c in candidates:
		if built >= 22:
			break
		if randf() < 0.75:
			_ceiling_conduit(container, c.w == 1, c.y, c.z, c.x)
			built += 1

func _ceiling_conduit(container: Node3D, along_x: bool, a: int, b: int, cross: int) -> void:
	var length := float(b - a + 1) * cell_size - 1.0
	var center := (float(a) + float(b + 1)) * 0.5 * cell_size
	var line_pos := (float(cross) + 0.5) * cell_size
	var r0 := randf_range(0.18, 0.3)
	var h := wall_height - 0.05 - r0
	var radii := [r0, 0.12, 0.08]
	var offs := [0.0, r0 + 0.22, -r0 - 0.18]
	var n := 3 if randf() < 0.45 else 2
	for i in n:
		var pipe := CSGCylinder3D.new()
		pipe.radius = radii[i]
		pipe.height = length
		pipe.sides = 12
		pipe.material = _pipe_mat()
		if along_x:
			pipe.rotation.z = PI * 0.5
			pipe.position = Vector3(center, h if i == 0 else wall_height - 0.3, line_pos + offs[i] * 0.5)
		else:
			pipe.rotation.x = PI * 0.5
			pipe.position = Vector3(line_pos + offs[i] * 0.5, h if i == 0 else wall_height - 0.3, center)
		container.add_child(pipe)
	# 15% 干线漏蒸汽
	if randf() < 0.15 and _steam_count < STEAM_MAX:
		var t := randf_range(-length * 0.35, length * 0.35)
		var at := Vector3(center + t, h - r0 * 0.4, line_pos) if along_x \
				else Vector3(line_pos, h - r0 * 0.4, center + t)
		_steam_source(container, at)

# —— 老旧荧光灯：常亮 40% / 闪烁 35% / 熄灭 25%，密度调稀（路口/管群处才有灯）——

func _place_lights() -> void:
	var container := Node3D.new()
	container.name = "Lights"
	add_child(container)

	var floor_cells: Array[Vector2i] = maze.get_all_floor_cells()
	var covered := {}
	# 覆盖半径拉大 2.4 倍：灯更稀、走廊更深陷黑暗（同时把体积雾的按灯计费砍半）
	var range_in_cells: float = light_range * 2.4 / cell_size
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

	for cell_pos in positions:
		var world_pos := _cell_to_world(cell_pos)
		var roll := randf()
		if roll < 0.25:
			# 熄灭：死灰灯管，"老旧"的实锤
			_light_panel(container, world_pos + Vector3(0, wall_height - 0.15, 0), _dead_panel_mat())
		elif roll < 0.60:
			# 闪烁：灯管同步闪（复用 L1 验证过的 FlickeringLight + sync_material）
			var light := FlickeringLight.new()
			light.light_color = light_color
			light.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
			light.omni_range = light_range
			light.omni_attenuation = 1.5
			light.shadow_enabled = false
			light.position = world_pos + Vector3(0, wall_height - 0.4, 0)
			Atmosphere.set_fog_energy(light, 0.8)
			container.add_child(light)
			var mat := _lit_panel_mat()
			_light_panel(container, world_pos + Vector3(0, wall_height - 0.15, 0), mat)
			light.sync_material = mat
		else:
			var light2 := OmniLight3D.new()
			light2.light_color = light_color
			light2.light_energy = randf_range(light_energy_range.x, light_energy_range.y)
			light2.omni_range = light_range
			light2.omni_attenuation = 1.5
			light2.shadow_enabled = false
			light2.position = world_pos + Vector3(0, wall_height - 0.4, 0)
			Atmosphere.set_fog_energy(light2, 0.8)
			container.add_child(light2)
			_light_panel(container, world_pos + Vector3(0, wall_height - 0.15, 0), _lit_panel_mat())

# 老式窄灯管（1.0 × 0.28），贴顶
func _light_panel(container: Node3D, at: Vector3, mat: StandardMaterial3D) -> void:
	var panel := CSGBox3D.new()
	panel.size = Vector3(light_panel_size.x, 0.06, light_panel_size.y)
	panel.position = at
	panel.material = mat
	panel.use_collision = false
	container.add_child(panel)
	var housing := CSGBox3D.new()
	housing.size = Vector3(light_panel_size.x + 0.12, 0.05, light_panel_size.y + 0.06)
	housing.position = at + Vector3(0, 0.05, 0)
	housing.material = _tray_mat()
	housing.use_collision = false
	container.add_child(housing)

# 灯色老化：emission 压暗 30%、色温往绿黄偏
func _lit_panel_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.82, 0.66)
	m.emission_enabled = true
	m.emission = Color(0.72, 0.82, 0.66)
	m.emission_energy_multiplier = 1.4
	return m

func _dead_panel_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.31, 0.28)
	m.roughness = 0.7
	return m

# —— 回声：全局混响 bus（混凝土隧道的空荡感），离开关卡时撤掉 ——

func _setup_tunnel_reverb() -> void:
	var bus := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectReverb:
			return  # 已挂过（场景重载兜底）
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.9
	_reverb.damping = 0.65
	_reverb.wet = 0.15
	_reverb.hipass = 0.1
	AudioServer.add_bus_effect(bus, _reverb)
	tree_exiting.connect(func():
		if is_instance_valid(_reverb):
			var b := AudioServer.get_bus_index("Master")
			for i in AudioServer.get_bus_effect_count(b):
				if AudioServer.get_bus_effect(b, i) == _reverb:
					AudioServer.remove_bus_effect(b, i)
					break
	)

# 滴水：随机间隔 4~8 秒一声——"闷热潮湿"的听觉注脚
func _start_drip() -> void:
	_drip_player = AudioStreamPlayer.new()
	_drip_player.name = "DripPlayer"
	_drip_player.stream = SoundGen.create_drip()
	_drip_player.volume_db = -10.0
	add_child(_drip_player)
	_drip_timer = Timer.new()
	_drip_timer.one_shot = true
	_drip_timer.timeout.connect(func():
		if not is_instance_valid(_drip_player):
			return
		_drip_player.pitch_scale = randf_range(0.85, 1.25)
		_drip_player.play()
		_drip_timer.wait_time = randf_range(4.0, 8.0)
		_drip_timer.start()
	)
	add_child(_drip_timer)
	_drip_timer.wait_time = randf_range(2.0, 5.0)
	_drip_timer.start()

# —— 材质：锈蚀哑光，锈是主色 ——

func _pipe_mat() -> StandardMaterial3D:
	var r := randf()
	var m := StandardMaterial3D.new()
	if r < 0.30:
		m.albedo_color = Color(0.33, 0.34, 0.36)  # 灰铁 30%
	elif r < 0.70:
		m.albedo_color = Color(0.38, 0.15, 0.08)  # 锈红 40%（主色）
	else:
		m.albedo_color = Color(0.32, 0.22, 0.10)  # 暗铜 30%
	m.roughness = 0.7
	m.metallic = 0.3
	return m

func _tray_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.16, 0.17)
	m.roughness = 0.75
	m.metallic = 0.2
	return m

func _valve_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.08, 0.05)  # 锈红暗红，旧得不反光
	m.roughness = 0.7
	m.metallic = 0.2
	return m
