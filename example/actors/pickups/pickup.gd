extends Area2D

## 示例掉落物：被玩家的拾取 Area2D 扫到即收集。
## 既可由 PickupSpawn 固定摆放，也可由 RoomEntityDirector 在怪物死亡时生成。

signal collected

@export var value := 1
@export var bob_height := 3.0
@export var bob_speed := 4.0

var _base_y := 0.0
var _time := 0.0
var _has_base := false


func _ready() -> void:
	# 物理层 5 = Pickup（bitmask 16）；不需要主动检测别人，由玩家侧扫描。
	collision_layer = 16
	collision_mask = 0
	z_index = 0
	queue_redraw()


func _process(delta: float) -> void:
	# 生成时 director 先 add_child 再写 global_position，所以基准 Y 要在第一帧再取。
	if not _has_base:
		_base_y = position.y
		_has_base = true
	_time += delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height
	queue_redraw()


func collect() -> void:
	if not is_inside_tree():
		return
	collected.emit()
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.85, 0.3))
	draw_circle(Vector2(-2.0, -2.0), 3.0, Color(1.0, 0.97, 0.7))
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3, 0.5), 1.0)
