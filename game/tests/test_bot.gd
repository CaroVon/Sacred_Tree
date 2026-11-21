extends "res://tests/base_test.gd"


func test_bots_finish_a_game() -> void:
	for p in [Bot.Policy.GREEDY, Bot.Policy.PLANNER]:
		var r := Bot.make(p).run_game(3)
		check(not r.stages.is_empty(), "bot %d played no stage" % p)
		check(r.stages[0].year == 1 and r.stages[0].season == 1, "first stage is year 1 spring")


func test_free_mode_never_loses() -> void:
	var r := Bot.make(Bot.Policy.GREEDY).run_game(5, true)
	check(r.won, "ignore_targets should play through all years")
	check_eq(r.stages.size(), Rules.YEARS * Rules.STAGES)
