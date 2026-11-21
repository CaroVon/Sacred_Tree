extends "res://tests/base_test.gd"
## 构筑层：启程者、卡池过滤、抽选引导、精炼、收藏解锁、联动谱。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


func test_starters_load_and_build_decks() -> void:
	check(Cards.starter_ids().size() >= 4, "four starters")
	for id in Cards.starter_ids():
		var st := Cards.starter(id)
		var n := 0
		for t in st.deck:
			check(Cards.has(StringName(t)), "%s deck card %s exists" % [id, t])
			n += int(st.deck[t])
		check(n >= 15, "%s deck has enough cards" % id)
		if st.relic != &"":
			check(Cards.relic(st.relic) != null, "%s relic exists" % id)
	var s := RunState.create(3, &"artisan")
	check(s.has_relic(&"tongs"), "artisan starts with tongs")
	check(s.deck_counts().has(&"gear_cog"), "artisan deck has gears")


func test_pool_respects_unlocks() -> void:
	var s := RunState.create(3, &"gardener", [&"wood", &"gear"])
	for id in s.card_pool():
		var d := Cards.get_def(id)
		for f in d.families():
			check(f == &"wood" or f == &"gear", "%s allowed" % id)
	check(s.card_pool().has(&"gear_cog"), "gear in pool")
	check(not s.card_pool().has(&"forge_coal"), "forge locked")
	check(not s.card_pool().has(&"bridge_bell"), "bridge needs both families")
	var all := RunState.create(3)
	check(all.card_pool().has(&"seal_box"), "no filter = everything")


func test_roll_biases_toward_main_families() -> void:
	var s := RunState.create(5, &"artisan")
	var top := s.top_families()
	check(top.has(&"gear") and top.has(&"forge"), "artisan's main families")
	var hits := 0
	var offs := 0
	for i in 60:
		var picks := s.roll_cards(s.card_pool(), 3)
		check_eq(picks.size(), 3)
		var main := picks.filter(func(id): return s.card_weight(id, top) > 1.0).size()
		hits += main
		if main < 3:
			offs += 1
	check(hits > 60 * 3 * 0.35, "main families show up often (%d)" % hits)
	check_eq(offs, 60, "always at least one other family")


func test_refine_makes_plus_card() -> void:
	var plus := Cards.get_def(&"stem+")
	check(plus != null and plus.is_plus(), "stem+ derived")
	check_eq(plus.value, 3.0 + 2.0)
	check_eq(plus.art_id(), &"stem")
	check_eq(Cards.get_def(&"fruit+").value, 2.5)
	check_eq(Cards.get_def(&"vine+").graft_self_mult, 1.5)
	check_eq(Cards.get_def(&"gear_cog+").adj_family_add, 3)
	check(not Cards.pool_ids().any(func(id): return String(id).ends_with("+")), "plus cards never in the pool")
	var s := RunState.create(2)
	s.phase = RunState.Phase.MARKET
	s.sap = 20
	check(s.refine(&"stem"), "refine")
	check(s.deck_counts().has(&"stem+"), "deck has stem+")
	check(not s.can_refine(&"stem+"), "only once")
	check_eq(s.sap, 20 - Rules.REFINE_PRICE)
	# 精炼版能放到树上并按新数值计分
	var tree := TreeModel.create(5)
	Growth.place(tree, &"stem+", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	var c := Pulse.Context.for_season(1)
	c.maturity = false
	c.patterns = false
	check_eq(Pulse.resolve(tree, c).total, 1 + 5)


func test_profile_defaults_and_unlocks() -> void:
	var p := Profile.load_from("")
	check(p.has_family(&"gear") and not p.has_family(&"star"), "defaults")
	check(p.has_starter(&"artisan") and not p.has_starter(&"stargazer"), "default starters")
	check(p.unlock_hint_family(&"star") != "", "hint for locked family")
	var s := RunState.create(1)
	s.year = 2
	var msgs := p.record_progress(s)
	check(p.has_family(&"star"), "star unlocked in year 2")
	check(p.has_starter(&"stargazer"), "stargazer unlocked")
	check(msgs.size() == 2, "two messages")
	check(p.record_progress(s).is_empty(), "only once")


func test_profile_records_cards_and_combos() -> void:
	var p := Profile.load_from("")
	var s := RunState.create(1)
	s.tree.land.clear()
	var tree := s.tree
	Growth.place(tree, &"fruit", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"fruit", Vector2i(0, 1), _t([Vector2i.ZERO], 5))
	Growth.place(tree, &"vine", Vector2i(1, 0), _t([Vector2i(1, -1), Vector2i(0, 1)], -1))
	var res := s.preview()
	var msgs := p.record_pulse(s, tree, res)
	check(p.combo_found(&"fruitvine"), "果藤 recorded")
	check(msgs.any(func(m): return m.contains("果藤")), "message")
	check_eq(int(p.card_stats(&"vine").best), res.contrib[Vector2i(1, 0)])
	check_eq(int(p.card_stats(&"vine").runs), 1)
	p.record_pulse(s, tree, res)
	check_eq(int(p.card_stats(&"vine").runs), 1, "same run counted once")


func test_combo_detection_steam() -> void:
	var tree := TreeModel.create(5)
	Growth.place(tree, &"gear_cog", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	Growth.place(tree, &"gear_cog", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"forge_coal", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	Growth.place(tree, &"forge_coal", Hex.DIRS[4], _t([Vector2i.ZERO], 4))
	var res := Pulse.resolve(tree, Pulse.Context.for_season(1))
	check(Combos.detect(tree, res).has(&"steam"), "蒸汽机")
	for c in Combos.LIST:
		check(Combos.LIST[c].name != "" and Combos.LIST[c].desc != "", "combo %s described" % c)
