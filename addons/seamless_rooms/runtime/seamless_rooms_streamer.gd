class_name SeamlessRoomStreamer
extends Node

## 距离驱动的房间供给器。
##
## 只做两件事：按跟踪目标的位置维护房间生命周期；提供纯几何 / 生命周期查询。
## 不认识玩家、不移动任何节点、不表达连通性、不提供"传送"这种玩法语义。
##
## 生命周期：未加载 → 线程加载中 → 已挂载 → 休眠 → 释放节点。
## PackedScene 留在 _cache 里，所以释放的只是实例，回来时不用重新读盘。

signal room_mounted(id: StringName)
signal room_sleeping(id: StringName)
signal room_unloaded(id: StringName)
signal room_load_failed(id: StringName, path: String)

var layout: SeamlessRoomLayout

var _tracked: Node2D = null
var _mounted: Dictionary = {}      # StringName -> Node
var _sleeping: Dictionary = {}     # StringName -> Node
var _loading: Dictionary = {}      # StringName -> true
var _requesting: Dictionary = {}   # path -> StringName
var _cache: Dictionary = {}        # path -> PackedScene
var _cache_lru: Array[String] = [] # 最近使用的 path 在前，用于 LRU 淘汰
var _tick := 0.0
## 运行期有效距离：由游戏层 set_load_radius() 注入，绝不写回 .tres。
## 未注入时等于配置基准，行为与静态配置完全一致。
var _effective_mount := 0.0
var _effective_sleep := 0.0
var _effective_unload := 0.0
var _auto_max_mounted := false


# ---------------------------------------------------------------- 装配 / 查询

func configure(p_config: SeamlessRoomConfig) -> void:
	_clear_all()
	_cache.clear()
	_cache_lru.clear()
	SeamlessRoomCameraRegion.clear_cache()
	layout = SeamlessRoomLayout.new(p_config)
	var s := layout.streaming()
	_auto_max_mounted = s.max_mounted <= 0
	_effective_mount = s.mount_distance
	_effective_sleep = s.sleep_distance
	_effective_unload = s.unload_distance


## 注入"以谁为中心加载"。可以是玩家，也可以是镜头、载具或任意节点。
func track(target: Node2D) -> void:
	_tracked = target


## 启动期 / 分辨率切换时预热所有连通分量的合法区域，把首次切房的坐标压缩
## 开销前移到配置加载或视口尺寸稳定阶段；运行期切房只查缓存。
func precompute_regions(view_size: Vector2) -> void:
	if layout == null or view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	for group in layout.connected_groups():
		SeamlessRoomCameraRegion.precompute(group, view_size)


## 注入「一次要提前加载多远」（世界像素）。半径由认识视口 / 相机 / 玩家的
## 游戏层算好；插件不推算视口，只把它限制在 [配置下限, query_near 桶预算] 内，
## 再按同一比例派生 sleep / unload，保持滞回带形状不变。
func set_load_radius(radius: float) -> void:
	if layout == null or not (radius > 0.0):  # NaN / 0 / 负数一律忽略
		return
	var s := layout.streaming()
	var base := maxf(s.mount_distance, 1.0)
	# 配置的 bucket_size 可能是 0（自动推导），必须用 layout 实际采用的值。
	var upper := maxf(SeamlessRoomLayout.max_query_radius(layout.bucket_size()), base)
	var mount := clampf(radius, base, upper)  # INF 会被夹到 upper，不会挂死
	var ratio := mount / base
	_effective_mount = mount
	_effective_sleep = s.sleep_distance * ratio
	_effective_unload = s.unload_distance * ratio


## 只读：当前生效的三个距离，供自检 / HUD 使用。
func effective_distances() -> Dictionary:
	return {
		"mount": _effective_mount,
		"sleep": _effective_sleep,
		"unload": _effective_unload,
	}


## 只读：当前生效的同时挂载上限（自动派生或配置值），供自检 / HUD 使用。
func mount_budget() -> int:
	return _mount_budget() if layout != null else 0


## 自动派生同时挂载上限：按有效半径覆盖的圆面积与平均房间面积估算，
## 留一倍余量，并以地图房间总数为上界（静态地图可控）。
func _mount_budget() -> int:
	if not _auto_max_mounted:
		return maxi(layout.streaming().max_mounted, 1)
	var r := _effective_mount
	var est := ceili(PI * r * r / layout.average_room_area() * 2.0) + 4
	return clampi(est, 4, maxi(layout.room_count(), 4))


func _cache_put(path: String, packed: PackedScene) -> void:
	_cache[path] = packed
	_cache_touch(path)
	_trim_cache()


func _cache_touch(path: String) -> void:
	if path.is_empty() or not _cache.has(path):
		return
	_cache_lru.erase(path)
	_cache_lru.push_front(path)


## 缓存上界随挂载预算变化；淘汰最久未使用的 PackedScene，已实例化的节点不受影响。
func _trim_cache() -> void:
	var budget := maxi(_mount_budget() * 2, 8)
	while _cache.size() > budget and not _cache_lru.is_empty():
		var old: String = _cache_lru.pop_back()
		_cache.erase(old)


func world_rect(id: StringName) -> Rect2:
	return layout.world_rect(id) if layout != null else Rect2()


func to_world(id: StringName, local_pos: Vector2) -> Vector2:
	return layout.to_world(id, local_pos) if layout != null else local_pos


## 世界坐标 → 房间局部信息。刻意不叫 to_local：那是 Node2D 的坐标变换方法，
## 语义完全不同（这里返回 { id, local }，不是 Vector2）。
func world_to_room(world_pos: Vector2) -> Dictionary:
	return layout.world_to_room(world_pos) if layout != null else {}


func room_at(world_pos: Vector2) -> StringName:
	return layout.room_at(world_pos) if layout != null else &""


func is_mounted(id: StringName) -> bool:
	return _mounted.has(id)


func is_loading(id: StringName) -> bool:
	return _loading.has(id)


func mounted_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _mounted.keys():
		out.append(id)
	return out


## 只读查询：已挂载的房间实例；休眠 / 未加载时返回 null。
## 游戏层用它读取房间自己声明的相机规则，插件不解释规则、不驱动相机。
func mounted_room(id: StringName) -> Node:
	return _mounted.get(id, null)


func nearest_room(world_pos: Vector2, radius: float = -1.0) -> StringName:
	return layout.nearest_room(world_pos, radius) if layout != null else &""


func touching_bounds(id: StringName) -> Rect2:
	return layout.touching_bounds(id) if layout != null else Rect2()


func touching_rects(id: StringName) -> Array[Rect2]:
	return layout.touching_rects(id) if layout != null else []


# ---------------------------------------------------------------- 生命周期 API

## 异步预载某房间（不等待）。用于提前准备，插件不知道调用方的意图。
func request_room(id: StringName) -> void:
	if layout == null or not layout.has_room(id):
		return
	if _mounted.has(id) or _loading.has(id):
		return
	if _sleeping.has(id):
		_mount_now(id)
		return
	var path := layout.scene_path(id)
	if path.is_empty():
		room_load_failed.emit(id, path)
		return
	if _cache.has(path):
		_mount_now(id)
		return
	_loading[id] = true
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		_loading.erase(id)
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			room_load_failed.emit(id, path)
			return
		_cache_put(path, packed)
		_mount_now(id)
		return
	_requesting[path] = id


## 同步保底：返回时目标房间一定已挂载（休眠的会被直接唤醒）。
## 游戏层在"把某个节点放到该房间"之前调用它，就不会出现落地踩空的一帧。
func ensure_room(id: StringName) -> void:
	if layout == null or not layout.has_room(id) or _mounted.has(id):
		return
	var path := layout.scene_path(id)
	if _requesting.has(path):
		_requesting.erase(path)
		_loading.erase(id)
	if not _sleeping.has(id) and not _cache.has(path) and not path.is_empty():
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed != null:
			_cache_put(path, packed)
	_mount_now(id)


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	if layout == null:
		return
	_poll_requests()
	if not is_instance_valid(_tracked):
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = maxf(layout.streaming().tick, 0.01)
	_update_streaming()


func _poll_requests() -> void:
	if _requesting.is_empty():
		return
	for path in _requesting.keys():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var id := StringName(_requesting[path])
		_requesting.erase(path)
		_loading.erase(id)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			if packed != null:
				_cache_put(path, packed)
				_mount_now(id)
			else:
				room_load_failed.emit(id, path)
		else:
			room_load_failed.emit(id, path)


func _update_streaming() -> void:
	var p := _tracked.global_position

	# 挂载：只枚举邻域，不遍历全世界。半径来自游戏层注入的有效值。
	for id in layout.query_near(p, _effective_mount):
		if _mounted.has(id) or _loading.has(id):
			continue
		if _dist_to_rect(p, world_rect(id)) > _effective_mount:
			continue
		request_room(id)

	# 休眠：远离就停画、停脚本、停碰撞。
	for id in _mounted.keys():
		if _dist_to_rect(p, world_rect(id)) > _effective_sleep:
			_sleep(id)

	# 卸载：休眠且更远才真正释放节点。
	for id in _sleeping.keys():
		if _dist_to_rect(p, world_rect(id)) > _effective_unload:
			_unload(id)

	# 预算保护：只休眠半径外的房间。若所有房间都还在半径内，说明上限偏小，
	# 保留全部并告警，避免「休眠 → 下一 tick 唤醒」的周期性抖动。
	var budget := _mount_budget()
	while _mounted.size() > budget:
		var far := &""
		var far_d := -1.0
		for id in _mounted.keys():
			var d := _dist_to_rect(p, world_rect(id))
			if d <= _effective_mount or d <= far_d:
				continue
			far_d = d
			far = id
		if far == &"":
			push_warning(SeamlessRoomI18n.tf(
					"Mount limit %d is smaller than the number of rooms in range; all rooms were kept",
					[budget]))
			break
		_sleep(far)


# ---------------------------------------------------------------- 内部

func _mount_now(id: StringName) -> void:
	if _mounted.has(id):
		return
	if _sleeping.has(id):
		var woken: Node = _sleeping[id]
		_sleeping.erase(id)
		_wake(woken)
		_mounted[id] = woken
		room_mounted.emit(id)
		return

	var path := layout.scene_path(id)
	var packed: PackedScene = _cache.get(path, null)
	if packed == null:
		return
	_cache_touch(path)
	var room := packed.instantiate()
	if room == null:
		room_load_failed.emit(id, path)
		return
	if room is Node2D:
		(room as Node2D).position = world_rect(id).position
	# 可选钩子：房间内容自己决定要不要用这些几何信息，插件不强制。
	if room.has_method("configure"):
		room.call("configure", id, layout.placement(id), layout.cell_size())
	add_child(room)
	_mounted[id] = room
	room_mounted.emit(id)


func _sleep(id: StringName) -> void:
	var n: Node = _mounted.get(id, null)
	if n == null:
		return
	if n is CanvasItem:
		(n as CanvasItem).visible = false
	n.process_mode = Node.PROCESS_MODE_DISABLED
	_set_collision(n, false)
	_mounted.erase(id)
	_sleeping[id] = n
	room_sleeping.emit(id)


func _wake(n: Node) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visible = true
	n.process_mode = Node.PROCESS_MODE_INHERIT
	_set_collision(n, true)


func _unload(id: StringName) -> void:
	var n: Node = _sleeping.get(id, null)
	if n == null:
		return
	_sleeping.erase(id)
	if is_instance_valid(n):
		n.queue_free()
	room_unloaded.emit(id)
	_trim_cache()


func _set_collision(root: Node, enabled: bool) -> void:
	for node in root.find_children("*", "CollisionShape2D", true, false):
		(node as CollisionShape2D).set_deferred(&"disabled", not enabled)


func _clear_all() -> void:
	for id in _mounted.keys():
		var n: Node = _mounted[id]
		if is_instance_valid(n):
			n.queue_free()
	for id in _sleeping.keys():
		var n: Node = _sleeping[id]
		if is_instance_valid(n):
			n.queue_free()
	_mounted.clear()
	_sleeping.clear()
	_loading.clear()
	_requesting.clear()


static func _dist_to_rect(p: Vector2, r: Rect2) -> float:
	var q := Vector2(
		clampf(p.x, r.position.x, r.end.x),
		clampf(p.y, r.position.y, r.end.y)
	)
	return p.distance_to(q)
