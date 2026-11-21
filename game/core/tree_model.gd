class_name TreeModel
extends RefCounted
## 牌桌状态：格子 → 节点。字典保持插入顺序，与原型 Map 的遍历顺序一致。

const SEED_KEY := Vector2i.ZERO

var radius: int = 4
var nodes: Dictionary = {}  # Vector2i -> TreeNode
var next_order: int = 0
var land: Dictionary = {}   # Vector2i -> Land.Type（缺省为平地）


static func create(board_radius: int = 4) -> TreeModel:
	var t := TreeModel.new()
	t.radius = board_radius
	var s := TreeNode.new()
	s.key = SEED_KEY
	s.type = TreeNode.SEED
	s.order = t.next_order
	t.next_order += 1
	t.nodes[SEED_KEY] = s
	return t


func at(k: Vector2i) -> TreeNode:
	return nodes.get(k)


func land_at(k: Vector2i) -> int:
	return land.get(k, Land.Type.PLAIN)


func has(k: Vector2i) -> bool:
	return nodes.has(k)


func size() -> int:
	return nodes.size()


func sorted() -> Array[TreeNode]:
	var list: Array[TreeNode] = []
	for n in nodes.values():
		list.append(n)
	list.sort_custom(func(a: TreeNode, b: TreeNode): return a.order < b.order)
	return list


func tips() -> Array[TreeNode]:
	var out: Array[TreeNode] = []
	for n in sorted():
		if n.children.is_empty():
			out.append(n)
	return out


func copy() -> TreeModel:
	var t := TreeModel.new()
	t.radius = radius
	t.next_order = next_order
	t.land = land.duplicate()
	for k in nodes:
		t.nodes[k] = nodes[k].copy()
	return t


func to_dict() -> Dictionary:
	var list := []
	for n in nodes.values():
		list.append(n.to_dict())
	var ld := []
	for k in land:
		ld.append([k.x, k.y, land[k]])
	return {"radius": radius, "next_order": next_order, "nodes": list, "land": ld}


static func from_dict(d: Dictionary) -> TreeModel:
	var t := TreeModel.new()
	t.radius = int(d.radius)
	t.next_order = int(d.next_order)
	for l in d.get("land", []):
		t.land[Vector2i(int(l[0]), int(l[1]))] = int(l[2])
	for nd in d.nodes:
		var n := TreeNode.from_dict(nd)
		t.nodes[n.key] = n
	# children 由 parents 重建，保证一致
	for n in t.nodes.values():
		for p in n.parents:
			t.nodes[p].children.append(n.key)
	return t
