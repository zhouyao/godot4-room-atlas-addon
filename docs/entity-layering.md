# 实体分层与房间怪物

> 相关文档：[根 README](../README.md) · [插件 README](../addons/seamless_rooms/README.md) · [视差约定](parallax-convention.md)

本文约定房间里“谁归谁管、谁画在谁前面、谁和谁碰撞”。核心原则：

> **房间负责内容与出生点，运行实例统一挂在 `Main/Actors`。**

`Main` 里只有运行期容器和供给器，不手摆 100 间房的怪；怪物、宝箱、掉落物的定义仍然写在各自的房间场景里。

## 1. 绘制 band

| `z_index` | 层 | 内容 |
|---|---|---|
| -100 | 调试 / 背景 | `WorldGrid` 与 `BgParallax`（同 z 时按树顺序，背景后画覆盖网格） |
| -99 ~ -1 | 世界后景 | 地面、水、墙、影子、贴地装饰 |
| 0 ~ 9 | 静态物件 | 默认 props；永远在角色后 |
| **10** | **`Actors`（y-sort）** | **玩家、怪物、宝箱、掉落物** |
| 11 ~ 99 | 固定前景 | 永远盖住角色的静态物 |
| 100+ | 前景视差 | `FgParallax`；遮片层用 `scroll_scale = (1, 1)` |
| `CanvasLayer.layer` | UI | HUD、小地图、血条 |

`z_index` 只影响绘制，不影响输入和物理；`CanvasLayer` 是独立画布，和 `z_index` 不是一套系统。

## 2. 归属与生命周期

| 对象 | 归属 | 原因 |
|---|---|---|
| 玩家 | `Main/Actors`（常驻） | 不能随房间 `queue_free()` |
| 怪物 | 房间里的 `EnemySpawn` + 运行时实例在 `Main/Actors` | 和玩家同一个 y-sort 容器；按房间挂载生成/回收 |
| 宝箱 | 房间里的 `ChestSpawn` + 运行时实例在 `Main/Actors` | 开合状态按 `room_id/名称` 持久化 |
| 掉落物 | `PickupSpawn` 或怪物死亡生成，实例在 `Main/Actors` | 房间卸载不能把它 free 掉 |
| 植物 | `r1.tscn/World/Props` 或 `FgParallax` | 纯场景装饰，随房间走 |
| 血条 / 伤害数字 | `Main/Overlays` | 不参与世界 y-sort |

streamer 的休眠 / 卸载行为：

- `_sleep()`：房间根 `visible = false`、`process_mode = DISABLED`、碰撞关闭；
- `_unload()`：`queue_free()` 房间实例。

因此玩家、跨房实体、掉落物不能放在房间节点下；房间内的怪如果直接摆放，会被休眠冻结、被卸载释放，而且无法和玩家跨容器 y-sort。

## 3. 场景结构

```text
Main (Node2D)
├─ WorldGrid                 z = -100
├─ SeamlessRoomStreamer
├─ Actors (Node2D)           z = 10, y_sort_enabled = true
│  ├─ Player
│  ├─ Player2
│  ├─ r1_EnemySpawn_01       ← RoomEntityDirector 生成
│  ├─ r1_EnemySpawn_02
│  ├─ r1_ChestSpawn_01
│  ├─ r1_PickupSpawn_01
│  └─ r1_drop_0              ← 怪物死亡掉落
├─ RoomEntityDirector (Node)
├─ Overlays (Node2D)         z = 15
├─ Camera2D
├─ CanvasLayer              layer = 1   # debug_overlay（房内/房外标记）
├─ CameraDebugPanel         CanvasLayer # 调试面板（Tab 显隐）
└─ MinimapLayer             layer = 2   # Minimap
```

```text
R1 (SeamlessRoom2D / room_view.gd)
├─ BgParallax (Control, z = -100, clip_to_room = true)
│  ├─ Sky (Node2D)                   # Darkness 静态背景，不参与视差
│  ├─ Far (0.55)
│  ├─ Far2 (0.75)
│  ├─ Mid (0.87)
│  └─ Near (0.95)
├─ World (Node2D)
│  ├─ Water
│  ├─ Terrain
│  ├─ Obstacles                      # 碰撞
│  ├─ Decals (Node2D, z = -10)       # 影子、水渍、血迹
│  ├─ Props (Node2D)                 # 永远在角色后的静态物
│  └─ Spawns (Node2D)                # 出生点，不是实体
│     ├─ EnemySpawn_01 / 02
│     ├─ ChestSpawn_01
│     └─ PickupSpawn_01
└─ FgParallax (Control, z = 100, clip_to_room = true)
   ├─ Occluders (1.0, z = 20)        # 前景遮片；OccluderTest 为演示占位
   ├─ Foreground (1.06)
   ├─ FG2 (1.18)
   └─ FG3 (1.30)
```

`World` 下的分组节点必须是 `Node2D`。Godot 的 transform / modulate / visibility 只向**直接** `CanvasItem` 子节点传播；中间夹普通 `Node` 会切断链路，`Marker2D.global_position` 和物理体都会算错。

## 4. y-sort 规则

1. 实体必须是 y-sort 容器的**直接子节点**。`Actors/Enemies` 这种中间 `Node2D` 会被当成一个整体排序，下面所有怪挤在容器的 Y 上。
2. 只有最终 `z_index` 相同的节点才互相排序。`Actors` 是 10，实体子节点必须是 0（`z_as_relative` 默认 `true`）。
3. 节点原点放在脚底；贴图用 `Sprite2D.offset` 往上抬。demo 角色是胶囊中心，生产角色建议改脚底。
4. 实体内部的子节点作为一个整体跟着实体排序；血条、名字、伤害数字放 `Overlays`，不要随手加 `z_index`。

## 5. 房间实体供给：RoomEntityDirector

`example/actors/room_entity_director.gd`：

- `main.gd` 在 `controller.setup()` **之前**创建 director，并注入 `streamer` / `actors` / `player` / `pickup_scene`；
- `room_mounted(id)`：读该房间 `World/Spawns`，按标记类型生成实例到 `Actors`；
- `room_sleeping(id)`：回收 `home_room == id` 的实例；
- `_ready()` 扫一遍 `streamer.mounted_ids()`，补开局已经挂载的房间（`controller.setup()` 里已经 `ensure_room(start_room)`）；
- key 统一为 `"room_id/出生点节点名"`，用于存活表、宝箱状态、掉落物已拾取、精英怪死亡；怪物死亡动态掉落用 `"room_id/drop_N"`。

支持三种出生点：

| 节点 | 脚本 | 生成 |
|---|---|---|
| `EnemySpawn` | `example/actors/enemies/enemy_spawn.gd` | 怪物，带领地 / 仇恨 / leash |
| `ChestSpawn` | `example/actors/interactables/chest_spawn.gd` | 宝箱，开合状态持久化 |
| `PickupSpawn` | `example/actors/pickups/pickup_spawn.gd` | 固定掉落物 |

当前 `r1.tscn/World/Spawns` 的实际配置：

| 节点 | 位置 | 参数 |
|---|---|---|
| `EnemySpawn_01` | `(1650, 700)` | territory 260 / aggro 180 / leash 420 |
| `EnemySpawn_02` | `(900, 760)` | territory 320 / aggro 220 / leash 480 |
| `ChestSpawn_01` | `(2450, 900)` | 使用 `chest.tscn` |
| `PickupSpawn_01` | `(2050, 780)` | 使用 `pickup.tscn` |

新增房间内容时，只改该房间场景：在 `World/Spawns` 下放一个标记，拖入对应的 `PackedScene` 即可，不需要改 `main.tscn`。

## 6. 领地 AI

`EnemySpawn.position` 就是 `home_position`。怪物只做三态：

- `IDLE`：玩家进入 `aggro_radius` 且仍在领地内 → `CHASE`；
- `CHASE`：玩家离开领地，或自己超出 `leash_radius`，或玩家超出 `deaggro_radius` → `RETURN`；
- `RETURN`：以 `return_speed` 走回出生点，到达后 `IDLE`。

数值约束：

- `aggro_radius <= territory_radius`；
- `territory_radius < sleep_distance`（示例是 2200），这样“怪在追玩家” ⇒ 玩家一定在房间附近 ⇒ 房间不会休眠，`room_sleeping` 回收不会误杀正在追人的怪。

## 7. 宝箱与掉落

- 宝箱是 `Area2D`，物理层 4；`collision_mask = 2` 只检测玩家。靠近按 `E` 打开。
- 开合状态由 director 存在 `_flags["r1/ChestSpawn_01"]`；休眠 / 卸载后重新挂载会恢复。
- 掉落物是 `Area2D`，物理层 5；玩家脚下的 `PickupArea` 用 `mask = 16` 扫描并调用 `collect()`。
- 怪物死亡时 director 在死亡位置生成一个掉落物；demo 用 `K` 键对最近的怪造成伤害。

正式项目把 `_flags` 换成存档单例即可，key 格式保持不变。

## 8. 物理层

| Layer | 名称 | bitmask | 用途 |
|---|---|---|---|
| 1 | World | 1 | 地形、平台、墙 |
| 2 | Player | 2 | 玩家本体 |
| 3 | Enemy | 4 | 怪物本体 |
| 4 | Interactable | 8 | 宝箱、门、可采集物 |
| 5 | Pickup | 16 | 掉落物 `Area2D` |

`collision_layer` 是 bitmask，不是层号：层 3 = 4，层 4 = 8，层 5 = 16。

## 9. 100 间房

- 编辑期：每间房一个场景，自己摆 `World/Spawns`；加房间不碰 `main.tscn`。
- 运行期：streamer 只挂载玩家附近 `max_mounted` 间房，director 只遍历 `mounted_ids()`。
- 100 间 × 每房 4~5 个出生点 = 编辑期 400~500 个轻量 `Marker2D`；运行期同时最多 8 间房的实体。
- 嫌多再加一层“玩家离房间 < 900 才生成”的激活半径，或调小 `max_mounted`。

## 10. demo 操作

| 输入 | 作用 |
|---|---|
| `WASD` / 方向键 | 移动白色玩家 |
| `J` / `L`、`Space` / `I` | 移动 / 跳跃橙色角色 |
| `K` | 对最近的怪造成 15 点伤害（两下击杀，生成掉落物） |
| `E` | 靠近宝箱时打开 |
| `Tab` | 显隐相机调试面板 |

## 11. 常见坑

- 房间里的 `CanvasLayer` 不会被房间 `visible = false` 隐藏（它不是 `CanvasItem`）；HUD 一律放 `Main`，不要放房间。
- `room_sleeping` 发出时房间已经不在 `mounted` 里，`mounted_room()` 返回 `null`；回收只依赖实例上的 `home_room` metadata。
- 如果改回“房间里直接摆怪 + reparent”，要额外处理：休眠信号在 `_set_collision()` 之后才发，回收前要手动关碰撞；怪死亡直接 `queue_free()` 会导致休眠唤醒后不回来。
- `Actors` 下不要放 `Enemies` / `Pickups` 中间容器；用 group / metadata / director 内部字典归类。
- 世界分组节点不要用普通 `Node`，否则 CanvasItem 变换链断开。

## 12. 自检

```bash
# 资源导入（生成新脚本的 .uid）
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

# 脚本语法检查
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --check-only --script res://example/actors/room_entity_director.gd
```

运行时确认：

1. r1 的史莱姆生成在 `Main/Actors` 下，和玩家按 Y 排序；
2. 玩家靠近 → 追；离开领地 → 回出生点；
3. 走远让 r1 休眠，再回来 → 史莱姆重新生成；
4. 宝箱打开后走远再回来 → 保持打开；
5. 怪物死亡掉落 → 玩家走过去自动拾取；
6. 连续进出房间 `Actors` 子节点数量不持续增长。
