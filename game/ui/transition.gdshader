shader_type canvas_item;
// 转场：纸色从画面中心像墨一样晕开（边缘带噪声和一圈深色墨边），盖满后换场景，再晕散。
// progress 0 = 完全透明，1 = 盖满。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 paper : source_color = vec4(0.93, 0.89, 0.79, 1.0);
uniform vec4 ink : source_color = vec4(0.17, 0.16, 0.15, 1.0);
uniform vec2 aspect = vec2(1.7778, 1.0);
uniform float seed = 0.0;

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
	vec2 p = (UV - 0.5) * aspect;
	float d = length(p);
	float n = noise(UV * 5.0 + seed) * 0.22 + noise(UV * 17.0 + seed) * 0.07;
	// 盖满需要半径超过对角线（约 1.02），再加噪声余量
	float edge = progress * 1.45;
	float v = edge - (d + n);
	float cover = smoothstep(0.0, 0.025, v);
	float rim = smoothstep(0.0, 0.02, v) * (1.0 - smoothstep(0.02, 0.07, v));
	vec3 c = mix(paper.rgb, ink.rgb, rim * 0.85);
	COLOR = vec4(c, cover);
}
