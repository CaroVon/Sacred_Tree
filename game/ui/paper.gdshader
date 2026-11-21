shader_type canvas_item;
// 旧印刷品质感：全屏叠加纸纹、纤维、晕影，以及极轻的套色错位（RGB 通道错开）。
// 混合模式为正片叠底。
render_mode blend_mul, unshaded;

uniform float grain : hint_range(0.0, 0.2) = 0.07;
uniform float fiber : hint_range(0.0, 0.2) = 0.04;
uniform float scale = 1.0;
// 纸面晕影强度。
uniform float vignette : hint_range(0.0, 0.5) = 0.05;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 p = FRAGCOORD.xy / scale;
	float g = hash(floor(p)) - 0.5;
	// 拉长的纤维：在一个方向上低频、另一个方向上高频
	float f = noise(vec2(p.x * 0.02, p.y * 0.6)) * noise(vec2(p.x * 0.6, p.y * 0.03));
	float v = 1.0 - grain * (g + 0.5) * 0.6 - fiber * f;
	// 极淡的大块晕染
	v -= 0.025 * noise(p * 0.004);
	// 纸面晕影：四周压暗，像摊在灯下的旧纸
	vec2 q = UV - vec2(0.5);
	float r = length(q * vec2(1.15, 1.0));
	v -= vignette * smoothstep(0.28, 0.78, r);
	COLOR = vec4(vec3(v), 1.0);
}
