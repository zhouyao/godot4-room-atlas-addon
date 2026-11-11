extends Node2D

## 示例装配序列：configure → track → ensure_room → to_world。
## 这段代码属于游戏层，用于演示"插件不认识玩家、不移动任何节点"。

const CONFIG_PATH := "res://world_config.tres"
const START_ROOM := &"r1"
const START_LOCAL := Vector2(2300, 600)

const CameraPolicy = preload("res://example/camera_policy.gd")
const RoomCameraController = preload("res://example/room_camera_controller.gd")
const CameraDebugPanel = preload("res://example/camera_debug_panel.gd")

var streamer: RoomAtlasStreamer
var player: CharacterBody2D
var player2: CharacterBody2D
var cam: Camera2D
var minimap: RoomAtlasMinimap
var policy: RefCounted
var controller: Node


func _ready() -> void:
	var config := ResourceLoader.load(CONFIG_PATH) as RoomAtlasConfig
	if config == null:
		push_error("[Room Atlas] 配置加载失败：" + CONFIG_PATH)
		return
	var result := RoomAtlasValidator.validate(config)
	for w in result.warnings:
		push_warning("[Room Atlas] " + w)
	if not result.errors.is_empty():
		push_error("[Room Atlas] 配置不合法：\n" + RoomAtlasValidator.format(result))
		return

	# 房间是空白的，铺一层世界网格，否则相机跟随会让移动看起来像静止。
	var grid := Node2D.new()
	grid.name = "WorldGrid"
	grid.z_index = -100
	grid.set_script(load("res://example/world_grid.gd"))
	grid.set("config", config)
	add_child(grid)

	streamer = RoomAtlasStreamer.new()
	streamer.name = "RoomAtlasStreamer"
	add_child(streamer)
	streamer.configure(config)

	player = CharacterBody2D.new()
	player.name = "Player"
	player.set_script(load("res://example/player.gd"))
	add_child(player)

	# 与 player 同样的加入方式：动态建节点、挂脚本、挂到场景树。
	player2 = CharacterBody2D.new()
	player2.name = "Player2"
	player2.set_script(load("res://example/player2.gd"))
	add_child(player2)

	cam = Camera2D.new()
	# 不开平滑：死区跟随已经保证连续移动，平滑会让画面自己漂、掩盖真实位移。
	cam.position_smoothing_enabled = false
	add_child(cam)
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
	if is_instance_valid(player2):
		player2.global_position = player.global_position

	var layer := CanvasLayer.new()
	# 调试标记要盖住世界层（0），但不能盖住小地图与调试面板。
	layer.layer = 1
	add_child(layer)
	var overlay := Node2D.new()
	overlay.set_script(load("res://example/debug_overlay.gd"))
	overlay.set("player", player)
	overlay.set("controller", controller)
	overlay.set("policy", policy)
	layer.add_child(overlay)

	var panel := CameraDebugPanel.new()
	panel.name = "CameraDebugPanel"
	add_child(panel)
	panel.setup(policy, controller)

	_build_minimap(config)
	minimap.show_room_ids = policy.show_minimap_ids

	print("[Room Atlas] 已就绪：WASD 移动 ｜ Tab 显隐调试面板")


## 视差组件不认识相机：每帧把真实相机中心推给所有 RoomAtlasParallax 实例。
## 放在 _process 而不是 _physics_process，保证读到的是控制器本帧移动后的相机。
func _process(_delta: float) -> void:
	if is_instance_valid(cam):
		get_tree().call_group(RoomAtlasParallax.GROUP, &"set_camera_center",
				cam.get_screen_center_position())


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(minimap):
		minimap.set_cursor_world_position(player.global_position)
		# 相机视野矩形：中心取真实屏幕中心，尺寸 = 视口 / zoom。
		if is_instance_valid(cam) and cam.zoom.x > 0.0 and cam.zoom.y > 0.0:
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
			if is_instance_valid(player):
				player.set("move_speed", policy.player_speed)
		&"show_minimap_ids":
			if is_instance_valid(minimap):
				minimap.show_room_ids = policy.show_minimap_ids
		&"show_minimap_camera":
			if is_instance_valid(minimap):
				minimap.show_camera_view = policy.show_minimap_camera
		&"show_minimap_coords":
			if is_instance_valid(minimap):
				minimap.show_cursor_coords = policy.show_minimap_coords
		&"reset":
			if is_instance_valid(player):
				player.set("move_speed", policy.player_speed)
			if is_instance_valid(minimap):
				minimap.show_room_ids = policy.show_minimap_ids
				minimap.show_camera_view = policy.show_minimap_camera
				minimap.show_cursor_coords = policy.show_minimap_coords


## 右上角小地图：外部把玩家坐标推进去，它负责换算与画光标。
func _build_minimap(p_config: RoomAtlasConfig) -> void:
	var layer := CanvasLayer.new()
	layer.name = "MinimapLayer"
	layer.layer = 2
	add_child(layer)

	minimap = RoomAtlasMinimap.new()
	minimap.name = "Minimap"
	layer.add_child(minimap)
	# 锚点钉在右上角，窗口缩放时自动跟随。
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -336.0
	minimap.offset_right = -16.0
	minimap.offset_top = 16.0
	# 底部留出坐标条高度，房间缩略图与坐标文字不抢位置。
	minimap.offset_bottom = 156.0
	minimap.configure(p_config)
	minimap.show_camera_view = policy.show_minimap_camera
	minimap.show_cursor_coords = policy.show_minimap_coords
	minimap.set_cursor_world_position(player.global_position)
