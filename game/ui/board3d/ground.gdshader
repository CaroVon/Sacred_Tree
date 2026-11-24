shader_type spatial;
// 台面：一块中间调的古石台（让浅色纸牌和奶油色面板都跳出来），向四周淡出到背景里。
// 受光，所以地块、枝干的投影会落在上面；六边形格线是若隐若现的细纹（fwidth 抗锯齿，远处不闪）。
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(0.44, 0.41, 0.35, 1.0);
uniform vec4 line_color : source_color = vec4(0.86, 0.78, 0.62, 1.0);
// 网格半径（格数）。
uniform float radius = 4.0;
// 格线的不透明度（越小越隐约）。
uniform float line_alpha = 0.12;
// 台面本身的不透明度与淡出距离（世界单位）。
uniform float base_alpha = 0.9;
uniform float fade_out = 3.0;
// 季节色调。
uniform vec4 season_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 axial_round(vec2 qr) {
	vec3 c = vec3(qr.x, qr.y, -qr.x - qr.y);
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z) {
		r.x = -r.y - r.z;
	} else if (d.y > d.z) {
		r.y = -r.x - r.z;
	}
	return r.xy;
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = wpos.xz;
	float q = 0.57735027 * p.x - p.y / 3.0;
	float r = 2.0 / 3.0 * p.y;
	vec2 c = axial_round(vec2(q, r));
	vec2 center = vec2(1.7320508 * (c.x + c.y * 0.5), 1.5 * c.y);
	vec2 l = p - center;
	// 到六边形边的归一化距离（中心 0，边上 1）
	float e = max(abs(l.x), max(abs(0.5 * l.x + 0.8660254 * l.y), abs(-0.5 * l.x + 0.8660254 * l.y))) / 0.8660254;
	float hd = max(abs(c.x), max(abs(c.y), abs(-c.x - c.y)));
	float inside = 1.0 - step(radius + 0.5, hd);
	float w = fwidth(e) * 1.5;
	float line = smoothstep(1.0 - w - 0.035, 1.0 - 0.01, e) * inside;
	float dist = length(p);
	float board_r = (radius + 0.6) * 1.7320508;
	float fade = 1.0 - smoothstep(board_r - 1.0, board_r + fade_out, dist);
	// 石面：低频斑驳 + 细颗粒；中间被光照得更亮，边缘渐暗
	float stone = fbm(p * 0.9) * 0.6 + noise(p * 9.0) * 0.4;
	vec3 base = tint.rgb * (0.86 + 0.24 * stone);
	base *= mix(0.78, 1.12, 1.0 - clamp(dist / (board_r + 1.0), 0.0, 1.0));
	base *= season_tint.rgb;
	ALBEDO = mix(base, line_color.rgb, line * line_alpha);
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	ALPHA = clamp(base_alpha * fade, 0.0, 1.0);
}
