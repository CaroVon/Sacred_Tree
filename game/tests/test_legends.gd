extends "res://tests/base_test.gd"
## 传说牌：改写规则的效果，以及天灾季后的传说三选一。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


func _ctx(resonance := false) -> Pulse.Context:
	var c := Pulse.Context.for_season(1)
	c.maturity = false
	c.patterns = false
	c.resonance = resonance
	return c


func _bare_run(run_seed: int = 1) -> RunState:
	var s := RunState.create(run_seed)
	s.tree.land.clear()
	s.hand.clear()
	s.hand_fresh.clear()
	return s


func test_legends_change_rules_not_only_numbers() -> void:
	# 每个新流派至少一张传说，且都带一条规则改写（或嫁接 / 解印这类机制）
	for f in [&"gear", &"forge", &"star", &"coin", &"mirror", &"seal"]:
		var found := false
		for id in Cards.pool_ids():
			var d := Cards.get_def(id)
			if d.rarity >= 2 and d.family == ([f] as Array[StringName]):
				found = true
				check(d.burn_fresh or d.retro or d.link_all or d.partner_per > 0 or d.phantom_mirror > 0.0
					or d.graft_family != &"" or d.release_on_prune > 0.0, "%s 是规则型传说" % id)
		check(found, "%s 有传说" % f)


func test_phoenix_makes_pruned_cards_playable() -> void:
	var s := _bare_run()
	Growth.place(s.tree, &"forge_phoenix", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	var a := Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	check(s.prune(a.key) >= 0, "prune")
	check_eq(s.hand, [&"stem"] as Array[StringName])
	check_eq(s.hand_fresh, [false] as Array[bool], "浴火：当回合可用")
	check(not s.targets_for_hand(0).is_empty(), "可以立即打出")


func test_retro_makes_every_turn_last() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"star_meteor", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var c := _ctx()
	c.turns_total = 5
	c.turn = 1
	var before := Pulse.resolve(tree, c).total
	Growth.place(tree, &"star_retro", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	var t1 := Pulse.resolve(tree, c).total
	c.turn = 5
	var t5 := Pulse.resolve(tree, c).total
	check_eq(t1, t5, "逆行：第 1 回合等于最后一回合")
	check(t1 > before, "逆行让流星提前爆发")


func test_perpetual_links_all_gears() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"gear_cog", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	Growth.place(tree, &"gear_cog", Hex.DIRS[3], _t([Vector2i.ZERO], 3))  # 不相邻
	var before := Pulse.resolve(tree, _ctx()).total
	Growth.place(tree, &"gear_perpetual", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var res := Pulse.resolve(tree, _ctx())
	check(res.link_all, "永动机生效")
	check(res.total > before, "不相邻的齿轮也联动")


func test_legend_pick_only_first_year() -> void:
	var s := _bare_run()
	s.year = 2
	s.phase = RunState.Phase.RELIC
	s.relic_options = [Cards.relic_ids()[0]] as Array[StringName]
	s.skip_relic()
	check_eq(s.phase, RunState.Phase.MARKET, "第 2 年天灾后没有传说之选")


func test_partner_counts_other_cards_as_coin() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"coin_partner", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	for d in [1, 2, 3, 4]:
		Growth.place(tree, &"stem", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	var d := Cards.get_def(&"coin_partner")
	check_eq(int(Pulse.family_counts(tree)[&"coin"]), 1 + mini(4 / d.partner_per, d.partner_cap))


func test_myriad_mirror_phantoms() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"stem", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	Growth.place(tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))  # 与上一张对称
	Growth.place(tree, &"fork", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"mirror_myriad", Hex.DIRS[2], _t([Vector2i.ZERO], 2))
	var res := Pulse.resolve(tree, _ctx())
	var x := Cards.get_def(&"mirror_myriad").phantom_mirror
	var base := 0
	var extra := 0
	var ph := 0
	for t in res.contrib:
		base += int(res.contrib[t])
		if tree.at(-t) == null:
			extra += int(floor(int(res.contrib[t]) * x))
			ph += 1
	check(ph > 0, "有幻影")
	check_eq(res.phantoms, ph)
	check_eq(res.total, base + extra)


func test_legend_pick_after_calamity_relic() -> void:
	var s := _bare_run()
	s.phase = RunState.Phase.RELIC
	s.relic_options = [Cards.relic_ids()[0]] as Array[StringName]
	check(s.choose_relic(0), "choose relic")
	check_eq(s.phase, RunState.Phase.REWARD)
	check(s.legend_reward, "传说三选一")
	check_eq(s.reward_options.size(), Rules.LEGEND_CHOICES)
	for id in s.reward_options:
		check_eq(Cards.get_def(id).rarity, 2, "%s 是传说" % id)
	var saved := RunState.from_dict(s.to_dict())
	check(saved.legend_reward, "存档保留")
	var pick := s.reward_options[0]
	s.choose_reward(0)
	check_eq(s.phase, RunState.Phase.MARKET)
	check(not s.legend_reward, "已结束")
	check(s.discard.has(pick), "加入牌组")


func test_no_legend_pool_goes_to_market() -> void:
	var s := _bare_run()
	s.max_rarity = 1
	s.phase = RunState.Phase.RELIC
	s.relic_options = [Cards.relic_ids()[0]] as Array[StringName]
	s.skip_relic()
	check_eq(s.phase, RunState.Phase.MARKET)
	for id in s.card_pool():
		check(Cards.get_def(id).rarity <= 1, "禁用传说")
