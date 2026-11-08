@tool
extends "res://addons/room_atlas/runtime/room_atlas_room2d.gd"

## 示例房间底板：继承插件基类（id / 尺寸 / 编辑器边界预览），
## 额外画自己的矩形、地面与标签。
## 这里用路径继承以避免依赖全局 class_name 缓存；自建房间直接
## `extends RoomAtlasRoom2D` 即可。
##
## 每个房间是独立的 .tscn，根节点挂本脚本，子节点树各不相同（平台 / 装饰）。
## 这里没有侧墙：房间靠网格边界自然连通，插件不生成墙 / 门洞数据。
## room_id / room_title / room_size 由基类声明；运行时几何只认
## RoomAtlasPlacement.cells，由 configure() 注入。

var _size := Vector2(2400, 1080)
var _tint := Color(0.18, 0.22, 0.28)


func _ready() -> void:
	# 编辑器预览按场景自己声明的尺寸画底板；运行时会被 configure() 覆盖。
	_size = Vector2(float(room_size.x), float(room_size.y))
	queue_redraw()


func configure(p_id: StringName, p_placement: Resource, p_cell_size: Vector2) -> void:
	super.configure(p_id, p_placement, p_cell_size)
	if p_placement != null:
		var cells: Rect2i = p_placement.get("cells")
		_tint = p_placement.get("tint")
		_size = Vector2(float(cells.size.x), float(cells.size.y)) * p_cell_size
	_build_ground()
	queue_redraw()


func _build_ground() -> void:
	var floor_y := _size.y * 0.75
	var body := get_node_or_null("Ground") as StaticBody2D
	if body == null:
		body = StaticBody2D.new()
		body.name = "Ground"
		add_child(body)
		var shape_node := CollisionShape2D.new()
		shape_node.name = "Shape"
		shape_node.shape = RectangleShape2D.new()
		body.add_child(shape_node)
	body.position = Vector2(_size.x * 0.5, floor_y + 30.0)
	var cs := body.get_node_or_null("Shape") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		(cs.shape as RectangleShape2D).size = Vector2(_size.x, 60.0)


func _draw() -> void:
	# 先让基类画编辑器边界预览（运行时自动跳过），再画示例内容。
	super()
	var floor_y := _size.y * 0.75
	draw_rect(Rect2(Vector2.ZERO, Vector2(_size.x, floor_y)), _tint, true)
	draw_rect(Rect2(Vector2(0, floor_y), Vector2(_size.x, _size.y - floor_y)),
			Color(0.10, 0.11, 0.14), true)
	draw_line(Vector2(0, floor_y), Vector2(_size.x, floor_y),
			Color(0.38, 0.85, 0.62), 3.0)
	draw_rect(Rect2(Vector2.ZERO, _size), Color(1, 1, 1, 0.14), false, 2.0)
	var title := room_title if not room_title.is_empty() else String(room_id).to_upper()
	draw_string(ThemeDB.fallback_font, Vector2(28, 54),
			title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
			Color(1, 1, 1, 0.65))
