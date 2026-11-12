extends CharacterBody2D

## Player2：有重量（受重力下坠），可左右移动、可跳跃的独立角色。
## 与 player.gd 不同，它受重力影响、会落在房间平台上，并能起跳。
##
## 控制（与 player.gd 分开，避免按键冲突）：
##   左右移动：J / L
##   跳跃：空格 或 I（仅在站在地面时生效）
##
## "重量"由重力体现：mass 越大，下坠越快，手感越"重"。

const SPEED := 320.0
const JUMP_VELOCITY := -520.0
const GRAVITY := 1400.0

@export var move_speed: float = SPEED
@export var jump_velocity: float = JUMP_VELOCITY
@export var gravity: float = GRAVITY
## 重量：仅用于缩放重力下坠速度，越大越"重"（下坠越快）。
@export var mass: float = 1.0


func _ready() -> void:
	# 碰撞层 1，与房间平台（StaticBody2D，默认 layer 1）对齐，才能踩在上面。
	collision_layer = 1
	collision_mask = 1
	# z 由 Main/Actors 统一控制；实体自身保持 0 才能参与 y-sort。
	z_index = 0
	var cs := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 14.0
	shape.height = 48.0
	cs.shape = shape
	add_child(cs)


func _physics_process(delta: float) -> void:
	# 重量：始终向下施加重力（mass 越大下坠越明显）。
	if not is_on_floor():
		velocity.y += gravity * mass * delta
	else:
		# 贴地：消除残余下坠速度，避免 move_and_slide 抖动。
		if velocity.y > 0.0:
			velocity.y = 0.0

	# 左右移动
	var dir := 0.0
	if Input.is_key_pressed(KEY_J):
		dir -= 1.0
	if Input.is_key_pressed(KEY_L):
		dir += 1.0
	velocity.x = dir * move_speed

	# 跳跃：仅在站在地面上时触发，按住不会连跳。
	if is_on_floor() and (Input.is_key_pressed(KEY_SPACE)
			or Input.is_key_pressed(KEY_I)):
		velocity.y = jump_velocity

	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.62, 0.42))
