@tool
class_name SeamlessRoomParallaxLayer
extends Node2D

## 可选配套：SeamlessRoomParallax 下的一个视差层。
##
## 子节点直接按房间局部像素摆放，和 2D 编辑器里完全一致；运行时只有本节点的
## position 会被容器推动，子节点的相对位置永远不动。
##
## scroll_scale = 1 → 与普通世界物体同速（没有视差）；
## scroll_scale = 0 → 完全钉在屏幕上（最远）。
##
## 语义与 Godot Parallax2D.scroll_scale / Phaser scrollFactor 一致，是本组件对外的
## 唯一视差参数；参照系由父节点 SeamlessRoomParallax.reference_mode 决定。
##
## 编辑器预览同样由容器驱动；本脚本是 @tool，否则编辑器里会被当成占位实例。

@export_group("Parallax")
## 视差强度，X / Y 两轴分开设置：
## 1.0 = 与普通世界物体同速（没有视差）；0.0 = 完全钉在屏幕上（最远）；
## 0.0 ~ 1.0 之间 = 背景层，数值越小越远；大于 1 或负数 = 比世界更快（前景层）。
## 常用值：远景 (0.1, 1)、中景 (0.4, 1)；不做垂直视差时 Y 保持 1.0。
@export var scroll_scale := Vector2(0.2, 1.0):
	set(value):
		scroll_scale = value
		update_configuration_warnings()

@export_group("Shift Clamp")
## 位移钳制开关：默认关闭。镜头跨房、相机不受房间矩形限制（过场 / 自由跟随）、
## 或用了负 / 大于 1 的 scroll_scale 时可打开，防止层被推出构图。
## 打开后位移按轴夹在 [-min_shift, max_shift]（min_shift 为 0 时下限为 -max_shift）。
@export var clamp_shift := false:
	set(value):
		clamp_shift = value
		update_configuration_warnings()
## 正向最大位移（像素，相对作者摆放位置），仅 clamp_shift 打开时生效。
## 建议先按「(房间尺寸 - 视口尺寸) / 2 × (1 - scroll_scale)」估算，再用编辑器预览微调。
@export var max_shift := Vector2(400.0, 200.0):
	set(value):
		max_shift = value
		update_configuration_warnings()
## 负向最大位移（像素，取正值）：位移 <= 0 时最多往负方向走这么远。
## 0 = 与 max_shift 对称（默认，兼容旧场景）；填正值即非对称钳制。
## 可近似 Parallax2D.limit_begin / limit_end，但零点始终是作者摆放位置。
@export var min_shift := Vector2.ZERO:
	set(value):
		min_shift = value
		update_configuration_warnings()

## 作者摆放的位置，运行时所有偏移都叠加在它上面。
var _home := Vector2.ZERO
var _home_set := false
## 上一次由本脚本写出的 position，用来区分「外部改了作者位置」和「上一帧的位移」。
var _last_written := Vector2.INF


func _ready() -> void:
	_capture_home()


## 场景面板提示：父节点类型不对、视差实际不生效、z 顺序或内容类型不对时直接点出来。
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _find_rig() == null:
		warnings.append(SeamlessRoomI18n.t(
				"Parent is not a SeamlessRoomParallax; this layer will not receive camera updates."))
	# z 顺序看整条祖先链：band 分组和 rig 都可能带 z_index。
	var effective_z := z_index
	var ancestor := get_parent()
	while ancestor is CanvasItem:
		effective_z += (ancestor as CanvasItem).z_index
		if not (ancestor as CanvasItem).z_as_relative:
			break
		ancestor = ancestor.get_parent()
	# 世界同速放在前景 rig 里是合法的「前景遮片」（只借 z 顺序），不告警；
	# 放在世界后面则多半是漏了 scroll_scale。
	if scroll_scale.is_equal_approx(Vector2.ONE) and effective_z <= 0:
		warnings.append(SeamlessRoomI18n.t(
				"scroll_scale is (1, 1); this layer moves with the world and has no parallax effect."))
	var has_far_axis := scroll_scale.x < 1.0 or scroll_scale.y < 1.0
	var has_near_axis := scroll_scale.x > 1.0 or scroll_scale.y > 1.0
	if has_near_axis and effective_z <= 0:
		warnings.append(SeamlessRoomI18n.t(
				"scroll_scale > 1 is a foreground layer; set a positive z_index to draw above the world."))
	if has_far_axis and effective_z > 0:
		warnings.append(SeamlessRoomI18n.t(
				"scroll_scale < 1 with z_index > 0: this layer slides against the world; use scroll_scale ≈ 1 for ground-attached foreground art."))
	if _has_collision_child(self):
		warnings.append(SeamlessRoomI18n.t(
				"Parallax layers should not contain collision shapes; keep physics in the world layer."))
	if clamp_shift:
		warnings.append_array(_clamp_warnings())
	return warnings


## 视差层只应该放装饰：碰撞体留在世界层，否则视觉和物理会分离。
func _has_collision_child(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionObject2D or child is CollisionShape2D:
			return true
		if _has_collision_child(child):
			return true
	return false


## 层可以嵌在 band 分组里，向上找到 rig 即可。
func _find_rig() -> SeamlessRoomParallax:
	var node := get_parent()
	while node != null:
		if node is SeamlessRoomParallax:
			return node
		node = node.get_parent()
	return null


## 位移钳制的自检：无效上限、与钉屏层冲突、以及「永远不会触发」。
func _clamp_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var locked := _axes_of(max_shift.x <= 0.0, max_shift.y <= 0.0)
	if not locked.is_empty():
		warnings.append(SeamlessRoomI18n.tf(
				"clamp_shift is on but max_shift is <= 0 on %s: those axes cannot move in the positive direction.",
				[locked]))
	if min_shift.x < 0.0 or min_shift.y < 0.0:
		warnings.append(SeamlessRoomI18n.t(
				"min_shift is a positive magnitude; negative values fall back to symmetric -max_shift."))
	# scroll_scale = 0 的层靠 shift = camera_delta 抵消相机移动；夹住之后就不再钉屏。
	var pinned := _axes_of(
			is_zero_approx(scroll_scale.x), is_zero_approx(scroll_scale.y))
	if not pinned.is_empty():
		warnings.append(SeamlessRoomI18n.tf(
				"clamp_shift limits the screen-pinned %s axis (scroll_scale = 0); the layer drifts once the camera passes the limit.",
				[pinned]))
	# 相机留在房间内时 camera_delta 有上界：上限比它还大就一定不会触发。
	var travel := _camera_travel_bound()
	if travel != Vector2.INF:
		var lower := _shift_floor()
		var never := _axes_of(
				_scroll_never_clamped(0, travel.x, lower.x),
				_scroll_never_clamped(1, travel.y, lower.y))
		if not never.is_empty():
			warnings.append(SeamlessRoomI18n.tf(
					"clamp_shift never triggers on %s: the limits are >= the largest shift the camera can produce inside the room.",
					[never]))
	return warnings


## 单个轴是否「永远不会被夹到」；scroll_scale = 1 的轴本来就不位移，不参与判断。
func _scroll_never_clamped(axis: int, travel: float, lower_limit: float) -> bool:
	var scale := scroll_scale[axis]
	if is_equal_approx(scale, 1.0):
		return false
	var natural := absf(1.0 - scale) * travel
	return natural <= max_shift[axis] and natural <= -lower_limit


## 相机在房间内移动时 camera_delta 的上界；拿不到房间矩形时返回 INF。
## Room Center 最多偏离半间房；Custom 取参照点到较远边的距离。
func _camera_travel_bound() -> Vector2:
	var rig := _find_rig()
	if rig == null or rig.size.x <= 0.0 or rig.size.y <= 0.0:
		return Vector2.INF
	if rig.reference_mode == SeamlessRoomParallax.REFERENCE_CUSTOM:
		var local := rig.reference_local
		return Vector2(
				maxf(local.x, rig.size.x - local.x),
				maxf(local.y, rig.size.y - local.y))
	return rig.size * 0.5


## 把两个布尔轴拼成 "X" / "Y" / "X, Y"。
func _axes_of(axis_x: bool, axis_y: bool) -> String:
	var axes := PackedStringArray()
	if axis_x:
		axes.append("X")
	if axis_y:
		axes.append("Y")
	return ", ".join(axes)


## 每轴下限：min_shift 填正值时用它，0 时镜像 max_shift（兼容旧的对称语义）。
func _shift_floor() -> Vector2:
	return Vector2(
			-min_shift.x if min_shift.x > 0.0 else -max_shift.x,
			-min_shift.y if min_shift.y > 0.0 else -max_shift.y)


## 由 SeamlessRoomParallax 调用；camera_delta = 相机中心 - 容器参照点（世界单位）。
func apply_camera_delta(camera_delta: Vector2) -> void:
	# 外部（运行时脚本 / 场景搭建）改过 position：把它当成新的作者位置，
	# 否则 _home 会一直停在 _ready 时的旧值。
	if _last_written != Vector2.INF and not position.is_equal_approx(_last_written):
		_home = position
	# 支持在 _ready 之前先推一次（自检 / 工具脚本），此时现记作者位置。
	_capture_home()
	var shift := (Vector2.ONE - scroll_scale) * camera_delta
	if clamp_shift:
		var lower := _shift_floor()
		shift = Vector2(
				clampf(shift.x, lower.x, max_shift.x),
				clampf(shift.y, lower.y, max_shift.y))
	position = _home + shift
	_last_written = position


func _capture_home() -> void:
	if not _home_set:
		_home = position
		_home_set = true


## 编辑器保存前由容器调用：回到作者摆放的位置。
func reset_to_home() -> void:
	_capture_home()
	position = _home
	_last_written = _home
