extends Area2D

## 示例宝箱：靠近按 E 打开。
## 开合状态由 RoomEntityDirector 以 room_id/出生点名称 为 key 持久化，
## 房间休眠 / 卸载后重新挂载时恢复。

signal opened_changed(opened: bool)

var state_key: StringName = &""
var opened := false

var _player_in_range := false


func _ready() -> void:
	# 物理层 4 = Interactable（bitmask 8）；mask 2 = 只检测玩家层。
	collision_layer = 8
	collision_mask = 2
	z_index = 0
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func set_opened(value: bool) -> void:
	opened = value
	queue_redraw()


func _process(_delta: float) -> void:
	if _player_in_range and not opened and Input.is_key_pressed(KEY_E):
		open()


func open() -> void:
	if opened:
		return
	opened = true
	queue_redraw()
	opened_changed.emit(true)


func _on_body_entered(body: Node2D) -> void:
	if body.collision_layer & 2:
		_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if body.collision_layer & 2:
		_player_in_range = false


func _draw() -> void:
	# 占位美术：箱子 + 打开的盖子。
	var wood := Color(0.55, 0.35, 0.18)
	var trim := Color(0.95, 0.78, 0.35)
	draw_rect(Rect2(-22.0, -14.0, 44.0, 28.0), wood, true)
	draw_rect(Rect2(-22.0, -14.0, 44.0, 28.0), trim, false, 2.0)
	draw_rect(Rect2(-22.0, -18.0, 44.0, 5.0), trim, true)
	if opened:
		draw_rect(Rect2(-20.0, -34.0, 40.0, 10.0), wood, true)
		draw_rect(Rect2(-20.0, -34.0, 40.0, 10.0), trim, false, 2.0)
		draw_circle(Vector2(0.0, -6.0), 4.0, Color(1.0, 0.9, 0.5, 0.8))
	else:
		draw_rect(Rect2(-4.0, -4.0, 8.0, 8.0), trim, true)
