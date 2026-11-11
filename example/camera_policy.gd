extends RefCounted

## 示例层相机策略：全部开关都可在运行时热切换，changed 信号驱动控制器幂等重算。
## 它属于游戏层，插件不认识这份数据。
##
## 开发期脚手架：`override_*`、显示开关与 `player_speed` 都是调试期
## 才需要的东西。正式项目应把它们拆成「相机运行参数」与「开发期调试开关」两份
## 数据，不要把整个对象原样搬进业务代码。

signal changed(key: StringName)

## 会改变相机几何或规则生效结果的开关：这些键变化后控制器必须幂等重算。
## 其余键（显示、玩家速度、防抖数值）都是每帧现读，重算没有意义。
## 白名单集中在这里，控制器不再维护容易漏项的字符串黑名单。
const CAMERA_KEYS := [
	&"reset", &"out_of_room", &"room_transition",
	&"override_room_rules", &"override_confine", &"override_fit_mode",
	&"override_deadzone", &"override_offset", &"override_zoom",
]

enum OutOfRoom {
	HOLD_LAST,          ## 保持上一房规则：画面最稳，但玩家可能走出屏幕
	HOLD_AND_RESPAWN,   ## 保持 + 出房即回起点
	UNLOCK,             ## 解除 limit，相机自由跟随（会看到房外）
	NEAREST_ROOM,       ## 用最近房间的规则（边界附近可能来回切）
}

enum RoomTransition {
	CONTINUOUS,         ## 连续滚动：同一片覆盖区内 limit 恒定，跨房不换边界（默认）
	HARD_CUT,           ## 当帧换 limit，切屏
}

## 与 RoomAtlasRoom2D 的常量一一对应，覆盖房间声明时使用。
## 锁死模式（固定中心）不提供运行时开关：相机始终跟随玩家、玩家始终在画面内；
## 跟随的松紧由每个房间自己声明的 camera_deadzone 决定（(0,0) = 每帧硬贴）。
const FIT_ZOOM_TO_FIT := 0
const FIT_LETTERBOX := 1
const FIT_CENTER_ONLY := 2

var out_of_room: OutOfRoom = OutOfRoom.HOLD_AND_RESPAWN
var room_transition: RoomTransition = RoomTransition.CONTINUOUS
var switch_cooldown: float = 0.0
var enter_margin: float = 0.0
## 玩家移动速度（像素/秒）：纯调试手感开关，由 main.gd 写入 Player.move_speed。
var player_speed: float = 1480.0

var override_room_rules: bool = false
var override_confine: bool = true
var override_fit_mode: int = FIT_ZOOM_TO_FIT
var override_deadzone: Vector2 = Vector2(220, 140)
var override_offset: Vector2 = Vector2(0, -60)
var override_zoom: Vector2 = Vector2.ONE

## 从上层房间向下跨层进入下层后，暂时冻结相机的横向跟随，
## 避免画面从上层重叠区滑到相邻下层房间（r5 右下角 → r4）。
var freeze_x_on_layer_change: bool = true
## 玩家水平位移超过该值（像素）后解除冻结，恢复横向跟随，防止玩家出画。
var freeze_release_margin: float = 240.0

var show_hud: bool = true
var show_player_room: bool = true
## 小地图是否显示每个房间的 id 角标；由 main.gd 写入 Minimap.show_room_ids。
var show_minimap_ids: bool = true
## 小地图是否显示相机位置与视野矩形；由 main.gd 写入 Minimap.show_camera_view。
var show_minimap_camera: bool = true
## 小地图是否显示玩家世界坐标；由 main.gd 写入 Minimap.show_cursor_coords。
var show_minimap_coords: bool = true
var panel_visible: bool = true


func set_option(key: StringName, value: Variant) -> void:
	if get(key) == value:
		return
	set(key, value)
	changed.emit(key)


func toggle(key: StringName) -> void:
	set_option(key, not bool(get(key)))


func cycle(key: StringName, count: int) -> void:
	set_option(key, (int(get(key)) + 1) % maxi(1, count))


## 该键变化后是否需要重建相机几何（策略 / 覆盖 / 规则生效结果）。
static func affects_camera(key: StringName) -> bool:
	return CAMERA_KEYS.has(key)


## 把面板上的全部开关恢复到启动默认值，并通知订阅者重算。
func reset_defaults() -> void:
	out_of_room = OutOfRoom.HOLD_AND_RESPAWN
	room_transition = RoomTransition.CONTINUOUS
	switch_cooldown = 0.0
	enter_margin = 0.0
	player_speed = 480.0
	freeze_x_on_layer_change = true
	freeze_release_margin = 240.0
	override_room_rules = false
	override_confine = true
	override_fit_mode = FIT_ZOOM_TO_FIT
	override_deadzone = Vector2(220, 140)
	override_offset = Vector2(0, -60)
	override_zoom = Vector2.ONE
	show_hud = true
	show_player_room = true
	show_minimap_ids = true
	show_minimap_camera = true
	show_minimap_coords = true
	panel_visible = true
	changed.emit(&"reset")
