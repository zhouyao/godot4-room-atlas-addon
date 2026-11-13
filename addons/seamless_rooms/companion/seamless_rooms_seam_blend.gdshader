shader_type canvas_item;
render_mode blend_premul_alpha;

// 接缝遮罩：UV 中心对齐共享边，中心不透明、两端羽化。
// 预乘契约：COLOR.rgb 必须已乘 COLOR.a，否则边缘会出现灰白边；
// material_override 若替换本 shader，也必须声明同一 render mode。
// 与 SeamlessRoomSeam.feather_alpha() 使用同一条曲线。
uniform vec4 veil_color = vec4(0.02, 0.03, 0.025, 1.0);
uniform float axis = 0.0;          // 0 = UV.x 竖直缝，1 = UV.y 水平缝
uniform float core = 0.12;
uniform float feather_min = 1.0;   // 低侧
uniform float feather_max = 1.0;   // 高侧

void fragment() {
	float u = mix(UV.x, UV.y, axis) * 2.0 - 1.0;
	float a = veil_color.a * pow(1.0 - smoothstep(core, 1.0, abs(u)),
			mix(feather_min, feather_max, step(0.0, u)));
	COLOR = vec4(veil_color.rgb * a, a);
}
