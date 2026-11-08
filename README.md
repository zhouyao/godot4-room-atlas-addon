# Godot4 Room Atlas

> 网格化房间编排与距离流式加载：编辑期把房间摆在一张网格大地图上，导出一份配置；运行期按这份配置，以玩家附近为中心流式供给房间内容。

**引擎**：Godot 4.7 · **渲染器**：Forward Plus / GL Compatibility 均可（纯 2D，不依赖渲染特性）
**后续迭代目录**：本仓库根目录

---

## 这个插件不做什么

边界比功能更重要，先写清楚：

| 插件**不认识** | 原因 |
|---|---|
| 门、传送门、接缝、连通性 | 房间之间怎么来往是游戏层的事 |
| 玩家、相机、出生点 | 插件只接受一个 `track()` 注入的跟踪目标，从不移动任何节点 |
| 钥匙、锁、剧情、进度 | 属于关卡内容，随房间加载/卸载 |
| 房间之间的可达性 | 不做可达性校验；房间之间留空、靠跳跃或飞行过去都是合法设计 |
| 程序化无限生成 | 插件不生成地形，只负责"已注册的房间"按距离加载 |

一句话：**插件是一台按位置供给房间内容的机器，外加一组纯几何 / 生命周期的原子 API；玩法由游戏层自己拼。**

由此，同一份插件既能做开放连续大地图，也能做"房间孤岛 + 游戏层自己实现传送门"的项目。

---

## 当前状态

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | 配置契约、空间索引、距离流式调度、原子 API、最小可运行示例 | ✅ 已完成 |
| **P1** | 可视化网格地图编辑器：拖拽、吸附、x/y 轴相邻辅助线、重叠高亮、撤销、校验报告 | ✅ 已完成 |
| **P2** | tscn 资源库（导入 + 拖拽落图）已完成；Inspector 场景选择器、画布内搜索与批量操作待做 | ◐ 部分完成 |
| **P3** | 资源缓存 LRU、按格懒生成索引、每房独立配置资源 | ⬜ 待做 |
| **P4** | floating origin（大坐标精度） | ⬜ 待做 |

P1 完成后，配置可以在编辑器底部 dock 里可视化编辑，也可以继续手写 `.tres` —— 两者是同一份数据。P2 的资源库是**另一份纯编辑期数据**，只记录哪些 `.tscn` 被导入，运行期不加载。

---

## 快速开始

1. 用 Godot 4.7 打开本目录（`project.godot`），或命令行：

   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --path /Users/yao.zhou/GitHub/godot4-room-atlas
   ```

2. 按 **F5** 运行示例（主场景 `res://example/main.tscn`）。
3. 操作：`A` / `D` 或 `←` / `→` 移动，`Space` / `W` 跳跃。掉出世界会自动回到起点。
4. 画面上的**绿框 = 已挂载房间，灰框 = 未挂载**；往右走可以看到相邻房间提前变绿、远处房间变灰。

插件已在 `project.godot` 的 `[editor_plugins]` 中启用，所有编辑与校验能力都集中在底部 dock（不注册工具菜单）。右侧校验报告在每次地图改动后自动刷新；按 F5 前还会再校验一次，配置有 error 会阻止运行。运行期地图配置只有一份：`example/world_config.tres`；编辑期已导入列表是 `example/room_library.tres`。

---

## 可视化地图编辑器

插件启用后，编辑器**底部 dock** 会出现 **Room Atlas · 地图**，分三栏：左侧 tscn 资源管理、中间网格画布、右侧属性与校验报告。中间画布编辑 `example/world_config.tres`；左栏的导入 / 移出列表写 `example/room_library.tres`，而删除「已载入」条目会同时从 `world_config.tres` 移除对应房间。两层 `HSplitContainer` 的分隔条可直接拖动，用来调宽左栏（tscn 资源管理）和右栏（房间属性）；三栏最小宽度分别降到 120 / 220 / 170 px，窄窗口下也有余量可拖。左栏底部提示文字做了裁剪（`clip_text`），不会再把最小宽度撑大，因此分隔条可以往里拖窄。两条分隔条的位置保存在 **`EditorSettings`**（`room_atlas/dock_split_outer` / `room_atlas/dock_split_inner`，用户级、不进项目），拖动后约 0.25 秒写入，重新打开编辑器会自动恢复。

> 如果插件是在编辑器打开期间才升级到 P1，需要**重新打开项目**，或在「项目设置 → 插件」里禁用再启用：`EditorPlugin._enter_tree()` 只在插件加载时执行一次，已运行的编辑器不会自动新建 dock。

| 操作 | 说明 |
|---|---|
| 左键拖动房间 | 按 `cell_size` 吸附（示例 1 px，即整数像素），并在约 10 屏幕 px 内自动吸附相邻房间边界（贴边 / 共线，x、y 各自独立）；拖动时实时预览并显示 x/y 轴辅助线，松手才提交（可撤销）。贴边吸附不会重叠，共线吸附可能重叠，仍以红框与校验报告为准 |
| 空白处 / 右键拖动 | 平移视图 |
| 滚轮 / 双指捏合 | 以鼠标位置为中心缩放；macOS 触控板双指外扩放大、双指收缩缩小（Godot `InputEventMagnifyGesture`），也支持手势事件的兜底接收 |
| 单击房间 | 选中并高亮；右侧字段分两段——**不可改的在上**（`id` / `title` / `scene` / `w` / `h`，由场景声明），**可改的在下**（`x` / `y` / `tint`）。`x` / `y` 输入框支持 `↑` / `↓` 每次 1 格（示例 1 px），也可直接键入数值；画布同时标注格数与像素尺寸 |
| 单击列表「已载入」 | 视图平移到对应房间并高亮，右侧显示它完整的房间属性 |
| 单击列表「未载入」 | 右侧切换为「房间信息 · 未载入」，只显示场景自己声明的 `id` / `title` / `scene` / `w` / `h`；`x` / `y` / `tint` 三行整组隐藏，没有额外提示文案 |
| `导入 .tscn` | 打开项目内 `*.tscn` 多选对话框，把资源加入列表；新条目默认在「未载入」，只写 `room_library.tres`，不改地图 |
| 列表 ⚠ 标记 | 保存 `.tscn` 后，若 `room_size` 与地图占位（已载入）或资源库基线（未载入）不一致，条目显示橙色 ⚠ 并在行内多出一个同步按钮，tooltip 写出两边尺寸；改回原尺寸或点同步后自动消失 |
| 左栏「未载入」 | 已导入但**没有拖入地图**的资源，固定排在**上半区**；拖到画布即放一间房 |
| 左栏「已载入」 | 已导入且**地图上至少有一间房引用它**的资源，排在下半区；仍可继续拖放复用 |
| 虚拟组 | 点「已载入」标题右侧的 **+** 新建组；**双击组名**进入内联编辑，回车或点走保存、Esc 取消；把「已载入」条目**拖到组节点**即入组，拖到「已载入」标题移出组；组右侧 × 删组，成员自动回到根层（不动 tscn / 地图） |
| 每行右侧 × | 统一删除入口：未载入 → 移出列表；已载入 → 从地图移除引用它的房间，资源保留并回到「未载入」（可撤销） |
| 拖拽辅助线（绿 / 蓝 / 黄） | 拖动房间时贯穿画布的 x/y 轴虚线：**绿** = 与相邻房间边贴合（吸附后出现），**蓝** = 与邻居边共线，**黄** = 更远范围内的最近候选边（只提示，不参与吸附）；松手即消失 |
| `适应视图` | 缩放平移到能看见全部房间 |
| 行内同步按钮 | 只处理该行场景：已载入项把 `cells.size` 更新为场景当前 `room_size`（保持左上角，可撤销）；未载入项把资源库基线改为当前值 |
| `保存配置` | 写回 `world_config.tres`（运行期唯一地图配置）；编辑器保存项目时也会自动落盘未保存改动 |

**红色边框 = 该房间与其它房间的格区间重叠**，必须修掉才能通过校验；绿色边框 = 当前选中。拖拽落图时鼠标位置就是房间 `cells.position`（左上角），不做中心偏移、不自动避让，重叠交给红框与校验报告处理。所有地图改动（含拖拽落图 / 列表删除已载入项 / 改位置 / 改色）都走 `EditorUndoRedoManager`，支持 Ctrl+Z 撤销；导入与「移出列表」只改 `room_library.tres`，不进撤销栈。工具条不再有「对齐邻居」和「删除」：相邻关系改由拖拽辅助线提示，删除统一在列表每行右侧。

画布刻意只表达几何：没有"连接房间""设置门""指定目标"之类的操作——连通性不属于布局层。拖拽辅助线与边界吸附都只影响预览落点，不写入配置。所有绘制都裁剪到画布矩形（引擎级 `clip_contents` + 绘制前剔除越界图元），放大到房间超出视口时不会溢出到编辑器其它 dock。

---

## 目录结构

```text
godot4-room-atlas/
├── project.godot
├── addons/room_atlas/
│   ├── plugin.cfg                          # 插件清单
│   ├── plugin.gd                           # EditorPlugin：注册 dock + 自动保存 + 运行前校验
│   ├── editor/
│   │   ├── room_atlas_world_canvas.gd      # 编辑器面板：三栏 / 导入 / 落图 / 属性 / 撤销
│   │   ├── room_atlas_grid_canvas.gd       # 网格画布：绘制 / 拖拽吸附 / 相邻辅助线 / 平移缩放 / drop
│   │   ├── room_atlas_scene_library.gd     # 编辑期资源库：场景清单 + room_size 基线
│   │   ├── room_atlas_scene_list.gd        # 左栏 Tree：分区 / 拖拽数据 / 每行删除按钮
│   │   └── room_atlas_validator.gd         # 静态校验（纯逻辑，运行时也可调用）
│   └── runtime/                            # 游戏包里只需要这些
│       ├── room_atlas_config.gd            # class_name RoomAtlasConfig
│       ├── room_placement.gd               # class_name RoomAtlasPlacement
│       ├── streaming_settings.gd           # class_name RoomAtlasStreamingSettings
│       ├── room_atlas_layout.gd            # class_name RoomAtlasLayout
│       ├── room_atlas_room2d.gd            # class_name RoomAtlasRoom2D：房间基类 + 2D 编辑器边界预览
│       └── room_atlas_streamer.gd          # class_name RoomAtlasStreamer
└── example/                                # 最小可运行示例，不属于插件本体
	├── world_config.tres                   # 8 房配置（运行期唯一地图配置；1px 网格）
	├── room_library.tres                   # 已导入列表 + 尺寸基线 + 虚拟组（入库）
	├── rooms/r1.tscn … r8.tscn             # 8 个独立房间场景，各自声明 room_id / room_title / room_size 与不同内容
	├── main.tscn / main.gd                 # 装配序列
	├── room_view.gd                        # 示例底板：继承 RoomAtlasRoom2D，画底 / 地面 / 标题
	├── room_platform.gd / room_decor.gd    # 平台与装饰节点脚本，供各房间 .tscn 组合
	├── player.gd                           # 跟踪目标
	└── debug_overlay.gd                    # 挂载状态可视化
```

`class_name` 是 Godot 全局注册的，所以 `RoomAtlas*` 前缀不能省，避免和其它插件撞名。

---

## 核心概念

### 1. 格坐标，不是世界坐标

配置里房间的位置是 `Rect2i cells`（格坐标区间），运行时才乘 `cell_size`：

\[
\text{world\_rect} = \text{Rect2}\big(\text{cells.position} \odot \text{cell\_size},\; \text{cells.size} \odot \text{cell\_size}\big)
\]

**`cell_size` 的单位就是像素，示例取 `Vector2(1, 1)`**，即一格 1×1 px，格坐标 == 世界像素坐标。于是 `r1` 直接写 `Rect2i(0, 0, 2400, 1080)`，塔井 `r5` 写 `Rect2i(9600, -1080, 2400, 2160)`，房间边界精确到 1 px、任意宽高都可以。

房间内容在 `.tscn` 里本来就用局部像素坐标摆放（平台放 `(803, 512)` 完全合法），`cell_size` 只决定编辑器吸附步长与画布网格线；两者用的是同一把像素尺。

好处：整数可校验、可 diff、无浮点误差；相邻房间的边界由整数相加得出，**严丝合缝是网格的副产品，不需要任何"对齐数据"**。`cells` 是任意 `Rect2i`，所以房间不必等大。

### 2. 空间索引与网格解耦

`cell_size` 只管坐标换算、编辑器吸附和画布网格线；**空间索引用的是另一套固定尺寸的桶**——`RoomAtlasLayout.BUCKET_SIZE = 600 px`。房间按它覆盖的桶登记，一间 2400×1080 px 的房只占 4×2 = 8 个桶。

这个解耦是 1px 网格能成立的前提：若按格逐格登记，一间房就是 259 万个桶、8 间房约两千万个，启动即爆内存；`query_near(半径 900)` 每次还要枚举三百多万个桶。解耦后索引开销只与房间数量和房间尺寸有关，与 `cell_size` 无关。

`query_near()` 只枚举玩家周围固定的几个桶，循环次数是常数，**与世界里总共有多少房间、玩家走了多远无关**——这是从"有限 demo"迈向无限世界的关键一步。

### 3. 四级生命周期

| 状态 | 触发 |
|---|---|
| 未加载 | 初始 |
| 线程加载中 | `request_room()` 发起 `ResourceLoader.load_threaded_request()` |
| 已挂载 | 加载完成 → `instantiate()` → `add_child()`，摆到世界原点 |
| 休眠 | 距离 > `sleep_distance`：隐藏、`PROCESS_MODE_DISABLED`、关碰撞 |
| 释放节点 | 休眠且距离 > `unload_distance`：`queue_free()` |

`PackedScene` 留在缓存里，所以释放的只是实例，回头不用重新读盘。`mount < sleep < unload` 形成滞回带，避免边界抖动。

---

## 配置格式

配置只有一份：自定义 `Resource`（`.tres`），Inspector 原生可编辑、类型安全、引擎管 UID，运行时由 `ResourceLoader` 直接加载。插件不生成 JSON 快照——双份数据容易不同步，且当前没有外部工具消费它。

| 字段 | 类型 | 说明 |
|---|---|---|
| `schema_version` | `int` | 当前为 `1`，用于格式迁移 |
| `cell_size` | `Vector2` | **网格大小**，单位 px；示例 `Vector2(1, 1)`，此时 `cells` 数值就是像素。只影响编辑器吸附与画布网格线，不影响空间索引 |
| `rooms` | `Array` | `RoomAtlasPlacement` 列表；访问请走 `config.placements()` |
| `streaming` | `RoomAtlasStreamingSettings` | 调度参数 |

`RoomAtlasPlacement`：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `StringName` | 房间唯一标识 |
| `scene` | `PackedScene` | 房间场景；多个房间可共用同一份 |
| `cells` | `Rect2i` | 格坐标矩形（x, y, w, h）；世界像素矩形 = `cells × cell_size`。`cell_size=1` 时数值就是像素 |
| `tint` | `Color` | 供房间内容 / 地图 / 调试层使用 |

> 编辑期约定：`id` 与 `cells.size` 在拖入地图时由场景根节点的 `room_id` / `room_size` 决定，之后只读；可改的只有 `cells.position` 与 `tint`。

`RoomAtlasStreamingSettings`：

| 字段 | 示例值 | 说明 |
|---|---|---|
| `mount_distance` | `900` | 小于它开始加载 |
| `sleep_distance` | `2200` | 大于它休眠 |
| `unload_distance` | `4200` | 大于它释放节点 |
| `max_mounted` | `8` | 同时挂载上限 |
| `tick` | `0.12` | 调度检测间隔（秒） |

字段的实际取值见 `example/world_config.tres`。

### 编辑器资源库（room_library.tres）

`RoomAtlasSceneLibrary` 是**纯编辑期** Resource，主要字段：`scenes: Array`（已导入场景，用无类型 Array 便于手写 / diff）、`sizes: Dictionary`（room_size 基线）、`groups: Array` + `group_of: Dictionary`（虚拟分组）。它就是左栏列表的全部内容——项目里其余 `.tscn` 只通过「导入 .tscn」对话框选取，不自动出现在列表里：

| 分区 | 判定 | 行为 |
|---|---|---|
| 未载入 | 在 `scenes` 中，但 `world_config.tres` 里没有任何 `placement.scene` 指向它 | 固定排在**上半区**；拖到画布放置房间；× 移出列表 |
| 已载入 | 在 `scenes` 中，且至少有一个 `placement.scene` 指向它 | 排在下半区；可继续拖放复用；× 从地图移除对应房间后回落到未载入 |

分区由**是否被拖入地图**决定，与运行期是否挂载无关。拖拽落图、删除「已载入」项以及它们的撤销都会让条目在两个分区之间迁移；内部有差量保护，改 `cells` / `tint` 等不影响分区的操作不会重建列表。若一个资源被多间房引用，删除「已载入」项会一并移除这些房间。

虚拟组只影响列表展示：`groups` 存组名（数组顺序即显示顺序），`group_of` 存每个场景的归属。拖拽只改 `group_of`；删组只清 `groups` 与该组的成员归属，tscn 与 `world_config.tres` 都不受影响，成员自动回到「已载入」根层。组内条目仍按 `scenes` 顺序显示。

### 房间基类与身份声明

自建房间继承 `RoomAtlasRoom2D`（`addons/room_atlas/runtime/room_atlas_room2d.gd`）即可；插件按属性名识别，不依赖具体脚本文件：

```gdscript
@tool
extends RoomAtlasRoom2D

func _draw() -> void:
	super()   # 基类画编辑器边界预览，运行时自动跳过
	# 房间内容...
```

基类提供 `room_id`（`StringName`）、`room_title`（`String`，显示名）、`room_size`（`Vector2i`，像素）和 `show_editor_bounds`，并在 **2D 编辑器**里常驻绘制边界预览：

- 亮青主边框 + 四角外向 L 形角标（画在边界外侧，不会被房间内容盖住）
- 顶边 `W xxx px`、左边 `H xxx px` 尺寸线与刻度，房间上方写 `宽 × 高 px`
- 四等分淡网格与很淡填充，方便判断内容是否出界
- 在 Inspector 改 `room_size` 会立即重绘；`show_editor_bounds = false` 可关闭预览
- 预览只在编辑器绘制（`Engine.is_editor_hint()`），运行时不产生任何绘制

编辑器通过 `PackedScene.get_state()` 读取这些属性，不实例化场景；读不到尺寸时退回 `2400×1080`。

改完 `room_size` 保存场景后，左栏对应条目会显示橙色 ⚠（与地图占位或资源库基线不一致），行内会多出一个同步按钮，tooltip 写出两边尺寸；点该按钮即可按这个 tscn 的尺寸更新地图（可撤销），未载入项则更新基线。

- 拖入地图时 `placement.id` 取 `room_id`、`cells.size` 取 `room_size ÷ cell_size`；`room_id` 已被占用时自动回退到 `rN`，避免重复 id 死锁。
- 属性面板里 `id` / `title` / `scene` / `w` / `h` 只读并排在上半段，`x` / `y` / `tint` 可改并排在下半段；改 `x` / `y` 或在画布拖动房间都会原样保留 `cells.size`。
- 单击「未载入」条目时，右侧只读该 `.tscn` 的 `room_id` / `room_title` / `room_size` 显示五项信息，并把下半段的可编辑行整组隐藏。

### 校验规则

`RoomAtlasValidator.validate(config)` 只查几何与资源自洽：

- `cell_size` 为正、`rooms` 非空、`id` 唯一非空、`scene` 已指定、`cells.size` 为正
- **格区间两两不重叠**（重叠会让"谁覆盖谁"取决于加载顺序，把确定性交给运行时）
- `0 < mount < sleep < unload`、`max_mounted > 0`、`tick > 0`

**不查**连通性、可达性、缝隙、门对齐——这些不是布局层的职责。

---

## Runtime API

`RoomAtlasStreamer` 是唯一的运行时入口。所有方法都是几何 / 生命周期语义，**没有任何方法会移动节点**。

| 方法 | 说明 |
|---|---|
| `configure(config)` | 载入配置、建立索引 |
| `track(target: Node2D)` | 注入"以谁为中心加载"，可以是玩家 / 镜头 / 载具 / 任意节点 |
| `world_rect(id) -> Rect2` | 房间的世界矩形 |
| `to_world(id, local_pos) -> Vector2` | 房间局部坐标 → 世界坐标（纯换算） |
| `world_to_room(world_pos) -> Dictionary` | 世界坐标 → `{ id, local }`，不在任何房间时返回 `{}`。刻意不叫 `to_local`，避免与 `Node2D.to_local()` 混淆 |
| `room_at(world_pos) -> StringName` | 点属于哪个房间，空 `StringName` 表示无 |
| `is_mounted(id)` / `is_loading(id)` | 状态查询 |
| `mounted_ids() -> Array[StringName]` | 已挂载房间列表 |
| `request_room(id)` | 异步预载（不等待），插件不知道调用方意图 |
| `ensure_room(id)` | 同步保底：返回时该房间一定已挂载或已唤醒 |

信号：`room_mounted(id)`、`room_sleeping(id)`、`room_unloaded(id)`、`room_load_failed(id, path)`。

房间场景根节点可选实现 `configure(id, placement, cell_size)` 钩子，用来拿自己的几何信息；插件不强制，房间内容完全自己决定怎么用。继承 `RoomAtlasRoom2D` 时基类已有默认实现（只记录 id），子类 `super()` 后处理自己的内容即可。示例见 `example/room_view.gd`。

### 游戏层如何组合出「前往指定房间的指定位置」

下面这段代码**属于游戏层，不在插件里**：

```gdscript
func go_to(room_id: StringName, local_pos: Vector2) -> void:
	streamer.request_room(room_id)                  # 可提前预载，避免那一帧读盘
	streamer.ensure_room(room_id)                   # 同步兜底：落地不踩空
	player.global_position = streamer.to_world(room_id, local_pos)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	cam.reset_smoothing()
```

插件提供 ① 保证挂载 ② 坐标换算，游戏层负责 ③ 移动节点 ④ 清理状态。复活、剧情跳转、调试定位、NPC 生成点都复用这一组 API——这正是它没有玩法语义带来的自由度。

---

## 设计决策

| 决策 | 理由 |
|---|---|
| 配置里没有门 / seam / portal / 连通图 | 连通性属于内容层；删掉后配置只描述"房间在哪、对应哪个场景"，通用性更强 |
| 配置里没有 `anchor_room` / 出生点 | 开局挂哪间房由游戏层调 `ensure_room()` 决定 |
| 用 `track()` 而不是 `player` | 插件不假设世界里存在"玩家"，依赖方向始终是游戏层 → 插件 |
| 用 `to_world()` 而不是 `teleport_to()` | 插件只返回数据，从不移动节点 |
| 存格坐标而不是世界坐标 | 整数、可校验、无浮点误差、天然不重叠、支持跨多格 |
| `cell_size = 1px`，索引桶独立为 600px | 房间边界精确到 1px，同时不让空间索引随网格粒度膨胀；坐标单位与索引粒度是两个不相干的职责 |
| 房间不生成侧墙 | A 开放连续世界靠网格边界自然连通；墙若要存在，属于房间自己的内容 |
| `max_mounted` 与距离阈值分离 | 两者需要协同；设太小会让刚挂载的房间立刻被休眠，产生周期性抖动 |

---

## 验证

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
PROJ=/Users/yao.zhou/GitHub/godot4-room-atlas

# 1) 资源导入 + 脚本解析（会生成 .uid 文件，务必入库）
$GODOT --headless --path "$PROJ" --import

# 2) 跑几帧，确认示例主场景无运行时报错
$GODOT --headless --path "$PROJ" --quit-after 5

# 3) 单文件语法检查（新增 / 改动的脚本逐个跑）
for f in addons/room_atlas/editor/room_atlas_world_canvas.gd \
         addons/room_atlas/editor/room_atlas_grid_canvas.gd \
         addons/room_atlas/editor/room_atlas_scene_library.gd \
         addons/room_atlas/editor/room_atlas_scene_list.gd \
         addons/room_atlas/runtime/room_atlas_room2d.gd \
         example/room_view.gd example/room_platform.gd example/room_decor.gd; do
  $GODOT --headless --path "$PROJ" --check-only --script "res://$f"
done

# 4) 启动编辑器若干帧，确认 dock 构建 / 资源库加载无报错
$GODOT --headless --path "$PROJ" --editor --quit-after 90
```

`.uid` 与 `.tscn` / `.tres` 需要入库；`.godot/` 已在 `.gitignore` 中忽略。移动或重命名脚本 / 场景请在 Godot 编辑器内操作，否则 `uid://` 引用会断。拖拽落图、导入对话框属于 GUI 交互，headless 只能验证脚本与资源，需在编辑器里人工试一遍。

---

### 编辑器上下文：`@tool` 是必需的

`addons/room_atlas/` 下除 `room_atlas_streamer.gd` 之外的脚本都带 `@tool`。原因是：编辑器里的 `plugin.gd` 是 `@tool` 脚本，它加载 `.tres` 时，若资源上的自定义脚本没有 `@tool`，Godot 只会创建一个**占位实例（placeholder）**，自定义方法一律不可调用：

> `Invalid call ... Attempt to call a method on a placeholder instance. Check if the script is in tool mode.`

受影响的整条链：`RoomAtlasConfig.placements()`、`r is RoomAtlasPlacement` 类型判断、`RoomAtlasStreamingSettings` 字段读取，以及 `RoomAtlasValidator` 的静态方法——所以这几个脚本都要加 `@tool`，缺一个就可能在编辑器里复现该错误。

`RoomAtlasStreamer` 故意不加：它是运行时节点，加了会让它在编辑器场景里也执行 `_process()` 调度。

`plugin.gd` 加载配置时额外用了 `ResourceLoader.CACHE_MODE_REPLACE`，强制替换缓存中的实例——这样刚给脚本加上 `@tool` 之后，即便编辑器还开着也能立刻拿到真正的实例。保险起见，改动这些脚本后仍建议重新打开项目。

---

## 已知限制

- **资源缓存无 LRU**：`_cache` 常驻，走过的房间越多占用越大。房间数量上千后需要淘汰策略（P3）。
- **`ensure_room()` 与在途线程请求**：同步保底会丢弃该房间的在途请求并直接 `load()`，极端情况下有一次同步读盘。可接受，但生产级应统一成"等待在途请求完成"。
- **无 floating origin**：Godot 的 `Vector2` 是 32 位浮点，世界坐标超过约 \(1.6\times10^7\) px 后整数精度下降，接缝可能出现裂缝（P4）。
- **索引桶尺寸固定**：`RoomAtlasLayout.BUCKET_SIZE = 600 px` 是内部常量，未开放到配置。房间普遍远大于或远小于它时可按实际尺寸调整——太小则桶数变多，太大则 `query_near()` 的候选超集变宽。
- **编辑器属性面板**：`id` / `scene` / `w` / `h` 只读（由 `.tscn` 自己声明，落图时固定下来），只有 `x` / `y` / `tint` 可改；要换房间场景或身份得改 `.tscn` / `.tres` 或重新拖入。
- **调度参数是全局的**：所有房间共用一套 `mount/sleep/unload`；未来可考虑按房间或按层覆盖。

---

## 迭代路线

1. **P2 剩余工作**：tscn 资源库 / 导入 / 拖拽落图 / 列表联动属性面板已完成；接下来把校验结果做成可点击列表并定位到出问题的房间、画布内搜索与批量操作。
2. **P3 规模化**：`_cache` LRU、按格懒生成空间索引、每房独立 `.tres`（降低多人协作冲突）。
3. **P4 大坐标**：floating origin，平移量必须是 `cell_size` 的整数倍，否则网格会整体错开。

> **P1 已完成**：`add_dock()` + `EditorDock.default_slot = DOCK_SLOT_BOTTOM`、自绘 `Control` 网格画布、拖拽吸附、x/y 轴相邻辅助线、重叠高亮、`EditorUndoRedoManager` 撤销。Godot 4.7 里 `add_control_to_bottom_panel()` / `add_control_to_dock()` 已弃用，不要再使用。

---

## 参考

本项目的设计脱胎于一个 Godot 4 无缝区域流式加载练习工程（`godot4-seamless-world-demo`）：保留了它的距离流式调度、玩家与区域解耦、三级生命周期思路；去掉了门配对推导原点、锁门玩法与全局包围盒假设，改为编辑期配置驱动 + 空间索引。
