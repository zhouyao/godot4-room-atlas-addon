extends Node

## 房间实体供给器：把已挂载房间里的出生点实例化到 Main/Actors。
## 房间只负责“内容 + 出生点”，实体的生命周期跟 streamer 的挂载状态走：
##   room_mounted → 生成；room_sleeping → 回收；room_unloaded → 已经被回收。
## 这样 100 间房在编辑期各自独立，运行期只处理 max_mounted 间房。

@export var streamer: SeamlessRoomStreamer
@export var actors: Node2D
@export var player: Node2D
## 怪物死亡时掉落的场景；留空则不生成掉落物。
@export var pickup_scene: PackedScene

## key = "room_id/出生点节点名"；value = 运行时实例
var _spawned: Dictionary = {}
## 简单的 demo 状态：宝箱开合、掉落物已拾取、精英怪已死亡。
## 正式项目换成存档单例，key 的格式保持不变即可。
var _flags: Dictionary = {}
var _drop_seq := 0


func _ready() -> void:
	if streamer == null or actors == null:
		push_error("[RoomEntityDirector] streamer / actors 未注入。")
		return
	streamer.room_mounted.connect(_on_room_mounted)
	streamer.room_sleeping.connect(_on_room_sleeping)
	# 开局补生成：controller.setup() 里已经 ensure_room(start_room)，
	# 如果本节点加得晚，就错过了那一次 room_mounted。
	for id in streamer.mounted_ids():
		_on_room_mounted(id)


func _on_room_mounted(room_id: StringName) -> void:
	var room := streamer.mounted_room(room_id)
	if room == null:
		return
	var spawns := room.get_node_or_null("World/Spawns")
	if spawns == null:
		return
	for marker in spawns.get_children():
		if marker is EnemySpawn:
			_spawn_enemy(room_id, marker as EnemySpawn)
		elif marker is ChestSpawn:
			_spawn_chest(room_id, marker as ChestSpawn)
		elif marker is PickupSpawn:
			_spawn_pickup(room_id, marker as PickupSpawn)


func _on_room_sleeping(room_id: StringName) -> void:
	# room_sleeping 发出时房间已经不在 mounted 里，所以只靠实例自身的 home_room 回收。
	for key in _spawned.keys():
		var node: Node = _spawned[key]
		if not is_instance_valid(node):
			_spawned.erase(key)
			continue
		if node.get_meta(&"home_room", &"") != room_id:
			continue
		node.queue_free()
		_spawned.erase(key)


# ---------------------------------------------------------------- 生成

func _spawn_enemy(room_id: StringName, marker: EnemySpawn) -> void:
	var key := _key(room_id, marker)
	if _spawned.has(key):
		return
	if not marker.respawn and _flags.get(key, &"") == &"dead":
		return
	if marker.enemy_scene == null:
		return
	var enemy := marker.enemy_scene.instantiate()
	if enemy == null:
		return
	enemy.name = StringName("%s_%s" % [room_id, marker.name])
	actors.add_child(enemy)
	enemy.global_position = marker.global_position
	if enemy.has_method(&"setup"):
		enemy.call(&"setup", room_id, marker, player)
	var respawn := marker.respawn
	if enemy.has_signal(&"died"):
		enemy.connect(&"died", func() -> void:
			_on_enemy_died(enemy, key, room_id, respawn))
	_track(key, room_id, enemy)


func _spawn_chest(room_id: StringName, marker: ChestSpawn) -> void:
	var key := _key(room_id, marker)
	if _spawned.has(key) or marker.chest_scene == null:
		return
	var chest := marker.chest_scene.instantiate()
	if chest == null:
		return
	chest.name = StringName("%s_%s" % [room_id, marker.name])
	actors.add_child(chest)
	chest.global_position = marker.global_position
	chest.set(&"state_key", key)
	if chest.has_method(&"set_opened"):
		chest.call(&"set_opened", bool(_flags.get(key, false)))
	if chest.has_signal(&"opened_changed"):
		chest.connect(&"opened_changed", func(value: bool) -> void:
			_flags[key] = value)
	_track(key, room_id, chest)


func _spawn_pickup(room_id: StringName, marker: PickupSpawn) -> void:
	var key := _key(room_id, marker)
	if _spawned.has(key) or marker.pickup_scene == null:
		return
	if _flags.get(key, &"") == &"taken":
		return
	var pickup := marker.pickup_scene.instantiate()
	if pickup == null:
		return
	pickup.name = StringName("%s_%s" % [room_id, marker.name])
	actors.add_child(pickup)
	pickup.global_position = marker.global_position
	if pickup.has_signal(&"collected"):
		pickup.connect(&"collected", func() -> void:
			_flags[key] = &"taken")
	_track(key, room_id, pickup)


func _track(key: StringName, room_id: StringName, node: Node) -> void:
	node.set_meta(&"home_room", room_id)
	_spawned[key] = node
	node.tree_exited.connect(func() -> void:
		_spawned.erase(key))


# ---------------------------------------------------------------- 战斗 / 掉落

func _on_enemy_died(enemy: Node2D, key: StringName, room_id: StringName,
		respawn: bool) -> void:
	if not respawn:
		_flags[key] = &"dead"
	_drop_at(enemy.global_position, room_id)


func _drop_at(world_pos: Vector2, room_id: StringName) -> void:
	if pickup_scene == null:
		return
	var drop := pickup_scene.instantiate()
	if drop == null:
		return
	var seq := _drop_seq
	_drop_seq += 1
	var key := StringName("%s/drop_%d" % [room_id, seq])
	drop.name = StringName("%s_drop_%d" % [room_id, seq])
	actors.add_child(drop)
	drop.global_position = world_pos
	_track(key, room_id, drop)


## demo 用：K 键打最近的怪；正式项目换成玩家攻击判定。
func damage_nearest_enemy(origin: Vector2, amount: float, radius: float = 600.0) -> bool:
	var best: Node = null
	var best_dist := radius * radius
	for node in _spawned.values():
		if not is_instance_valid(node) or not node.has_method(&"take_damage"):
			continue
		var target := node as Node2D
		if target == null:
			continue
		var dist := origin.distance_squared_to(target.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = node
	if best == null:
		return false
	best.call(&"take_damage", amount)
	return true


# ---------------------------------------------------------------- 查询

func enemy_count() -> int:
	var count := 0
	for node in _spawned.values():
		if is_instance_valid(node) and node.has_method(&"take_damage"):
			count += 1
	return count


func spawned_count() -> int:
	return _spawned.size()


func _key(room_id: StringName, marker: Node) -> StringName:
	return StringName("%s/%s" % [room_id, marker.name])
