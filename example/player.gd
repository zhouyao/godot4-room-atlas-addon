extends CharacterBody2D

## 示例用跟踪目标。它属于游戏层，插件完全不认识这个节点。

const SPEED := 420.0
const GRAVITY := 2000.0
const JUMP := -780.0
const MAX_FALL := 1400.0

var spawn_point := Vector2.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	z_index = 2
	var cs := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 14.0
	shape.height = 48.0
	cs.shape = shape
	add_child(cs)


func _physics_process(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += 1.0
	velocity.x = dir * SPEED
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	elif Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W):
		velocity.y = JUMP
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, Color(0.88, 0.93, 1.0))
