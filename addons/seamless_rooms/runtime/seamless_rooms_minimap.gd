@tool
class_name SeamlessRoomMinimap
extends Control

## 房间小地图（纯显示，不含任何玩法语义）。
##
## 按 SeamlessRoomConfig 里的房间几何画一张缩略图；外部把世界坐标推给
## set_cursor_world_position()，小地图就用光标标出它在图上的位置。
##
## 插件不认识"玩家"，也不读游戏状态：谁要显示，谁就喂坐标。
## 房间矩形只来自配置，与流式加载状态无关。
##
## 绘制分两层：本节点只画静态房间层（配置 / 尺寸 / 样式变化时重绘），
## Overlay 子节点只画光标与相机视野（每帧重绘但只有几个图元）。
## 玩家移动时不再重画 O(N) 个房间矩形。

## 地图配置。赋值后自动重算世界包围盒并重绘。
@export var config: SeamlessRoomConfig:
	set(value):
		config = value
		_rebuild()
		_redraw_static()

## 世界坐标四周的留白（像素），让边缘房间不贴着小地图边框。
@export var world_padding := 200.0:
	set(value):
		world_padding = maxf(0.0, value)
		_rebuild()
		_redraw_static()

@export_group("Style")
@export var background_color := Color(0.07, 0.08, 0.11, 0.92)
@export var border_color := Color(1.0, 1.0, 1.0, 0.18)
@export var room_border_color := Color(1.0, 1.0, 1.0, 0.30)
## 房间 id 角标文字颜色。
@export var label_color := Color(0.95, 0.97, 1.0, 0.92)
## 房间 id 角标底衬，避免文字压在房间色块上看不清。
@export var id_badge_color := Color(0.02, 0.03, 0.05, 0.78)
## 光标在房间包围盒内时的颜色。
@export var cursor_color := Color(0.45, 0.92, 1.0, 1.0)
## 坐标越出房间包围盒时的颜色（光标会被贴到边缘）。
@export var out_of_bounds_color := Color(1.0, 0.55, 0.35, 1.0)
@export var cursor_radius := 4.0
## 是否在底部坐标条里显示光标（玩家）的世界坐标。
## 打开后地图区让出底部一条，不与房间色块重叠。
## 示例层启动时由 camera_policy.show_minimap_coords 写入，插件默认值保持关闭。
@export var show_cursor_coords := false:
	set(value):
		show_cursor_coords = value
		# 底部条会改变地图区的尺寸，静态层也要跟着重排。
		_redraw_static()
## 坐标条文字颜色。
@export var cursor_coords_color := Color(0.85, 0.93, 1.0, 0.95)
## 坐标条背景色。
@export var coords_bar_color := Color(0.02, 0.03, 0.05, 0.78)
## 是否在房间左上角画 id 角标；房间很小或数量多时可关掉。
## 示例层启动时由 camera_policy.show_minimap_ids 写入（默认展示），插件默认值保持关闭。
@export var show_room_ids := false:
	set(value):
		show_room_ids = value
		_redraw_static()
## 相机视野矩形的边框 / 填充色。
@export var camera_view_color := Color(1.0, 0.82, 0.35, 0.95)
@export var camera_view_fill := Color(1.0, 0.82, 0.35, 0.12)
## 是否绘制相机位置与视野矩形；数据由外部通过 set_camera_view() 推入。
## 示例层启动时由 camera_policy.show_minimap_camera 写入（默认展示）。
@export var show_camera_view := true:
	set(value):
		show_camera_view = value
		_redraw_overlay()

## 底部坐标条高度；关闭 show_cursor_coords 时不占位。
const COORDS_BAR_HEIGHT := 18.0

var _world_bounds := Rect2()
var _map_scale := 1.0
var _map_offset := Vector2.ZERO
var _has_cursor := false
var _cursor_world := Vector2.ZERO
var _has_camera := false
var _camera_rect := Rect2()
var _placements: Array = []
var _id_labels: Array[String] = []
var _id_sizes: Array[Vector2] = []
var _overlay: Overlay = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	if config != null:
		_rebuild()
	_ensure_overlay()
	_redraw_static()


func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	var layer := Overlay.new()
	layer.name = "MinimapOverlay"
	layer.host = self
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	_overlay = layer


func _on_resized() -> void:
	_redraw_static()


## 静态层重绘（低频）：配置 / 尺寸 / 样式变化。
func _redraw_static() -> void:
	queue_redraw()
	_redraw_overlay()


## 动态层重绘（每帧）：只重画光标与相机视野，成本与房间数无关。
func _redraw_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw()
	else:
		queue_redraw()


# ---------------------------------------------------------------- 对外 API

## 载入配置；等价于给 config 赋值。
func configure(p_config: SeamlessRoomConfig) -> void:
	config = p_config


## 外部推入要显示的世界坐标（通常是玩家位置）。
func set_cursor_world_position(world_pos: Vector2) -> void:
	# 玩家静止时不做无意义的重绘。
	if _has_cursor and _cursor_world.is_equal_approx(world_pos):
		return
	_cursor_world = world_pos
	_has_cursor = true
	_redraw_overlay()


## 外部推入相机视野的世界矩形；其中心就是相机位置。
## 传空矩形等价于隐藏；位置 / 尺寸没变时不触发重绘。
func set_camera_view(world_rect: Rect2) -> void:
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		clear_camera_view()
		return
	if _has_camera and _camera_rect.is_equal_approx(world_rect):
		return
	_camera_rect = world_rect
	_has_camera = true
	_redraw_overlay()


func clear_camera_view() -> void:
	if not _has_camera:
		return
	_has_camera = false
	_redraw_overlay()


func has_camera_view() -> bool:
	return _has_camera


## 隐藏光标（例如玩家不在任何房间、或暂时不需要显示）。
func clear_cursor() -> void:
	_has_cursor = false
	_redraw_overlay()


func has_cursor() -> bool:
	return _has_cursor


func cursor_world_position() -> Vector2:
	return _cursor_world


## 世界坐标 → 小地图本地坐标（Control 内坐标，未裁剪）。
func world_to_map(world_pos: Vector2) -> Vector2:
	_update_map_transform()
	return world_pos * _map_scale + _map_offset


## 房间包围盒（世界坐标，不含 world_padding）。
func world_bounds() -> Rect2:
	return _world_bounds


# ---------------------------------------------------------------- 绘制：静态层

func _draw() -> void:
	_update_map_transform()
	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)
	draw_rect(Rect2(Vector2.ZERO, size).grow(-0.5), border_color, false, 1.0)
	if config == null:
		return

	var font := ThemeDB.fallback_font
	var cs := config.cell_size
	var view := _map_area()
	for i in range(_placements.size()):
		var p: Resource = _placements[i]
		var world := Rect2(
				Vector2(p.cells.position) * cs,
				Vector2(p.cells.size) * cs)
		var r := Rect2(world.position * _map_scale + _map_offset,
				world.size * _map_scale)
		# 缩略图上完全不可见的房间不画（大地图缩得很小时省掉绘制调用）。
		if not view.intersects(r):
			continue
		draw_rect(r, p.tint, true)
		draw_rect(r, room_border_color, false, 1.0)
		if show_room_ids:
			var ts: Vector2 = _id_sizes[i]
			var badge := Rect2(r.position + Vector2(2.0, 2.0), ts + Vector2(7.0, 4.0))
			draw_rect(badge, id_badge_color, true)
			draw_string(font, badge.position + Vector2(3.5, 11.0),
					_id_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_color)
	# 光标 / 相机视野由 Overlay 子节点绘制，静态层不随玩家移动重画。


# ---------------------------------------------------------------- 内部

## 房间并集包围盒（世界坐标）。配置里没有有效房间时保持空矩形。
func _rebuild() -> void:
	_world_bounds = Rect2()
	_placements.clear()
	_id_labels.clear()
	_id_sizes.clear()
	if config == null:
		return
	var cs := config.cell_size
	var font := ThemeDB.fallback_font
	var first := true
	for p in config.placements():
		var r := Rect2(Vector2(p.cells.position) * cs, Vector2(p.cells.size) * cs)
		if first:
			_world_bounds = r
			first = false
		else:
			_world_bounds = _world_bounds.merge(r)
		_placements.append(p)
		var text := String(p.id)
		_id_labels.append(text)
		if font != null:
			_id_sizes.append(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10))
		else:
			_id_sizes.append(Vector2.ZERO)


## 地图区：整块控件减去底部坐标条（关闭时不减）。
func _map_area() -> Rect2:
	var h := COORDS_BAR_HEIGHT if show_cursor_coords else 0.0
	return Rect2(Vector2.ZERO, Vector2(size.x, maxf(0.0, size.y - h)))


## 世界 → 本地：等比缩放并居中，不拉伸房间比例。
func _update_map_transform() -> void:
	_map_scale = 1.0
	_map_offset = Vector2.ZERO
	if _world_bounds.size.x <= 0.0 or _world_bounds.size.y <= 0.0:
		return
	var area := _map_area()
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var b := _world_bounds.grow(world_padding)
	_map_scale = minf(area.size.x / b.size.x, area.size.y / b.size.y)
	_map_offset = (area.size - b.size * _map_scale) * 0.5 - b.position * _map_scale


## 动态层：每帧只画光标 + 相机视野，图元数量恒定，与房间数无关。
class Overlay extends Control:
	var host: SeamlessRoomMinimap

	func _draw() -> void:
		if host == null or not is_instance_valid(host):
			return
		if host.show_camera_view and host._has_camera:
			_draw_camera_view()
		if host.show_cursor_coords:
			_draw_coords_bar()
		if not host._has_cursor:
			return
		_draw_cursor()

	func _draw_cursor() -> void:
		var local := host.world_to_map(host._cursor_world)
		var inside := host._world_bounds.has_point(host._cursor_world)
		var col := host.cursor_color if inside else host.out_of_bounds_color
		var center := Vector2(
				clampf(local.x, 0.0, size.x),
				clampf(local.y, 0.0, size.y))
		draw_circle(center, host.cursor_radius + 2.5, Color(col.r, col.g, col.b, 0.25))
		draw_circle(center, host.cursor_radius, col)
		draw_arc(center, host.cursor_radius + 5.0, 0.0, TAU, 24,
				Color(col.r, col.g, col.b, 0.55), 1.0, true)

	## 底部坐标条：底衬 + 分隔线 + 世界坐标文字；光标还没推入时显示占位符。
	func _draw_coords_bar() -> void:
		var h := SeamlessRoomMinimap.COORDS_BAR_HEIGHT
		var top := size.y - h
		draw_rect(Rect2(0.0, top, size.x, h), host.coords_bar_color, true)
		draw_line(Vector2(0.0, top), Vector2(size.x, top), host.border_color, 1.0)
		var text := SeamlessRoomI18n.t("Player coords  —")
		if host._has_cursor:
			text = SeamlessRoomI18n.tf("Player coords  x %d   y %d", [
					roundi(host._cursor_world.x), roundi(host._cursor_world.y)])
		var font := ThemeDB.fallback_font
		var font_size := 11
		var baseline := top + (h + font.get_ascent(font_size)) * 0.5 - 1.0
		draw_string(font, Vector2(8.0, baseline), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, host.cursor_coords_color)

	func _draw_camera_view() -> void:
		var r := Rect2(host._camera_rect.position * host._map_scale + host._map_offset,
				host._camera_rect.size * host._map_scale)
		draw_rect(r, host.camera_view_fill, true)
		draw_rect(r, host.camera_view_color, false, 1.0)
		var c := r.get_center()
		draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), host.camera_view_color, 1.5)
		draw_line(c + Vector2(0, -5), c + Vector2(0, 5), host.camera_view_color, 1.5)
		draw_circle(c, 2.0, host.camera_view_color)
