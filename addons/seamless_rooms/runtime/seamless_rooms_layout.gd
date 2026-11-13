@tool
class_name SeamlessRoomLayout
extends RefCounted

## 把配置变成可查询的几何：世界矩形、坐标换算、空间索引。
## 纯数据层，不进场景树，不加载任何场景。

## 空间索引桶尺寸（世界像素），与 cell_size 完全解耦。
## 网格可以细到 1px，索引桶数仍然是常数。
## 桶尺寸由 SeamlessRoomStreamingSettings.bucket_size 配置；<= 0 时按地图房间
## 短边的中位数自动推导，不依赖任何示例视口或房间尺寸。
const FALLBACK_BUCKET_SIZE := SeamlessRoomStreamingSettings.FALLBACK_BUCKET_SIZE
## 单次邻域查询允许枚举的桶数上限，防止 radius 误配时卡死主线程。
const MAX_QUERY_BUCKETS := 4096

var config: SeamlessRoomConfig

var _by_id: Dictionary = {}
var _buckets: Dictionary = {}  # Vector2i(桶坐标) -> Array[StringName]
var _cell_size := Vector2(1, 1)
var _streaming: SeamlessRoomStreamingSettings = null
var _bucket_size := FALLBACK_BUCKET_SIZE
var _world_bounds := Rect2()   # 全图包围盒，供自动推导搜索半径
var _avg_room_area := 1.0     # 平均房间面积，供自动派生挂载上限


func _init(p_config: SeamlessRoomConfig = null) -> void:
	if p_config != null:
		configure(p_config)


func configure(p_config: SeamlessRoomConfig) -> void:
	config = p_config
	_by_id.clear()
	_buckets.clear()
	_world_bounds = Rect2()
	_avg_room_area = 1.0
	if p_config.cell_size.x > 0.0 and p_config.cell_size.y > 0.0:
		_cell_size = p_config.cell_size
	_streaming = p_config.streaming if p_config.streaming != null \
			else SeamlessRoomStreamingSettings.new()
	# bucket_size <= 0 / NaN / INF 一律走自动推导，不绑定任何示例尺度。
	_bucket_size = FALLBACK_BUCKET_SIZE
	if _streaming.bucket_size > 0.0 and _streaming.bucket_size < INF:
		_bucket_size = _streaming.bucket_size
	else:
		_bucket_size = suggest_bucket_size(p_config)

	var first := true
	var area_sum := 0.0
	var area_count := 0
	for p in p_config.placements():
		# 空 id / 重复 id / 非正尺寸都不进索引：桶登记必须与 _by_id 的几何一致。
		if p.id == &"" or _by_id.has(p.id):
			continue
		if p.cells.size.x <= 0 or p.cells.size.y <= 0:
			continue
		_by_id[p.id] = p
		var r := world_rect(p.id)
		if first:
			_world_bounds = r
			first = false
		else:
			_world_bounds = _world_bounds.merge(r)
		area_sum += r.get_area()
		area_count += 1
		# 按空间索引桶登记，而不是逐格登记：
		# 即便 cell_size = 1px，一间房也只占几个桶。
		var lo := Vector2i(
			floori(r.position.x / _bucket_size),
			floori(r.position.y / _bucket_size)
		)
		# 半开区间 [position, end) 的精确桶上界：ceili(end/B) - 1。
		var hi := Vector2i(
			ceili(r.end.x / _bucket_size) - 1,
			ceili(r.end.y / _bucket_size) - 1
		)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var k := Vector2i(x, y)
				if not _buckets.has(k):
					_buckets[k] = []
				_buckets[k].append(p.id)
	if area_count > 0:
		_avg_room_area = maxf(area_sum / float(area_count), 1.0)


func cell_size() -> Vector2:
	return _cell_size


func streaming() -> SeamlessRoomStreamingSettings:
	return _streaming


func bucket_size() -> float:
	return _bucket_size


func room_count() -> int:
	return _by_id.size()


func average_room_area() -> float:
	return _avg_room_area


func world_bounds() -> Rect2:
	return _world_bounds


## 按地图房间短边的中位数选桶尺寸：桶太大候选超集宽，太小登记数多。
## 只依据地图几何，不假设任何视口或示例房间尺寸。
static func suggest_bucket_size(p_config: SeamlessRoomConfig) -> float:
	var cs := p_config.cell_size
	var sizes: Array[float] = []
	for p in p_config.placements():
		if p.cells.size.x <= 0 or p.cells.size.y <= 0:
			continue
		var short_side := minf(float(p.cells.size.x) * cs.x, float(p.cells.size.y) * cs.y)
		if short_side > 0.0 and short_side < INF:
			sizes.append(short_side)
	if sizes.is_empty():
		return SeamlessRoomStreamingSettings.FALLBACK_BUCKET_SIZE
	sizes.sort()
	return clampf(sizes[sizes.size() / 2], 64.0, 8192.0)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _by_id.keys():
		out.append(id)
	return out


func has_room(id: StringName) -> bool:
	return _by_id.has(id)


func placement(id: StringName) -> SeamlessRoomPlacement:
	return _by_id.get(id, null)


func scene_path(id: StringName) -> String:
	var p: SeamlessRoomPlacement = _by_id.get(id, null)
	if p == null or p.scene == null:
		return ""
	return p.scene.resource_path


func world_rect(id: StringName) -> Rect2:
	var p: SeamlessRoomPlacement = _by_id.get(id, null)
	if p == null:
		return Rect2()
	return Rect2(_v2(p.cells.position) * _cell_size, _v2(p.cells.size) * _cell_size)


## 所有相邻房间的共享边（纯几何派生，不读 config.seams，不含渲染语义）。
##
## 竖直：左右贴边 + y 区间重叠；水平：上下贴边 + x 区间重叠。
## 只取重叠区间，不取两房并集 —— L 形拼接时并集会把空白也算成接缝。
## 走 _nearby_ids() 桶候选，避免全表 O(N²)；同一条边按 key 去重。
## 详见 docs/seam-blending.md §5。
func seams() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for id in ids():
		var r := world_rect(id)
		for other in _nearby_ids(r):
			if other == id or str(id) >= str(other):
				continue   # 每对房间只处理一次
			_add_seam(out, seen, id, other, r, world_rect(other), SeamlessRoomSeam.AXIS_X)
			_add_seam(out, seen, id, other, r, world_rect(other), SeamlessRoomSeam.AXIS_Y)
	return out


func _add_seam(out: Array[Dictionary], seen: Dictionary,
		a: StringName, b: StringName, ra: Rect2, rb: Rect2, axis: int) -> void:
	# 按几何方位规范化：low = 较小 x / 较小 y 的一侧。
	var low := ra
	var high := rb
	var low_id := a
	var high_id := b
	if axis == SeamlessRoomSeam.AXIS_X and ra.position.x > rb.position.x:
		low = rb
		high = ra
		low_id = b
		high_id = a
	elif axis == SeamlessRoomSeam.AXIS_Y and ra.position.y > rb.position.y:
		low = rb
		high = ra
		low_id = b
		high_id = a

	var at := 0.0
	var from := 0.0
	var to := 0.0
	if axis == SeamlessRoomSeam.AXIS_X:
		if not is_equal_approx(low.end.x, high.position.x):
			return
		at = low.end.x
		from = maxf(low.position.y, high.position.y)
		to = minf(low.end.y, high.end.y)
	else:
		if not is_equal_approx(low.end.y, high.position.y):
			return
		at = low.end.y
		from = maxf(low.position.x, high.position.x)
		to = minf(low.end.x, high.end.x)
	if not (to - from > 0.001):   # 角接触不算共享边
		return

	var key := SeamlessRoomSeam.make_key(a, b, axis)
	if seen.has(key):
		return
	seen[key] = true
	out.append({
		"key": key, "axis": axis, "at": at, "from": from, "to": to,
		"span": to - from, "low_id": low_id, "high_id": high_id,
	})


## 与某间房相关的共享边，并附带本房间在边上的方向：
## room_side = +1 表示本房间在 low 侧，-1 表示在 high 侧。
## 供 SeamlessRoomParallax 做背景边缘渐隐（side 决定衰减方向）。
func seams_for_room(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in seams():
		var side := 0.0
		if e["low_id"] == id:
			side = 1.0
		elif e["high_id"] == id:
			side = -1.0
		else:
			continue
		var item: Dictionary = e.duplicate()
		item["room_side"] = side
		out.append(item)
	return out


## 该房间相关的边 + 对应 seam 配置（仅 enabled），FADE 模式注入用。
## 把 width / core / feather 一并带出去，房间侧不需要再认识 config。
func seam_fades_for_room(id: StringName) -> Array[Dictionary]:
	var by_key := {}
	if config != null:
		for s in config.seam_configs():
			by_key[s.key()] = s
	var out: Array[Dictionary] = []
	for e in seams_for_room(id):
		var s: SeamlessRoomSeam = by_key.get(e["key"], null)
		if s == null or not s.enabled:
			continue
		var item: Dictionary = e.duplicate()
		item["width_ratio"] = s.width_ratio
		item["width_max"] = s.width_max
		item["core"] = s.core
		item["feather"] = s.feather_min if e["room_side"] > 0.0 else s.feather_max
		out.append(item)
	return out


## 纯几何换算：房间局部坐标 → 世界坐标。不移动任何节点。
func to_world(id: StringName, local_pos: Vector2) -> Vector2:
	return world_rect(id).position + local_pos


func world_to_room(world_pos: Vector2) -> Dictionary:
	var id := room_at(world_pos)
	if id == &"":
		return {}
	return { "id": id, "local": world_pos - world_rect(id).position }


## O(1) 定位：先由 floori 找到索引桶，再在候选里用世界矩形精判。
## 用桶而不是格，所以 cell_size 细到 1px 也不影响查询成本。
func room_at(world_pos: Vector2) -> StringName:
	var c := Vector2i(
		floori(world_pos.x / _bucket_size),
		floori(world_pos.y / _bucket_size)
	)
	for raw in _buckets.get(c, []):
		var id := StringName(raw)
		if world_rect(id).has_point(world_pos):
			return id
	return &""


## 半径预算：枚举桶数 ≈ (2r/B+1)²，反推出不超过 MAX_QUERY_BUCKETS 的最大半径。
static func max_query_radius(bucket_size: float) -> float:
	return (sqrt(float(MAX_QUERY_BUCKETS)) - 1.0) * bucket_size * 0.5


## 邻域查询：返回半径内「可能相关」的房间 id（保守超集，调用方再精筛）。
## 桶数与半径平方成正比，与网格粒度、世界总房间数无关；超预算时截断半径并告警。
func query_near(world_pos: Vector2, radius: float) -> Array[StringName]:
	var out: Array[StringName] = []
	# NaN / 0 / 负数不枚举（NaN 的比较恒为 false）；INF 由下面的预算截断。
	if not (radius > 0.0):
		return out
	var max_radius := max_query_radius(_bucket_size)
	if radius > max_radius:
		push_warning(SeamlessRoomI18n.tf(
				"query_near: radius %.1f exceeds the bucket budget; clamped to %.1f",
				[radius, max_radius]))
		radius = max_radius
	var seen: Dictionary = {}
	var lo := Vector2i(
		floori((world_pos.x - radius) / _bucket_size),
		floori((world_pos.y - radius) / _bucket_size)
	)
	var hi := Vector2i(
		floori((world_pos.x + radius) / _bucket_size),
		floori((world_pos.y + radius) / _bucket_size)
	)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for raw in _buckets.get(Vector2i(x, y), []):
				var id := StringName(raw)
				if not seen.has(id):
					seen[id] = true
					out.append(id)
	return out


## 最近房间：给「玩家在房间外」的策略用。仍只枚举邻域桶，不遍历全世界。
## radius <= 0 表示按地图包围盒长边自动取搜索半径，不绑定任何示例世界尺寸。
## radius 内没有任何房间时返回空 StringName。
func nearest_room(world_pos: Vector2, radius: float = -1.0) -> StringName:
	if radius <= 0.0:
		radius = maxf(_world_bounds.size.x, _world_bounds.size.y)
	var best := &""
	var best_d := INF
	for id in query_near(world_pos, radius):
		var r := world_rect(id)
		var q := Vector2(
			clampf(world_pos.x, r.position.x, r.end.x),
			clampf(world_pos.y, r.position.y, r.end.y)
		)
		var d := world_pos.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = id
	return best


## 与 id 边贴合连通的房间矩形集合（纯几何，不含可达性语义）。
## 连续滚动用这组矩形做「视图覆盖检测」，而不是它们的包围盒 —— L 形拼接时
## 包围盒会把凹处的空白也算成房间，矩形集合不会。
func touching_rects(id: StringName) -> Array[Rect2]:
	if not _by_id.has(id):
		return []
	var out: Array[Rect2] = [world_rect(id)]
	var visited: Dictionary = { id: true }
	var queue: Array[StringName] = [id]
	while not queue.is_empty():
		var cur: StringName = queue.pop_back()
		var r := world_rect(cur)
		# 只与「边界附近桶」里的房间比较，不再全表扫描 O(N²)。
		for other in _nearby_ids(r):
			if visited.has(other):
				continue
			var ro := world_rect(other)
			if _rects_touch(r, ro):
				visited[other] = true
				queue.append(other)
				out.append(ro)
	return out


## 矩形外扩一个桶范围内登记过的所有 id。两个房间若边贴合，共享边上的点
## 所在的桶必然被两者都登记，因此外扩一格足以找到全部连通候选。
func _nearby_ids(r: Rect2) -> Array[StringName]:
	var out: Array[StringName] = []
	var seen: Dictionary = {}
	var lo := Vector2i(
		floori((r.position.x - _bucket_size) / _bucket_size),
		floori((r.position.y - _bucket_size) / _bucket_size)
	)
	var hi := Vector2i(
		floori((r.end.x + _bucket_size) / _bucket_size),
		floori((r.end.y + _bucket_size) / _bucket_size)
	)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for raw in _buckets.get(Vector2i(x, y), []):
				var id := StringName(raw)
				if not seen.has(id):
					seen[id] = true
					out.append(id)
	return out


## 覆盖区的包围盒，只用于 limit_* 粗约束 / auto_fit 缩放 / HUD 数值。
## 真正的「视图是否合法」由 view_covered() 按矩形集合判定。
func touching_bounds(id: StringName) -> Rect2:
	var rects := touching_rects(id)
	if rects.is_empty():
		return Rect2()
	var out: Rect2 = rects[0]
	for i in range(1, rects.size()):
		out = out.merge(rects[i])
	return out


## 一次遍历全图，返回所有连通分量的矩形集合，供启动期批量预计算合法区域。
## 每个房间只被访问一次，总成本与桶近邻候选数量成正比，而不是 O(N²)。
func connected_groups() -> Array:
	var visited: Dictionary = {}
	var out: Array = []
	for raw in _by_id.keys():
		var start := StringName(raw)
		if visited.has(start):
			continue
		visited[start] = true
		var rects: Array[Rect2] = []
		var queue: Array[StringName] = [start]
		while not queue.is_empty():
			var cur: StringName = queue.pop_back()
			var r := world_rect(cur)
			rects.append(r)
			for other in _nearby_ids(r):
				if visited.has(other):
					continue
				if _rects_touch(r, world_rect(other)):
					visited[other] = true
					queue.append(other)
		out.append(rects)
	return out


## 视图矩形是否被房间矩形并集完全覆盖：逐块做矩形差集，剩下任何一块即未覆盖。
## 1px 容差：浮点换算产生的细条不算漏出。
static func view_covered(view: Rect2, rects: Array) -> bool:
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return true
	const EPS := 1.0
	var remain: Array[Rect2] = [view]
	for raw in rects:
		var r: Rect2 = raw
		var next: Array[Rect2] = []
		for piece in remain:
			var lo := Vector2(maxf(piece.position.x, r.position.x), maxf(piece.position.y, r.position.y))
			var hi := Vector2(minf(piece.end.x, r.end.x), minf(piece.end.y, r.end.y))
			# 交集窄于容差视为浮点误差：整块保留，交给后续房间处理。
			# 否则 L 形拼接的边界会产生 0.25px 的残留细条，被误判成空白。
			if hi.x <= lo.x or hi.y <= lo.y \
					or hi.x - lo.x <= EPS or hi.y - lo.y <= EPS:
				next.append(piece)
				continue
			# piece 减掉交集，切成上 / 下 / 左 / 右四块（不重叠）。
			if piece.position.y < lo.y - EPS:
				next.append(Rect2(piece.position.x, piece.position.y, piece.size.x, lo.y - piece.position.y))
			if piece.end.y > hi.y + EPS:
				next.append(Rect2(piece.position.x, hi.y, piece.size.x, piece.end.y - hi.y))
			if piece.position.x < lo.x - EPS:
				next.append(Rect2(piece.position.x, lo.y, lo.x - piece.position.x, hi.y - lo.y))
			if piece.end.x > hi.x + EPS:
				next.append(Rect2(hi.x, lo.y, piece.end.x - hi.x, hi.y - lo.y))
		remain = next
		if remain.is_empty():
			return true
	return false


## 两矩形是否共享一段边（不只是角接触）。
static func _rects_touch(a: Rect2, b: Rect2) -> bool:
	const EPS := 0.001
	var x_edge := is_equal_approx(a.end.x, b.position.x) or is_equal_approx(b.end.x, a.position.x)
	var y_shared := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y) > EPS
	var y_edge := is_equal_approx(a.end.y, b.position.y) or is_equal_approx(b.end.y, a.position.y)
	var x_shared := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x) > EPS
	return (x_edge and y_shared) or (y_edge and x_shared)


func _v2(v: Vector2i) -> Vector2:
	return Vector2(float(v.x), float(v.y))
