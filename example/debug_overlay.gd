extends Node2D

## 示例调试层：绿框 = 已挂载，灰框 = 未挂载。
## 只依赖插件公开的查询 API，不读插件内部状态。

var streamer: Node = null
var config: Resource = null


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if streamer == null or config == null:
		return
	var xf := get_viewport().get_canvas_transform()
	var cs: Vector2 = config.get("cell_size")
	for raw in config.get("rooms"):
		var p: Resource = raw
		var cells: Rect2i = p.get("cells")
		var origin := Vector2(float(cells.position.x), float(cells.position.y)) * cs
		var size := Vector2(float(cells.size.x), float(cells.size.y)) * cs
		var r := Rect2(origin, size)
		var id := StringName(p.get("id"))
		var mounted := bool(streamer.call("is_mounted", id))
		var col := Color(0.35, 1.0, 0.55, 0.95) if mounted \
				else Color(1, 1, 1, 0.20)
		_stroke_rect(r, xf, col)
		draw_string(ThemeDB.fallback_font, xf * r.position + Vector2(12, 24),
				String(id).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)


func _stroke_rect(r: Rect2, xf: Transform2D, col: Color) -> void:
	var pts := PackedVector2Array([
		xf * r.position,
		xf * Vector2(r.end.x, r.position.y),
		xf * r.end,
		xf * Vector2(r.position.x, r.end.y),
		xf * r.position,
	])
	draw_polyline(pts, col, 2.0)
