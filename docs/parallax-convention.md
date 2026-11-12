# 2D 视差约定（Seamless Rooms）

> 相关文档：[根 README](../README.md) · [插件 README](../addons/seamless_rooms/README.md) · [实体分层](entity-layering.md)

本文定义 `addons/seamless_rooms/companion/` 中视差组件对外承诺的语义、参照系、分层、绘制顺序与校验规则。

它不是某个具体关卡（例如 `moss_hole`）的复刻说明：具体比值由美术按房间构图决定，组件只保证同一套参数在不同房间、不同窗口尺寸下行为一致。

## 1. 核心约定：一个无量纲的 scroll_scale

每一层只有一个视差参数 `scroll_scale: Vector2`，X / Y 两轴独立。它是**速度倍率**，不是像素/秒，也不是深度值。

| 取值 | 含义 | 典型内容 |
|---|---|---|
| `0` | 钉在屏幕上，完全不随相机移动 | 天空、全屏暗角、UI |
| `0 ~ 1` | 背景层，数值越小越远 | 远山、云、洞穴背景 |
| `1` | 与普通世界物体同速，没有视差 | 地面、平台、角色、可交互物 |
| `> 1` | 前景层，数值越大越近 | 前景草、树叶、粒子 |
| `< 0` | 反向移动 | 水面倒影、特殊特效 |

这套语义与以下实现一致，是本组件唯一对外的视差参数：

- Godot 4 `Parallax2D.scroll_scale`
- Godot 3/4 `ParallaxLayer.motion_scale`
- Phaser `scrollFactor`
- Cocos2d-x `ParallaxNode` 的每子节点 ratio

Unity 社区的 `parallaxFactor` 命名不统一：有人把它定义为“跟随相机的比例”（0.5 = 相机移动一半），那它对应的是 `scroll_scale = 1 - factor`。**迁移时先确认对方用的是哪一种定义。**

### 硬规则

1. **视差层只放装饰。** 不要放 `CollisionObject2D` / `CollisionShape2D` / 可交互物；碰撞体留在世界层，否则视觉和物理会分离。
2. **更新时机在相机之后。** 先让相机控制器完成本帧移动，再把 `get_screen_center_position()` 推给视差系统；用相机节点的 `global_position` 或过早更新都会抖。
3. **移动层根节点，不移动层内每个 Sprite。** 每层只有一个 `position` 变化，子节点相对位置保持不变。
4. **绘制顺序用层 / z band 管理。** 不要逐 Sprite 调 `z_index`，也不要依赖场景树的偶然顺序。
5. **重复背景必须无缝，且纹理左上角对齐 `(0,0)`。** 这是 Godot 官方 `Parallax2D` 教程的硬性要求；纹理居中会导致循环时被切掉一半。
6. **层数控制在 3~7 层。** 层太多会牺牲可读性和性能，通常 4~6 层足够。

## 2. 参照系：本组件唯一新增的约定

原生 `Parallax2D` / `ParallaxBackground` 的参照系隐含在“世界原点 + 视口”里。房间被流式摆到任意世界坐标后，这个隐含参照系会让整层相对房间漂移。本组件把它显式化：

\[
\text{shift} = (1 - \text{scroll\_scale}) \odot (\text{camera\_center} - \text{reference})
\]

```text
plane.position = offset + shift
```

`offset` 是作者摆放位置（层根节点的 `position`），`shift` 是每帧叠加的偏移。

| `reference_mode` | `reference` | 适合 |
|---|---|---|
| `Room Center` | 房间矩形中心 | **默认。** 房间是构图单位，美术在房间中心摆图 |
| `Custom` | 房间左上角 + `reference_local` | 固定机位 Boss 房、过场、特殊构图 |

`reference_local` 只在 `Custom` 下显示并生效；`Room Center` 下会被隐藏并忽略。

### Room Center（默认）

- 相机正好在房间中心时 `shift = 0`，运行时画面与 2D 编辑器逐像素一致。
- 不依赖视口尺寸；窗口比例变化、缩放变化都不会让背景相对房间漂移。
- 作者工作流：在 2D 编辑器里把视图中心放在房间中心，再摆各层内容。

### Custom

- `reference_local` 是房间局部坐标，房间左上角为 `(0,0)`。
- 典型用法：Boss 房固定机位、过场镜头、需要与某个特定相机位置对齐的构图。

### 位移钳制（可选）

`shift` 本身是有界的：相机留在房间内时 \(\lvert \text{camera\_delta} \rvert \le (\text{房间尺寸} - \text{视口尺寸}) / 2\)，所以默认配置不需要额外钳制。只有这些情况才打开 `clamp_shift`：

- 相机不受房间矩形限制：过场运镜、电梯 / 转场、跨房平移、自由跟随；
- 相机在别的房间时本房间的 rig 仍在接收组播（邻房跨接缝可见），不夹会让整层相对自己的房间滑走；
- `scroll_scale < 0` 或明显大于 1，位移被放大；
- 想给构图一个与窗口比例无关的硬上限（美术只画了 ±N px 的内容）。

\[
\text{shift} = \operatorname{clamp}\big((1-\text{scroll\_scale}) \odot \Delta,\; -\text{min\_shift},\; \text{max\_shift}\big)
\]

- 每轴独立，`min_shift` / `max_shift` 都是取正值的量级；`min_shift = 0` 表示下限镜像 `max_shift`（旧行为）。
- 下限默认对称，因此只能近似 `Parallax2D.limit_begin / limit_end`：零点始终是作者摆放位置，不能按绝对滚动量限制。
- `scroll_scale = 0` 的钉屏层不要开：它的语义就是 `shift = Δ`，夹住之后相机越过上限就不再钉屏。
- 取值先按 \(\lvert 1 - \text{scroll\_scale} \rvert \times (\text{房间尺寸} - \text{视口尺寸}) / 2\) 估自然上限，保险丝取 1.2~1.5 倍；设小了背景会提前冻住。
- 场景面板只会提示「永远不会触发」：它用房间矩形作 `camera_delta` 上界，不需要知道视口尺寸；是否提前冻住请在 `editor_preview_absolute` 下平移视图确认。
- 房间小于视口且用了 `required_zoom` 时，相机被钉在房间中心、`camera_delta = 0`，视差本身就不存在，钳制救不了；这种情况要调 zoom 或参照系。

### 旧 `ParallaxBg` 迁移

组件不再提供运行时逐层锚定模式。旧关卡使用自定义 `ParallaxBg` 时，先在外部按下面的公式一次性重投影到统一参照，再把 `reference_mode` 设为 `Room Center`：

```text
position = reference + scroll_scale * (position - reference)
```

其中 `scroll_scale = pow(k, move_layer)`，`reference` 取目标模式的零点（`Room Center` 时为房间中心）。重投影后画面与旧实现逐像素一致，之后所有层共享同一个参照系。

## 3. 数据模型

```text
ParallaxRig（SeamlessRoomParallax，Control）
├─ reference_mode: ROOM_CENTER | CUSTOM
├─ reference_local: Vector2          # CUSTOM 时使用
├─ clip_to_room: bool                # 流式房间建议 true
└─ layers: ParallaxPlane[]

ParallaxPlane（SeamlessRoomParallaxLayer，Node2D）
├─ scroll_scale: Vector2             # 1 = 世界，0 = 钉屏幕
├─ position: Vector2                 # 作者摆放位置（home）
├─ z_index: int
├─ clamp_shift: bool
├─ max_shift: Vector2               # 正向位移上限
└─ min_shift: Vector2               # 负向上限（取正值），0 = 镜像 max_shift
```

一期的能力边界：

- 支持：有限房间构图、X/Y 独立比例、对称 / 非对称位移钳制、编辑器预览。
- 暂不支持：`repeat_size` / `repeat_times` / `autoscroll` / `limit_begin/end`。
- 如果某层必须无限平铺，优先继续使用原生 `Parallax2D`，或者等二期扩展。

## 4. 分层与推荐比例

| 层 | `scroll_scale` | 内容 | 视觉处理 |
|---|---|---|---|
| Sky / Background | `0 ~ 0.1` | 天空、最深洞穴背景 | 低对比、低饱和 |
| Far | `0.1 ~ 0.25` | 远山、远景剪影 | 冷色、雾化 |
| Mid | `0.3 ~ 0.5` | 中景建筑、植被 | 中等对比 |
| Near Background | `0.65 ~ 0.85` | 近景背景 | 接近世界色 |
| Gameplay / World | `1.0` | 地面、平台、角色、碰撞 | 正常 |
| Foreground | `1.1 ~ 1.4` | 前景草、树叶、暗角 | 更深、更饱和 |
| UI | 独立 `CanvasLayer` | HUD、小地图 | 不参与世界视差 |

这些比例是美术起点，不是硬性标准。关键是**相邻层的比例要拉开**：`0.1 / 0.2` 这种差距在 1080 px 的相机行程里只有 108 px 的屏幕位移差，很难看出层次。表里的层名是构图角色示例，不是模板节点名；模板只定义 §5 的 `Backdrop` 与 8 个视差 band，内容分组由房间自建。

### z band

推荐用固定 band，而不是随手写 `z_index`：

```text
-100  BgParallax（背景 rig）
 -80  Far
 -40  Mid
 -10  Near
   0  World（地面、平台、碰撞、水）
 100  FgParallax（前景 rig）
1000  UI（独立 CanvasLayer）
```

- 背景 rig 的 `z_index` 设为 `-100`，与 Godot `ParallaxBackground` 的默认 `layer = -100` 对齐。
- 前景 rig 的 `z_index` 设为 `100`，保证盖住玩家和世界内容。
- 如果只用一个 rig，也可以在各层上写 `-20 / -10 / 10`；只要**背景层 < 0、前景层 > 0**，并且不依赖树顺序。
- `SeamlessRoomParallaxLayer` 的校验会按“容器 z + 层 z”计算有效值。

## 5. 场景结构

推荐把背景和前景拆成两个 rig，把世界夹在中间。层骨架由 `example/rooms/room_template.tscn` 统一定义，`r1`–`r8` 全部以场景继承（`instance=ExtResource("1_base")`）复用它；模板只有空层，不含任何房间内容：

```text
RoomTemplate（SeamlessRoom2D，由 r1–r8 继承）
├─ BgParallax（SeamlessRoomParallax，z = -100，clip_to_room = true）
│  ├─ Backdrop   # Node2D，房间固定静态背景，不挂 layer 脚本
│  ├─ Far        scroll_scale = (0.55, 0.55)
│  ├─ Far2       scroll_scale = (0.75, 0.75)
│  ├─ Mid        scroll_scale = (0.87, 0.87)
│  └─ Near       scroll_scale = (0.95, 0.95)
├─ World（Node2D）
│  ├─ Underlay（z = -10）  # 世界后景 band
│  └─ Spawns（只放标记，出生点由各房间自行新增）
└─ FgParallax（SeamlessRoomParallax，z = 100，clip_to_room = true）
   ├─ Occluders   scroll_scale = (1.0, 1.0)   # 前景遮片，z = 20
   ├─ Foreground  scroll_scale = (1.06, 1.06)
   ├─ FG2         scroll_scale = (1.18, 1.18)
   └─ FG3         scroll_scale = (1.30, 1.30)
```

`Backdrop` 是「房间固定」而非「钉屏」：它不挂 `SeamlessRoomParallaxLayer`，相对房间静止、随相机滚出画面；真正钉屏需要 `scroll_scale = (0, 0)`（§4），本项目不用。它也不设 `z_index`，保证挂在它下面的 `Darkness` 有效 z 不变。

### 模板节点准入标准

模板只描述**房间怎么画 / 怎么动**（结构、绘制 band、运动参数），不描述**房间里有什么**（题材、物件分类）。一个节点需同时满足全部条款才能进模板：

| # | 条款 | 判据 |
|---|---|---|
| S1 | 机制依赖 | 被运行时代码按路径或脚本类型引用：`example/actors/room_entity_director.gd` 的 `World/Spawns`；`SeamlessRoomParallax` 按 `SeamlessRoomParallaxLayer` 类型扫描并组播；`_setup_rect()` 认 rig 脚本 |
| S2 | 规范承载 | 承载跨房一致的参数：z band、`scroll_scale` 默认值、参照系、clip、`Node2D` 变换链；兄弟顺序影响绘制，顺序本身也是契约 |
| S3 | 命名可承诺 | 名字是与题材无关的结构术语（层 / band / 容器），不是内容分类（水、天空、地形）；要能承诺在洞窟、城镇、室内、Boss 房里都成立 |
| S4 | 差异可表达 | 单房特例只能靠属性覆写或**新增**子节点表达；凡需要「删掉 / 改名」才能表达的东西不能进模板 |
| S5 | 最小集合 | 模板节点是 8+N 间房永久背负的公共 API。新增节点永远允许、删基础节点永远不允许，宁可少放 |

**否决线**：命中内容分类名即否，即使空 `Node2D` 零成本——成本在于名字永久占坑。`Water / Terrain / Obstacles / Props` 属于 r1 的构图分组，由 `r1.tscn` 自行新增；`Sky` → `Backdrop`、`Decals` → `Underlay` 是把内容分类名改成结构术语后才纳入规范。按此标准模板共 15 个节点（根 + 14 层/分组），8 个视差 band 的名称、数量与默认比例属于 S2 的规范承载，由模板统一定义。

比例是模板默认值，单房可在继承节点上覆写 `scroll_scale`。以后加层、改 z band、改默认比例一律改模板；派生场景不能删除 / 重命名 / 调整基础节点顺序。两个 rig 的 `offset_right / offset_bottom` 与 `fallback_size` 在模板里统一写 2400×1080，只是编辑期占位，运行时由父房间的 `camera_world_rect()` 自动覆写。

`scroll_scale = (1, 1)` 放在前景 rig 里是合法的“前景遮片”：它不产生视差，但能保证苔藓、草丛盖在角色前面。`r1` 在继承的 `FgParallax/Occluders` 下挂了 `OccluderTest`（`z_index = 20`，演示占位，可替换成树冠 / 草叶）。校验不会对这种情况报警。

模板定义 8 个视差 band：背景 `Far / Far2 / Mid / Near`，前景 `Occluders / Foreground / FG2 / FG3`；`Backdrop` 是房间固定静态背景，不计入视差 band。`r1` 的内容（95 个原 `Bg_XXX` 合并成的 `Sprite2D`、`Backdrop/Darkness`、自建的 `Water / Terrain / Obstacles / Props` 下的地形 / 碰撞、4 个出生点）挂在继承层与自建分组下，节点路径与改造前一致；r1 已按 `position = reference + scroll_scale * (position - reference)` 一次性重投影到 `Room Center`，相机在房间中心时构图与旧版一致。`r2`–`r8` 只覆写 `room_id / room_title / room_size`，自然获得同一套空层。新增素材时选中 band，把贴图拖进 2D 视图即可，不需要给每个素材配 `scroll_scale`。

模板默认比例沿用 r1 的构图选择，不是 §4 的推荐比例：`Far 0.55 / Far2 0.75 / Mid 0.87 / Near 0.95`，`Occluders 1.0 / Foreground 1.06 / FG2 1.18 / FG3 1.30`。

旧 `ParallaxBg` 关卡在导入前完成一次重投影即可；运行期不再有逐层锚定模式。

## 6. 运行时契约

视差组件**不认识相机**，由游戏层每帧推送相机中心：

```gdscript
get_tree().call_group(SeamlessRoomParallax.GROUP, &"set_camera_center",
		cam.get_screen_center_position())
```

- 用 `get_screen_center_position()`，它包含 limit、拖动边距和平滑后的真实屏幕中心。
- 在相机移动完成之后推送；示例项目放在 `_process`，相机控制器放在 `_physics_process`。
- 一个场景可以有多套 rig；组播一次全部更新，不需要认识房间实例。
- 没人推送时，层停在作者摆放的位置；失败模式是“没有视差”，不是“内容消失”。
- 分屏 / 多 `SubViewport`：每个 viewport 各一套 rig，各自推自己的相机中心；一期的单组播契约不支持分屏。

## 7. 编辑器工作流

两个脚本都是 `@tool`：

- 默认预览模式以打开场景时的 2D 视图中心为零点，各层与作者摆放完全重合；平移视图即可看到相对视差。
- 打开 `editor_preview_absolute` 后，视图中心就是模拟相机中心，直接按运行时公式预览，用于核对构图。
- 保存前收到 `NOTIFICATION_EDITOR_PRE_SAVE`，各层先复位到作者坐标；预览位移不会写进 `.tscn`。
- 容器会强制 `position = (0,0)` 并让尺寸等于房间矩形，保证 `clip_contents` 的裁剪框就是房间边界。不要靠移动容器来对位，移动层内容。

### 自检

1. 把一层临时设为 `(1, 1)`：它应该和地面完全同步，贴地装饰不掉队。
2. 把一层临时设为 `(0, 1)`：它应该钉在屏幕上，完全不随相机移动。
3. 相机从房间最左走到最右：屏幕位移应等于 `scroll_scale × 相机行程`；相对地面的滑移等于 `(1 - scroll_scale) × 相机行程`。
4. 走到房间接缝：背景不应画进相邻房间（`clip_to_room = true`）。

## 8. 校验规则

`SeamlessRoomParallaxLayer` 会在场景面板给出以下提示：

| 条件 | 提示 |
|---|---|
| 父节点不是 `SeamlessRoomParallax` | 收不到相机更新 |
| `scroll_scale = (1,1)` 且有效 z <= 0 | 与世界同速，没有视差 |
| `scroll_scale` 有轴 > 1 且有效 z <= 0 | 前景层没有画在世界之上 |
| `scroll_scale` 有轴 < 1 且有效 z > 0 | 背景速度画在前景，会相对地面滑动 |
| 子树里出现碰撞体 | 视差层不应放物理，视觉和物理会分离 |
| `clamp_shift` 打开且 `max_shift` 某轴 <= 0 | 该轴无法往正方向位移 |
| `min_shift` 有负分量 | 负数无效，回退到对称 `-max_shift` |
| `clamp_shift` 打开且有轴 `scroll_scale = 0` | 钉屏层被夹住，相机越过上限后开始漂移 |
| `clamp_shift` 上限 >= 房间内最大位移 | 钳制永远不会触发 |

`SeamlessRoomParallax` 容器会提示：

| 条件 | 提示 |
|---|---|
| `clip_to_room = false` | 可能画进相邻房间 |
| 编辑器预览开启 | 一个可见标记，确认 tool 实例在跑 |

## 9. 从原生节点迁移

| 来源 | 目标 |
|---|---|
| `Parallax2D.scroll_scale` | `scroll_scale`，1:1 |
| `Parallax2D.scroll_offset` | 层根节点的 `position` |
| `Parallax2D.repeat_size` / `repeat_times` | 一期不支持；保留原生节点或等二期 |
| `Parallax2D.autoscroll` | 一期不支持 |
| `Parallax2D.limit_begin/end` | `min_shift` / `max_shift`（以作者位置为零点的近似；`min_shift = 0` 即对称） |
| `ParallaxLayer.motion_scale` | `scroll_scale`，1:1 |
| `ParallaxLayer.motion_offset` | 层根节点的 `position` |
| `ParallaxBackground.layer` | rig 的 `z_index` band |
| 自定义 `ParallaxBg`（`move_layer` / `k`） | `scroll_scale = pow(k, move_layer)`；先用上面的重投影公式收回 `Room Center` |
| Phaser `scrollFactor` | `scroll_scale`，语义一致 |
| Unity `parallaxFactor` | 先确认定义；若是“跟随比例”，`scroll_scale = 1 - factor` |

迁移时先决定参照系：

- 旧坐标是原样拷贝的屏幕空间美术 → 先减去房间左上角，再用 `Custom` 的 `reference_local` 对齐，或直接重投影到 `Room Center`。
- 在 r1 里按房间中心重新摆过 → `Room Center`，不要补偿。
- 旧关卡是逐层锚定的 `ParallaxBg` → 先用重投影公式收回 `Room Center`。
- 只有这样才能避免“看起来像，但整体偏几百像素”。

## 10. 与行业实现对照

| 引擎 | 组件 | 参数 | 0 | 1 | >1 |
|---|---|---|---|---|---|
| Godot 4 | `Parallax2D` | `scroll_scale` | 静止 | 与世界同速 | 更近、更快 |
| Godot 3/4 | `ParallaxLayer` | `motion_scale` | 静止 | 与世界同速 | 更近、更快 |
| Phaser | `ScrollFactor` | `scrollFactor` | 钉在相机 | 正常世界 | 前景更快 |
| Cocos2d-x | `ParallaxNode` | 每子节点 ratio | 钉住 | 与世界同速 | 更快 |
| Unity | 自定义 / Cinemachine | `parallaxFactor` | 视实现 | 世界 | 前景 |
| GameMaker | Room Layer | `hspeed/vspeed` | — | — | 单位是 px/帧，不是比例 |

结论：**没有跨引擎的正式规范，但有稳定的事实标准**——一层一个 `scroll_scale`，0 = 钉屏幕，1 = 世界，>1 = 前景；层根节点统一由相机驱动；背景和前景分 band；装饰层不放物理；更新在相机之后。

## 11. 路线图

- **一期（当前）**：有限房间构图、`scroll_scale`、`Room Center` / `Custom` 两种参照系、z band 约定、校验、编辑器预览。
- **二期**：`repeat_size` / `repeat_times` / `autoscroll` / `limit`。
- **三期**：Shader UV 滚动的天空 / 云层、分屏多 rig、可选的 `ParallaxPreset` 资源（只存比例和 band，不存内容）。
