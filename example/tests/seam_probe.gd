extends SceneTree

## headless 自检：接缝过渡的数据与纯几何层（docs/seam-blending.md §11 P1）。
## 运行：Godot --headless --path <proj> --script res://example/tests/seam_probe.gd
## 与 camera_rules_probe.gd / room_template_probe.gd 相互独立；那两份已有的
## 历史失败不计入本自检，避免把基线问题混进新功能。

const CONFIG_PATH := "res://world_config.tres"
const BlendScript = preload("res://addons/seamless_rooms/companion/seamless_rooms_seam_blend.gd")

var _failed := 0


func _initialize() -> void:
	var config := ResourceLoader.load(CONFIG_PATH) as SeamlessRoomConfig
	if config == null:
		push_error("FAIL  world_config.tres 加载失败")
		quit(1)
		return

	# 1) 旧配置兼容：显式空 seams 时为空数组，不产生任何新增结论。
	var legacy := _make_config([])
	_check("旧配置 seam_configs() 为空", legacy.seam_configs().is_empty())
	_check("空 seams 不影响既有校验结论",
			SeamlessRoomValidator.validate(legacy).errors.is_empty())
	# P3 迁移：真实配置含 1 条启用的 r2/r1 接缝，保留示例已调好的参数。
	var demo_list := config.seam_configs()
	_check("示例配置含 1 条启用的 r2/r1 接缝",
			demo_list.size() == 1 and demo_list[0].key() == "r1|r2|0"
					and demo_list[0].enabled)
	if demo_list.size() == 1:
		var demo: SeamlessRoomSeam = demo_list[0]
		_check("示例接缝保留绿色 / core=0.0 / 宽度比例",
				is_equal_approx(demo.color.g, 0.21434534)
						and is_equal_approx(demo.core, 0.0)
						and is_equal_approx(demo.width_ratio, 1.0 / 3.0)
						and is_equal_approx(demo.feather_min, 1.35))

	# 2) 稳定键按 id 字典序，与几何左右无关。
	_check("make_key 按字典序归一化",
			SeamlessRoomSeam.make_key(&"r2", &"r1", 0) == "r1|r2|0"
					and SeamlessRoomSeam.make_key(&"r1", &"r2", 0) == "r1|r2|0")
	var sample := _seam(&"r2", &"r1", SeamlessRoomSeam.AXIS_X, true)
	_check("SeamlessRoomSeam.key() 与 make_key 一致", sample.key() == "r1|r2|0")

	# 3) 共享边几何：只取重叠区间，不取两房并集。
	var layout := SeamlessRoomLayout.new(config)
	var edges := layout.seams()
	var by_key := {}
	for e in edges:
		by_key[e["key"]] = e
	_check("共享边共 8 条", edges.size() == 8)
	for e in edges:
		print("      ", e["key"], "  at=", e["at"],
				"  [", e["from"], ", ", e["to"], "]  span=", e["span"])
	var vertical := 0
	for e in edges:
		if e["axis"] == SeamlessRoomSeam.AXIS_X:
			vertical += 1
	_check("竖直共享边 5 条", vertical == 5)
	_check("水平共享边 3 条", edges.size() - vertical == 3)

	var r2r1: Dictionary = by_key.get("r1|r2|0", {})
	_check("r2/r1 竖直缝 at=10141 且区间完整",
			not r2r1.is_empty() and is_equal_approx(r2r1["at"], 10141.0)
					and is_equal_approx(r2r1["from"], -1080.0)
					and is_equal_approx(r2r1["to"], 0.0)
					and is_equal_approx(r2r1["span"], 1080.0)
					and r2r1["low_id"] == &"r2" and r2r1["high_id"] == &"r1")
	var r3r2: Dictionary = by_key.get("r2|r3|0", {})
	_check("r3/r2 竖直缝 at=3141 且方位正确",
			not r3r2.is_empty() and is_equal_approx(r3r2["at"], 3141.0)
					and r3r2["low_id"] == &"r3" and r3r2["high_id"] == &"r2")
	var r7r8: Dictionary = by_key.get("r7|r8|0", {})
	_check("r7/r8 部分重叠只取交集（1040，不是并集）",
			not r7r8.is_empty() and is_equal_approx(r7r8["at"], 10741.0)
					and is_equal_approx(r7r8["from"], -4280.0)
					and is_equal_approx(r7r8["to"], -3240.0)
					and is_equal_approx(r7r8["span"], 1040.0))
	var r8r1: Dictionary = by_key.get("r1|r8|1", {})
	_check("r8/r1 水平缝 at=-1080 且区间为 x 重叠",
			not r8r1.is_empty() and is_equal_approx(r8r1["at"], -1080.0)
					and is_equal_approx(r8r1["from"], 10741.0)
					and is_equal_approx(r8r1["to"], 12661.0)
					and is_equal_approx(r8r1["span"], 1920.0)
					and r8r1["low_id"] == &"r8" and r8r1["high_id"] == &"r1")
	var r5r6: Dictionary = by_key.get("r5|r6|1", {})
	_check("r6/r5 水平缝 at=-3240",
			not r5r6.is_empty() and is_equal_approx(r5r6["at"], -3240.0)
					and is_equal_approx(r5r6["span"], 2400.0))
	_check("角接触不算共享边（r5/r3）", not by_key.has("r3|r5|0"))

	# 4) cell_size 换算：格坐标不变，世界坐标按比例放大。
	var scaled := _make_config([])
	scaled.cell_size = Vector2(2, 2)
	var scaled_by_key := {}
	for e in SeamlessRoomLayout.new(scaled).seams():
		scaled_by_key[e["key"]] = e
	var scaled_r2r1: Dictionary = scaled_by_key.get("r1|r2|0", {})
	_check("cell_size=2 时 at 与区间等比放大",
			not scaled_r2r1.is_empty()
					and is_equal_approx(scaled_r2r1["at"], 20282.0)
					and is_equal_approx(scaled_r2r1["span"], 2160.0))

	# 5) Validator 规则。
	var ok := SeamlessRoomValidator.validate(_make_config([sample]))
	_check("合法接缝无 ERROR", ok.errors.is_empty())
	_check("合法接缝无 WARN", ok.warnings.is_empty())

	var missing := _seam(&"r2", &"ghost", SeamlessRoomSeam.AXIS_X, true)
	var r_missing := SeamlessRoomValidator.validate(_make_config([missing]))
	_check("引用不存在房间报 WARN",
			_has_any(r_missing.warnings, "references a room", "不在地图上"))

	var wrong_axis := _seam(&"r2", &"r1", SeamlessRoomSeam.AXIS_Y, true)
	var r_wrong := SeamlessRoomValidator.validate(_make_config([wrong_axis]))
	_check("轴不对应共享边报 WARN",
			_has_any(r_wrong.warnings, "no longer matches", "已不对应"))

	var duplicate := SeamlessRoomValidator.validate(
			_make_config([sample, _seam(&"r1", &"r2", 0, true)]))
	_check("重复键报 ERROR",
			_has_any(duplicate.errors, "Duplicate seam key", "接缝键重复"))

	var bad_type := SeamlessRoomValidator.validate(_make_config(["not a seam"]))
	_check("非 SeamlessRoomSeam 报 ERROR",
			_has_any(bad_type.errors, "is not a SeamlessRoomSeam", "不是 SeamlessRoomSeam"))

	var bad_axis := _seam(&"r2", &"r1", 9, true)
	var r_bad_axis := SeamlessRoomValidator.validate(_make_config([bad_axis]))
	_check("非法 axis 报 ERROR",
			_has_any(r_bad_axis.errors, "invalid axis", "axis 非法"))

	var bad_params := _seam(&"r2", &"r1", 0, true)
	bad_params.width_ratio = 0.0
	var r_params := SeamlessRoomValidator.validate(_make_config([bad_params]))
	_check("非法宽度参数报 ERROR",
			_has_any(r_params.errors, "invalid width/core/feather", "羽化参数非法"))

	var no_shader := _seam(&"r2", &"r1", 0, true)
	no_shader.material_override = ShaderMaterial.new()
	var r_no_shader := SeamlessRoomValidator.validate(_make_config([no_shader]))
	_check("material_override 缺 shader 报 WARN",
			_has_any(r_no_shader.warnings, "has no shader", "没有 shader"))

	var plain_shader := Shader.new()
	plain_shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }"
	var no_premul := _seam(&"r2", &"r1", 0, true)
	var mat := ShaderMaterial.new()
	mat.shader = plain_shader
	no_premul.material_override = mat
	var r_no_premul := SeamlessRoomValidator.validate(_make_config([no_premul]))
	_check("material_override 未用预乘报 WARN",
			_has_any(r_no_premul.warnings, "blend_premul_alpha", "未使用"))

	# 6) P2 画布预览公式：与 shader 的 GLSL 写法数值一致。
	var max_err := 0.0
	for i in range(21):
		var u := -1.0 + 2.0 * float(i) / 20.0
		for c in [0.0, 0.12, 0.4]:
			for f in [1.0, 1.35, 2.0]:
				max_err = maxf(max_err, absf(
						SeamlessRoomSeam.feather_alpha(u, float(c), float(f))
						- _glsl_alpha(u, float(c), float(f))))
	_check("预览羽化公式与 shader 等价（误差 < 0.01）", max_err < 0.01)
	_check("羽化曲线中心不透明、两端透明",
			is_equal_approx(SeamlessRoomSeam.feather_alpha(0.0, 0.12, 1.0), 1.0)
					and is_zero_approx(SeamlessRoomSeam.feather_alpha(-1.0, 0.12, 1.0))
					and is_zero_approx(SeamlessRoomSeam.feather_alpha(1.0, 0.12, 1.0)))

	# 7) 房间改尺寸后共享边失效：这正是画布标红的判定条件。
	var moved := _make_config([_seam(&"r2", &"r1", 0, true)])
	for p in moved.placements():
		if p.id != &"r2":
			continue
		var shifted := SeamlessRoomPlacement.new()
		shifted.id = p.id
		shifted.cells = Rect2i(p.cells.position.x, p.cells.position.y,
				p.cells.size.x - 10, p.cells.size.y)
		moved.rooms[moved.rooms.find(p)] = shifted
		break
	var moved_keys := {}
	for e in SeamlessRoomLayout.new(moved).seams():
		moved_keys[e["key"]] = true
	_check("房间改尺寸后原共享边失效（标红条件）",
			not moved_keys.has("r1|r2|0"))
	_check("失效边的 enabled 配置仍被 Validator 报 WARN",
			_has_any(SeamlessRoomValidator.validate(moved).warnings,
					"no longer matches", "已不对应"))

	# 8) 画布新建的 seam 记录必须能随 world_config.tres 一起持久化。
	var rt := SeamlessRoomConfig.new()
	rt.streaming = SeamlessRoomStreamingSettings.new()
	var persisted := _seam(&"r2", &"r1", 0, true)
	persisted.color = Color(0.1, 0.2, 0.3, 1.0)
	rt.seams = [persisted]
	var tmp := "user://seam_roundtrip.tres"
	_check("含 seams 的配置可保存", ResourceSaver.save(rt, tmp) == OK)
	var loaded := ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_REPLACE) as SeamlessRoomConfig
	_check("接缝配置读回后 key 与颜色不丢失",
			loaded != null and loaded.seam_configs().size() == 1
					and loaded.seam_configs()[0].key() == "r1|r2|0"
					and is_equal_approx(loaded.seam_configs()[0].color.r, 0.1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# 9) P3 运行时组件：实例化后核对遮罩几何、材质与预乘契约。
	var blend_cfg := _make_config([])
	var blend_seam := _seam(&"r2", &"r1", 0, true)
	blend_seam.width_ratio = 1.0 / 3.0
	blend_seam.color = Color(0.1, 0.2, 0.3, 1.0)
	blend_cfg.seams = [blend_seam]
	var blend := BlendScript.new()
	blend.configure(blend_cfg)
	root.add_child(blend)
	await process_frame
	var rects: Array[ColorRect] = []
	for c in blend.get_children():
		if c is ColorRect:
			rects.append(c)
	_check("组件按 seam 生成 1 条遮罩", rects.size() == 1)
	var veil: ColorRect = rects[0] if not rects.is_empty() else null
	_check("遮罩位置 / 尺寸由共享边与 width_ratio 派生",
			veil != null
					and is_equal_approx(veil.position.x, 10141.0 - 360.0)
					and is_equal_approx(veil.position.y, -1080.0)
					and is_equal_approx(veil.size.x, 720.0)
					and is_equal_approx(veil.size.y, 1080.0))
	_check("遮罩 z 与鼠标过滤", veil != null
			and veil.z_index == -101
			and veil.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var blend_mat: ShaderMaterial = null
	if veil != null:
		blend_mat = veil.material as ShaderMaterial
	_check("遮罩使用 blend_premul_alpha shader", blend_mat != null and blend_mat.shader != null
			and blend_mat.shader.code.find("blend_premul_alpha") != -1)
	_check("材质 uniform 来自 seam 配置", blend_mat != null
			and is_equal_approx(blend_mat.get_shader_parameter(&"core"), 0.12)
			and is_equal_approx(blend_mat.get_shader_parameter(&"feather_min"), 1.0)
			and is_equal_approx(blend_mat.get_shader_parameter(&"axis"), 0.0))
	blend.free()

	var blend_off := BlendScript.new()
	blend_off.configure(_make_config([_seam(&"r2", &"r1", 0, false)]))
	root.add_child(blend_off)
	await process_frame
	_check("未启用的 seam 不生成遮罩", blend_off.get_child_count() == 0)
	blend_off.free()

	# 10) 端到端装配：main.tscn 注入的 config 真的驱动组件生成遮罩。
	var main_packed := load("res://example/main.tscn") as PackedScene
	var main_inst := main_packed.instantiate()
	root.add_child(main_inst)
	await process_frame
	var main_blend := main_inst.get_node_or_null("SeamBlend")
	_check("main.tscn 装配了 SeamBlend 组件", main_blend != null)
	if main_blend != null:
		var main_rects := 0
		var main_color := Color()
		for c in main_blend.get_children():
			if c is ColorRect:
				main_rects += 1
				main_color = (c as ColorRect).color
		_check("主场景生成 1 条遮罩且保留示例绿色",
				main_rects == 1 and is_equal_approx(main_color.g, 0.21434534))
	# 交给引擎按帧回收：直接 free() 时 viewport 仍持有 current camera 引用。
	main_inst.queue_free()
	await process_frame

	# 11) P4 FADE：按房间查询、组件跳过、背景 band 应用、前景不动。
	var fade_seam := _seam(&"r2", &"r1", 0, true)
	fade_seam.width_ratio = 1.0 / 3.0
	fade_seam.core = 0.0
	fade_seam.feather_min = 1.35
	var fade_cfg := _make_config([fade_seam])
	_check("seam_mode 默认 OVERLAY",
			fade_cfg.seam_mode == SeamlessRoomConfig.SEAM_MODE_OVERLAY)
	var fade_layout := SeamlessRoomLayout.new(fade_cfg)
	var fades := fade_layout.seam_fades_for_room(&"r2")
	_check("r2 有 2 条几何接缝、其中 1 条启用配置",
			fade_layout.seams_for_room(&"r2").size() == 2 and fades.size() == 1)
	var f_r1 := {}
	for e in fades:
		if e["key"] == "r1|r2|0":
			f_r1 = e
	_check("r2 的接缝查询带出方位与参数",
			not f_r1.is_empty()
					and f_r1["room_side"] == 1.0
					and is_equal_approx(f_r1["width_ratio"], 1.0 / 3.0)
					and is_equal_approx(f_r1["core"], 0.0)
					and is_equal_approx(f_r1["feather"], 1.35))

	fade_cfg.seam_mode = SeamlessRoomConfig.SEAM_MODE_FADE
	var fade_blend := BlendScript.new()
	fade_blend.configure(fade_cfg)
	root.add_child(fade_blend)
	await process_frame
	_check("FADE 模式组件不生成遮罩", fade_blend.get_child_count() == 0)
	fade_blend.free()

	var room2 = load("res://example/rooms/r2.tscn").instantiate()
	room2.call("configure", &"r2", fade_layout.placement(&"r2"), fade_layout.cell_size(),
			fade_layout.seam_fades_for_room(&"r2"))
	root.add_child(room2)
	await process_frame
	var far_layer := room2.get_node_or_null("BgParallax/Far") as CanvasItem
	var far_mat: ShaderMaterial = null
	if far_layer != null:
		far_mat = far_layer.material as ShaderMaterial
	_check("FADE：背景 band 挂上渐隐材质",
			far_mat != null and far_mat.shader != null
					and far_mat.shader.code.find("world_pos") != -1)
	var far_sprite: CanvasItem = null
	if far_layer != null and far_layer.get_child_count() > 0:
		far_sprite = far_layer.get_child(0) as CanvasItem
	_check("FADE：band 子 Sprite 使用父材质",
			far_sprite != null and far_sprite.use_parent_material)
	var occluders := room2.get_node_or_null("FgParallax/Occluders") as CanvasItem
	_check("FADE：前景 rig 不被应用", occluders != null and occluders.material == null)
	room2.queue_free()
	await process_frame

	# 12) FADE 下 streamer 真实挂载链路：注入 → 房间 → 视差 band。
	var stream_cfg := _make_config([fade_seam])
	stream_cfg.seam_mode = SeamlessRoomConfig.SEAM_MODE_FADE
	var streamer := SeamlessRoomStreamer.new()
	streamer.configure(stream_cfg)
	root.add_child(streamer)
	streamer.ensure_room(&"r2")
	await process_frame
	var mounted := streamer.mounted_room(&"r2")
	var injected: Array = []
	if mounted != null and mounted.get("seam_edges") is Array:
		injected = mounted.get("seam_edges")
	_check("FADE：streamer 挂载房间并注入接缝",
			mounted != null and injected.size() == 1)
	var m_far: CanvasItem = null
	if mounted != null:
		m_far = mounted.get_node_or_null("BgParallax/Far") as CanvasItem
	_check("FADE：挂载后背景 band 自动挂上材质",
			m_far != null and m_far.material != null)
	streamer.queue_free()
	await process_frame

	print("[Seamless Rooms] 接缝数据/几何自检：",
			"全部通过" if _failed == 0 else "%d 项失败" % _failed)
	quit(1 if _failed > 0 else 0)


## shader 中 pow(1 - smoothstep(core, 1, abs(u)), feather) 的等价写法。
func _glsl_alpha(u: float, p_core: float, feather: float) -> float:
	var x := clampf((absf(u) - p_core) / maxf(1.0 - p_core, 0.0001), 0.0, 1.0)
	var s := x * x * (3.0 - 2.0 * x)
	return pow(1.0 - s, feather)


func _make_config(p_seams: Array) -> SeamlessRoomConfig:
	var base := ResourceLoader.load(CONFIG_PATH) as SeamlessRoomConfig
	var cfg := SeamlessRoomConfig.new()
	cfg.rooms = base.rooms.duplicate()
	cfg.streaming = base.streaming
	cfg.seams = p_seams
	return cfg


func _seam(a: StringName, b: StringName, p_axis: int, p_enabled: bool) -> SeamlessRoomSeam:
	var s := SeamlessRoomSeam.new()
	s.left = a
	s.right = b
	s.axis = p_axis
	s.enabled = p_enabled
	return s


func _has_any(lines: Array, en: String, zh: String) -> bool:
	for line in lines:
		var text := String(line)
		if text.find(en) != -1 or text.find(zh) != -1:
			return true
	return false


func _check(label: String, ok: bool) -> void:
	if ok:
		print("OK    ", label)
	else:
		_failed += 1
		push_error("FAIL  " + label)
