shader_type spatial;
// 虚拟台面：一片向四周淡出的光，六边形格线只是若隐若现的细纹。
// 透明但受光，所以立牌和枝条的投影会落在上面。
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 tint : source_color = vec4(0.91, 0.87, 0.78, 1.0);
uniform vec4 line_color : source_color = vec4(0.62, 0.53, 0.40, 1.0);
// 网格半径（格数）。
uniform float radius = 4.0;
// 格线的不透明度（越小越隐约）。
uniform float line_alpha = 0.10;
// 台面本身的不透明度与淡出距离（世界单位）。
uniform float base_alpha = 0.93;
uniform float fade_out = 6.5;
// 季节色调（阶段 3：由牌桌按季节设置）。
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
	float line = smoothstep(0.92, 0.995, e) * inside;
	float dist = length(p);
	float board_r = (radius + 0.6) * 1.7320508;
	float fade = 1.0 - smoothstep(board_r - 1.5, board_r + fade_out, dist);
	// 中间更亮一点，像一束光照在桌面上
	vec3 base = mix(tint.rgb, tint.rgb * 1.06, 1.0 - clamp(dist / board_r, 0.0, 1.0));
	base *= season_tint.rgb;
	ALBEDO = mix(base, line_color.rgb, line * 0.45);
	ALPHA = clamp(base_alpha * fade + line * line_alpha * fade, 0.0, 1.0);
}
