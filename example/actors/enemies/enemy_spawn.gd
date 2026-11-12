@tool
class_name EnemySpawn
extends Marker2D

## 房间内的怪物出生点与领地。
## 运行时由 RoomEntityDirector 读取，实例化到 Main/Actors；本节点自身不参与战斗。
## 领地圆心就是本节点位置；半径应小于 streamer 的 sleep_distance，保证怪追人时房间不会休眠。

@export var enemy_scene: PackedScene
@export var territory_radius: float = 320.0:
	set(value):
		territory_radius = maxf(0.0, value)
		queue_redraw()
@export var aggro_radius: float = 220.0:
	set(value):
		aggro_radius = maxf(0.0, value)
		queue_redraw()
@export var leash_radius: float = 480.0
## false 时死亡后不再刷新；需要游戏层自己保存 dead 标记。
@export var respawn: bool = true

const TERRITORY_COLOR := Color(0.25, 0.85, 1.0, 0.7)
const TERRITORY_FILL := Color(0.25, 0.85, 1.0, 0.06)
const AGGRO_COLOR := Color(1.0, 0.72, 0.25, 0.75)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, territory_radius, TERRITORY_FILL)
	draw_arc(Vector2.ZERO, territory_radius, 0.0, TAU, 64, TERRITORY_COLOR, 2.0)
	draw_arc(Vector2.ZERO, aggro_radius, 0.0, TAU, 64, AGGRO_COLOR, 1.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(8.0, 0.0), TERRITORY_COLOR, 1.0)
	draw_line(Vector2(0.0, -8.0), Vector2(0.0, 8.0), TERRITORY_COLOR, 1.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if enemy_scene == null:
		warnings.append("enemy_scene is empty; this spawn is ignored at runtime.")
	if leash_radius < aggro_radius:
		warnings.append("leash_radius should be >= aggro_radius.")
	return warnings
