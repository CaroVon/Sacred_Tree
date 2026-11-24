class_name TubeMesh
extends RefCounted
## 程序生成的平滑管子（枝干、藤）：沿一条在 YZ 平面里拱起的二次曲线，从 z=0 伸到 z=-length，
## 半径从 r0 渐变到 r1。带法线与沿管长的 UV（树皮纹理沿枝条方向）。


static func arch(length: float, r0: float, r1: float, rise: float, segs: int = 12, sides: int = 10) -> ArrayMesh:
	var p0 := Vector3(0, 0, 0)
	var p1 := Vector3(0, rise, -length * 0.5)
	var p2 := Vector3(0, 0, -length)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var t := float(i) / segs
		var u := 1.0 - t
		var pos := p0 * u * u + p1 * 2.0 * u * t + p2 * t * t
		var tan := ((p1 - p0) * 2.0 * u + (p2 - p1) * 2.0 * t).normalized()
		var side := Vector3.RIGHT
		var up := tan.cross(side).normalized() * -1.0
		# 两端略微收拢再展开，像枝节
		var r := lerpf(r0, r1, t) * (1.0 + 0.08 * sin(t * PI * 3.0))
		for j in sides + 1:
			var a := TAU * float(j) / sides
			var n := (side * cos(a) + up * sin(a)).normalized()
			verts.append(pos + n * r)
			norms.append(n)
			uvs.append(Vector2(float(j) / sides, t * length * 2.0))
	for i in segs:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
