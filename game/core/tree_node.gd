class_name TreeNode
extends RefCounted
## 树上的一个节点（一张牌或树心）。

const SEED := &"seed"

var key: Vector2i
var type: StringName
var parents: Array[Vector2i] = []
var children: Array[Vector2i] = []
## 从父牌长出来的方向（0..5），树心和藤为 -1。
var facing: int = -1
var depth: int = 0
## 放置顺序；父节点一定先于子节点。
var order: int = 0
## 经历过的脉动次数（成熟机制用）。
var age: int = 0
## 年轮印记。
var marks: Array[StringName] = []
## 集市“芽点”服务追加的芽点（绝对方向 0..5）。
var extra_ports: Array[int] = []
## 封印：封存的收获与封存过的脉动次数（季末或提前收获时释放）。
var stored: int = 0
var sealed: int = 0


func is_seed() -> bool:
	return type == SEED


func def() -> CardDef:
	return null if is_seed() else Cards.get_def(type)


## 坚韧：刻了“坚韧”年轮，或牌本身天生坚韧。
func is_tough() -> bool:
	return marks.has(&"tough") or (not is_seed() and def().innate_tough)


func copy() -> TreeNode:
	var n := TreeNode.new()
	n.key = key
	n.type = type
	n.parents = parents.duplicate()
	n.children = children.duplicate()
	n.facing = facing
	n.depth = depth
	n.order = order
	n.age = age
	n.marks = marks.duplicate()
	n.extra_ports = extra_ports.duplicate()
	n.stored = stored
	n.sealed = sealed
	return n


func to_dict() -> Dictionary:
	var ps := []
	for p in parents:
		ps.append([p.x, p.y])
	return {
		"key": [key.x, key.y], "type": String(type), "parents": ps,
		"facing": facing, "depth": depth, "order": order, "age": age,
		"marks": marks.map(func(m): return String(m)),
		"extra_ports": extra_ports.duplicate(),
		"stored": stored, "sealed": sealed,
	}


static func from_dict(d: Dictionary) -> TreeNode:
	var n := TreeNode.new()
	n.key = Vector2i(d.key[0], d.key[1])
	n.type = StringName(d.type)
	for p in d.parents:
		n.parents.append(Vector2i(p[0], p[1]))
	n.facing = int(d.facing)
	n.depth = int(d.depth)
	n.order = int(d.order)
	n.age = int(d.get("age", 0))
	for m in d.get("marks", []):
		n.marks.append(StringName(m))
	for p in d.get("extra_ports", []):
		n.extra_ports.append(int(p))
	n.stored = int(d.get("stored", 0))
	n.sealed = int(d.get("sealed", 0))
	return n
