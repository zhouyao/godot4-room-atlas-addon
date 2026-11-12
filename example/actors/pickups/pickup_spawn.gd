@tool
class_name PickupSpawn
extends Marker2D

## 房间内的固定掉落物出生点。运行时由 RoomEntityDirector 实例化到 Main/Actors。
## 收集后以 room_id/节点名 为 key 记录，房间重新挂载时不会再生成。

@export var pickup_scene: PackedScene


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.85, 0.3, 0.15))
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, 0.8), 2.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if pickup_scene == null:
		warnings.append("pickup_scene is empty; this spawn is ignored at runtime.")
	return warnings
