class_name SeamlessRoomSeamBlend
extends Node2D

## 可选配套：按 config.seams 在每条启用的共享边上生成渐变遮罩。
##
## 与 SeamlessRoomMinimap / SeamlessRoomParallax 一致：不认识相机、不寻找节点、
## 不驱动任何 Camera2D；由游戏层摆放并注入配置（或调用 configure()）。
## 遮罩挂在 Main 层，房间休眠 / 卸载时不会消失，因此不会出现半边空白。
## 几何全部由 SeamlessRoomLayout.seams() 派生，配置里不存坐标。
## 详见 docs/seam-blending.md §8。

const DEFAULT_SHADER := preload("res://addons/seamless_rooms/companion/seamless_rooms_seam_blend.gdshader")

@export var config: SeamlessRoomConfig = null
## 游戏层按自己的 z 约定指定；插件本体不硬编码示例数值。
@export var z_band := -101
## 可整体替换的材质模板；为空时用 DEFAULT_SHADER。
@export var default_material: ShaderMaterial = null

var _generated: Array[ColorRect] = []


func configure(p_config: SeamlessRoomConfig) -> void:
	config = p_config
	if is_node_ready():
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for r in _generated:
		if is_instance_valid(r):
			r.queue_free()
	_generated.clear()
	if config == null:
		push_warning("[SeamlessRoomSeamBlend] 未注入配置，跳过生成")
		return
	if config.seam_mode == SeamlessRoomConfig.SEAM_MODE_FADE:
		# FADE 模式由 SeamlessRoomParallax 在背景层内部渐隐，避免双重衰减。
		return

	var by_key := {}
	for e in SeamlessRoomLayout.new(config).seams():
		by_key[e["key"]] = e
	for s in config.seam_configs():
		if not s.enabled:
			continue
		var edge: Dictionary = by_key.get(s.key(), {})
		# 失效边（房间被移动 / 改尺寸）由编辑器校验报告标红，运行时直接跳过。
		if edge.is_empty() or edge["span"] <= 0.0:
			continue
		_spawn(s, edge)


func _spawn(s: SeamlessRoomSeam, edge: Dictionary) -> void:
	var span: float = edge["span"]
	var w := span * s.width_ratio
	if s.width_max > 0.0:
		w = minf(w, s.width_max)
	if w <= 0.0:
		return

	var rect := ColorRect.new()
	rect.name = "Veil_" + s.key().replace("|", "_")
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = s.color      # shader 失效时的兜底色
	rect.z_index = z_band
	if edge["axis"] == SeamlessRoomSeam.AXIS_X:
		rect.position = Vector2(edge["at"] - w, edge["from"])
		rect.size = Vector2(w * 2.0, span)
	else:
		rect.position = Vector2(edge["from"], edge["at"] - w)
		rect.size = Vector2(span, w * 2.0)

	var mat: ShaderMaterial
	if s.material_override != null:
		# 题材化入口：完全交给使用方，不覆盖它的 uniform。
		mat = s.material_override
	else:
		mat = default_material.duplicate() if default_material != null \
				else ShaderMaterial.new()
		if mat.shader == null:
			mat.shader = DEFAULT_SHADER
		mat.set_shader_parameter(&"veil_color", s.color)
		mat.set_shader_parameter(&"axis", float(edge["axis"]))
		mat.set_shader_parameter(&"core", s.core)
		mat.set_shader_parameter(&"feather_min", s.feather_min)
		mat.set_shader_parameter(&"feather_max", s.feather_max)
	rect.material = mat
	add_child(rect)
	_generated.append(rect)
