class_name WarehouseGenerator
extends MazeGenerator
# 仓库生成器：不是迷宫，是"开阔大平层 + 规则柱网 + 带缺口隔断墙"。
# 输出结构完全兼容 MazeGenerator（grid/pillar_cells/距离场/寻路），
# 基类的墙体/柱体/出口/地标流程无需改动即可装配。
# partitions 记录隔断墙段 {horizontal, line, a, b}，关卡据此贴靠货架。

const PILLAR_STRIDE := 4   # 柱网间距（格），4 格 = 16m
const PART_STRIDE := 4     # 隔断墙候选线间距（格）

var partitions: Array[Dictionary] = []

func generate(maze_size: int, seed_value: int = -1) -> void:
	if seed_value >= 0:
		seed(seed_value)
	width = maze_size * 2 + 1
	height = maze_size * 2 + 1
	grid = PackedByteArray()
	grid.resize(width * height)
	grid.fill(Cell.FLOOR)
	pillar_cells.clear()
	room_cells.clear()
	room_rects.clear()
	partitions.clear()
	dist = PackedInt32Array()

	# 1. 边界墙：四周一圈
	for x in width:
		grid[_index(x, 0)] = Cell.WALL
		grid[_index(x, height - 1)] = Cell.WALL
	for y in height:
		grid[_index(0, y)] = Cell.WALL
		grid[_index(width - 1, y)] = Cell.WALL

	# 2. 规则柱网：间隔 stride 的格点设柱（开阔地中不阻断通行）
	for y in range(PILLAR_STRIDE - 1, height - 1, PILLAR_STRIDE):
		for x in range(PILLAR_STRIDE - 1, width - 1, PILLAR_STRIDE):
			if x < 2 or y < 2 or x > width - 3 or y > height - 3:
				continue
			grid[_index(x, y)] = Cell.WALL
			pillar_cells[_index(x, y)] = true

	# 3. 隔断墙：候选线随机取 ~45%，每段开 2~3 个 2~3 格宽缺口
	_place_partitions(true)
	_place_partitions(false)

func _place_partitions(horizontal: bool) -> void:
	# horizontal：墙沿 X 延伸，line 是 y 坐标，扫描范围 width
	# vertical：墙沿 Y 延伸，line 是 x 坐标，扫描范围 height
	var cross_count := width if horizontal else height
	var line_max := height if horizontal else width
	for line in range(PART_STRIDE + 1, line_max - PART_STRIDE, PART_STRIDE):
		if randf() > 0.45:
			continue
		# 沿该线随机放 1~2 段墙，段间留大缺口
		var pos := randi_range(2, max(2, cross_count - 10))
		var segs := 1 if randf() < 0.6 else 2
		for _s in segs:
			var a := pos
			var b := mini(pos + randi_range(4, 10), cross_count - 3)
			for c in range(a, b + 1):
				var gx: int = c if horizontal else line
				var gy: int = line if horizontal else c
				if gx < 2 or gy < 2 or gx > width - 3 or gy > height - 3:
					continue
				if pillar_cells.has(_index(gx, gy)):
					continue  # 不与柱体重合
				grid[_index(gx, gy)] = Cell.WALL
			partitions.append({"horizontal": horizontal, "line": line, "a": a, "b": b})
			pos = b + randi_range(3, 6)
			if pos >= cross_count - 6:
				break
