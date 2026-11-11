@tool
extends Control

## 网格画布：只负责画与交互，不碰文件、不碰 undo。
## 所有修改都以信号交给 RoomAtlasWorldCanvas 统一提交。

signal selection_changed(id: StringName)
signal cells_committed(placement: RoomAtlasPlacement, old_cells: Rect2i, new_cells: Rect2i)
signal scene_dropped(path: String, grid_pos: Vector2i)

const DRAG_TYPE := "room_atlas_scene"

# 拖拽辅助线：绿色 = 与邻居边贴合（相邻），蓝色 = 边共线，黄色 = 最近候选。
const GUIDE_SEAM := Color(0.42, 1.0, 0.6, 0.95)
const GUIDE_ALIGN := Color(0.42, 0.72, 1.0, 0.75)
const GUIDE_NEAR := Color(1.0, 0.82, 0.42, 0.7)
const GUIDE_NEAR_PX := 90.0
const GUIDE_DASH := 8.0
const GUIDE_GAP := 6.0

# 拖动时的边界吸附阈值（屏幕像素）：缩放变化时手感保持一致。
const SNAP_PX := 10.0

var config: RoomAtlasConfig = null
var selected: StringName = &""

var _zoom := 0.12
var _pan := Vector2.ZERO
var _drag_room := false
var _drag_pan := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pan := Vector2.ZERO
var _drag_placement: RoomAtlasPlacement = null
var _drag_grab_world := Vector2.ZERO
var _drag_start_cells := Rect2i()
var _drag_preview_cells := Rect2i()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 引擎级裁剪：所有绘制（含子节点）都限制在画布矩形内，
	# 放大后不会溢出到 Godot 编辑器的其它 dock / 布局。
	clip_contents = true
	# 接收触控板捏合手势的兜底路径。
	set_process_unhandled_input(true)
	resized.connect(func(): queue_redraw())


func set_config(c: RoomAtlasConfig) -> void:
	config = c
	selected = &""
	# 不依赖 _ready() 的调用时机，配置注入时再确认一次裁剪开启。
	clip_contents = true
	call_deferred("fit_view")
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func select(id: StringName) -> void:
	selected = id
	selection_changed.emit(id)
	queue_redraw()


func fit_view() -> void:
	if config == null or config.placements().is_empty():
		_zoom = 0.12
		_pan = Vector2.ZERO
		queue_redraw()
		return
	var b := Rect2()
	for p in config.placements():
		var r := _rect(p)
		b = r if b.size == Vector2.ZERO else b.merge(r)
	_pan = b.get_center()
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		s = Vector2(800, 320)
	_zoom = clampf(minf(s.x / maxf(b.size.x, 1.0), s.y / maxf(b.size.y, 1.0)) * 0.86,
			0.02, 3.0)
	queue_redraw()


## 把视图平移到指定房间中心，供列表点击定位（不改缩放）。
func focus_room(id: StringName) -> void:
	if config == null:
		return
	for p in config.placements():
		if p.id == id:
			_pan = _rect(p).get_center()
			queue_redraw()
			return


func _world_to_canvas(p: Vector2) -> Vector2:
	return (p - _pan) * _zoom + size * 0.5


func _canvas_to_world(c: Vector2) -> Vector2:
	return (c - size * 0.5) / _zoom + _pan


func _v2(v: Vector2i) -> Vector2:
	return Vector2(float(v.x), float(v.y))


func _rect(p: RoomAtlasPlacement) -> Rect2:
	var cs := config.cell_size
	return Rect2(_v2(p.cells.position) * cs, _v2(p.cells.size) * cs)


func _overlaps(target: RoomAtlasPlacement) -> bool:
	for p in config.placements():
		if p != target and target.cells.intersects(p.cells):
			return true
	return false


## 一次算出所有重叠房间的 id。按 x 排序后扫描，后一个左边界越过当前右边界
## 即可 break；绘制时不再对每个房间重复全表判断。
static func _overlap_ids(placements: Array) -> Dictionary:
	var sorted := placements.duplicate()
	sorted.sort_custom(func(a, b): return a.cells.position.x < b.cells.position.x)
	var out := {}
	for i in range(sorted.size()):
		var a: RoomAtlasPlacement = sorted[i]
		for j in range(i + 1, sorted.size()):
			var b: RoomAtlasPlacement = sorted[j]
			if b.cells.position.x >= a.cells.end.x:
				break
			if a.cells.intersects(b.cells):
				out[a.id] = true
				out[b.id] = true
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.062, 0.085), true)
	if config == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var cs := config.cell_size
	if cs.x <= 0.0 or cs.y <= 0.0:
		return

	var view := Rect2(Vector2.ZERO, size)
	var tl := _canvas_to_world(Vector2.ZERO)
	var br := _canvas_to_world(size)
	var gx0 := floori(tl.x / cs.x) - 1
	var gx1 := ceili(br.x / cs.x) + 1
	var gy0 := floori(tl.y / cs.y) - 1
	var gy1 := ceili(br.y / cs.y) + 1
	# 网格线按"屏幕像素间距"抽稀，与 cell_size 无关：
	# 1px 网格在 fit_view 缩放下也不会糊成一片。
	var target_px := 24.0
	var step_x := maxi(1, ceili(target_px / maxf(cs.x * _zoom, 0.001)))
	var step_y := maxi(1, ceili(target_px / maxf(cs.y * _zoom, 0.001)))
	# 起点对齐到 step 的倍数，平移时网格线才不会滑动。
	var ax0 := ceili(float(gx0) / float(step_x)) * step_x
	var ay0 := ceili(float(gy0) / float(step_y)) * step_y

	var grid_col := Color(1, 1, 1, 0.13)
	for gx in range(ax0, gx1 + 1, step_x):
		var x := _world_to_canvas(Vector2(gx * cs.x, 0)).x
		if x < -1.0 or x > size.x + 1.0:
			continue
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_col, 1.0)
	for gy in range(ay0, gy1 + 1, step_y):
		var y := _world_to_canvas(Vector2(0, gy * cs.y)).y
		if y < -1.0 or y > size.y + 1.0:
			continue
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_col, 1.0)

	var o := _world_to_canvas(Vector2.ZERO)
	var axis_col := Color(0.4, 0.7, 1, 0.28)
	if o.x >= 0.0 and o.x <= size.x:
		draw_line(Vector2(o.x, 0), Vector2(o.x, size.y), axis_col, 1.0)
	if o.y >= 0.0 and o.y <= size.y:
		draw_line(Vector2(0, o.y), Vector2(size.x, o.y), axis_col, 1.0)

	# 一次取 placements、一次算重叠集合，避免每个房间再全表扫一遍（原先 O(N²)）。
	var placements := config.placements()
	var overlap_ids := _overlap_ids(placements)
	for p in placements:
		var r := _rect(p)
		var a := _world_to_canvas(r.position)
		var b := _world_to_canvas(r.end)
		var cr := Rect2(a, b - a)
		# 放大后房间矩形可能远大于画布：先剔除，再把绘制范围裁剪到画布内。
		# 用纯算术裁剪，不依赖引擎的 clip_contents 也能保证零越界。
		if not view.intersects(cr):
			continue
		var cx0 := maxf(cr.position.x, 0.0)
		var cy0 := maxf(cr.position.y, 0.0)
		var cx1 := minf(cr.end.x, size.x)
		var cy1 := minf(cr.end.y, size.y)
		var visible := Rect2(cx0, cy0, maxf(0.0, cx1 - cx0), maxf(0.0, cy1 - cy0))
		var is_sel := p.id == selected
		var col := Color(1.0, 0.36, 0.36) if overlap_ids.has(p.id) \
				else (Color(0.42, 1.0, 0.6) if is_sel else Color(0.75, 0.83, 0.95, 0.6))
		draw_rect(visible, Color(p.tint.r, p.tint.g, p.tint.b, 0.32), true)
		draw_rect(visible, col, false, 3.0 if is_sel else 1.5)
		var f := ThemeDB.fallback_font
		var px := Vector2(p.cells.size.x * cs.x, p.cells.size.y * cs.y)
		var origin := _rect(p).position
		# 标签吸附到可见区域边缘，房间左上角在画布外时文字也不会被画出去。
		draw_string(f, _clamp_label(cr.position + Vector2(8, 20)),
				String(p.id).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
		draw_string(f, _clamp_label(cr.position + Vector2(8, 38)),
				"%dx%d px  @ %d,%d" % [int(px.x), int(px.y),
					int(origin.x), int(origin.y)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))

	# 拖拽期间叠加 x/y 轴辅助线，松手即消失；只提示，不改变落点。
	if _drag_room and _drag_placement != null:
		_draw_drag_guides(_drag_placement, _drag_preview_cells)


## 把标签坐标限制在画布内，避免放大后文字溢出到编辑器其它区域。
func _clamp_label(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, 8.0, maxf(8.0, size.x - 180.0)),
		clampf(p.y, 20.0, maxf(20.0, size.y - 12.0))
	)


# ---------------------------------------------------------------- 拖拽吸附

## 拖动时把房间边缘吸附到邻居的边（贴边或共线），x / y 独立判断。
## 阈值按屏幕像素换算，任何缩放下手感一致；只吸附，不阻止重叠。
func _snap_cells(pos: Vector2i, size: Vector2i, ignore: RoomAtlasPlacement = null) -> Vector2i:
	if config == null:
		return pos
	var cs := config.cell_size
	var limit := SNAP_PX / maxf(_zoom, 0.0001)
	var out := pos
	var best_x := limit
	var best_y := limit
	for p in config.placements():
		if p == ignore:
			continue
		var o := p.cells
		# 右贴左、左贴右、左边共线、右边共线。
		for c in [o.position.x - size.x, o.end.x, o.position.x, o.end.x - size.x]:
			var d := absf(float(pos.x - c) * cs.x)
			if d < best_x:
				best_x = d
				out.x = c
		for c in [o.position.y - size.y, o.end.y, o.position.y, o.end.y - size.y]:
			var d := absf(float(pos.y - c) * cs.y)
			if d < best_y:
				best_y = d
				out.y = c
	return out


# ---------------------------------------------------------------- 拖拽辅助线

## 纯计算：拖拽矩形与所有邻居的边关系，供绘制与验证共用。
func _guide_state(target: RoomAtlasPlacement, cells: Rect2i) -> Dictionary:
	var cs := config.cell_size
	var t := Rect2(_v2(cells.position) * cs, _v2(cells.size) * cs)
	var seam_x := {}
	var seam_y := {}
	var align_x := {}
	var align_y := {}
	var near := {
		"x": INF, "x_at": 0.0, "x_d": 0.0,
		"y": INF, "y_at": 0.0, "y_d": 0.0,
	}

	for q in config.placements():
		if q == target:
			continue
		var o := Rect2(_v2(q.cells.position) * cs, _v2(q.cells.size) * cs)
		# 只有另一轴有区间重叠，两条边贴在一起才构成真正的「相邻」。
		var x_ov := t.position.x < o.end.x and t.end.x > o.position.x
		var y_ov := t.position.y < o.end.y and t.end.y > o.position.y
		if y_ov:
			_check_edge(t.position.x, o.end.x, q.id, seam_x, near, "x")
			_check_edge(t.end.x, o.position.x, q.id, seam_x, near, "x")
		if x_ov:
			_check_edge(t.position.y, o.end.y, q.id, seam_y, near, "y")
			_check_edge(t.end.y, o.position.y, q.id, seam_y, near, "y")
		if is_equal_approx(t.position.x, o.position.x):
			align_x[o.position.x] = q.id
		if is_equal_approx(t.end.x, o.end.x):
			align_x[o.end.x] = q.id
		if is_equal_approx(t.position.y, o.position.y):
			align_y[o.position.y] = q.id
		if is_equal_approx(t.end.y, o.end.y):
			align_y[o.end.y] = q.id
	return {
		"seam_x": seam_x, "seam_y": seam_y,
		"align_x": align_x, "align_y": align_y, "near": near,
	}


## 拖拽时画贯穿画布的 x/y 轴辅助线，只作相邻提示、不改吸附结果：
## 绿色 = 与邻居边贴合（严丝合缝），蓝色 = 与邻居边共线，
## 黄色 = 尚未贴合时最接近的候选边，并标出还差多少世界像素。
func _draw_drag_guides(target: RoomAtlasPlacement, cells: Rect2i) -> void:
	var st := _guide_state(target, cells)
	var seam_x: Dictionary = st["seam_x"]
	var seam_y: Dictionary = st["seam_y"]
	var align_x: Dictionary = st["align_x"]
	var align_y: Dictionary = st["align_y"]
	var near: Dictionary = st["near"]

	for x in seam_x.keys():
		_dashed_v(_world_to_canvas(Vector2(float(x), 0)).x, GUIDE_SEAM, 2.0)
	for y in seam_y.keys():
		_dashed_h(_world_to_canvas(Vector2(0, float(y))).y, GUIDE_SEAM, 2.0)
	for x in align_x.keys():
		if not seam_x.has(x):
			_dashed_v(_world_to_canvas(Vector2(float(x), 0)).x, GUIDE_ALIGN, 1.0)
	for y in align_y.keys():
		if not seam_y.has(y):
			_dashed_h(_world_to_canvas(Vector2(0, float(y))).y, GUIDE_ALIGN, 1.0)

	var parts: Array[String] = []
	_append_guides(parts, RoomAtlasI18n.t("X seam"), seam_x)
	_append_guides(parts, RoomAtlasI18n.t("Y seam"), seam_y)
	_append_guides(parts, RoomAtlasI18n.t("X align"), align_x)
	_append_guides(parts, RoomAtlasI18n.t("Y align"), align_y)
	if seam_x.is_empty() and near["x"] < INF:
		_dashed_v(_world_to_canvas(Vector2(float(near["x_at"]), 0)).x, GUIDE_NEAR, 1.0)
		parts.append(RoomAtlasI18n.tf("Nearest X: Δ%d px", [int(round(near["x_d"]))]))
	if seam_y.is_empty() and near["y"] < INF:
		_dashed_h(_world_to_canvas(Vector2(0, float(near["y_at"]))).y, GUIDE_NEAR, 1.0)
		parts.append(RoomAtlasI18n.tf("Nearest Y: Δ%d px", [int(round(near["y_d"]))]))
	if parts.is_empty():
		return

	var pos := _clamp_label(Vector2(10, maxf(20.0, size.y - 12.0)))
	draw_rect(Rect2(pos + Vector2(-4, -14),
			Vector2(maxf(0.0, minf(size.x - 8.0, 620.0)), 20)),
			Color(0.02, 0.03, 0.05, 0.72), true)
	draw_string(ThemeDB.fallback_font, pos, "  ·  ".join(PackedStringArray(parts)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.95, 1, 0.9))


## 相等记贴合，否则在屏幕阈值内记录最近候选边。
func _check_edge(edge: float, other: float, id: StringName,
		seams: Dictionary, near: Dictionary, axis: String) -> void:
	var d := absf(edge - other)
	if d < 0.001:
		seams[other] = id
		return
	var px := d * _zoom
	if px <= GUIDE_NEAR_PX and px < near[axis]:
		near[axis] = px
		near[axis + "_at"] = other
		near[axis + "_d"] = d


func _append_guides(parts: Array[String], label: String, d: Dictionary) -> void:
	if d.is_empty():
		return
	var ids: Array[String] = []
	for id in d.values():
		var s := String(id)
		if not ids.has(s):
			ids.append(s)
	parts.append(label + ": " + ", ".join(PackedStringArray(ids)))


func _dashed_v(x: float, col: Color, width: float) -> void:
	if x < 0.0 or x > size.x:
		return
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(x, y), Vector2(x, minf(y + GUIDE_DASH, size.y)), col, width)
		y += GUIDE_DASH + GUIDE_GAP


func _dashed_h(y: float, col: Color, width: float) -> void:
	if y < 0.0 or y > size.y:
		return
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, y), Vector2(minf(x + GUIDE_DASH, size.x), y), col, width)
		x += GUIDE_DASH + GUIDE_GAP


func _hit_room(cpos: Vector2) -> RoomAtlasPlacement:
	var w := _canvas_to_world(cpos)
	var ps := config.placements()
	for i in range(ps.size() - 1, -1, -1):
		if _rect(ps[i]).has_point(w):
			return ps[i]
	return null


func _zoom_at(cpos: Vector2, factor: float) -> void:
	var before := _canvas_to_world(cpos)
	_zoom = clampf(_zoom * factor, 0.02, 3.0)
	_pan = before - (cpos - size * 0.5) / _zoom


func _gui_input(event: InputEvent) -> void:
	if config == null:
		return
	# macOS 触控板双指捏合：外扩放大、收缩缩小，以鼠标位置为中心。
	var mag := event as InputEventMagnifyGesture
	if mag != null:
		_zoom_at(get_local_mouse_position(), mag.factor)
		queue_redraw()
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var f := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
				_zoom_at(mb.position, f)
				queue_redraw()
				accept_event()
			return
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var hit := _hit_room(mb.position)
				if hit != null:
					select(hit.id)
					_drag_room = true
					_drag_placement = hit
					_drag_start_cells = hit.cells
					_drag_preview_cells = hit.cells
					_drag_grab_world = _canvas_to_world(mb.position) - _rect(hit).position
				else:
					select(&"")
					_drag_pan = true
			else:
				_drag_pan = true
			_drag_start_mouse = mb.position
			_drag_start_pan = _pan
			accept_event()
		else:
			if _drag_room and _drag_placement != null \
					and _drag_preview_cells != _drag_start_cells:
				cells_committed.emit(_drag_placement, _drag_start_cells, _drag_preview_cells)
			_drag_room = false
			_drag_pan = false
			_drag_placement = null
			# 松手后必须重绘，否则辅助线会残留在画布上。
			queue_redraw()
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _drag_pan:
			_pan = _drag_start_pan - (mm.position - _drag_start_mouse) / _zoom
			queue_redraw()
			accept_event()
		elif _drag_room and _drag_placement != null:
			var w := _canvas_to_world(mm.position) - _drag_grab_world
			var cs := config.cell_size
			var g := Vector2i(roundi(w.x / cs.x), roundi(w.y / cs.y))
			g = _snap_cells(g, _drag_placement.cells.size, _drag_placement)
			_drag_preview_cells = Rect2i(g, _drag_placement.cells.size)
			_drag_placement.cells = _drag_preview_cells
			queue_redraw()
			accept_event()


## 兜底：个别环境下手势不会经鼠标焦点控件进入 _gui_input。
## 只在鼠标位于画布内时处理，避免影响编辑器其它区域。
func _unhandled_input(event: InputEvent) -> void:
	var mag := event as InputEventMagnifyGesture
	if mag == null:
		return
	if not get_global_rect().has_point(get_global_mouse_position()):
		return
	_zoom_at(get_local_mouse_position(), mag.factor)
	queue_redraw()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 资源拖入

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if config == null or not (data is Dictionary):
		return false
	var d: Dictionary = data
	if String(d.get("type", "")) != DRAG_TYPE:
		return false
	var path := String(d.get("path", ""))
	return path.ends_with(".tscn") and ResourceLoader.exists(path)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var path := String((data as Dictionary).get("path", ""))
	if path.is_empty() or config == null:
		return
	# 落点就是鼠标位置：换算成格坐标后直接作为 cells.position，
	# 不做中心偏移，也不自动找空位（重叠交给红框 / 校验报告）。
	var w := _canvas_to_world(at_position)
	var cs := config.cell_size
	var g := Vector2i(
		roundi(w.x / maxf(cs.x, 0.001)),
		roundi(w.y / maxf(cs.y, 0.001))
	)
	scene_dropped.emit(path, g)
