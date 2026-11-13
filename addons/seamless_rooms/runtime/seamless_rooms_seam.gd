@tool
class_name SeamlessRoomSeam
extends Resource

## 一条「房间共享边过渡」配置：只描述两房之间的关系与参数，不存坐标。
##
## at / from / to / span 都由 SeamlessRoomLayout.seams() 按两侧 cells 现算，
## 因此拖动房间或改尺寸不需要同步修改本资源；失效关系由 Validator 报 WARN。
## 详见 docs/seam-blending.md。

const AXIS_X := 0   # 竖直接缝：左右相邻，羽化沿 X
const AXIS_Y := 1   # 水平接缝：上下相邻，羽化沿 Y

@export var left: StringName = &""
@export var right: StringName = &""
@export_enum("Vertical", "Horizontal") var axis: int = AXIS_X
## 默认关闭：只有画布上显式启用才生成遮罩。
@export var enabled := false
## 半宽占共享边长度的比例，与房间尺寸解耦；插件默认值保持中立。
@export_range(0.01, 1.0, 0.01) var width_ratio := 0.15
## 世界像素上限，0 = 不限制。
@export var width_max := 0.0
@export_range(0.0, 0.9, 0.01) var core := 0.12
@export var feather_min := 1.0
@export var feather_max := 1.0
@export var color := Color(0.02, 0.03, 0.025, 1.0)
## 题材化入口；替换时仍须遵守 blend_premul_alpha 预乘契约。
@export var material_override: ShaderMaterial = null


## 稳定键：按 id 字典序，房间相对位置变化不会丢配置。
static func make_key(a: StringName, b: StringName, p_axis: int) -> String:
	var sa := str(a)
	var sb := str(b)
	if sa > sb:
		var tmp := sa
		sa = sb
		sb = tmp
	return "%s|%s|%d" % [sa, sb, p_axis]


func key() -> String:
	return make_key(left, right, axis)


## 羽化曲线，与 companion 默认 shader 的
## pow(1 - smoothstep(core, 1.0, abs(u)), feather) 等价。
## 画布渐变预览调用本函数，避免预览与运行各写一套曲线；
## seam_probe.gd 对 GLSL 等价写法做数值一致性断言。
static func feather_alpha(u: float, p_core: float, feather: float) -> float:
	var denom := maxf(1.0 - p_core, 0.0001)
	var t := clampf((absf(u) - p_core) / denom, 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	return pow(1.0 - smooth, maxf(feather, 0.0001))
