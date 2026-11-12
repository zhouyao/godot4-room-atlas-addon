extends Node2D

## 示例装配序列：configure → track → ensure_room → to_world。
## 可见节点（网格、玩家、相机、调试层、小地图）在 main.tscn 里静态声明，
## 这里只注入依赖与装配顺序；插件不认识玩家、不移动任何节点。

const CONFIG_PATH := "res://world_config.tres"
const START_ROOM := &"r1"
const START_LOCAL := Vector2(2300, 600)

const CameraPolicy = preload("res://example/camera/camera_policy.gd")
const RoomCameraController = preload("res://example/camera/room_camera_controller.gd")
const CameraDebugPanel = preload("res://example/ui/camera_debug_panel.gd")
const RoomEntityDirector = preload("res://example/actors/room_entity_director.gd")

## main.tscn 里的场景节点：编辑器中可见，可调整层级、位置与参数。
## 用节点路径取引用；在编辑器里改节点名时要同步这里的路径。
@onready var actors: Node2D = $Actors
@onready var player: CharacterBody2D = $Actors/Player
@onready var player2: CharacterBody2D = $Actors/Player2
@onready var cam: Camera2D = $Camera2D
@onready var debug_overlay: Node2D = $DebugLayer/DebugOverlay
@onready var panel: CameraDebugPanel = $CameraDebugPanel
@onready var minimap: SeamlessRoomMinimap = $MinimapLayer/Minimap

## 逻辑节点仍由代码按装配顺序创建：streamer 要先 configure，director 要在
## controller.setup() 之前注入；policy 是 RefCounted，不能是场景节点。
var streamer: SeamlessRoomStreamer
var director: Node
var policy: RefCounted
var controller: Node


func _ready() -> void:
	var config := ResourceLoader.load(CONFIG_PATH) as SeamlessRoomConfig
	if config == null:
		push_error("[Seamless Rooms] 配置加载失败：" + CONFIG_PATH)
		return
	var result := SeamlessRoomValidator.validate(config)
	for w in result.warnings:
		push_warning("[Seamless Rooms] " + w)
	if not result.errors.is_empty():
		push_error("[Seamless Rooms] 配置不合法：\n" + SeamlessRoomValidator.format(result))
		return

	streamer = SeamlessRoomStreamer.new()
	streamer.name = "SeamlessRoomStreamer"
	add_child(streamer)
	streamer.configure(config)

	# 房间实体供给器：房间里的 Spawns 只提供出生点，实例统一挂到 Actors。
	director = RoomEntityDirector.new()
	director.name = "RoomEntityDirector"
	director.streamer = streamer
	director.actors = actors
	director.player = player
	director.pickup_scene = load("res://example/actors/pickups/pickup.tscn")
	add_child(director)

	# Overlays（血条 / 伤害数字）与全局唯一相机也由 main.tscn 提供。
	# 不开平滑：场景里已设 position_smoothing_enabled = false，
	# 平滑会让画面自己漂、掩盖真实位移。
	cam.make_current()

	# 全局唯一相机由控制器驱动：按 player 所在房间的规则锁定边界。
	policy = CameraPolicy.new()
	policy.changed.connect(_on_debug_option_changed)
	player.set("move_speed", policy.player_speed)
	controller = RoomCameraController.new()
	controller.name = "RoomCameraController"
	add_child(controller)
	controller.setup(streamer, player, cam, policy, START_ROOM, START_LOCAL)

	# player2 与 player 同一出生点，便于一起观察（player 已被控制器放到世界坐标）。
	player2.global_position = player.global_position

	# DebugLayer / DebugOverlay / CameraDebugPanel 已在 main.tscn 里摆好层级；
	# 这里只注入装配期才存在的对象（controller、policy、player）。
	debug_overlay.set("player", player)
	debug_overlay.set("controller", controller)
	debug_overlay.set("policy", policy)
	panel.setup(policy, controller)

	_build_minimap(config)
	minimap.show_room_ids = policy.show_minimap_ids

	print("[Seamless Rooms] 已就绪：WASD 移动 ｜ K 攻击最近的怪 ｜ E 开宝箱 ｜ Tab 显隐调试面板")


## demo：K 键对最近的怪造成伤害，用于验证死亡掉落。
func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_K:
		return
	# director 在配置校验失败时不会被创建；player 是场景节点，恒有效。
	if is_instance_valid(director):
		director.damage_nearest_enemy(player.global_position, 15.0, 700.0)


## 视差组件不认识相机：每帧把真实相机中心推给所有 SeamlessRoomParallax 实例。
## 放在 _process 而不是 _physics_process，保证读到的是控制器本帧移动后的相机。
func _process(_delta: float) -> void:
	get_tree().call_group(SeamlessRoomParallax.GROUP, &"set_camera_center",
			cam.get_screen_center_position())


func _physics_process(_delta: float) -> void:
	minimap.set_cursor_world_position(player.global_position)
	# 相机视野矩形：中心取真实屏幕中心，尺寸 = 视口 / zoom。
	if cam.zoom.x > 0.0 and cam.zoom.y > 0.0:
		var view := get_viewport().get_visible_rect().size / cam.zoom
		var center := cam.get_screen_center_position()
		minimap.set_camera_view(Rect2(center - view * 0.5, view))
	# 兜底：极端位置仍回起点（常规出房由控制器的 HOLD_AND_RESPAWN 处理）。
	if player.global_position.y > 6000.0 and controller != null:
		controller.respawn()


## 与相机几何无关的调试开关，由装配脚本直接落到对应节点。
func _on_debug_option_changed(key: StringName) -> void:
	match key:
		&"player_speed":
			player.set("move_speed", policy.player_speed)
		&"show_minimap_ids":
			minimap.show_room_ids = policy.show_minimap_ids
		&"show_minimap_camera":
			minimap.show_camera_view = policy.show_minimap_camera
		&"show_minimap_coords":
			minimap.show_cursor_coords = policy.show_minimap_coords
		&"reset":
			player.set("move_speed", policy.player_speed)
			minimap.show_room_ids = policy.show_minimap_ids
			minimap.show_camera_view = policy.show_minimap_camera
			minimap.show_cursor_coords = policy.show_minimap_coords


## 右上角小地图：MinimapLayer / Minimap 已在 main.tscn 里摆好锚点与尺寸，
## 这里只注入校验过的配置与调试开关，之后每帧由 _physics_process 推坐标。
func _build_minimap(p_config: SeamlessRoomConfig) -> void:
	minimap.configure(p_config)
	minimap.show_camera_view = policy.show_minimap_camera
	minimap.show_cursor_coords = policy.show_minimap_coords
	minimap.set_cursor_world_position(player.global_position)
