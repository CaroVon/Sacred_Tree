class_name PrintStyle
extends RefCounted
## 版画绘制工具箱：套色错位、网点半调、木刻排线、手绘抖动轮廓、裁切标记。
## 全部是静态函数，直接在任意 Control 的 _draw 里用。

## 稳定的伪随机（同 seed 永远同结果），用于手绘抖动。
static func _rand(seed_val: int, i: int) -> float:
	var x := (seed_val * 374761393 + i * 668265263) & 0x7FFFFFFF
	x = (x ^ (x >> 13)) * 1274126177
	x = x & 0x7FFFFFFF
	return float(x % 100000) / 100000.0 - 0.5


## 手绘抖动：把折线每条边细分并随机偏移，得到「手刻」的毛边轮廓。
static func rough_points(pts: PackedVector2Array, jitter: float, seed_val: int, per_edge: int = 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n == 0:
		return out
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		for k in per_edge:
			var t := float(k) / float(per_edge)
			var p := a.lerp(b, t)
			var r := _rand(seed_val, i * 97 + k)
			var r2 := _rand(seed_val, i * 97 + k + 5000)
			p += Vector2(r, r2) * jitter * 2.0
			out.append(p)
	return out


## 手绘多边形（实心 + 可选描边）。
static func rough_polygon(ci: CanvasItem, pts: PackedVector2Array, fill: Color, line: Color = Color.TRANSPARENT, lw: float = 0.0, jitter: float = 0.0, seed_val: int = 1) -> void:
	var p := rough_points(pts, jitter, seed_val) if jitter > 0.0 else pts
	if fill.a > 0.0:
		ci.draw_colored_polygon(p, fill)
	if line.a > 0.0 and lw > 0.0:
		var q := p
		q.append(p[0])
		ci.draw_polyline(q, line, lw, true)


## 网点半调：菱形网格排点，模拟旧印刷的网点。
static func halftone(ci: CanvasItem, rect: Rect2, color: Color, spacing: float = 6.0, radius: float = 1.6, angle_deg: float = 45.0) -> void:
	var a := deg_to_rad(angle_deg)
	var ca := cos(a)
	var sa := sin(a)
	var diag := rect.size.length()
	var steps := int(diag / spacing) + 2
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var lx := float(i) * spacing
			var ly := float(j) * spacing
			var p := rect.position + Vector2(
				lx * ca - ly * sa + diag * 0.5,
				lx * sa + ly * ca + diag * 0.5)
			if not rect.has_point(p):
				continue
			ci.draw_circle(p, radius, color)


## 木刻排线：一组平行短线，角度任意。
static func hatch(ci: CanvasItem, rect: Rect2, color: Color, angle_deg: float = 45.0, spacing: float = 5.0, width: float = 1.0, length_ratio: float = 0.8) -> void:
	var a := deg_to_rad(angle_deg)
	var dir := Vector2(cos(a), sin(a))
	var nrm := Vector2(-sin(a), cos(a))
	var diag := rect.size.length()
	var steps := int(diag / spacing) + 2
	var c := rect.position + rect.size * 0.5
	for i in range(-steps, steps + 1):
		var off := float(i) * spacing
		var half := diag * 0.5 * length_ratio
		var p0 := c + nrm * off - dir * half
		var p1 := c + nrm * off + dir * half
		# 只画落在矩形里的那一段
		var a0 := _clip_to_rect(p0, dir, rect)
		var a1 := _clip_to_rect(p1, dir, rect)
		if a0 == Vector2(INF, INF) or a1 == Vector2(INF, INF):
			continue
		ci.draw_line(a0, a1, color, width, true)


## 沿一条方向把点裁到矩形内；不在矩形内返回 Vector2.INF。
static func _clip_to_rect(p: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var t0 := 0.0
	var t1 := 1e9
	for axis in 2:
		var o := p[axis]
		var d := dir[axis]
		var lo := rect.position[axis]
		var hi := rect.position[axis] + rect.size[axis]
		if absf(d) < 0.0001:
			if o < lo or o > hi:
				return Vector2(INF, INF)
			continue
		var ta := (lo - o) / d
		var tb := (hi - o) / d
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return Vector2(INF, INF)
	return p + dir * t0


## 裁切十字：印张四角的对位标记。
static func crop_marks(ci: CanvasItem, rect: Rect2, color: Color, length: float = 12.0, width: float = 1.0) -> void:
	var corners := [
		[rect.position, Vector2(1, 0), Vector2(0, 1)],
		[Vector2(rect.position.x + rect.size.x, rect.position.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(rect.position.x, rect.position.y + rect.size.y), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Vector2(-1, 0), Vector2(0, -1)],
	]
	for c in corners:
		var p: Vector2 = c[0]
		var d1: Vector2 = c[1]
		var d2: Vector2 = c[2]
		ci.draw_line(p, p + d1 * length, color, width, true)
		ci.draw_line(p, p + d2 * length, color, width, true)


## 套色错位的第二版轮廓：把形状往右下偏移一点，用淡色画一遍。
static func plate_offset_poly(ci: CanvasItem, pts: PackedVector2Array, color: Color, offset: Vector2, width: float = 3.0) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(v + offset)
	p.append(p[0])
	ci.draw_polyline(p, color, width, true)


## 树皮短排线：沿一段枝干画木刻纹理。
static func bark_hatch(ci: CanvasItem, a: Vector2, b: Vector2, width: float, color: Color, seed_val: int = 0) -> void:
	var dir := (b - a)
	var len := dir.length()
	if len < 1.0:
		return
	dir /= len
	var nrm := Vector2(-dir.y, dir.x)
	var count := maxi(1, int(len / 5.0))
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var p := a.lerp(b, t)
		var r := _rand(seed_val, i)
		var w := width * (0.5 + r * 0.4)
		var off := nrm * (width * 0.22) * (1 if i % 2 == 0 else -1)
		ci.draw_line(p + off - dir * w * 0.5, p + off + dir * w * 0.5, color, 1.0, true)


## 圆环（年轮 / 水纹）。
static func ring(ci: CanvasItem, c: Vector2, radius: float, color: Color, width: float = 1.5, segments: int = 28) -> void:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	ci.draw_polyline(pts, color, width, true)


## 一枚印章（双线方框 + 文字），以当前变换的原点为中心。
## 想要倾斜的效果，由调用方用 draw_set_transform_matrix 组合好变换再调用。
static func stamp(ci: CanvasItem, font: Font, text: String, color: Color, fs: int = 16, pad: float = 6.0) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var w := sz.x + pad * 2.0
	var h := sz.y + pad * 1.2
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)
	var prev := Color(color, 0.82)
	ci.draw_rect(r, prev, false, maxf(1.5, 2.0 * fs / 16.0))
	ci.draw_string(font, Vector2(-sz.x * 0.5, sz.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, prev)


## 虚线方框（焦点框）。
static func dashed_rect(ci: CanvasItem, rect: Rect2, color: Color, width: float = 2.0, dash: float = 6.0) -> void:
	var corners := [rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x, rect.position.y + rect.size.y)]
	for i in 4:
		ci.draw_dashed_line(corners[i], corners[(i + 1) % 4], color, width, dash)


## 压印凹槽：内凹的双线 + 四角定位角标。
static func emboss_slot(ci: CanvasItem, center: Vector2, radius: float, color: Color, accent: Color, phase: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	# 外圈暗线
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(center + (p - center) * 1.0)
	outer.append(outer[0])
	ci.draw_polyline(outer, Color(color, 0.55), 1.6, true)
	# 内圈亮线（错位一像素，像压凹）
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(center + (p - center) * 0.86)
	inner.append(inner[0])
	ci.draw_polyline(inner, Color(accent, 0.35 + 0.25 * sin(phase)), 1.4, true)
	# 四角定位角标
	for i in 6:
		var p := pts[i]
		var d := (p - center).normalized()
		var t := Vector2(-d.y, d.x)
		ci.draw_line(p - d * 5.0, p, Color(accent, 0.8), 1.4, true)
		ci.draw_line(p, p + t * 4.0, Color(accent, 0.8), 1.4, true)
