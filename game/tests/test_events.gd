extends "res://tests/base_test.gd"
## 阶段 D：局间事件。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


## 一局走到第一季选牌之后、刚好遇到事件的状态。
func _at_event(ev: StringName, run_seed: int = 3) -> RunState:
	var s := RunState.create(run_seed)
	Growth.place(s.tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(s.tree, &"fruit", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	Growth.place(s.tree, &"stem", Hex.DIRS[3], _t([Vector2i.ZERO], 3))
	s.sap = 20
	s.phase = RunState.Phase.EVENT
	s.event_id = ev
	return s


func test_every_option_applies() -> void:
	for ev in RunEvents.LIST:
		var info: Dictionary = RunEvents.LIST[ev]
		check(info.title != "" and info.text != "", "%s described" % ev)
		check(info.options.size() >= 2, "%s has choices" % ev)
		var has_free := false
		for i in info.options.size():
			var s := _at_event(ev)
			if not s.relics.is_empty():
				pass
			s.relics.append(&"dew")
			if RunEvents.blocked(s, ev, i) == "":
				has_free = has_free or int(info.options[i].get("cost", 0)) == 0
				check(s.choose_event(i), "%s option %d" % [ev, i])
				check_eq(s.phase, RunState.Phase.MARKET, "%s → market" % ev)
				check(not s.event_result.is_empty(), "%s option %d result" % [ev, i])
				check(s.seen_events.has(ev), "%s seen" % ev)
				check(s.sap >= 0, "sap never negative")
		check(has_free, "%s has a free option" % ev)


func test_event_follows_reward_sometimes() -> void:
	var events := 0
	var markets := 0
	for seed_i in 40:
		var s := RunState.create(100 + seed_i)
		s.phase = RunState.Phase.REWARD
		s.reward_options = [&"stem"] as Array[StringName]
		s.choose_reward(0)
		if s.phase == RunState.Phase.EVENT:
			events += 1
			check(RunEvents.LIST.has(s.event_id), "valid event")
		elif s.phase == RunState.Phase.MARKET:
			markets += 1
	check(events > 5 and markets > 5, "both happen (%d events, %d markets)" % [events, markets])


func test_blocked_and_cost() -> void:
	var s := _at_event(&"dice")
	s.sap = 2
	check(RunEvents.blocked(s, &"dice", 0) != "", "too poor to gamble")
	check(not s.choose_event(0), "cannot choose blocked option")
	check(s.choose_event(1), "walk away")
	var t := _at_event(&"taxman")
	t.relics.clear()
	check(RunEvents.blocked(t, &"taxman", 1) != "", "no relic to hand over")


func test_available_filters() -> void:
	var s := RunState.create(1, &"gardener", [&"wood", &"gear"])
	var av := RunEvents.available(s)
	check(av.has(&"workshop"), "gear event allowed")
	check(not av.has(&"mirror_lake"), "mirror locked")
	s.seen_events.append(&"well")
	check(not RunEvents.available(s).has(&"well"), "no repeats in a run")


func test_market_discount_and_transplants() -> void:
	var s := _at_event(&"wanderer")
	s.choose_event(0)
	check_eq(s.market_discount, 0.5)
	var id := s.market_cards[0]
	check_eq(s.card_price(id), maxi(1, int(round(Cards.get_def(id).price * 0.5))))
	s.leave_market()
	check_eq(s.market_discount, 1.0, "discount used up")
	var t := _at_event(&"landslide")
	t.choose_event(0)
	t.leave_market()
	check_eq(t.transplants, Rules.TRANSPLANTS + 3)


func test_debt_curse() -> void:
	var s := _at_event(&"creditor")
	var before := s.sap
	s.choose_event(0)
	check_eq(s.sap, before + 15)
	check(s.deck_counts().has(RunEvents.DEBT), "debt in deck")
	check(not Cards.pool_ids().has(RunEvents.DEBT), "debt never offered")
	var tree := TreeModel.create(5)
	Growth.place(tree, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, RunEvents.DEBT, Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	var c := Pulse.Context.for_season(1)
	c.maturity = false
	c.patterns = false
	check_eq(Pulse.resolve(tree, c).total, 4 - 2)


func test_whisper_thins_deck() -> void:
	var s := _at_event(&"whisper")
	var n0: int = s.deck_counts().get(&"dead", 0)
	s.choose_event(0)
	check_eq(int(s.deck_counts().get(&"dead", 0)), maxi(0, n0 - 2))


func test_save_roundtrip_event() -> void:
	var s := _at_event(&"omen")
	s.market_discount = 0.5
	s.bonus_transplants = 2
	s.seen_events.append(&"well")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(s2.event_id, &"omen")
	check_eq(s2.phase, RunState.Phase.EVENT)
	check_eq(s2.market_discount, 0.5)
	check_eq(s2.bonus_transplants, 2)
	check_eq(s2.seen_events, [&"well"] as Array[StringName])
