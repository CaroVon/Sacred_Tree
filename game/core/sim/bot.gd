class_name Bot
extends RefCounted
## 平衡测试用的自动玩家。
## GREEDY：只看眼前一步，选让下次脉动最高的放法；不修剪、不规划（对应设计文档里的贪心基线）。
## PLANNER：放置时兼顾留给以后的芽点，卡住时修剪，选奖励/器物/集市有偏好。

enum Policy { GREEDY, PLANNER }

const CARD_PREF: Array[StringName] = [
	&"gold", &"vine", &"twinvine", &"fruit", &"tri", &"fork", &"heartwood", &"burl", &"palm",
	&"side", &"shoot", &"oak", &"node", &"nectar", &"pod", &"bud", &"stem", &"flower", &"moss",
	&"berry", &"curl", &"leaf", &"rot", &"dead",
]
const RELIC_PREF: Array[StringName] = [
	&"root", &"dew", &"knife", &"chime", &"basket", &"shears", &"beehive", &"ruler", &"seedbag", &"compost",
]
## 规划者愿意为一个空芽点付出的分数（以“当前平均末梢收获”为单位）。
const PORT_WEIGHT := 0.6

var policy: Policy = Policy.GREEDY
## 主流派（空 = 不限）：选牌、买牌时优先这个流派。
var focus: StringName = &""


static func make(p: Policy, focus_family: StringName = &"") -> Bot:
	var b := Bot.new()
	b.policy = p
	b.focus = focus_family
	return b


# ---------- 一整局 ----------

## 跑完一局。ignore_targets 为真时不会因未达标而失败，用来测量每季的得分分布。
## 返回 {won, year, season, stages: [{year, season, score, target, passed}]}
func run_game(run_seed: int, ignore_targets: bool = false) -> Dictionary:
	var s := RunState.create(run_seed)
	s.ignore_targets = ignore_targets
	var stages := []
	var guard := 0
	while s.phase != RunState.Phase.LOST and s.phase != RunState.Phase.WON:
		guard += 1
		if guard > 1000:
			break
		match s.phase:
			RunState.Phase.PLAY:
				var y := s.year
				var se := s.season
				if not ignore_targets and s.can_harvest():
					stages.append({"year": y, "season": se, "score": s.score,
						"target": Rules.target(se, y), "passed": true})
					s.harvest()
					continue
				play_turn(s)
				if s.phase == RunState.Phase.DISCARD:
					continue
				s.end_turn()
				if s.phase != RunState.Phase.PLAY and s.phase != RunState.Phase.DISCARD:
					stages.append({"year": y, "season": se, "score": s.score,
						"target": Rules.target(se, y), "passed": s.score >= Rules.target(se, y)})
			RunState.Phase.DISCARD:
				_discard(s)
			RunState.Phase.REWARD:
				_choose_reward(s)
			RunState.Phase.RELIC:
				_choose_relic(s)
			RunState.Phase.MARKET:
				_shop(s)
				s.leave_market()
	return {"won": s.phase == RunState.Phase.WON, "year": s.year, "season": s.season, "stages": stages}


# ---------- 回合 ----------

func play_turn(s: RunState) -> void:
	while s.plays > 0 and s.phase == RunState.Phase.PLAY:
		var best := _best_placement(s)
		if best.is_empty():
			if policy == Policy.PLANNER and _unstick(s):
				continue
			return
		if not s.place(best.i, best.k):
			return


## 对每张手牌只算一次可放位置，再逐个格子在树的副本上试放。
func _best_placement(s: RunState) -> Dictionary:
	var ctx := s.ctx()
	var best := {}
	var best_v := -INF
	var seen := {}
	for i in s.hand.size():
		var type := s.hand[i]
		if seen.has(type) or s.is_fresh(i):
			continue
		seen[type] = true
		var tg := Growth.targets_for(s.tree, type, ctx)
		for k in tg:
			var t := s.tree.copy()
			Growth.place(t, type, k, tg[k])
			var v := _value(t, ctx)
			if v > best_v:
				best_v = v
				best = {"i": i, "k": k}
	return best


func _value(t: TreeModel, ctx: Pulse.Context) -> float:
	var res := Pulse.resolve(t, ctx)
	if policy == Policy.GREEDY:
		return res.total
	var avg := float(res.total) / maxf(1.0, res.tip_list.size())
	return res.total + PORT_WEIGHT * free_ports(t, ctx) * maxf(1.0, avg)


static func free_ports(t: TreeModel, ctx: Pulse.Context) -> int:
	var n := 0
	var seen := {}
	for node: TreeNode in t.nodes.values():
		for d in Growth.ports_of(node, ctx):
			var c: Vector2i = node.key + Hex.DIRS[d]
			if not seen.has(c) and Growth.can_grow_on(t, c):
				seen[c] = true
				n += 1
	return n


## 卡住时：先试修剪（剪掉不超过 3 张、损失最小的一段），否则花养分重抽。
func _unstick(s: RunState) -> bool:
	if s.can_prune():
		var ctx := s.ctx()
		var best_k := Vector2i.ZERO
		var best_v := -INF
		for n: TreeNode in s.tree.nodes.values():
			if n.is_seed():
				continue
			var set := Growth.subtree(s.tree, n.key)
			if set.size() > 3:
				continue
			var t := s.tree.copy()
			Growth.remove_set(t, set)
			var v := _value(t, ctx) + Growth.prune_gain(s.tree, set, s.compost_extra())
			if v > best_v:
				best_v = v
				best_k = n.key
		if best_v > -INF:
			return s.prune(best_k) >= 0
	if s.can_redraw():
		return s.redraw()
	return false


# ---------- 季间选择 ----------

func _rank(list: Array[StringName], id: StringName) -> int:
	var i := list.find(id)
	return i if i >= 0 else 999


## 牌的偏好名次（越小越想要）：不在偏好表里的新牌按稀有度排；主流派的牌整体提前。
func _rank_card(id: StringName) -> int:
	var d := Cards.get_def(id)
	var r := _rank(CARD_PREF, id)
	if r == 999:
		r = 20 - d.rarity * 8
	if focus != &"" and d.has_family(focus):
		r -= 1000
	return r


func _choose_reward(s: RunState) -> void:
	var best := 0
	for i in s.reward_options.size():
		if _rank_card(s.reward_options[i]) < _rank_card(s.reward_options[best]):
			best = i
	s.choose_reward(best)


func _choose_relic(s: RunState) -> void:
	var best := 0
	for i in s.relic_options.size():
		if _rank(RELIC_PREF, s.relic_options[i]) < _rank(RELIC_PREF, s.relic_options[best]):
			best = i
	if not s.relics_full():
		s.choose_relic(best)
		return
	var worst := 0
	for i in s.relics.size():
		if _rank(RELIC_PREF, s.relics[i]) > _rank(RELIC_PREF, s.relics[worst]):
			worst = i
	if _rank(RELIC_PREF, s.relic_options[best]) < _rank(RELIC_PREF, s.relics[worst]):
		s.choose_relic(best, worst)
	else:
		s.skip_relic()


## 弃牌：先弃偏好最低的牌。
func _discard(s: RunState) -> void:
	while s.phase == RunState.Phase.DISCARD:
		var worst := 0
		for i in s.hand.size():
			if _rank_card(s.hand[i]) > _rank_card(s.hand[worst]):
				worst = i
		s.discard_card(worst)


func _shop(s: RunState) -> void:
	if policy == Policy.GREEDY:
		return
	# 删掉枯枝，再按偏好买牌，剩下的钱给收获最高的末梢刻“坚韧”（防冬季枯萎和天灾）
	while s.deck_counts().has(&"dead") and s.remove_card(&"dead"):
		pass
	for i in range(s.market_relics.size() - 1, -1, -1):
		if _rank(RELIC_PREF, s.market_relics[i]) < 6:
			s.buy_relic(i)
	var bought := true
	while bought:
		bought = false
		var best := -1
		for i in s.market_cards.size():
			var id := s.market_cards[i]
			if _rank_card(id) < 30 and s.sap >= Cards.get_def(id).price:
				if best < 0 or _rank_card(id) < _rank_card(s.market_cards[best]):
					best = i
		if best >= 0:
			bought = s.buy_card(best)
	var res := s.preview()
	var tips := res.tip_list.duplicate()
	tips.sort_custom(func(a, b): return res.contrib[a] > res.contrib[b])
	for k in tips:
		if s.can_mark(&"tough", k):
			s.buy_mark(&"tough", k)
