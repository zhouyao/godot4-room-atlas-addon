@tool
extends Tree

## 左侧 tscn 资源列表：未载入在上、已载入在下。
## 「已载入」标题右侧 + 新建组；双击组名内联改名（回车/失焦保存，Esc 取消）；
## 把 tscn 拖到组节点即入组，拖到「已载入」标题即移出组；
## 组右侧 × 删组，成员自动回到根层。

signal path_deleted(path: String)
signal path_selected(path: String)
signal path_synced(path: String)
signal group_create_requested()
signal group_deleted(group_name: String)
signal group_renamed(old_name: String, new_name: String)
signal path_group_changed(path: String, group_name: String)

const DRAG_TYPE := "room_atlas_scene"
const GROUP_PREFIX := "group:"
const SECTION_LOADED := "section:loaded"
const SECTION_UNLOADED := "section:unloaded"
const BTN_DELETE := 0
const BTN_SYNC := 1
const BTN_ADD_GROUP := 2

var _delete_icon: Texture2D = null
var _sync_icon: Texture2D = null
var _add_icon: Texture2D = null
var _rename_edit: LineEdit = null
var _rename_item: TreeItem = null
var _rename_old := ""
var _filter := ""
var _last_unloaded := PackedStringArray()
var _last_loaded := PackedStringArray()
var _last_changed: Dictionary = {}
var _last_groups: Array = []
var _last_group_of: Dictionary = {}


func _ready() -> void:
	hide_root = true
	select_mode = Tree.SELECT_ROW
	button_clicked.connect(_on_button_clicked)
	item_selected.connect(_on_item_selected)
	item_activated.connect(_on_item_activated)


func _on_item_selected() -> void:
	var item := get_selected()
	if item == null:
		return
	var meta := String(item.get_metadata(0))
	if meta.is_empty() or meta.begins_with("section:") or meta.begins_with(GROUP_PREFIX):
		return
	path_selected.emit(meta)


## 双击组节点 → 进入内联改名。
func _on_item_activated() -> void:
	var item := get_selected()
	if item == null:
		return
	var meta := String(item.get_metadata(0))
	if meta.begins_with(GROUP_PREFIX):
		_begin_rename(item)


func rebuild(unloaded: PackedStringArray, loaded: PackedStringArray,
		changed: Dictionary = {}, groups: Array = [], group_of: Dictionary = {}) -> void:
	_last_unloaded = unloaded
	_last_loaded = loaded
	_last_changed = changed
	_last_groups = groups
	_last_group_of = group_of
	_render()


## 按文件名筛选；输入为空显示全部。组名命中时整组保留。
func set_filter(text: String) -> void:
	var f := text.strip_edges().to_lower()
	if f == _filter:
		return
	_filter = f
	_render()


func _render() -> void:
	_end_rename()
	clear()
	var root := create_item()
	var icon := _get_delete_icon()
	var changed := _last_changed

	var unloaded := PackedStringArray()
	for p in _last_unloaded:
		if _matches(p):
			unloaded.append(p)
	var loaded := PackedStringArray()
	for p in _last_loaded:
		if _matches(p):
			loaded.append(p)

	var top := create_item(root)
	top.set_text(0, "未载入 (%d)" % unloaded.size())
	top.set_selectable(0, false)
	top.set_custom_color(0, Color(1.0, 0.78, 0.42))
	top.collapsed = false
	top.set_metadata(0, SECTION_UNLOADED)
	for p in unloaded:
		_add_scene_item(top, p, "未拖入地图 · 拖到画布放置 · × 移出列表", icon,
				String(changed.get(p, "")))

	var bottom := create_item(root)
	bottom.set_selectable(0, false)
	bottom.set_custom_color(0, Color(0.45, 0.9, 0.6))
	bottom.collapsed = false
	bottom.set_metadata(0, SECTION_LOADED)
	var add_icon := _get_add_icon()
	if add_icon != null:
		bottom.add_button(0, add_icon, BTN_ADD_GROUP)

	# 先按 groups 顺序建组并挂成员，剩余条目平铺在「已载入」下。
	var grouped := {}
	for g in _last_groups:
		var gname := String(g.get("name", ""))
		if gname.is_empty():
			continue
		var group_hit := _filter.is_empty() or gname.to_lower().contains(_filter)
		var members := PackedStringArray()
		for p in _last_loaded:
			if String(_last_group_of.get(p, "")) != gname:
				continue
			if group_hit or _matches(p):
				members.append(p)
		# 组名没命中、成员也全被过滤掉时，隐藏空组。
		if not _filter.is_empty() and not group_hit and members.is_empty():
			continue
		var gi := create_item(bottom)
		gi.set_text(0, "%s (%d)" % [gname, members.size()])
		gi.set_metadata(0, GROUP_PREFIX + gname)
		gi.set_custom_color(0, Color(0.75, 0.86, 1.0))
		gi.set_tooltip_text(0, "虚拟组：" + gname
				+ "\n双击组名改名 · 拖 tscn 到这里入组\n拖到「已载入」标题移出 · × 删除组")
		gi.collapsed = false
		if icon != null:
			gi.add_button(0, icon, BTN_DELETE)
		if group_hit:
			for p in members:
				if not loaded.has(p):
					loaded.append(p)
		for p in members:
			grouped[p] = true
			_add_scene_item(gi, p, "组内 · 拖到画布放置 · × 移出列表", icon,
					String(changed.get(p, "")))
	for p in loaded:
		if grouped.has(p):
			continue
		_add_scene_item(bottom, p, "已在地图中 · 可继续拖放 · × 从地图移除", icon,
				String(changed.get(p, "")))
	# 组名命中时成员已补进 loaded，统一在这里写分区计数。
	bottom.set_text(0, "已载入 (%d)" % loaded.size())


func _matches(path: String) -> bool:
	if _filter.is_empty():
		return true
	return path.get_file().to_lower().contains(_filter)


func _add_scene_item(parent: TreeItem, path: String, tip: String, icon: Texture2D,
		warn: String) -> void:
	var it := create_item(parent)
	it.set_metadata(0, path)
	if warn.is_empty():
		it.set_text(0, path.get_file())
		it.set_tooltip_text(0, path + " · " + tip)
	else:
		# 场景 room_size 与地图占位/基线不一致：橙色 + ⚠ 标记。
		it.set_text(0, path.get_file() + "  ⚠")
		it.set_custom_color(0, Color(1.0, 0.72, 0.35))
		it.set_tooltip_text(0, path + " · " + tip + "\n⚠ " + warn
				+ "\n点行内同步按钮：按该 tscn 当前尺寸更新")
		var sync := _get_sync_icon()
		if sync != null:
			it.add_button(0, sync, BTN_SYNC)
	if icon != null:
		it.add_button(0, icon, BTN_DELETE)


# ---------------------------------------------------------------- 图标

func _get_delete_icon() -> Texture2D:
	if _delete_icon != null:
		return _delete_icon
	var icon: Texture2D = null
	if has_theme_icon("Remove", "EditorIcons"):
		icon = get_theme_icon("Remove", "EditorIcons")
	elif has_theme_icon("Close", "EditorIcons"):
		icon = get_theme_icon("Close", "EditorIcons")
	else:
		icon = _make_cross_icon()
	_delete_icon = icon
	return icon


func _make_cross_icon() -> Texture2D:
	var img := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(2, 10):
		var c := Color(0.95, 0.45, 0.45)
		img.set_pixel(i, i, c)
		img.set_pixel(11 - i, i, c)
	return ImageTexture.create_from_image(img)


func _get_sync_icon() -> Texture2D:
	if _sync_icon != null:
		return _sync_icon
	var icon: Texture2D = null
	for n in ["Reload", "Loop", "Refresh"]:
		if has_theme_icon(n, "EditorIcons"):
			icon = get_theme_icon(n, "EditorIcons")
			break
	if icon == null:
		icon = _make_sync_icon()
	_sync_icon = icon
	return icon


func _make_sync_icon() -> Texture2D:
	var n := 14
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.55, 0.85, 1.0, 1.0)
	var center := Vector2(7.0, 7.0)
	for y in range(n):
		for x in range(n):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
			if d >= 4.2 and d <= 6.0:
				img.set_pixel(x, y, c)
	# 右上留缺口，视觉上更像“刷新”而不是实心圆。
	for y in range(0, 5):
		for x in range(9, n):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _get_add_icon() -> Texture2D:
	if _add_icon != null:
		return _add_icon
	var icon: Texture2D = null
	for n in ["Add", "FolderAdd", "New"]:
		if has_theme_icon(n, "EditorIcons"):
			icon = get_theme_icon(n, "EditorIcons")
			break
	if icon == null:
		icon = _make_add_icon()
	_add_icon = icon
	return icon


func _make_add_icon() -> Texture2D:
	var n := 14
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.55, 0.9, 1.0, 1.0)
	for i in range(4, 10):
		img.set_pixel(i, 6, c)
		img.set_pixel(i, 7, c)
		img.set_pixel(6, i, c)
		img.set_pixel(7, i, c)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 内联改名

func _begin_rename(item: TreeItem) -> void:
	if _rename_edit != null:
		return
	var rect := get_item_area_rect(item, 0)
	if rect.size.x < 1.0:
		return
	_rename_item = item
	_rename_old = String(item.get_metadata(0)).substr(GROUP_PREFIX.length())
	_rename_edit = LineEdit.new()
	_rename_edit.text = _rename_old
	_rename_edit.select_all_on_focus = true
	_rename_edit.position = rect.position
	_rename_edit.size = Vector2(maxf(80.0, rect.size.x - 30.0), maxf(20.0, rect.size.y))
	_rename_edit.text_submitted.connect(_on_rename_submitted)
	_rename_edit.focus_exited.connect(_on_rename_focus_exit)
	_rename_edit.gui_input.connect(_on_rename_gui_input)
	add_child(_rename_edit)
	_rename_edit.grab_focus()


func _on_rename_submitted(text: String) -> void:
	_commit_rename(text)


func _on_rename_focus_exit() -> void:
	if _rename_edit != null:
		_commit_rename(_rename_edit.text)


func _on_rename_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_end_rename()
		get_viewport().set_input_as_handled()


func _commit_rename(text: String) -> void:
	var old := _rename_old
	var new_name := text.strip_edges()
	_end_rename()
	if old.is_empty() or new_name.is_empty() or new_name == old:
		return
	group_renamed.emit(old, new_name)


func _end_rename() -> void:
	if _rename_edit != null:
		_rename_edit.queue_free()
		_rename_edit = null
	_rename_item = null
	_rename_old = ""


# ---------------------------------------------------------------- 按钮 / 拖拽

func _on_button_clicked(item: TreeItem, _column: int, id: int, mouse_button_index: int) -> void:
	if item == null or mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var meta := String(item.get_metadata(0))
	if meta == SECTION_LOADED and id == BTN_ADD_GROUP:
		group_create_requested.emit()
		return
	if meta.begins_with(GROUP_PREFIX):
		# 组节点只有「删除组」按钮。
		group_deleted.emit(meta.substr(GROUP_PREFIX.length()))
		return
	if meta.is_empty() or meta.begins_with("section:"):
		return
	# id 1 = 行内同步（按 tscn 当前尺寸），0 = 删除。
	if id == BTN_SYNC:
		path_synced.emit(meta)
	else:
		path_deleted.emit(meta)


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
	var meta := String(item.get_metadata(0))
	if meta.is_empty() or meta.begins_with("section:") or meta.begins_with(GROUP_PREFIX):
		return null
	var preview := Label.new()
	preview.text = meta.get_file()
	set_drag_preview(preview)
	return { "type": DRAG_TYPE, "path": meta }


# ---------------------------------------------------------------- 拖入组

## 落点对应的目标组：组名 / ""（已载入标题 = 移出组）/ null（不接受）。
func _drop_group_at(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
	var meta := String(item.get_metadata(0))
	if meta.begins_with(GROUP_PREFIX):
		return meta.substr(GROUP_PREFIX.length())
	if meta == SECTION_LOADED:
		return ""
	return null


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if String((data as Dictionary).get("type", "")) != DRAG_TYPE:
		return false
	return _drop_group_at(at_position) != null


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var target = _drop_group_at(at_position)
	if target == null:
		return
	var path := String((data as Dictionary).get("path", ""))
	if not path.is_empty():
		path_group_changed.emit(path, String(target))
