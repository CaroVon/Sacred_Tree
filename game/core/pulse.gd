class_name Pulse
extends RefCounted
## 脉动计分。纯函数：输入 TreeModel 与上下文，输出每个节点的养分和总分。
## Context.prototype() 关闭全部扩展机制，结果与网页原型 compute() 完全一致。

const LONG_STEM_DEPTH := 6
const SYMMETRY_MIN := 6
const RICH_BONUS := 2


class Context:
	extends RefCounted
	var seed_out: int = 1
	var season: int = 1
	## 成熟：牌按经历过的脉动次数增强。
	var maturity: bool = true
	## 几何牌型：长茎、星芒、对称、闭环。
	var patterns: bool = true
	## 末端类牌流出养分的季节倍率（秋季 1.5）。
	var end_mult: float = 1.0
	# ---- 器物、天灾、临时效果 ----
	var seed_extra_port: bool = false
	var long_depth: int = LONG_STEM_DEPTH
	var aura_extra: int = 0
	var graft_mult: float = 1.0
	var total_mult: float = 1.0
	var tip_bonus: int = 0
	## 为真时记录每一步算式（界面解释用；平衡模拟保持关闭）。
	var explain: bool = false

	static func for_season(s: int, year: int = 1) -> Context:
		var c := Context.new()
		c.season = s
		c.seed_out = Rules.seed_out(s, year)
		c.end_mult = Rules.season_end_mult(s)
		return c

	## 与网页原型一致的规则（用于一致性测试）。
	static func prototype(s: int) -> Context:
		var c := Context.new()
		c.season = s
		c.seed_out = Rules.seed_out(s)
		c.maturity = false
		c.patterns = false
		return c


class Pattern:
	extends RefCounted
	var id: StringName
	var label: String
	var cells: Array[Vector2i] = []

	static func make(pid: StringName, text: String, at: Array[Vector2i]) -> Pattern:
		var p := Pattern.new()
		p.id = pid
		p.label = text
		p.cells = at
		return p


class Result:
	extends RefCounted
	var out: Dictionary = {}      # Vector2i -> int，每个节点流出的养分
	var bonus: Dictionary = {}    # Vector2i -> int，末梢获得的相邻/土地/临时加成
	var contrib: Dictionary = {}  # Vector2i -> int，每个末梢的收获
	var tips: Dictionary = {}     # Vector2i -> true
	var tip_list: Array[Vector2i] = []
	var patterns: Array[Pattern] = []
	var total_mult: float = 1.0
	var total: int = 0
	## 乘整树倍率之前的总和。
	var raw_total: int = 0
	# 仅 Context.explain 为真时填充：
	var trace: Dictionary = {}      # Vector2i -> Array[{label, op, result}]，节点流出养分的算式
	var tip_trace: Dictionary = {}  # Vector2i -> Array[...]，末梢收获的算式
	var total_trace: Array = []     # 整树倍率


static func resolve(tree: TreeModel, ctx: Context) -> Result:
	var res := Result.new()
	var ex := ctx.explain
	var list := tree.sorted()
	var loops := _loop_vines(tree) if ctx.patterns else {}

	for n in list:
		if n.is_seed():
			res.out[n.key] = ctx.seed_out
			if ex:
				res.trace[n.key] = [_step("树心", "输出 %d" % ctx.seed_out, ctx.seed_out)]
			continue
		var def := n.def()
		var v := 0
		var tr: Array = []
		if def.is_graft():
			var inflows: Array[int] = []
			for p in n.parents:
				inflows.append(int(res.out.get(p, 0)))
			v = def.combine(inflows)
			if ex:
				var parts := inflows.map(func(x): return str(x))
				var op := ("(%s) ×%s" % [" + ".join(parts), num(def.value)]) if def.graft_sum else " × ".join(parts)
				tr.append(_step(def.display_name, ("嫁接相加 " if def.graft_sum else "嫁接相乘 ") + op, v))
			if ctx.graft_mult != 1.0:
				v = int(floor(v * ctx.graft_mult))
				if ex: tr.append(_step("嫁接刀", "×%s" % num(ctx.graft_mult), v))
			if loops.has(n.key):
				v *= 2
				if ex: tr.append(_step("闭环", "×2", v))
		else:
			var inflow: int = res.out.get(n.parents[0], 0) if not n.parents.is_empty() else 0
			v = def.apply(inflow, n, ctx.maturity)
			if ex:
				tr.append(_step("来自" + _name(tree.at(n.parents[0])), "", inflow))
				tr.append(_step(def.display_name, effect_text(def, n, ctx.maturity), v))
			if def.category == CardDef.Category.CONDUCT:
				for nb in Hex.neighbors(n.key):
					var m := tree.at(nb)
					if m and not m.is_seed() and m.def().aura_conduct > 0:
						v += m.def().aura_conduct
						if ex: tr.append(_step("相邻的" + m.def().display_name, "+%d" % m.def().aura_conduct, v))
			if def.category == CardDef.Category.END and ctx.end_mult != 1.0:
				v = int(floor(v * ctx.end_mult))
				if ex: tr.append(_step("秋季", "×%s" % num(ctx.end_mult), v))
		if tree.land_at(n.key) == Land.Type.FERTILE:
			v += Land.FERTILE_BONUS
			if ex: tr.append(_step("沃土", "+%d" % Land.FERTILE_BONUS, v))
		if n.marks.has(&"rich"):
			v += RICH_BONUS
			if ex: tr.append(_step("年轮·丰饶", "+%d" % RICH_BONUS, v))
		# 星芒：一张牌直接长出 3 条子枝，流出养分翻倍
		if ctx.patterns and n.children.size() >= 3:
			v *= 2
			if ex: tr.append(_step("星芒", "×2", v))
		res.out[n.key] = v
		if ex:
			res.trace[n.key] = tr

	for n in list:
		if n.children.is_empty():
			res.tips[n.key] = true
			res.tip_list.append(n.key)

	var bonus_src := {}  # 末梢 -> [[来源, 数值]]
	for n in list:
		if n.is_seed():
			continue
		var aura := n.def().aura
		if aura == 0:
			continue
		aura += ctx.aura_extra
		for nb in Hex.neighbors(n.key):
			if res.tips.has(nb):
				res.bonus[nb] = int(res.bonus.get(nb, 0)) + aura
				if ex: _add_src(bonus_src, nb, "相邻的" + n.def().display_name, aura)
	for c in tree.land:
		if tree.land[c] == Land.Type.SPRING:
			for nb in Hex.neighbors(c):
				if res.tips.has(nb):
					res.bonus[nb] = int(res.bonus.get(nb, 0)) + Land.SPRING_BONUS
					if ex: _add_src(bonus_src, nb, "相邻的泉眼", Land.SPRING_BONUS)
	if ctx.tip_bonus != 0:
		for t in res.tip_list:
			res.bonus[t] = int(res.bonus.get(t, 0)) + ctx.tip_bonus
			if ex: _add_src(bonus_src, t, "落叶", ctx.tip_bonus)

	var long_tips: Array[Vector2i] = []
	for t in res.tip_list:
		var c: int = res.out[t]
		var tt: Array = []
		if ex:
			tt.append(_step("自身流出", "", c))
			var run_c := c
			for src in bonus_src.get(t, []):
				run_c += src[1]
				tt.append(_step(src[0], "+%d" % src[1], run_c))
		c += int(res.bonus.get(t, 0))
		# 长茎：从树心到这个末梢连续 6 张以上
		if ctx.patterns and tree.at(t).depth >= ctx.long_depth:
			c *= 2
			long_tips.append(t)
			if ex: tt.append(_step("长茎", "×2", c))
		res.contrib[t] = c
		res.total += c
		if ex:
			res.tip_trace[t] = tt

	if ctx.patterns:
		if not long_tips.is_empty():
			res.patterns.append(Pattern.make(&"long", "长茎 ×%d 处" % long_tips.size(), long_tips))
		var stars: Array[Vector2i] = []
		for n in list:
			if not n.is_seed() and n.children.size() >= 3:
				stars.append(n.key)
		if not stars.is_empty():
			res.patterns.append(Pattern.make(&"star", "星芒 ×%d 处" % stars.size(), stars))
		if not loops.is_empty():
			var lc: Array[Vector2i] = []
			lc.assign(loops.keys())
			res.patterns.append(Pattern.make(&"loop", "闭环 ×%d 处" % lc.size(), lc))
		if is_symmetric(tree):
			res.total_mult *= 1.5
			if ex: res.total_trace.append(_step("对称", "总分 ×1.5", 0))
			var all: Array[Vector2i] = []
			for n in list:
				if not n.is_seed():
					all.append(n.key)
			res.patterns.append(Pattern.make(&"sym", "对称 总分 ×1.5", all))
	if ctx.total_mult != 1.0 and ex:
		res.total_trace.append(_step("露水瓶", "总分 ×%s" % num(ctx.total_mult), 0))
	res.total_mult *= ctx.total_mult
	res.raw_total = res.total
	if res.total_mult != 1.0:
		res.total = int(floor(res.total * res.total_mult))
	return res


# ---------- 解释 ----------

static func _step(label: String, op: String, result: int) -> Dictionary:
	return {"label": label, "op": op, "result": result}


static func _add_src(d: Dictionary, k: Vector2i, label: String, v: int) -> void:
	if not d.has(k):
		d[k] = []
	d[k].append([label, v])


static func _name(n: TreeNode) -> String:
	return "树心" if n.is_seed() else n.def().display_name


## 数字的简短写法：2 → "2"，2.5 → "2.5"。
static func num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return ("%.2f" % x).rstrip("0").rstrip(".")


## 一张牌在当前状态下的效果写法（用于牌桌标签和算式）。
static func effect_text(def: CardDef, n: TreeNode, maturity: bool = true) -> String:
	var x := def.current_value(n.age if n else 0, maturity)
	match def.effect:
		CardDef.Effect.ADD:
			return "+%s" % num(x)
		CardDef.Effect.ADD_DEPTH:
			return "+深度 %d" % (n.depth if n else 0)
		CardDef.Effect.MUL:
			return "×%s" % num(x)
		CardDef.Effect.SUB_CLAMP:
			return "−%s（最低 0）" % num(x)
		CardDef.Effect.GRAFT:
			return "相加 ×%s" % num(def.value) if def.graft_sum else "相乘"
	return "复制" if def.ports.size() >= 2 else "不变"


## 把一串步骤写成一行算式：树心 1 → 茎 +3 = 4 → 果 ×2 = 8
static func chain_text(steps: Array) -> String:
	var parts: Array[String] = []
	for st in steps:
		if st.op == "":
			parts.append("%s %d" % [st.label, st.result])
		else:
			parts.append("%s %s = %d" % [st.label, st.op, st.result])
	return " → ".join(parts)


## 对称：除树心外至少 6 张牌，且每张牌在点对称位置上都有同类牌。
static func is_symmetric(tree: TreeModel) -> bool:
	if tree.size() - 1 < SYMMETRY_MIN:
		return false
	for n: TreeNode in tree.nodes.values():
		if n.is_seed():
			continue
		var m := tree.at(-n.key)
		if m == null or m.type != n.type:
			return false
	return true


## 闭环：藤的多个父牌能追溯到同一个非树心的祖先。返回 Vector2i -> true。
static func _loop_vines(tree: TreeModel) -> Dictionary:
	var out := {}
	for n: TreeNode in tree.nodes.values():
		if n.is_seed() or n.parents.size() < 2 or not n.def().is_graft():
			continue
		var seen := {}
		var closed := false
		for p in n.parents:
			var anc := _ancestors(tree, p)
			for a in anc:
				if seen.has(a):
					closed = true
			for a in anc:
				seen[a] = true
		if closed:
			out[n.key] = true
	return out


## 一个节点自身及其所有非树心祖先。
static func _ancestors(tree: TreeModel, k: Vector2i) -> Dictionary:
	var res := {}
	var stack: Array[Vector2i] = [k]
	while not stack.is_empty():
		var x: Vector2i = stack.pop_back()
		if res.has(x) or x == TreeModel.SEED_KEY:
			continue
		res[x] = true
		for p in tree.at(x).parents:
			stack.append(p)
	return res
