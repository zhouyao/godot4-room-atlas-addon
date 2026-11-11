extends Node2D

## 示例调试层：标记玩家房内 / 房外。
## 只依赖插件公开的查询 API，不读插件内部状态。

var player: Node2D = null
var controller: Node = null
var policy: RefCounted = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_camera_debug(_status())


func _status() -> Dictionary:
	if controller != null and controller.has_method("status"):
		return controller.status()
	return {}


func _draw_camera_debug(st: Dictionary) -> void:
	if st.is_empty() or policy == null:
		return
	var xf := get_viewport().get_canvas_transform()
	if policy.show_player_room and player != null:
		var p := xf * player.global_position
		var inside := bool(st.get("inside", true))
		var col := Color(0.35, 1.0, 0.55, 0.95) if inside \
				else Color(1.0, 0.4, 0.35, 0.95)
		draw_line(p + Vector2(-10, 0), p + Vector2(10, 0), col, 2.0)
		draw_line(p + Vector2(0, -10), p + Vector2(0, 10), col, 2.0)
		draw_string(ThemeDB.fallback_font, p + Vector2(14, -12),
				"房内" if inside else "房外",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
