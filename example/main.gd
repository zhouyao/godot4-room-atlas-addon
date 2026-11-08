extends Node2D

## 示例装配序列：configure → track → ensure_room → to_world。
## 这段代码属于游戏层，用于演示"插件不认识玩家、不移动任何节点"。

const CONFIG_PATH := "res://example/world_config.tres"
const START_ROOM := &"r1"
const START_LOCAL := Vector2(320, 600)

var streamer: RoomAtlasStreamer
var player: CharacterBody2D
var cam: Camera2D


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

	streamer = RoomAtlasStreamer.new()
	streamer.name = "RoomAtlasStreamer"
	add_child(streamer)
	streamer.configure(config)

	player = CharacterBody2D.new()
	player.name = "Player"
	player.set_script(load("res://example/player.gd"))
	add_child(player)

	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	cam.make_current()

	# 顺序很重要：先保证目标房间醒着，再放人、再硬切镜头。
	streamer.ensure_room(START_ROOM)
	player.set("spawn_point", streamer.to_world(START_ROOM, START_LOCAL))
	player.global_position = player.get("spawn_point")
	streamer.track(player)
	cam.global_position = player.global_position + Vector2(0, -60)

	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := Node2D.new()
	overlay.set_script(load("res://example/debug_overlay.gd"))
	overlay.set("streamer", streamer)
	overlay.set("config", config)
	layer.add_child(overlay)

	print("[Room Atlas] 已就绪：A/D 移动，空格跳跃，绿框为已挂载房间")


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(cam):
		return
	cam.global_position = player.global_position + Vector2(0, -60)
	# 掉出世界就回起点：这里演示游戏层自己用 API 完成"前往指定房间指定位置"。
	if player.global_position.y > 6000.0:
		streamer.ensure_room(START_ROOM)
		player.global_position = streamer.to_world(START_ROOM, START_LOCAL)
		player.velocity = Vector2.ZERO
		cam.reset_smoothing()
