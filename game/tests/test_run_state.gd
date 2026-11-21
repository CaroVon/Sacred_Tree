extends "res://tests/base_test.gd"


func test_new_run_deals_hand() -> void:
	var s := RunState.create(42)
	check_eq(s.hand.size(), Rules.hand_size(1))
	var total := 0
	for t in Rules.START_DECK:
		total += Rules.START_DECK[t]
	check_eq(s.hand.size() + s.deck.size(), total)
	check_eq(s.preview().total, 1)


func test_same_seed_same_deck() -> void:
	check_eq(RunState.create(7).deck, RunState.create(7).deck)


func _play_greedy_turn(s: RunState) -> void:
	while s.plays > 0:
		var best := -1
		var best_i := -1
		var best_k := Vector2i.ZERO
		for i in s.hand.size():
			for k in s.targets_for_hand(i):
				var v := s.preview_place(i, k)
				if v > best:
					best = v
					best_i = i
					best_k = k
		if best_i < 0:
			break
		s.place(best_i, best_k)


func test_full_season_flow() -> void:
	var s := RunState.create(3)
	for i in Rules.TURNS:
		check_eq(s.phase, RunState.Phase.PLAY)
		_play_greedy_turn(s)
		s.end_turn()
	check(s.phase != RunState.Phase.PLAY, "season should end after %d turns" % Rules.TURNS)
	if s.phase == RunState.Phase.REWARD:
		check_eq(s.reward_options.size(), Rules.REWARD_CHOICES)
		var n := s.tree.size()
		s.choose_reward(0)
		_skip_event(s)
		check_eq(s.phase, RunState.Phase.MARKET)
		s.leave_market()
		check_eq(s.season, 2)
		check_eq(s.tree.size(), n, "tree persists across seasons")
		check_eq(s.hand.size(), Rules.hand_size(2))


func test_prune_gives_sap() -> void:
	var s := RunState.create(11)
	_play_greedy_turn(s)
	var k: Vector2i = s.tree.sorted()[1].key
	var pv := s.preview_prune(k)
	var gain := s.prune(k)
	check_eq(gain, pv.gain)
	check_eq(s.sap, gain)
	check(s.hand_fresh.has(true) or s.exhausted.size() > 0, "pruned cards return to hand or exhaust")
	check_eq(s.preview().total, pv.total)
	check_eq(s.prune(k), -1, "only one prune per turn")


func test_save_roundtrip() -> void:
	var s := RunState.create(99)
	_play_greedy_turn(s)
	s.end_turn()
	_play_greedy_turn(s)
	var json := JSON.stringify(s.to_dict())
	var s2 := RunState.from_dict(JSON.parse_string(json))
	check_eq(JSON.stringify(s2.to_dict()), json)
	check_eq(s2.preview().total, s.preview().total)
	# 随机数流也必须一致
	s.end_turn()
	s2.end_turn()
	check_eq(s2.hand, s.hand)


func _skip_event(s: RunState) -> void:
	if s.phase == RunState.Phase.EVENT:
		for i in RunEvents.LIST[s.event_id].options.size():
			if RunEvents.blocked(s, s.event_id, i) == "" and s.choose_event(i):
				return
