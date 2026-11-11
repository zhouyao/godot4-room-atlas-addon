extends Node2D

## 示例用世界网格：给自由移动的玩家一个位置参照。
## 房间场景已清空，若没有静态参照物，相机跟随会让人误以为玩家没动。
## 属于游戏层装饰，插件不认识它；需要的话直接删掉即可。
##
## 网格线在世界坐标里位置固定（对齐 STEP 的倍数），但每次只绘制相机视野
## 附近的一段：绘制量与地图总大小无关，上千间房也不会一次画几万条线。
## 相机移动不足 REDRAW_THRESHOLD 时不重绘。

const STEP := 120.0
const MAJOR_EVERY := 5
const REDRAW_THRESHOLD := 24.0
const MINOR_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const MAJOR_COLOR := Color(1.0, 1.0, 1.0, 0.18)

## 保留该字段只为兼容 main.gd 的装配；网格本身与房间配置无关。
@export var config: RoomAtlasConfig:
	set(value):
		config = value
		queue_redraw()

var _view_center := Vector2.ZERO
var _view_size := Vector2(1920, 1080)
var _last_center := Vector2.ZERO
var _last_view := Vector2.ZERO


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var cam := viewport.get_camera_2d()
	var center := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var zoom := Vector2.ONE
	if cam != null:
		zoom = Vector2(maxf(cam.zoom.x, 0.001), maxf(cam.zoom.y, 0.001))
	var view := viewport.get_visible_rect().size / zoom
	if center.distance_to(_last_center) < REDRAW_THRESHOLD \
			and view.is_equal_approx(_last_view):
		return
	_last_center = center
	_last_view = view
	_view_center = center
	_view_size = view
	queue_redraw()


func _draw() -> void:
	if _view_size.x <= 0.0 or _view_size.y <= 0.0:
		return
	# 视野外扩一格，保证滚到边界时不会出现空缺。
	var half := _view_size * 0.5 + Vector2(STEP, STEP)
	var x0 := floorf((_view_center.x - half.x) / STEP) * STEP
	var x1 := ceilf((_view_center.x + half.x) / STEP) * STEP
	var y0 := floorf((_view_center.y - half.y) / STEP) * STEP
	var y1 := ceilf((_view_center.y + half.y) / STEP) * STEP

	var x := x0
	while x <= x1:
		var major := int(roundf(x / STEP)) % MAJOR_EVERY == 0
		draw_line(Vector2(x, y0), Vector2(x, y1),
				MAJOR_COLOR if major else MINOR_COLOR, 1.0)
		x += STEP
	var y := y0
	while y <= y1:
		var major := int(roundf(y / STEP)) % MAJOR_EVERY == 0
		draw_line(Vector2(x0, y), Vector2(x1, y),
				MAJOR_COLOR if major else MINOR_COLOR, 1.0)
		y += STEP
