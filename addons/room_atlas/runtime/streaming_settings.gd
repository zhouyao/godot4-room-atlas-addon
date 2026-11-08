@tool
class_name RoomAtlasStreamingSettings
extends Resource

## 距离流式调度参数。
## mount / sleep / unload 形成滞回带，避免玩家在阈值附近来回蹭时反复加载卸载。

@export var mount_distance: float = 900.0
@export var sleep_distance: float = 2200.0
@export var unload_distance: float = 4200.0
@export var max_mounted: int = 8
@export var tick: float = 0.12
