@tool
class_name SeamlessRoomParallaxLayer
extends Node2D

## 可选配套：SeamlessRoomParallax 下的一个视差层。
##
## 子节点直接按房间局部像素摆放，和 2D 编辑器里完全一致；运行时只有本节点的
## position 会被容器推动，子节点的相对位置永远不动。
##
## scroll_scale = 1 → 与普通世界物体同速（没有视差）；
## scroll_scale = 0 → 完全钉在屏幕上（最远）。
##
## 编辑器预览同样由容器驱动；本脚本是 @tool，否则编辑器里会被当成占位实例。

@export var scroll_scale := Vector2(0.2, 1.0)
## 位移上限：默认不启用。镜头跨房、房间小于视口时可打开，防止层被拉出构图。
@export var clamp_shift := false
@export var max_shift := Vector2(400.0, 200.0)

## 作者摆放的位置，运行时所有偏移都叠加在它上面。
var _home := Vector2.ZERO
var _home_set := false


func _ready() -> void:
	_capture_home()


## 由 SeamlessRoomParallax 调用；camera_delta = 相机中心 - 房间中心（世界单位）。
func apply_camera_delta(camera_delta: Vector2) -> void:
	# 支持在 _ready 之前先推一次（自检 / 工具脚本），此时现记作者位置。
	_capture_home()
	var shift := (Vector2.ONE - scroll_scale) * camera_delta
	if clamp_shift:
		shift = shift.clamp(-max_shift, max_shift)
	position = _home + shift


func _capture_home() -> void:
	if not _home_set:
		_home = position
		_home_set = true


## 编辑器保存前由容器调用：回到作者摆放的位置。
func reset_to_home() -> void:
	_capture_home()
	position = _home
