class_name Pulse
extends RefCounted
## 脉动计分。纯函数：输入 TreeModel 与上下文，输出每个节点的养分和总分。
## Context.prototype() 关闭全部扩展机制，结果与网页原型 compute() 完全一致。

const LONG_STEM_DEPTH := 6
const SYMMETRY_MIN := 6
const RICH_BONUS := 2
## 共鸣：牌桌上同一流派的牌数达到这些阈值时分别激活第 1/2/3 层。木是基础流派，没有共鸣。
const RESONANCE_STEPS: Array[int] = [2, 4, 6]
## 齿轮共鸣：联动加成的倍数；熔炉共鸣：火候倍率的倍数（按层数 0–3）。
const GEAR_RES := [1.0, 2.0, 3.0, 4.0]
const FORGE_RES := [1.0, 2.0, 3.0, 4.0]
## 星辰共鸣：整树总分倍率；商会共鸣：每次脉动额外养分；镜像共鸣：每对对称牌的总分加成；
## 封印共鸣：释放倍率每次封存额外 +x。
const STAR_RES := [1.0, 1.1, 1.25, 1.5]
const COIN_RES := [0, 2, 3, 5]
const MIRROR_RES := [0.0, 0.3, 0.6, 1.0]
const SEAL_RES := [0.0, 1.0, 1.75, 2.75]
## 共鸣说明（界面用）：每层的效果。
## 共鸣说明（界面用），数字直接取自上面的常量。
static func resonance_desc(f: StringName) -> String:
	var tiers := func(arr: Array, fmt: String) -> String:
		return " / ".join(arr.slice(1).map(func(x): return fmt % num(x) if fmt.contains("%s") else fmt))
	match f:
		&"gear":
			return "齿轮牌的联动加成 %s" % tiers.call(GEAR_RES, "×%s")
		&"forge":
			return "熔炉的火候倍率 %s；每燃烧一张牌火候再 +1 / +2 / +3" % tiers.call(FORGE_RES, "×%s")
		&"star":
			return "整树总分 %s" % tiers.call(STAR_RES, "×%s")
		&"coin":
			return "每次脉动额外 %s 养分" % tiers.call(COIN_RES, "+%s")
		&"mirror":
			return "镜阵：牌桌上每一对对称的同类牌，总分 %s" % " / ".join(MIRROR_RES.slice(1).map(func(x): return "+%d%%" % roundi(x * 100)))
		&"seal":
			return "封存释放时，每封存过一次脉动倍率再 %s" % tiers.call(SEAL_RES, "+%s")
	return ""


## 共鸣的一行文字：例如「齿轮 3/4」（已满 6 张写「齿轮 6 满」）。
static func resonance_text(f: StringName, count: int) -> String:
	var nm: String = CardDef.FAMILY_NAMES.get(f, String(f))
	for st in RESONANCE_STEPS:
		if count < st:
			return "%s %d/%d" % [nm, count, st]
	return "%s %d 满" % [nm, count]


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
	# ---- 阶段 C：流派机制需要的局面信息 ----
	## 共鸣是否生效（原型模式关闭）。
	var resonance: bool = true
	var turn: int = 1
	var turns_total: int = 5
	var sap: int = 0
	var heat: int = 0
	var burned_total: int = 0
	var relic_count: int = 0
	## 本局在集市累计花费的养分（账本）。
	var spent: int = 0
	## 日蚀：星辰牌流出 0。
	var eclipse: bool = false
	# ---- 器物 ----
	## 各流派共鸣阈值的减免（徽章）：StringName -> 张数。
	var res_discount: Dictionary = {}
	## 齿轮牌联动加成每张额外 +x（油壶）。
	var link_extra: int = 0
	## 星辰牌计算回合数时 +x（星象仪）。
	var star_turn_bonus: int = 0
	## 对称牌对不要求同类（双面镜）。
	var pairs_any: bool = false
	## 镜阵每对额外加成（镀银）。
	var mirror_extra: float = 0.0
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
		c.resonance = false
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
	## 本次脉动的副作用（由 RunState 结算）：产出养分、增加火候。
	var sap_gain: int = 0
	var heat_gain: int = 0
	## 各流派在牌桌上的牌数与共鸣层数。
	var family_counts: Dictionary = {}
	var resonance: Dictionary = {}  # StringName -> 层数 1..3（未激活不出现）
	## 契约等每次脉动要花的养分；回合末生息的总比例（每张最多 +5 由 RunState 限制）与张数。
	var sap_cost: int = 0
	var interest: float = 0.0
	var interest_cards: int = 0
	## 封印：本次脉动存进每张封印牌的量（格子 -> 数值），被封存的末梢，以及封存总量。
	var stores: Dictionary = {}
	var sealed: Dictionary = {}
	var stored_total: int = 0
	## 牌桌上对称的同类牌对数。
	var pairs: int = 0
	## 牌桌上有逆行（星辰牌每回合都按最后一回合算）。
	var retro: bool = false
	## 牌桌上有永动机。
	var link_all: bool = false
	var link_all_cap: int = 0
	## 万象镜映出的幻影数。
	var phantoms: int = 0
	# 仅 Context.explain 为真时填充：
	var trace: Dictionary = {}      # Vector2i -> Array[{label, op, result}]，节点流出养分的算式
	var tip_trace: Dictionary = {}  # Vector2i -> Array[...]，末梢收获的算式
	var total_trace: Array = []     # 整树倍率


static func resolve(tree: TreeModel, ctx: Context) -> Result:
	var res := Result.new()
	var ex := ctx.explain
	var list := tree.sorted()
	var loops := _loop_vines(tree) if ctx.patterns else {}
	res.family_counts = family_counts(tree)
	if ctx.resonance:
		for f in res.family_counts:
			var tr_ := resonance_tier(int(res.family_counts[f]) + int(ctx.res_discount.get(f, 0)))
			if tr_ > 0 and f != &"wood":
				res.resonance[f] = tr_
	var gear_f: float = GEAR_RES[res.resonance.get(&"gear", 0)]
	var forge_f: float = FORGE_RES[res.resonance.get(&"forge", 0)]
	res.pairs = sym_pairs(tree, ctx.pairs_any)
	var lines := star_lines(tree) if ctx.patterns else {}
	var phantom_x := 0.0
	for n in list:
		if n.is_seed():
			continue
		if n.def().retro:
			res.retro = true
		if n.def().link_all:
			res.link_all = true
			res.link_all_cap = maxi(res.link_all_cap, n.def().link_all_cap)
		phantom_x = maxf(phantom_x, n.def().phantom_mirror)

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
			if def.graft_count_mul:
				v *= inflows.size()
				if ex: tr.append(_step("枢纽", "×%d（父牌数）" % inflows.size(), v))
			if ctx.graft_mult != 1.0:
				v = to_int((v * ctx.graft_mult))
				if ex: tr.append(_step("嫁接刀", "×%s" % num(ctx.graft_mult), v))
			if loops.has(n.key):
				v *= 2
				if ex: tr.append(_step("闭环", "×2", v))
		else:
			var inflow: int = res.out.get(n.parents[0], 0) if not n.parents.is_empty() else 0
			if ex:
				tr.append(_step("来自" + _name(tree.at(n.parents[0])), "", inflow))
			if def.copy_max_neighbor:
				var best := inflow
				for nb in Hex.neighbors(n.key):
					if res.out.has(nb) and nb != n.key:
						best = maxi(best, int(res.out[nb]))
				if best > inflow:
					inflow = best
					if ex: tr.append(_step("传动", "取相邻最高 %d" % best, inflow))
			v = def.apply(inflow, n, ctx.maturity)
			if ex:
				tr.append(_step(def.display_name, effect_text(def, n, ctx.maturity), v))
			v = _modifiers(tree, n, def, v, ctx, res, gear_f, forge_f, tr if ex else null)
			v = _modifiers2(tree, n, def, v, ctx, res, tr if ex else null)
			if def.category == CardDef.Category.CONDUCT:
				for nb in Hex.neighbors(n.key):
					var m := tree.at(nb)
					if m and not m.is_seed() and m.def().aura_conduct > 0:
						v += m.def().aura_conduct
						if ex: tr.append(_step("相邻的" + m.def().display_name, "+%d" % m.def().aura_conduct, v))
			if def.category == CardDef.Category.END and ctx.end_mult != 1.0:
				v = to_int((v * ctx.end_mult))
				if ex: tr.append(_step("秋季", "×%s" % num(ctx.end_mult), v))
		match tree.land_at(n.key):
			Land.Type.FERTILE:
				v += Land.FERTILE_BONUS
				if ex: tr.append(_step("沃土", "+%d" % Land.FERTILE_BONUS, v))
			Land.Type.ORE:
				var ob := 4 if def.has_family(&"gear") else 1
				v += ob
				if ex: tr.append(_step("矿脉", "+%d" % ob, v))
			Land.Type.STARWELL:
				v += ctx.turn
				if ex: tr.append(_step("星井", "+%d" % ctx.turn, v))
			Land.Type.GOLDSAND:
				res.sap_gain += 1
		if n.marks.has(&"rich"):
			v += RICH_BONUS
			if ex: tr.append(_step("年轮·丰饶", "+%d" % RICH_BONUS, v))
		if n.marks.has(&"echo"):
			v *= 2
			if ex: tr.append(_step("年轮·回响", "×2", v))
		# 星芒：一张牌直接长出 3 条子枝，流出养分翻倍
		if ctx.patterns and n.children.size() >= 3:
			v *= 2
			if ex: tr.append(_step("星芒", "×2", v))
		if lines.has(n.key):
			v *= 2
			if ex: tr.append(_step("连星", "×2", v))
		res.out[n.key] = v
		if ex:
			res.trace[n.key] = tr

	for n in list:
		if n.children.is_empty():
			res.tips[n.key] = true
			res.tip_list.append(n.key)

	var bonus_src := {}  # 末梢 -> [[来源, 数值]]
	var tip_mul := {}    # 末梢 -> 收获倍率（擒纵）
	for n in list:
		if n.is_seed():
			continue
		var d := n.def()
		res.sap_gain += d.pulse_sap
		res.heat_gain += d.pulse_heat
		if d.pulse_cost > 0 and ctx.sap >= d.pulse_cost:
			res.sap_cost += d.pulse_cost
		if d.interest > 0.0:
			res.interest += d.interest
			res.interest_cards += 1
		if d.seal_feed > 0:
			for nb in Hex.neighbors(n.key):
				var m := tree.at(nb)
				if m and not m.is_seed() and (m.def().seal_adjacent or m.def().seal_self):
					res.stores[nb] = int(res.stores.get(nb, 0)) + d.seal_feed
					res.stored_total += d.seal_feed
		if d.aura_tip_mul > 0.0:
			for nb in Hex.neighbors(n.key):
				if res.tips.has(nb) and nb != n.key:
					tip_mul[nb] = float(tip_mul.get(nb, 1.0)) * (1.0 + d.aura_tip_mul)
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

	res.sap_gain += COIN_RES[res.resonance.get(&"coin", 0)]
	# 封印：每个末梢的封存去处（自己封存，或第一张相邻的封印匣）
	var seal_to := {}
	for t in res.tip_list:
		var tn := tree.at(t)
		if tn.is_seed():
			continue
		if tn.def().seal_self:
			seal_to[t] = t
			continue
		for nb in Hex.neighbors(t):
			var m := tree.at(nb)
			if m and not m.is_seed() and m.def().seal_adjacent:
				seal_to[t] = nb
				break
	# 倒影类末梢最后算，好读到对面的收获
	var order: Array[Vector2i] = []
	var late: Array[Vector2i] = []
	for t in res.tip_list:
		var tn := tree.at(t)
		if not tn.is_seed() and tn.def().mirror_tip:
			late.append(t)
		else:
			order.append(t)
	order.append_array(late)
	var long_tips: Array[Vector2i] = []
	for t in order:
		var c: int = res.out[t]
		var tt: Array = []
		if ex:
			tt.append(_step("自身流出", "", c))
			var run_c := c
			for src in bonus_src.get(t, []):
				run_c += src[1]
				tt.append(_step(src[0], "+%d" % src[1], run_c))
		c += int(res.bonus.get(t, 0))
		if tip_mul.has(t):
			c = to_int((c * float(tip_mul[t])))
			if ex: tt.append(_step("相邻的擒纵", "×%s" % num(tip_mul[t]), c))
		# 长茎：从树心到这个末梢连续 6 张以上
		var tnode := tree.at(t)
		var eff_depth := tnode.depth + (0 if tnode.is_seed() else tnode.def().depth_bonus)
		if ctx.patterns and eff_depth >= ctx.long_depth:
			c *= 2
			long_tips.append(t)
			if ex: tt.append(_step("长茎", "×2", c))
		if not tnode.is_seed() and tnode.def().mirror_tip and res.contrib.has(-t) and int(res.contrib[-t]) > c:
			c = int(res.contrib[-t])
			if ex: tt.append(_step("倒影", "取对面收获 %d" % c, c))
		res.contrib[t] = c
		if seal_to.has(t):
			var h: Vector2i = seal_to[t]
			res.stores[h] = int(res.stores.get(h, 0)) + c
			res.stored_total += c
			res.sealed[t] = true
			if ex: tt.append(_step("封存", "存入%s，本次不计分" % _name(tree.at(h)), 0))
		else:
			res.total += c
		if ex:
			res.tip_trace[t] = tt

	# 万象镜：没有对称牌的末梢在对面映出幻影
	if phantom_x > 0.0:
		var extra := 0
		for t in res.contrib:
			if res.sealed.has(t) or t == TreeModel.SEED_KEY or tree.at(-t) != null:
				continue
			extra += to_int((int(res.contrib[t]) * phantom_x))
			res.phantoms += 1
		if extra > 0:
			res.total += extra
			res.pairs += res.phantoms / 3
			if ex: res.total_trace.append(_step("万象镜 %d 个幻影" % res.phantoms, "+%d" % extra, 0))

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
		if not lines.is_empty():
			var lc2: Array[Vector2i] = []
			lc2.assign(lines.keys())
			res.patterns.append(Pattern.make(&"line", "连星 ×%d 张" % lc2.size(), lc2))
	# 星图：每张 ×(1 + x·星辰牌数)
	var star_n: int = res.family_counts.get(&"star", 0)
	for n in list:
		if not n.is_seed() and n.def().star_total_mult > 0.0 and star_n > 0:
			var m := 1.0 + n.def().star_total_mult * star_n
			res.total_mult *= m
			if ex: res.total_trace.append(_step(n.def().display_name, "总分 ×%s" % num(m), 0))
	var sr: float = STAR_RES[res.resonance.get(&"star", 0)]
	if sr != 1.0:
		res.total_mult *= sr
		if ex: res.total_trace.append(_step("星辰共鸣", "总分 ×%s" % num(sr), 0))
	var mr: float = MIRROR_RES[res.resonance.get(&"mirror", 0)]
	if mr > 0.0:
		mr += ctx.mirror_extra
	if mr > 0.0 and res.pairs > 0:
		var m2 := 1.0 + mr * res.pairs
		res.total_mult *= m2
		if ex: res.total_trace.append(_step("镜阵 %d 对" % res.pairs, "总分 ×%s" % num(m2), 0))
	if ctx.total_mult != 1.0 and ex:
		res.total_trace.append(_step("露水瓶", "总分 ×%s" % num(ctx.total_mult), 0))
	res.total_mult *= ctx.total_mult
	res.raw_total = res.total
	if res.total_mult != 1.0:
		res.total = to_int((res.total * res.total_mult))
	return res


# ---------- 流派修饰器与共鸣 ----------

## 基础效果之后依次结算的修饰器。tr 为 null 时不记录算式。
static func _modifiers(tree: TreeModel, n: TreeNode, def: CardDef, v: int, ctx: Context, res: Result,
		gear_f: float, forge_f: float, tr) -> int:
	if def.adj_family_add != 0 or def.adj_family_mul != 0.0:
		var adj := adjacent_family(tree, n)
		if res.link_all and def.has_family(&"gear"):
			var all_g := mini(res.link_all_cap, int(res.family_counts.get(&"gear", 0)) - 1)
			if all_g > adj:
				adj = all_g
				if tr != null: tr.append(_step("永动机", "按 %d 张相邻算" % adj, v))
		if adj > 0:
			if def.adj_family_add != 0:
				var per := def.adj_family_add + (ctx.link_extra if def.has_family(&"gear") else 0)
				v += int(round(per * adj * gear_f))
				if tr != null: tr.append(_step("联动 %d 张" % adj, "+%s" % num(per * adj * gear_f), v))
			if def.adj_family_mul != 0.0:
				var m := 1.0 + def.adj_family_mul * adj * gear_f
				v = to_int((v * m))
				if tr != null: tr.append(_step("联动 %d 张" % adj, "×%s" % num(m), v))
	if def.family_count_mul != 0.0:
		var cnt := 0
		for f in def.families():
			cnt = maxi(cnt, int(res.family_counts.get(f, 0)))
		var m := 1.0 + def.family_count_mul * cnt
		v = to_int((v * m))
		if tr != null: tr.append(_step("同流派 %d 张" % cnt, "×%s" % num(m), v))
	if def.heat_mul != 0.0 and ctx.heat > 0:
		var m := 1.0 + def.heat_mul * ctx.heat * forge_f
		v = to_int((v * m))
		if tr != null: tr.append(_step("火候 %d" % ctx.heat, "×%s" % num(m), v))
	if def.burned_add != 0.0 and ctx.burned_total > 0:
		v += int(def.burned_add * ctx.burned_total)
		if tr != null: tr.append(_step("已燃烧 %d 张" % ctx.burned_total, "+%s" % num(def.burned_add * ctx.burned_total), v))
	return v


## 星辰、商会、镜像、封印的修饰器。
static func _modifiers2(tree: TreeModel, n: TreeNode, def: CardDef, v: int, ctx: Context, res: Result, tr) -> int:
	if ctx.eclipse and def.has_family(&"star"):
		v = to_int(v * ECLIPSE_MULT)
		if tr != null: tr.append(_step("日蚀", "×%s" % num(ECLIPSE_MULT), v))
	var turn := ctx.turn + (ctx.star_turn_bonus if def.has_family(&"star") else 0)
	if res.retro and def.has_family(&"star") and turn < ctx.turns_total:
		turn = ctx.turns_total
		if tr != null: tr.append(_step("逆行", "按第 %d 回合算" % turn, v))
	if def.turn_add != 0.0:
		v += int(def.turn_add * turn)
		if tr != null: tr.append(_step("第 %d 回合" % turn, "+%s" % num(def.turn_add * turn), v))
	if def.turn_mul:
		v *= turn
		if tr != null: tr.append(_step("第 %d 回合" % turn, "×%d" % turn, v))
	if def.odd_turn_mul != 0.0 and turn % 2 == 1:
		v = to_int((v * def.odd_turn_mul))
		if tr != null: tr.append(_step("奇数回合", "×%s" % num(def.odd_turn_mul), v))
	if def.last_turn_mult != 0.0 and turn >= ctx.turns_total:
		v = to_int((v * def.last_turn_mult))
		if tr != null: tr.append(_step("本季最后一回合", "×%s" % num(def.last_turn_mult), v))
	if def.season_mul:
		var sm := mini(ctx.season, 4)
		v *= sm
		if tr != null: tr.append(_step("季节", "×%d" % sm, v))
	if def.sap_add != 0.0 and ctx.sap > 0:
		v += int(def.sap_add * ctx.sap)
		if tr != null: tr.append(_step("养分 %d" % ctx.sap, "+%s" % num(def.sap_add * ctx.sap), v))
	if def.sap_mul != 0.0 and ctx.sap > 0:
		var m := 1.0 + def.sap_mul * ctx.sap
		v = to_int((v * m))
		if tr != null: tr.append(_step("养分 %d" % ctx.sap, "×%s" % num(m), v))
	if def.pulse_cost > 0 and ctx.sap < def.pulse_cost:
		v = 0
		if tr != null: tr.append(_step("养分不足 %d" % def.pulse_cost, "流出 0", v))
	if def.spent_add != 0.0 and ctx.spent > 0:
		v += int(def.spent_add * ctx.spent)
		if tr != null: tr.append(_step("累计花费 %d" % ctx.spent, "+%s" % num(def.spent_add * ctx.spent), v))
	if def.relic_mul:
		v *= ctx.relic_count + 1
		if tr != null: tr.append(_step("器物 %d 件" % ctx.relic_count, "×%d" % (ctx.relic_count + 1), v))
	if def.calamity_mult != 0.0 and Rules.is_calamity(ctx.season):
		v = to_int((v * def.calamity_mult))
		if tr != null: tr.append(_step("天灾季", "×%s" % num(def.calamity_mult), v))
	var mirror := tree.at(-n.key)
	if def.mirror_same_mult != 0.0 and mirror != null and mirror.type == n.type:
		v = to_int((v * def.mirror_same_mult))
		if tr != null: tr.append(_step("对面同类", "×%s" % num(def.mirror_same_mult), v))
	if def.mirror_copy != 0.0 and res.out.has(-n.key):
		var mv := to_int((int(res.out[-n.key]) * def.mirror_copy))
		if mv > v:
			v = mv
			if tr != null: tr.append(_step("映照对面", "取 %d" % mv, v))
	if def.pair_add != 0 and res.pairs > 0:
		v += def.pair_add * res.pairs
		if tr != null: tr.append(_step("对称 %d 对" % res.pairs, "+%d" % (def.pair_add * res.pairs), v))
	return v


## 牌桌上点对称位置为同类牌的对数（不含树心）。
static func sym_pairs(tree: TreeModel, any_type: bool = false) -> int:
	var c := 0
	for n: TreeNode in tree.nodes.values():
		if n.is_seed():
			continue
		var m := tree.at(-n.key)
		if m != null and not m.is_seed() and (any_type or m.type == n.type):
			c += 1
	return c / 2


## 连星：星辰牌沿同一方向连续 3 张以上，返回这些格子。
static func star_lines(tree: TreeModel) -> Dictionary:
	var out := {}
	for n: TreeNode in tree.nodes.values():
		if n.is_seed() or not n.def().has_family(&"star"):
			continue
		for d in 3:
			var prev := tree.at(n.key - Hex.DIRS[d])
			if prev != null and not prev.is_seed() and prev.def().has_family(&"star"):
				continue  # 只从一条线的起点开始数
			var run: Array[Vector2i] = [n.key]
			var c := n.key + Hex.DIRS[d]
			while tree.at(c) != null and not tree.at(c).is_seed() and tree.at(c).def().has_family(&"star"):
				run.append(c)
				c += Hex.DIRS[d]
			if run.size() >= 3:
				for k in run:
					out[k] = true
	return out


## 相邻的、与 n 至少共享一个流派的牌数（不含树心）。
static func adjacent_family(tree: TreeModel, n: TreeNode) -> int:
	var mine := n.def().families()
	var c := 0
	for nb in Hex.neighbors(n.key):
		var m := tree.at(nb)
		if m == null or m.is_seed():
			continue
		for f in m.def().families():
			if mine.has(f):
				c += 1
				break
	return c


## 牌桌上每个流派的牌数（双流派牌两边都算）。
static func family_counts(tree: TreeModel) -> Dictionary:
	var out := {}
	var wilds := 0
	var partner := 0
	var partner_cap := 0
	var others := 0
	for n: TreeNode in tree.nodes.values():
		if n.is_seed():
			continue
		for f in n.def().families():
			out[f] = int(out.get(f, 0)) + 1
		if n.def().wild:
			wilds += 1
		if not n.def().has_family(&"coin"):
			others += 1
		if n.def().partner_per > 0:
			partner = n.def().partner_per if partner == 0 else mini(partner, n.def().partner_per)
			partner_cap = maxi(partner_cap, n.def().partner_cap)
	# 合伙契约：每 x 张非商会牌算 1 张商会牌
	if partner > 0 and others >= partner:
		out[&"coin"] = int(out.get(&"coin", 0)) + mini(others / partner, partner_cap)
	# 幻影：逐张加到离下一阈值最近的流派上（木和镜像自己除外）
	for i in wilds:
		var best := &""
		var best_gap := 99
		for f in out:
			if f == &"wood" or f == &"mirror":
				continue
			var gap := 99
			for st in RESONANCE_STEPS:
				if out[f] < st:
					gap = st - out[f]
					break
			if gap < best_gap:
				best_gap = gap
				best = f
		if best != &"":
			out[best] = int(out[best]) + 1
	return out


## 牌数对应的共鸣层数 0..3。
static func resonance_tier(count: int) -> int:
	var t := 0
	for s in RESONANCE_STEPS:
		if count >= s:
			t += 1
	return t


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
## 分数上限：浮点转整数前先夹住，防止 int64 回绕（留足余量给求和）。
const SCORE_CAP := 1000000000000000
## 日蚀：星辰牌流出倍率。
const ECLIPSE_MULT := 0.25


## 向下取整并夹到 [−SCORE_CAP, SCORE_CAP]。
static func to_int(f: float) -> int:
	return int(floor(clampf(f, -SCORE_CAP, SCORE_CAP)))


## 大数显示：1 万以下写整数；1 万到 1 亿写「万」（三位有效数字，如 2.4万、200万）；
## 1 亿以上写科学计数法（三位有效数字，如 3.27e8）。
static func big(v: float) -> String:
	var a := absf(v)
	if a < 10000.0:
		return str(int(v))
	if a < 100000000.0:
		var w := v / 10000.0
		var digits := 2 if absf(w) < 10.0 else (1 if absf(w) < 100.0 else 0)
		var t := ("%." + str(digits) + "f") % w
		if t.contains("."):
			t = t.rstrip("0").rstrip(".")
		return t + "万"
	var e := int(floor(log(a) / log(10.0)))
	var m := v / pow(10.0, e)
	if absf(m) >= 9.995:
		m /= 10.0
		e += 1
	return "%.2fe%d" % [m, e]


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
