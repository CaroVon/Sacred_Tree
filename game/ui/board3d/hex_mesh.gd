class_name HexMesh
extends RefCounted
## 程序生成的六棱柱（尖顶六边形，与 Hex.corners 同角度）。
## 两个表面：0 = 顶面（带 UV，可贴图），1 = 侧面。世界坐标里 2D 的 (x, y) 对应 (x, z)。

## 尖顶 = 0，平顶 = 1（大台座用平顶）。
const POINTY := 0
const FLAT := 1


static func _corner(i: int, r: float, orient: int) -> Vector2:
	var a := deg_to_rad(60.0 * i - (30.0 if orient == POINTY else 0.0))
	return Vector2(cos(a), sin(a)) * r


## r：外接圆半径；y0..y1：底和顶的高度；uv：顶面贴图取样的区域（0..1）；
## uv_world：>0 时顶面 UV 按世界坐标平铺（每 uv_world 个单位重复一次），用于大台面。
static func prism(r: float, y0: float, y1: float, uv: Rect2 = Rect2(0, 0, 1, 1), orient: int = POINTY, uv_world: float = 0.0, bevel: float = 0.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# ---- 顶面：中心扇形 ----
	var top := PackedVector3Array()
	var tn := PackedVector3Array()
	var tuv := PackedVector2Array()
	var rt := r - bevel
	for i in 6:
		var a := _corner(i, rt, orient)
		var b := _corner((i + 1) % 6, rt, orient)
		for p: Vector2 in [Vector2.ZERO, a, b]:
			top.append(Vector3(p.x, y1, p.y))
			tn.append(Vector3.UP)
			if uv_world > 0.0:
				tuv.append(p / uv_world + Vector2(0.5, 0.5))
			else:
				var u := p / (2.0 * r) + Vector2(0.5, 0.5)
				tuv.append(uv.position + u * uv.size)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = top
	arr[Mesh.ARRAY_NORMAL] = tn
	arr[Mesh.ARRAY_TEX_UV] = tuv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# ---- 侧面（可带一圈倒角）----
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	var suv := PackedVector2Array()
	for i in 6:
		var a := _corner(i, r, orient)
		var b := _corner((i + 1) % 6, r, orient)
		var mid := (a + b) * 0.5
		var n := Vector3(mid.x, 0, mid.y).normalized()
		var yb := y1 - bevel
		_quad(sv, sn, suv, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, yb, b.y), Vector3(a.x, yb, a.y), n)
		if bevel > 0.0:
			var at := _corner(i, rt, orient)
			var bt := _corner((i + 1) % 6, rt, orient)
			var nb := (n + Vector3.UP).normalized()
			_quad(sv, sn, suv, Vector3(a.x, yb, a.y), Vector3(b.x, yb, b.y), Vector3(bt.x, y1, bt.y), Vector3(at.x, y1, at.y), nb)
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = sv
	arr2[Mesh.ARRAY_NORMAL] = sn
	arr2[Mesh.ARRAY_TEX_UV] = suv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
	return mesh


static func _quad(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nor: Vector3) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		v.append(p)
		n.append(nor)
	for t: Vector2 in [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)]:
		uv.append(t)


## 一条细长的方条（枝干），从 a 到 b，宽 w、高 h，底面贴在 a/b 的 y 上。
static func beam(length: float, w: float, h: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, length)
	return m
