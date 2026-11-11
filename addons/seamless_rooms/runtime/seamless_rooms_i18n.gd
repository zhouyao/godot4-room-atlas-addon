@tool
class_name SeamlessRoomI18n
extends RefCounted

## 插件文案的中英双语表。
##
## 英文是源文案，也是所有非中文 locale 的回退值；中文在 ZH 里逐条对照。
## 语言判定：
## · 编辑器内（@tool / EditorPlugin）跟随「编辑器设置 → 界面 → 编辑器 → 编辑器语言」，
##   由 TranslationServer.get_tool_locale() 提供；
## · 游戏运行时跟随 TranslationServer 的当前 locale。
## 因此切换编辑器语言并重开编辑器后，dock 文案会自动切换；游戏内则由项目 locale 决定。
##
## 新增文案：代码里写英文原文，并在 ZH 里补一条同 key 的中文。

const ZH := {
	# plugin.gd / world_canvas
	"Failed to load config: ": "无法加载配置：",
	"Config validation failed, build blocked:\n": "配置校验失败，已阻止运行：\n",

	# seamless_rooms_validator.gd
	"Config is empty": "配置为空",
	"schema_version=%d, this build is %d; verify whether migration is required":
			"schema_version=%d，当前实现为 %d，请确认是否需要迁移",
	"cell_size must be positive": "cell_size 必须为正数",
	"streaming settings are missing": "缺少 streaming 设置",
	"mount_distance must be greater than 0": "mount_distance 必须大于 0",
	"Requires mount_distance < sleep_distance < unload_distance":
			"需满足 mount_distance < sleep_distance < unload_distance",
	"bucket_size must not be NaN / INF (<= 0 means auto)":
			"bucket_size 不能是 NaN / INF（<= 0 表示自动推导）",
	"mount_distance exceeds the bucket budget for a single neighborhood query; the radius will be clamped at runtime":
			"mount_distance 超出单次邻域查询的桶预算，运行时会截断半径",
	"max_mounted must not be negative (<= 0 means auto)":
			"max_mounted 不能为负数（<= 0 表示自动派生）",
	"tick must be greater than 0": "tick 必须大于 0",
	"max_mounted is small and may conflict with mount_distance, causing repeated sleep/wake cycles":
			"max_mounted 偏小，可能与 mount_distance 冲突导致反复休眠/唤醒",
	"rooms is empty": "rooms 为空",
	"rooms[%d] is not a SeamlessRoomPlacement": "rooms[%d] 不是 SeamlessRoomPlacement",
	"%s is missing id": "%s 缺少 id",
	"Duplicate id: %s": "id 重复：%s",
	"%s (%s) has no scene": "%s (%s) 未指定 scene",
	"%s (%s) cells.size must be positive": "%s (%s) 的 cells.size 必须为正",
	"Room cells overlap: %s and %s": "房间格区间重叠：%s 与 %s",

	# seamless_rooms_scene_list.gd
	"Not loaded (%d)": "未载入 (%d)",
	"Loaded (%d)": "已载入 (%d)",
	"Not on the map · drag onto canvas to place · × removes from list":
			"未拖入地图 · 拖到画布放置 · × 移出列表",
	"In group · drag onto canvas to place · × removes from list":
			"组内 · 拖到画布放置 · × 移出列表",
	"On the map · drag to place again · × removes from map":
			"已在地图中 · 可继续拖放 · × 从地图移除",
	"Virtual group: %s\nDouble-click the name to rename · drag a tscn here to add it\nDrag onto \"Loaded\" to remove · × deletes the group":
			"虚拟组：%s\n双击组名改名 · 拖 tscn 到这里入组\n拖到「已载入」标题移出 · × 删除组",
	"\n⚠ %s\nClick the inline sync button to update from the current tscn size":
			"\n⚠ %s\n点行内同步按钮：按该 tscn 当前尺寸更新",

	# seamless_rooms_world_canvas.gd
	"Import .tscn": "导入 .tscn",
	"Fit View": "适应视图",
	"Save Config": "保存配置",
	"tscn Assets": "tscn 资源管理",
	"Filter by file name…": "筛选文件名…",
	"Not loaded on top · drag onto canvas to place · loaded + creates a group · double-click a group name to rename":
			"未载入在上 · 拖到画布放置 · 已载入 + 新建组 · 双击组名改名",
	"Room Properties": "房间属性",
	"Room Info · Not Loaded": "房间信息 · 未载入",
	"Validation Report": "校验报告",
	"Drag from the list onto the canvas to place rooms · left-drag a room (snaps to grid; green/blue/yellow guides show neighbors) · drag empty space or right-drag to pan · wheel to zoom · red outline = overlap":
			"左侧列表拖到画布放房间 · 左键拖房间（吸附格，绿/蓝/黄辅助线提示相邻） · 空白处/右键拖动平移 · 滚轮缩放 · 红框 = 重叠",
	"(not assigned)": "(未指定)",
	"Modified · unsaved": "已修改 · 未保存",
	"No new assets (already imported?)": "没有新增资源（可能已导入）",
	"Imported %d tscn": "已导入 %d 个 tscn",
	"Removed from list: ": "已移出列表 ",
	"Group %d": "组 %d",
	"Created group: %s (double-click the name to rename)":
			"已新建组：%s（双击组名可重命名）",
	"Group already exists: %s": "组已存在：%s",
	"Renamed group: %s": "已重命名组：%s",
	"Deleted group (members are ungrouped): %s": "已删除组（成员回到未分组）：%s",
	"Grouped: %s → %s": "已分组：%s → %s",
	"Ungrouped": "未分组",
	"Save failed: error code %d": "保存失败：错误码 %d",
	"Failed to save config: %d": "保存配置失败：%d",
	"Failed to save scene library: %d": "保存资源库失败：%d",
	"Saved ": "已保存 ",
	"Failed to create config: ": "配置创建失败：",
	"Grid %d×%d px · %d rooms loaded": "格 %d×%d px · 已加载 %d 个房间",
	"Scene load failed: ": "场景加载失败：",
	"Located map room %s": "已定位地图房间 %s",
	"Not loaded asset: ": "未载入资源：",
	"Scene id %s is already used by another room; id not synced":
			"场景 id %s 已被其它房间占用，未同步 id",
	"Baseline updated from scene: ": "已按场景更新基线：",
	"Synced from %s · %d rooms": "已按 %s 同步 %d 间房",
	"Sync %s (%d rooms)": "同步 %s（%d 间房）",
	"Remove %s from map (%d rooms)": "从地图移除 %s（%d 间房）",
	"Removed %d rooms from map: %s (assets return to not loaded)":
			"已从地图移除 %d 间房：%s（资源回到未载入）",
	"Scene %d×%d, recorded %d×%d": "场景 %d×%d，记录 %d×%d",
	"Scene %d×%d, map %d×%d cells": "场景 %d×%d，地图 %d×%d 格",
	"Scene id %s, map id %s": "场景 id %s，地图 id %s",
	"Scene id %s is also used by %s": "场景 id %s 与 %s 重复",
	"Move room %s": "移动房间 %s",
	"Change room color": "修改房间颜色",
	"Place room %s": "放置房间 %s",
	"Godot Scene": "Godot 场景",
	"Import tscn into asset list": "导入 tscn 到资源列表",
	"Config not loaded": "配置未加载",
	"Config is valid": "配置有效",
	"Duplicate scene id: %s (%s)": "场景 id 重复：%s（%s）",

	# seamless_rooms_grid_canvas.gd
	"X seam": "X 贴合",
	"Y seam": "Y 贴合",
	"X align": "X 对齐",
	"Y align": "Y 对齐",
	"Nearest X: Δ%d px": "最近 X: Δ%d px",
	"Nearest Y: Δ%d px": "最近 Y: Δ%d px",

	# seamless_rooms_parallax.gd
	"Editor preview enabled: pan the 2D view to preview parallax; layers are restored when saving.":
			"编辑器预览已启用：平移 2D 视图查看视差；保存时自动复位各层。",

	# seamless_rooms_layout.gd / seamless_rooms_streamer.gd
	"query_near: radius %.1f exceeds the bucket budget; clamped to %.1f":
			"query_near: radius %.1f 超出桶预算，已截断到 %.1f",
	"Mount limit %d is smaller than the number of rooms in range; all rooms were kept":
			"挂载上限 %d 小于半径内房间数，已保留全部",

	# seamless_rooms_minimap.gd
	"Player coords  —": "玩家坐标  —",
	"Player coords  x %d   y %d": "玩家坐标  x %d   y %d",

	# seamless_rooms_room2d.gd
	"Follow & Confine": "跟随并锁边界",
	"Fixed Center": "固定房间中心",
	"Auto Zoom": "自动抬高缩放",
	"Keep Zoom": "保持缩放",
	"Center Only": "仅居中",
	" (disabled)": "（已关闭）",
	"Camera %s  %d × %d px%s": "相机 %s  %d × %d px%s",
}

static var _cached_locale := ""
static var _cached_zh := false


## 当前是否中文语境（zh / zh_CN / zh_TW…）。
static func is_chinese() -> bool:
	var locale := TranslationServer.get_tool_locale() \
			if Engine.is_editor_hint() else TranslationServer.get_locale()
	if locale != _cached_locale:
		_cached_locale = locale
		_cached_zh = locale.begins_with("zh")
	return _cached_zh


## 取当前语言的文案；非中文或缺 key 时回退英文原文。
static func t(key: String) -> String:
	return String(ZH.get(key, key)) if is_chinese() else key


## 带格式化参数的版本：tf("Move room %s", [id])。
static func tf(key: String, args: Array) -> String:
	return t(key) % args


## 列表拼接分隔符：中文用全角分号，英文用 "; "。
static func list_sep() -> String:
	return "；" if is_chinese() else "; "
