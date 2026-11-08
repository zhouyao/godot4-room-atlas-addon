class_name RoomAtlasStreamer
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

var layout: RoomAtlasLayout

var _tracked: Node2D = null
var _mounted: Dictionary = {}      # StringName -> Node
var _sleeping: Dictionary = {}     # StringName -> Node
var _loading: Dictionary = {}      # StringName -> true
var _requesting: Dictionary = {}   # path -> StringName
var _cache: Dictionary = {}        # path -> PackedScene
var _tick := 0.0


# ---------------------------------------------------------------- 装配 / 查询

func configure(p_config: RoomAtlasConfig) -> void:
	_clear_all()
	layout = RoomAtlasLayout.new(p_config)


## 注入"以谁为中心加载"。可以是玩家，也可以是镜头、载具或任意节点。
func track(target: Node2D) -> void:
	_tracked = target


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
		_cache[path] = packed
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
			_cache[path] = packed
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
				_cache[path] = packed
				_mount_now(id)
			else:
				room_load_failed.emit(id, path)
		else:
			room_load_failed.emit(id, path)


func _update_streaming() -> void:
	var p := _tracked.global_position
	var s := layout.streaming()

	# 挂载：只枚举邻域，不遍历全世界。
	for id in layout.query_near(p, s.mount_distance):
		if _mounted.has(id) or _loading.has(id):
			continue
		if _dist_to_rect(p, world_rect(id)) > s.mount_distance:
			continue
		request_room(id)

	# 休眠：远离就停画、停脚本、停碰撞。
	for id in _mounted.keys():
		if _dist_to_rect(p, world_rect(id)) > s.sleep_distance:
			_sleep(id)

	# 卸载：休眠且更远才真正释放节点。
	for id in _sleeping.keys():
		if _dist_to_rect(p, world_rect(id)) > s.unload_distance:
			_unload(id)

	# 预算保护：超出上限时休眠最远的一个。
	while _mounted.size() > s.max_mounted:
		var far := &""
		var far_d := -1.0
		for id in _mounted.keys():
			var d := _dist_to_rect(p, world_rect(id))
			if d > far_d:
				far_d = d
				far = id
		if far == &"":
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
