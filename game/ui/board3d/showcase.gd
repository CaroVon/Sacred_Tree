class_name Showcase
extends RefCounted
## 展示用的神树：主菜单等处让一棵树在 3D 牌桌上逐枚长出来。
## 树由一局临时的 RunState 按贪心策略长几个回合得到（只调用规则层，不改它）。


## 用种子 run_seed 长 turns 个回合，返回那棵树（以及那一局，方便取脉动结果）。
static func grow(run_seed: int, turns: int) -> RunState:
	var s := RunState.create(run_seed)
	for t in turns:
		while s.plays > 0:
			var best := -1
			var bi := -1
			var bk := Vector2i.ZERO
			for i in s.hand.size():
				for k in s.targets_for_hand(i):
					var v := s.preview_place(i, k)
					if v > best:
						best = v
						bi = i
						bk = k
			if bi < 0:
				break
			s.place(bi, bk)
		if s.phase != RunState.Phase.PLAY:
			break
		s.end_turn()
		if s.phase != RunState.Phase.PLAY:
			break
	return s


## 只保留放置顺序 ≤ upto 的牌（树心总在），子枝引用一并裁掉。
static func partial(t: TreeModel, upto: int) -> TreeModel:
	var c := t.copy()
	for k in c.nodes.keys():
		var n: TreeNode = c.nodes[k]
		if not n.is_seed() and n.order > upto:
			c.nodes.erase(k)
	for n: TreeNode in c.nodes.values():
		var kept: Array[Vector2i] = []
		for ch in n.children:
			if c.nodes.has(ch):
				kept.append(ch)
		n.children = kept
	return c


## 按放置顺序排好的非树心牌。
static func order_of(t: TreeModel) -> Array[TreeNode]:
	var list: Array[TreeNode] = []
	for n: TreeNode in t.nodes.values():
		if not n.is_seed():
			list.append(n)
	list.sort_custom(func(a, b): return a.order < b.order)
	return list
