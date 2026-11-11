@tool
class_name SeamlessRoomSceneLibrary
extends Resource

## 地图编辑器的 tscn 已导入列表，也就是左栏列表的全部内容。
##
## 纯编辑期数据，运行期不加载。分区（载入 / 未载入）不存本资源里，
## 由 world_config.tres 中是否存在引用该场景的 placement 实时决定。
## 用无类型 Array，让 .tres 可手写、可 diff（与 SeamlessRoomConfig.rooms 一致）。
@export var scenes: Array = []

## 导入 / 上次同步时的 room_size 基线：path(String) → Vector2i。
## 未载入项用它判断场景尺寸是否被改过；已载入项直接和 world_config 的 cells 比较。
@export var sizes: Dictionary = {}

## 已载入列表的虚拟分组（只影响列表展示，不改变文件系统）：
## groups = [{ "name": String }]，group_of = { path(String): 组名(String) }。
## 删除组时只移除分组信息，成员自动回到根层，不会动 tscn 或地图。
@export var groups: Array = []
@export var group_of: Dictionary = {}
