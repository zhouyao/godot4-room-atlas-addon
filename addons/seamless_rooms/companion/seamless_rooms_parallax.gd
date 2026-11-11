@tool
class_name SeamlessRoomParallax
extends Control

## 可选配套：房间级视差容器，替代以世界原点为参照系的 Parallax2D。
##
## 语义以「房间矩形」而不是「世界原点」为参照：
##     shift = (1 - scroll_scale) * (相机中心 - 房间中心)
## scroll_scale = 1 → 与普通世界物体同速；0 → 钉在屏幕上（最远）。
## 相机正好在房间中心时 shift = 0，画面与 2D 编辑器里完全一致。
##
## 插件不认识相机：游戏层每帧把真实相机中心推给本节点（与 SeamlessRoomMinimap
## 的 set_cursor_world_position() 是同一套契约）。没人推时所有层停在作者摆放
## 的位置，失败模式是「没有视差」，而不是内容消失。
##
## 容器用 clip_contents 把各层裁在房间矩形内，背景不会画到隔壁房间。
##
## 编辑器预览：本脚本是 @tool。打开房间场景时把当前 2D 视图中心记为零点——此时
## 各层与作者摆放完全重合；平移视图即可实时看到视差（视图像移多少，模拟相机就
## 移多少）。预览位移不会写进 .tscn：保存前收到 NOTIFICATION_EDITOR_PRE_SAVE，
## 先把各层复位到作者摆放的位置，保存后再恢复预览。
##
## 结构：本节点（Control）下放若干 SeamlessRoomParallaxLayer，层里放 Sprite2D 等内容。

## 游戏层用 get_tree().call_group(&"seamless_rooms_parallax", &"set_camera_center", pos)
## 批量推送，不需要认识房间实例。
const GROUP := &"seamless_rooms_parallax"

## 父节点不是 SeamlessRoom2D 时使用的兜底房间尺寸。
@export var fallback_size := Vector2(2400.0, 1080.0)
## 是否把各层裁在房间矩形内。关闭后退化成不裁剪的房间局部视差。
@export var clip_to_room := true

@export_group("Editor Preview")
## 关掉后编辑器里不再驱动各层，恢复成纯作者摆放。
@export var editor_preview := true
## 手动预览偏移（叠加在视图平移上）。拖一下就能确认预览是否生效。
@export var editor_preview_offset := Vector2.ZERO

var _room_center := Vector2.ZERO
var _preview_view_origin := Vector2.INF
var _camera_center := Vector2.ZERO
var _has_camera := false
var _preview_reset := false
var _preview_logged := false
var _preview_moved_logged := false


func _ready() -> void:
	clip_contents = clip_to_room
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	_setup_rect()
	if Engine.is_editor_hint():
		set_process(true)
		print("[Seamless Rooms] parallax editor ready: ", get_path())


## 场景面板里给一个可见标记：确认编辑器确实把本节点当成 tool 实例在跑。
func _get_configuration_warnings() -> PackedStringArray:
	if Engine.is_editor_hint() and editor_preview:
		return [SeamlessRoomI18n.t(
				"Editor preview enabled: pan the 2D view to preview parallax; layers are restored when saving.")]
	return PackedStringArray()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not editor_preview:
		if not _preview_reset:
			_reset_layers()
		return
	_apply_editor_preview()


## 保存的是作者坐标，不是预览坐标：进编辑器保存流程前先把各层复位。
func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_reset_layers()
	elif what == NOTIFICATION_EDITOR_POST_SAVE and editor_preview:
		_apply_editor_preview()


## 游戏层每帧推入当前相机中心（世界坐标）。
## 推哪台相机、分屏怎么推，都由游戏层决定；插件只消费这个点。
func set_camera_center(world_pos: Vector2) -> void:
	# 支持在 _ready 之前先推一次（自检 / 工具脚本）：几何还没缓存时现算。
	if not is_node_ready():
		_setup_rect()
	_camera_center = world_pos
	_has_camera = true
	_apply()


## 各层共享同一个 camera_delta，避免每个层重复读相机 / 重复算房间中心。
func _apply() -> void:
	if not _has_camera:
		return
	_apply_delta(_camera_center - _room_center)


func _apply_delta(camera_delta: Vector2) -> void:
	for child in get_children():
		if child is SeamlessRoomParallaxLayer:
			(child as SeamlessRoomParallaxLayer).apply_camera_delta(camera_delta)


func _reset_layers() -> void:
	for child in get_children():
		if child is SeamlessRoomParallaxLayer:
			(child as SeamlessRoomParallaxLayer).reset_to_home()
	_preview_reset = true


# ---------------------------------------------------------------- 编辑器预览

func _apply_editor_preview() -> void:
	_setup_rect()
	var vp := get_viewport()
	if vp == null:
		return
	# 2D 编辑器视图中心 → 世界坐标，当成模拟相机中心。
	# 编辑器把平移/缩放放在 global_canvas_transform 里；canvas_transform 常是单位矩阵。
	var view_center := vp.global_canvas_transform.affine_inverse() \
			* (vp.get_visible_rect().size * 0.5)
	# 打开场景时的视图中心作为「相机在房间中心」的零点：
	# 刚打开时层停在作者摆放的位置，平移视图才产生视差，不会一进来就偏移。
	if _preview_view_origin == Vector2.INF:
		_preview_view_origin = view_center
	var delta := view_center - _preview_view_origin + editor_preview_offset
	_preview_reset = false
	_apply_delta(delta)
	if not _preview_logged:
		_preview_logged = true
		var layer_pos := Vector2.ZERO
		for child in get_children():
			if child is SeamlessRoomParallaxLayer:
				layer_pos = (child as SeamlessRoomParallaxLayer).position
				break
		print("[Seamless Rooms] parallax preview: origin=", _preview_view_origin,
				" view=", view_center, " delta=", delta,
				" layer=", layer_pos)
	elif not _preview_moved_logged and delta != Vector2.ZERO:
		_preview_moved_logged = true
		var moved := Vector2.ZERO
		for child in get_children():
			if child is SeamlessRoomParallaxLayer:
				moved = (child as SeamlessRoomParallaxLayer).position
				break
		print("[Seamless Rooms] parallax preview moved: delta=", delta, " layer=", moved)


## 几何的权威来源是配置注入的世界矩形，而不是场景里声明的 room_size。
## 单独打开房间场景 / 被别的容器复用时退回自己的尺寸。
func _setup_rect() -> void:
	var room := get_parent()
	if room is SeamlessRoom2D:
		var r := (room as SeamlessRoom2D).camera_world_rect()
		if r.size.x > 0.0 and r.size.y > 0.0:
			size = r.size
			_room_center = r.get_center()
			return
	if size.x <= 0.0 or size.y <= 0.0:
		size = fallback_size
	_room_center = global_position + size * 0.5
