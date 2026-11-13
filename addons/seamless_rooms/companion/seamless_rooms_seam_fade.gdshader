shader_type canvas_item;

// 背景层边缘渐隐（FADE 模式）：在共享边附近把背景 Sprite 的 alpha 衰减到 0，
// 露出房间自己的实心底色，因此不需要额外遮罩层与 z band 约定。
// 由 SeamlessRoomParallax 通过 use_parent_material 批量应用到背景 band。
// 与 OVERLAY 遮罩共用同一条羽化曲线（core / feather 语义一致）。
uniform int seam_count = 0;
uniform vec4 seam_a = vec4(0.0);   // x=at, y=axis, z=half_width, w=side
uniform vec4 seam_b = vec4(0.0);
uniform float core_a = 0.12;
uniform float core_b = 0.12;
uniform float feather_a = 1.0;
uniform float feather_b = 1.0;
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float edge_alpha(vec4 s, float p_core, float feather) {
	float p = mix(world_pos.x, world_pos.y, s.y);
	float d = s.w * (s.x - p) / max(s.z, 1.0);
	float t = clamp((d - p_core) / max(1.0 - p_core, 0.0001), 0.0, 1.0);
	float st = t * t * (3.0 - 2.0 * t);
	return pow(st, max(feather, 0.0001));
}

void fragment() {
	float a = 1.0;
	if (seam_count > 0) {
		a *= edge_alpha(seam_a, core_a, feather_a);
	}
	if (seam_count > 1) {
		a *= edge_alpha(seam_b, core_b, feather_b);
	}
	COLOR.a *= a;
}
