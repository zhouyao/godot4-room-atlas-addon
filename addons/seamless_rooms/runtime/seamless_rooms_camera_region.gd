@tool
class_name SeamlessRoomCameraRegion
extends RefCounted

## 相机中心的合法区域（一次性预计算）。
##
## 输入一组房间矩形与可见世界尺寸，用坐标压缩求出所有满足
## 「视图矩形被房间并集完全覆盖」的相机中心位置，合并成少量矩形。
## 配置 / 视口 / zoom 不变期间结果可反复查询，运行期不再做覆盖检测或二分。
##
## 纯几何数据 + 纯计算：不认识玩家、不认识 Camera2D、不移动任何节点。

const EPS := 0.5

## 进程内缓存：键 = 顺序无关的覆盖区签名 + 可见尺寸。
## 静态地图下同一片覆盖区在同一分辨率只算一次；切换分辨率后旧尺寸的结果也保留，
## 切回来直接命中。由 SeamlessRoomStreamer.configure() 清空，避免跨配置累积。
static var _cache: Dictionary = {}

static func cache_key(p_rects: Array, p_view: Vector2) -> String:
	var parts: Array[String] = []
	for r in p_rects:
		parts.append(str(r))
	parts.sort()
	return "%s|%.3fx%.3f" % ["|".join(PackedStringArray(parts)), p_view.x, p_view.y]


## 带缓存的构建；命中时不再跑坐标压缩。
static func build_cached(p_rects: Array, p_view: Vector2) -> SeamlessRoomCameraRegion:
	var key := cache_key(p_rects, p_view)
	if _cache.has(key):
		return _cache[key]
	var region := build(p_rects, p_view)
	_cache[key] = region
	return region


## 预热：把指定覆盖区 / 尺寸的合法区域提前算好，运行期切房直接查表。
static func precompute(p_rects: Array, p_view: Vector2) -> void:
	build_cached(p_rects, p_view)


static func clear_cache() -> void:
	_cache.clear()


static func cache_size() -> int:
	return _cache.size()

var view_size := Vector2.ZERO
var bounds := Rect2()                 # 合法中心的包围盒（房间包围盒按 view_size 收缩）
var rects: Array[Rect2] = []          # 精确合法区域，由若干矩形组成
var source_count := 0                 # 参与预计算的房间矩形数


static func build(p_room_rects: Array, p_view_size: Vector2) -> SeamlessRoomCameraRegion:
	var region := SeamlessRoomCameraRegion.new()
	region.view_size = p_view_size
	region.source_count = p_room_rects.size()
	if p_room_rects.is_empty() or p_view_size.x <= 0.0 or p_view_size.y <= 0.0:
		return region

	var first: Rect2 = p_room_rects[0]
	var all := first
	for i in range(1, p_room_rects.size()):
		var r: Rect2 = p_room_rects[i]
		all = all.merge(r)

	var half := p_view_size * 0.5
	var lo := all.position + half
	var hi := all.end - half
	if hi.x < lo.x:
		hi.x = lo.x
	if hi.y < lo.y:
		hi.y = lo.y
	region.bounds = Rect2(lo, hi - lo)

	# 覆盖性质只在「视图边对齐房间边」的临界中心坐标处变化。
	# 每个临界值 ±EPS 也入列，零厚度合法线段才不会被漏掉。
	var xs := _axis_candidates(p_room_rects, p_view_size.x, lo.x, hi.x, true)
	var ys := _axis_candidates(p_room_rects, p_view_size.y, lo.y, hi.y, false)
	# 只有「单房间覆盖区」（HARD_CUT 的单房约束区 / 孤立岛）才补退化轴：
	# 房间某条边恰好等于可见尺寸时，这条轴没有可变区间，候选只剩一个值。
	# 此时不能把整个合法区压成「一个中心点」——另一条轴往往仍有完整的一维区间
	# （r5 2400×2160：x 固定、y 可上下；r6 5400×1080：y 固定、x 可左右）。
	# 补一个重复端点，压成零宽列 / 零高行，交给同一套坐标压缩；两轴都退化时
	# 结果与旧的中心点逻辑完全一致（仍是房中心一个零大小矩形）。
	# 多矩形连通覆盖区（连续滚动）两轴都有多个候选值，不会进入这里，
	# 后续计算与改动前逐行相同。
	if p_room_rects.size() == 1:
		if xs.size() < 2:
			xs.append(xs[0])
		if ys.size() < 2:
			ys.append(ys[0])
	var nx := xs.size() - 1
	var ny := ys.size() - 1
	if nx <= 0 or ny <= 0:
		var c := Vector2((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5)
		if SeamlessRoomLayout.view_covered(Rect2(c - half, p_view_size), p_room_rects):
			region.rects.append(Rect2(c, Vector2.ZERO))
		return region

	# 按 x 排序，让每个网格单元只把「与自己相交」的房间交给 view_covered，
	# 而不是每次都遍历全部 N 个矩形（原先整体 ≈ O(N³)）。
	var by_x := p_room_rects.duplicate()
	by_x.sort_custom(func(a, b): return a.position.x < b.position.x)
	var max_width := 0.0
	for r in by_x:
		max_width = maxf(max_width, (r as Rect2).size.x)
	var legal: Array = []
	for j in range(ny):
		var row: Array[bool] = []
		var cy := (ys[j] + ys[j + 1]) * 0.5
		for i in range(nx):
			var cx := (xs[i] + xs[i + 1]) * 0.5
			var view := Rect2(Vector2(cx, cy) - half, p_view_size)
			row.append(SeamlessRoomLayout.view_covered(
					view, _candidates_for_view(by_x, view, max_width)))
		legal.append(row)
	region.rects = _merge_cells(legal, xs, ys, nx, ny)
	return region


static func _axis_candidates(p_room_rects: Array, p_view_len: float,
		p_lo: float, p_hi: float, p_is_x: bool) -> Array[float]:
	var half := p_view_len * 0.5
	var out: Array[float] = [p_lo, p_hi]
	for raw_r in p_room_rects:
		var r: Rect2 = raw_r
		var a := (r.position.x if p_is_x else r.position.y) + half
		var b := (r.end.x if p_is_x else r.end.y) - half
		out.append(clampf(a - EPS, p_lo, p_hi))
		out.append(clampf(a + EPS, p_lo, p_hi))
		out.append(clampf(b - EPS, p_lo, p_hi))
		out.append(clampf(b + EPS, p_lo, p_hi))
	out.sort()
	var uniq: Array[float] = []
	for v in out:
		if uniq.is_empty() or v - uniq[uniq.size() - 1] > 0.01:
			uniq.append(v)
	return uniq


## 按 x 排序的房间列表里取出与 view 真正相交的矩形。position.x 单调，
## 越过 view 右界即可停止；y 方向再补一次过滤，进一步缩小候选集。
static func _candidates_for_view(
		p_sorted: Array, p_view: Rect2, p_max_width: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	# position.x 单调：任何 position.x <= view.x - max_width 的房间，其 end.x
	# 必然 <= view.x，不可能与 view 相交，用二分直接跳过整段前缀。
	var start_x := p_view.position.x - p_max_width
	var lo := 0
	var hi := p_sorted.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if (p_sorted[mid] as Rect2).position.x <= start_x:
			lo = mid + 1
		else:
			hi = mid
	for i in range(lo, p_sorted.size()):
		var r: Rect2 = p_sorted[i]
		if r.position.x >= p_view.end.x:
			break
		if r.end.x <= p_view.position.x:
			continue
		if r.end.y <= p_view.position.y or r.position.y >= p_view.end.y:
			continue
		out.append(r)
	return out


## 贪心把合法网格单元合并成尽量少的矩形（先横向扩，再整行向下扩）。
static func _merge_cells(p_legal: Array, p_xs: Array, p_ys: Array,
		p_nx: int, p_ny: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var used: Array = []
	for j in range(p_ny):
		var row: Array[bool] = []
		for i in range(p_nx):
			row.append(false)
		used.append(row)
	for j in range(p_ny):
		var i := 0
		while i < p_nx:
			if not p_legal[j][i] or used[j][i]:
				i += 1
				continue
			var i2 := i
			while i2 + 1 < p_nx and p_legal[j][i2 + 1] and not used[j][i2 + 1]:
				i2 += 1
			var j2 := j
			while j2 + 1 < p_ny and _row_clear(p_legal, used, j2 + 1, i, i2):
				j2 += 1
			for jj in range(j, j2 + 1):
				for ii in range(i, i2 + 1):
					used[jj][ii] = true
			out.append(Rect2(Vector2(p_xs[i], p_ys[j]),
					Vector2(p_xs[i2 + 1] - p_xs[i], p_ys[j2 + 1] - p_ys[j])))
			i = i2 + 1
	return out


static func _row_clear(p_legal: Array, p_used: Array, p_j: int,
		p_i: int, p_i2: int) -> bool:
	for i in range(p_i, p_i2 + 1):
		if not p_legal[p_j][i] or p_used[p_j][i]:
			return false
	return true


func is_inside(p: Vector2) -> bool:
	for r in rects:
		if p.x >= r.position.x - EPS and p.x <= r.end.x + EPS \
				and p.y >= r.position.y - EPS and p.y <= r.end.y + EPS:
			return true
	return false


## 离 p 最近的合法中心：用于传送 / 策略切换后重新定位相机。
func nearest(p: Vector2) -> Vector2:
	if is_inside(p):
		return p
	var best := p
	var best_d := INF
	for r in rects:
		var q := Vector2(
			clampf(p.x, r.position.x, r.end.x),
			clampf(p.y, r.position.y, r.end.y)
		)
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best if best_d < INF else p


## 直线被挡住时，给出两段折线的下一航点。两种候选：
## · 先纵向对齐、再横向前进：下排房间高度恰好等于视口高时，横向合法带是
##   零厚度的，相机 y 必须精确对齐才能穿过（r4 → r3）。
## · 先横向进入竖直通道、再纵向跟随：L 形上下层之间的通行（r4 → r5）。
## 只返回两段都直线可达的折点；调用方限速逐帧靠近，避免瞬移。
func waypoint(p_from: Vector2, p_to: Vector2, p_layer_y: float = INF) -> Vector2:
	var goal := nearest(p_to)
	# 有房间层信息时，优先选 y 范围包含该层中心、且最窄的合法带：
	# 上层房间只落在竖直通道里，下层房间落在零厚度水平带里。
	# 只看 nearest() 会被横向距离误导到错误的带，让相机停在原地。
	if p_layer_y < INF:
		var best: Rect2
		var found := false
		var best_dx := INF
		for r in rects:
			if p_layer_y < r.position.y - EPS or p_layer_y > r.end.y + EPS:
				continue
			# 同一层里可能有多条合法带（竖直通道 + 零厚度水平带），选 clamp 后
			# 离目标 x 最近的那条：玩家在下层左半边时留在竖直通道，否则才滑到
			# 水平带。只按 y 宽度取最窄会把下层左侧的相机强行推到水平带左界。
			var gx := clampf(p_to.x, r.position.x, r.end.x)
			var dx := absf(gx - p_to.x)
			if not found or dx < best_dx:
				found = true
				best_dx = dx
				best = r
		if found:
			goal = Vector2(clampf(p_to.x, best.position.x, best.end.x),
					clampf(p_to.y, best.position.y, best.end.y))
	if _line_reachable(p_from, goal):
		return goal
	var corners: Array[Vector2] = [
		Vector2(p_from.x, goal.y),
		Vector2(goal.x, p_from.y),
	]
	for c in corners:
		if c.distance_to(p_from) <= EPS:
			continue
		if not is_inside(c):
			continue
		if not _line_reachable(p_from, c) or not _line_reachable(c, goal):
			continue
		return c
	return goal


## 线段是否完全落在合法区域内（用矩形交区间逐段推进，不假设目标点合法）。
func _line_reachable(p_from: Vector2, p_to: Vector2) -> bool:
	var t := 0.0
	for _iteration in range(8):
		var best := t
		for r in rects:
			var seg := _segment_in_rect(r, p_from, p_to)
			if seg.is_empty():
				continue
			if seg[0] <= t + 0.0001 and seg[1] > best:
				best = seg[1]
		if best >= 1.0 - 0.0001:
			return true
		if best <= t + 0.0001:
			return false
		t = best
	return false


## 沿 from → to 的线段，返回从合法位置出发能到达的最远合法中心。
## 用线段与各合法矩形的交区间逐段推进，精确，不需要二分或单调假设。
func project(p_from: Vector2, p_to: Vector2) -> Vector2:
	if is_inside(p_to):
		return p_to
	var t := 0.0
	for _iteration in range(8):
		var best := t
		for r in rects:
			var seg := _segment_in_rect(r, p_from, p_to)
			if seg.is_empty():
				continue
			if seg[0] <= t + 0.0001 and seg[1] > best:
				best = seg[1]
		if best <= t + 0.0001:
			break
		t = best
	return p_from.lerp(p_to, minf(t, 1.0))


static func _segment_in_rect(r: Rect2, p_from: Vector2, p_to: Vector2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var dx := p_to.x - p_from.x
	if absf(dx) < 0.000001:
		if p_from.x < r.position.x - EPS or p_from.x > r.end.x + EPS:
			return []
	else:
		var a := (r.position.x - EPS - p_from.x) / dx
		var b := (r.end.x + EPS - p_from.x) / dx
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	var dy := p_to.y - p_from.y
	if absf(dy) < 0.000001:
		if p_from.y < r.position.y - EPS or p_from.y > r.end.y + EPS:
			return []
	else:
		var a2 := (r.position.y - EPS - p_from.y) / dy
		var b2 := (r.end.y + EPS - p_from.y) / dy
		t0 = maxf(t0, minf(a2, b2))
		t1 = minf(t1, maxf(a2, b2))
	return [] if t0 > t1 else [t0, t1]
