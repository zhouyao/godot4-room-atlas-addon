extends SceneTree

## headless 自检：验证相机规则的纯几何计算，不需要进入场景树。
## 运行：Godot --headless --path <proj> --script res://example/tests/camera_rules_probe.gd

const RoomCameraController = preload("res://example/camera/room_camera_controller.gd")

var _failed := 0


func _initialize() -> void:
	var r1 := Rect2(10141, -1080, 3000, 1080)
	_check("r1 四个 limit 与配置一致",
			SeamlessRoom2D.limit_rect_from(r1) == Rect2i(10141, -1080, 3000, 1080))
	_check("limit 向内取整，不留 1px 越界",
			SeamlessRoom2D.limit_rect_from(Rect2(0.2, 0.2, 10.8, 10.8)) == Rect2i(1, 1, 10, 10))
	_check("房间大于视口时保持期望 zoom",
			SeamlessRoom2D.required_zoom(r1, Vector2(1920, 1080), Vector2.ONE) == Vector2.ONE)
	var narrow := Rect2(0, 0, 2400, 1080)
	var wide := SeamlessRoom2D.required_zoom(narrow, Vector2(3000, 1080), Vector2.ONE)
	_check("视口宽于房间时抬高 zoom", is_equal_approx(wide.x, 1.25) and is_equal_approx(wide.y, 1.0))
	_check("相机中心夹在房间内",
			SeamlessRoom2D.clamp_camera_position(Vector2(99999, 0), r1, Vector2(1920, 1080))
					== Vector2(10141 + 3000 - 960, -540))
	_check("房间小于视口时退回居中",
			SeamlessRoom2D.clamp_camera_position(Vector2.ZERO,
					Rect2(0, 0, 1000, 500), Vector2(1920, 1080)) == Vector2(500, 250))
	_check("视图矩形以真实屏幕中心为准",
			SeamlessRoom2D.view_rect(Vector2(100, 50), Vector2(20, 10)) == Rect2(90, 45, 20, 10))

	var config := ResourceLoader.load("res://world_config.tres") as SeamlessRoomConfig
	if config == null:
		push_error("FAIL  world_config.tres 加载失败")
		quit(1)
		return
	var layout := SeamlessRoomLayout.new(config)
	_check("r1 世界矩形", layout.world_rect(&"r1") == r1)
	_check("nearest_room 落在 r1", layout.nearest_room(Vector2(10200, -500)) == &"r1")
	_check("nearest_room 落在 r2", layout.nearest_room(Vector2(7900, -500)) == &"r2")
	_check("nearest_room 半径外为空", layout.nearest_room(Vector2(1000000, 1000000)) == &"")

	# 1920×1080 基准视口：半径要覆盖半对角线，桶尺寸与视口高 / 房间高对齐。
	var half_diag := Vector2(1920, 1080).length() * 0.5
	_check("mount_distance 覆盖视口半对角线", config.streaming.mount_distance >= half_diag)
	_check("bucket_size 取 1080 与视口高对齐",
			is_equal_approx(config.streaming.bucket_size, 1080.0))
	_check("挂载半径未超出桶预算",
			config.streaming.mount_distance <= SeamlessRoomLayout.max_query_radius(
					config.streaming.bucket_size))

	# 方案 C：半径由游戏层按视口算好，插件只接受一个世界单位的长度。
	var dz := Vector2(220, 140)
	var off := Vector2(0, -60)
	var speed := 1480.0
	var tick := config.streaming.tick
	var latency := 240.0
	var far_corner := Vector2(960 + 220, 540 + 140 + 60).length()
	var r720 := RoomCameraController.compute_load_radius(
			Vector2(1280, 720), dz, off, speed, tick, latency)
	var r1080 := RoomCameraController.compute_load_radius(
			Vector2(1920, 1080), dz, off, speed, tick, latency)
	var r4k := RoomCameraController.compute_load_radius(
			Vector2(3840, 2160), dz, off, speed, tick, latency)
	_check("半径随分辨率单调增长", r720 < r1080 and r1080 < r4k)
	_check("半径覆盖视口半对角线", r1080 >= half_diag)
	_check("半径覆盖相机死区与 offset 偏移", r1080 >= far_corner)
	_check("半径包含 tick 位移与加载余量",
			is_equal_approx(r1080, far_corner + speed * tick + latency))
	_check("各分辨率半径都在桶预算内",
			r4k <= SeamlessRoomLayout.max_query_radius(config.streaming.bucket_size))
	_check("非法视口返回 0",
			is_equal_approx(RoomCameraController.compute_load_radius(
					Vector2.ZERO, dz, off, speed, tick, latency), 0.0))

	# 注入行为：插件不写回配置，且把半径限制在 [配置下限, 桶预算] 内。
	var st := SeamlessRoomStreamer.new()
	st.configure(config)
	var base := st.effective_distances()
	_check("未注入时等于配置基准",
			is_equal_approx(base.mount, config.streaming.mount_distance)
					and is_equal_approx(base.sleep, config.streaming.sleep_distance))
	st.set_load_radius(r1080)
	var eff := st.effective_distances()
	_check("注入半径生效", is_equal_approx(eff.mount, r1080))
	_check("滞回带按同一比例派生",
			is_equal_approx(eff.sleep, config.streaming.sleep_distance
					* r1080 / config.streaming.mount_distance))
	_check("配置未被写回", is_equal_approx(config.streaming.mount_distance, 1200.0))
	st.set_load_radius(NAN)
	_check("NaN 半径被忽略", is_equal_approx(st.effective_distances().mount, r1080))
	st.set_load_radius(INF)
	_check("INF 半径被桶预算截断",
			st.effective_distances().mount
					<= SeamlessRoomLayout.max_query_radius(config.streaming.bucket_size))
	st.free()

	# 桶边界：浮点 end 略越过桶线时，旧的「减 0.001」写法会少登记最后一桶。
	var frac := SeamlessRoomConfig.new()
	frac.cell_size = Vector2(0.0005, 1.0)
	var frac_s := SeamlessRoomStreamingSettings.new()
	frac_s.bucket_size = 600.0
	frac.streaming = frac_s
	var frac_room := SeamlessRoomPlacement.new()
	frac_room.id = &"frac"
	frac_room.cells = Rect2i(0, 0, 1200001, 600)  # end.x = 600.0005
	frac.rooms = [frac_room]
	var frac_layout := SeamlessRoomLayout.new(frac)
	_check("浮点 end 略越过桶线时不漏判",
			frac_layout.room_at(Vector2(600.0002, 100)) == &"frac")
	_check("桶线左侧仍可定位", frac_layout.room_at(Vector2(599.9, 100)) == &"frac")

	# 换桶尺寸不应改变查询结果（只改变索引粒度）。
	var alt := SeamlessRoomConfig.new()
	alt.cell_size = config.cell_size
	alt.rooms = config.rooms
	var alt_s := SeamlessRoomStreamingSettings.new()
	alt_s.bucket_size = 300.0
	alt.streaming = alt_s
	var alt_layout := SeamlessRoomLayout.new(alt)
	var probe_p := Vector2(10200, -500)
	_check("桶尺寸不影响 room_at", alt_layout.room_at(probe_p) == layout.room_at(probe_p))
	var near_a := layout.query_near(probe_p, 1200.0)
	var near_b := alt_layout.query_near(probe_p, 1200.0)
	var same_near := near_a.size() == near_b.size()
	for id in near_a:
		if not near_b.has(id):
			same_near = false
	_check("桶尺寸不影响 query_near 候选集", same_near)

	# 半径误配不能再让 query_near 枚举千万个桶。
	_check("负半径返回空", layout.query_near(probe_p, -1.0).is_empty())
	_check("NaN 半径返回空", layout.query_near(probe_p, NAN).is_empty())
	_check("INF 半径被桶预算截断", not layout.query_near(probe_p, INF).is_empty())

	var cover := layout.touching_bounds(&"r1")
	_check("相邻房间连成一片覆盖区", cover == Rect2(2941, -4320, 10200, 4320))
	_check("r2 与 r1 共享覆盖区（跨房不换边界）", layout.touching_bounds(&"r2") == cover)

	var rects := layout.touching_rects(&"r5")
	_check("覆盖区包含全部房间（全图连通）", rects.size() == config.rooms.size())

	# P0：同一片连通覆盖区跨房切换时签名不变，预计算结果可复用。
	var sig5 := RoomCameraController.cover_signature(rects)
	var rects_r1 := layout.touching_rects(&"r1")
	_check("不同起点的 BFS 顺序确实不同", rects != rects_r1)
	_check("跨房切换覆盖区签名一致",
			RoomCameraController.cover_signature(rects_r1) == sig5)
	var swapped: Array[Rect2] = rects.duplicate()
	swapped.reverse()
	_check("签名与矩形顺序无关",
			RoomCameraController.cover_signature(swapped) == sig5)
	var subset: Array[Rect2] = [rects[0]]
	_check("覆盖区变化时签名不同",
			RoomCameraController.cover_signature(subset) != sig5)

	_check("r5 右侧空白视图未被覆盖",
			not SeamlessRoomLayout.view_covered(Rect2(4400, -2500, 1920, 1080), rects))
	_check("完全在 r5 内的视图被覆盖",
			SeamlessRoomLayout.view_covered(Rect2(3000, -3100, 1920, 1080), rects))
	_check("跨 r1/r2 接缝的视图被覆盖",
			SeamlessRoomLayout.view_covered(Rect2(9200, -1080, 1920, 1080), rects))
	_check("房间边界的亚像素误差不算漏出",
			SeamlessRoomLayout.view_covered(Rect2(4381, -1080.25, 1920, 1080), rects))
	_check("L 形凹处视图未被覆盖",
			not SeamlessRoomLayout.view_covered(Rect2(6000, -2000, 1920, 1080), rects))

	var region := SeamlessRoomCameraRegion.build(rects, Vector2(1920, 1080))
	_check("预计算得到合法中心区域", not region.rects.is_empty())
	_check("r1 内合法中心被判定为合法", region.is_inside(Vector2(11581, -540)))
	_check("r5 内合法中心被判定为合法", region.is_inside(Vector2(4200, -2000)))
	_check("L 形凹处中心被判定为非法", not region.is_inside(Vector2(6000, -2000)))
	var projected := region.project(Vector2(4200, -2000), Vector2(6000, -2000))
	_check("精确投影把相机挡在 r5 右缘", projected.x <= 4382.0)
	_check("传送重定位落在 r1 合法区", region.is_inside(region.nearest(Vector2(12000, -500))))
	_check("L 形绕路先横向进入通道",
			is_equal_approx(region.waypoint(Vector2(5000, -540.5), Vector2(5000, -1280)).x, 4381.5))
	_check("零厚度水平带回程先纵向对齐",
			is_equal_approx(region.waypoint(Vector2(4000, -560), Vector2(4780, -560)).y, -540.5))
	_check("r5 右侧空白不会触发绕路",
			region.waypoint(Vector2(4381.5, -1920), Vector2(4441, -1920))
					.distance_to(Vector2(4381.5, -1920)) < 1.0)

	# 单房约束区（HARD_CUT）：某条轴等于可见尺寸时，另一条轴必须保留完整区间，
	# 否则相机会被钉在房间中心，玩家进房后直接出画。
	var solo_r5 := SeamlessRoomCameraRegion.build(
			[Rect2(2941, -3240, 2400, 2160)], Vector2(2400, 1080))
	_check("单房 r5：x 固定、y 保留整段可移动区间",
			is_equal_approx(solo_r5.nearest(Vector2(4141, -9999)).y, -2700.0)
					and is_equal_approx(solo_r5.nearest(Vector2(4141, 9999)).y, -1620.0))
	var solo_r6 := SeamlessRoomCameraRegion.build(
			[Rect2(2941, -4320, 5400, 1080)], Vector2(2400, 1080))
	_check("单房 r6：y 固定、x 保留整段可移动区间",
			is_equal_approx(solo_r6.nearest(Vector2(-9999, -3780)).x, 4141.0)
					and is_equal_approx(solo_r6.nearest(Vector2(9999, -3780)).x, 7141.0))
	_check("单房 r6：区间外仍判定非法", not solo_r6.is_inside(Vector2(5641, -3580)))
	var solo_r1 := SeamlessRoomCameraRegion.build(
			[Rect2(10141, -1080, 2400, 1080)], Vector2(2400, 1080))
	_check("单房 r1：两轴都退化时锁在房中心",
			solo_r1.nearest(Vector2.ZERO) == Vector2(11341, -540))

	# 连续滚动行为锁定：多矩形覆盖区不走单房补点分支，退化轴仍按原逻辑压点。
	var row_region := SeamlessRoomCameraRegion.build(
			[Rect2(0, 0, 2400, 1080), Rect2(2400, 0, 2400, 1080)], Vector2(1920, 1080))
	_check("多矩形覆盖区保持原有退化行为（连续滚动不受影响）",
			row_region.rects.size() == 1 and row_region.rects[0].size == Vector2.ZERO)

	var solo := SeamlessRoomConfig.new()
	var a := SeamlessRoomPlacement.new()
	a.id = &"a"
	a.cells = Rect2i(0, 0, 100, 100)
	var b := SeamlessRoomPlacement.new()
	b.id = &"b"
	b.cells = Rect2i(500, 0, 100, 100)
	solo.rooms = [a, b]
	_check("孤岛房间各自独立",
			SeamlessRoomLayout.new(solo).touching_bounds(&"a") == Rect2(0, 0, 100, 100))

	# P3：程序化大地图。插件不能只在 8 房规模下被验证；
	# 这里的 streaming 全部留默认值，走「自动推导」路径。
	var big := _make_grid_config(20, 10, 1200, 800)
	var big_layout := SeamlessRoomLayout.new(big)
	_check("大地图 200 房全部登记", big_layout.room_count() == 200)
	_check("大地图桶尺寸按房间短边自动推导",
			is_equal_approx(big_layout.bucket_size(), 800.0))
	var big_center := Vector2(7 * 1200 + 600, 4 * 800 + 400)
	var gid := StringName("g_7_4")
	_check("大地图 room_at 命中正确房间", big_layout.room_at(big_center) == gid)
	var big_near := big_layout.query_near(big_center, 1500.0)
	_check("大地图邻域查询非空且不返回全表",
			not big_near.is_empty() and big_near.size() < 200)
	_check("大地图最近房间按包围盒自动取半径",
			big_layout.nearest_room(big_center) == gid)
	var t0 := Time.get_ticks_usec()
	var big_rects := big_layout.touching_rects(gid)
	var t1 := Time.get_ticks_usec()
	_check("大地图连通区包含全部房间", big_rects.size() == 200)
	_check("大地图桶化 BFS 在预算内", t1 - t0 < 2_000_000)
	var t2 := Time.get_ticks_usec()
	var big_region := SeamlessRoomCameraRegion.build(big_rects, Vector2(1920, 1080))
	var t3 := Time.get_ticks_usec()
	_check("大地图预计算得到合法区域", not big_region.rects.is_empty())
	_check("大地图坐标压缩在预算内", t3 - t2 < 8_000_000)
	print("[Seamless Rooms] 大地图 200 房：桶化 BFS %d ms，坐标压缩 %d ms" % [
			(t1 - t0) / 1000, (t3 - t2) / 1000])
	_check("大地图配置校验通过", SeamlessRoomValidator.validate(big).errors.is_empty())
	var big_streamer := SeamlessRoomStreamer.new()
	big_streamer.configure(big)
	big_streamer.set_load_radius(2000.0)
	_check("大地图自动挂载上限大于 demo 的 8", big_streamer.mount_budget() > 8)
	big_streamer.free()

	# P4：边界完全不对齐的离散地图 —— 候选坐标不会像规则网格那样大量合并，
	# 是坐标压缩的最坏布局。房间彼此不连通，但一起传给 build() 压满候选网格。
	var scattered := _make_scattered_config(100)
	var scattered_layout := SeamlessRoomLayout.new(scattered)
	var scattered_groups := scattered_layout.connected_groups()
	_check("离散地图分出多个连通分量", scattered_groups.size() > 1)
	var all_rects: Array[Rect2] = []
	for group in scattered_groups:
		for r in group:
			all_rects.append(r)
	var s0 := Time.get_ticks_usec()
	var scattered_region := SeamlessRoomCameraRegion.build(all_rects, Vector2(1920, 1080))
	var s1 := Time.get_ticks_usec()
	_check("离散地图预计算完成", scattered_region != null)
	_check("离散地图坐标压缩在预算内", s1 - s0 < 15_000_000)
	print("[Seamless Rooms] 离散 100 房（最坏布局）：坐标压缩 %d ms" % [(s1 - s0) / 1000])

	# 缓存与预热：同一覆盖区 / 尺寸只算一次，分辨率切换后按尺寸区分。
	SeamlessRoomCameraRegion.clear_cache()
	_check("区域缓存可清空", SeamlessRoomCameraRegion.cache_size() == 0)
	var cached_a := SeamlessRoomCameraRegion.build_cached(all_rects, Vector2(1920, 1080))
	var after_first := SeamlessRoomCameraRegion.cache_size()
	var cached_b := SeamlessRoomCameraRegion.build_cached(all_rects, Vector2(1920, 1080))
	_check("缓存命中返回同一实例", cached_a == cached_b)
	_check("缓存命中不新增条目", SeamlessRoomCameraRegion.cache_size() == after_first)
	var cached_c := SeamlessRoomCameraRegion.build_cached(all_rects, Vector2(1280, 720))
	_check("缓存按可见尺寸区分", cached_c != cached_a)
	var pre_streamer := SeamlessRoomStreamer.new()
	pre_streamer.configure(big)
	pre_streamer.precompute_regions(Vector2(1920, 1080))
	_check("批量预热填满合法区域缓存", SeamlessRoomCameraRegion.cache_size() > 0)
	pre_streamer.free()

	# 可选配套：房间局部视差组件。相机中心由游戏层推入，插件不认识相机。
	var px_room := SeamlessRoom2D.new()
	px_room.room_size = Vector2i(2400, 1080)
	var px := SeamlessRoomParallax.new()
	var px_far := SeamlessRoomParallaxLayer.new()
	px_far.scroll_scale = Vector2(0.2, 1.0)
	var px_near := SeamlessRoomParallaxLayer.new()
	px_near.scroll_scale = Vector2(0.4, 1.0)
	px.add_child(px_far)
	px.add_child(px_near)
	px_room.add_child(px)
	root.add_child(px_room)
	px.set_camera_center(Vector2(1200, 540))
	_check("视差容器按房间矩形取尺寸与中心",
			px.size == Vector2(2400, 1080))
	_check("相机在房间中心时层不偏移",
			is_zero_approx(px_far.position.x) and is_zero_approx(px_near.position.x))
	px.set_camera_center(Vector2(1440, 540))
	_check("相机右移 240：远层右移 192、近层右移 144",
			is_equal_approx(px_far.position.x, 192.0)
					and is_equal_approx(px_near.position.x, 144.0))
	px.set_camera_center(Vector2(960, 540))
	_check("相机左移时层反向偏移",
			is_equal_approx(px_far.position.x, -192.0)
					and is_equal_approx(px_near.position.x, -144.0))
	px_far.clamp_shift = true
	px_far.max_shift = Vector2(100, 100)
	px.set_camera_center(Vector2(2400, 540))
	_check("clamp_shift 限制最大位移", is_equal_approx(px_far.position.x, 100.0))
	px_far.position = Vector2(999, 999)
	px_far.reset_to_home()
	_check("reset_to_home 回到作者位置", px_far.position == Vector2.ZERO)

	# 非对称钳制：min_shift 取正值；0 保持旧的对称语义。
	px_far.max_shift = Vector2(300, 100)
	px_far.min_shift = Vector2(40, 0)
	px.set_camera_center(Vector2(2400, 540))
	_check("max_shift 限制正向位移", is_equal_approx(px_far.position.x, 300.0))
	px.set_camera_center(Vector2(-600, 540))
	_check("min_shift 限制负向位移", is_equal_approx(px_far.position.x, -40.0))
	px_far.min_shift = Vector2.ZERO
	px.set_camera_center(Vector2(-600, 540))
	_check("min_shift 为 0 时下限镜像 max_shift",
			is_equal_approx(px_far.position.x, -300.0))

	# 钳制自检：上限覆盖房间内全部行程时提示「永远不会触发」。
	px_far.max_shift = Vector2(10, 10)
	_check("钳制上限有效时不提示", px_far._get_configuration_warnings().is_empty())
	px_far.max_shift = Vector2(2000, 2000)
	_check("钳制永远不会触发时给出提示",
			px_far._get_configuration_warnings().size() == 1)
	px_far.max_shift = Vector2(400, 200)

	# 参照系二选一：Room Center 默认，Custom 用房间局部点（固定机位 Boss 房 / 过场）。
	px_far.clamp_shift = false
	px_near.reset_to_home()
	px.reference_mode = SeamlessRoomParallax.REFERENCE_CUSTOM
	px.reference_local = Vector2(1200, 540)
	px.set_camera_center(Vector2(1200, 540))
	_check("Custom 参照与相机重合时层不偏移",
			is_zero_approx(px_far.position.x) and is_zero_approx(px_near.position.x))

	px.reference_local = Vector2.ZERO
	px.set_camera_center(Vector2(1200, 540))
	_check("Custom 参照在房间左上角时按相机位移偏移",
			is_equal_approx(px_far.position.x, 960.0)
					and is_equal_approx(px_near.position.x, 720.0))

	px.reference_mode = SeamlessRoomParallax.REFERENCE_ROOM_CENTER
	var ref_local_prop := {"name": "reference_local", "usage": PROPERTY_USAGE_DEFAULT}
	px._validate_property(ref_local_prop)
	_check("Room Center 下 reference_local 隐藏",
			ref_local_prop["usage"] == PROPERTY_USAGE_NONE)
	px.reference_mode = SeamlessRoomParallax.REFERENCE_CUSTOM
	ref_local_prop = {"name": "reference_local", "usage": PROPERTY_USAGE_DEFAULT}
	px._validate_property(ref_local_prop)
	_check("Custom 下 reference_local 显示",
			ref_local_prop["usage"] != PROPERTY_USAGE_NONE)
	px.reference_mode = SeamlessRoomParallax.REFERENCE_ROOM_CENTER

	px_far.scroll_scale = Vector2(0.2, 1.0)
	px_far.position = Vector2.ZERO
	px.set_camera_center(Vector2(1200.0, 540.0))

	px.clip_to_room = false
	_check("clip_to_room 关闭时同步 clip_contents", not px.clip_contents)
	px.clip_to_room = true
	_check("clip_to_room 开启时同步 clip_contents", px.clip_contents)

	# 校验：世界同速放在前景 rig 是合法的遮片；放在世界后面则提示没视差；
	# 背景速度画在前景则提示会相对地面滑动。
	px_near.scroll_scale = Vector2.ONE
	px_near.z_index = 10
	_check("世界同速的前景遮片不告警",
			px_near._get_configuration_warnings().is_empty())
	px_near.z_index = 0
	_check("世界同速的背景层提示没有视差",
			not px_near._get_configuration_warnings().is_empty())
	px_near.scroll_scale = Vector2(0.3, 1.0)
	px_near.z_index = 10
	_check("背景速度画在前景时提示滑动",
			not px_near._get_configuration_warnings().is_empty())
	px_room.free()

	print("[Seamless Rooms] 相机规则自检：%s" % ("全部通过" if _failed == 0 else "%d 项失败" % _failed))
	quit(1 if _failed > 0 else 0)


## 生成规则网格地图：房间彼此边贴合、全部连通，streaming 留默认走自动推导。
func _make_grid_config(cols: int, rows: int, w: int, h: int) -> SeamlessRoomConfig:
	var cfg := SeamlessRoomConfig.new()
	cfg.cell_size = Vector2(1, 1)
	cfg.streaming = SeamlessRoomStreamingSettings.new()
	var rooms: Array = []
	for y in range(rows):
		for x in range(cols):
			var p := SeamlessRoomPlacement.new()
			p.id = StringName("g_%d_%d" % [x, y])
			p.cells = Rect2i(x * w, y * h, w, h)
			p.scene = PackedScene.new()
			rooms.append(p)
	cfg.rooms = rooms
	return cfg


## 确定性伪随机：房间位置 / 尺寸都不同、彼此不连通，边界不共享，
## 用来压满 SeamlessRoomCameraRegion 的候选坐标（最坏布局）。
func _make_scattered_config(n: int) -> SeamlessRoomConfig:
	var cfg := SeamlessRoomConfig.new()
	cfg.cell_size = Vector2(1, 1)
	cfg.streaming = SeamlessRoomStreamingSettings.new()
	var rooms: Array = []
	var seed := 12345
	for i in range(n):
		seed = (seed * 1103515245 + 12345) % 2147483647
		var x := i * 2600 + (seed % 613)
		seed = (seed * 1103515245 + 12345) % 2147483647
		var y := (i % 17) * 1900 + (seed % 431)
		seed = (seed * 1103515245 + 12345) % 2147483647
		var w := 900 + (seed % 700)
		seed = (seed * 1103515245 + 12345) % 2147483647
		var h := 700 + (seed % 500)
		var p := SeamlessRoomPlacement.new()
		p.id = StringName("s_%d" % i)
		p.cells = Rect2i(x, y, w, h)
		p.scene = PackedScene.new()
		rooms.append(p)
	cfg.rooms = rooms
	return cfg


func _check(label: String, ok: bool) -> void:
	if ok:
		print("OK    ", label)
	else:
		_failed += 1
		push_error("FAIL  " + label)
