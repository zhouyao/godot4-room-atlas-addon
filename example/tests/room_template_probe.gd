extends SceneTree

## headless 自检：r1–r8 全部继承 room_template.tscn，且根节点身份由派生场景显式覆写。
## 运行：Godot --headless --path <proj> --script res://example/tests/room_template_probe.gd

const TEMPLATE := "res://example/rooms/room_template.tscn"

## 模板只放结构性契约节点，准入标准见 docs/parallax-convention.md §5。
const LAYERS: Array[String] = [
	"BgParallax",
	"BgParallax/Backdrop",
	"BgParallax/Far",
	"BgParallax/Far2",
	"BgParallax/Mid",
	"BgParallax/Near",
	"World",
	"World/Underlay",
	"World/Spawns",
	"FgParallax",
	"FgParallax/Occluders",
	"FgParallax/Foreground",
	"FgParallax/FG2",
	"FgParallax/FG3",
]

## 内容分类分组不属于模板，由需要的房间自行新增（目前只有 r1）。
const ROOM_GROUPS: Array[String] = [
	"World/Water",
	"World/Terrain",
	"World/Obstacles",
	"World/Props",
]

const ROOMS := [
	{"id": &"r1", "title": "R1", "size": Vector2i(3000, 1080)},
	{"id": &"r2", "title": "R2", "size": Vector2i(2400, 1080)},
	{"id": &"r3", "title": "R3", "size": Vector2i(2400, 1080)},
	{"id": &"r4", "title": "R4", "size": Vector2i(2400, 1080)},
	{"id": &"r5", "title": "R5", "size": Vector2i(2400, 2160)},
	{"id": &"r6", "title": "R6", "size": Vector2i(5400, 1080)},
	{"id": &"r7", "title": "R7", "size": Vector2i(4000, 1080)},
	{"id": &"r8", "title": "R8", "size": Vector2i(1920, 2160)},
]

var _failed := 0


func _initialize() -> void:
	_check_template()
	for info in ROOMS:
		_check_room(info)
	print("[Seamless Rooms] 房间模板自检：%s" % ("全部通过" if _failed == 0 else "%d 项失败" % _failed))
	quit(1 if _failed > 0 else 0)


func _check_template() -> void:
	var packed := ResourceLoader.load(TEMPLATE) as PackedScene
	if packed == null:
		_check("room_template.tscn 加载成功", false)
		return
	var state := packed.get_state()
	_check("模板共 15 个节点（根 + 14 层）", state.get_node_count() == LAYERS.size() + 1)
	var only_layers := true
	for i in range(state.get_node_count()):
		var type := state.get_node_type(i)
		if type != "Node2D" and type != "Control":
			only_layers = false
	_check("模板无 Sprite / ColorRect / 碰撞体等内容节点", only_layers)
	var inst := packed.instantiate()
	if inst == null:
		_check("模板可实例化", false)
		return
	# 三个顶层 rig / 分组允许有层子节点，其余叶子层必须为空容器。
	var empty := true
	var leaf_count := 0
	for path in LAYERS:
		var layer: Node = inst.get_node_or_null(NodePath(path))
		if path.contains("/"):
			leaf_count += 1
		if layer == null or (path.contains("/") and layer.get_child_count() != 0):
			empty = false
	_check("模板 %d 个叶子层都是空容器" % leaf_count, empty)
	_check("模板不含 Water / Terrain / Obstacles / Props 等内容分组",
			_no_room_groups(inst))
	_check("模板根节点挂 SeamlessRoom2D",
			inst.get("room_title") == "Room Template" and inst.get("room_id") == &"")
	inst.free()


func _check_room(info: Dictionary) -> void:
	var id := String(info["id"])
	var path := "res://example/rooms/%s.tscn" % id
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		_check(id + " 场景加载成功", false)
		return

	# dock 只读 PackedScene.get_state() 根节点属性，三项必须由派生场景显式覆写。
	var state := packed.get_state()
	var props := {}
	for i in range(state.get_node_property_count(0)):
		props[String(state.get_node_property_name(0, i))] = state.get_node_property_value(0, i)
	_check(id + " 根节点显式声明 room_id",
			props.has("room_id") and StringName(String(props["room_id"])) == info["id"])
	_check(id + " 根节点显式声明 room_title",
			props.has("room_title") and String(props["room_title"]) == info["title"])
	_check(id + " 根节点显式声明 room_size",
			props.has("room_size") and props["room_size"] == info["size"])

	var inst := packed.instantiate()
	if inst == null:
		_check(id + " 场景可实例化", false)
		return
	for layer in LAYERS:
		_check("%s 继承层 %s 存在" % [id, layer],
				inst.get_node_or_null(NodePath(layer)) != null)
	_check(id + " BgParallax/Far.scroll_scale == (0.55, 0.55)",
			_prop(inst.get_node_or_null("BgParallax/Far"), "scroll_scale", Vector2(0.55, 0.55)))
	_check(id + " FgParallax/FG3.scroll_scale == (1.3, 1.3)",
			_prop(inst.get_node_or_null("FgParallax/FG3"), "scroll_scale", Vector2(1.3, 1.3)))
	_check(id + " World/Underlay.z_index == -10",
			_prop(inst.get_node_or_null("World/Underlay"), "z_index", -10))
	_check(id + " BgParallax.z_index == -100",
			_prop(inst.get_node_or_null("BgParallax"), "z_index", -100))
	_check(id + " FgParallax.z_index == 100",
			_prop(inst.get_node_or_null("FgParallax"), "z_index", 100))
	_check(id + " World/Spawns 是 Node2D",
			inst.get_node_or_null("World/Spawns") is Node2D)
	var backdrop: Node = inst.get_node_or_null("BgParallax/Backdrop")
	_check(id + " Backdrop 是房间固定静态层（无 layer 脚本 / 无 z 覆写）",
			backdrop != null and backdrop.get_script() == null
					and _prop(backdrop, "z_index", 0))

	if id == "r1":
		for group in ROOM_GROUPS:
			_check("r1 自建分组 %s 存在且是 Node2D" % group,
					inst.get_node_or_null(NodePath(group)) is Node2D)
		_check("r1 World/Spawns/EnemySpawn_01 保留",
				inst.get_node_or_null("World/Spawns/EnemySpawn_01") != null)
		_check("r1 BgParallax/Backdrop/Darkness 保留",
				inst.get_node_or_null("BgParallax/Backdrop/Darkness") != null)
		var spawns: Node = inst.get_node_or_null("World/Spawns")
		_check("r1 World/Spawns 子节点数 == 4",
				spawns != null and spawns.get_child_count() == 4)
		var water: Node = inst.get_node_or_null("World/Water")
		_check("r1 World/Water 4 个水面动画仍在",
				water != null and water.get_child_count() == 4)
		var terrain: Node = inst.get_node_or_null("World/Terrain")
		_check("r1 World/Terrain 地形贴图仍在",
				terrain != null and terrain.get_child_count() > 0)
		var obstacles: Node = inst.get_node_or_null("World/Obstacles")
		_check("r1 World/Obstacles 5 组碰撞体仍在",
				obstacles != null and obstacles.get_child_count() == 5)
	else:
		var spawns: Node = inst.get_node_or_null("World/Spawns")
		_check(id + " 无房间内容（Spawns 为空）",
				spawns != null and spawns.get_child_count() == 0)
		_check(id + " 不含 r1 的内容分组", _no_room_groups(inst))
	inst.free()


func _no_room_groups(inst: Node) -> bool:
	for group in ROOM_GROUPS:
		if inst.get_node_or_null(NodePath(group)) != null:
			return false
	return true


func _prop(node: Node, prop: String, expected: Variant) -> bool:
	if node == null:
		return false
	var value: Variant = node.get(prop)
	if value is Vector2 and expected is Vector2:
		return is_equal_approx(value.x, expected.x) and is_equal_approx(value.y, expected.y)
	return value == expected


func _check(label: String, ok: bool) -> void:
	if ok:
		print("OK    ", label)
	else:
		_failed += 1
		push_error("FAIL  " + label)
