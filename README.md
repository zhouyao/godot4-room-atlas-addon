# Seamless Rooms · 示例项目

> 插件的最小可运行示例：8 间房、连续滚动相机、距离流式实体、调试面板与小地图。
> 插件本体的安装、配置格式、Runtime API 见 **[addons/seamless_rooms/README.md](addons/seamless_rooms/README.md)**。

![Godot](https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white)
![Version](https://img.shields.io/badge/plugin-0.2.0-blue)
![Language](https://img.shields.io/badge/GDScript-2D-4b8bbe)

![运行截图：r1 房间内的连续滚动相机、左侧调试面板与右上角小地图](screenshot/0.webp)

*示例 `example/main.tscn`：WASD 移动，Tab 显隐调试面板；右上角小地图实时显示玩家坐标与相机视野。*

---

## 运行

用 Godot 4.7 打开本目录的 `project.godot`，按 **F5** 运行示例（主场景 `res://example/main.tscn`）。也可以用命令行：

```bash
# 在仓库根目录执行
godot --path .
```

### 示例操作

| 输入 | 作用 |
|---|---|
| `W` `A` `S` `D` / 方向键 | 移动白色玩家（不受重力，四向自由移动） |
| `J` / `L`、`Space` 或 `I` | 移动 / 跳跃橙色角色（受重力，会落在 r1 的平台上） |
| `K` | 对最近的怪造成 15 点伤害（两下击杀，掉落金币） |
| `E` | 靠近宝箱时打开 |
| `Tab` | 显示 / 隐藏相机调试面板 |
| 面板 | 切换相机策略、跨房过渡、规则覆盖、跨层冻结；调玩家速度；开关小地图角标 / 视野 / 坐标 |

橙色角色只是场景里的第二个普通节点，用来演示「插件不参与玩家管理」：加载中心始终只有 `track()` 注入的那一个目标。

---

## 示例层说明

示例把「插件能力」和「游戏层拼装」分开：

- `example/main.gd` 只负责 `configure → track → ensure_room → to_world` 的装配顺序；
- 房间场景只放背景、静态装饰、碰撞和出生点；
- 玩家、怪物、宝箱、掉落物统一挂在 `Main/Actors`，由游戏层管理；
- 相机、调试面板、小地图、视差都是可删的示例层。

### 相机控制器

> 本节只讲示例层怎么用插件提供的几何 / 生命周期 API；插件 API 本身见 [插件 README](addons/seamless_rooms/README.md)。

示例用**全局唯一** `Camera2D`，由 `example/camera/room_camera_controller.gd` 驱动：每帧 `streamer.room_at(player.global_position)` 取房间 → 读 `SeamlessRoom2D.camera_rules()` → 把 `limit_*` / `zoom` 与相机位置夹在**约束区**内。插件全程不碰相机；配置几何同步可用，房间还在异步加载时也能立即锁好边界。

示例地图共 8 间房：底层 r4 → r1 横向排列，r5 叠在 r4 上方，r6 再叠在 r5 上方，r7 与 r6 同层向右延伸，r8 位于 r1 上方，整体是一块带 L 形转角的连通区。

#### 连续滚动（默认）

房间配置是静态的，相机中心的可滚动范围能提前算出来。`SeamlessRoomCameraRegion.build(rects, view_size)` 以「与当前房间边贴合连通的矩形集合」和可见世界尺寸为输入，用坐标压缩求出所有满足「视图被房间并集完全覆盖」的相机中心，合并成少量矩形。

结果按「覆盖矩形签名 + 可见尺寸」缓存：签名与矩形顺序无关，连续滚动下同一片连通区跨房不变，所以切房直接复用预计算结果，只有进入另一个连通岛、或视口 / zoom 变化才重跑。运行期每帧只查表：

- 目标点合法 → 直接采用；
- 直线可达 → 用线段与各合法矩形的交区间**精确投影**；
- 直线被挡住 → `waypoint()` 走两段折线（先纵向对齐水平带，或先横向进入 L 形竖直通道），每段都做直线可达校验；
- 所有分支统一限速（`0.02 × 可见宽 + 玩家单帧位移`），避免目标突然合法时一帧跳几百像素；
- 传送 / 策略切换时用 `nearest()` 直接落到目标附近的合法中心。

纵向只在「房间高度不超过视口」时约束到中线；房间高于视口（r5 高 2160）时放开纵向。跨层回落按 `1.2 × 视口高/秒` 平滑逼近中线，不会一帧切掉上一层。包围盒 `touching_bounds(id)` 只用于 `limit_*` 粗约束、`auto_fit` 缩放与 HUD 数值。

由此得到的行为：从 r1 走到 r2 时 limit / zoom / 覆盖集合都不变，相机按死区继续水平滚动，视图自然越过接缝；从 r4 右侧向上进 r5 时，相机会先左移进竖直通道再上移；从 r5 向下回 r4 时，下排房间高度恰好等于视口高，横向合法带是零厚度的，相机会先把 y 对齐再向右跟随。两种回程玩家都全程不出画。

#### 策略与调试面板

所有策略集中在 `example/camera/camera_policy.gd`，运行时热切换（`changed` 信号触发控制器幂等重算）：

| 开关 | 取值（默认） | 说明 |
|---|---|---|
| `out_of_room` | `HOLD_LAST` / **`HOLD_AND_RESPAWN`** / `UNLOCK` / `NEAREST_ROOM` | 玩家不在任何房间时：保持上一房 / 保持并回起点 / 解除 limit / 用最近房间规则 |
| `room_transition` | **`CONTINUOUS`** / `HARD_CUT` | 连续滚动（不换边界） / 硬切一屏 |
| `switch_cooldown` / `enter_margin` | `0` / `0` | 切换冷却、进入缓冲，消除贴边界反复切屏 |
| `override_room_rules` + `override_*` | `false` | 用面板数值覆盖所有房间声明，便于横向对比 |
| `freeze_x_on_layer_change` / `freeze_release_margin` | `true` / `240` | 上层 → 下层跨层后冻结横向跟随；玩家水平位移超过该值解冻 |
| `player_speed` | `1480` | 玩家速度（px/s），面板热调 |
| `show_hud` / `show_player_room` | `true` | 中文状态区、玩家「房内」/「房外」标记 |
| `show_minimap_ids` / `show_minimap_camera` / `show_minimap_coords` | `true` | 小地图房间角标 / 相机视野 / 玩家坐标 |

面板贴在左上角：标题栏（标出 `Tab`）、状态区、可滚动设置区、页脚。设置区按「相机策略 / 房间规则覆盖 / 调试绘制 / 小地图 / 跨层与手感 / 过渡时序」分组；状态区显示房间、房内房外、约束区、缩放与策略、冻结与冷却，几何越界时追加红字警告。

| 想对比 | 操作 | 预期 |
|---|---|---|
| 连续滚动 vs 切屏 | 面板切「跨房过渡」，从 r1 走到 r2 | 连续：相机持续滚动、limit 不变；硬切：整屏跳到 r2 并对准玩家 |
| 锁边有没有用 | 勾「覆盖房间声明的规则」并关「约束生效」，在 r5 里向右走 | 开：停在房间右缘；关：跟到空白区，露出世界网格 |
| 房间外四策略 | 依次选四种，开局按 `D` 约 1.5 秒出 r1 | 画面稳住 / 回起点 / 自由跟随 / 最近房规则切换 |
| 视口大于覆盖区 | 硬切 + 缩放 `0.5`，再轮换「视口适配」三项 | 自动抬高 zoom 填满 / 露出房外并红字警告 |
| 跨层冻结 | 开关「跨层冻结横向」，从 r5 右下角向下进 r4 | 开：保持 x 停在 r4 右半；关：限速右滑到交界 |

调试面板、`override_*` 与显示开关都是**开发期脚手架**，不是插件的公共 API。正式项目建议把「相机运行参数」与「开发期调试开关」拆成两份数据：房间只声明自己那一间的构图参数，跨房过渡与防抖交给统一持有相机的业务系统。

### 实体分层与房间怪物

房间场景只负责背景、静态装饰、碰撞和出生点；玩家、怪物、宝箱、掉落物统一挂到 `Main/Actors`（`y_sort_enabled = true`，`z_index = 10`），由 `RoomEntityDirector` 按 streamer 的挂载状态生成/回收。

```text
r1.tscn: World/Spawns/EnemySpawn_01 (领地/仇恨/leash)
				│ room_mounted
				▼
main.tscn: Main/Actors/r1_EnemySpawn_01  ← 与 Player 同容器，按 Y 排序
				│ room_sleeping
				▼
			  queue_free
```

- 怪物用 `EnemySpawn` 标记，宝箱用 `ChestSpawn`，固定掉落用 `PickupSpawn`；加房间只改房间场景，不改 `main.tscn`。
- 领地半径应小于 `sleep_distance`，保证怪追人时房间不会休眠。
- `r1` 的 `FgParallax/Occluders` 是 `scroll_scale = (1, 1)` 的遮片层，用来放会盖住角色的树冠 / 草叶；1.06 的 `Foreground` 只做纯装饰。
- 完整约定、z band、物理层和 100 间房的运行时上界见 **[docs/entity-layering.md](docs/entity-layering.md)**。

### 小地图 demo

`SeamlessRoomMinimap` 是一个纯显示 `Control`：外部每帧把玩家世界坐标与相机视野推给它，它只负责按配置里的房间几何绘制。示例在 `main.gd` 的 `_build_minimap()` 里创建 `CanvasLayer`、设置锚点，然后：

```gdscript
minimap.configure(config)
minimap.set_cursor_world_position(player.global_position)
minimap.set_camera_view(Rect2(center - view * 0.5, view))
```

完整成员表、导出参数与绘制分层见 **[插件 README 的小地图章节](addons/seamless_rooms/README.md#可选配套seamlessroomminimap)**。

### 视差 demo

`r1.tscn` 用 `SeamlessRoomParallax` 把房间内容拆成背景 / 世界 / 前景三组：

```text
R1（SeamlessRoom2D）
├─ BgParallax（z = -100，clip_to_room = true，Room Center）
│  ├─ Sky（Darkness 背景，不参与视差）
│  ├─ Far（scroll_scale = 0.55）
│  ├─ Far2（0.75）
│  ├─ Mid（0.87）
│  └─ Near（0.95）
├─ World（地面 / 平台 / 水 / 碰撞 / 出生点）
└─ FgParallax（z = 100，clip_to_room = true，Room Center）
   ├─ Occluders（1.0，z = 20）
   ├─ Foreground（1.06）
   ├─ FG2（1.18）
   └─ FG3（1.30）
```

`r1.tscn` 把 95 个原 `Bg_XXX` 合并为 band 下的 `Sprite2D`，视差参数只保留在 band 上；相机在房间中心时构图与旧版一致。之后加素材只需要选中 band，把贴图拖进 2D 视图，`scroll_scale` 都不用碰。

组件的 `scroll_scale` 语义、参照系、位移钳制与迁移映射见 **[插件 README 的视差章节](addons/seamless_rooms/README.md#可选配套房间局部视差seamlessroomparallax)** 和 **[docs/parallax-convention.md](docs/parallax-convention.md)**。

---

## 目录结构

```text
godot4-seamless-rooms/
├── project.godot
├── world_config.tres                 # 运行期地图配置（8 间房，1px 网格）
├── room_library.tres                 # 编辑期资源库（导入列表 + 尺寸基线）
├── screenshot/                       # 运行 / 编辑器截图
├── docs/
│   ├── parallax-convention.md        # 视差规范
│   └── entity-layering.md            # 实体分层与房间怪物
├── addons/seamless_rooms/            # 插件本体；文档见 addons/seamless_rooms/README.md
└── example/                          # 最小可运行示例，不属于插件本体
	├── main.tscn / main.gd           # 装配序列
	├── assets/                       # 按资源类型 / 主题组织
	│   ├── sprites/moss_hole/        # r1 使用的贴图
	│   └── effects/                  # 水面等 SpriteFrames
	├── rooms/                        # 房间场景；根节点直接挂插件基类 SeamlessRoom2D
	│   └── r1.tscn … r8.tscn         # r1 为苔藓洞窟场景，其余为空白房间
	├── actors/                       # 按实体类型分；场景 + 脚本 + 出生点同目录
	│   ├── player/                   # player.gd / player2.gd
	│   ├── enemies/                  # enemy_slime.gd/.tscn / enemy_spawn.gd
	│   ├── interactables/            # chest.gd/.tscn / chest_spawn.gd
	│   ├── pickups/                  # pickup.gd/.tscn / pickup_spawn.gd
	│   └── room_entity_director.gd   # 房间实体供给器
	├── camera/                       # 相机策略与控制器
	│   ├── camera_policy.gd
	│   └── room_camera_controller.gd
	├── ui/                           # 调试 UI / 覆盖层
	│   ├── camera_debug_panel.gd
	│   └── debug_overlay.gd
	├── world/                        # 世界级辅助
	│   └── world_grid.gd
	└── tests/                        # headless 自检
		└── camera_rules_probe.gd
```

`example/rooms/` 只保留房间场景：根节点直接挂 `addons/seamless_rooms/runtime/seamless_rooms_room2d.gd`，示例层不再维护自己的房间脚本；需要自定义房间行为时，按 [插件 README](addons/seamless_rooms/README.md) 的「房间基类与相机规则」继承 `SeamlessRoom2D` 即可。

插件自身的目录结构见 [addons/seamless_rooms/README.md](addons/seamless_rooms/README.md)。

---

## 验证

```bash
GODOT=godot    # macOS 图形版可写 /Applications/Godot.app/Contents/MacOS/Godot
PROJ=$(pwd)    # 在仓库根目录执行

# 1) 资源导入 + 脚本解析（会生成 .uid 文件，务必入库）
$GODOT --headless --path "$PROJ" --import

# 2) 跑几帧，确认示例主场景无运行时报错
$GODOT --headless --path "$PROJ" --quit-after 5

# 3) 单文件语法检查（示例 + 插件）
cd "$PROJ"
for f in $(find addons example -name '*.gd'); do
  $GODOT --headless --path "$PROJ" --check-only --script "res://$f" || exit 1
done

# 4) 相机规则自检（limit / zoom / 桶边界 / 半径注入 / 覆盖区签名 / 200 房大地图 / 视差组件）
$GODOT --headless --path "$PROJ" --script res://example/tests/camera_rules_probe.gd

# 5) 启动编辑器若干帧，确认 dock 构建 / 资源库加载无报错
$GODOT --headless --path "$PROJ" --editor --quit-after 90
```

`.uid` 与 `.tscn` / `.tres` 需要入库；`.godot/` 已在 `.gitignore` 中忽略。移动或重命名脚本 / 场景请在 Godot 编辑器内操作，否则 `uid://` 引用会断。拖拽落图、导入对话框属于 GUI 交互，headless 只能验证脚本与资源，需在编辑器里人工试一遍。

---

## 已知限制（示例层）

- **示例层不提供房间外遮罩**：房外内容（`WorldGrid`、超出 `room_size` 的 Sprite2D）在视图越界时会直接可见；需要「房外不可见」时请在自己的渲染层按房间矩形并集做差集遮罩。
- **连续滚动允许视图跨房**：这是「没有切换过程」的前提；若相邻房间尚未挂载会短暂看到空白，由有效挂载半径提前供给。
- **`Camera2D.offset` 会推过 limit**：偏移在 limit 计算之后叠加，示例把 `camera_offset` 加在相机 `global_position` 上，并保持 `cam.offset = Vector2.ZERO`。
- **相机规则在房间场景里，未挂载时用默认值**：规则不写进 `world_config.tres`，因此地图 dock 不展示它们；控制器用 `ensure_room()` 兜底。
- **示例策略开关只影响运行期**：`override_room_rules` 与调试面板的改动不写回 `.tscn`，重启恢复房间声明值。

插件本体的已知限制（LRU、floating origin、桶尺寸、调度参数全局等）见 [addons/seamless_rooms/README.md](addons/seamless_rooms/README.md#已知限制)。

---

## 插件文档

- [插件 README：安装 / 配置格式 / 编辑器 dock / Runtime API](addons/seamless_rooms/README.md)
- [视差规范：scroll_scale / 参照系 / 分层 / z band / 迁移](docs/parallax-convention.md)
- [实体分层：z band / y-sort / 房间怪物 / 拾取物](docs/entity-layering.md)
