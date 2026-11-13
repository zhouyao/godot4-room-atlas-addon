@tool
class_name SeamlessRoom2D
extends Node2D

## 房间场景可选基类：声明房间身份 / 尺寸 / 相机规则，并在 2D 编辑器里常驻边界预览。
##
## 自建房间继承本类即可被 Seamless Rooms 编辑器识别：
## · room_id / room_size 由编辑器通过 SceneState 读取（列表信息、落图尺寸）
## · configure() 是运行时可选钩子，基类记录 id 与权威世界矩形，子类可覆盖并 super()
## · 改 room_size 会立即重绘边界；预览只在编辑器里画，运行时不产生绘制
## · 相机规则只是数据 + 纯几何计算，基类不寻找、不移动任何 Camera2D
##
## 房间内容（平台、装饰、碰撞）完全由子类决定，基类不生成任何玩法节点。

## 房间唯一标识；留空时由编辑器落图时自动分配 rN。
@export var room_id: StringName = &""
## 房间显示名，只用于编辑器列表 / 属性面板，不参与运行期逻辑。
@export var room_title: String = ""
## 房间像素尺寸，编辑器据此显示边界与真实格数。
@export var room_size: Vector2i = Vector2i(2400, 1080):
	set(value):
		room_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		queue_redraw()
## 关闭后不再绘制编辑器边界预览（不影响导入与落图）。
@export var show_editor_bounds: bool = true

@export_group("Camera Rules")
## 关闭后相机不再被本房间约束（恢复无限 limit），用于对比效果。
@export var camera_confine: bool = true:
	set(value):
		camera_confine = value
		queue_redraw()
## FOLLOW_CONFINED = 跟随但视图不越界；FIXED_CENTER = 相机固定房间中心。
@export_enum("Follow & Confine", "Fixed Center") var camera_lock_mode: int = LOCK_FOLLOW_CONFINED
## 房间局部可视区；size <= 0 表示整间房。世界矩形由 configure() 从配置注入。
@export var camera_bounds: Rect2 = Rect2(0, 0, 0, 0):
	set(value):
		camera_bounds = value
		queue_redraw()
## 死区跟随参数：由游戏层读取，基类不驱动相机。
@export var camera_deadzone: Vector2 = Vector2(220, 140)
## 跟随偏移：请加在相机位置上，不要用 Camera2D.offset（它会推过 limit）。
@export var camera_offset: Vector2 = Vector2(0, -60)
@export var camera_zoom: Vector2 = Vector2.ONE
## ZOOM_TO_FIT = 视口大于房间时抬高 zoom；其余取值保持期望 zoom。
## 露出的房外区域由游戏层自行处理，基类只提供数据、不绘制任何遮罩。
@export_enum("Auto Zoom", "Keep Zoom", "Center Only") var camera_fit_mode: int = FIT_ZOOM_TO_FIT
## 2D 编辑器里额外画相机约束区预览。
@export var show_camera_bounds: bool = true:
	set(value):
		show_camera_bounds = value
		queue_redraw()

const BOUNDS_COLOR := Color(0.25, 0.85, 1.0, 0.95)
const CORNER_COLOR := Color(0.45, 1.0, 0.75, 1.0)
const GRID_COLOR := Color(0.35, 0.7, 1.0, 0.10)
const FILL_COLOR := Color(0.2, 0.65, 1.0, 0.05)
const LABEL_COLOR := Color(0.75, 0.95, 1.0, 0.9)
const METRIC_COLOR := Color(0.55, 0.9, 1.0, 0.8)
const CORNER_LEN := 48.0
const CORNER_WIDTH := 4.0
## 尺寸线 / 总尺寸文字外移，给四周刻度与数字留出空间。
const METRIC_OFFSET := 48.0
const TICK_STEP := 100.0
const TICK_MAJOR_STEP := 500.0
const TICK_MINOR_LEN := 6.0
const TICK_MAJOR_LEN := 12.0
const TICK_LABEL_SIZE := 14
const METRIC_LABEL_SIZE := 16
const TOTAL_LABEL_SIZE := 22
const CAMERA_LABEL_SIZE := 16
const TICK_COLOR := Color(0.4, 0.85, 1.0, 0.45)
const TICK_LABEL_COLOR := Color(0.6, 0.9, 1.0, 0.75)

const LOCK_FOLLOW_CONFINED := 0
const LOCK_FIXED_CENTER := 1
const FIT_ZOOM_TO_FIT := 0
const FIT_LETTERBOX := 1
const FIT_CENTER_ONLY := 2
const CAMERA_BOUNDS_COLOR := Color(1.0, 0.76, 0.28, 0.95)
const CAMERA_BOUNDS_FILL := Color(1.0, 0.76, 0.28, 0.06)
const CAMERA_BOUNDS_OFF_COLOR := Color(0.65, 0.65, 0.65, 0.7)

var _camera_world_rect := Rect2()
var _has_camera_world_rect := false
## FADE 模式下由 streamer 注入的共享边（含 width/core/feather 与 room_side）。
## OVERLAY 模式保持为空，SeamlessRoomParallax 据此决定是否做背景渐隐。
var seam_edges: Array = []


## Inspector 枚举标签跟随编辑器语言；存盘值仍是 int，切换语言不会改变场景数据。
func _validate_property(property: Dictionary) -> void:
	match String(property.get("name", "")):
		"camera_lock_mode":
			property["hint_string"] = SeamlessRoomI18n.t("Follow & Confine") + "," \
					+ SeamlessRoomI18n.t("Fixed Center")
		"camera_fit_mode":
			property["hint_string"] = SeamlessRoomI18n.t("Auto Zoom") + "," \
					+ SeamlessRoomI18n.t("Keep Zoom") + "," + SeamlessRoomI18n.t("Center Only")


## 运行时可选钩子：记录 id 与配置算出的权威世界矩形（不依赖房间实例是否进树）。
## p_seams 是 FADE 模式下与该房间相关的共享边；默认空，旧的 3 参数调用保持兼容。
func configure(p_id: StringName, p_placement: Resource, p_cell_size: Vector2,
		p_seams: Array = []) -> void:
	room_id = p_id
	seam_edges = p_seams
	_has_camera_world_rect = false
	if p_placement != null:
		var cells: Variant = p_placement.get("cells")
		if cells is Rect2i:
			var cs := Vector2(maxf(p_cell_size.x, 0.0001), maxf(p_cell_size.y, 0.0001))
			_camera_world_rect = Rect2(
				Vector2(float(cells.position.x), float(cells.position.y)) * cs,
				Vector2(float(cells.size.x), float(cells.size.y)) * cs
			)
			_has_camera_world_rect = true
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if show_camera_bounds:
		_draw_camera_bounds()
	if not show_editor_bounds:
		return
	var s := Vector2(
		maxf(1.0, float(room_size.x)),
		maxf(1.0, float(room_size.y))
	)
	var r := Rect2(Vector2.ZERO, s)

	# 很淡的填充 + 四等分网格，方便判断内容是否落在房间内。
	draw_rect(r, FILL_COLOR, true)
	for i in range(1, 4):
		var f := float(i) / 4.0
		draw_line(Vector2(s.x * f, 0), Vector2(s.x * f, s.y), GRID_COLOR, 1.0)
		draw_line(Vector2(0, s.y * f), Vector2(s.x, s.y * f), GRID_COLOR, 1.0)

	# 主边框 + 四角外向 L 形角标（画在边界外侧，不会被房间内容盖住）。
	draw_rect(r.grow(-1.0), BOUNDS_COLOR, false, 2.0)
	_draw_corner(Vector2.ZERO, Vector2(-1, -1))
	_draw_corner(Vector2(s.x, 0), Vector2(1, -1))
	_draw_corner(Vector2(0, s.y), Vector2(-1, 1))
	_draw_corner(s, Vector2(1, 1))

	# 四周刻度：短刻度每 100px，长刻度每 500px 并标数值。
	_draw_ruler_ticks(s)

	# 顶边 / 左边尺寸线，直接标出 W / H。
	_draw_metric(Vector2.ZERO, Vector2(s.x, 0),
			Vector2(0, -METRIC_OFFSET), "W %d px" % room_size.x)
	_draw_metric(Vector2.ZERO, Vector2(0, s.y),
			Vector2(-METRIC_OFFSET, 0), "H %d px" % room_size.y)

	# 房间上方写总尺寸，最直观。
	draw_string(ThemeDB.fallback_font, Vector2(0, -METRIC_OFFSET - 26.0),
			"%d × %d px" % [room_size.x, room_size.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, TOTAL_LABEL_SIZE, LABEL_COLOR)


## 四周外向刻度：短刻度每 100px，长刻度每 500px 并标数值。
func _draw_ruler_ticks(s: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var x := TICK_STEP
	while x < s.x - 0.5:
		var major_x := _is_major_tick(x)
		var len_x := TICK_MAJOR_LEN if major_x else TICK_MINOR_LEN
		draw_line(Vector2(x, 0), Vector2(x, -len_x), TICK_COLOR, 1.0)
		draw_line(Vector2(x, s.y), Vector2(x, s.y + len_x), TICK_COLOR, 1.0)
		if major_x:
			var text_x := str(roundi(x))
			var w_x := font.get_string_size(text_x, HORIZONTAL_ALIGNMENT_LEFT,
					-1, TICK_LABEL_SIZE).x
			draw_string(font, Vector2(x - w_x * 0.5, -TICK_MAJOR_LEN - 4.0), text_x,
					HORIZONTAL_ALIGNMENT_LEFT, -1, TICK_LABEL_SIZE, TICK_LABEL_COLOR)
			draw_string(font, Vector2(x - w_x * 0.5, s.y + TICK_MAJOR_LEN + 20.0), text_x,
					HORIZONTAL_ALIGNMENT_LEFT, -1, TICK_LABEL_SIZE, TICK_LABEL_COLOR)
		x += TICK_STEP
	var y := TICK_STEP
	while y < s.y - 0.5:
		var major_y := _is_major_tick(y)
		var len_y := TICK_MAJOR_LEN if major_y else TICK_MINOR_LEN
		draw_line(Vector2(0, y), Vector2(-len_y, y), TICK_COLOR, 1.0)
		draw_line(Vector2(s.x, y), Vector2(s.x + len_y, y), TICK_COLOR, 1.0)
		if major_y:
			var text_y := str(roundi(y))
			var w_y := font.get_string_size(text_y, HORIZONTAL_ALIGNMENT_LEFT,
					-1, TICK_LABEL_SIZE).x
			draw_string(font, Vector2(-TICK_MAJOR_LEN - 4.0 - w_y, y + 4.0), text_y,
					HORIZONTAL_ALIGNMENT_LEFT, -1, TICK_LABEL_SIZE, TICK_LABEL_COLOR)
			draw_string(font, Vector2(s.x + TICK_MAJOR_LEN + 4.0, y + 4.0), text_y,
					HORIZONTAL_ALIGNMENT_LEFT, -1, TICK_LABEL_SIZE, TICK_LABEL_COLOR)
		y += TICK_STEP


static func _is_major_tick(v: float) -> bool:
	return roundi(v) % int(TICK_MAJOR_STEP) == 0


func _draw_corner(origin: Vector2, dir: Vector2) -> void:
	var a := Vector2(origin.x + dir.x * CORNER_LEN, origin.y)
	var b := Vector2(origin.x, origin.y + dir.y * CORNER_LEN)
	draw_line(origin, a, CORNER_COLOR, CORNER_WIDTH)
	draw_line(origin, b, CORNER_COLOR, CORNER_WIDTH)


func _draw_metric(from: Vector2, to: Vector2, offset: Vector2, text: String) -> void:
	var p0 := from + offset
	var p1 := to + offset
	draw_line(p0, p1, METRIC_COLOR, 1.0)
	var tick := offset.normalized() * 8.0
	draw_line(p0 - tick, p0 + tick, METRIC_COLOR, 1.0)
	draw_line(p1 - tick, p1 + tick, METRIC_COLOR, 1.0)
	var mid := (p0 + p1) * 0.5
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, METRIC_LABEL_SIZE).x
	if absf(offset.y) > absf(offset.x):
		# 水平尺寸线：文字在中点上方。
		draw_string(font, mid + Vector2(-w * 0.5, -6.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, METRIC_LABEL_SIZE, LABEL_COLOR)
	else:
		# 垂直尺寸线：文字在中点左侧。
		draw_string(font, mid + Vector2(-w - 10.0, 5.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, METRIC_LABEL_SIZE, LABEL_COLOR)


# ---------------------------------------------------------------- 相机规则：数据 + 纯几何
# 这一组方法不接触场景树、不寻找 Camera2D、不移动任何节点。
# 游戏层拿到的只是「该把 limit / zoom / 相机位置写成什么」。

func camera_world_rect() -> Rect2:
	if _has_camera_world_rect:
		return _camera_world_rect
	return Rect2(global_position, Vector2(float(room_size.x), float(room_size.y)))


func camera_rules() -> Dictionary:
	return {
		"confine": camera_confine,
		"lock_mode": camera_lock_mode,
		"bounds": camera_bounds,
		"deadzone": camera_deadzone,
		"offset": camera_offset,
		"zoom": camera_zoom,
		"fit_mode": camera_fit_mode,
		"world_rect": camera_world_rect(),
	}


static func default_camera_rules() -> Dictionary:
	return {
		"confine": true,
		"lock_mode": 0,
		"bounds": Rect2(0, 0, 0, 0),
		"deadzone": Vector2(220, 140),
		"offset": Vector2(0, -60),
		"zoom": Vector2.ONE,
		"fit_mode": 0,
		"world_rect": Rect2(),
	}


## 世界矩形 → Camera2D 的四个 int limit。向内取整，保证不因取整露出 1px 房外。
## 返回 Rect2i：position = (left, top)，end = (right, bottom)。
static func limit_rect_from(world_bounds: Rect2) -> Rect2i:
	var l := ceili(world_bounds.position.x)
	var t := ceili(world_bounds.position.y)
	var r := floori(world_bounds.end.x)
	var b := floori(world_bounds.end.y)
	return Rect2i(l, t, maxi(1, r - l), maxi(1, b - t))


## 把相机中心夹到「可见矩形完全落在房间内」的区间；房间比视口小时退回居中。
static func clamp_camera_position(p_desired: Vector2, p_bounds: Rect2, p_view: Vector2) -> Vector2:
	var half := p_view * 0.5
	var lo := p_bounds.position + half
	var hi := p_bounds.end - half
	if hi.x < lo.x or hi.y < lo.y:
		return p_bounds.get_center()
	return Vector2(
		clampf(p_desired.x, lo.x, maxf(lo.x, hi.x)),
		clampf(p_desired.y, lo.y, maxf(lo.y, hi.y))
	)


## 视口大于房间时所需的最小 zoom（保证 viewport / zoom <= 房间尺寸）。
static func required_zoom(world_bounds: Rect2, viewport_size: Vector2, desired_zoom: Vector2) -> Vector2:
	var z := Vector2(maxf(absf(desired_zoom.x), 0.001), maxf(absf(desired_zoom.y), 0.001))
	var fit := Vector2(
		viewport_size.x / maxf(world_bounds.size.x, 1.0),
		viewport_size.y / maxf(world_bounds.size.y, 1.0)
	)
	return Vector2(maxf(z.x, fit.x), maxf(z.y, fit.y))


static func view_rect(screen_center: Vector2, view_size: Vector2) -> Rect2:
	return Rect2(screen_center - view_size * 0.5, view_size)


func _camera_local_bounds(room_s: Vector2) -> Rect2:
	if camera_bounds.size.x > 0.0 and camera_bounds.size.y > 0.0:
		return Rect2(camera_bounds.position, camera_bounds.size)
	return Rect2(Vector2.ZERO, room_s)


func _draw_camera_bounds() -> void:
	var s := Vector2(maxf(1.0, float(room_size.x)), maxf(1.0, float(room_size.y)))
	var b := _camera_local_bounds(s)
	var col := CAMERA_BOUNDS_COLOR if camera_confine else CAMERA_BOUNDS_OFF_COLOR
	draw_rect(b, CAMERA_BOUNDS_FILL, true)
	draw_rect(b.grow(-1.0), col, false, 2.0)
	var mode := SeamlessRoomI18n.t("Follow & Confine") \
			if camera_lock_mode == LOCK_FOLLOW_CONFINED else SeamlessRoomI18n.t("Fixed Center")
	var suffix := "" if camera_confine else SeamlessRoomI18n.t(" (disabled)")
	draw_string(ThemeDB.fallback_font, b.position + Vector2(8, 24),
			SeamlessRoomI18n.tf("Camera %s  %d × %d px%s",
					[mode, roundi(b.size.x), roundi(b.size.y), suffix]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, CAMERA_LABEL_SIZE, col)
