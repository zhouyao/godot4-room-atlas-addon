@tool
class_name RoomAtlasLayout
extends RefCounted

## 把配置变成可查询的几何：世界矩形、坐标换算、空间索引。
## 纯数据层，不进场景树，不加载任何场景。

## 空间索引桶尺寸（世界像素），与 cell_size 完全解耦。
## 网格可以细到 1px，索引桶数仍然是常数。
const BUCKET_SIZE := 600.0

var config: RoomAtlasConfig

var _by_id: Dictionary = {}
var _buckets: Dictionary = {}  # Vector2i(桶坐标) -> Array[StringName]
var _cell_size := Vector2(1, 1)
var _streaming: RoomAtlasStreamingSettings = null


func _init(p_config: RoomAtlasConfig = null) -> void:
	if p_config != null:
		configure(p_config)


func configure(p_config: RoomAtlasConfig) -> void:
	config = p_config
	_by_id.clear()
	_buckets.clear()
	if p_config.cell_size.x > 0.0 and p_config.cell_size.y > 0.0:
		_cell_size = p_config.cell_size
	_streaming = p_config.streaming if p_config.streaming != null \
			else RoomAtlasStreamingSettings.new()

	for p in p_config.placements():
		if p.id == &"":
			continue
		_by_id[p.id] = p
		# 按空间索引桶登记，而不是逐格登记：
		# 即便 cell_size = 1px，一间房也只占几个桶。
		var r := world_rect(p.id)
		var lo := Vector2i(
			floori(r.position.x / BUCKET_SIZE),
			floori(r.position.y / BUCKET_SIZE)
		)
		# -0.001：房间矩形是半开区间，边界正好落在桶线上时不多登记一个桶。
		var hi := Vector2i(
			floori((r.end.x - 0.001) / BUCKET_SIZE),
			floori((r.end.y - 0.001) / BUCKET_SIZE)
		)
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var k := Vector2i(x, y)
				if not _buckets.has(k):
					_buckets[k] = []
				_buckets[k].append(p.id)


func cell_size() -> Vector2:
	return _cell_size


func streaming() -> RoomAtlasStreamingSettings:
	return _streaming


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _by_id.keys():
		out.append(id)
	return out


func has_room(id: StringName) -> bool:
	return _by_id.has(id)


func placement(id: StringName) -> RoomAtlasPlacement:
	return _by_id.get(id, null)


func scene_path(id: StringName) -> String:
	var p: RoomAtlasPlacement = _by_id.get(id, null)
	if p == null or p.scene == null:
		return ""
	return p.scene.resource_path


func world_rect(id: StringName) -> Rect2:
	var p: RoomAtlasPlacement = _by_id.get(id, null)
	if p == null:
		return Rect2()
	return Rect2(_v2(p.cells.position) * _cell_size, _v2(p.cells.size) * _cell_size)


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
		floori(world_pos.x / BUCKET_SIZE),
		floori(world_pos.y / BUCKET_SIZE)
	)
	for raw in _buckets.get(c, []):
		var id := StringName(raw)
		if world_rect(id).has_point(world_pos):
			return id
	return &""


## 邻域查询：返回半径内「可能相关」的房间 id（保守超集，调用方再精筛）。
## 枚举范围是固定的几个桶，与网格粒度、世界里有多少房间都无关 —— 这是可无限扩展的关键。
func query_near(world_pos: Vector2, radius: float) -> Array[StringName]:
	var out: Array[StringName] = []
	var seen: Dictionary = {}
	var lo := Vector2i(
		floori((world_pos.x - radius) / BUCKET_SIZE),
		floori((world_pos.y - radius) / BUCKET_SIZE)
	)
	var hi := Vector2i(
		floori((world_pos.x + radius) / BUCKET_SIZE),
		floori((world_pos.y + radius) / BUCKET_SIZE)
	)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for raw in _buckets.get(Vector2i(x, y), []):
				var id := StringName(raw)
				if not seen.has(id):
					seen[id] = true
					out.append(id)
	return out


func _v2(v: Vector2i) -> Vector2:
	return Vector2(float(v.x), float(v.y))
