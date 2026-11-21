class_name CardDemo
extends RefCounted
## 图鉴用：为每张牌搭一棵最小示例树，并根据牌的数据自动生成规则说明（避免说明和数据不一致）。

const UP := 1   # 示例树统一向右上方生长（方向 1）

const PORT_NAMES := {0: "正前方", 1: "左前方", -1: "右前方", 2: "左后方", -2: "右后方", 3: "正后方"}
const CATEGORY_HELP := [
	"传导牌接在枝干中间，把流过的养分加工后继续往后传。",
	"分枝牌有多个芽点，养分流到这里会复制成多份，每份各自往后流——路径越多，末梢越多。",
	"末端牌没有芽点，后面不能再接牌，天然就是末梢，负责在终点放大收获。",
	"相邻牌不通过枝干传递养分，而是给挨着它的格子加成。",
	"嫁接牌放在同时挨着几个末梢的空格上，把它们都当作父牌，几股养分在这里汇合。",
	"时间牌的效果会随着它经历的脉动次数变化。",
	"修剪牌本身不强，但剪掉时能换到养分或其他好处。",
]


static func _put(t: TreeModel, type: StringName, parent: Vector2i, dir: int) -> TreeNode:
	var info := Growth.Target.new()
	info.parents = [parent]
	info.facing = dir
	return Growth.place(t, type, parent + Hex.DIRS[dir], info)


static func _graft(t: TreeModel, type: StringName, at: Vector2i, parents: Array[Vector2i]) -> TreeNode:
	var info := Growth.Target.new()
	info.parents = parents
	return Growth.place(t, type, at, info)


## 返回 {tree, focus, note}。compare 为真时把本牌换成茎（嫁接牌则去掉），用来对比。
static func build(id: StringName, age: int = 0, compare: bool = false) -> Dictionary:
	var def := Cards.get_def(id)
	var t := TreeModel.create(Rules.RADIUS)
	var me := &"stem" if compare else id
	var focus := Vector2i.ZERO
	var note := ""
	var root := Vector2i.ZERO
	match def.category:
		CardDef.Category.GRAFT:
			var s1 := _put(t, &"stem", root, UP)
			var f := _put(t, &"fork", s1.key, UP)
			var a := _put(t, &"fruit", f.key, 0)
			var b := _put(t, &"fruit", f.key, 2)
			focus = f.key + Hex.DIRS[1]  # 同时挨着两个果的格子
			if not compare:
				_graft(t, id, focus, [a.key, b.key] as Array[Vector2i])
			else:
				focus = a.key
			note = "分叉把养分复制成两份，两个果是末梢；%s挨着它们，把两股养分汇合。" % def.display_name
		CardDef.Category.AURA when def.aura > 0:
			var s1 := _put(t, &"stem", root, UP)
			var tri := _put(t, &"tri", s1.key, UP)
			_put(t, &"fruit", tri.key, 0)
			var mid := _put(t, me, tri.key, 1)
			_put(t, &"fruit", tri.key, 2)
			focus = mid.key
			note = "%s挨着两个果（都是末梢），给它们各加成。" % def.display_name
		CardDef.Category.AURA when def.aura_conduct > 0:
			var side := _put(t, &"side", root, UP)
			var st := _put(t, &"stem", side.key, UP)
			_put(t, &"fruit", st.key, UP)
			var m := _put(t, me, side.key, 2)
			focus = m.key
			note = "%s挨着一根茎（传导牌），让茎流出的养分变多。" % def.display_name
		_:
			var prev := _put(t, &"stem", root, UP)
			if def.min_depth > 1:
				for i in def.min_depth - 2:
					prev = _put(t, &"stem", prev.key, UP)
			var mine := _put(t, me, prev.key, UP)
			focus = mine.key
			if not def.is_end():
				var ports: Array[int] = []
				for p in def.ports:
					ports.append(p)
				if compare:
					ports = [0]
				for p in ports:
					var d := (UP + p + 6) % 6
					var nxt := mine.key + Hex.DIRS[d]
					if Hex.in_board(nxt, t.radius):
						_put(t, &"fruit" if def.category != CardDef.Category.BRANCH else &"stem", mine.key, d)
				if def.category == CardDef.Category.BRANCH:
					note = "%s的每个芽点后面各接了一根茎：养分在这里复制，变成 %d 条路径。" % [def.display_name, ports.size()]
				else:
					note = "养分从树心经过茎流到%s，再流进后面的果。" % def.display_name
			else:
				note = "%s接在茎后面，自己就是末梢。" % def.display_name
	for n: TreeNode in t.nodes.values():
		n.age = age
	return {"tree": t, "focus": focus, "note": note}


static func ctx() -> Pulse.Context:
	var c := Pulse.Context.for_season(1)
	c.patterns = false
	c.explain = true
	return c


## 根据牌的字段生成完整规则说明。
static func rules_text(def: CardDef) -> String:
	var lines: Array[String] = []
	lines.append("【类别】%s——%s" % [def.category_name(), CATEGORY_HELP[def.category]])
	if def.is_graft():
		lines.append("【放置】放在同时挨着 %d 个以上末梢的空格上（不需要芽点）。被它连上的末梢不再是末梢，%s成为新的末梢。" % [def.graft_min, def.display_name])
	elif def.is_end():
		lines.append("【芽点】没有。后面不能再接牌，所以它一定是末梢。")
	else:
		var names: Array[String] = []
		for p in def.ports:
			names.append(PORT_NAMES.get(p, str(p)))
		lines.append("【芽点】%d 个：%s（以它从父牌长出来的方向为“前方”，所以同一张牌放在不同位置，芽点朝向也不同）。" % [def.ports.size(), "、".join(names)])
	if def.min_depth > 0:
		lines.append("【限制】只能接在深度 ≥%d 的位置（树心深度 0，每往外接一张 +1）。" % def.min_depth)
	lines.append("【效果】" + _effect_line(def))
	if def.mature_step > 0:
		lines.append("【成熟】每经历一次脉动，数值 +%s，最多累计 +%s。" % [Pulse.num(def.mature_step), Pulse.num(def.mature_cap)])
	if def.ripen_age > 0:
		lines.append("【花苞】前 %d 次脉动数值为 %s，之后变为 %s。" % [def.ripen_age, Pulse.num(def.value), Pulse.num(def.ripe_value)])
	if def.aura > 0:
		lines.append("【相邻】挨着它的其他末梢，收获各 +%d（不经过枝干）。" % def.aura)
	if def.aura_conduct > 0:
		lines.append("【相邻】挨着它的传导牌，流出的养分各 +%d。" % def.aura_conduct)
	lines.append("【修剪】剪掉时得 %d 养分%s。" % [def.prune_value, ("，并让下次脉动所有末梢 +%d" % def.prune_tip_bonus) if def.prune_tip_bonus > 0 else ""])
	if def.category == CardDef.Category.END:
		lines.append("【季节】秋季时末端牌流出的养分 ×1.5。")
	lines.append("【集市价格】%d 养分。" % def.price)
	return "\n".join(lines)


static func _effect_line(def: CardDef) -> String:
	match def.effect:
		CardDef.Effect.ADD:
			return "流过的养分 +%s。" % Pulse.num(def.value)
		CardDef.Effect.ADD_DEPTH:
			return "流过的养分加上它所在的深度（离树心越远加得越多）。"
		CardDef.Effect.MUL:
			return "流过的养分 ×%s（向下取整）。乘法放在越靠后的位置，放大的数越大。" % Pulse.num(def.value)
		CardDef.Effect.SUB_CLAMP:
			return "流过的养分 −%s（最低为 0），换来更多芽点。" % Pulse.num(def.value)
		CardDef.Effect.GRAFT:
			if def.graft_sum:
				return "把几个父末梢的养分相加，再 ×%s。父牌的数小时比相乘更划算。" % Pulse.num(def.value)
			return "把几个父末梢的养分相乘。两个 8 相乘就是 64——这是本作最大的爆发来源。"
	if def.ports.size() >= 2:
		return "养分原样复制到每个芽点后面的牌。"
	return "养分原样通过，不加不减。"
