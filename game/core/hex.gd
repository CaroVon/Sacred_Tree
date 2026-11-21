class_name Hex
extends RefCounted
## 六边形轴向坐标工具（参考 Red Blob Games）。
## 方向顺序与网页原型 DIRS 一致：相邻方向依次旋转 60°。

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const SQRT3 := 1.7320508075688772


static func in_board(c: Vector2i, radius: int) -> bool:
	return maxi(maxi(absi(c.x), absi(c.y)), absi(-c.x - c.y)) <= radius


## 与原型 allCells 相同的遍历顺序（q 外层、r 内层）。
static func all_cells(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var c := Vector2i(q, r)
			if in_board(c, radius):
				out.append(c)
	return out


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(c + d)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return maxi(maxi(absi(d.x), absi(d.y)), absi(-d.x - d.y))


## 两个相邻格之间的方向索引，不相邻返回 -1。
static func dir_between(from: Vector2i, to: Vector2i) -> int:
	return DIRS.find(to - from)


## 以原点为中心的点对称（用于“对称”牌型）。
static func mirror(c: Vector2i) -> Vector2i:
	return -c


static func to_pixel(c: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (c.x + c.y / 2.0), size * 1.5 * c.y)


static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - 1.0 / 3.0 * p.y) / size
	var r := (2.0 / 3.0 * p.y) / size
	return cube_round(q, r)


static func cube_round(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var q := roundf(fq)
	var r := roundf(fr)
	var s := roundf(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## 尖顶六边形的六个顶点（与原型 hexPts 相同的角度）。
static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(a), sin(a)) * size)
	return pts
