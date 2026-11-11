extends Node

## 示例层相机控制器：全局唯一 Camera2D 的驱动者。
##
## 每帧用 streamer.room_at(player) 判定当前房间，取该房间在 SeamlessRoom2D 上
## 声明的规则，再用配置里的权威几何把相机 limit / zoom / 位置夹在约束区内。
## 插件本身不认识相机、不移动节点。
##
## 连续滚动（默认）：SeamlessRoomCameraRegion 在「配置 + 视口 + zoom」确定后一次性
## 预算出相机中心的合法区域并缓存；运行期只查表 + 精确投影，没有逐帧覆盖检测、
## 没有二分、没有切屏。硬切一屏把约束区切回单间房，保留供对比。

const CameraPolicy = preload("res://example/camera_policy.gd")

const UNLIMITED := 10000000
## 窗口尺寸稳定这么久之后才重算预计算区域：拖拽 resize 期间尺寸每帧都在变，
## 立即重算会额外产生几毫秒的坐标压缩开销。
const VIEWPORT_SETTLE := 0.12
## 异步加载期间玩家继续移动的等效余量（世界像素），与分辨率无关。
const LOAD_LATENCY_MARGIN := 240.0

## 纯函数：游戏层按当前可见世界尺寸算出「该提前加载多远」，插件不参与推算。
## 最远可见角 = 半视图 + 相机中心相对玩家的最大偏移（死区 + offset）；
## 再补上两次调度之间玩家的位移，以及异步加载的等效延迟。
static func compute_load_radius(
		p_view_size: Vector2, p_deadzone: Vector2, p_offset: Vector2,
		p_speed: float, p_tick: float, p_latency: float) -> float:
	if not (p_view_size.x > 0.0 and p_view_size.y > 0.0):
		return 0.0
	var far := Vector2(
		p_view_size.x * 0.5 + absf(p_deadzone.x) + absf(p_offset.x),
		p_view_size.y * 0.5 + absf(p_deadzone.y) + absf(p_offset.y)
	)
	return far.length() + maxf(p_speed, 0.0) * maxf(p_tick, 0.0) \
			+ maxf(p_latency, 0.0)

## 顺序无关的覆盖区签名。touching_rects() 从不同房间出发时 BFS 顺序不同，
## 但同一片连通区是同一个矩形集合；直接比较 Array 会把「跨房」误判成「覆盖区变了」。
static func cover_signature(p_rects: Array) -> String:
	var parts: Array[String] = []
	for r in p_rects:
		parts.append(str(r))
	parts.sort()
	return "|".join(PackedStringArray(parts))


static func _merge_rects(p_rects: Array[Rect2]) -> Rect2:
	if p_rects.is_empty():
		return Rect2()
	var out := p_rects[0]
	for i in range(1, p_rects.size()):
		out = out.merge(p_rects[i])
	return out

var streamer: SeamlessRoomStreamer
var player: Node2D
var cam: Camera2D
var policy: RefCounted
var start_room: StringName = &"r1"
var start_local: Vector2 = Vector2.ZERO

var _active_room_id: StringName = &""
var _rules: Dictionary = {}
var _bounds := Rect2()          # 当前房间规则给出的单房矩形（状态显示 / 兜底用）
var _confine_rect := Rect2()    # 覆盖区包围盒：limit_* 粗约束 / auto_fit / HUD 数值
var _cover_rects: Array[Rect2] = []  # 参与预计算的房间矩形集合
var _cover_signature := ""          # 顺序无关的覆盖区签名，跨房复用预计算结果
var _region: SeamlessRoomCameraRegion = null  # 覆盖区 + 可见尺寸对应的预计算结果
var _last_viewport_size := Vector2.ZERO
var _precomputed_view := Vector2.ZERO
var _viewport_settle := 0.0
var _last_player_pos := Vector2.ZERO
var _teleported := false
var _player_step := 0.0
var _delta := 0.0               # 本帧物理步长，供跨层平滑回落使用
var _freeze_x := false            # 跨层后是否冻结横向跟随
var _freeze_anchor_x := 0.0       # 冻结时的玩家 x，用于判断解冻
var _view_size := Vector2.ZERO
var _zoom := Vector2.ONE
var _cooldown := 0.0
var _entry_blocked := false      # 想换房但被冷却 / 进入缓冲挡下，供 HUD 观察
var _unlocked := false
var _status: Dictionary = {}
var _inside := true
var _out_of_bounds := false


# ---------------------------------------------------------------- 装配

func setup(
		p_streamer: SeamlessRoomStreamer, p_player: Node2D, p_cam: Camera2D,
		p_policy: RefCounted, p_start_room: StringName, p_start_local: Vector2) -> void:
	streamer = p_streamer
	player = p_player
	cam = p_cam
	policy = p_policy
	start_room = p_start_room
	start_local = p_start_local

	# 先保证目标房间醒着，再放人，再注入跟踪目标。
	streamer.ensure_room(start_room)
	player.global_position = streamer.to_world(start_room, start_local)
	streamer.track(player)

	if policy != null and not policy.changed.is_connected(_on_policy_changed):
		policy.changed.connect(_on_policy_changed)
	_activate_room(start_room)
	# 记录当前视口，避免首帧把初始尺寸当成一次 resize 而触发防抖。
	_last_viewport_size = get_viewport().get_visible_rect().size


# ---------------------------------------------------------------- 主循环

func _physics_process(delta: float) -> void:
	if streamer == null or policy == null or not is_instance_valid(player) or not is_instance_valid(cam):
		return
	_delta = delta
	# 窗口拉伸会改变可见世界尺寸；等尺寸稳定后再重算，避免拖拽期间每帧重建区域。
	var vp := get_viewport().get_visible_rect().size
	if not vp.is_equal_approx(_last_viewport_size):
		_last_viewport_size = vp
		_viewport_settle = VIEWPORT_SETTLE
	elif _viewport_settle > 0.0:
		_viewport_settle = maxf(_viewport_settle - delta, 0.0)
		if _viewport_settle <= 0.0:
			_apply_camera_bounds()
	_cooldown = maxf(_cooldown - delta, 0.0)
	# 传送只按玩家位置的单帧跳变判定；相机被边界挡住时玩家继续走远不算传送。
	var pos := player.global_position
	_player_step = pos.distance_to(_last_player_pos)
	_teleported = _player_step > maxf(_view_size.x, 500.0)
	_last_player_pos = pos
	var id: StringName = streamer.room_at(player.global_position)
	_inside = id != &""
	if not _inside:
		_on_out_of_room()
	elif _unlocked or (id != _active_room_id and _cooldown <= 0.0 and _past_enter_margin(id)):
		if id != _active_room_id and _active_room_id != &"" and not _teleported:
			_note_layer_change(_active_room_id, id)
		_begin_room_switch(id)
	# 「想切但被挡下」单独记录：贴边界来回蹭时，HUD 能直接看到防抖正在生效。
	_entry_blocked = _inside and not _unlocked and id != _active_room_id \
			and (_cooldown > 0.0 or not _past_enter_margin(id))
	# 玩家纯垂直移动时保持冻结；一旦水平走远（或传送）就恢复跟随，避免出画。
	if _freeze_x and (_teleported or absf(pos.x - _freeze_anchor_x) > maxf(float(policy.freeze_release_margin), 0.0)):
		_freeze_x = false
	_follow_player()
	_update_status()


func _on_out_of_room() -> void:
	var mode: int = policy.out_of_room
	if mode == CameraPolicy.OutOfRoom.HOLD_AND_RESPAWN:
		respawn()
	elif mode == CameraPolicy.OutOfRoom.UNLOCK:
		if not _unlocked:
			_unlocked = true
			_apply_camera_bounds()
	elif mode == CameraPolicy.OutOfRoom.NEAREST_ROOM:
		var near := streamer.nearest_room(player.global_position)
		if near != &"" and near != _active_room_id and _cooldown <= 0.0:
			_begin_room_switch(near)
	# HOLD_LAST：什么都不做，规则与 limit 保持上一房，避免反复解除 / 生效。


## 只在「上层 → 下层」的垂直跨层时开启冻结。反向（下层 → 上层）必须先绕进
## L 形竖直通道，冻结横向会挡住这条唯一通路，所以不冻结。
func _note_layer_change(p_old: StringName, p_new: StringName) -> void:
	_freeze_x = false
	if not bool(policy.freeze_x_on_layer_change):
		return
	var a := streamer.world_rect(p_old)
	var b := streamer.world_rect(p_new)
	if a.size.x <= 0.0 or b.size.x <= 0.0:
		return
	if not is_equal_approx(a.end.y, b.position.y):
		return
	if minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x) <= 0.0:
		return
	_freeze_x = true
	_freeze_anchor_x = player.global_position.x


func _begin_room_switch(id: StringName) -> void:
	# 两种过渡都直接换规则；连续模式下约束区恒定，
	# 因此不会重设边界，相机位置保持连续。
	_unlocked = false
	_activate_room(id)


func _activate_room(id: StringName) -> void:
	_active_room_id = id
	if not streamer.is_mounted(id):
		streamer.ensure_room(id)
	_unlocked = false
	_refresh_rules(id)
	_apply_camera_bounds()
	_snap_or_clamp()
	cam.align()
	cam.force_update_scroll()
	if cam.position_smoothing_enabled:
		cam.reset_smoothing()
	_cooldown = maxf(policy.switch_cooldown, 0.0)


func _refresh_rules(id: StringName) -> void:
	var room: Node = streamer.mounted_room(id)
	if room is SeamlessRoom2D:
		_rules = (room as SeamlessRoom2D).camera_rules()
	else:
		_rules = SeamlessRoom2D.default_camera_rules()
	# 几何永远以配置为准，不用房间场景自己声明的 room_size。
	_rules["world_rect"] = streamer.world_rect(id)
	if policy.override_room_rules:
		_rules["confine"] = policy.override_confine
		_rules["fit_mode"] = policy.override_fit_mode
		_rules["deadzone"] = policy.override_deadzone
		_rules["offset"] = policy.override_offset
		_rules["zoom"] = policy.override_zoom
		_rules["bounds"] = Rect2(0, 0, 0, 0)
	var world: Rect2 = _rules["world_rect"]
	var b: Rect2 = _rules["bounds"]
	_bounds = Rect2(world.position + b.position, b.size) \
			if b.size.x > 0.0 and b.size.y > 0.0 else world
	# 连续模式：整片边贴合房间共用一个覆盖区，跨房时它不变，limit 不重设。
	# 硬切模式：约束区就是单间房，切换时才会出现切屏。
	if int(policy.room_transition) == CameraPolicy.RoomTransition.CONTINUOUS:
		_cover_rects = streamer.touching_rects(id)
		# 包围盒直接由已有矩形集合合并，避免 touching_bounds() 再跑一次 BFS。
		_confine_rect = _merge_rects(_cover_rects)
	else:
		_cover_rects = [_bounds]
		_confine_rect = _bounds
	# 覆盖区真的变了才让预计算失效。连续滚动下同一片连通区跨房不变，
	# 用顺序无关签名比较，避免每次切房重跑 O(N³) 的坐标压缩。
	var sig := cover_signature(_cover_rects)
	if sig != _cover_signature:
		_cover_signature = sig
		_region = null


# ---------------------------------------------------------------- 相机边界

## 幂等：任何策略变化都走这里重算，不改变当前房间、不触发换房。
func _apply_camera_bounds() -> void:
	if _rules.is_empty():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var desired: Vector2 = _rules["zoom"]
	_zoom = Vector2(maxf(absf(desired.x), 0.001), maxf(absf(desired.y), 0.001))
	if int(_rules["fit_mode"]) == SeamlessRoom2D.FIT_ZOOM_TO_FIT:
		_zoom = SeamlessRoom2D.required_zoom(_confine_rect, vp, _zoom)
	_view_size = vp / _zoom
	cam.zoom = _zoom
	# 尺寸变化后一次性预热所有连通分量的合法区域，首次切房不再现场计算。
	if streamer != null and not _view_size.is_equal_approx(_precomputed_view):
		_precomputed_view = _view_size
		streamer.precompute_regions(_view_size)
	# 游戏层负责视口相关的推算：插件只接受一个世界单位的半径。
	# 分辨率切换 / zoom 变化都会走这个幂等入口，注入值随之更新。
	if streamer != null:
		var dz: Vector2 = _rules.get("deadzone", Vector2.ZERO)
		var off: Vector2 = _rules.get("offset", Vector2.ZERO)
		var speed := 0.0
		if is_instance_valid(player):
			speed = float(player.get("move_speed"))
		var tick := 0.12
		if streamer.layout != null:
			tick = streamer.layout.streaming().tick
		streamer.set_load_radius(
				compute_load_radius(_view_size, dz, off, speed, tick, LOAD_LATENCY_MARGIN))
	# Camera2D.offset 在 limit 之后叠加，会推过边界；偏移统一加在相机位置上。
	cam.offset = Vector2.ZERO
	if bool(_rules["confine"]) and not _unlocked:
		var lr := SeamlessRoom2D.limit_rect_from(_confine_rect)
		cam.limit_left = lr.position.x
		cam.limit_top = lr.position.y
		cam.limit_right = lr.end.x
		cam.limit_bottom = lr.end.y
	else:
		cam.limit_left = -UNLIMITED
		cam.limit_top = -UNLIMITED
		cam.limit_right = UNLIMITED
		cam.limit_bottom = UNLIMITED
	cam.align()
	cam.force_update_scroll()


## 预计算结果按引用缓存：覆盖矩形变化时由 _refresh_rules() 置空，
## 可见尺寸变化时这里按 view_size 判断重算。运行期每帧只做两次比较。
func _ensure_region(p_view: Vector2) -> SeamlessRoomCameraRegion:
	if _region != null and _region.view_size.is_equal_approx(p_view):
		return _region
	if _cover_rects.is_empty():
		return null
	_region = SeamlessRoomCameraRegion.build_cached(_cover_rects, p_view)
	return _region


func _follow_player() -> void:
	if _rules.is_empty():
		return
	var target: Vector2
	if int(_rules["lock_mode"]) == SeamlessRoom2D.LOCK_FIXED_CENTER:
		target = _confine_rect.get_center()
	else:
		var off: Vector2 = _rules["offset"]
		var dz: Vector2 = _rules["deadzone"]
		var desired := player.global_position + off
		var d := desired - cam.global_position
		target = cam.global_position
		if absf(d.x) > dz.x:
			target.x = cam.global_position.x + d.x - signf(d.x) * dz.x
		if absf(d.y) > dz.y:
			target.y = cam.global_position.y + d.y - signf(d.y) * dz.y
	if bool(_rules["confine"]) and not _unlocked:
		# 一层刚好放满视口时（下排房间高 1080 = 视口高），把相机中心锁在该房间
		# 的垂直中线，避免玩家贴近上边界时镜头提前跨层露出上一层。
		# 房间高于视口（如 r5）则放开纵向，让跨层时镜头跟着玩家连续过渡，
		# 而不是瞬间切到另一层的中心范围。
		if int(_rules["lock_mode"]) != SeamlessRoom2D.LOCK_FIXED_CENTER \
				and _bounds.size.y <= _view_size.y + 1.0:
			var half_h := _view_size.y * 0.5
			var y_lo := _bounds.position.y + half_h
			var y_hi := _bounds.end.y - half_h
			if y_hi >= y_lo:
				var mid := (y_lo + y_hi) * 0.5
				# 相机已在房间中线范围内：只做正常夹取，防止玩家贴近房间
				# 边界时镜头提前跨层露出相邻层。
				if cam.global_position.y >= y_lo - 1.0 \
						and cam.global_position.y <= y_hi + 1.0:
					target.y = clampf(target.y, y_lo, y_hi)
				else:
					# 刚从相邻层进来（相机还停在上一层或下一层）：按时间平滑
					# 逼近中线（约 0.55 秒），r5→r6、r5→r4 都不会一帧切过去。
					# 过渡期间冻结横向目标，避免 waypoint 绕路把 y 也一起拽过去。
					target.y = move_toward(cam.global_position.y, mid,
							_view_size.y * 1.2 * _delta)
					target.x = cam.global_position.x
		if _teleported:
			var region := _ensure_region(_view_size)
			if region != null and not region.rects.is_empty():
				var aim: Vector2 = _rules["offset"]
				target = region.nearest(player.global_position + aim)
			else:
				target = _clamp_camera_to_coverage(target, _view_size)
		else:
			# 跨层冻结：不再主动把相机推向玩家 x，但仍允许 _clamp_camera_to_coverage
			# 为满足视图合法性做必要修正。
			if _freeze_x and int(_rules["lock_mode"]) != SeamlessRoom2D.LOCK_FIXED_CENTER:
				target.x = cam.global_position.x
			target = _clamp_camera_to_coverage(target, _view_size)
	cam.global_position = target


## 查表 + 精确投影：不再逐帧做覆盖检测或二分。
func _clamp_camera_to_coverage(p_desired: Vector2, p_view: Vector2) -> Vector2:
	var region := _ensure_region(p_view)
	if region == null or region.rects.is_empty():
		return SeamlessRoom2D.clamp_camera_position(p_desired, _confine_rect, p_view)
	var from := cam.global_position
	# 当前位置已不在合法区域（切策略 / 瞬移兜底）：立即落到最近合法中心。
	if not region.is_inside(from):
		return region.nearest(p_desired)
	var goal: Vector2
	if region.is_inside(p_desired):
		goal = p_desired
	else:
		var direct := region.project(from, p_desired)
		if direct.distance_to(p_desired) <= 1.0:
			goal = direct
		else:
			goal = region.waypoint(from, p_desired, _bounds.get_center().y)
	# 所有分支统一限速：相机被边界挡住时玩家仍在走远，目标一旦重新合法就会
	# 与当前位置拉开很大距离（r5 右下角下到 r4 时尤其明显），不能一帧跳过去。
	# 限速 = 基准平滑值 + 玩家步长的一半，既限制「追赶」的绝对速度，
	# 又保证相机始终比玩家略快，能补上 L 形绕路欠下的横向距离。
	var max_step := maxf(p_view.x, 500.0) * 0.02 + _player_step
	var step := goal - from
	if step.length() > max_step:
		goal = from + step.normalized() * max_step
	if region.is_inside(goal):
		return goal
	return region.project(from, goal)


## 硬切一屏：整屏换到目标房间的那一帧直接对准玩家（夹在该房合法区内），切完不脱节；
## 之后由 _follow_player() 按该房间自己声明的 camera_deadzone 跟随（(0,0) 即每帧硬贴）。
## 连续滚动：保持原行为，从旧相机位置最近的合法点落位，画面不跳、零改动。
func _snap_or_clamp() -> void:
	if int(policy.room_transition) == CameraPolicy.RoomTransition.HARD_CUT \
			and is_instance_valid(player):
		var aim: Vector2 = player.global_position + Vector2(_rules.get("offset", Vector2.ZERO))
		var region := _ensure_region(_view_size)
		if region != null and not region.rects.is_empty():
			cam.global_position = region.nearest(aim)
		else:
			# 房间比视口小：合法区为空，回退为房间居中（与跟随逻辑的兜底一致）。
			cam.global_position = SeamlessRoom2D.clamp_camera_position(
					aim, _confine_rect, _view_size)
		return
	_clamp_camera_now()


func _clamp_camera_now() -> void:
	if bool(_rules.get("confine", false)) and not _unlocked:
		cam.global_position = _clamp_camera_to_coverage(cam.global_position, _view_size)


func _past_enter_margin(id: StringName) -> bool:
	var margin := maxf(policy.enter_margin, 0.0)
	if margin <= 0.0:
		return true
	var inner := streamer.world_rect(id).grow(-margin)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return true
	return inner.has_point(player.global_position)


# ---------------------------------------------------------------- 回起点 / 策略热切换

func respawn() -> void:
	if streamer == null or not is_instance_valid(player):
		return
	streamer.ensure_room(start_room)
	player.global_position = streamer.to_world(start_room, start_local)
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO
	if player.has_method("reset_physics_interpolation"):
		player.call("reset_physics_interpolation")
	_unlocked = false
	_freeze_x = false
	_activate_room(start_room)
	_clamp_camera_now()


func _on_policy_changed(key: StringName) -> void:
	# 关闭冻结开关时立即恢复横向跟随。
	if key == &"freeze_x_on_layer_change":
		if not bool(policy.freeze_x_on_layer_change):
			_freeze_x = false
		return
	# 分类由策略对象自己维护，控制器不再维护字符串黑名单：
	# 显示 / 遮罩 / 玩家速度 / 防抖数值都是每帧现读，重算没有意义。
	if not CameraPolicy.affects_camera(key):
		return
	_reapply()


func _reapply() -> void:
	if _rules.is_empty() or not is_instance_valid(cam):
		return
	if _active_room_id != &"":
		_refresh_rules(_active_room_id)
	_apply_camera_bounds()
	_snap_or_clamp()
	cam.align()
	cam.force_update_scroll()


# ---------------------------------------------------------------- 状态输出（HUD / 调试层）

func status() -> Dictionary:
	return _status


func _update_status() -> void:
	var center := cam.get_screen_center_position()
	var view := SeamlessRoom2D.view_rect(center, _view_size)
	var fit := int(_rules.get("fit_mode", SeamlessRoom2D.FIT_ZOOM_TO_FIT))
	var confining: bool = bool(_rules.get("confine", false)) and not _unlocked
	var region := _ensure_region(_view_size)
	# 直接按「视图是否被房间并集完全覆盖」判定，与遮罩同一套几何；
	# 视口大于覆盖区时 region.rects 为空，旧判定会漏报。
	var covered := SeamlessRoomLayout.view_covered(view, _cover_rects)
	_out_of_bounds = confining and not covered
	# 复用同一个字典，避免每帧重新分配键。
	_status["room"] = _active_room_id
	_status["inside"] = _inside
	_status["confine"] = confining
	_status["bounds"] = _confine_rect
	_status["room_rect"] = _bounds
	_status["cover_rects"] = _cover_rects
	_status["cover_count"] = _cover_rects.size()
	_status["region_count"] = region.rects.size() if region != null else 0
	_status["view_rect"] = view
	_status["zoom"] = _zoom
	_status["fit_mode"] = fit
	_status["view_covered"] = covered
	_status["out_of_bounds"] = _out_of_bounds
	_status["freeze_x"] = _freeze_x
	_status["cooldown"] = _cooldown
	_status["entry_blocked"] = _entry_blocked
