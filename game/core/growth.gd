class_name Growth
extends RefCounted
## 生长：可放置位置计算、放置、修剪。纯函数，直接修改传入的 TreeModel。

const SEED_PORTS: Array[int] = [1, 3, 5]


class Target:
	extends RefCounted
	var parents: Array[Vector2i] = []
	var facing: int = -1
	var score: int = 0


static func ports_of(n: TreeNode, ctx: Pulse.Context = null) -> Array[int]:
	var out: Array[int] = []
	if n.is_seed():
		out = SEED_PORTS.duplicate()
		if ctx and ctx.seed_extra_port:
			out.append(0)
		return out
	var base := n.facing if n.facing >= 0 else 0
	for p in n.def().ports:
		out.append((base + p + 6) % 6)
	for d in n.extra_ports:
		if not out.has(d):
			out.append(d)
	return out


## 芽点服务可以加的方向：这张牌还没有芽点、且不是它来的方向。
static func free_port_dirs(n: TreeNode) -> Array[int]:
	var out: Array[int] = []
	if n == null or n.is_seed():
		return out
	var have := ports_of(n)
	for d in 6:
		if have.has(d):
			continue
		var c := n.key + Hex.DIRS[d]
		if n.parents.has(c):
			continue
		out.append(d)
	return out


static func can_grow_on(tree: TreeModel, c: Vector2i) -> bool:
	return Hex.in_board(c, tree.radius) and not tree.has(c) and not Land.blocks_growth(tree.land_at(c))


## 某种牌可以放的位置：Vector2i -> Target。
## 同一格可由多个芽点到达时，选择流出养分最高的父牌（与原型一致）。
static func targets_for(tree: TreeModel, type: StringName, ctx: Pulse.Context) -> Dictionary:
	var res := {}
	var pulse := Pulse.resolve(tree, ctx)
	var def := Cards.get_def(type)
	if def.is_graft():
		for c in Hex.all_cells(tree.radius):
			if not can_grow_on(tree, c):
				continue
			var ps: Array[Vector2i] = []
			for nb in Hex.neighbors(c):
				if graft_parent_ok(tree, def, nb, pulse):
					ps.append(nb)
			if ps.size() >= def.graft_min:
				var t := Target.new()
				t.parents = ps
				res[c] = t
	else:
		for n: TreeNode in tree.nodes.values():
			if def.min_depth > 0 and n.depth + 1 < def.min_depth:
				continue
			for d in ports_of(n, ctx):
				var c: Vector2i = n.key + Hex.DIRS[d]
				if not can_grow_on(tree, c):
					continue
				var sc: int = pulse.out[n.key]
				var cur: Target = res.get(c)
				if cur == null or sc > cur.score:
					var t := Target.new()
					t.parents = [n.key]
					t.facing = d
					t.score = sc
					res[c] = t
	return res


static func place(tree: TreeModel, type: StringName, k: Vector2i, info: Target) -> TreeNode:
	var depth := 0
	for p in info.parents:
		depth = maxi(depth, tree.at(p).depth)
	var n := TreeNode.new()
	n.key = k
	n.type = type
	n.parents = info.parents.duplicate()
	n.facing = info.facing
	n.depth = depth + 1
	n.order = tree.next_order
	tree.next_order += 1
	tree.nodes[k] = n
	for p in info.parents:
		tree.at(p).children.append(k)
	return n


## 一张牌和它后面的所有枝（含嫁接后的汇合点）。
static func subtree(tree: TreeModel, k: Vector2i) -> Dictionary:
	var seen := {}
	var stack: Array[Vector2i] = [k]
	while not stack.is_empty():
		var x: Vector2i = stack.pop_back()
		if seen.has(x):
			continue
		seen[x] = true
		for c in tree.at(x).children:
			stack.append(c)
	return seen


static func remove_set(tree: TreeModel, set: Dictionary) -> void:
	for x in set:
		tree.nodes.erase(x)
	for n: TreeNode in tree.nodes.values():
		n.children.assign(n.children.filter(func(c): return not set.has(c)))


## 修剪带来的养分（不修改树）。per_card_extra 为器物“堆肥桶”的额外收益。
static func prune_gain(tree: TreeModel, set: Dictionary, per_card_extra: int = 0) -> int:
	var gain := 0
	for x in set:
		var g := tree.at(x).def().prune_value + per_card_extra
		if tree.at(x).marks.has(&"gilded"):
			g *= 2
		gain += g
	return gain


## 修剪后下次脉动所有末梢的加成（落叶）。
static func prune_tip_bonus(tree: TreeModel, set: Dictionary) -> int:
	var b := 0
	for x in set:
		b += tree.at(x).def().prune_tip_bonus
	return b


# ---------- 移栽 ----------

## 一次移栽：根牌的新位置与父牌，以及子枝每个格子的新位置。
class Move:
	extends RefCounted
	var target: Target
	var rot: int = 0
	var map: Dictionary = {}  # 旧格 -> 新格


## 六边形绕原点旋转 r 个 60°（DIRS[i] → DIRS[i+r]）。
static func rotate(c: Vector2i, r: int) -> Vector2i:
	var v := c
	for i in posmod(r, 6):
		v = Vector2i(v.x + v.y, -v.x)
	return v


## 把 k 连同它的子枝整体挪到别处的可选落点：新格 -> Move。
## 子枝保持形状随新朝向旋转；藤不能作为根，子枝里的藤必须所有父牌都在子枝内。
static func transplant_targets(tree: TreeModel, k: Vector2i, ctx: Pulse.Context) -> Dictionary:
	var res := {}
	var root := tree.at(k)
	if root == null or root.is_seed() or root.def().is_graft() or root.facing < 0:
		return res
	var set := subtree(tree, k)
	for x in set:
		if x == k:
			continue
		for p in tree.at(x).parents:
			if not set.has(p):
				return res
	var rest := tree.copy()
	remove_set(rest, set)
	var tg := targets_for(rest, root.type, ctx)
	for c in tg:
		var t: Target = tg[c]
		if c == k and t.facing == root.facing:
			continue
		var mv := Move.new()
		mv.target = t
		mv.rot = t.facing - root.facing
		var new_root_depth := 0
		for p in t.parents:
			new_root_depth = maxi(new_root_depth, rest.at(p).depth + 1)
		var dd := new_root_depth - root.depth
		var ok := true
		for x in set:
			var nc: Vector2i = c + rotate(x - k, mv.rot)
			var md := tree.at(x).def().min_depth
			if not can_grow_on(rest, nc) or (md > 0 and tree.at(x).depth + dd < md):
				ok = false
				break
			mv.map[x] = nc
		if ok:
			res[c] = mv
	return res


## 执行移栽（直接修改 tree）。成熟度、印记保留；放置顺序挪到最后（父牌先于子牌）。
static func transplant(tree: TreeModel, k: Vector2i, mv: Move) -> void:
	var set := subtree(tree, k)
	var moving: Array[TreeNode] = []
	for x in set:
		moving.append(tree.at(x))
	moving.sort_custom(func(a: TreeNode, b: TreeNode): return a.order < b.order)
	remove_set(tree, set)
	for n in moving:
		var old: Vector2i = n.key
		n.key = mv.map[old]
		if old == k:
			n.parents = mv.target.parents.duplicate()
		else:
			n.parents.assign(n.parents.map(func(p): return mv.map[p]))
		n.children.assign(n.children.map(func(c): return mv.map[c]))
		if n.facing >= 0:
			n.facing = posmod(n.facing + mv.rot, 6)
		n.extra_ports.assign(n.extra_ports.map(func(d): return posmod(d + mv.rot, 6)))
		var depth := 0
		for p in n.parents:
			depth = maxi(depth, tree.at(p).depth)
		n.depth = depth + 1
		n.order = tree.next_order
		tree.next_order += 1
		tree.nodes[n.key] = n
	for p in mv.target.parents:
		tree.at(p).children.append(mv.map[k])


# ---------- 解释 ----------

## 每张牌的每个芽点及状态：open 可用 / occupied 已被占 / offboard 出界 / rock 岩石 / spring 泉眼。
## 返回 [{from, dir, cell, status}]
static func bud_report(tree: TreeModel, ctx: Pulse.Context = null) -> Array:
	var out := []
	for n: TreeNode in tree.nodes.values():
		for d in ports_of(n, ctx):
			var c: Vector2i = n.key + Hex.DIRS[d]
			var st := &"open"
			if not Hex.in_board(c, tree.radius):
				st = &"offboard"
			elif tree.has(c):
				st = &"occupied"
			elif tree.land_at(c) == Land.Type.ROCK:
				st = &"rock"
			elif tree.land_at(c) == Land.Type.SPRING:
				st = &"spring"
			out.append({"from": n.key, "dir": d, "cell": c, "status": st})
	return out


static func open_bud_count(tree: TreeModel, ctx: Pulse.Context = null) -> int:
	var seen := {}
	for b in bud_report(tree, ctx):
		if b.status == &"open":
			seen[b.cell] = true
	return seen.size()


static func _nm(n: TreeNode) -> String:
	return "树心" if n.is_seed() else n.def().display_name


## 嫁接牌能否以 nb 为父牌：普通藤要求末梢；带 graft_family 的（枢纽）要求是该流派的牌。
static func graft_parent_ok(tree: TreeModel, def: CardDef, nb: Vector2i, pulse: Pulse.Result) -> bool:
	if def.graft_family != &"":
		var m := tree.at(nb)
		return m != null and not m.is_seed() and m.def().has_family(def.graft_family)
	return pulse.tips.has(nb)


## 某格为什么不能放这张牌；能放返回空字符串。
static func why_not(tree: TreeModel, type: StringName, c: Vector2i, ctx: Pulse.Context) -> String:
	var def := Cards.get_def(type)
	if not Hex.in_board(c, tree.radius):
		return "这里在牌桌外。"
	if tree.has(c):
		return "这里已经长了%s。" % _nm(tree.at(c))
	match tree.land_at(c):
		Land.Type.ROCK:
			return "岩石上无法生长（可以在集市清除岩石）。"
		Land.Type.SPRING:
			return "泉眼上无法生长，但它会给相邻的末梢 +%d。" % Land.SPRING_BONUS
	if def.is_graft():
		var pr := Pulse.resolve(tree, ctx)
		var n := 0
		for nb in Hex.neighbors(c):
			if graft_parent_ok(tree, def, nb, pr):
				n += 1
		if n < def.graft_min:
			var what := ("%s牌" % CardDef.FAMILY_NAMES.get(def.graft_family, "")) if def.graft_family != &"" else "末梢"
			return "%s要放在同时挨着 %d 个以上%s的空格上，这里只挨着 %d 个。" % [def.display_name, def.graft_min, what, n]
		return ""
	var pointing: Array[TreeNode] = []
	for n: TreeNode in tree.nodes.values():
		for d in ports_of(n, ctx):
			if n.key + Hex.DIRS[d] == c:
				pointing.append(n)
	if pointing.is_empty():
		var near: Array[String] = []
		var ends: Array[String] = []
		for nb in Hex.neighbors(c):
			var m := tree.at(nb)
			if m == null:
				continue
			if not m.is_seed() and m.def().ports.is_empty() and m.extra_ports.is_empty():
				ends.append(m.def().display_name)
			else:
				near.append(_nm(m))
		if near.is_empty() and ends.is_empty():
			return "这里离树太远：新牌只能接在已有牌的空芽点上（粉色短线）。"
		if near.is_empty():
			return "旁边的%s是末端牌，没有芽点，不能在它后面继续生长。" % "、".join(ends)
		return "旁边的%s没有芽点朝向这里——芽点跟着牌的朝向转，看牌上伸出的粉色短线。" % "、".join(near)
	if def.min_depth > 0:
		var best := 0
		for n in pointing:
			best = maxi(best, n.depth + 1)
		if best < def.min_depth:
			return "%s只能接在深度 ≥%d 的位置，这里深度是 %d（树心算 0，每接一张 +1）。" % [def.display_name, def.min_depth, best]
	return ""


## 手里这张牌为什么一个位置都没有。
static func hand_reason(tree: TreeModel, type: StringName, ctx: Pulse.Context) -> String:
	var def := Cards.get_def(type)
	if def.is_graft():
		if def.graft_family != &"":
			return "没有同时挨着 %d 张%s牌的空格" % [def.graft_min, CardDef.FAMILY_NAMES.get(def.graft_family, "")]
		return "没有同时挨着 %d 个末梢的空格" % def.graft_min
	if open_bud_count(tree, ctx) == 0:
		return "芽点全被占了，修剪可腾出空间"
	if def.min_depth > 0:
		return "需要深度 ≥%d 的空芽点" % def.min_depth
	return "没有可放的位置"
