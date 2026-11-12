extends CharacterBody2D

## 示例用跟踪目标：不受重力，方向键 / WASD 四向自由移动。
## 直接读按键而不依赖 InputMap 动作，避免项目输入映射缺失时按了没反应。
## 它属于游戏层，插件完全不认识这个节点。

## 默认移动速度（像素/秒）；由 main.gd 从 camera_policy.player_speed 写入。
const SPEED := 1480.0

@export var move_speed: float = SPEED

var spawn_point := Vector2.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	# z 由 Main/Actors 统一控制；实体自身保持 0 才能参与 y-sort。
	z_index = 0
	var cs := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 14.0
	shape.height = 48.0
	cs.shape = shape
	add_child(cs)

	# 拾取扫描：mask 16 = 物理层 5（Pickup）。
	var pickup := Area2D.new()
	pickup.name = "PickupArea"
	pickup.collision_layer = 0
	pickup.collision_mask = 16
	var pickup_shape := CollisionShape2D.new()
	var pickup_circle := CircleShape2D.new()
	pickup_circle.radius = 36.0
	pickup_shape.shape = pickup_circle
	pickup.add_child(pickup_shape)
	pickup.area_entered.connect(_on_pickup_area_entered)
	add_child(pickup)


func _on_pickup_area_entered(area: Area2D) -> void:
	if area.has_method(&"collect"):
		area.call(&"collect")


func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	velocity = dir.normalized() * move_speed
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, Color(0.88, 0.93, 1.0))
