shader_type canvas_item;
// 新手指导的聚光层：全屏压暗，在目标处挖出圆角柔边的洞；洞口一圈金线，外面一圈周期外扩的光环。
// 洞用画布坐标（与 Control 全局坐标一致）传进来：xy = 左上角，zw = 尺寸。

uniform vec2 canvas_size = vec2(1920.0, 1080.0);
uniform vec4 holes[4];
uniform int hole_count = 0;
uniform float dim = 0.55;
uniform vec4 dim_color : source_color = vec4(0.10, 0.09, 0.08, 1.0);
uniform vec4 ring_color : source_color = vec4(0.95, 0.80, 0.45, 1.0);
uniform float pulse = 1.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * canvas_size;
	float d = 1e5;
	for (int i = 0; i < 4; i++) {
		if (i >= hole_count) {
			break;
		}
		vec4 h = holes[i];
		vec2 c = h.xy + h.zw * 0.5;
		float r = min(18.0, min(h.z, h.w) * 0.5);
		d = min(d, sd_round_box(p - c, h.zw * 0.5, r));
	}
	float a = hole_count > 0 ? dim * smoothstep(0.0, 16.0, d) : dim;
	vec3 col = dim_color.rgb;
	if (hole_count > 0) {
		// 洞口金线
		float ring = 1.0 - smoothstep(1.2, 3.2, abs(d - 2.0));
		// 外扩光环：从洞口向外 0→28px，同时淡出
		float t = fract(TIME * 0.8);
		float wave = (1.0 - smoothstep(0.0, 4.0, abs(d - (4.0 + 28.0 * t)))) * (1.0 - t) * pulse;
		float g = max(ring * 0.95, wave * 0.8);
		col = mix(col, ring_color.rgb, g / max(a + g, 0.001));
		a = max(a, g);
	}
	COLOR = vec4(col, a);
}
