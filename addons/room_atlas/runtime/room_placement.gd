@tool
class_name RoomAtlasPlacement
extends Resource

## 一条房间记录：只有几何与资源引用，不描述连通性。
##
## cells 是格坐标区间（不是世界坐标）。运行时由 RoomAtlasLayout 乘以
## config.cell_size 换算成 world_rect。size 可以是 (1, 2)、(2, 1) 等，
## 因此房间不必等大 —— 大房间就是跨多格的房间。

@export var id: StringName = &""
@export var scene: PackedScene = null
@export var cells: Rect2i = Rect2i(0, 0, 1, 1)
@export var tint: Color = Color(0.18, 0.22, 0.28)
