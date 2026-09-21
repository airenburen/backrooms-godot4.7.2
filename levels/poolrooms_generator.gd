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
var l_bridges: Array[Rect2i] = []    # 对角舱的 L 形兜底桥：只供二层天桥用，
                                     # 不并入 bridges（否则会多生成拱门、改动 is_bridge_cell）
var col_cells := {}                  # 池中柱格索引（grid 仍 FLOOR，柱由关卡渲染）
var depth: PackedInt32Array          # 每格深度级：0 走道 / 1 浅台 / 2 深水

const SHELF_DEPTH := 1
const DEEP_DEPTH := 2
const DECK_INSET := 2   # 池盆距舱墙的干走道宽（格）

# —— 上层图层（二楼）：grid 之上的平行数组，MazeGenerator 的 2D 接口零改动 ——
const UP_NONE := 0    # 上方无板（挑空天井，从一层直望天花）
const UP_SLAB := 1    # 上方有楼板，二楼可站立
const UP_WELL := 2    # 楼梯井（楼板开洞）

var upper: PackedInt32Array          # 与 depth 同尺寸：UP_NONE / UP_SLAB / UP_WELL
var upper_halls := {}                # hall 下标 -> true（双层舱：二楼明显宽于一层）
var upper_bridge_cells := {}         # 索引 -> true（天桥面格：回廊板在此让位，免 z-fighting）
var upper_stairs: Array[Dictionary] = []   # {hall, kind, rect, up_dir, edge_dir, bottom, top, need}
var upper_bridges: Array[Dictionary] = []  # {bridge_idx, cells: Array[Vector2i], axis}
var upper_wells: Array[Rect2i] = []  # 各舱挑空（天井）矩形，栏墙沿其边界
var _all_bridges: Array[Rect2i] = []      # bridges + l_bridges（天桥候选）
var _skipped_bridges: Array[int] = []     # 被环路概率跳过、待连通修复时补建

func upper_at(cell: Vector2i) -> int:
	if upper.is_empty() or cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return UP_NONE
	return upper[_index(cell.x, cell.y)]

func upper_slab(cell: Vector2i) -> bool:
	return upper_at(cell) == UP_SLAB

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
	l_bridges = []
	col_cells = {}
	depth = PackedInt32Array()
	depth.resize(width * height)
	upper = PackedInt32Array()
	upper.resize(width * height)
	upper_halls.clear()
	upper_bridge_cells.clear()
	upper_stairs = []
	upper_bridges = []
	upper_wells = []
	_all_bridges = []
	_skipped_bridges = []

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

	# ⑤ 上层规划：选双层舱 → 定楼梯 → 铺楼板 → 架天桥 → 连通修复
	_plan_upper()

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

# 对角舱兜底：4~6 格宽的 L 形桥（不并入 bridges、桥上无拱，但二层天桥要沿它架）
func _carve_wide_l(a: Rect2i, b: Rect2i, w: int) -> void:
	var ca := a.get_center()
	var cb := b.get_center()
	var half := w / 2
	var x0 := mini(ca.x, cb.x) - half
	var x1 := maxi(ca.x, cb.x) + half
	var y0 := mini(ca.y, cb.y) - half
	var y1 := maxi(ca.y, cb.y) + half
	_carve_rect(x0, ca.y - half, x1 - x0, w)
	l_bridges.append(Rect2i(x0, ca.y - half, x1 - x0, w))
	_carve_rect(cb.x - half, y0, w, y1 - y0)
	l_bridges.append(Rect2i(cb.x - half, y0, w, y1 - y0))

# ── 上层规划：选双层舱 → 定楼梯 → 铺楼板 → 架天桥 → 连通修复 ──────────

func _plan_upper() -> void:
	if halls.size() < 2:
		return
	_choose_double_halls()

	# 先定楼梯再铺板：找不到楼梯位的舱直接放弃二层（宁可"平"，不留上不去的板）
	var specs: Array[Dictionary] = []
	for i in halls.size():
		var spec := _plan_stairs(i, upper_halls.has(i))
		if spec.is_empty():
			upper_halls.erase(i)
			continue
		specs.append(spec)

	for spec in specs:
		_plan_hall_slab(spec["hall"], spec["double"])
	for spec in specs:
		upper_stairs.append(spec)
		_mark_well(spec["rect"])

	_plan_bridges()
	_repair_upper()

# 双层舱：按面积降序取最多 2 个（长边 ≥12 格），且至少留一个回廊舱保证形态混合
func _choose_double_halls() -> void:
	var order: Array[int] = []
	for i in halls.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return halls[a].get_area() > halls[b].get_area())
	for i in order:
		if upper_halls.size() >= 2:
			break
		if halls.size() - upper_halls.size() <= 1:
			break
		var hall: Rect2i = halls[i]
		if maxi(hall.size.x, hall.size.y) < 12:
			continue
		upper_halls[i] = true

func _basin_of(hall: Rect2i) -> Rect2i:
	for b in basins:
		if hall.has_point(b.position) and hall.has_point(b.end - Vector2i(1, 1)):
			return b
	return Rect2i()

# 某格是否被规划为二层板（与 _plan_hall_slab 的规则必须一致）
func _slab_planned(cell: Vector2i, hall_idx: int) -> bool:
	if not is_floor(cell.x, cell.y):
		return false
	var hall: Rect2i = halls[hall_idx]
	if not hall.has_point(cell):
		return false
	if upper_halls.has(hall_idx):
		var basin := _basin_of(hall)
		if basin.size.x > 4 and basin.size.y > 4 and basin.grow(-1).has_point(cell):
			return false  # 双层舱的挑空（盆内缩 1 格）
		return true
	return depth_at(cell) == 0

func _plan_hall_slab(hall_idx: int, is_double: bool) -> void:
	var hall: Rect2i = halls[hall_idx]
	var basin := _basin_of(hall)
	var well := Rect2i()
	if basin.size.x > 4 and basin.size.y > 4:
		well = basin.grow(-1) if is_double else basin
	for y in range(hall.position.y, hall.end.y):
		for x in range(hall.position.x, hall.end.x):
			if well.size.x > 0 and well.has_point(Vector2i(x, y)):
				continue
			upper[_index(x, y)] = UP_SLAB
	if well.size.x > 0:
		upper_wells.append(well)

func _mark_well(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			upper[_index(x, y)] = UP_WELL

# 每舱一条楼梯：扫四条边，取"外侧是墙且非桥带"的最长连续段，
# 回廊舱占 2 格（折返梯），双层舱占 3 格（直跑梯）
func _plan_stairs(hall_idx: int, is_double: bool) -> Dictionary:
	var hall: Rect2i = halls[hall_idx]
	var need := 3 if is_double else 2
	var best: Dictionary = {}
	for dir in DIRS4:
		var cells := _edge_run(hall, dir)
		var run: Array[Vector2i] = []
		for i in range(cells.size() + 1):
			var ok := false
			if i < cells.size():
				var c: Vector2i = cells[i]
				ok = is_wall(c.x + dir.x, c.y + dir.y) and not is_bridge_cell(c.x, c.y)
			if ok:
				run.append(cells[i])
				continue
			if run.size() >= need:
				var spec := _make_stair_spec(hall_idx, is_double, dir, run, need)
				if not spec.is_empty() and int(spec["span"]) > int(best.get("span", -1)):
					best = spec
			run = []
	return best

func _make_stair_spec(hall_idx: int, is_double: bool, edge_dir: Vector2i,
		run: Array[Vector2i], need: int) -> Dictionary:
	var off := (run.size() - need) / 2
	var use: Array[Vector2i] = []
	for i in range(off, off + need):
		use.append(run[i])
	var base := Vector2i(1, 0) if edge_dir.y != 0 else Vector2i(0, 1)
	# 折返梯出口在起端外侧（第二跑折回），直跑梯出口在末端外侧
	for flip in [false, true]:
		var ud: Vector2i = -base if flip else base
		var top: Vector2i = use[need - 1] + ud if is_double else use[0] - ud
		if not _slab_planned(top, hall_idx) or is_bridge_cell(top.x, top.y):
			continue
		var rect: Rect2i
		if edge_dir.y != 0:
			rect = Rect2i(use[0].x, use[0].y, need, 1)
		else:
			rect = Rect2i(use[0].x, use[0].y, 1, need)
		return {
			"hall": hall_idx, "double": is_double,
			"kind": "straight" if is_double else "switch",
			"rect": rect, "up_dir": ud, "edge_dir": edge_dir,
			"bottom": use[0], "top": top, "span": run.size(),
		}
	return {}

# 舱某条边的格序列（dir 为外法线方向）
func _edge_run(hall: Rect2i, dir: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if dir.y != 0:
		var y: int = hall.position.y if dir.y < 0 else hall.end.y - 1
		for x in range(hall.position.x, hall.end.x):
			out.append(Vector2i(x, y))
	else:
		var x: int = hall.position.x if dir.x < 0 else hall.end.x - 1
		for y in range(hall.position.y, hall.end.y):
			out.append(Vector2i(x, y))
	return out

# 天桥：沿每座桥的中线找两端第一个二层板格，中间格铺桥面。
# MST 生成树的桥必建（保证上层连通）、L 形兜底桥一律建；环路桥按概率建，
# 被跳过的记进 _skipped_bridges——连通修复时还会补回来，不会白丢
func _plan_bridges() -> void:
	_all_bridges = []
	_all_bridges.append_array(bridges)
	_all_bridges.append_array(l_bridges)
	var mst_count := maxi(halls.size() - 1, 1)
	for bi in _all_bridges.size():
		var mandatory := bi < mst_count or bi >= bridges.size()
		if not mandatory and randf() >= 0.6:
			_skipped_bridges.append(bi)
			continue
		_try_bridge(bi, _all_bridges[bi])

# 桥带方向有歧义（size.x == size.y 时）：两个轴向的中线都试，取能接上两端板的那个
func _try_bridge(bi: int, b: Rect2i) -> bool:
	for along_y in [b.size.x <= b.size.y, b.size.x > b.size.y]:
		var cells := _bridge_line(b, along_y)
		var a := -1
		var z := -1
		for i in cells.size():
			if upper_at(cells[i]) == UP_SLAB:
				if a < 0:
					a = i
				z = i
		if a < 0 or z <= a:
			continue
		var blocked := false
		for i in range(a, z + 1):
			if upper_at(cells[i]) == UP_WELL:
				blocked = true
				break
		if blocked:
			continue
		_commit_bridge(bi, cells, a, z)
		return true
	return false

func _bridge_line(b: Rect2i, along_y: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if along_y:
		var mx: int = b.position.x + (b.size.x - 1) / 2
		for y in range(b.position.y, b.end.y):
			cells.append(Vector2i(mx, y))
	else:
		var my: int = b.position.y + (b.size.y - 1) / 2
		for x in range(b.position.x, b.end.x):
			cells.append(Vector2i(x, my))
	return cells

func _commit_bridge(bi: int, cells: Array[Vector2i], a: int, z: int) -> void:
	var span: Array[Vector2i] = cells.slice(a, z + 1)
	for c in span:
		upper[_index(c.x, c.y)] = UP_SLAB
		upper_bridge_cells[_index(c.x, c.y)] = true
	upper_bridges.append({
		"bridge_idx": bi, "cells": span, "axis": span[0].x == span[span.size() - 1].x,
	})

# 连通修复：只保留最大连通块，其余整体降级（无板就不画栏墙/楼梯/桥），
# 绝不留上不去的孤立二层。降级前先补建被概率跳过的桥——把桥补上比废掉整个舱的二层划算
func _repair_upper() -> void:
	if not _skipped_bridges.is_empty():
		for bi in _skipped_bridges:
			if bi < _all_bridges.size():
				_try_bridge(bi, _all_bridges[bi])
		_skipped_bridges.clear()
	var slabs: Array[Vector2i] = []
	for y in height:
		for x in width:
			if upper[_index(x, y)] == UP_SLAB:
				slabs.append(Vector2i(x, y))
	if slabs.is_empty():
		return
	var comp := {}
	var sizes := {}
	var next_id := 0
	var best_id := -1
	var best_size := 0
	for start in slabs:
		if comp.has(start):
			continue
		var queue: Array[Vector2i] = [start]
		comp[start] = next_id
		var count := 1
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			for dir in DIRS4:
				var n: Vector2i = cur + dir
				if upper_at(n) != UP_SLAB or comp.has(n):
					continue
				comp[n] = next_id
				count += 1
				queue.append(n)
		sizes[next_id] = count
		if count > best_size:
			best_size = count
			best_id = next_id
		next_id += 1
	if sizes.size() <= 1:
		return
	for c in slabs:
		if comp[c] != best_id:
			upper[_index(c.x, c.y)] = UP_NONE
			upper_bridge_cells.erase(_index(c.x, c.y))
	var keep_stairs: Array[Dictionary] = []
	for s in upper_stairs:
		var t: Vector2i = s["top"]
		if upper_slab(t):
			keep_stairs.append(s)
	upper_stairs = keep_stairs
	var keep_bridges: Array[Dictionary] = []
	for b in upper_bridges:
		var cs: Array = b["cells"]
		if cs.size() > 0 and upper_slab(cs[0]):
			keep_bridges.append(b)
	upper_bridges = keep_bridges
	var keep_wells: Array[Rect2i] = []
	for w in upper_wells:
		if _well_kept(w):
			keep_wells.append(w)
	upper_wells = keep_wells
	var stale: Array[int] = []
	for i in upper_halls:
		if not _hall_has_slab(i):
			stale.append(i)
	for i in stale:
		upper_halls.erase(i)

# 挑空边界外一圈还有板 → 这块天井还有意义（否则该舱已被降级，栏墙不许悬空）
func _well_kept(w: Rect2i) -> bool:
	for y in range(w.position.y - 1, w.end.y + 1):
		for x in range(w.position.x - 1, w.end.x + 1):
			var c := Vector2i(x, y)
			if w.has_point(c):
				continue
			if upper_slab(c):
				return true
	return false

func _hall_has_slab(hall_idx: int) -> bool:
	var hall: Rect2i = halls[hall_idx]
	for y in range(hall.position.y, hall.end.y):
		for x in range(hall.position.x, hall.end.x):
			if upper[_index(x, y)] == UP_SLAB:
				return true
	return false
