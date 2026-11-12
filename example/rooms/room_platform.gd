@tool
extends StaticBody2D

## 示例房间里的可站立平台：编辑器里画外观，运行时补碰撞形状。
## 每个房间 .tscn 用不同数量 / 位置 / 颜色的节点摆出自己的内容。

@export var size: Vector2 = Vector2(220, 24)
@export var color: Color = Color(0.42, 0.75, 0.9)


func _ready() -> void:
	# 编辑器里只做视觉预览，避免往场景树里塞不会保存的动态子节点。
	if not Engine.is_editor_hint():
		_ensure_shape()
	queue_redraw()


func _ensure_shape() -> void:
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "Shape"
		add_child(cs)
	if not (cs.shape is RectangleShape2D):
		cs.shape = RectangleShape2D.new()
	(cs.shape as RectangleShape2D).size = size


func _draw() -> void:
	draw_rect(Rect2(-size * 0.5, size), color, true)
	draw_rect(Rect2(-size * 0.5, size), Color(1, 1, 1, 0.35), false, 2.0)
