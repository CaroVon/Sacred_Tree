class_name RunState
extends RefCounted
## 一局游戏的完整状态与所有玩家行动。不依赖任何节点，可在无头模式下驱动（测试、平衡模拟）。
## 流程：每年 春→夏→秋→冬→天灾季；每季达标（或提前收获）后选牌→集市→下一季；
## 天灾季达标后选器物→集市→下一年（牌桌外扩一圈）。

enum Phase { PLAY, REWARD, RELIC, MARKET, LOST, WON, DISCARD, EVENT }

const SAVE_VERSION := 3

signal changed
signal logged(text: String)

var rng := RandomNumberGenerator.new()
var seed_value: int = 0
## 启程者与本局允许出现的流派（空 = 全部）。
var starter: StringName = &"gardener"
var families_allowed: Array[StringName] = []
var year: int = 1
var season: int = 1
var turn: int = 1
var score: int = 0
var sap: int = 0
var tree: TreeModel
var deck: Array[StringName] = []
var discard: Array[StringName] = []
var hand: Array[StringName] = []
## 与 hand 平行：为真表示这张牌是本回合剪下/退回的，下回合才能打出。
var hand_fresh: Array[bool] = []
## 燃尽的牌：本季移出，季初回到牌组。
var exhausted: Array[StringName] = []
var plays: int = Rules.PLAYS
var prunes: int = Rules.PRUNES
var transplants: int = Rules.TRANSPLANTS
var phase: Phase = Phase.PLAY
var reward_options: Array[StringName] = []
var relic_options: Array[StringName] = []
var relics: Array[StringName] = []
## 本年的天灾，以及已经出现过的天灾（尽量不重复）。
var calamity: StringName = &""
var seen_calamities: Array[StringName] = []
## 集市里本次可买的牌、器物（买走后从列表中移除）。
var market_cards: Array[StringName] = []
var market_relics: Array[StringName] = []
## 落叶等效果：下次脉动所有末梢的加成。
var next_tip_bonus: int = 0
## 熔炉流派：火候（整局累积）、累计燃烧牌数、下次脉动的总分倍率（余烬）。
var heat: int = 0
var burned_total: int = 0
var next_total_mult: float = 1.0
## 商会流派：本局在集市累计花费的养分（账本）。
var spent_total: int = 0
## 最近一次封存释放的总量（界面演出用，不存档）。
var last_release: int = 0
## 平衡模拟用：不因未达标而失败（不存档）。
var ignore_targets: bool = false
var last_pulse: Pulse.Result
var log_lines: Array[String] = []


## run_seed < 0 随机；starter_id 选启程者；allowed 为已解锁的流派（空 = 全部，测试与模拟用）。
static func create(run_seed: int = -1, starter_id: StringName = &"gardener", allowed: Array = []) -> RunState:
	var s := RunState.new()
	if run_seed < 0:
		s.rng.randomize()
		run_seed = s.rng.randi()
	s.seed_value = run_seed
	s.rng.seed = run_seed
	s.starter = starter_id
	for f in allowed:
		s.families_allowed.append(StringName(f))
	s.tree = TreeModel.create(Rules.radius_for_year(1))
	Land.scatter(s.tree, s.rng, Rules.START_LAND)
	Land.scatter(s.tree, s.rng, {Land.SPECIALS[s.rng.randi_range(0, Land.SPECIALS.size() - 1)]: 1}, 3)
	var st := Cards.starter(starter_id)
	var start_deck: Dictionary = st.deck if st and not st.deck.is_empty() else Rules.START_DECK
	for t in start_deck:
		for i in int(start_deck[t]):
			s.deck.append(StringName(t))
	if st and st.relic != &"" and Cards.relic(st.relic):
		s.relics.append(st.relic)
	s.shuffle(s.deck)
	s._pick_calamity()
	s._reset_turn()
	s.draw()
	s.add_log("神树之种落地。第一年春季开始。")
	return s


# ---------- 查询 ----------

func has_relic(id: StringName) -> bool:
	return relics.has(id)


func ctx() -> Pulse.Context:
	var c := Pulse.Context.for_season(season, year)
	if is_calamity() and calamity == &"eclipse":
		c.maturity = false
		c.eclipse = true
	if is_calamity() and calamity == &"drought":
		c.seed_out = maxi(1, c.seed_out / 2)
	c.seed_extra_port = has_relic(&"root")
	if has_relic(&"ruler"):
		c.long_depth -= 1
	if has_relic(&"beehive"):
		c.aura_extra += 2
	if has_relic(&"knife"):
		c.graft_mult *= 1.5
	if has_relic(&"dew") and turn == 1:
		c.total_mult *= 2.0
	c.tip_bonus = next_tip_bonus
	c.total_mult *= next_total_mult
	c.turn = turn
	c.turns_total = turns_this_season()
	c.sap = sap
	c.heat = heat
	c.burned_total = burned_total
	c.relic_count = relics.size()
	c.spent = spent_total
	for f in CardDef.FAMILY_NAMES:
		if has_relic(StringName("badge_" + String(f))):
			c.res_discount[f] = 1
	c.link_extra = 1 if has_relic(&"oilcan") else 0
	c.star_turn_bonus = 1 if has_relic(&"orrery") else 0
	c.pairs_any = has_relic(&"twofaced")
	c.mirror_extra = 0.05 if has_relic(&"silvering") else 0.0
	return c


## 某流派当前的共鸣层数（含徽章减免）。
func res_tier(f: StringName) -> int:
	var cnt := int(Pulse.family_counts(tree).get(f, 0))
	if cnt > 0 and has_relic(StringName("badge_" + String(f))):
		cnt += 1
	return Pulse.resonance_tier(cnt)


func preview() -> Pulse.Result:
	return Pulse.resolve(tree, ctx())


## 带逐步算式的预览（界面解释用）。
func explained(t: TreeModel = null) -> Pulse.Result:
	var c := ctx()
	c.explain = true
	return Pulse.resolve(t if t else tree, c)


## 放下第 i 张手牌到 k 之后的树（不修改当前状态）；不能放返回 null。
func tree_after_place(i: int, k: Vector2i) -> TreeModel:
	var info: Growth.Target = targets_for_hand(i).get(k)
	if info == null:
		return null
	var t := tree.copy()
	Growth.place(t, hand[i], k, info)
	return t


func target() -> int:
	var t := Rules.target(season, year)
	if is_calamity() and has_relic(&"almanac"):
		t = int(t * 0.8)
	return t


func turns_this_season() -> int:
	return Rules.turns(season) + (1 if has_relic(&"hourglass") and not is_calamity() else 0)


func is_calamity() -> bool:
	return Rules.is_calamity(season)


func season_label() -> String:
	return "第%d年 · %s%s" % [year, Rules.season_name(season), "" if is_calamity() else "季"]


func hand_limit() -> int:
	return Rules.hand_size(season) + (1 if has_relic(&"basket") else 0)


func prunes_per_turn() -> int:
	return Rules.PRUNES + (1 if has_relic(&"shears") else 0)


func plays_this_turn() -> int:
	var p := Rules.plays_per_turn(season)
	if has_relic(&"chime") and turn == turns_this_season():
		p += 1
	return p


func compost_extra() -> int:
	return 1 if has_relic(&"compost") else 0


func is_fresh(i: int) -> bool:
	return i >= 0 and i < hand_fresh.size() and hand_fresh[i]


func targets_for_hand(i: int) -> Dictionary:
	if i < 0 or i >= hand.size() or plays <= 0 or phase != Phase.PLAY or is_fresh(i):
		return {}
	if sap < Cards.get_def(hand[i]).play_cost:
		return {}
	return Growth.targets_for(tree, hand[i], ctx())


func can_play(i: int) -> bool:
	return not targets_for_hand(i).is_empty()


func can_prune() -> bool:
	return phase == Phase.PLAY and prunes > 0 and tree.size() > 1


func can_redraw() -> bool:
	return phase == Phase.PLAY and sap >= Rules.REDRAW_COST and hand_fresh.has(false)


func can_harvest() -> bool:
	return phase == Phase.PLAY and score + pending_release() >= target()


## 提前收获能拿到的养分。
func harvest_sap() -> int:
	return (turns_this_season() - turn + 1) * Rules.HARVEST_SAP_PER_TURN


func can_transplant() -> bool:
	return phase == Phase.PLAY and transplants > 0 and tree.size() > 1


## 移栽 k（连同子枝）的可选落点：新格 -> Growth.Move。
func transplant_targets(k: Vector2i) -> Dictionary:
	if not can_transplant():
		return {}
	return Growth.transplant_targets(tree, k, ctx())


func tree_after_transplant(k: Vector2i, to: Vector2i) -> TreeModel:
	var mv: Growth.Move = transplant_targets(k).get(to)
	if mv == null:
		return null
	var t := tree.copy()
	Growth.transplant(t, k, mv)
	return t


## 假装放下第 i 张手牌，返回下次脉动的总分；不能放返回 -1。
func preview_place(i: int, k: Vector2i) -> int:
	var info: Growth.Target = targets_for_hand(i).get(k)
	if info == null:
		return -1
	var t := tree.copy()
	Growth.place(t, hand[i], k, info)
	return Pulse.resolve(t, ctx()).total


## 返回 {count, gain, total}；不能剪返回空字典。
func preview_prune(k: Vector2i) -> Dictionary:
	if not can_prune() or k == TreeModel.SEED_KEY or not tree.has(k):
		return {}
	var set := Growth.subtree(tree, k)
	var t := tree.copy()
	Growth.remove_set(t, set)
	var c := ctx()
	c.tip_bonus += Growth.prune_tip_bonus(tree, set)
	return {"count": set.size(), "gain": Growth.prune_gain(tree, set, compost_extra()), "total": Pulse.resolve(t, c).total}


# ---------- 回合内行动 ----------

func draw() -> void:
	while hand.size() < hand_limit():
		if deck.is_empty():
			if discard.is_empty():
				break
			deck = discard
			discard = []
			shuffle(deck)
		_add_hand(deck.pop_back(), false)


func _add_hand(t: StringName, fresh: bool) -> void:
	hand.append(t)
	hand_fresh.append(fresh)


func _remove_hand(i: int) -> StringName:
	var t := hand[i]
	hand.remove_at(i)
	hand_fresh.remove_at(i)
	return t


## 手牌超过上限时进入弃牌阶段。
func _check_overflow() -> void:
	if phase == Phase.PLAY and hand.size() > hand_limit():
		phase = Phase.DISCARD
		add_log("手牌超过上限 %d，请弃掉 %d 张" % [hand_limit(), hand.size() - hand_limit()])


func overflow() -> int:
	return maxi(0, hand.size() - hand_limit())


## 弃牌阶段：弃掉第 i 张手牌；降到上限后回到出牌。
func discard_card(i: int) -> bool:
	if phase != Phase.DISCARD or i < 0 or i >= hand.size():
		return false
	var t := _remove_hand(i)
	discard.append(t)
	add_log("弃掉%s" % Cards.get_def(t).display_name)
	if hand.size() <= hand_limit():
		phase = Phase.PLAY
	changed.emit()
	return true


func place(i: int, k: Vector2i) -> bool:
	var info: Growth.Target = targets_for_hand(i).get(k)
	if info == null:
		return false
	var type := hand[i]
	var before := preview().total
	Growth.place(tree, type, k, info)
	_remove_hand(i)
	plays -= 1
	sap -= Cards.get_def(type).play_cost
	add_log("放下%s：脉动预计 %d → %d" % [Cards.get_def(type).display_name, before, preview().total])
	changed.emit()
	return true


## 剪掉一张牌和它后面的所有枝，返回得到的养分；失败返回 -1。
## 剪下的牌直接回到手牌（下回合才能打出），燃尽的牌本季移出；超过手牌上限则进入弃牌阶段。
func prune(k: Vector2i) -> int:
	if not can_prune() or k == TreeModel.SEED_KEY or not tree.has(k):
		return -1
	var set := Growth.subtree(tree, k)
	var gain := Growth.prune_gain(tree, set, compost_extra())
	next_tip_bonus += Growth.prune_tip_bonus(tree, set)
	var pr := preview()
	var release_x := 0.0
	for x in set:
		var d := tree.at(x).def()
		gain += int(floor(int(pr.out.get(x, 0)) * d.prune_out_sap))
		release_x = maxf(release_x, d.release_on_prune)
	if release_x > 0.0:
		var got := release_seals(release_x)
		if got > 0:
			add_log("解印：立即释放封存 %d" % got)
	_remove_to_hand(set)
	sap += gain
	prunes -= 1
	add_log("修剪 %d 张，得 %d 养分；剪下的牌回到手牌（下回合可用）" % [set.size(), gain])
	_check_overflow()
	changed.emit()
	return gain


## 移栽：把 k 连同子枝挪到 to。
func transplant(k: Vector2i, to: Vector2i) -> bool:
	var mv: Growth.Move = transplant_targets(k).get(to)
	if mv == null:
		return false
	var nm := Cards.get_def(tree.at(k).type).display_name
	var n := Growth.subtree(tree, k).size()
	Growth.transplant(tree, k, mv)
	transplants -= 1
	add_log("移栽%s（共 %d 张）" % [nm, n])
	changed.emit()
	return true


## 提前收获：本季已达标，直接结束本季，剩余回合折算养分。
func harvest() -> bool:
	if not can_harvest():
		return false
	var gain := harvest_sap()
	sap += gain
	if has_relic(&"timebox"):
		var left := turns_this_season() - turn + 1
		for n: TreeNode in tree.nodes.values():
			if n.stored > 0:
				n.sealed += left
	add_log("提前收获：剩余 %d 回合，得 %d 养分" % [turns_this_season() - turn + 1, gain])
	release_seals()
	if Rules.is_winter(season):
		wither(Rules.WINTER_WITHER)
	_end_season()
	changed.emit()
	return true


## 重抽：弃掉所有可用的手牌（刚剪下的保留），重新补满。
func redraw() -> bool:
	if not can_redraw():
		return false
	sap -= Rules.REDRAW_COST
	for i in range(hand.size() - 1, -1, -1):
		if not hand_fresh[i]:
			discard.append(_remove_hand(i))
	draw()
	add_log("花 %d 养分重抽手牌" % Rules.REDRAW_COST)
	changed.emit()
	return true


## 结束回合并脉动，返回本次脉动结果。
func end_turn() -> Pulse.Result:
	if phase != Phase.PLAY:
		return null
	var res := preview()
	last_pulse = res
	score += res.total
	next_tip_bonus = 0
	next_total_mult = 1.0
	sap -= mini(sap, res.sap_cost)
	sap += res.sap_gain
	if res.interest > 0.0:
		sap += mini(int(floor(sap * res.interest)), 5 * res.interest_cards)
	heat += res.heat_gain
	if has_relic(&"piggy"):
		sap += mini(3, sap / 5)
	for k in res.stores:
		var sn := tree.at(k)
		if sn:
			sn.stored += int(res.stores[k])
			sn.sealed += 1
	_altars(res)
	for n: TreeNode in tree.nodes.values():
		n.age += 1
	add_log("%s第 %d 回合脉动：%d 个末梢，得 %d" % [season_label(), turn, res.tip_list.size(), res.total])
	if has_relic(&"windkey"):
		for n: TreeNode in tree.nodes.values():
			n.age += 1
	if not res.patterns.is_empty():
		add_log("牌型：" + "、".join(res.patterns.map(func(p): return p.label)))
	if is_calamity() and calamity == &"pests":
		_pests()
	if is_calamity() and calamity == &"wildfire":
		_wildfire()
	if is_calamity() and calamity == &"gale":
		_gale()
	turn += 1
	if turn > turns_this_season():
		release_seals()
		if Rules.is_winter(season):
			wither(Rules.WINTER_WITHER)
		_end_season()
	else:
		for i in hand_fresh.size():
			hand_fresh[i] = false
		_reset_turn()
		draw()
		_check_overflow()
	changed.emit()
	return res


func _reset_turn() -> void:
	plays = plays_this_turn()
	prunes = prunes_per_turn()
	transplants = Rules.TRANSPLANTS + (1 if has_relic(&"cart") else 0)


# ---------- 冬季与天灾 ----------

func _vulnerable_tips() -> Array[TreeNode]:
	var out: Array[TreeNode] = []
	for t in tree.tips():
		if not t.is_seed() and not is_tough_at(t):
			out.append(t)
	return out


## 坚韧：年轮、天生坚韧、耐火砖下的熔炉牌，或挨着护符。
func is_tough_at(n: TreeNode) -> bool:
	if n.is_tough():
		return true
	if not n.is_seed() and has_relic(&"firebrick") and n.def().has_family(&"forge"):
		return true
	for nb in Hex.neighbors(n.key):
		var m := tree.at(nb)
		if m and not m.is_seed() and m.def().aura_tough:
			return true
	return false


## 现在释放会得到多少（不修改状态）。
func pending_release(extra_mult: float = 1.0) -> int:
	var bonus: float = Pulse.SEAL_RES[res_tier(&"seal")] + (0.25 if has_relic(&"signet") else 0.0)
	var total := 0
	for n: TreeNode in tree.nodes.values():
		if n.stored <= 0:
			continue
		var rate := n.def().seal_rate + bonus
		for nb in Hex.neighbors(n.key):
			var m := tree.at(nb)
			if m and not m.is_seed():
				rate += m.def().release_adj_bonus
		total += int(floor(n.stored * (1.0 + rate * n.sealed) * extra_mult))
	return total


## 释放牌桌上全部封存：存量 ×(1 + 每次封存的倍率 × 次数)，计入本季累计。返回释放量。
func release_seals(extra_mult: float = 1.0) -> int:
	var total := pending_release(extra_mult)
	for n: TreeNode in tree.nodes.values():
		n.stored = 0
		n.sealed = 0
	if total > 0:
		score += total
		add_log("封存释放：+%d" % total)
	last_release = total
	return total


## 献祭台：每次脉动后烧掉相邻收获最低的末梢（坚韧的除外），回到弃牌堆。
func _altars(res: Pulse.Result) -> void:
	var burned := {}
	for n: TreeNode in tree.sorted():
		if n.is_seed() or not n.def().burn_adjacent or not tree.has(n.key):
			continue
		var best := Vector2i.ZERO
		var best_v := 1 << 60
		var found := false
		for nb in Hex.neighbors(n.key):
			var m := tree.at(nb)
			if m == null or m.is_seed() or is_tough_at(m) or burned.has(nb) or not m.children.is_empty():
				continue
			var v: int = res.contrib.get(nb, 0)
			if v < best_v:
				best_v = v
				best = nb
				found = true
		if found:
			burned[best] = true
			add_log("献祭台烧掉了%s" % Cards.get_def(tree.at(best).type).display_name)
			_remove_to_discard({best: true})


## 冬季末：最老的 n 个末梢枯萎（离开牌桌，回到弃牌堆）。坚韧的牌不受影响。返回枯萎的格子。
func wither(n: int) -> Array[Vector2i]:
	var gone: Array[Vector2i] = []
	for t in _vulnerable_tips().slice(0, n):
		gone.append(t.key)
	if gone.is_empty():
		return gone
	var set := {}
	for k in gone:
		set[k] = true
	_remove_to_discard(set)
	add_log("寒冬：%d 个最老的末梢枯萎" % gone.size())
	return gone


## 虫害：脉动后随机咬掉一个末梢。
func _pests() -> void:
	var tips := _vulnerable_tips()
	if tips.is_empty():
		return
	var t := tips[rng.randi_range(0, tips.size() - 1)]
	var name := Cards.get_def(t.type).display_name
	_remove_to_hand({t.key: true})
	add_log("虫害：咬掉了%s（回到手牌）" % name)


## 山火：脉动后烧掉最老的一个末梢（回到弃牌堆，算燃料）。
func _wildfire() -> void:
	var tips := _vulnerable_tips()
	if tips.is_empty():
		return
	var name := Cards.get_def(tips[0].type).display_name
	_remove_to_discard({tips[0].key: true})
	add_log("山火：烧掉了%s" % name)


## 大风：脉动后一个随机末梢被吹到别的芽点；无处可去就吹回手牌。
func _gale() -> void:
	var tips := _vulnerable_tips()
	if tips.is_empty():
		return
	var t := tips[rng.randi_range(0, tips.size() - 1)]
	var name := Cards.get_def(t.type).display_name
	var tg := Growth.transplant_targets(tree, t.key, ctx())
	if tg.is_empty():
		_remove_to_hand({t.key: true})
		add_log("大风：把%s吹回了手牌" % name)
		return
	var keys := tg.keys()
	keys.sort()
	var to: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
	Growth.transplant(tree, t.key, tg[to])
	add_log("大风：把%s吹到了别处" % name)


## 洪水：天灾季开始时，泉眼旁的空平地一半变成泉眼。
func _flood() -> void:
	var cand: Array[Vector2i] = []
	for c in tree.land.keys():
		if tree.land[c] != Land.Type.SPRING:
			continue
		for nb in Hex.neighbors(c):
			if Hex.in_board(nb, tree.radius) and not tree.has(nb) and tree.land_at(nb) == Land.Type.PLAIN and not cand.has(nb):
				cand.append(nb)
	shuffle(cand)
	var n := cand.size() / 2
	for i in n:
		tree.land[cand[i]] = Land.Type.SPRING
	add_log("洪水：%d 块地被泉水淹没" % n)


## 雷击：劈断最长的一条枝（最深末梢往上共 3 张）。整段中有坚韧的牌则换下一条。
func _lightning() -> void:
	var tips: Array[TreeNode] = []
	for t in tree.tips():
		if not t.is_seed():
			tips.append(t)
	tips.sort_custom(func(a, b): return a.depth > b.depth if a.depth != b.depth else a.order < b.order)
	for t in tips:
		var cut := t
		while cut.depth > maxi(1, t.depth - 2) and not cut.parents.is_empty():
			cut = tree.at(cut.parents[0])
		var set := Growth.subtree(tree, cut.key)
		var safe := true
		for x in set:
			if is_tough_at(tree.at(x)):
				safe = false
		if safe:
			_remove_to_hand(set)
			add_log("雷击：劈断了 %d 张牌（回到手牌，下回合可用）" % set.size())
			_check_overflow()
			return


func _remove_to_discard(set: Dictionary) -> void:
	_burn(set)
	for x in set:
		discard.append(tree.at(x).type)
	Growth.remove_set(tree, set)


## 牌离开牌桌 = 燃料：火候 +1/张（加上牌自身的额外火候与熔炉共鸣），并记下余烬的总分倍率。
func _burn(set: Dictionary) -> void:
	if set.is_empty():
		return
	var tier := res_tier(&"forge")
	for x in set:
		var d := tree.at(x).def()
		heat += 1 + d.heat_on_burn + tier + (turn if d.heat_on_burn_turn else 0)
		if tree.at(x).marks.has(&"fireproof"):
			heat += 3
		if tree.land_at(x) == Land.Type.LAVA:
			heat += 3
		next_total_mult += d.burn_total_mult
	burned_total += set.size()
	# 铸币炉：牌桌上（未被烧掉的）每张，每烧一张牌得养分
	var mint := 0
	for n: TreeNode in tree.nodes.values():
		if not n.is_seed() and not set.has(n.key):
			mint += n.def().sap_on_burn
	sap += mint * set.size()


## 离开牌桌的牌回到手牌（标记为下回合可用）；燃尽的牌本季移出。
func _remove_to_hand(set: Dictionary) -> void:
	var list: Array[TreeNode] = []
	for x in set:
		list.append(tree.at(x))
	list.sort_custom(func(a: TreeNode, b: TreeNode): return a.order < b.order)
	_burn(set)
	for n in list:
		if n.def().exhaust_on_prune:
			exhausted.append(n.type)
		else:
			_add_hand(n.type, true)
	Growth.remove_set(tree, set)


func _pick_calamity() -> void:
	var all := Cards.calamity_ids()
	var fresh: Array[StringName] = []
	for c in all:
		if not seen_calamities.has(c):
			fresh.append(c)
	if fresh.is_empty():
		fresh = all
	calamity = fresh[rng.randi_range(0, fresh.size() - 1)]
	seen_calamities.append(calamity)


# ---------- 季末、奖励、器物 ----------

func _end_season() -> void:
	if score < target() and not ignore_targets:
		phase = Phase.LOST
		add_log("本季累计 %d，未达到目标 %d。" % [score, target()])
		return
	if is_calamity():
		sap += Rules.CALAMITY_CLEAR_SAP
		add_log("度过了%s，得 %d 养分" % [Cards.calamity(calamity).display_name, Rules.CALAMITY_CLEAR_SAP])
		if year == Rules.YEARS:
			phase = Phase.WON
			add_log("三年过去，神树成年。")
			return
		phase = Phase.RELIC
		var pool := _relic_pool()
		shuffle(pool)
		relic_options.assign(pool.slice(0, Rules.RELIC_CHOICES))
		if relic_options.is_empty():
			_open_market()
		return
	sap += Rules.SEASON_CLEAR_SAP
	phase = Phase.REWARD
	var cards := card_pool()
	var n := Rules.REWARD_CHOICES + (1 if has_relic(&"seedbag") else 0)
	reward_options.assign(roll_cards(cards, n))
	if has_relic(&"compass"):
		shuffle(cards)
		_compass_reward(cards)


# ---------- 构筑：卡池、抽选引导、精炼 ----------

## 本局可出现的牌：所有流派都已解锁的牌（木总是可用）。
func card_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Cards.pool_ids():
		if family_allowed(Cards.get_def(id)):
			out.append(id)
	return out


func family_allowed(d: CardDef) -> bool:
	if families_allowed.is_empty():
		return true
	for f in d.families():
		if f != &"wood" and not families_allowed.has(f):
			return false
	return true


## 牌组里牌数最多的新流派（最多 k 个）。
func top_families(k: int = 2) -> Array[StringName]:
	var counts := {}
	var dc := deck_counts()
	for t in dc:
		for f in Cards.get_def(t).family:
			if f != &"wood":
				counts[f] = int(counts.get(f, 0)) + int(dc[t])
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b] if counts[a] != counts[b] else String(a) < String(b))
	var out: Array[StringName] = []
	for f in keys.slice(0, k):
		out.append(f)
	return out


## 抽选权重：稀有度（普通 1、稀有 0.45、传说 0.15）× 已有主流派 ×Rules.FAMILY_BIAS。
func card_weight(id: StringName, top: Array[StringName]) -> float:
	var d := Cards.get_def(id)
	var w: float = [1.0, 0.45, 0.15][clampi(d.rarity, 0, 2)]
	for f in d.families():
		if top.has(f):
			return w * Rules.FAMILY_BIAS
	return w


## 按权重不放回地抽 n 张；如果全都来自主流派，最后一张换成别的流派（保留跨流派的机会）。
func roll_cards(pool: Array[StringName], n: int) -> Array[StringName]:
	var top := top_families()
	var cand := pool.duplicate()
	var out: Array[StringName] = []
	while out.size() < n and not cand.is_empty():
		var total := 0.0
		for id in cand:
			total += card_weight(id, top)
		var r := rng.randf() * total
		var pick := cand.size() - 1
		for i in cand.size():
			r -= card_weight(cand[i], top)
			if r <= 0.0:
				pick = i
				break
		out.append(cand[pick])
		cand.remove_at(pick)
	if not top.is_empty() and out.size() >= 2 and out.all(func(id): return card_weight(id, top) > 1.0):
		var off: Array[StringName] = []
		for id in cand:
			if card_weight(id, top) <= 1.0:
				off.append(id)
		if not off.is_empty():
			out[out.size() - 1] = off[rng.randi_range(0, off.size() - 1)]
	return out


func can_refine(t: StringName) -> bool:
	var d := Cards.get_def(t)
	return phase == Phase.MARKET and d != null and not d.is_plus() and deck_counts().has(t) \
		and sap >= service_price(Rules.REFINE_PRICE)


## 精炼：把一张牌换成它的“+”版（每张牌只能精炼一次）。
func refine(t: StringName) -> bool:
	if not can_refine(t):
		return false
	var plus := StringName(String(t) + "+")
	for pile: Array[StringName] in [deck, discard, exhausted, hand]:
		var i := pile.find(t)
		if i >= 0:
			pile[i] = plus
			_spend(service_price(Rules.REFINE_PRICE))
			add_log("精炼%s → %s" % [Cards.get_def(t).display_name, Cards.get_def(plus).display_name])
			changed.emit()
			return true
	return false


## 罗盘：保证至少一个选项来自牌组里最多的新流派。
func _compass_reward(pool: Array) -> void:
	var counts := {}
	var dc := deck_counts()
	for t in dc:
		for f in Cards.get_def(t).family:
			if f != &"wood":
				counts[f] = int(counts.get(f, 0)) + int(dc[t])
	if counts.is_empty() or reward_options.is_empty():
		return
	var top: StringName = counts.keys()[0]
	for f in counts:
		if counts[f] > counts[top]:
			top = f
	for o in reward_options:
		if Cards.get_def(o).has_family(top):
			return
	for c in pool:
		if Cards.get_def(c).has_family(top) and not reward_options.has(c):
			reward_options[reward_options.size() - 1] = c
			return


func choose_reward(i: int) -> void:
	if phase != Phase.REWARD or i < 0 or i >= reward_options.size():
		return
	var t := reward_options[i]
	discard.append(t)
	add_log("获得%s" % Cards.get_def(t).display_name)
	_open_market()


func skip_reward() -> void:
	if phase != Phase.REWARD:
		return
	sap += Rules.SKIP_REWARD_SAP
	_open_market()


## 选器物。槽满时必须指定替换哪一个槽（被替换的器物按出售价返还养分）。
func choose_relic(i: int, replace: int = -1) -> bool:
	if phase != Phase.RELIC or i < 0 or i >= relic_options.size():
		return false
	if relics_full():
		if replace < 0 or replace >= relics.size():
			return false
		_sell_relic_at(replace)
	var r := relic_options[i]
	relics.append(r)
	add_log("获得器物：%s" % Cards.relic(r).display_name)
	_open_market()
	return true


func skip_relic() -> void:
	if phase != Phase.RELIC:
		return
	sap += Rules.SKIP_REWARD_SAP
	_open_market()


func _collect_cards() -> void:
	discard.append_array(hand)
	hand.clear()
	hand_fresh.clear()
	deck.append_array(discard)
	deck.append_array(exhausted)
	discard.clear()
	exhausted.clear()
	shuffle(deck)


func _next_season() -> void:
	season += 1
	_start_season()
	add_log("%s开始，目标 %d" % [season_label(), target()])
	if is_calamity():
		var cd := Cards.calamity(calamity)
		add_log("天灾：%s——%s" % [cd.display_name, cd.desc])
		if calamity == &"lightning":
			_lightning()
		elif calamity == &"flood":
			_flood()
	changed.emit()


func _start_season() -> void:
	turn = 1
	score = 0
	if has_relic(&"tongs"):
		heat += 5
	phase = Phase.PLAY
	reward_options.clear()
	relic_options.clear()
	_collect_cards()
	_reset_turn()
	draw()


# ---------- 集市 ----------

func _open_market() -> void:
	phase = Phase.MARKET
	relic_options.clear()
	reward_options.clear()
	market_cards.assign(roll_cards(card_pool(), Rules.MARKET_CARD_OFFERS))
	market_relics.clear()
	var rp := _relic_pool()
	shuffle(rp)
	market_relics.assign(rp.slice(0, Rules.MARKET_RELIC_OFFERS + (1 if has_relic(&"lantern") else 0)))
	add_log("进入集市")
	changed.emit()


## 集市服务的实际价格（天平：便宜 1，最低 1）。
func service_price(base: int) -> int:
	return maxi(1, base - (1 if has_relic(&"scales") else 0))


## 在集市花养分（账本记账）。
func _spend(n: int) -> void:
	sap -= n
	spent_total += n


func _relic_pool() -> Array[StringName]:
	var pool: Array[StringName] = []
	for r in Cards.relic_ids():
		if not relics.has(r) and not market_relics.has(r):
			pool.append(r)
	return pool


func relics_full() -> bool:
	return relics.size() >= Rules.RELIC_SLOTS


func relic_sell_price(id: StringName) -> int:
	return int(floor(Cards.relic(id).price * Rules.RELIC_SELL_RATIO))


func can_buy_relic(i: int) -> bool:
	return phase == Phase.MARKET and i >= 0 and i < market_relics.size() and not relics_full() \
		and sap >= Cards.relic(market_relics[i]).price


func buy_relic(i: int) -> bool:
	if not can_buy_relic(i):
		return false
	var r := market_relics[i]
	_spend(Cards.relic(r).price)
	relics.append(r)
	market_relics.remove_at(i)
	add_log("买下器物%s（-%d）" % [Cards.relic(r).display_name, Cards.relic(r).price])
	changed.emit()
	return true


## 出售第 i 个器物（集市中，或选器物时腾槽）。
func sell_relic(i: int) -> bool:
	if (phase != Phase.MARKET and phase != Phase.RELIC) or i < 0 or i >= relics.size():
		return false
	_sell_relic_at(i)
	changed.emit()
	return true


func _sell_relic_at(i: int) -> void:
	var r := relics[i]
	var gain := relic_sell_price(r)
	sap += gain
	relics.remove_at(i)
	add_log("卖出器物%s（+%d）" % [Cards.relic(r).display_name, gain])


func deck_counts() -> Dictionary:
	var out := {}
	for pile in [deck, discard, hand, exhausted]:
		for t in pile:
			out[t] = int(out.get(t, 0)) + 1
	return out


func buy_card(i: int) -> bool:
	if phase != Phase.MARKET or i < 0 or i >= market_cards.size():
		return false
	var t := market_cards[i]
	var price := Cards.get_def(t).price
	if sap < price:
		return false
	_spend(price)
	deck.append(t)
	market_cards.remove_at(i)
	add_log("买下%s（-%d）" % [Cards.get_def(t).display_name, price])
	changed.emit()
	return true


func remove_card(t: StringName) -> bool:
	if phase != Phase.MARKET or sap < service_price(Rules.REMOVE_CARD_PRICE):
		return false
	for pile: Array[StringName] in [deck, discard, exhausted]:
		var i := pile.find(t)
		if i >= 0:
			pile.remove_at(i)
			_spend(service_price(Rules.REMOVE_CARD_PRICE))
			add_log("删去一张%s（-%d）" % [Cards.get_def(t).display_name, service_price(Rules.REMOVE_CARD_PRICE)])
			changed.emit()
			return true
	var h := hand.find(t)
	if h >= 0:
		_remove_hand(h)
		_spend(service_price(Rules.REMOVE_CARD_PRICE))
		add_log("删去一张%s（-%d）" % [Cards.get_def(t).display_name, service_price(Rules.REMOVE_CARD_PRICE)])
		changed.emit()
		return true
	return false


func can_mark(mark: StringName, k: Vector2i) -> bool:
	var n := tree.at(k)
	return phase == Phase.MARKET and n != null and not n.is_seed() and not n.marks.has(mark) \
		and sap >= service_price(int(Rules.MARKS[mark].price))


func buy_mark(mark: StringName, k: Vector2i) -> bool:
	if not can_mark(mark, k):
		return false
	var n := tree.at(k)
	_spend(service_price(int(Rules.MARKS[mark].price)))
	n.marks.append(mark)
	add_log("给%s刻上年轮「%s」" % [Cards.get_def(n.type).display_name, Rules.mark_name(mark)])
	changed.emit()
	return true


func can_add_port(k: Vector2i, dir: int) -> bool:
	var n := tree.at(k)
	return phase == Phase.MARKET and n != null and not n.is_seed() and sap >= service_price(Rules.PORT_PRICE) \
		and n.extra_ports.size() < Rules.MAX_EXTRA_PORTS and Growth.free_port_dirs(n).has(dir)


## 芽点服务：给 k 处的牌在 dir 方向加一个芽点。
func add_port(k: Vector2i, dir: int) -> bool:
	if not can_add_port(k, dir):
		return false
	var n := tree.at(k)
	_spend(service_price(Rules.PORT_PRICE))
	n.extra_ports.append(dir)
	add_log("给%s加了一个芽点（-%d）" % [Cards.get_def(n.type).display_name, service_price(Rules.PORT_PRICE)])
	changed.emit()
	return true


func can_clear_rock(k: Vector2i) -> bool:
	return phase == Phase.MARKET and tree.land_at(k) == Land.Type.ROCK and sap >= service_price(Rules.CLEAR_ROCK_PRICE)


func clear_rock(k: Vector2i) -> bool:
	if not can_clear_rock(k):
		return false
	_spend(service_price(Rules.CLEAR_ROCK_PRICE))
	tree.land.erase(k)
	add_log("清除了一块岩石（-%d）" % service_price(Rules.CLEAR_ROCK_PRICE))
	changed.emit()
	return true


func can_make_fertile(k: Vector2i) -> bool:
	return phase == Phase.MARKET and Hex.in_board(k, tree.radius) and k != TreeModel.SEED_KEY \
		and tree.land_at(k) == Land.Type.PLAIN and sap >= service_price(Rules.MAKE_FERTILE_PRICE)


func make_fertile(k: Vector2i) -> bool:
	if not can_make_fertile(k):
		return false
	_spend(service_price(Rules.MAKE_FERTILE_PRICE))
	tree.land[k] = Land.Type.FERTILE
	add_log("把一块地养成沃土（-%d）" % service_price(Rules.MAKE_FERTILE_PRICE))
	changed.emit()
	return true


## 离开集市：天灾季之后进入新的一年（牌桌外扩一圈），否则进入下一季。
func leave_market() -> void:
	if phase != Phase.MARKET:
		return
	market_cards.clear()
	market_relics.clear()
	if not is_calamity():
		_next_season()
		return
	year += 1
	season = 1
	_pick_calamity()
	var old_r := tree.radius
	tree.radius = maxi(tree.radius, Rules.radius_for_year(year))
	var added := Land.scatter(tree, rng, Rules.YEARLY_LAND)
	if tree.radius > old_r:
		added.append_array(Land.scatter(tree, rng, Rules.RING_LAND, old_r + 1))
		var sp := Land.SPECIALS.duplicate()
		shuffle(sp)
		added.append_array(Land.scatter(tree, rng, {sp[0]: 1, sp[1]: 1}, old_r + 1))
	_start_season()
	add_log("第%d年春季开始，目标 %d；牌桌扩到半径 %d，新长出 %d 块地" % [year, target(), tree.radius, added.size()])
	changed.emit()


# ---------- 工具 ----------

func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func add_log(text: String) -> void:
	log_lines.push_front(text)
	if log_lines.size() > 60:
		log_lines.resize(60)
	logged.emit(text)


# ---------- 存档 ----------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "seed": seed_value, "rng_state": str(rng.state),
		"starter": String(starter), "families_allowed": _names(families_allowed),
		"year": year, "season": season, "turn": turn, "score": score, "sap": sap,
		"tree": tree.to_dict(),
		"deck": _names(deck), "discard": _names(discard), "hand": _names(hand),
		"hand_fresh": hand_fresh.duplicate(), "exhausted": _names(exhausted),
		"plays": plays, "prunes": prunes, "transplants": transplants, "phase": phase,
		"reward_options": _names(reward_options), "relic_options": _names(relic_options),
		"relics": _names(relics), "calamity": String(calamity), "seen_calamities": _names(seen_calamities),
		"market_cards": _names(market_cards), "market_relics": _names(market_relics),
		"next_tip_bonus": next_tip_bonus,
		"heat": heat, "burned_total": burned_total, "next_total_mult": next_total_mult,
		"spent_total": spent_total,
		"log": log_lines.duplicate(),
	}


static func from_dict(d: Dictionary) -> RunState:
	var s := RunState.new()
	s.seed_value = int(d.seed)
	s.rng.seed = s.seed_value
	s.rng.state = String(d.rng_state).to_int()
	s.starter = StringName(d.get("starter", "gardener"))
	s.families_allowed = _ids(d.get("families_allowed", []))
	s.year = int(d.year)
	s.season = int(d.season)
	s.turn = int(d.turn)
	s.score = int(d.score)
	s.sap = int(d.sap)
	s.tree = TreeModel.from_dict(d.tree)
	s.deck = _ids(d.deck)
	s.discard = _ids(d.discard)
	s.hand = _ids(d.hand)
	for f in d.get("hand_fresh", []):
		s.hand_fresh.append(bool(f))
	while s.hand_fresh.size() < s.hand.size():
		s.hand_fresh.append(false)
	s.exhausted = _ids(d.get("exhausted", []))
	s.plays = int(d.plays)
	s.prunes = int(d.prunes)
	s.transplants = int(d.get("transplants", Rules.TRANSPLANTS))
	s.phase = int(d.phase) as Phase
	s.reward_options = _ids(d.reward_options)
	s.relic_options = _ids(d.relic_options)
	s.relics = _ids(d.relics)
	s.calamity = StringName(d.calamity)
	s.seen_calamities = _ids(d.seen_calamities)
	s.market_cards = _ids(d.market_cards)
	s.market_relics = _ids(d.get("market_relics", []))
	s.next_tip_bonus = int(d.next_tip_bonus)
	s.heat = int(d.get("heat", 0))
	s.burned_total = int(d.get("burned_total", 0))
	s.next_total_mult = float(d.get("next_total_mult", 1.0))
	s.spent_total = int(d.get("spent_total", 0))
	for l in d.get("log", []):
		s.log_lines.append(String(l))
	return s


static func _names(a: Array[StringName]) -> Array:
	return a.map(func(x): return String(x))


static func _ids(a: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for x in a:
		out.append(StringName(x))
	return out
