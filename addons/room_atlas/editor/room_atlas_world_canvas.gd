@tool
extends VBoxContainer

## 编辑器面板：工具栏 + tscn 资源列表 + 网格画布 + 属性 + 校验报告。
##
## room_library.tres 是已导入列表（编辑期数据），world_config.tres 是地图配置。
## 列表分区按「是否被拖入地图」划分：有 placement 引用的为已载入，其余未载入。
## 地图改动都通过 EditorUndoRedoManager 提交，保存由按钮显式触发。

const GridCanvasScript = preload("res://addons/room_atlas/editor/room_atlas_grid_canvas.gd")
const SceneLibraryScript = preload("res://addons/room_atlas/editor/room_atlas_scene_library.gd")
const SceneListScript = preload("res://addons/room_atlas/editor/room_atlas_scene_list.gd")
const DEFAULT_ROOM_SIZE := Vector2i(2400, 1080)

var config: RoomAtlasConfig = null
var config_path := ""
var library_path := ""
var library: Resource = null
var undo_redo: EditorUndoRedoManager = null
var selected: StringName = &""
var dirty := false

var _built := false
var _updating := false
var _canvas = null
var _scene_list = null
var _import_dialog: FileDialog = null
var _status_label: Label = null
var _report: RichTextLabel = null
var _inspector: VBoxContainer = null
var _right_title: Label = null
var _id_label: Label = null
var _title_label: Label = null
var _scene_label: Label = null
var _spin: Array[SpinBox] = []
var _w_label: Label = null
var _h_label: Label = null
var _tint_picker: ColorPickerButton = null
var _editable_row_controls: Array[Control] = []
var _inspected_scene_path := ""
var _last_library_state := PackedStringArray()
## 场景声明缓存：path → { room_id, room_title, room_size }；文件系统变化时整体清空。
var _scene_props_cache: Dictionary = {}
## 编辑器设置，用来记住 dock 内两条分隔条的位置。
var _settings: EditorSettings = null
var _split_outer: HSplitContainer = null
var _split_inner: HSplitContainer = null
var _split_restored := false
var _split_save_pending := false

const SETTING_SPLIT_OUTER := "room_atlas/dock_split_outer"
const SETTING_SPLIT_INNER := "room_atlas/dock_split_inner"


func setup(p_config_path: String, p_library_path: String, p_ur: EditorUndoRedoManager,
		p_settings: EditorSettings = null) -> void:
	config_path = p_config_path
	library_path = p_library_path
	undo_redo = p_ur
	_settings = p_settings
	# 方向键接管需要 _input 回调。
	set_process_input(true)
	if not _built:
		_build_ui()
	# 延迟一帧：_enter_tree 阶段资源系统可能尚未就绪。
	call_deferred("_reload")


func current_config() -> RoomAtlasConfig:
	return config


func save_if_dirty() -> void:
	if dirty:
		_on_save()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_built = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 320)
	# 面板级裁剪：整棵 UI 子树都不允许画到 dock 之外。
	clip_contents = true

	var bar := HBoxContainer.new()
	add_child(bar)
	_add_button(bar, RoomAtlasI18n.t("Import .tscn"), _on_import)
	_add_button(bar, RoomAtlasI18n.t("Fit View"), _on_fit)
	_add_button(bar, RoomAtlasI18n.t("Save Config"), _on_save)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status_label)

	# 两层 HSplitContainer：外层分隔条调左栏宽度，内层调右栏宽度。
	var outer := HSplitContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	add_child(outer)
	_split_outer = outer

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(120, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.22
	left.clip_contents = true
	outer.add_child(left)

	var ltitle := Label.new()
	ltitle.text = RoomAtlasI18n.t("tscn Assets")
	left.add_child(ltitle)

	# 按文件名筛选；输入即过滤，清空恢复全部。
	var lfilter := LineEdit.new()
	lfilter.placeholder_text = RoomAtlasI18n.t("Filter by file name…")
	lfilter.clear_button_enabled = true
	lfilter.custom_minimum_size = Vector2(0, 0)
	lfilter.text_changed.connect(func(text: String) -> void:
		_scene_list.call("set_filter", text))
	left.add_child(lfilter)

	_scene_list = SceneListScript.new()
	_scene_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_list.custom_minimum_size = Vector2(80, 0)
	left.add_child(_scene_list)
	_scene_list.connect("path_deleted", _on_library_delete)
	_scene_list.connect("path_selected", _on_scene_selected)
	_scene_list.connect("path_synced", _on_sync_path)
	_scene_list.connect("group_create_requested", _on_group_create_requested)
	_scene_list.connect("group_deleted", _on_group_delete_name)
	_scene_list.connect("group_renamed", _on_group_renamed)
	_scene_list.connect("path_group_changed", _on_path_group_changed)

	var lhint := Label.new()
	lhint.text = RoomAtlasI18n.t(
			"Not loaded on top · drag onto canvas to place · loaded + creates a group · double-click a group name to rename")
	lhint.modulate.a = 0.6
	# 不设置 clip 时 Label 会按文本宽度撑大左栏最小宽度，导致分隔条只能放大。
	lhint.clip_text = true
	lhint.custom_minimum_size = Vector2(0, 0)
	lhint.tooltip_text = lhint.text
	left.add_child(lhint)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_stretch_ratio = 0.78
	split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	outer.add_child(split)
	_split_inner = split
	# 拖动后记住位置；首次布局完成时恢复上次保存的偏移。
	outer.dragged.connect(func(_offset: int) -> void: _schedule_split_save())
	split.dragged.connect(func(_offset: int) -> void: _schedule_split_save())
	outer.resized.connect(_restore_split_once)
	split.resized.connect(_restore_split_once)

	_canvas = GridCanvasScript.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(220, 0)
	_canvas.size_flags_stretch_ratio = 0.6
	split.add_child(_canvas)
	_canvas.connect("selection_changed", _on_selection_changed)
	_canvas.connect("cells_committed", _on_cells_committed)
	_canvas.connect("scene_dropped", _on_scene_dropped)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(170, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.4
	right.clip_contents = true
	split.add_child(right)

	_right_title = Label.new()
	_right_title.text = RoomAtlasI18n.t("Room Properties")
	right.add_child(_right_title)
	_inspector = VBoxContainer.new()
	right.add_child(_inspector)

	var grid := GridContainer.new()
	grid.columns = 2
	_inspector.add_child(grid)
	# 不可改的字段在上，可改的字段在下；未载入模式把可改行整组隐藏。
	_id_label = _read_only_label()
	_add_row(grid, "id", _id_label)
	_title_label = _read_only_label()
	_add_row(grid, "title", _title_label)
	_scene_label = _read_only_label()
	_add_row(grid, "scene", _scene_label)
	_w_label = _read_only_label()
	_add_row(grid, "w", _w_label)
	_h_label = _read_only_label()
	_add_row(grid, "h", _h_label)
	for n in ["x", "y"]:
		var s := SpinBox.new()
		s.min_value = -100000.0
		s.max_value = 100000.0
		# ↑/↓ 每次 1 格（示例 1 px）；聚焦时全选，方便直接键入数值。
		s.step = 1.0
		s.rounded = true
		s.select_all_on_focus = true
		_spin.append(s)
		_add_editable_row(grid, n, s)
	_tint_picker = ColorPickerButton.new()
	_add_editable_row(grid, "tint", _tint_picker)

	for s in _spin:
		s.value_changed.connect(_on_cells_value_changed)
	_tint_picker.color_changed.connect(_on_tint_changed)

	var rtitle := Label.new()
	rtitle.text = RoomAtlasI18n.t("Validation Report")
	right.add_child(rtitle)
	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.custom_minimum_size = Vector2(0, 90)
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_report)

	var hint := Label.new()
	hint.text = RoomAtlasI18n.t(
			"Drag from the list onto the canvas to place rooms · left-drag a room (snaps to grid; green/blue/yellow guides show neighbors) · drag empty space or right-drag to pan · wheel to zoom · red outline = overlap")
	hint.modulate.a = 0.6
	hint.clip_text = true
	add_child(hint)


# ---------------------------------------------------------------- 分隔条状态

## 首次布局完成（size > 0）时恢复上次保存的 split_offset，只执行一次。
func _restore_split_once() -> void:
	if _split_restored or _settings == null:
		return
	if _split_outer == null or _split_outer.size.x <= 1.0:
		return
	_split_restored = true
	var outer_off: Variant = _settings.get_setting(SETTING_SPLIT_OUTER)
	if outer_off != null:
		_split_outer.split_offset = int(outer_off)
	if _split_inner != null and _split_inner.size.x > 1.0:
		var inner_off: Variant = _settings.get_setting(SETTING_SPLIT_INNER)
		if inner_off != null:
			_split_inner.split_offset = int(inner_off)


## 拖动中合并保存请求，避免每个拖动帧都写编辑器设置。
func _schedule_split_save() -> void:
	if _settings == null or _split_save_pending:
		return
	_split_save_pending = true
	get_tree().create_timer(0.25).timeout.connect(_flush_split_save, CONNECT_ONE_SHOT)


func _flush_split_save() -> void:
	_split_save_pending = false
	if _settings == null or not is_inside_tree():
		return
	if _split_outer != null:
		_settings.set_setting(SETTING_SPLIT_OUTER, _split_outer.split_offset)
	if _split_inner != null:
		_settings.set_setting(SETTING_SPLIT_INNER, _split_inner.split_offset)


func _add_button(parent: HBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _add_row(grid: GridContainer, text: String, control: Control) -> Label:
	var l := Label.new()
	l.text = text
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return l


func _add_editable_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := _add_row(grid, text, control)
	_editable_row_controls.append(l)
	_editable_row_controls.append(control)


func _read_only_label() -> Label:
	var l := Label.new()
	l.clip_text = true
	# 只读字段用 tooltip 展示完整值（窄面板里文字会被裁剪）。
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


# ---------------------------------------------------------------- 数据

func _reload() -> void:
	if config_path.is_empty():
		return
	# 新项目第一次打开时在默认位置生成一份空配置，避免面板不可用。
	if not ResourceLoader.exists(config_path):
		var dir := config_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		var fresh := RoomAtlasConfig.new()
		fresh.streaming = RoomAtlasStreamingSettings.new()
		if ResourceSaver.save(fresh, config_path) != OK:
			_status(RoomAtlasI18n.t("Failed to create config: ") + config_path)
			return
	config = ResourceLoader.load(config_path, "", ResourceLoader.CACHE_MODE_REPLACE) as RoomAtlasConfig
	if config == null:
		_status(RoomAtlasI18n.t("Failed to load config: ") + config_path)
		return
	selected = &""
	_inspected_scene_path = ""
	_canvas.set_config(config)
	_load_library()
	_refresh_library()
	_refresh_inspector()
	_validate()
	dirty = false
	_status(RoomAtlasI18n.tf("Grid %d×%d px · %d rooms loaded", [
		int(config.cell_size.x), int(config.cell_size.y), config.placements().size()
	]))


func _selected_placement() -> RoomAtlasPlacement:
	if config == null or selected == &"":
		return null
	for p in config.placements():
		if p.id == selected:
			return p
	return null


## 两种模式：选中地图房间时显示 placement（只读字段在上，可改字段在下）；
## 点未载入资源时只显示场景自己声明的 id / scene / w / h，可改行整组隐藏。
func _refresh_inspector() -> void:
	if _inspector == null:
		return
	var p := _selected_placement()
	var info := {}
	if p == null and not _inspected_scene_path.is_empty():
		info = _scene_info(_inspected_scene_path)
	_inspector.visible = p != null or not info.is_empty()
	if not _inspector.visible:
		return
	_updating = true
	var scene_mode := p == null
	_right_title.text = RoomAtlasI18n.t("Room Info · Not Loaded") if scene_mode \
			else RoomAtlasI18n.t("Room Properties")
	for c in _editable_row_controls:
		c.visible = not scene_mode
	if scene_mode:
		_id_label.text = String(info.get("id", &""))
		_title_label.text = String(info.get("title", ""))
		_scene_label.text = _inspected_scene_path
		var size: Vector2i = info.get("size", DEFAULT_ROOM_SIZE)
		_w_label.text = str(size.x)
		_h_label.text = str(size.y)
	else:
		_id_label.text = String(p.id)
		_title_label.text = "" if p.scene == null \
				else String(_scene_root_props(p.scene).get("room_title", ""))
		_scene_label.text = p.scene.resource_path if p.scene != null \
				else RoomAtlasI18n.t("(not assigned)")
		_w_label.text = str(p.cells.size.x)
		_h_label.text = str(p.cells.size.y)
		_spin[0].set_value_no_signal(p.cells.position.x)
		_spin[1].set_value_no_signal(p.cells.position.y)
		_tint_picker.color = p.tint
	_id_label.tooltip_text = _id_label.text
	_title_label.tooltip_text = _title_label.text
	_scene_label.tooltip_text = _scene_label.text
	_w_label.tooltip_text = _w_label.text
	_h_label.tooltip_text = _h_label.text
	_updating = false


func _set_property(obj: Object, prop: StringName, value: Variant, label: String) -> void:
	var old := obj.get(prop)
	if old == value:
		return
	if undo_redo == null:
		obj.set(prop, value)
		_after_change()
		return
	undo_redo.create_action(label)
	undo_redo.add_do_property(obj, prop, value)
	undo_redo.add_undo_property(obj, prop, old)
	undo_redo.add_do_method(self, "_after_change")
	undo_redo.add_undo_method(self, "_after_change")
	undo_redo.commit_action()


func _after_change() -> void:
	if config != null:
		config.emit_changed()
	dirty = true
	if _canvas != null:
		_canvas.refresh()
	_refresh_inspector()
	_validate()
	# 房间增删会改变「是否拖入地图」，需同步列表分区（内部有差量保护）。
	_refresh_library()
	_status(RoomAtlasI18n.t("Modified · unsaved"))


func _insert_placement(p: RoomAtlasPlacement, idx: int) -> void:
	if config == null or config.rooms.has(p):
		return
	config.rooms.insert(mini(idx, config.rooms.size()), p)


func _erase_placement(p: RoomAtlasPlacement) -> void:
	if config == null:
		return
	config.rooms.erase(p)


## id 优先取场景自己声明的 room_id；已被占用才回退自动编号，避免重复 id 死锁。
func _next_id(preferred: StringName = &"") -> String:
	var used := {}
	for p in config.placements():
		used[p.id] = true
	if preferred != &"" and not used.has(preferred):
		return String(preferred)
	var n := 1
	while true:
		var id := StringName("r%d" % n)
		if not used.has(id):
			return String(id)
		n += 1
	return "r_new"


# ---------------------------------------------------------------- tscn 资源库

## 资源库 = 已导入列表。分区另外由 world_config.tres 里是否有 placement
## 引用来决定，因此增删房间会让条目在两个分区之间迁移。
func _load_library() -> void:
	if library_path.is_empty():
		return
	if ResourceLoader.exists(library_path):
		library = ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Resource
	if library == null or not (library.get("scenes") is Array):
		library = SceneLibraryScript.new()
		ResourceSaver.save(library, library_path)
	_last_library_state.clear()
	_ensure_size_baselines()


func _library_scenes() -> Array:
	if library == null:
		return []
	var scenes: Variant = library.get("scenes")
	return scenes if scenes is Array else []


## 列表的全部内容 = 已导入清单；项目里其它 .tscn 由「导入」对话框选取。
func _library_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _library_scenes():
		if s is PackedScene:
			var path := (s as PackedScene).resource_path
			if not path.is_empty():
				out.append(path)
	return out


func _save_library() -> void:
	if library == null or library_path.is_empty():
		return
	var err := ResourceSaver.save(library, library_path)
	if err != OK:
		push_error("[Room Atlas] " + RoomAtlasI18n.tf("Failed to save scene library: %d", [err]))


func _import_paths(paths: PackedStringArray) -> void:
	if library == null:
		_load_library()
	if library == null:
		return
	var scenes: Array = _library_scenes()
	var known := {}
	for p in _library_paths():
		known[p] = true
	var added := 0
	for p in paths:
		if p.is_empty() or not p.ends_with(".tscn") or known.has(p):
			continue
		if not ResourceLoader.exists(p):
			continue
		var packed := ResourceLoader.load(p, "PackedScene") as PackedScene
		if packed == null:
			continue
		scenes.append(packed)
		_set_size_baseline(p, _scene_root_props(packed)["room_size"])
		known[p] = true
		added += 1
	if added == 0:
		_status(RoomAtlasI18n.t("No new assets (already imported?)"))
		return
	library.set("scenes", scenes)
	_save_library()
	_refresh_library()
	_validate()
	_status(RoomAtlasI18n.tf("Imported %d tscn", [added]))


## 未载入项删除：从导入清单移除，列表里消失。
func _remove_from_library(path: String) -> void:
	if library == null or path.is_empty():
		return
	var scenes: Array = _library_scenes()
	var removed := 0
	for i in range(scenes.size() - 1, -1, -1):
		var s: Variant = scenes[i]
		if s is PackedScene and (s as PackedScene).resource_path == path:
			scenes.remove_at(i)
			removed += 1
	if removed == 0:
		return
	library.set("scenes", scenes)
	var go := _library_group_of()
	if go.erase(path):
		library.set("group_of", go)
	_save_library()
	_refresh_library()
	_validate()
	_status(RoomAtlasI18n.t("Removed from list: ") + path.get_file())


# ---------------------------------------------------------------- 虚拟组

func _library_groups() -> Array:
	if library == null:
		return []
	var v: Variant = library.get("groups")
	return v if v is Array else []


func _library_group_of() -> Dictionary:
	if library == null:
		return {}
	var v: Variant = library.get("group_of")
	return v if v is Dictionary else {}


func _group_exists(name: String) -> bool:
	for g in _library_groups():
		if String(g.get("name", "")) == name:
			return true
	return false


## 「已载入」标题右侧的 +：建一个默认名组，之后双击组名可改。
func _on_group_create_requested() -> void:
	if library == null:
		return
	var n := 1
	var name := RoomAtlasI18n.tf("Group %d", [n])
	while _group_exists(name):
		n += 1
		name = RoomAtlasI18n.tf("Group %d", [n])
	var groups := _library_groups()
	groups.append({ "name": name })
	library.set("groups", groups)
	_save_library()
	_refresh_library()
	_status(RoomAtlasI18n.tf(
			"Created group: %s (double-click the name to rename)", [name]))


## 组名内联编辑提交。
func _on_group_renamed(old_name: String, new_name: String) -> void:
	if library == null or old_name.is_empty() or new_name.is_empty() or old_name == new_name:
		return
	if _group_exists(new_name):
		_status(RoomAtlasI18n.tf("Group already exists: %s", [new_name]))
		return
	var groups := _library_groups()
	for g in groups:
		if String(g.get("name", "")) == old_name:
			g["name"] = new_name
			break
	library.set("groups", groups)
	# 成员归属一起改名，否则会变成「组已删、成员回根」。
	var go := _library_group_of()
	for k in go.keys():
		if String(go[k]) == old_name:
			go[k] = new_name
	library.set("group_of", go)
	_save_library()
	_refresh_library()
	_status(RoomAtlasI18n.tf("Renamed group: %s", [new_name]))


func _on_group_delete_name(name: String) -> void:
	_delete_group(name)


## 删组只清分组信息，成员自动回到「已载入」根层。
func _delete_group(name: String) -> void:
	if library == null or name.is_empty():
		return
	var groups := _library_groups()
	for i in range(groups.size() - 1, -1, -1):
		if String(groups[i].get("name", "")) == name:
			groups.remove_at(i)
	library.set("groups", groups)
	var go := _library_group_of()
	for k in go.keys():
		if String(go[k]) == name:
			go.erase(k)
	library.set("group_of", go)
	_save_library()
	_refresh_library()
	_status(RoomAtlasI18n.tf("Deleted group (members are ungrouped): %s", [name]))


func _on_path_group_changed(path: String, group_name: String) -> void:
	if library == null or path.is_empty():
		return
	var go := _library_group_of()
	if group_name.is_empty():
		go.erase(path)
	else:
		go[path] = group_name
	library.set("group_of", go)
	_save_library()
	_refresh_library()
	_status(RoomAtlasI18n.tf("Grouped: %s → %s", [path.get_file(),
			group_name if not group_name.is_empty() else RoomAtlasI18n.t("Ungrouped")]))


## 分区：清单里被地图 placement 引用的为「已载入」，其余「未载入」。
func _refresh_library() -> void:
	if _scene_list == null:
		return
	var used := {}
	if config != null:
		for p in config.placements():
			if p.scene != null and not p.scene.resource_path.is_empty():
				used[p.scene.resource_path] = true
	var unloaded := PackedStringArray()
	var loaded := PackedStringArray()
	for p in _library_paths():
		if used.has(p):
			loaded.append(p)
		else:
			unloaded.append(p)
	var changed := _changed_assets()
	var groups := _library_groups()
	var group_of := _library_group_of()
	var state := PackedStringArray()
	for p in unloaded:
		state.append(p + ("*" if changed.has(p) else ""))
	state.append("|")
	for p in loaded:
		state.append(p + ("*" if changed.has(p) else ""))
	state.append("|g:")
	for g in groups:
		state.append(String(g.get("name", "")))
	state.append("|go:")
	var keys := group_of.keys()
	keys.sort()
	for k in keys:
		state.append(String(k) + "=" + String(group_of[k]))
	# 差量保护：改 cells / tint 等不影响分区 / 标记 / 分组的操作不必重建 Tree。
	if state == _last_library_state and _scene_list.get_root() != null:
		return
	_last_library_state = state
	_scene_list.rebuild(unloaded, loaded, changed, groups, group_of)


## 读取场景根节点声明的 room_id / room_size，不实例化场景。
func _scene_root_props(packed: PackedScene) -> Dictionary:
	var out := { "room_id": &"", "room_title": "", "room_size": DEFAULT_ROOM_SIZE }
	var st := packed.get_state()
	if st == null or st.get_node_count() == 0:
		return out
	for i in range(st.get_node_property_count(0)):
		var key := String(st.get_node_property_name(0, i))
		var v: Variant = st.get_node_property_value(0, i)
		if key == "room_id":
			out["room_id"] = StringName(String(v))
		elif key == "room_title":
			out["room_title"] = String(v)
		elif key == "room_size" and v is Vector2i:
			out["room_size"] = v
	return out


func _scene_cells_size(packed: PackedScene) -> Vector2i:
	var vi: Vector2i = _scene_root_props(packed)["room_size"]
	return _px_to_cells(vi)


## 像素尺寸 → 格尺寸（与落图时的换算保持一致）。
func _px_to_cells(px: Vector2i) -> Vector2i:
	var cs := config.cell_size
	return Vector2i(
		maxi(1, roundi(float(px.x) / maxf(cs.x, 0.001))),
		maxi(1, roundi(float(px.y) / maxf(cs.y, 0.001)))
	)


## 未载入资源的信息：直接来自 .tscn 根节点，与地图配置无关。
func _scene_info(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		return {}
	var props := _scene_root_props(packed)
	return {
		"id": props["room_id"],
		"title": props["room_title"],
		"size": props["room_size"],
	}


# ---------------------------------------------------------------- 尺寸差异

## 场景当前声明的属性（带缓存，文件系统变化时由插件清空）。
func _scene_props_of(path: String) -> Dictionary:
	if _scene_props_cache.has(path):
		return _scene_props_cache[path]
	var out := { "room_id": &"", "room_title": "", "room_size": DEFAULT_ROOM_SIZE }
	if not path.is_empty() and ResourceLoader.exists(path):
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if packed != null:
			out = _scene_root_props(packed)
	_scene_props_cache[path] = out
	return out


func _scene_size_of(path: String) -> Vector2i:
	return _scene_props_of(path)["room_size"]


func _library_sizes() -> Dictionary:
	if library == null:
		return {}
	var v: Variant = library.get("sizes")
	return v if v is Dictionary else {}


## 更新基线；真的发生变化才返回 true，调用方按需保存库。
func _set_size_baseline(path: String, size: Vector2i) -> bool:
	if library == null or path.is_empty():
		return false
	var sizes := _library_sizes()
	if sizes.get(path) == size:
		return false
	sizes[path] = size
	library.set("sizes", sizes)
	return true


## 旧库没有 sizes 字段时，以当前场景尺寸补齐一次。
func _ensure_size_baselines() -> void:
	if library == null:
		return
	var sizes := _library_sizes()
	var changed := false
	for path in _library_paths():
		if not sizes.has(path):
			sizes[path] = _scene_size_of(path)
			changed = true
	if changed:
		library.set("sizes", sizes)
		_save_library()


func _placements_for_path(path: String) -> Array:
	var out: Array = []
	if config == null:
		return out
	for p in config.placements():
		if p.scene != null and p.scene.resource_path == path:
			out.append(p)
	return out


## 库内多个 .tscn 声明了同一个 room_id 时返回 id → 路径数组；空 id 不参与。
func _duplicate_scene_ids() -> Dictionary:
	var by_id := {}
	for path in _library_paths():
		var id: StringName = _scene_props_of(path)["room_id"]
		if id == &"":
			continue
		if not by_id.has(id):
			by_id[id] = []
		by_id[id].append(path)
	var out := {}
	for id in by_id:
		var paths: Array = by_id[id]
		if paths.size() > 1:
			out[id] = paths
	return out


## 返回 path → 差异描述（列表 ⚠ 标记与行内同步都用它）。
## 已载入：场景的 room_size / room_id vs placement；未载入：场景尺寸 vs 库基线。
func _changed_assets() -> Dictionary:
	var out := {}
	if library == null:
		return out
	var sizes := _library_sizes()
	for path in _library_paths():
		var props := _scene_props_of(path)
		var cur: Vector2i = props["room_size"]
		var placements := _placements_for_path(path)
		if placements.is_empty():
			if not sizes.has(path):
				continue
			var base: Vector2i = sizes[path]
			if base != cur:
				out[path] = RoomAtlasI18n.tf("Scene %d×%d, recorded %d×%d",
						[cur.x, cur.y, base.x, base.y])
		else:
			var expect := _px_to_cells(cur)
			var notes: Array[String] = []
			for p in placements:
				if p.cells.size != expect:
					notes.append(RoomAtlasI18n.tf("Scene %d×%d, map %d×%d cells", [
						cur.x, cur.y, p.cells.size.x, p.cells.size.y
					]))
					break
			# 场景被多间房引用时 id 各不相同，只对唯一 placement 检查 id。
			if placements.size() == 1:
				var scene_id: StringName = props["room_id"]
				var only: RoomAtlasPlacement = placements[0]
				if scene_id != &"" and only.id != scene_id:
					notes.append(RoomAtlasI18n.tf("Scene id %s, map id %s",
							[scene_id, only.id]))
			if not notes.is_empty():
				out[path] = RoomAtlasI18n.list_sep().join(PackedStringArray(notes))
	# 跨场景 id 重复：涉及的文件都标出来（行内同步解决不了，需要改 .tscn）。
	var dup := _duplicate_scene_ids()
	for id in dup:
		var paths: Array = dup[id]
		for i in paths.size():
			var others: Array[String] = []
			for j in paths.size():
				if j != i:
					others.append(String(paths[j]).get_file())
			var note := RoomAtlasI18n.tf("Scene id %s is also used by %s", [
				id, ", ".join(PackedStringArray(others))
			])
			var target: String = paths[i]
			out[target] = (out[target] + RoomAtlasI18n.list_sep() + note) \
					if out.has(target) else note
	return out


## 文件系统变化后由插件调用：清缓存 → 重载库 → 重算标记。
func refresh_library_from_disk() -> void:
	_scene_props_cache.clear()
	_load_library()
	_refresh_library()
	_validate()


## 行内同步：只处理一个场景，把 room_size / room_id 写回地图占位（可撤销）。
## id 只在该场景只有一个 placement、且新 id 未被其它房间占用时才更新。
func _on_sync_path(path: String) -> void:
	if config == null or path.is_empty():
		return
	if not _changed_assets().has(path):
		return
	var props := _scene_props_of(path)
	var expect := _px_to_cells(props["room_size"])
	var scene_id: StringName = props["room_id"]
	var placements := _placements_for_path(path)
	var single := placements.size() == 1
	var id_conflict := false
	if single and scene_id != &"" and placements[0].id != scene_id:
		for q in config.placements():
			if q != placements[0] and q.id == scene_id:
				id_conflict = true
				break
	var old_rooms: Array = config.rooms.duplicate()
	var new_rooms: Array = []
	var synced := 0
	var new_selected := selected
	for r in old_rooms:
		if r is RoomAtlasPlacement:
			var p: RoomAtlasPlacement = r
			if p.scene != null and p.scene.resource_path == path:
				var copy: RoomAtlasPlacement = p.duplicate()
				var touched := false
				if p.cells.size != expect:
					copy.cells = Rect2i(p.cells.position, expect)
					touched = true
				if single and scene_id != &"" and p.id != scene_id and not id_conflict:
					copy.id = scene_id
					new_selected = scene_id
					touched = true
				if touched:
					new_rooms.append(copy)
					synced += 1
					continue
		new_rooms.append(r)
	# 同步后把基线也更新，之后回到未载入不会误报。
	if _set_size_baseline(path, props["room_size"]):
		_save_library()
	if synced == 0:
		_refresh_library()
		if id_conflict:
			_status(RoomAtlasI18n.tf(
					"Scene id %s is already used by another room; id not synced", [scene_id]))
		else:
			_status(RoomAtlasI18n.t("Baseline updated from scene: ") + path.get_file())
		return
	if undo_redo == null:
		config.rooms = new_rooms
		_after_change()
	else:
		undo_redo.create_action(RoomAtlasI18n.tf(
				"Sync %s (%d rooms)", [path.get_file(), synced]))
		undo_redo.add_do_property(config, "rooms", new_rooms)
		undo_redo.add_undo_property(config, "rooms", old_rooms)
		undo_redo.add_do_method(self, "_after_change")
		undo_redo.add_undo_method(self, "_after_change")
		undo_redo.commit_action()
	if new_selected != selected:
		selected = new_selected
		_canvas.select(new_selected)
	_status(RoomAtlasI18n.tf("Synced from %s · %d rooms", [path.get_file(), synced]))


func _on_import() -> void:
	if _import_dialog == null:
		var dlg := EditorFileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		dlg.access = FileDialog.ACCESS_RESOURCES
		dlg.add_filter("*.tscn", RoomAtlasI18n.t("Godot Scene"))
		dlg.mode_overrides_title = false
		dlg.title = RoomAtlasI18n.t("Import tscn into asset list")
		dlg.files_selected.connect(_on_import_files)
		add_child(dlg)
		_import_dialog = dlg
	_import_dialog.current_dir = "res://"
	_import_dialog.popup_file_dialog()


func _on_import_files(paths: PackedStringArray) -> void:
	_import_paths(paths)


## 列表每行右侧的删除：已载入 → 从地图移除房间（回到未载入）；
## 未载入 → 移出导入清单（从列表消失）。
func _on_library_delete(path: String) -> void:
	if _has_placement(path):
		_delete_placements_for_path(path)
	else:
		_remove_from_library(path)


func _first_placement_for_path(path: String) -> RoomAtlasPlacement:
	if config == null or path.is_empty():
		return null
	for p in config.placements():
		if p.scene != null and p.scene.resource_path == path:
			return p
	return null


func _has_placement(path: String) -> bool:
	return _first_placement_for_path(path) != null


## 点击列表：已载入 → 视图移到该房间并高亮，右侧显示房间属性；
## 未载入 → 清空画布选中，右侧改显场景自身声明的 id / scene / w / h。
func _on_scene_selected(path: String) -> void:
	var p := _first_placement_for_path(path)
	if p != null:
		_canvas.call("focus_room", p.id)
		_canvas.select(p.id)
		_status(RoomAtlasI18n.tf("Located map room %s", [String(p.id)]))
	else:
		_canvas.select(&"")
		_inspected_scene_path = path
		_refresh_inspector()
		_status(RoomAtlasI18n.t("Not loaded asset: ") + path.get_file())


## 移除地图上所有引用该场景的房间；资源留在清单里，自动回落到「未载入」。
func _delete_placements_for_path(path: String) -> void:
	if config == null:
		return
	var old_rooms: Array = config.rooms.duplicate()
	var new_rooms: Array = []
	var removed := 0
	for r in old_rooms:
		if r is RoomAtlasPlacement and (r as RoomAtlasPlacement).scene != null \
				and (r as RoomAtlasPlacement).scene.resource_path == path:
			removed += 1
		else:
			new_rooms.append(r)
	if removed == 0:
		return
	if undo_redo == null:
		config.rooms = new_rooms
		_after_change()
	else:
		undo_redo.create_action(RoomAtlasI18n.tf(
				"Remove %s from map (%d rooms)", [path.get_file(), removed]))
		undo_redo.add_do_property(config, "rooms", new_rooms)
		undo_redo.add_undo_property(config, "rooms", old_rooms)
		undo_redo.add_do_method(self, "_after_change")
		undo_redo.add_undo_method(self, "_after_change")
		undo_redo.commit_action()
	_canvas.select(&"")
	_status(RoomAtlasI18n.tf(
			"Removed %d rooms from map: %s (assets return to not loaded)",
			[removed, path.get_file()]))


# ---------------------------------------------------------------- 交互回调

func _on_selection_changed(id: StringName) -> void:
	selected = id
	# 画布选中变化即退出「未载入资源信息」模式。
	_inspected_scene_path = ""
	_refresh_inspector()


func _on_cells_committed(p: RoomAtlasPlacement, old_cells: Rect2i, new_cells: Rect2i) -> void:
	if old_cells == new_cells:
		return
	# 拖动期间为了预览已直接改过属性，这里先还原，再交给 undo 的 do 应用新值。
	p.cells = old_cells
	_set_property(p, "cells", new_cells, RoomAtlasI18n.tf("Move room %s", [p.id]))


func _on_cells_value_changed(_v: float) -> void:
	if _updating:
		return
	var p := _selected_placement()
	if p == null:
		return
	# 宽高由场景决定，改位置时原样保留 p.cells.size。
	var new_cells := Rect2i(
		int(_spin[0].value), int(_spin[1].value), p.cells.size.x, p.cells.size.y
	)
	_set_property(p, "cells", new_cells, RoomAtlasI18n.tf("Move room %s", [p.id]))


## SpinBox 自身不处理上下键，这里在 _input 阶段接管：
## 只在 x / y 的输入框拥有焦点时生效，长按（echo）可连续调整。
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode != KEY_UP and key.keycode != KEY_DOWN:
		return
	var spin := _focused_axis_spin()
	if spin == null:
		return
	var d := spin.step if key.keycode == KEY_UP else -spin.step
	spin.value = clampf(spin.value + d, spin.min_value, spin.max_value)
	get_viewport().set_input_as_handled()


func _focused_axis_spin() -> SpinBox:
	for s in _spin:
		var le := s.get_line_edit()
		if le != null and le.has_focus():
			return s
	return null


func _on_tint_changed(c: Color) -> void:
	if _updating:
		return
	var p := _selected_placement()
	if p == null:
		return
	_set_property(p, "tint", c, RoomAtlasI18n.t("Change room color"))


## 拖拽落图：鼠标所在格点即房间左上角，尺寸取场景声明的 room_size。
## 写 world_config.tres 后，该资源会从「未载入」迁移到「已载入」。
func _on_scene_dropped(path: String, grid_pos: Vector2i) -> void:
	if config == null:
		return
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		_status(RoomAtlasI18n.t("Scene load failed: ") + path)
		return
	var props := _scene_root_props(packed)
	var preferred: StringName = props["room_id"]
	var p := RoomAtlasPlacement.new()
	p.id = StringName(_next_id(preferred))
	p.scene = packed
	p.cells = Rect2i(grid_pos, _px_to_cells(props["room_size"]))
	p.tint = Color(0.20, 0.24, 0.30)
	# 拖入时把基线更新为当前场景尺寸，之后回到未载入不会误报。
	if _set_size_baseline(path, props["room_size"]):
		_save_library()
	var idx := config.rooms.size()
	if undo_redo == null:
		config.rooms.append(p)
		_after_change()
	else:
		undo_redo.create_action(RoomAtlasI18n.tf("Place room %s", [p.id]))
		undo_redo.add_do_method(self, "_insert_placement", p, idx)
		undo_redo.add_undo_method(self, "_erase_placement", p)
		undo_redo.add_do_method(self, "_after_change")
		undo_redo.add_undo_method(self, "_after_change")
		undo_redo.commit_action()
	_canvas.select(p.id)


func _on_fit() -> void:
	_canvas.fit_view()


func _validate() -> void:
	if _report == null:
		return
	_report.clear()
	if config == null:
		_report.append_text("[color=#ff6b6b]"
				+ RoomAtlasI18n.t("Config not loaded") + "[/color]")
		return
	var result := RoomAtlasValidator.validate(config)
	var lines: Array[String] = []
	for e in result.errors:
		lines.append("[color=#ff6b6b]ERROR[/color] " + e)
	for w in result.warnings:
		lines.append("[color=#ffd166]WARN [/color] " + w)
	# 库内跨场景 id 重复：配置本身合法，但落图时后放的那份会被自动改名。
	var dup := _duplicate_scene_ids()
	for id in dup:
		var names: Array[String] = []
		for p in dup[id]:
			names.append(String(p).get_file())
		lines.append("[color=#ffd166]WARN [/color] " + RoomAtlasI18n.tf(
				"Duplicate scene id: %s (%s)", [id, ", ".join(PackedStringArray(names))]))
	if lines.is_empty():
		lines.append("[color=#6bff9b]OK[/color] " + RoomAtlasI18n.t("Config is valid"))
	_report.append_text("\n".join(PackedStringArray(lines)))


func _on_save() -> void:
	if config == null or config_path.is_empty():
		return
	var err := ResourceSaver.save(config, config_path)
	if err != OK:
		_status(RoomAtlasI18n.tf("Save failed: error code %d", [err]))
		push_error("[Room Atlas] " + RoomAtlasI18n.tf("Failed to save config: %d", [err]))
	else:
		dirty = false
		_status(RoomAtlasI18n.t("Saved ") + config_path)


func _status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
