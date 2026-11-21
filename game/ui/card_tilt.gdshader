shader_type canvas_item;
// 卡牌伪 3D：把整张卡（CardView 自绘的所有图元）绕中心做一次透视倾斜，
// 再叠一道随倾斜角移动的高光；foil > 0 时额外叠一层鎏金反光（金色系的牌）。
// 顶点在本地坐标里变换，所以对 _draw 里画的每个图元都一致。

uniform vec2 card_size = vec2(150.0, 255.0);
// 倾斜：x = 绕竖轴（左右），y = 绕横轴（上下），弧度。
uniform vec2 tilt = vec2(0.0, 0.0);
// 透视强度：越大透视越明显。
uniform float depth = 0.0009;
uniform float sheen = 0.0;
uniform float foil = 0.0;
uniform float time_offset = 0.0;

varying vec2 local_uv;

void vertex() {
	vec2 c = card_size * 0.5;
	vec2 p = VERTEX - c;
	local_uv = VERTEX / card_size;
	// 先绕 y 轴（左右倾），再绕 x 轴（上下倾）
	float z = p.x * sin(tilt.x);
	p.x = p.x * cos(tilt.x);
	float z2 = p.y * sin(tilt.y);
	p.y = p.y * cos(tilt.y);
	z += z2;
	float w = 1.0 + z * depth;
	VERTEX = c + p / max(w, 0.2);
}

void fragment() {
	vec4 col = COLOR;
	// 高光：一条斜向的亮带，位置跟着倾斜方向走
	float band_pos = 0.5 + tilt.x * 1.6 - tilt.y * 1.2;
	float d = (local_uv.x + local_uv.y * 0.6) - band_pos;
	float band = exp(-d * d * 18.0);
	col.rgb += band * sheen * 0.22;
	if (foil > 0.0) {
		// 鎏金：细密的斜纹随时间与倾斜流动，金色只叠在亮处
		float stripes = 0.5 + 0.5 * sin((local_uv.x * 9.0 - local_uv.y * 6.0) * 3.14159 + TIME * 1.2 + time_offset + tilt.x * 8.0);
		float lum = dot(col.rgb, vec3(0.3, 0.59, 0.11));
		vec3 gold = vec3(1.0, 0.82, 0.45);
		col.rgb = mix(col.rgb, col.rgb * gold * 1.25, foil * stripes * 0.35 * smoothstep(0.35, 0.9, lum));
		col.rgb += foil * band * vec3(0.30, 0.22, 0.08);
	}
	COLOR = col;
}
