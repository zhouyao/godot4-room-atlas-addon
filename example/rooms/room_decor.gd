@tool
extends Node2D

## 示例房间装饰：柱子 / 灯 / 旗 / 水晶，按 kind 画不同形状。
## 纯视觉内容，不参与碰撞，也不含任何玩法逻辑。

@export var kind: StringName = &"pillar"
@export var color: Color = Color(0.85, 0.78, 0.5)
@export var size: Vector2 = Vector2(24, 120)


func _draw() -> void:
	match kind:
		&"pillar":
			draw_rect(Rect2(Vector2(-size.x * 0.5, -size.y), size), color, true)
			draw_rect(Rect2(-size.x * 0.7, -size.y - 10, size.x * 1.4, 12),
					Color(1, 1, 1, 0.35), true)
		&"lamp":
			draw_circle(Vector2.ZERO, size.x * 0.9, Color(color.r, color.g, color.b, 0.16))
			draw_circle(Vector2.ZERO, size.x * 0.45, color)
		&"banner":
			draw_rect(Rect2(-size.x * 0.5, -size.y * 0.5, size.x, size.y), color, true)
			draw_line(Vector2(0, -size.y * 0.5), Vector2(0, -size.y * 0.5 - 64),
					Color(1, 1, 1, 0.4), 2.0)
		&"crystal":
			var pts := PackedVector2Array([
				Vector2(0, -size.y * 0.5), Vector2(size.x * 0.5, 0),
				Vector2(0, size.y * 0.5), Vector2(-size.x * 0.5, 0),
			])
			draw_colored_polygon(pts, color)
		_:
			draw_rect(Rect2(-size * 0.5, size), color, true)
