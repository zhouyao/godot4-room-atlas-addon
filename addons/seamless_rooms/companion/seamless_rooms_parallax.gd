@tool
class_name SeamlessRoomParallax
extends Control

## 可选配套：房间级视差容器，替代以世界原点为参照系的 Parallax2D。
##
## 行业通用的 scroll_scale 语义（与 Godot Parallax2D / Phaser scrollFactor 一致）：
##     1 = 与普通世界物体同速；0 = 钉在屏幕上（最远）；>1 = 前景（更近）；
##     0 ~ 1 = 背景，数值越小越远。
##
## 本节点把参照系从「世界原点」换成可配置的 reference_mode：
##     shift = (1 - scroll_scale) * (相机中心 - reference)
## · Room Center：reference = 房间中心（默认）。相机在房间中心时 shift = 0，
##   画面与 2D 编辑器里完全一致，适合把房间当作构图单位。
## · Custom：reference = 房间左上角 + reference_local，用于固定机位 Boss 房 / 过场。
##
## 插件不认识相机：游戏层每帧把真实相机中心推给本节点（与 SeamlessRoomMinimap
## 的 set_cursor_world_position() 是同一套契约）。没人推时所有层停在作者摆放
## 的位置，失败模式是「没有视差」，而不是内容消失。
##
## 容器用 clip_contents 把各层裁在房间矩形内，背景不会画到隔壁房间。
##
## 编辑器预览：本脚本是 @tool。默认以打开场景时的 2D 视图中心为零点，各层与
## 作者摆放完全重合；平移视图即可实时看到视差。editor_preview_absolute 打开后
## 按运行时公式预览，视图中心就是当前相机中心。预览位移不会写进 .tscn：保存前
## 收到 NOTIFICATION_EDITOR_PRE_SAVE，先把各层复位到作者摆放的位置，保存后再恢复。
##
## 结构：本节点（Control）下放若干 SeamlessRoomParallaxLayer，层里放 Sprite2D 等内容。
## 层顺序即绘制顺序；背景与前景建议拆成两个容器，用 z_index 把世界夹在中间。

## 游戏层用 get_tree().call_group(&"seamless_rooms_parallax", &"set_camera_center", pos)
## 批量推送，不需要认识房间实例。
const GROUP := &"seamless_rooms_parallax"

const REFERENCE_ROOM_CENTER := 0
const REFERENCE_CUSTOM := 1

## 父节点不是 SeamlessRoom2D 时使用的兜底房间尺寸。
@export var fallback_size := Vector2(2400.0, 1080.0)
## 是否把各层裁在房间矩形内。关闭后退化成不裁剪的房间局部视差。
@export var clip_to_room := true:
	set(value):
		clip_to_room = value
		clip_contents = value

@export_group("Reference")
## 视差零点：相机正好在零点时 shift = 0。
## Room Center：房间中心（默认，适合直接在房间里按房间中心摆图）。
## Custom：房间左上角 + reference_local，适合固定机位 Boss 房 / 过场。
@export_enum("Room Center", "Custom")
var reference_mode := REFERENCE_ROOM_CENTER:
	set(value):
		if reference_mode == value:
			return
		reference_mode = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
## Custom 模式的零点，房间局部坐标（房间左上角 = (0,0)）。
## Room Center 模式下该属性会被隐藏并忽略。
@export var reference_local := Vector2.ZERO

@export_group("Editor Preview")
## 关掉后编辑器里不再驱动各层，恢复成纯作者摆放。
@export var editor_preview := true
## false：以打开场景时的视图中心为零点，只预览相对平移（方便摆图）。
## true：按运行时公式预览，视图中心就是当前相机中心（用于核对构图）。
@export var editor_preview_absolute := false
## 手动预览偏移（叠加在视图平移上）。拖一下就能确认预览是否生效。
@export var editor_preview_offset := Vector2.ZERO

var _reference_point := Vector2.ZERO
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


## Inspector 枚举标签跟随编辑器语言；存盘值仍是 int，切换语言不会改变场景数据。
func _validate_property(property: Dictionary) -> void:
	var property_name := String(property.get("name", ""))
	if property_name == "reference_mode":
		property["hint_string"] = SeamlessRoomI18n.t("Room Center") + "," \
				+ SeamlessRoomI18n.t("Custom")
	elif property_name == "reference_local" and reference_mode != REFERENCE_CUSTOM:
		property["usage"] = PROPERTY_USAGE_NONE


## 场景面板里给一个可见标记：确认编辑器确实把本节点当成 tool 实例在跑。
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not clip_to_room:
		warnings.append(SeamlessRoomI18n.t(
				"clip_to_room is off; parallax layers may draw into neighbouring rooms."))
	if Engine.is_editor_hint() and editor_preview:
		warnings.append(SeamlessRoomI18n.t(
				"Editor preview enabled: pan the 2D view to preview parallax; layers are restored when saving."))
	return warnings


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


## 各层共享同一个 camera_delta，避免每个层重复读相机 / 重复算参照点。
func _apply() -> void:
	if not _has_camera:
		return
	# configure() 可能在 _ready 之后才注入权威矩形；每帧刷新一次参照点，
	# 顺带覆盖流式重挂载后的位置变化。
	_setup_rect()
	_apply_delta(_camera_center - _reference_point)


## 递归遍历：7 个 band 分组可以是普通 Node2D，下面再挂任意多视差层。
func _apply_delta(camera_delta: Vector2) -> void:
	_apply_delta_recursive(self, camera_delta)


func _apply_delta_recursive(node: Node, camera_delta: Vector2) -> void:
	for child in node.get_children():
		if child is SeamlessRoomParallaxLayer:
			(child as SeamlessRoomParallaxLayer).apply_camera_delta(camera_delta)
		else:
			_apply_delta_recursive(child, camera_delta)


func _reset_layers() -> void:
	_reset_layers_recursive(self)
	_preview_reset = true


func _reset_layers_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is SeamlessRoomParallaxLayer:
			(child as SeamlessRoomParallaxLayer).reset_to_home()
		else:
			_reset_layers_recursive(child)


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
	var delta := Vector2.ZERO
	if editor_preview_absolute:
		# 视图中心就是相机中心：直接套运行时公式，方便核对与原场景的构图。
		delta = view_center - _reference_point
	else:
		# 打开场景时的视图中心作为零点：刚打开时层停在作者摆放的位置，
		# 平移视图才产生视差，不会一进来就偏移。
		if _preview_view_origin == Vector2.INF:
			_preview_view_origin = view_center
		delta = view_center - _preview_view_origin
	delta += editor_preview_offset
	_preview_reset = false
	_apply_delta(delta)
	if not _preview_logged:
		_preview_logged = true
		var layer_pos := Vector2.ZERO
		for child in get_children():
			if child is SeamlessRoomParallaxLayer:
				layer_pos = (child as SeamlessRoomParallaxLayer).position
				break
		print("[Seamless Rooms] parallax preview: mode=", reference_mode,
				" reference=", _reference_point, " view=", view_center,
				" delta=", delta, " layer=", layer_pos)
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
	var rect := Rect2(global_position, size)
	var room := get_parent()
	if room is SeamlessRoom2D:
		var r := (room as SeamlessRoom2D).camera_world_rect()
		if r.size.x > 0.0 and r.size.y > 0.0:
			size = r.size
			# 容器必须与房间左上角对齐，clip_contents 的裁剪框才是房间矩形。
			position = Vector2.ZERO
			rect = r
	if size.x <= 0.0 or size.y <= 0.0:
		size = fallback_size
		rect = Rect2(global_position, size)

	# Room Center 不依赖视口尺寸，窗口比例变化不会漂移。
	match reference_mode:
		REFERENCE_CUSTOM:
			_reference_point = rect.position + reference_local
		_:
			_reference_point = rect.get_center()
