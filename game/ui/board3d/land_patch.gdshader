shader_type spatial;
// 特殊地块（沃土 / 岩石 / 泉眼）：一块边缘柔和、带噪声的地貌斑块，没有硬的六边形边。
// 泉眼的纹理会缓慢荡漾。
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float opacity = 0.95;
uniform float ripple = 0.0;
uniform float seed = 0.0;
uniform vec4 season_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 l = (UV - 0.5) * 2.0;
	// 尖顶六边形的归一化距离（四边形 2×2 对应外接圆半径 1，再放大一点让斑块彼此交融）
	float e = max(abs(l.x), max(abs(0.5 * l.x + 0.8660254 * l.y), abs(-0.5 * l.x + 0.8660254 * l.y))) / 0.8660254;
	float n = noise(UV * 5.0 + seed) * 0.28 + noise(UV * 13.0 + seed * 2.0) * 0.12;
	float m = 1.0 - smoothstep(0.62, 0.98, e * 0.92 + n - 0.12);
	vec2 uv = uv_rect.xy + UV * uv_rect.zw;
	if (ripple > 0.0) {
		float d = length(l);
		uv += ripple * 0.012 * vec2(sin(TIME * 1.6 - d * 14.0), cos(TIME * 1.3 - d * 12.0));
	}
	vec4 t = texture(tex, uv);
	ALBEDO = t.rgb * season_tint.rgb;
	ALPHA = m * opacity;
}
