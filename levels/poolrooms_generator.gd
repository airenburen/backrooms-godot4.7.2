class_name PoolroomsGenerator
extends MazeGenerator
# 泳室生成器：撒若干矩形"大厅"（互不重叠、留 3 格间隙）再用 2 格宽通道连通成一体。
# 大厅不重叠是硬约束：上层厅台地 / 拱券门套 / 深水池都按大厅矩形落位，
# 重叠会让台地悬在别家水池上、拱券飘在开阔地里（见 docs/level_poolrooms_design.md §3.8）。
# 输出结构完全兼容 MazeGenerator（grid/pillar_cells/距离场/寻路），
# 所以基类的墙体/出口/地标流程无需改动即可装配。
# halls 记录每个大厅的格矩形（关卡据此铺水面/台地/拱券）。

var halls: Array[Rect2i] = []

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
	dist = PackedInt32Array()
	halls = []

	# 大厅 8~14 格见方；放不下就逐级缩小再试，保证至少放下 4 个
	var target_count := randi_range(6, 8)
	var placed := 0
	for size_base in [14, 12, 10, 8]:
		for _i in range(target_count * 2):
			if placed >= target_count:
				break
			if halls.size() >= 4 and size_base <= 8:
				break
			var hw := randi_range(maxi(8, size_base - 2), size_base)
			var hh := randi_range(maxi(8, size_base - 2), size_base)
			var hx := randi_range(1, width - hw - 2)
			var hy := randi_range(1, height - hh - 2)
			var rect := Rect2i(hx, hy, hw, hh)
			# 间隙 3 格：通道 2 格 + 墙 1 格，互不打架
			var margin := Rect2i(hx - 3, hy - 3, hw + 6, hh + 6)
			var overlap := false
			for other in halls:
				if margin.intersects(other):
					overlap = true
					break
			if overlap:
				continue
			halls.append(rect)
			placed += 1
		if placed >= target_count:
			break

	# 兜底：一个都没放下（地图太小）——无间隙硬塞两个
	while halls.size() < 2:
		var hw := 8
		var hh := 8
		var hx := 1 + halls.size() * (hw + 1)
		var hy := 1
		if hx + hw >= width - 1:
			hx = 1
			hy = height - hh - 1
		var rect := Rect2i(hx, hy, hw, hh)
		var clash := false
		for other in halls:
			if rect.intersects(other):
				clash = true
				break
		if not clash:
			halls.append(rect)
			placed += 1
		else:
			break

	for hall in halls:
		_carve_rect(hall.position.x, hall.position.y, hall.size.x, hall.size.y)

	_connect_halls()
	# 保险：万一连通失败（理论上不会），把所有大厅中心串一条总线兜底
	if not _is_fully_connected():
		for i in range(1, halls.size()):
			_carve_corridor(halls[0].get_center(), halls[i].get_center())

func _carve_rect(x: int, y: int, w: int, h: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx > 0 and yy > 0 and xx < width - 1 and yy < height - 1:
				grid[_index(xx, yy)] = Cell.FLOOR

# 生成树连通：每次把"离已连通大厅最近"的一个大厅用 L 形通道接进来
func _connect_halls() -> void:
	if halls.is_empty():
		return
	var connected := [0]
	var remaining: Array[int] = []
	for i in range(1, halls.size()):
		remaining.append(i)
	while not remaining.is_empty():
		var best_i := -1
		var best_from := -1
		var best_d := 99999999.0
		for from_idx in connected:
			for rem_i in remaining:
				var d: float = (halls[from_idx].get_center() - halls[rem_i].get_center()).length_squared()
				if d < best_d:
					best_d = d
					best_i = rem_i
					best_from = from_idx
		_carve_corridor(halls[best_from].get_center(), halls[best_i].get_center())
		connected.append(best_i)
		remaining.erase(best_i)

# L 形通道：先横后纵（随机顺序），每步凿 2×2 门洞
func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var x := from.x
	var y := from.y
	var horizontal_first := randf() < 0.5
	if horizontal_first:
		while x != to.x:
			_carve_rect(x, y, 2, 2)
			x += signi(to.x - x)
		while y != to.y:
			_carve_rect(x, y, 2, 2)
			y += signi(to.y - y)
	else:
		while y != to.y:
			_carve_rect(x, y, 2, 2)
			y += signi(to.y - y)
		while x != to.x:
			_carve_rect(x, y, 2, 2)
			x += signi(to.x - x)
	_carve_rect(to.x, to.y, 2, 2)
