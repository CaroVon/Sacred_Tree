shader_type spatial;
// 牌桌上的一张牌：一块厚纸板六边形地块的顶面。
// 底色是流派色的纸，中央平印这张牌的纸雕插画（立牌抠图，透明底），外圈一道细框；
// 稀有牌的框是金色，传说牌的金框会缓缓流光。
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D art : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool has_art = true;
// 牌面插画里取样的区域（归一化：x, y, w, h），顶面的方形包围盒映射到这块区域。
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 paper : source_color = vec4(0.93, 0.89, 0.80, 1.0);
uniform vec4 frame : source_color = vec4(0.36, 0.30, 0.24, 1.0);
// 0 = 普通，1 = 稀有（金框），2 = 传说（金框流光）。
uniform int rarity = 0;
// 高亮（悬停 / 可选）与压暗（悬停路径以外）、整体染色（剪枝预览染红）。
uniform float glow = 0.0;
uniform vec4 glow_color : source_color = vec4(0.95, 0.76, 0.40, 1.0);
uniform vec4 modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 season_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// 到六边形边的归一化距离（中心 0，边上 1）：尖顶六边形，外接圆半径由 UV 推回
	vec2 l = (UV - vec2(0.5)) * 2.0;
	float e = max(abs(l.x), max(abs(0.5 * l.x + 0.8660254 * l.y), abs(0.5 * l.x - 0.8660254 * l.y))) / 0.8660254;
	// 纸张：细颗粒 + 纤维 + 中心微亮
	float grain = noise(UV * 140.0) * 0.5 + noise(UV * 37.0) * 0.5;
	vec3 base = paper.rgb * (0.94 + 0.08 * grain) * (1.04 - 0.10 * e * e);
	// 插画
	vec4 a = vec4(0.0);
	if (has_art) {
		a = texture(art, uv_rect.xy + UV * uv_rect.zw);
		// 印在纸上的插画略压暗、提对比，免得在受光面上发白
		a.rgb = pow(a.rgb, vec3(1.25)) * 0.95;
		// 插画只铺在内框以内，往外渐隐到纸色
		a.a *= 1.0 - smoothstep(0.74, 0.80, e);
	}
	vec3 col = mix(base, a.rgb, a.a);
	// 外框：一道墨线 + 稀有度金框
	float ring = smoothstep(0.80, 0.83, e) * (1.0 - smoothstep(0.88, 0.91, e));
	vec3 gold = vec3(0.80, 0.62, 0.30);
	vec3 fc = rarity > 0 ? gold : frame.rgb;
	float sheen = 0.0;
	if (rarity >= 2) {
		float ang = atan(l.y, l.x);
		sheen = pow(0.5 + 0.5 * sin(ang * 2.0 - TIME * 1.6), 8.0);
		fc = mix(gold, vec3(1.0, 0.92, 0.66), sheen);
	}
	col = mix(col, fc, ring * (rarity > 0 ? 0.95 : 0.55));
	float edge = smoothstep(0.95, 1.0, e);
	col *= 1.0 - 0.25 * edge;
	col *= season_tint.rgb * modulate.rgb;
	// 高亮：边缘一圈柔光
	vec3 gl = glow_color.rgb * glow * (0.35 + 0.65 * smoothstep(0.55, 1.0, e));
	ALBEDO = col;
	EMISSION = gl + fc * ring * sheen * 0.6;
	ROUGHNESS = mix(0.82, 0.35, ring * float(rarity > 0));
	METALLIC = ring * float(rarity > 0) * 0.6;
	SPECULAR = 0.3;
}
