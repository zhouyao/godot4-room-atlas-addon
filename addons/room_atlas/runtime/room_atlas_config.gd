@tool
class_name RoomAtlasConfig
extends Resource

## 网格房间世界的配置契约（编辑期产出，运行期只读）。
##
## 只包含几何与流式参数：不描述门、传送、连通性、出生点、关卡进度。
## 房间之间怎么来往、玩家怎么移动，是游戏层的事。

const SCHEMA_VERSION := 1

@export var schema_version: int = SCHEMA_VERSION
## 网格大小，单位：像素。示例用 1×1 px，于是格坐标 == 世界像素坐标。
## 它只决定编辑器吸附与画布网格线；空间索引桶尺寸由
## RoomAtlasStreamingSettings.bucket_size 独立控制，网格再细也不会让索引膨胀。
## 房间 cells 是 Rect2i，直接写像素矩形即可。
@export var cell_size: Vector2 = Vector2(1, 1)
## 用无类型 Array 存储，让 .tres 可手写、可 diff；访问请走 placements()。
@export var rooms: Array = []
@export var streaming: RoomAtlasStreamingSettings = null

## 取出经过类型过滤的房间列表。配置来源（手写 .tres / 编辑器 / JSON）都可能
## 混入无效元素，统一在这里收敛。
func placements() -> Array[RoomAtlasPlacement]:
	var out: Array[RoomAtlasPlacement] = []
	for r in rooms:
		if r is RoomAtlasPlacement:
			out.append(r)
	return out
