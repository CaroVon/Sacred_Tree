extends "res://tests/base_test.gd"
## P4 系统：土地、印记、器物、天灾、三年流程、集市、新牌。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


func _ctx(season: int = 1) -> Pulse.Context:
	var c := Pulse.Context.for_season(season)
	c.maturity = false
	c.patterns = false
	return c


func _bare_run(run_seed: int = 1) -> RunState:
	var s := RunState.create(run_seed)
	s.tree.land.clear()
	return s


## 打完当前季：直接把累计分设为目标，然后结束剩下的回合。
func _clear_season(s: RunState) -> void:
	while s.phase == RunState.Phase.PLAY:
		if s.turn == s.turns_this_season():
			s.score = 1 << 40
		s.end_turn()


# ---------- 土地 ----------

func test_fertile_rock_spring() -> void:
	var tree := TreeModel.create(4)
	tree.land[Hex.DIRS[1]] = Land.Type.FERTILE
	tree.land[Hex.DIRS[3]] = Land.Type.ROCK
	tree.land[Hex.DIRS[5] * 2] = Land.Type.SPRING
	var tg := Growth.targets_for(tree, &"stem", _ctx())
	check(tg.has(Hex.DIRS[1]), "fertile is growable")
	check(not tg.has(Hex.DIRS[3]), "rock blocks growth")
	Growth.place(tree, &"stem", Hex.DIRS[1], tg[Hex.DIRS[1]])
	check_eq(Pulse.resolve(tree, _ctx()).total, 1 + 3 + Land.FERTILE_BONUS)
	# 泉眼 (0,2) 与 (0,1) 相邻
	Growth.place(tree, &"stem", Hex.DIRS[5], _t([Vector2i.ZERO], 5))
	check_eq(Pulse.resolve(tree, _ctx()).total, 6 + 4 + Land.SPRING_BONUS)
	check(not Growth.targets_for(tree, &"stem", _ctx()).has(Hex.DIRS[5] * 2), "spring blocks growth")


func test_start_land_generated() -> void:
	var s := RunState.create(3)
	var counts := {}
	for c in s.tree.land:
		check(Hex.distance(c, Vector2i.ZERO) >= Land.MIN_DIST, "land too close to seed")
		counts[s.tree.land[c]] = int(counts.get(s.tree.land[c], 0)) + 1
	for t in Rules.START_LAND:
		check_eq(counts.get(t, 0), Rules.START_LAND[t])


# ---------- 印记 ----------

func test_marks() -> void:
	var tree := TreeModel.create(4)
	var st := Growth.place(tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	check_eq(Growth.ports_of(st).size(), 1)
	st.extra_ports.append(3)
	check_eq(Growth.ports_of(st), [1, 3] as Array[int])
	st.marks.append(&"rich")
	check_eq(Pulse.resolve(tree, _ctx()).total, 1 + 3 + Pulse.RICH_BONUS)


func test_tough_survives_winter() -> void:
	var s := _bare_run()
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	a.marks.append(&"tough")
	var gone := s.wither(3)
	check_eq(gone, [Hex.DIRS[3]] as Array[Vector2i])
	check(s.tree.has(Hex.DIRS[1]), "tough stem kept")


# ---------- 器物 ----------

func test_relics_root_and_shears() -> void:
	var s := _bare_run()
	check_eq(Growth.ports_of(s.tree.at(Vector2i.ZERO), s.ctx()).size(), 3)
	s.relics.append(&"root")
	check_eq(Growth.ports_of(s.tree.at(Vector2i.ZERO), s.ctx()).size(), 4)
	s.relics.append(&"shears")
	s._reset_turn()
	check_eq(s.prunes, 2)


func test_relic_dew_and_knife() -> void:
	var s := _bare_run()
	s.relics.append(&"dew")
	check_eq(s.preview().total, 2, "first pulse doubled")
	s.end_turn()
	check_eq(s.preview().total, 1)


# ---------- 天灾 ----------

func test_drought_halves_seed() -> void:
	var s := _bare_run()
	s.season = Rules.CALAMITY_STAGE
	s.calamity = &"drought"
	check_eq(s.ctx().seed_out, Rules.seed_out(4) / 2)


func test_lightning_cuts_longest_branch() -> void:
	var s := _bare_run()
	var prev := Vector2i.ZERO
	for i in 4:
		var c := prev + Hex.DIRS[1]
		Growth.place(s.tree, &"stem", c, _t([prev], 1))
		prev = c
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	s._lightning()
	check_eq(s.tree.size(), 1 + 1 + 1, "seed + short branch + first stem of long branch")


func test_pests_bite_tip() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	s._pests()
	check_eq(s.tree.size(), 2)


# ---------- 三年流程 ----------

func _resolve_discard(s: RunState) -> void:
	while s.phase == RunState.Phase.DISCARD:
		s.discard_card(0)


func test_year_flow_to_market_and_next_year() -> void:
	var s := RunState.create(9)
	check_eq(s.tree.radius, Rules.radius_for_year(1))
	for season in range(1, 5):
		check_eq(s.season, season)
		_clear_season(s)
		check_eq(s.phase, RunState.Phase.REWARD)
		s.choose_reward(0)
		check_eq(s.phase, RunState.Phase.MARKET, "market after every season")
		check_eq(s.market_relics.size(), Rules.MARKET_RELIC_OFFERS)
		s.leave_market()
		_resolve_discard(s)
	check(s.is_calamity(), "fifth stage is calamity")
	check_eq(s.turns_this_season(), Rules.CALAMITY_TURNS)
	_clear_season(s)
	check_eq(s.phase, RunState.Phase.RELIC)
	check_eq(s.relic_options.size(), Rules.RELIC_CHOICES)
	s.choose_relic(0)
	check_eq(s.relics.size(), 1)
	check_eq(s.phase, RunState.Phase.MARKET)
	check_eq(s.market_cards.size(), Rules.MARKET_CARD_OFFERS)
	var land_before := s.tree.land.size()
	var cal1 := s.calamity
	s.leave_market()
	check_eq(s.year, 2)
	check_eq(s.season, 1)
	check_eq(s.phase, RunState.Phase.PLAY)
	check(s.calamity != cal1, "calamity changes each year")
	check(s.tree.land.size() > land_before, "new land each year")
	check_eq(s.tree.radius, Rules.radius_for_year(2), "board grows")
	var ring := 0
	for c in s.tree.land:
		if Hex.distance(c, Vector2i.ZERO) == s.tree.radius:
			ring += 1
	check(ring >= 1, "land on the new ring")
	check_eq(s.ctx().seed_out, 2)


func test_win_after_three_years() -> void:
	var s := RunState.create(4)
	for y in Rules.YEARS:
		for season in Rules.STAGES:
			_clear_season(s)
			if s.phase == RunState.Phase.REWARD:
				s.skip_reward()
			elif s.phase == RunState.Phase.RELIC:
				s.skip_relic()
			s.leave_market()
			_resolve_discard(s)
	check_eq(s.phase, RunState.Phase.WON)
	check_eq(s.year, Rules.YEARS)


# ---------- 集市 ----------

func _market(run_seed: int = 2) -> RunState:
	var s := RunState.create(run_seed)
	s.phase = RunState.Phase.MARKET
	s._open_market()
	return s


func test_market_buy_and_remove() -> void:
	var s := _market()
	var t := s.market_cards[0]
	var price := Cards.get_def(t).price
	s.sap = price - 1
	check(not s.buy_card(0), "too poor")
	s.sap = price + Rules.REMOVE_CARD_PRICE
	var before: int = s.deck_counts().get(t, 0)
	check(s.buy_card(0), "buy")
	check_eq(s.deck_counts().get(t, 0), before + 1)
	check_eq(s.market_cards.size(), Rules.MARKET_CARD_OFFERS - 1)
	var rm: StringName = &"dead" if t != &"dead" else &"stem"
	check(s.remove_card(rm), "remove")
	check_eq(s.deck_counts()[rm], Rules.START_DECK[rm] - 1)
	check_eq(s.sap, 0)


func test_market_land_and_marks() -> void:
	var s := _market()
	s.sap = 100
	var rock := Vector2i(9, 9)
	for c in s.tree.land:
		if s.tree.land[c] == Land.Type.ROCK:
			rock = c
	check(s.clear_rock(rock), "clear rock")
	check_eq(s.tree.land_at(rock), Land.Type.PLAIN)
	check(s.make_fertile(rock), "make fertile")
	check_eq(s.tree.land_at(rock), Land.Type.FERTILE)
	check(not s.make_fertile(Vector2i.ZERO), "not on seed")
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	check(s.buy_mark(&"tough", Hex.DIRS[1]), "mark")
	check(not s.buy_mark(&"tough", Hex.DIRS[1]), "no duplicate mark")
	check_eq(s.sap, 100 - Rules.CLEAR_ROCK_PRICE - Rules.MAKE_FERTILE_PRICE - int(Rules.MARKS[&"tough"].price))


func test_save_roundtrip_in_market() -> void:
	var s := _market(5)
	s.relics.append(&"dew")
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1)).marks.append(&"rich")
	var json := JSON.stringify(s.to_dict())
	var s2 := RunState.from_dict(JSON.parse_string(json))
	check_eq(JSON.stringify(s2.to_dict()), json)
	check_eq(s2.tree.at(Hex.DIRS[1]).marks, [&"rich"] as Array[StringName])
	check_eq(s2.tree.land, s.tree.land)


# ---------- 新牌 ----------

func test_new_cards() -> void:
	var tree := TreeModel.create(4)
	# 古木只能接在深度 ≥3
	check(Growth.targets_for(tree, &"oak", _ctx()).is_empty(), "oak needs depth 3")
	var a := Growth.place(tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var b := Growth.place(tree, &"stem", Hex.DIRS[1] * 2, _t([a.key], 1))
	check(not Growth.targets_for(tree, &"oak", _ctx()).is_empty(), "oak fits at depth 3")
	# 苔：相邻传导牌 +2（苔挨着两根茎）
	var moss_cell := Hex.DIRS[0]  # (1,0) 与 (1,-1)、(0,0) 相邻；(2,-2) 不相邻
	Growth.place(tree, &"moss", moss_cell, _t([Vector2i.ZERO], 0))
	var res := Pulse.resolve(tree, _ctx())
	check_eq(res.out[a.key], 1 + 3 + 2)
	check_eq(res.out[b.key], 6 + 3 + (2 if Hex.distance(b.key, moss_cell) == 1 else 0))


func test_twinvine_sums() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"stem", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	# (1,-1) 与 (1,0) 都挨着 (2,-1)
	Growth.place(tree, &"twinvine", Vector2i(2, -1), _t([Hex.DIRS[1], Hex.DIRS[0]], -1))
	check_eq(Pulse.resolve(tree, _ctx()).total, (4 + 4) * 3)


func test_bud_ripens() -> void:
	var tree := TreeModel.create(4)
	var b := Growth.place(tree, &"bud", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var c := Pulse.Context.for_season(1)
	c.patterns = false
	check_eq(Pulse.resolve(tree, c).total, 1)
	b.age = 2
	check_eq(Pulse.resolve(tree, c).total, 13)


func test_leaf_prune_bonus() -> void:
	var s := _bare_run()
	s.hand.clear()
	s.hand_fresh.clear()
	Growth.place(s.tree, &"leaf", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	var pv := s.preview_prune(Hex.DIRS[1])
	s.prune(Hex.DIRS[1])
	check_eq(s.next_tip_bonus, 3)
	check_eq(s.preview().total, 4 + 3)
	check_eq(pv.total, 7)
	s.end_turn()
	check_eq(s.next_tip_bonus, 0)


func test_all_cards_load() -> void:
	check(Cards.all_ids().size() >= 24, "at least the original 24 cards")
	check(Cards.relic_ids().size() >= 10, "at least the original 10 relics")
	for id in Cards.relic_ids():
		check(Cards.relic(id).price > 0, "relic %s has price" % id)
	check(Cards.calamity_ids().size() >= 7, "seven calamities")
	for id in Cards.all_ids():
		var d := Cards.get_def(id)
		check(d.display_name != "" and d.desc != "", "card %s incomplete" % id)
