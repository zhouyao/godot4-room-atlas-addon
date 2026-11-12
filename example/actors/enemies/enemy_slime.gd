extends CharacterBody2D

## 示例领地怪：待机 → 追击 → 返回出生点。
## 由 RoomEntityDirector 生成到 Main/Actors；自身不属于房间节点。
## 只守自己的领地，玩家离开领地后慢慢走回出生点。

signal died

@export var move_speed := 110.0
@export var return_speed := 55.0
@export var max_health := 30.0
## 玩家离自己超过这个距离也放弃追击，避免被拖出房间。
@export var deaggro_radius := 520.0

enum State { IDLE, CHASE, RETURN }

var player: Node2D
var home_position := Vector2.ZERO
var territory_radius := 320.0
var aggro_radius := 220.0
var leash_radius := 480.0
var spawn_key: StringName = &""
var health := 0.0

var _state := State.IDLE
var _home_room: StringName = &""


func _ready() -> void:
	# 物理层 3 = Enemy（bitmask 4）；mask 只和世界（层 1）碰撞。
	collision_layer = 4
	collision_mask = 1
	z_index = 0
	health = max_health
	queue_redraw()


func setup(p_room: StringName, p_spawn: EnemySpawn, p_player: Node2D) -> void:
	_home_room = p_room
	home_position = global_position
	territory_radius = p_spawn.territory_radius
	aggro_radius = p_spawn.aggro_radius
	leash_radius = p_spawn.leash_radius
	player = p_player
	spawn_key = StringName("%s/%s" % [p_room, p_spawn.name])
	set_meta(&"home_room", p_room)
	set_meta(&"spawn_key", spawn_key)
	set_meta(&"respawn", p_spawn.respawn)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		velocity = Vector2.ZERO
		return

	var to_player := player.global_position - global_position
	var player_from_home := player.global_position.distance_to(home_position)
	var from_home := global_position.distance_to(home_position)

	match _state:
		State.IDLE:
			if to_player.length() <= aggro_radius and player_from_home <= territory_radius:
				_state = State.CHASE
		State.CHASE:
			if player_from_home > territory_radius \
					or from_home > leash_radius \
					or to_player.length() > deaggro_radius:
				_state = State.RETURN
		State.RETURN:
			if from_home <= 4.0:
				_state = State.IDLE

	var dir := Vector2.ZERO
	var speed := 0.0
	match _state:
		State.CHASE:
			dir = to_player.normalized()
			speed = move_speed
		State.RETURN:
			dir = (home_position - global_position).normalized()
			speed = return_speed

	velocity = dir * speed
	move_and_slide()


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	queue_redraw()
	if health <= 0.0:
		died.emit()
		queue_free()


func _draw() -> void:
	# 占位美术：带眼睛的史莱姆，避免依赖外部素材。
	var body := Color(0.35, 0.85, 0.55) if health > 0.0 else Color(0.4, 0.4, 0.4)
	draw_circle(Vector2.ZERO, 18.0, body)
	draw_circle(Vector2(-6.0, -4.0), 3.0, Color.WHITE)
	draw_circle(Vector2(6.0, -4.0), 3.0, Color.WHITE)
	draw_circle(Vector2(-6.0, -4.0), 1.4, Color(0.1, 0.15, 0.1))
	draw_circle(Vector2(6.0, -4.0), 1.4, Color(0.1, 0.15, 0.1))
