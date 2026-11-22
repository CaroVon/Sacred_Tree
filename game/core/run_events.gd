class_name RunEvents
extends RefCounted
## 局间事件：每季选牌之后有一定概率遇到一个事件，从 2–3 个选项里挑一个。
## 选项的效果用一串 op 描述，由 apply() 解释执行（规则层，不含画面）。
##
## op 一览（字段见各分支）：
##   sap n            养分 +n（可为负，最低 0）
##   sap_half         失去一半养分
##   heat n           火候 +n
##   add_card         加一张牌：id（指定）或 pick（random / rare / legendary / family:<流派> / top），count
##   remove_basic n   删去 n 张基础牌（优先枯枝、朽木，其次茎）
##   transform n      n 张基础牌变成主流派的随机牌
##   duplicate        复制牌组里最稀有的一张牌
##   refine_random n  随机精炼 n 张牌
##   relic            得一件随机器物（槽满则换成 8 养分）
##   lose_relic       失去最便宜的一件器物
##   market_discount  下次集市牌与器物半价
##   transplants n    下一季第一回合额外移栽 n 次
##   mark m           给树上收获最高、还没有该年轮的牌刻上年轮 m
##   burn n           烧掉 n 个末梢（坚韧的除外；算燃料）
##   age n            树上随机 3 张牌成熟 +n
##   land t n         n 块空平地变成地块 t（fertile / special）
##   clear_rock n     清除 n 块岩石
##   gamble p win lose  以概率 p 执行 win，否则执行 lose（都是 op 列表）

const DEBT := &"curse_debt"

const LIST := {
	&"wanderer": {"title": "流浪商人", "art": &"basket",
		"text": "一个背着大包裹的商人在树下歇脚，翻出几样旅途里收来的东西。",
		"options": [
			{"label": "约好下次集市给你半价", "ops": [{"op": "market_discount"}]},
			{"label": "花 5 养分，买他包里的一件器物", "cost": 5, "ops": [{"op": "sap", "n": -5}, {"op": "relic"}]},
			{"label": "道谢，送他上路（+3 养分）", "ops": [{"op": "sap", "n": 3}]},
		]},
	&"well": {"title": "古井", "art": &"dew",
		"text": "石砌的井口长满青苔，井底隐约有光。",
		"options": [
			{"label": "投下 5 养分许愿（一半可能得到器物）", "cost": 5, "ops": [{"op": "sap", "n": -5},
				{"op": "gamble", "p": 0.5, "win": [{"op": "relic"}], "lose": []}]},
			{"label": "打一桶水浇地：2 块平地变沃土", "ops": [{"op": "land", "t": "fertile", "n": 2}]},
		]},
	&"omen": {"title": "雷雨预兆", "art": &"lightning",
		"text": "远处的云压得很低，空气里有铁锈味。",
		"options": [
			{"label": "加固收获最高的牌：刻上「坚韧」", "ops": [{"op": "mark", "m": "tough"}]},
			{"label": "趁雨前多收一点（+6 养分）", "ops": [{"op": "sap", "n": 6}]},
		]},
	&"festival": {"title": "丰收祭", "art": &"fruit",
		"text": "村里的人围着神树跳舞，有人把一张牌抄了一份挂在枝头。",
		"options": [
			{"label": "复制牌组里最稀有的一张牌", "ops": [{"op": "duplicate"}]},
			{"label": "收下供品（+8 养分）", "ops": [{"op": "sap", "n": 8}]},
		]},
	&"dice": {"title": "骰子摊", "art": &"seedbag",
		"text": "一个戴面具的人摇着骨骰：「押六，赢十五。」",
		"options": [
			{"label": "押 6 养分（一半可能得 15）", "cost": 6, "ops": [{"op": "sap", "n": -6},
				{"op": "gamble", "p": 0.5, "win": [{"op": "sap", "n": 15}], "lose": []}]},
			{"label": "看看就走", "ops": []},
		]},
	&"bonfire": {"title": "篝火", "art": &"compost",
		"text": "守夜人在树下生了一堆火，问你要不要添几根枝。",
		"options": [
			{"label": "折两个末梢投进火里：火候 +6（末梢回到弃牌堆）", "ops": [{"op": "burn", "n": 2}, {"op": "heat", "n": 6}]},
			{"label": "只是取暖：火候 +2", "ops": [{"op": "heat", "n": 2}]},
		]},
	&"meteor_shower": {"title": "流星雨", "art": &"chime",
		"text": "整夜都有星星落下，有一颗落进了你的牌匣。",
		"options": [
			{"label": "得一张主流派的稀有牌", "ops": [{"op": "add_card", "pick": "rare_top"}]},
			{"label": "得两张普通牌", "ops": [{"op": "add_card", "pick": "random", "count": 2}]},
		]},
	&"creditor": {"title": "陌生的债主", "art": &"knife",
		"text": "一个衣着考究的人递来一袋养分：「不急着还。」",
		"options": [
			{"label": "收下 15 养分，牌组加入一张「债务」", "ops": [{"op": "sap", "n": 15}, {"op": "add_card", "id": "curse_debt"}]},
			{"label": "婉拒", "ops": []},
		]},
	&"landslide": {"title": "山体松动", "art": &"root",
		"text": "一场夜雨后，泥土变得松软，正适合重新布置。",
		"options": [
			{"label": "下一季第一回合额外移栽 3 次", "ops": [{"op": "transplants", "n": 3}]},
			{"label": "清除 2 块岩石", "ops": [{"op": "clear_rock", "n": 2}]},
		]},
	&"grafter": {"title": "嫁接师", "art": &"shears",
		"text": "一位老嫁接师路过，愿意帮你打磨几张牌。",
		"options": [
			{"label": "花 4 养分，随机精炼 2 张牌", "cost": 4, "ops": [{"op": "sap", "n": -4}, {"op": "refine_random", "n": 2}]},
			{"label": "请他免费精炼 1 张", "ops": [{"op": "refine_random", "n": 1}]},
		]},
	&"whisper": {"title": "古树低语", "art": &"tree",
		"text": "风穿过枝叶，你听见神树想要的样子。",
		"options": [
			{"label": "删去 2 张基础牌", "ops": [{"op": "remove_basic", "n": 2}]},
			{"label": "把 2 张基础牌变成主流派的随机牌", "ops": [{"op": "transform", "n": 2}]},
		]},
	&"workshop": {"title": "齿轮工坊", "art": &"ruler", "family": &"gear",
		"text": "工坊里堆满了零件，师傅让你挑几样。",
		"options": [
			{"label": "得一张稀有的齿轮牌", "ops": [{"op": "add_card", "pick": "rare_gear"}]},
			{"label": "得两张齿轮", "ops": [{"op": "add_card", "id": "gear_cog", "count": 2}]},
		]},
	&"smithy": {"title": "铁匠铺", "art": &"knife", "family": &"forge",
		"text": "炉火正旺，铁匠说可以借你一把火。",
		"options": [
			{"label": "花 4 养分，火候 +10", "cost": 4, "ops": [{"op": "sap", "n": -4}, {"op": "heat", "n": 10}]},
			{"label": "带走一块炭和一枚火种", "ops": [{"op": "add_card", "id": "forge_coal"}, {"op": "add_card", "id": "forge_kindle"}]},
		]},
	&"mirror_lake": {"title": "镜湖", "art": &"dew", "family": &"mirror",
		"text": "湖面平得像一块镜子，倒影比真树还要清楚。",
		"options": [
			{"label": "得一张镜像牌", "ops": [{"op": "add_card", "pick": "family:mirror"}]},
			{"label": "让倒影走出来：复制牌组里最稀有的一张牌", "ops": [{"op": "duplicate"}]},
		]},
	&"vault": {"title": "密室", "art": &"beehive",
		"text": "树根下露出一扇小门，门后的东西看起来不太干净。",
		"options": [
			{"label": "拿走一件器物，牌组加入一张「债务」", "ops": [{"op": "relic"}, {"op": "add_card", "id": "curse_debt"}]},
			{"label": "关上门", "ops": []},
		]},
	&"sprout": {"title": "春雨", "art": &"shoot",
		"text": "一场细雨，树上的牌好像一夜之间老成了不少。",
		"options": [
			{"label": "树上随机 3 张牌成熟 +2", "ops": [{"op": "age", "n": 2}]},
			{"label": "接雨水（+4 养分）", "ops": [{"op": "sap", "n": 4}]},
		]},
	&"taxman": {"title": "收税官", "art": &"seedbag",
		"text": "领主的收税官来了，账本上写着你的名字。",
		"options": [
			{"label": "交出一半养分", "ops": [{"op": "sap_half"}]},
			{"label": "交出最便宜的一件器物", "require_relic": true, "ops": [{"op": "lose_relic"}]},
			{"label": "交一张牌抵债：删去 1 张基础牌，再交 3 养分", "cost": 3, "ops": [{"op": "remove_basic", "n": 1}, {"op": "sap", "n": -3}]},
		]},
	&"caravan": {"title": "商队路过", "art": &"basket", "family": &"coin",
		"text": "骆驼铃声由远及近，商队在树荫下支起了摊子。",
		"options": [
			{"label": "花 6 养分，买一张随机传说牌", "cost": 6, "ops": [{"op": "sap", "n": -6}, {"op": "add_card", "pick": "legendary"}]},
			{"label": "卖一张基础牌（+5 养分）", "ops": [{"op": "remove_basic", "n": 1}, {"op": "sap", "n": 5}]},
		]},
}

const BASICS: Array[StringName] = [&"dead", &"rot", &"stem", &"node", &"fork"]


## 本局可以遇到的事件（流派限定的需要该流派已解锁）。
static func available(run: RunState) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in LIST:
		var fam: StringName = LIST[id].get("family", &"")
		if fam != &"" and not run.families_allowed.is_empty() and not run.families_allowed.has(fam):
			continue
		if run.seen_events.has(id):
			continue
		out.append(id)
	return out


## 某个选项现在能不能选；不能选返回原因（空字符串 = 可以）。
static func blocked(run: RunState, ev: StringName, i: int) -> String:
	var o: Dictionary = LIST[ev].options[i]
	if run.sap < int(o.get("cost", 0)):
		return "养分不足（需要 %d）" % int(o.cost)
	if o.get("require_relic", false) and run.relics.is_empty():
		return "没有器物"
	return ""


## 执行一串 op，返回结果描述（一行一条）。
static func apply(run: RunState, ops: Array) -> Array[String]:
	var out: Array[String] = []
	for op: Dictionary in ops:
		out.append_array(_op(run, op))
	return out


static func _op(run: RunState, o: Dictionary) -> Array[String]:
	var out: Array[String] = []
	match String(o.op):
		"sap":
			var n := int(o.n)
			run.sap = maxi(0, run.sap + n)
			out.append(("养分 +%d" if n >= 0 else "养分 %d") % n)
		"sap_half":
			var lost := run.sap / 2
			run.sap -= lost
			out.append("失去 %d 养分" % lost)
		"heat":
			run.heat += int(o.n)
			out.append("火候 +%d" % int(o.n))
		"add_card":
			for i in int(o.get("count", 1)):
				var id: StringName = StringName(o.id) if o.has("id") else _pick_card(run, String(o.get("pick", "random")))
				if id != &"":
					run.deck.append(id)
					out.append("得到%s（%s）" % [Cards.get_def(id).display_name, Cards.get_def(id).desc])
		"remove_basic":
			for i in int(o.n):
				var t := _find_basic(run)
				if t == &"":
					break
				_remove_one(run, t)
				out.append("删去%s" % Cards.get_def(t).display_name)
		"transform":
			for i in int(o.n):
				var t := _find_basic(run)
				var nid := _pick_card(run, "top")
				for _try in 6:
					if nid != t:
						break
					nid = _pick_card(run, "top")
				if t == &"" or nid == &"" or nid == t:
					break
				_remove_one(run, t)
				run.deck.append(nid)
				out.append("%s变成了%s（%s）" % [Cards.get_def(t).display_name, Cards.get_def(nid).display_name, Cards.get_def(nid).desc])
		"duplicate":
			var best := &""
			for t in run.deck_counts():
				var d := Cards.get_def(t)
				if t == DEBT or d.category == CardDef.Category.PRUNE:
					continue
				if best == &"" or d.rarity > Cards.get_def(best).rarity or (d.rarity == Cards.get_def(best).rarity and String(t) < String(best)):
					best = t
			if best != &"":
				run.deck.append(best)
				out.append("复制了%s" % Cards.get_def(best).display_name)
		"refine_random":
			for i in int(o.n):
				var cand: Array[StringName] = []
				for t in run.deck_counts():
					if not Cards.get_def(t).is_plus() and t != DEBT:
						cand.append(t)
				if cand.is_empty():
					break
				cand.sort()
				var t: StringName = cand[run.rng.randi_range(0, cand.size() - 1)]
				var plus := StringName(String(t) + "+")
				for pile: Array[StringName] in [run.deck, run.discard, run.exhausted, run.hand]:
					var k := pile.find(t)
					if k >= 0:
						pile[k] = plus
						break
				out.append("精炼了%s" % Cards.get_def(t).display_name)
		"relic":
			var pool := run._relic_pool()
			if pool.is_empty() or run.relics_full():
				run.sap += 8
				out.append("器物槽已满，改得 8 养分")
			else:
				var r: StringName = pool[run.rng.randi_range(0, pool.size() - 1)]
				run.relics.append(r)
				out.append("得到器物：%s（%s）" % [Cards.relic(r).display_name, Cards.relic(r).desc])
		"lose_relic":
			if not run.relics.is_empty():
				var cheap := 0
				for i in run.relics.size():
					if Cards.relic(run.relics[i]).price < Cards.relic(run.relics[cheap]).price:
						cheap = i
				out.append("交出了器物：%s" % Cards.relic(run.relics[cheap]).display_name)
				run.relics.remove_at(cheap)
		"market_discount":
			run.market_discount = 0.5
			out.append("下次集市的牌和器物半价")
		"transplants":
			run.bonus_transplants += int(o.n)
			out.append("下一季第一回合额外移栽 %d 次" % int(o.n))
		"mark":
			var m := StringName(o.m)
			var res := run.preview()
			var best_k := Vector2i.ZERO
			var best_v := -1
			for n: TreeNode in run.tree.nodes.values():
				if n.is_seed() or n.marks.has(m):
					continue
				var v: int = res.contrib.get(n.key, res.out.get(n.key, 0))
				if v > best_v:
					best_v = v
					best_k = n.key
			if best_v >= 0:
				run.tree.at(best_k).marks.append(m)
				out.append("给%s刻上「%s」" % [Cards.get_def(run.tree.at(best_k).type).display_name, Rules.mark_name(m)])
		"burn":
			var tips := run._vulnerable_tips()
			var set := {}
			for t in tips.slice(0, int(o.n)):
				set[t.key] = true
			if not set.is_empty():
				run._remove_to_discard(set)
				out.append("烧掉了 %d 个末梢" % set.size())
		"age":
			var nodes: Array[TreeNode] = []
			for n: TreeNode in run.tree.sorted():
				if not n.is_seed():
					nodes.append(n)
			run.shuffle(nodes)
			for n in nodes.slice(0, 3):
				n.age += int(o.n)
			if not nodes.is_empty():
				out.append("%d 张牌成熟 +%d" % [mini(3, nodes.size()), int(o.n)])
		"land":
			var t := Land.Type.FERTILE if String(o.t) == "fertile" else Land.SPECIALS[run.rng.randi_range(0, Land.SPECIALS.size() - 1)]
			var added := Land.scatter(run.tree, run.rng, {t: int(o.n)})
			out.append("%d 块地变成了%s" % [added.size(), Land.name_of(t)])
		"clear_rock":
			var rocks: Array[Vector2i] = []
			for c in run.tree.land:
				if run.tree.land[c] == Land.Type.ROCK:
					rocks.append(c)
			rocks.sort()
			for c in rocks.slice(0, int(o.n)):
				run.tree.land.erase(c)
			out.append("清除了 %d 块岩石" % mini(int(o.n), rocks.size()))
		"gamble":
			if run.rng.randf() < float(o.p):
				out.append("运气不错！")
				out.append_array(apply(run, o.win))
			else:
				out.append("什么也没发生。")
				out.append_array(apply(run, o.lose))
	return out


## 按规则挑一张牌：random 普通随机；rare_top 主流派稀有；legendary 传说；family:x 指定流派；rare_gear 等。
static func _pick_card(run: RunState, pick: String) -> StringName:
	var pool := run.card_pool()
	var top := run.top_families(1)
	var cand: Array[StringName] = []
	for id in pool:
		var d := Cards.get_def(id)
		var ok := true
		match pick:
			"random":
				ok = d.rarity == 0
			"rare_top":
				ok = d.rarity >= 1 and (top.is_empty() or d.has_family(top[0]))
			"legendary":
				ok = d.rarity == 2
			"top":
				ok = (top.is_empty() or d.has_family(top[0])) and d.category != CardDef.Category.PRUNE
			_:
				if pick.begins_with("family:"):
					ok = d.has_family(StringName(pick.substr(7)))
				elif pick.begins_with("rare_"):
					ok = d.rarity >= 1 and d.has_family(StringName(pick.substr(5)))
		if ok:
			cand.append(id)
	if cand.is_empty():
		cand = pool
	if cand.is_empty():
		return &""
	return cand[run.rng.randi_range(0, cand.size() - 1)]


static func _find_basic(run: RunState) -> StringName:
	var dc := run.deck_counts()
	for t in BASICS:
		if dc.has(t):
			return t
	return &""


static func _remove_one(run: RunState, t: StringName) -> void:
	for pile: Array[StringName] in [run.deck, run.discard, run.exhausted]:
		var i := pile.find(t)
		if i >= 0:
			pile.remove_at(i)
			return
	var h := run.hand.find(t)
	if h >= 0:
		run._remove_hand(h)
