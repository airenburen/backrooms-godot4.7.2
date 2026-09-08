class_name PoolroomsGenerator
extends MazeGenerator
# 泳池关生成器 v2「舱室图 + 深度图层」（docs/level_poolrooms_design.md）：
# ① 撒 6~9 个 10~16 格见方的池舱（间隙 ≥3 格），舱内凿 FLOOR
# ② 相邻舱用 4~6 格宽的直通桥连接（Prim 生成树 + 1~2 条环路），废除 2 格窄通道
# ③ 每舱内缩 2 格凿下沉池盆：盆缘一圈阳光浅台（-0.35），盆心深水（-1.2）
# grid 仍是 WALL/FLOOR 二值，MazeGenerator 的 BFS/距离场/贴墙判定零改动；
# depth/basins/col_cells/bridges 是 grid 之上的图层，关卡据此铺地板/水/柱/拱。

var halls: Array[Rect2i] = []        # 池舱矩形（格）
var basins: Array[Rect2i] = []       # 下沉池盆矩形（格）
var bridges: Array[Rect2i] = []      # 舱间直通桥（拱立在桥带中线上）
var col_cells := {}                  # 池中柱格索引（grid 仍 FLOOR，柱由关卡渲染）
var depth: PackedInt32Array          # 每格深度级：0 走道 / 1 浅台 / 2 深水

const SHELF_DEPTH := 1
const DEEP_DEPTH := 2
const DECK_INSET := 2   # 池盆距舱墙的干走道宽（格）

func depth_at(cell: Vector2i) -> int:
	if depth.is_empty() or cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return 0
	return depth[_index(cell.x, cell.y)]

func is_bridge_cell(x: int, y: int) -> bool:
	# 水平桥带可能与舱的北/南边界行重叠横穿（.gallery 分段据此排除桥格）
	for b in bridges:
		if x >= b.position.x and x < b.end.x and y >= b.position.y and y < b.end.y:
			return true
	return false

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
	basins = []
	bridges = []
	col_cells = {}
	depth = PackedInt32Array()
	depth.resize(width * height)

	# ① 撒舱：10~16 格见方、间隙 ≥3 格；放不下逐级缩，保底 2 个
	var target_count := randi_range(6, 9)
	var placed := 0
	for size_base in [16, 14, 12, 10]:
		for _i in range(target_count * 2):
			if placed >= target_count:
				break
			if halls.size() >= 4 and size_base <= 10:
				break
			var hw := randi_range(maxi(10, size_base - 2), size_base)
			var hh := randi_range(maxi(10, size_base - 2), size_base)
			var hx := randi_range(1, width - hw - 2)
			var hy := randi_range(1, height - hh - 2)
			var rect := Rect2i(hx, hy, hw, hh)
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
	while halls.size() < 2:
		var rect2 := Rect2i(1 + (halls.size() % 2) * (width - 12), 1, 10, 10)
		var clash := false
		for other in halls:
			if rect2.intersects(other):
				clash = true
				break
		if clash:
			break
		halls.append(rect2)

	# ② 舱内凿 FLOOR
	for hall in halls:
		_carve_rect(hall.position.x, hall.position.y, hall.size.x, hall.size.y)

	# ③ 桥接：Prim 生成树 + 1~2 条环路；失败兜底全桥接
	_connect_halls()
	_add_loop_bridges()
	if not _is_fully_connected():
		for i in range(1, halls.size()):
			_carve_bridge(halls[0], halls[i])

	# ④ 池盆：舱内缩 2 格；≥5×5 才成盆，否则该舱是旱厅
	for hall in halls:
		var inner := Rect2i(hall.position + Vector2i(DECK_INSET, DECK_INSET),
				hall.size - Vector2i(DECK_INSET * 2, DECK_INSET * 2))
		if inner.size.x < 5 or inner.size.y < 5:
			continue
		basins.append(inner)
		for yy in range(inner.position.y, inner.end.y):
			for xx in range(inner.position.x, inner.end.x):
				var ring := mini(mini(xx - inner.position.x, inner.end.x - 1 - xx),
						mini(yy - inner.position.y, inner.end.y - 1 - yy))
				depth[_index(xx, yy)] = SHELF_DEPTH if ring == 0 else DEEP_DEPTH
		# 池中柱网：3×3 格间距撒在深水区（ring≥1，避开盆缘浅台），神庙式柱林
		for yy in range(inner.position.y + 1, inner.end.y - 1):
			for xx in range(inner.position.x + 1, inner.end.x - 1):
				if (xx - inner.position.x) % 3 == 1 and (yy - inner.position.y) % 3 == 1:
					col_cells[_index(xx, yy)] = true

func _carve_rect(x: int, y: int, w: int, h: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx > 0 and yy > 0 and xx < width - 1 and yy < height - 1:
				grid[_index(xx, yy)] = Cell.FLOOR

# Prim：每次把"离已连通集最近"的舱桥接进来（开阔直通桥，不再是窄通道）
func _connect_halls() -> void:
	if halls.size() < 2:
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
		_carve_bridge(halls[best_from], halls[best_i])
		connected.append(best_i)
		remaining.erase(best_i)

# 环路：随机再搭 1~2 座桥，避免纯树形布局
func _add_loop_bridges() -> void:
	if halls.size() < 4:
		return
	var pairs: Array = []
	for i in halls.size():
		for j in range(i + 1, halls.size()):
			pairs.append(Vector2i(i, j))
	pairs.shuffle()
	var extra := randi_range(1, 2)
	var made := 0
	for p in pairs:
		if made >= extra:
			break
		_carve_bridge(halls[p.x], halls[p.y])
		made += 1

# 两舱直连桥：沿两舱重叠的轴带凿 4~6 格宽直通开口（穿过中间的间隙墙）；
# 对角舱（无重叠带）退化为宽 L 形，且不给拱
func _carve_bridge(a: Rect2i, b: Rect2i) -> void:
	var bw := randi_range(4, 6)
	var x_overl := mini(a.end.x, b.end.x) - maxi(a.position.x, b.position.x)
	var y_overl := mini(a.end.y, b.end.y) - maxi(a.position.y, b.position.y)
	var options: Array[int] = []
	if x_overl >= bw:
		options.append(0)   # 垂直桥（沿 y 凿）
	if y_overl >= bw:
		options.append(1)   # 水平桥（沿 x 凿）
	if options.is_empty():
		_carve_wide_l(a, b, bw)
		return
	if options[randi() % options.size()] == 0:
		var x0 := randi_range(maxi(a.position.x, b.position.x), mini(a.end.x, b.end.x) - bw)
		var y0 := mini(a.end.y, b.end.y) - 1
		var y1 := maxi(a.position.y, b.position.y) + 1
		_carve_rect(x0, y0, bw, y1 - y0 + 1)
		bridges.append(Rect2i(x0, y0, bw, y1 - y0 + 1))
	else:
		var y0 := randi_range(maxi(a.position.y, b.position.y), mini(a.end.y, b.end.y) - bw)
		var x0 := mini(a.end.x, b.end.x) - 1
		var x1 := maxi(a.position.x, b.position.x) + 1
		_carve_rect(x0, y0, x1 - x0 + 1, bw)
		bridges.append(Rect2i(x0, y0, x1 - x0 + 1, bw))

# 对角舱兜底：4~6 格宽的 L 形桥（不记入 bridges，桥上无拱）
func _carve_wide_l(a: Rect2i, b: Rect2i, w: int) -> void:
	var ca := a.get_center()
	var cb := b.get_center()
	var half := w / 2
	var x0 := mini(ca.x, cb.x) - half
	var x1 := maxi(ca.x, cb.x) + half
	var y0 := mini(ca.y, cb.y) - half
	var y1 := maxi(ca.y, cb.y) + half
	_carve_rect(x0, ca.y - half, x1 - x0, w)
	_carve_rect(cb.x - half, y0, w, y1 - y0)
