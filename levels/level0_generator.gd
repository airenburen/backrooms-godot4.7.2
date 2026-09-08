class_name Level0Generator
extends MazeGenerator
# 经典 L0 房间簇生成器（见 docs/level0_design.md §2.1）：
# 贪心装箱矩形房间（互不重叠、间隔 ≥1 格）+ MST 门洞连通（L 形通道穿过隔墙）
# + 大房柱阵 / 矮隔断（两端留口）+ 盲端凹室。输出完全兼容 MazeGenerator，
# 基类的墙体/地标/出口/距离场流程零改动可用。

var rooms: Array[Rect2i] = []

func generate(maze_size: int, seed_value: int = -1) -> void:
	if seed_value >= 0:
		seed(seed_value)
	width = maze_size * 2 + 1
	height = maze_size * 2 + 1
	grid = PackedByteArray()
	grid.resize(width * height)
	grid.fill(Cell.WALL)
	pillar_cells.clear()
	room_cells.clear()
	room_rects.clear()
	dist = PackedInt32Array()
	rooms.clear()

	# 1. 房间装箱：先塞 4 个 6~8 见方大厅（柱阵载体），再用 3~8 随机房填缝到 14~22；
	#    全部互不重叠、间隔 ≥1 格
	var target := randi_range(14, 22)
	var attempts := 0
	while rooms.size() < target and attempts < 12000:
		attempts += 1
		var big_phase := rooms.size() < 4
		var w := randi_range(6, 8) if big_phase else randi_range(3, 8)
		var h := randi_range(6, 8) if big_phase else randi_range(3, 8)
		var x := randi_range(2, width - w - 3)
		var y := randi_range(2, height - h - 3)
		var rect := Rect2i(x, y, w, h)
		var clash := false
		for other in rooms:
			if rect.grow(1).intersects(other.grow(1)):
				clash = true
				break
		if clash:
			continue
		rooms.append(rect)
		room_rects.append(rect)
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				grid[_index(xx, yy)] = Cell.FLOOR

	# 2. MST 连通：每个房间连向已放置的最近房间；35% 额外环路
	for i in range(1, rooms.size()):
		var j := _nearest_room(i)
		_carve_l_path(rooms[j], rooms[i])
		if rooms.size() > 2 and randf() < 0.35:
			_carve_l_path(rooms[_nearest_room(i, j)], rooms[i])

	# 3. 大房装修：≥6×6 房 70% 出柱阵，否则矮隔断（特大房 30% 再加一道）；小房仍可出一道
	for rect in rooms:
		var big := rect.size.x >= 6 and rect.size.y >= 6
		if big and randf() < 0.7:
			_add_colonnade(rect)
		elif randf() < 0.5:
			_add_partition(rect)
			if big and randf() < 0.3:
				_add_partition(rect)

	# 4. 盲端凹室：18% 房间向外凿 1×3~1×5 盲端
	for rect in rooms:
		if randf() < 0.18:
			_add_alcove(rect)

# 柱阵：房内每隔 2 格一根结构柱。柱格记为 WALL + pillar_cells——基类薄墙流程
# 自动跳过、按独立方柱渲染；柱间空 2 格、距墙 ≥1 格，不堵门不堵凹室
func _add_colonnade(rect: Rect2i) -> void:
	for yy in range(rect.position.y + 2, rect.end.y - 1, 2):
		for xx in range(rect.position.x + 2, rect.end.x - 1, 2):
			grid[_index(xx, yy)] = Cell.WALL
			pillar_cells[_index(xx, yy)] = true

func _nearest_room(i: int, exclude: int = -1) -> int:
	var best := -1
	var best_d := INF
	var ci := rooms[i].get_center()
	for j in i:
		if j == exclude:
			continue
		var d: float = ci.distance_to(rooms[j].get_center())
		if d < best_d:
			best_d = d
			best = j
	return best if best >= 0 else 0

# L 形 1 格宽通道：先横后竖或先竖后横（随机）
func _carve_l_path(a: Rect2i, b: Rect2i) -> void:
	var ac := Vector2i(int(a.get_center().x), int(a.get_center().y))
	var bc := Vector2i(int(b.get_center().x), int(b.get_center().y))
	if randf() < 0.5:
		_carve_h(ac.x, bc.x, ac.y)
		_carve_v(ac.y, bc.y, bc.x)
	else:
		_carve_v(ac.y, bc.y, ac.x)
		_carve_h(ac.x, bc.x, bc.y)

func _carve_h(x0: int, x1: int, y: int) -> void:
	y = clampi(y, 1, height - 2)
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		if x >= 1 and x <= width - 2:
			grid[_index(x, y)] = Cell.FLOOR

func _carve_v(y0: int, y1: int, x: int) -> void:
	x = clampi(x, 1, width - 2)
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		if y >= 1 and y <= height - 2:
			grid[_index(x, y)] = Cell.FLOOR

# 房内隔断：沿长轴方向一道 1 格厚墙，两端各留 1 格缺口（绕过去还有路）
func _add_partition(rect: Rect2i) -> void:
	var vertical: bool = rect.size.x >= rect.size.y
	if vertical and rect.size.x < 5:
		vertical = false
	if not vertical and rect.size.y < 5:
		if rect.size.x >= 5:
			vertical = true
		else:
			return
	var seg_len := randi_range(2, 4)
	if vertical:
		var xx := randi_range(rect.position.x + 2, rect.end.x - 3)
		var y0 := rect.position.y + 1
		var y1 := mini(y0 + seg_len - 1, rect.end.y - 2)
		for y in range(y0, y1 + 1):
			grid[_index(xx, y)] = Cell.WALL
	else:
		var yy := randi_range(rect.position.y + 2, rect.end.y - 3)
		var x0 := rect.position.x + 1
		var x1 := mini(x0 + seg_len - 1, rect.end.x - 2)
		for x in range(x0, x1 + 1):
			grid[_index(x, yy)] = Cell.WALL

# 盲端凹室：从房间边缘向外凿 1×3~1×5 格；途中有非墙格（撞别的房间/通道）则放弃
func _add_alcove(rect: Rect2i) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var dir: Vector2i = dirs[randi() % 4]
	var depth := randi_range(3, 5)
	if dir.x != 0:
		var edge: int = rect.end.x if dir.x > 0 else rect.position.x - 1
		var fixed := randi_range(rect.position.y, rect.end.y - 1)
		for step in depth:
			var x: int = edge + dir.x * step
			if x < 1 or x > width - 2 or grid[_index(x, fixed)] != Cell.WALL:
				return
		for step in depth:
			grid[_index(edge + dir.x * step, fixed)] = Cell.FLOOR
	else:
		var edge2: int = rect.end.y if dir.y > 0 else rect.position.y - 1
		var fixed2 := randi_range(rect.position.x, rect.end.x - 1)
		for step in depth:
			var y: int = edge2 + dir.y * step
			if y < 1 or y > height - 2 or grid[_index(fixed2, y)] != Cell.WALL:
				return
		for step in depth:
			grid[_index(fixed2, edge2 + dir.y * step)] = Cell.FLOOR
