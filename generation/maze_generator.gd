class_name MazeGenerator
extends RefCounted

enum Cell { WALL, FLOOR }

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var grid: PackedByteArray
var width: int
var height: int
# BFS 距离场：从出口出发到每个可行走格的步数，-1 表示不可达
var dist: PackedInt32Array
# 开阔区柱体格索引（用于渲染时套独立材质）
var pillar_cells := {}
# _carve_rooms 开凿的格子索引（子类关卡可据此布置家具，如仓库货箱）
var room_cells := {}
# _carve_rooms 开凿的房间矩形（格子坐标，供 L1 货架等按房间布局的装修用）
var room_rects: Array[Rect2i] = []

# —— 生成参数（各关卡可调，generate 前设置）——
# 额外环路：打通死墙的概率（0=纯迷宫，越高越"无限回廊"）
var loop_wall_chance := 0.14
var loop_pillar_chance := 0.06
# 死端编织概率：打掉死胡同尽头墙的概率
var braid_chance := 0.4
# 随机房间数/尺寸范围
var room_count_min := 3
var room_count_max := 5
var room_size_min := 2
var room_size_max := 5

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
	_carve_maze()
	_add_loops()
	_carve_rooms()
	_braid_dead_ends()
	_add_false_branches()
	_sprinkle_pillars()

func _index(x: int, y: int) -> int:
	return y * width + x

func is_wall(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height:
		return true
	return grid[_index(x, y)] == Cell.WALL

func is_floor(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height:
		return false
	return grid[_index(x, y)] == Cell.FLOOR

func _carve_maze() -> void:
	var stack: Array[Vector2i] = []
	var start := Vector2i(1, 1)
	grid[_index(start.x, start.y)] = Cell.FLOOR
	stack.append(start)

	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var neighbors := _get_unvisited_neighbors(current)
		if neighbors.is_empty():
			stack.pop_back()
		else:
			var next: Vector2i = neighbors[randi() % neighbors.size()]
			var wall_x: int = (current.x + next.x) / 2
			var wall_y: int = (current.y + next.y) / 2
			grid[_index(wall_x, wall_y)] = Cell.FLOOR
			grid[_index(next.x, next.y)] = Cell.FLOOR
			stack.append(next)

func _get_unvisited_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var directions := [
		Vector2i(0, -2), Vector2i(0, 2),
		Vector2i(-2, 0), Vector2i(2, 0)
	]
	var result: Array[Vector2i] = []
	for dir in directions:
		var nx: int = cell.x + dir.x
		var ny: int = cell.y + dir.y
		if nx > 0 and nx < width - 1 and ny > 0 and ny < height - 1:
			if grid[_index(nx, ny)] == Cell.WALL:
				result.append(Vector2i(nx, ny))
	return result

func _add_loops() -> void:
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			if grid[_index(x, y)] != Cell.WALL:
				continue
			var x_even := (x % 2 == 0)
			var y_even := (y % 2 == 0)
			if x_even and not y_even:
				if is_floor(x - 1, y) and is_floor(x + 1, y) and randf() < loop_wall_chance:
					grid[_index(x, y)] = Cell.FLOOR
			elif not x_even and y_even:
				if is_floor(x, y - 1) and is_floor(x, y + 1) and randf() < loop_wall_chance:
					grid[_index(x, y)] = Cell.FLOOR
			elif x_even and y_even:
				# 仅在邻接已有走廊时开格：孤立开格会形成四面围墙的 pocket，
				# 触发 _sprinkle_pillars 的连通性校验 → 全部柱体被连坐撤销
				if randf() < loop_pillar_chance and (is_floor(x - 1, y) or is_floor(x + 1, y) \
						or is_floor(x, y - 1) or is_floor(x, y + 1)):
					grid[_index(x, y)] = Cell.FLOOR

# 在迷宫中随机开凿若干矩形房间，打破单一走廊结构，形成开阔大厅
func _carve_rooms() -> void:
	var room_count := randi_range(room_count_min, room_count_max)
	for _i in room_count:
		var rw := randi_range(room_size_min, room_size_max)   # 房间宽（格）
		var rh := randi_range(room_size_min, room_size_max)   # 房间高（格）
		# 对齐到奇数坐标，保证房间边界落在走廊格上
		var rx := (randi_range(1, max(1, (width - rw - 1) / 2)) * 2) + 1
		var ry := (randi_range(1, max(1, (height - rh - 1) / 2)) * 2) + 1
		if rx + rw > width - 1 or ry + rh > height - 1:
			continue
		room_rects.append(Rect2i(rx, ry, rw, rh))
		for y in range(ry, ry + rh):
			for x in range(rx, rx + rw):
				if x > 0 and y > 0 and x < width - 1 and y < height - 1:
					grid[_index(x, y)] = Cell.FLOOR
					room_cells[_index(x, y)] = true

# 死端编织：打掉大部分死胡同尽头的墙，形成"无限回廊"的循环感（后室标志性体验）
func _braid_dead_ends() -> void:
	var dead_ends: Array[Vector2i] = []
	for y in range(1, height - 1, 2):
		for x in range(1, width - 1, 2):
			if not is_floor(x, y):
				continue
			var openings := 0
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if is_floor(x + dir.x, y + dir.y):
					openings += 1
			if openings == 1:
				dead_ends.append(Vector2i(x, y))
	for cell in dead_ends:
		if randf() >= braid_chance:
			continue
		var candidates: Array[Vector2i] = []
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var wall: Vector2i = cell + dir
			var beyond: Vector2i = cell + dir * 2
			if is_wall(wall.x, wall.y) and beyond.x > 0 and beyond.y > 0 \
					and beyond.x < width - 1 and beyond.y < height - 1 and is_floor(beyond.x, beyond.y):
				candidates.append(wall)
		if not candidates.is_empty():
			var pick: Vector2i = candidates[randi() % candidates.size()]
			grid[_index(pick.x, pick.y)] = Cell.FLOOR

# 假分支：在走廊侧壁开出 1-2 格的短岔路，看得见、走进去是死路。
# 增加"该走哪条"的判断成本，同时保留真正的连通性（岔路根部仍是走廊格）。
func _add_false_branches() -> void:
	var floors := get_all_floor_cells()
	# 数量硬上限 + 概率闸：旧版每次尝试必开，几百格迷宫能开出上百个假死路，是迷路主因。
	# 现在最多 6 条，且每条位置随机，只作点缀性迷惑，不破坏“可解且不太绕”的体验。
	var max_branches := mini(6, floors.size() / 12)
	var made := 0
	var attempts := floors.size()
	for _i in attempts:
		if made >= max_branches:
			break
		if randf() >= 0.5:
			continue
		var cell: Vector2i = floors[randi() % floors.size()]
		var dir: Vector2i = DIRS4[randi() % DIRS4.size()]
		var tip: Vector2i = cell + dir * 2
		# 要求：正侧是墙、目标格在图内且为墙、目标两侧封闭（避免开出新通路）
		if is_floor(cell.x + dir.x, cell.y + dir.y):
			continue
		if tip.x < 1 or tip.y < 1 or tip.x > width - 2 or tip.y > height - 2:
			continue
		if is_floor(tip.x, tip.y):
			continue
		var perp := Vector2i(dir.y, dir.x)
		if not is_wall(tip.x + perp.x, tip.y + perp.y) or not is_wall(tip.x - perp.x, tip.y - perp.y):
			continue
		if is_floor(tip.x + dir.x, tip.y + dir.y):
			continue  # 岔路尽头已有出口则不是死路，跳过
		grid[_index(cell.x + dir.x, cell.y + dir.y)] = Cell.FLOOR
		grid[_index(tip.x, tip.y)] = Cell.FLOOR
		made += 1

# 从 from 出发 BFS，返回最远且可贴门（有墙邻接）的可行走格作为出口，最大化探索距离
func find_farthest_floor(from: Vector2i) -> Vector2i:
	var d := PackedInt32Array()
	d.resize(width * height)
	d.fill(-1)
	if not is_floor(from.x, from.y):
		return from
	var queue: Array[Vector2i] = [from]
	d[_index(from.x, from.y)] = 0
	var best := from
	var best_d := 0
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var cd: int = d[_index(current.x, current.y)]
		var mountable := false
		for dir in DIRS4:
			if is_wall(current.x + dir.x, current.y + dir.y):
				mountable = true
		if cd > best_d and mountable:
			best_d = cd
			best = current
		for dir in DIRS4:
			var nx: int = current.x + dir.x
			var ny: int = current.y + dir.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			if not is_floor(nx, ny):
				continue
			var idx := _index(nx, ny)
			if d[idx] == -1:
				d[idx] = cd + 1
				queue.append(Vector2i(nx, ny))
	return best

# 在四周畅通的开阔区域撒独立柱体，作为空间地标（记录到 pillar_cells 供渲染层使用）
func _sprinkle_pillars() -> void:
	pillar_cells.clear()
	for y in range(2, height - 2):
		for x in range(2, width - 2):
			if not is_floor(x, y) or randf() >= 0.04:
				continue
			var all_floor := true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if not is_floor(x + dx, y + dy):
						all_floor = false
			if all_floor:
				grid[_index(x, y)] = Cell.WALL
				pillar_cells[_index(x, y)] = true
	# 柱体可能切断通路：撒完后校验全图连通性，不连通则全部撤销
	if not _is_fully_connected():
		for idx in pillar_cells:
			grid[idx] = Cell.FLOOR
		pillar_cells.clear()

func _is_fully_connected() -> bool:
	var floors := get_all_floor_cells()
	if floors.is_empty():
		return false
	var visited := {}
	var queue: Array[Vector2i] = [floors[0]]
	visited[floors[0]] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var next: Vector2i = current + dir
			if is_floor(next.x, next.y) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited.size() == floors.size()

# 查询某格到出口的 BFS 距离，-1 表示不可达
func dist_at(cell: Vector2i) -> int:
	if dist.is_empty() or not is_floor(cell.x, cell.y):
		return -1
	return dist[_index(cell.x, cell.y)]

func compute_distance_field(exit_cell: Vector2i) -> void:
	dist = PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	if not is_floor(exit_cell.x, exit_cell.y):
		return
	var queue: Array[Vector2i] = [exit_cell]
	dist[_index(exit_cell.x, exit_cell.y)] = 0
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var cd: int = dist[_index(current.x, current.y)]
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var nx: int = current.x + dir.x
			var ny: int = current.y + dir.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			if not is_floor(nx, ny):
				continue
			var idx := _index(nx, ny)
			if dist[idx] == -1:
				dist[idx] = cd + 1
				queue.append(Vector2i(nx, ny))

# 返回某个格子指向出口的下一步方向（梯度下降）。不可达返回 Vector2i.ZERO。
func get_guidance_dir(cell: Vector2i) -> Vector2i:
	if dist.is_empty() or not is_floor(cell.x, cell.y):
		return Vector2i.ZERO
	var here: int = dist[_index(cell.x, cell.y)]
	if here <= 0:
		return Vector2i.ZERO
	var best := here
	var best_dir := Vector2i.ZERO
	for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var nx: int = cell.x + dir.x
		var ny: int = cell.y + dir.y
		if nx < 0 or ny < 0 or nx >= width or ny >= height:
			continue
		if not is_floor(nx, ny):
			continue
		var d: int = dist[_index(nx, ny)]
		if d >= 0 and d < best:
			best = d
			best_dir = dir
	return best_dir

func find_nearest_floor(target: Vector2i) -> Vector2i:
	if is_floor(target.x, target.y):
		return target
	var queue: Array[Vector2i] = [target]
	var visited := {}
	visited[target] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if is_floor(current.x, current.y):
			return current
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var next: Vector2i = current + dir
			if next.x >= 0 and next.x < width and next.y >= 0 and next.y < height:
				if not visited.has(next):
					visited[next] = true
					queue.append(next)
	return Vector2i(1, 1)

func get_all_floor_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			if is_floor(x, y):
				result.append(Vector2i(x, y))
	return result
