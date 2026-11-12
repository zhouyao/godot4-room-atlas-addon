@tool
class_name ChestSpawn
extends Marker2D

## 房间内的宝箱出生点。运行时由 RoomEntityDirector 实例化到 Main/Actors。
## 开合状态以 room_id/节点名 为 key 持久化，不随房间休眠丢失。

@export var chest_scene: PackedScene

const CHEST_COLOR := Color(1.0, 0.8, 0.3, 0.8)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.8, 0.3, 0.08))
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, CHEST_COLOR, 2.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if chest_scene == null:
		warnings.append("chest_scene is empty; this spawn is ignored at runtime.")
	return warnings
