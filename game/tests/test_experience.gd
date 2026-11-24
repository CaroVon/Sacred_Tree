extends "res://tests/base_test.gd"
## 试玩报告后的体验改动：主流派算上牌桌、树心逐年长芽点、选牌保底分枝、天灾不逼弃牌、
## 超额奖励、复盘记录。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


func _bare_run(run_seed: int = 1) -> RunState:
	var s := RunState.create(run_seed)
	s.tree.land.clear()
	return s


func test_top_families_count_board_cards() -> void:
	var s := _bare_run()
	s.deck.clear()
	s.discard.clear()
	s.hand.clear()
	s.hand_fresh.clear()
	Growth.place(s.tree, &"star_sand", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"star_tide", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	Growth.place(s.tree, &"star_sand", Hex.DIRS[1] * 3, _t([Hex.DIRS[1] * 2], 1))
	s.deck.append(&"gear_cog")
	var w := _bare_run(2)
	check_eq(w.top_families(1), [&"wood"] as Array[StringName], "no new family yet: wood is the main family")
	check_eq(s.top_families(1), [&"star"] as Array[StringName], "board cards decide the main family")


func test_seed_grows_a_port_each_year() -> void:
	var s := _bare_run()
	var before := Growth.ports_of(s.tree.at(Vector2i.ZERO), s.ctx()).size()
	s.phase = RunState.Phase.MARKET
	s.season = Rules.CALAMITY_STAGE
	s.leave_market()
	check_eq(s.year, 2)
	check_eq(Growth.ports_of(s.tree.at(Vector2i.ZERO), s.ctx()).size(), before + Rules.SEED_PORT_PER_YEAR)


func test_reward_guarantees_branch_when_buds_low() -> void:
	var s := _bare_run(3)
	# 把树心三个芽点都用末端牌堵上：一个空芽点都没有
	for d in Growth.SEED_PORTS:
		Growth.place(s.tree, &"fruit", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	check_eq(s.free_buds(), 0)
	for i in 8:
		s.phase = RunState.Phase.PLAY
		s.score = s.target()
		s._end_season()
		check(s.reward_options.any(func(id): return RunState.is_branching(id)), "a branching card is offered")
		check(not s.reward_options.any(func(id): return Cards.get_def(id).category == CardDef.Category.PRUNE), "no dead-branch filler")
		s.season = 1


func test_calamity_return_does_not_force_discard() -> void:
	var s := _bare_run()
	var prev := Vector2i.ZERO
	for i in 4:
		var c := prev + Hex.DIRS[1]
		Growth.place(s.tree, &"stem", c, _t([prev], 1))
		prev = c
	while s.hand.size() < s.hand_limit():
		s.hand.append(&"stem")
		s.hand_fresh.append(false)
	s._lightning()
	check(s.hand.size() > s._base_hand_limit(), "hand went over the normal limit")
	s._check_overflow()
	check_eq(s.phase, RunState.Phase.PLAY, "no forced discard after a calamity")


func test_overkill_sap() -> void:
	var s := _bare_run()
	s.score = s.target() * 150
	var sap0 := s.sap
	s._end_season()
	check_eq(s.last_overkill, 2)
	check_eq(s.sap, sap0 + Rules.SEASON_CLEAR_SAP + 2 * Rules.OVERKILL_SAP)


func test_history_and_loss_reason() -> void:
	var s := _bare_run()
	s.score = 5
	s.end_turn()
	check(not s.best_pulse.is_empty(), "best pulse recorded")
	while s.phase == RunState.Phase.PLAY:
		s.end_turn()
	check_eq(s.phase, RunState.Phase.LOST)
	check_eq(s.history.size(), 1)
	check(s.loss_reason != "", "loss reason written")
	var d := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(d.history.size(), 1)
	check_eq(d.loss_reason, s.loss_reason)


func test_hand_stuck_and_projection() -> void:
	var s := _bare_run()
	for d in Growth.SEED_PORTS:
		Growth.place(s.tree, &"fruit", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	s.hand.assign([&"stem", &"fork"])
	s.hand_fresh.assign([false, false])
	check(s.hand_stuck(), "no free buds means stuck")
	check(s.projected_total() >= s.score, "projection is at least the current score")


func test_winter_wither_preview() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	Growth.place(s.tree, &"stem", Hex.DIRS[5], _t([Vector2i.ZERO], 5))
	check(s.wither_preview().is_empty(), "no preview outside winter")
	s.season = 4
	check_eq(s.wither_preview().size(), Rules.WINTER_WITHER)


func test_transform_never_same_card() -> void:
	var s := _bare_run(5)
	for i in 10:
		var out := RunEvents.apply(s, [{"op": "transform", "n": 1}])
		for line in out:
			check(not line.begins_with("枯枝变成了枯枝") and not line.begins_with("茎变成了茎"), line)


func test_seal_break_passive_release() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"seal_box", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	var box := s.tree.at(Hex.DIRS[0])
	box.stored = 10
	box.sealed = 1
	Growth.place(s.tree, &"seal_break", Hex.DIRS[2], _t([Vector2i.ZERO], 2))
	var rate: float = Cards.get_def(&"seal_box").seal_rate + Pulse.SEAL_RES[s.res_tier(&"seal")]
	check_eq(s.pending_release(), int(floor(10 * (1.0 + rate) * Rules.BREAK_PASSIVE_MULT)))
	check_eq(s.pending_release(1.0), int(floor(10 * (1.0 + rate))), "explicit multiplier skips the passive")
