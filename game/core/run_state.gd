class_name RunState
extends RefCounted
## 一局游戏的完整状态与所有玩家行动。不依赖任何节点，可在无头模式下驱动（测试、平衡模拟）。
## 流程：每年 春→夏→秋→冬→天灾季；四季达标后选牌，天灾季达标后选器物并进入集市，然后进入下一年。

enum Phase { PLAY, REWARD, RELIC, MARKET, LOST, WON }

const SAVE_VERSION := 2

signal changed
signal logged(text: String)

var rng := RandomNumberGenerator.new()
var seed_value: int = 0
var year: int = 1
var season: int = 1
var turn: int = 1
var score: int = 0
var sap: int = 0
var tree: TreeModel
var deck: Array[StringName] = []
var discard: Array[StringName] = []
var hand: Array[StringName] = []
var plays: int = Rules.PLAYS
var prunes: int = Rules.PRUNES
var phase: Phase = Phase.PLAY
var reward_options: Array[StringName] = []
var relic_options: Array[StringName] = []
var relics: Array[StringName] = []
## 本年的天灾，以及已经出现过的天灾（尽量不重复）。
var calamity: StringName = &""
var seen_calamities: Array[StringName] = []
## 集市里本次可买的牌（买走后从列表中移除）。
var market_cards: Array[StringName] = []
## 落叶等效果：下次脉动所有末梢的加成。
var next_tip_bonus: int = 0
## 平衡模拟用：不因未达标而失败（不存档）。
var ignore_targets: bool = false
var last_pulse: Pulse.Result
var log_lines: Array[String] = []


static func create(run_seed: int = -1) -> RunState:
	var s := RunState.new()
	if run_seed < 0:
		s.rng.randomize()
		run_seed = s.rng.randi()
	s.seed_value = run_seed
	s.rng.seed = run_seed
	s.tree = TreeModel.create(Rules.RADIUS)
	Land.scatter(s.tree, s.rng, Rules.START_LAND)
	for t in Rules.START_DECK:
		for i in Rules.START_DECK[t]:
			s.deck.append(t)
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
	return c


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
	return Rules.target(season, year)


func turns_this_season() -> int:
	return Rules.turns(season)


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


func targets_for_hand(i: int) -> Dictionary:
	if i < 0 or i >= hand.size() or plays <= 0 or phase != Phase.PLAY:
		return {}
	return Growth.targets_for(tree, hand[i], ctx())


func can_play(i: int) -> bool:
	return not targets_for_hand(i).is_empty()


func can_prune() -> bool:
	return phase == Phase.PLAY and prunes > 0 and tree.size() > 1


func can_redraw() -> bool:
	return phase == Phase.PLAY and sap >= Rules.REDRAW_COST and not hand.is_empty()


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
		hand.append(deck.pop_back())


func place(i: int, k: Vector2i) -> bool:
	var info: Growth.Target = targets_for_hand(i).get(k)
	if info == null:
		return false
	var type := hand[i]
	var before := preview().total
	Growth.place(tree, type, k, info)
	hand.remove_at(i)
	plays -= 1
	add_log("放下%s：脉动预计 %d → %d" % [Cards.get_def(type).display_name, before, preview().total])
	changed.emit()
	return true


## 剪掉一张牌和它后面的所有枝，返回得到的养分；失败返回 -1。
func prune(k: Vector2i) -> int:
	if not can_prune() or k == TreeModel.SEED_KEY or not tree.has(k):
		return -1
	var set := Growth.subtree(tree, k)
	var gain := Growth.prune_gain(tree, set, compost_extra())
	next_tip_bonus += Growth.prune_tip_bonus(tree, set)
	_remove_to_discard(set)
	sap += gain
	prunes -= 1
	add_log("修剪 %d 张，得 %d 养分" % [set.size(), gain])
	changed.emit()
	return gain


func redraw() -> bool:
	if not can_redraw():
		return false
	sap -= Rules.REDRAW_COST
	discard.append_array(hand)
	hand.clear()
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
	for n: TreeNode in tree.nodes.values():
		n.age += 1
	add_log("%s第 %d 回合脉动：%d 个末梢，得 %d" % [season_label(), turn, res.tip_list.size(), res.total])
	if not res.patterns.is_empty():
		add_log("牌型：" + "、".join(res.patterns.map(func(p): return p.label)))
	if is_calamity() and calamity == &"pests":
		_pests()
	turn += 1
	if turn > turns_this_season():
		if Rules.is_winter(season):
			wither(Rules.WINTER_WITHER)
		_end_season()
	else:
		_reset_turn()
		draw()
	changed.emit()
	return res


func _reset_turn() -> void:
	plays = plays_this_turn()
	prunes = prunes_per_turn()


# ---------- 冬季与天灾 ----------

func _vulnerable_tips() -> Array[TreeNode]:
	var out: Array[TreeNode] = []
	for t in tree.tips():
		if not t.is_seed() and not t.marks.has(&"tough"):
			out.append(t)
	return out


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
	_remove_to_discard({t.key: true})
	add_log("虫害：咬掉了%s" % name)


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
			if tree.at(x).marks.has(&"tough"):
				safe = false
		if safe:
			_remove_to_discard(set)
			add_log("雷击：劈断了 %d 张牌" % set.size())
			return


func _remove_to_discard(set: Dictionary) -> void:
	for x in set:
		discard.append(tree.at(x).type)
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
		var pool: Array[StringName] = []
		for r in Cards.relic_ids():
			if not relics.has(r):
				pool.append(r)
		shuffle(pool)
		relic_options.assign(pool.slice(0, Rules.RELIC_CHOICES))
		if relic_options.is_empty():
			_open_market()
		return
	sap += Rules.SEASON_CLEAR_SAP
	phase = Phase.REWARD
	var cards := Cards.pool_ids()
	shuffle(cards)
	var n := Rules.REWARD_CHOICES + (1 if has_relic(&"seedbag") else 0)
	reward_options.assign(cards.slice(0, n))


func choose_reward(i: int) -> void:
	if phase != Phase.REWARD or i < 0 or i >= reward_options.size():
		return
	var t := reward_options[i]
	discard.append(t)
	add_log("获得%s" % Cards.get_def(t).display_name)
	_next_season()


func skip_reward() -> void:
	if phase != Phase.REWARD:
		return
	sap += Rules.SKIP_REWARD_SAP
	_next_season()


func choose_relic(i: int) -> void:
	if phase != Phase.RELIC or i < 0 or i >= relic_options.size():
		return
	var r := relic_options[i]
	relics.append(r)
	add_log("获得器物：%s" % Cards.relic(r).display_name)
	_open_market()


func skip_relic() -> void:
	if phase != Phase.RELIC:
		return
	sap += Rules.SKIP_REWARD_SAP
	_open_market()


func _collect_cards() -> void:
	discard.append_array(hand)
	hand.clear()
	deck.append_array(discard)
	discard.clear()
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
	changed.emit()


func _start_season() -> void:
	turn = 1
	score = 0
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
	var pool := Cards.pool_ids()
	shuffle(pool)
	market_cards.assign(pool.slice(0, Rules.MARKET_CARD_OFFERS))
	add_log("进入集市")
	changed.emit()


func deck_counts() -> Dictionary:
	var out := {}
	for pile in [deck, discard, hand]:
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
	sap -= price
	deck.append(t)
	market_cards.remove_at(i)
	add_log("买下%s（-%d）" % [Cards.get_def(t).display_name, price])
	changed.emit()
	return true


func remove_card(t: StringName) -> bool:
	if phase != Phase.MARKET or sap < Rules.REMOVE_CARD_PRICE:
		return false
	for pile: Array[StringName] in [deck, discard, hand]:
		var i := pile.find(t)
		if i >= 0:
			pile.remove_at(i)
			sap -= Rules.REMOVE_CARD_PRICE
			add_log("删去一张%s（-%d）" % [Cards.get_def(t).display_name, Rules.REMOVE_CARD_PRICE])
			changed.emit()
			return true
	return false


func can_mark(mark: StringName, k: Vector2i) -> bool:
	var n := tree.at(k)
	return phase == Phase.MARKET and n != null and not n.is_seed() and not n.marks.has(mark) \
		and sap >= int(Rules.MARKS[mark].price)


func buy_mark(mark: StringName, k: Vector2i) -> bool:
	if not can_mark(mark, k):
		return false
	var n := tree.at(k)
	sap -= int(Rules.MARKS[mark].price)
	n.marks.append(mark)
	add_log("给%s刻上年轮「%s」" % [Cards.get_def(n.type).display_name, Rules.mark_name(mark)])
	changed.emit()
	return true


func can_clear_rock(k: Vector2i) -> bool:
	return phase == Phase.MARKET and tree.land_at(k) == Land.Type.ROCK and sap >= Rules.CLEAR_ROCK_PRICE


func clear_rock(k: Vector2i) -> bool:
	if not can_clear_rock(k):
		return false
	sap -= Rules.CLEAR_ROCK_PRICE
	tree.land.erase(k)
	add_log("清除了一块岩石（-%d）" % Rules.CLEAR_ROCK_PRICE)
	changed.emit()
	return true


func can_make_fertile(k: Vector2i) -> bool:
	return phase == Phase.MARKET and Hex.in_board(k, tree.radius) and k != TreeModel.SEED_KEY \
		and tree.land_at(k) == Land.Type.PLAIN and sap >= Rules.MAKE_FERTILE_PRICE


func make_fertile(k: Vector2i) -> bool:
	if not can_make_fertile(k):
		return false
	sap -= Rules.MAKE_FERTILE_PRICE
	tree.land[k] = Land.Type.FERTILE
	add_log("把一块地养成沃土（-%d）" % Rules.MAKE_FERTILE_PRICE)
	changed.emit()
	return true


func leave_market() -> void:
	if phase != Phase.MARKET:
		return
	market_cards.clear()
	year += 1
	season = 1
	_pick_calamity()
	var added := Land.scatter(tree, rng, Rules.YEARLY_LAND)
	_start_season()
	add_log("第%d年春季开始，目标 %d；新长出 %d 块地" % [year, target(), added.size()])
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
		"year": year, "season": season, "turn": turn, "score": score, "sap": sap,
		"tree": tree.to_dict(),
		"deck": _names(deck), "discard": _names(discard), "hand": _names(hand),
		"plays": plays, "prunes": prunes, "phase": phase,
		"reward_options": _names(reward_options), "relic_options": _names(relic_options),
		"relics": _names(relics), "calamity": String(calamity), "seen_calamities": _names(seen_calamities),
		"market_cards": _names(market_cards), "next_tip_bonus": next_tip_bonus,
		"log": log_lines.duplicate(),
	}


static func from_dict(d: Dictionary) -> RunState:
	var s := RunState.new()
	s.seed_value = int(d.seed)
	s.rng.seed = s.seed_value
	s.rng.state = String(d.rng_state).to_int()
	s.year = int(d.year)
	s.season = int(d.season)
	s.turn = int(d.turn)
	s.score = int(d.score)
	s.sap = int(d.sap)
	s.tree = TreeModel.from_dict(d.tree)
	s.deck = _ids(d.deck)
	s.discard = _ids(d.discard)
	s.hand = _ids(d.hand)
	s.plays = int(d.plays)
	s.prunes = int(d.prunes)
	s.phase = int(d.phase) as Phase
	s.reward_options = _ids(d.reward_options)
	s.relic_options = _ids(d.relic_options)
	s.relics = _ids(d.relics)
	s.calamity = StringName(d.calamity)
	s.seen_calamities = _ids(d.seen_calamities)
	s.market_cards = _ids(d.market_cards)
	s.next_tip_bonus = int(d.next_tip_bonus)
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
