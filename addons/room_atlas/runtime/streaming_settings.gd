@tool
class_name RoomAtlasStreamingSettings
extends Resource

## 距离流式调度参数 + 空间索引粒度。
## mount / sleep / unload 形成滞回带，避免玩家在阈值附近来回蹭时反复加载卸载。
##
## 这里的默认值是中立兜底，不绑定任何示例视口或房间尺寸：
## - 三个距离只作为基准下限，运行期有效值由游戏层 set_load_radius() 注入；
## - bucket_size <= 0 表示由 RoomAtlasLayout 按地图房间尺寸自动推导；
## - max_mounted <= 0 表示由 RoomAtlasStreamer 按有效半径与地图密度自动派生。
## 具体项目请把取值显式写在自己的 .tres 里（示例见 world_config.tres）。

## 自动推导桶尺寸时、地图里没有有效房间的兜底值。
const FALLBACK_BUCKET_SIZE := 512.0

@export var mount_distance: float = 1000.0
@export var sleep_distance: float = 2000.0
@export var unload_distance: float = 4000.0
## 同时挂载上限；<= 0 表示自动按有效半径与地图密度派生。
@export var max_mounted: int = 0
@export var tick: float = 0.12
## 空间索引桶边长（世界像素）；<= 0 表示自动按地图房间尺寸推导。
@export var bucket_size: float = 0.0
