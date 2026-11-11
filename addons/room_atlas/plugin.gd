@tool
extends EditorPlugin

## Godot4 Room Atlas 编辑器入口。
##
## · 底部 dock：tscn 资源列表 / 网格画布（导入 / 拖拽落图 / 删除 / 吸附 / 对齐 / 校验 / 保存）
## · _apply_changes()：编辑器保存项目时自动落盘未保存的配置
## · _build()：运行前自动校验，有 error 阻止运行
##
## 两份数据各司其职：world_config.tres 是运行期唯一地图配置；
## room_library.tres 是编辑期资源池（只记录导入了哪些 .tscn），运行期不加载。
## 不做 JSON 快照，也不注册工具菜单，所有编辑与校验能力都集中在底部 dock。

## 默认放在项目根目录；可在 project.godot 的 [room_atlas] 段覆盖：
##   config_path / library_path
const DEFAULT_CONFIG_PATH := "res://world_config.tres"
const DEFAULT_LIBRARY_PATH := "res://room_library.tres"
const WorldCanvasScript = preload("res://addons/room_atlas/editor/room_atlas_world_canvas.gd")

var _dock: EditorDock = null
var _panel = null
var _fs_refresh_pending := false


func _config_path() -> String:
	return String(ProjectSettings.get_setting("room_atlas/config_path", DEFAULT_CONFIG_PATH))


func _library_path() -> String:
	return String(ProjectSettings.get_setting("room_atlas/library_path", DEFAULT_LIBRARY_PATH))


## 在「项目设置」里为两个路径提供默认值与 *.tres 文件选择器。
##
## 顺序很重要：add_property_info() 与 set_initial_value() 都要求设置项已存在，
## 所以必须先 set_setting() 创建它，否则启动时会报
## "Request for nonexistent project setting" 和 "!props.has(pinfo.name)"。
func _register_project_settings() -> void:
	_register_setting("room_atlas/config_path", DEFAULT_CONFIG_PATH)
	_register_setting("room_atlas/library_path", DEFAULT_LIBRARY_PATH)


func _register_setting(name: String, default_value: String) -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)
	ProjectSettings.add_property_info({
		"name": name,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres",
	})
	ProjectSettings.set_initial_value(name, default_value)


func _enter_tree() -> void:
	_register_project_settings()
	_dock = EditorDock.new()
	_dock.name = "RoomAtlasDock"
	_dock.title = "Room Atlas"
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.closable = true
	_dock.custom_minimum_size = Vector2(0, 360)
	# dock 级裁剪：面板被撑大时也不会溢出到编辑器其它布局。
	_dock.clip_contents = true
	_panel = WorldCanvasScript.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(_panel)
	add_dock(_dock)
	_panel.setup(_config_path(), _library_path(), get_undo_redo(),
			get_editor_interface().get_editor_settings())
	var fs := get_editor_interface().get_resource_filesystem()
	if fs != null:
		fs.filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	var fs := get_editor_interface().get_resource_filesystem()
	if fs != null and fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
	_panel = null


## 保存 .tscn / 导入资源后合并刷新一次，让列表的尺寸标记及时出现。
func _on_filesystem_changed() -> void:
	if _fs_refresh_pending or _panel == null:
		return
	_fs_refresh_pending = true
	# 延迟一拍，等编辑器把场景重载完成，避免读到旧缓存。
	get_tree().create_timer(0.25).timeout.connect(_flush_fs_refresh, CONNECT_ONE_SHOT)


func _flush_fs_refresh() -> void:
	_fs_refresh_pending = false
	if _panel != null and _panel.has_method("refresh_library_from_disk"):
		_panel.call("refresh_library_from_disk")


## 编辑器保存项目 / 切换标签时，把未保存的配置改动落盘。
func _apply_changes() -> void:
	if _panel != null and _panel.has_method("save_if_dirty"):
		_panel.call("save_if_dirty")


func _current_config() -> RoomAtlasConfig:
	if _panel != null and _panel.has_method("current_config"):
		var c: RoomAtlasConfig = _panel.call("current_config") as RoomAtlasConfig
		if c != null:
			return c
	return ResourceLoader.load(_config_path(), "", ResourceLoader.CACHE_MODE_REPLACE) as RoomAtlasConfig


## 运行前最后一道闸：有 error 就中止运行，避免带着错配置跑半天。
func _build() -> bool:
	var cfg_path := _config_path()
	if not ResourceLoader.exists(cfg_path):
		return true
	var config := _current_config()
	if config == null:
		push_error("[Room Atlas] " + RoomAtlasI18n.t("Failed to load config: ") + cfg_path)
		return false
	var result := RoomAtlasValidator.validate(config)
	if not result.errors.is_empty():
		push_error("[Room Atlas] " + RoomAtlasI18n.t("Config validation failed, build blocked:\n")
				+ RoomAtlasValidator.format(result))
		return false
	return true
