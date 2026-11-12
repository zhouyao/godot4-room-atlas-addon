extends CanvasLayer

## 示例层调试面板：运行时热切换相机策略、跨层冻结、玩家速度、小地图显示，
## 并在面板顶部显示当前状态。属于游戏层，插件不认识它。
##
## 开发期工具：`override_*` 与显示开关只服务于调参对比，正式项目应当
## 用项目自己的调试入口按需实例化本面板，不要把它的字段当成业务配置。
##
## 布局：左侧一整块浮层卡片 = 标题栏 + 状态区 + 可滚动设置区 + 页脚，
## 只有 Tab 一个快捷键（显隐面板），其余开关都在卡片里点。

## 状态文字的重建间隔：肉眼 10Hz 足够，避免每帧产生大量临时字符串。
const HUD_INTERVAL := 0.1
## 设置区「标签 + 控件」两列里标签的固定宽度。
const LABEL_WIDTH := 110.0
## 面板宽度：与 1920 基准视口搭配，窄窗口下仍能完整显示一行控件。
const PANEL_WIDTH := 444.0

const BG_COLOR := Color(0.05, 0.07, 0.10, 0.94)
const BORDER_COLOR := Color(0.42, 0.62, 0.85, 0.35)
const GROUP_COLOR := Color(0.45, 0.80, 1.0, 1.0)
const TEXT_COLOR := Color(0.86, 0.90, 0.96, 1.0)
const TEXT_DIM := Color(0.62, 0.70, 0.80, 1.0)
const WARN_COLOR := Color(1.0, 0.42, 0.35, 1.0)

var policy: RefCounted
var controller: Node

var _root: PanelContainer
var _hud: Label
var _warn: Label
var _zoom_spin: SpinBox
var _options: Dictionary = {}
var _checks: Dictionary = {}
var _spins: Dictionary = {}
var _hud_timer := 0.0
var _syncing_ui := false


func setup(p_policy: RefCounted, p_controller: Node) -> void:
	policy = p_policy
	controller = p_controller
	layer = 20
	_build_ui()
	_sync_ui()


# ---------------------------------------------------------------- 布局骨架

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.anchor_left = 0.0
	_root.anchor_top = 0.0
	_root.anchor_right = 0.0
	_root.anchor_bottom = 1.0
	_root.offset_left = 16.0
	_root.offset_top = 16.0
	_root.offset_right = 16.0 + PANEL_WIDTH
	_root.offset_bottom = -16.0
	_root.add_theme_stylebox_override("panel", _card_style(BG_COLOR, true))
	add_child(_root)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_status())
	col.add_child(_separator())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)
	_build_settings(body)

	col.add_child(_separator())
	col.add_child(_build_footer())


## 标题栏：左标题、右 Tab 提示。
func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "房间相机调试"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var chip := Label.new()
	chip.text = "Tab 显隐"
	chip.add_theme_font_size_override("font_size", 11)
	chip.add_theme_color_override("font_color", TEXT_DIM)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	return row


## 状态区：三行只读信息 + 越界警告，藏在独立底色的子卡片里。
func _build_status() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(Color(1, 1, 1, 0.05), false))

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)

	_hud = Label.new()
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_theme_font_size_override("font_size", 11)
	_hud.add_theme_color_override("font_color", TEXT_DIM)
	box.add_child(_hud)

	_warn = Label.new()
	_warn.text = "相机视野超出房间覆盖区"
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.add_theme_font_size_override("font_size", 12)
	_warn.add_theme_color_override("font_color", WARN_COLOR)
	box.add_child(_warn)
	return card


## 页脚：快捷键说明 + 恢复默认。
func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.text = "Tab 显隐 ｜ 改动不写回 .tscn"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)

	var reset := Button.new()
	reset.text = "恢复默认"
	reset.tooltip_text = "把上面所有开关恢复到启动时的默认值"
	reset.custom_minimum_size = Vector2(84, 28)
	reset.pressed.connect(func() -> void:
		policy.reset_defaults()
		_sync_ui())
	row.add_child(reset)
	return row


# ---------------------------------------------------------------- 设置区

func _build_settings(vb: VBoxContainer) -> void:
	_add_group(vb, "相机策略")
	_add_option(vb, &"out_of_room", "房间外策略",
			PackedStringArray(["保持上一房", "保持并回起点", "解除约束", "最近房间"]))
	_add_option(vb, &"room_transition", "跨房过渡",
			PackedStringArray(["连续滚动（无切换）", "硬切一屏"]))
	_add_option(vb, &"override_fit_mode", "视口适配",
			PackedStringArray(["自动抬高缩放", "保持缩放（不抬 zoom）", "仅居中"]))

	_add_group(vb, "房间规则覆盖")
	_add_check(vb, &"override_room_rules", "覆盖房间声明的规则")
	_add_check(vb, &"override_confine", "约束生效（覆盖时）")
	_add_zoom_spin(vb)

	_add_group(vb, "调试绘制")
	_add_check(vb, &"show_hud", "显示状态区")
	_add_check(vb, &"show_player_room", "标记玩家房内 / 外")

	_add_group(vb, "小地图")
	_add_check(vb, &"show_minimap_ids", "显示房间 id")
	_add_check(vb, &"show_minimap_camera", "显示相机视野")
	_add_check(vb, &"show_minimap_coords", "显示玩家坐标")

	_add_group(vb, "跨层与手感")
	_add_check(vb, &"freeze_x_on_layer_change", "跨层冻结横向（上层 → 下层）")
	_add_spin(vb, &"freeze_release_margin", "解冻位移（px）", 60.0, 1200.0, 60.0)
	_add_spin(vb, &"player_speed", "玩家速度（px/s）", 60.0, 2000.0, 20.0)

	_add_group(vb, "过渡时序")
	_add_spin(vb, &"switch_cooldown", "切换冷却（s）", 0.0, 1.0, 0.05)
	_add_spin(vb, &"enter_margin", "进入缓冲（px）", 0.0, 200.0, 10.0)


func _add_group(vb: VBoxContainer, text: String) -> void:
	if vb.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 8.0
		vb.add_child(gap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var bar := ColorRect.new()
	bar.color = GROUP_COLOR
	bar.custom_minimum_size = Vector2(3, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", GROUP_COLOR)
	row.add_child(lab)
	vb.add_child(row)


## 统一的「左侧标签 + 右侧控件」行。
func _row(vb: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	var lab := Label.new()
	lab.text = text
	lab.custom_minimum_size.x = LABEL_WIDTH
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", TEXT_COLOR)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	return row


func _add_option(vb: VBoxContainer, key: StringName, text: String, items: PackedStringArray) -> void:
	var row := _row(vb, text)
	var opt := OptionButton.new()
	for item in items:
		opt.add_item(item)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", 13)
	opt.item_selected.connect(func(idx: int) -> void:
		# _sync_ui() 会程序化 select()；这期间不能把「用户交互」的逻辑再跑一遍。
		if _syncing_ui:
			return
		# 几何类覆盖项必须与 override_room_rules 配套，否则改了不生效。
		if key == &"override_fit_mode":
			policy.set_option(&"override_room_rules", true)
		policy.set_option(key, idx)
		_sync_ui())
	row.add_child(opt)
	_options[key] = opt


func _add_check(vb: VBoxContainer, key: StringName, text: String) -> void:
	var cb := CheckButton.new()
	cb.text = text
	cb.add_theme_font_size_override("font_size", 13)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.toggled.connect(func(pressed: bool) -> void: policy.set_option(key, pressed))
	vb.add_child(cb)
	_checks[key] = cb


func _add_spin(vb: VBoxContainer, key: StringName, text: String,
		p_min: float, p_max: float, p_step: float) -> void:
	var sp := _spin_row(vb, text, p_min, p_max, p_step)
	sp.value_changed.connect(func(v: float) -> void: policy.set_option(key, v))
	_spins[key] = sp


func _add_zoom_spin(vb: VBoxContainer) -> void:
	_zoom_spin = _spin_row(vb, "缩放（覆盖）", 0.25, 4.0, 0.25)
	_zoom_spin.tooltip_text = "覆盖所有房间的 camera_zoom。会自动打开「覆盖房间声明的规则」；" \
			+ "「视口适配」为自动抬高缩放时，低于阈值的取值会被逐轴抬高"
	_zoom_spin.value_changed.connect(func(v: float) -> void:
		# 与「视口适配」下拉保持一致：改几何类覆盖值时自动打开规则覆盖，避免改了不生效。
		policy.set_option(&"override_room_rules", true)
		policy.set_option(&"override_zoom", Vector2(v, v))
		_sync_ui())


func _spin_row(vb: VBoxContainer, text: String,
		p_min: float, p_max: float, p_step: float) -> SpinBox:
	var row := _row(vb, text)
	var sp := SpinBox.new()
	sp.min_value = p_min
	sp.max_value = p_max
	sp.step = p_step
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	return sp


## 面板卡片与子卡片的底色 / 描边；带阴影的那层只用于最外层，避免重复绘制。
func _card_style(bg: Color, with_shadow: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(1)
	if with_shadow:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 10
	return sb


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = Color(1, 1, 1, 0.10)
	sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sb)
	return sep


func _sync_ui() -> void:
	_syncing_ui = true
	for key in _options:
		var opt: OptionButton = _options[key]
		opt.select(clampi(int(policy.get(key)), 0, maxi(0, opt.item_count - 1)))
	for key in _checks:
		(_checks[key] as CheckButton).set_pressed_no_signal(bool(policy.get(key)))
	for key in _spins:
		(_spins[key] as SpinBox).set_value_no_signal(float(policy.get(key)))
	if _zoom_spin != null:
		var z: Vector2 = policy.override_zoom
		_zoom_spin.set_value_no_signal(z.x)
	_syncing_ui = false


# ---------------------------------------------------------------- 状态文字

func _process(delta: float) -> void:
	if policy == null or controller == null:
		return
	_root.visible = policy.panel_visible
	_hud.visible = policy.show_hud
	if not policy.show_hud:
		_warn.visible = false
		return
	# 状态文字只需要 10Hz；每帧重建会持续产生临时字符串。
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = HUD_INTERVAL
	var st: Dictionary = controller.status()
	var b: Rect2 = st.get("bounds", Rect2())
	var z: Vector2 = st.get("zoom", Vector2.ONE)
	var out_names := ["保持上一房", "回起点", "解除约束", "最近房间"]
	var tr_names := ["连续滚动", "硬切一屏"]
	var fit_names := ["抬缩放", "保持缩放", "仅居中"]
	# 玩家位置显式带上房间 id：相机因冷却 / 进入缓冲还没换房时，
	# 「房间 r1 ｜ 房内」会被读成「在 r1 房内」，其实人在另一间房。
	var inside := bool(st.get("inside", true))
	var where := "房外" if not inside else "房内 " + String(st.get("player_room", &""))
	_hud.text = ("房间 %s ｜ 玩家 %s ｜ 约束 %s ｜ 覆盖 %s\n"
			+ "盒 %d,%d → %d,%d ｜ %d 间房 %d 块 ｜ zoom %.2f×%.2f\n"
			+ "出房策略 %s ｜ 跨房 %s ｜ 适配 %s\n"
			+ "冷却 %.2fs ｜ 缓冲 %.0f ｜ 速度 %.0f%s") % [
		String(st.get("room", &"")),
		where,
		"开" if bool(st.get("confine", false)) else "关",
		"开" if policy.override_room_rules else "关",
		roundi(b.position.x), roundi(b.position.y), roundi(b.end.x), roundi(b.end.y),
		int(st.get("cover_count", 0)), int(st.get("region_count", 0)),
		z.x, z.y,
		out_names[clampi(int(policy.out_of_room), 0, 3)],
		tr_names[clampi(int(policy.room_transition), 0, 1)],
		fit_names[clampi(int(st.get("fit_mode", 0)), 0, 2)],
		# 冷却显示剩余值（不是面板配置值），调参时能直接看到防抖是否还在生效。
		float(st.get("cooldown", 0.0)), policy.enter_margin, policy.player_speed,
		(" ｜ 横向冻结" if bool(st.get("freeze_x", false)) else "") \
				+ (" ｜ 进入缓冲中" if bool(st.get("entry_blocked", false)) else ""),
	]
	_warn.visible = bool(st.get("out_of_bounds", false))


# ---------------------------------------------------------------- 快捷键

## 面板只保留 Tab：其余开关都在面板里点，避免和玩家的移动键抢输入。
func _input(event: InputEvent) -> void:
	if policy == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_TAB:
		return
	policy.toggle(&"panel_visible")
	get_viewport().set_input_as_handled()
