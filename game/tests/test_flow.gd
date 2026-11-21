extends "res://tests/base_test.gd"
## 阶段 A：提前收获、修剪进手牌、弃牌、燃尽、移栽、芽点服务、器物槽。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


func _bare_run(run_seed: int = 1) -> RunState:
	var s := RunState.create(run_seed)
	s.tree.land.clear()
	return s


# ---------- 提前收获 ----------

func test_harvest_when_target_reached() -> void:
	var s := _bare_run()
	check(not s.can_harvest(), "not before target")
	s.score = s.target()
	check(s.can_harvest(), "target reached")
	var sap0 := s.sap
	var expect := Rules.turns(1) * Rules.HARVEST_SAP_PER_TURN
	check_eq(s.harvest_sap(), expect)
	check(s.harvest(), "harvest")
	check_eq(s.phase, RunState.Phase.REWARD)
	check_eq(s.sap, sap0 + expect + Rules.SEASON_CLEAR_SAP)


# ---------- 修剪进手牌 ----------

func test_pruned_cards_return_to_hand_locked() -> void:
	var s := _bare_run()
	s.hand.clear()
	s.hand_fresh.clear()
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"fruit", Hex.DIRS[1] * 2, _t([a.key], 1))
	check(s.prune(a.key) > 0, "prune")
	check_eq(s.hand, [&"stem", &"fruit"] as Array[StringName], "parent first")
	check_eq(s.hand_fresh, [true, true] as Array[bool])
	check(s.targets_for_hand(0).is_empty(), "fresh card cannot be played this turn")
	s.end_turn()
	check(not s.hand_fresh.has(true), "unlocked next turn")
	check(not s.targets_for_hand(0).is_empty(), "playable next turn")


func test_overflow_enters_discard_phase() -> void:
	var s := _bare_run()
	check_eq(s.hand.size(), s.hand_limit())
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[1] * 2, _t([a.key], 1))
	s.prune(a.key)
	check_eq(s.phase, RunState.Phase.DISCARD)
	check_eq(s.overflow(), 2)
	check(s.end_turn() == null, "cannot pulse while discarding")
	s.discard_card(0)
	check_eq(s.phase, RunState.Phase.DISCARD)
	s.discard_card(0)
	check_eq(s.phase, RunState.Phase.PLAY)
	check_eq(s.hand.size(), s.hand_limit())


func test_dead_branch_exhausts_until_next_season() -> void:
	var s := _bare_run()
	var d := Growth.place(s.tree, &"dead", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var n_hand := s.hand.size()
	check_eq(s.prune(d.key), 3)
	check_eq(s.hand.size(), n_hand, "dead branch does not return to hand")
	check_eq(s.exhausted, [&"dead"] as Array[StringName])
	check_eq(int(s.deck_counts()[&"dead"]), Rules.START_DECK[&"dead"] + 1, "still owned (one extra placed by the test)")
	s._collect_cards()
	check(s.exhausted.is_empty(), "back in the deck next season")


func test_redraw_keeps_fresh_cards() -> void:
	var s := _bare_run()
	s.sap = 10
	var a := Growth.place(s.tree, &"oak", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	s.prune(a.key)
	while s.phase == RunState.Phase.DISCARD:
		s.discard_card(0)
	check(s.redraw(), "redraw")
	check(s.hand.has(&"oak"), "fresh oak kept")
	check_eq(s.hand.size(), s.hand_limit())


# ---------- 移栽 ----------

func test_transplant_moves_subtree_rigidly() -> void:
	var s := _bare_run()
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var f := Growth.place(s.tree, &"fruit", Hex.DIRS[1] * 2, _t([a.key], 1))
	f.age = 3
	var tg := s.transplant_targets(a.key)
	check(tg.has(Hex.DIRS[3]), "can move to another seed port")
	check(not tg.has(a.key), "not to the same spot")
	check(s.transplant(a.key, Hex.DIRS[3]), "transplant")
	check(not s.tree.has(Hex.DIRS[1]), "old cell empty")
	var na := s.tree.at(Hex.DIRS[3])
	var nf := s.tree.at(Hex.DIRS[3] * 2)
	check(na != null and na.type == &"stem" and na.facing == 3, "stem moved and rotated")
	check(nf != null and nf.type == &"fruit" and nf.age == 3, "fruit followed and kept age")
	check_eq(nf.parents, [Hex.DIRS[3]] as Array[Vector2i])
	check_eq(s.tree.at(Vector2i.ZERO).children, [Hex.DIRS[3]] as Array[Vector2i])
	check_eq(nf.depth, 2)
	check_eq(s.transplants, 0)
	check(s.transplant_targets(Hex.DIRS[3]).is_empty(), "once per turn")


func test_rotate_matches_dirs() -> void:
	for i in 6:
		for r in 6:
			check_eq(Growth.rotate(Hex.DIRS[i], r), Hex.DIRS[(i + r) % 6])


func test_transplant_blocked_by_outside_graft() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"fruit", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"fruit", Vector2i(0, 1), _t([Vector2i.ZERO], 5))
	Growth.place(s.tree, &"vine", Vector2i(1, 0), _t([Vector2i(1, -1), Vector2i(0, 1)], -1))
	check(s.transplant_targets(Vector2i(1, -1)).is_empty(), "vine has a parent outside")
	check(s.transplant_targets(Vector2i(1, 0)).is_empty(), "vine cannot be the root")


# ---------- 芽点服务 ----------

func test_add_port_in_chosen_direction() -> void:
	var s := _bare_run()
	s.phase = RunState.Phase.MARKET
	s.sap = 20
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var dirs := Growth.free_port_dirs(a)
	check(not dirs.has(1), "existing port excluded")
	check(not dirs.has(4), "direction back to parent excluded")
	check(s.add_port(a.key, 2), "add port")
	check_eq(Growth.ports_of(a), [1, 2] as Array[int])
	check_eq(s.sap, 20 - Rules.PORT_PRICE)
	s.phase = RunState.Phase.PLAY
	check(Growth.targets_for(s.tree, &"stem", s.ctx()).has(a.key + Hex.DIRS[2]), "new port is growable")


# ---------- 器物槽 ----------

func test_relic_slots_buy_sell() -> void:
	var s := _bare_run()
	s.phase = RunState.Phase.MARKET
	s._open_market()
	s.sap = 100
	var r := s.market_relics[0]
	check(s.buy_relic(0), "buy relic")
	check(s.has_relic(r), "owned")
	check_eq(s.sap, 100 - Cards.relic(r).price)
	var before := s.sap
	check(s.sell_relic(0), "sell")
	check_eq(s.sap, before + s.relic_sell_price(r))
	for id in Cards.relic_ids().slice(0, Rules.RELIC_SLOTS):
		s.relics.append(id)
	check(s.relics_full(), "full")
	s.market_relics = [Cards.relic_ids()[-1]] as Array[StringName]
	check(not s.can_buy_relic(0), "no free slot")


func test_choose_relic_needs_replace_when_full() -> void:
	var s := _bare_run()
	for id in Cards.relic_ids().slice(0, Rules.RELIC_SLOTS):
		s.relics.append(id)
	s.phase = RunState.Phase.RELIC
	s.relic_options = [Cards.relic_ids()[-1]] as Array[StringName]
	check(not s.choose_relic(0), "full without replace")
	check(s.choose_relic(0, 0), "replace slot 0")
	check_eq(s.relics.size(), Rules.RELIC_SLOTS)
	check(s.has_relic(Cards.relic_ids()[-1]), "new relic in")


func test_save_roundtrip_new_fields() -> void:
	var s := _bare_run(8)
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	a.extra_ports.append(2)
	Growth.place(s.tree, &"dead", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	s.prune(Hex.DIRS[3])
	var json := JSON.stringify(s.to_dict())
	var s2 := RunState.from_dict(JSON.parse_string(json))
	check_eq(JSON.stringify(s2.to_dict()), json)
	check_eq(s2.tree.at(a.key).extra_ports, [2] as Array[int])
	check_eq(s2.exhausted, s.exhausted)
