@tool
class_name RoomAtlasRoom2D
extends Node2D

## 房间场景可选基类：声明房间身份 / 尺寸，并在 2D 编辑器里常驻边界预览。
##
## 自建房间继承本类即可被 Room Atlas 编辑器识别：
## · room_id / room_size 由编辑器通过 SceneState 读取（列表信息、落图尺寸）
## · configure() 是运行时可选钩子，基类只记录 id，子类可覆盖并 super()
## · 改 room_size 会立即重绘边界；预览只在编辑器里画，运行时不产生绘制
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

const BOUNDS_COLOR := Color(0.25, 0.85, 1.0, 0.95)
const CORNER_COLOR := Color(0.45, 1.0, 0.75, 1.0)
const GRID_COLOR := Color(0.35, 0.7, 1.0, 0.10)
const FILL_COLOR := Color(0.2, 0.65, 1.0, 0.05)
const LABEL_COLOR := Color(0.75, 0.95, 1.0, 0.9)
const METRIC_COLOR := Color(0.55, 0.9, 1.0, 0.8)
const CORNER_LEN := 48.0
const CORNER_WIDTH := 4.0
const METRIC_OFFSET := 26.0


## 运行时可选钩子：基类只接收 id，子类可覆盖并 super() 后处理几何。
func configure(p_id: StringName, _p_placement: Resource, _p_cell_size: Vector2) -> void:
	room_id = p_id
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_editor_bounds:
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

	# 顶边 / 左边尺寸线，直接标出 W / H。
	_draw_metric(Vector2.ZERO, Vector2(s.x, 0),
			Vector2(0, -METRIC_OFFSET), "W %d px" % room_size.x)
	_draw_metric(Vector2.ZERO, Vector2(0, s.y),
			Vector2(-METRIC_OFFSET, 0), "H %d px" % room_size.y)

	# 房间上方写总尺寸，最直观。
	draw_string(ThemeDB.fallback_font, Vector2(0, -METRIC_OFFSET - 22.0),
			"%d × %d px" % [room_size.x, room_size.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, LABEL_COLOR)


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
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	if absf(offset.y) > absf(offset.x):
		# 水平尺寸线：文字在中点上方。
		draw_string(font, mid + Vector2(-w * 0.5, -6.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LABEL_COLOR)
	else:
		# 垂直尺寸线：文字在中点左侧。
		draw_string(font, mid + Vector2(-w - 10.0, 5.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LABEL_COLOR)
