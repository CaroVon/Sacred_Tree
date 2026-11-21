extends "res://tests/base_test.gd"
## 规则层的解释功能：算式记录必须与真实计分一致；不能放置的原因要准确。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


func _ex(season: int = 1) -> Pulse.Context:
	var c := Pulse.Context.for_season(season)
	c.explain = true
	return c


func _check_traces(tree: TreeModel, ctx: Pulse.Context, tag: String) -> void:
	var res := Pulse.resolve(tree, ctx)
	for k in res.out:
		var tr: Array = res.trace.get(k, [])
		if check(not tr.is_empty(), "%s: missing trace at %s" % [tag, k]):
			check_eq(tr[-1].result, res.out[k], "%s: trace end at %s" % [tag, k])
	for k in res.tip_list:
		var tt: Array = res.tip_trace.get(k, [])
		if check(not tt.is_empty(), "%s: missing tip trace at %s" % [tag, k]):
			check_eq(tt[-1].result, res.contrib[k], "%s: tip trace end at %s" % [tag, k])


func test_trace_matches_design_example() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"fork", Vector2i(2, -2), _t([Vector2i(1, -1)], 1))
	Growth.place(tree, &"fruit", Vector2i(3, -2), _t([Vector2i(2, -2)], 0))
	Growth.place(tree, &"fruit", Vector2i(2, -3), _t([Vector2i(2, -2)], 2))
	var res := Pulse.resolve(tree, _ex())
	check_eq(Pulse.chain_text(res.trace[Vector2i(1, -1)]), "来自树心 1 → 茎 +3 = 4")
	check_eq(res.trace[Vector2i(2, -2)][1].op, "复制")
	Growth.place(tree, &"vine", Vector2i(3, -3), _t([Vector2i(3, -2), Vector2i(2, -3)], -1))
	_check_traces(tree, _ex(), "vine")
	var r2 := Pulse.resolve(tree, _ex())
	check_eq(r2.trace[Vector2i(3, -3)][0].op, "嫁接相乘 8 × 8")
	check_eq(r2.trace[Vector2i(3, -3)][-1].label, "闭环")


func test_explain_does_not_change_scores() -> void:
	for sd in [1, 2, 3, 4, 5]:
		var s := RunState.create(sd)
		var bot := Bot.make(Bot.Policy.PLANNER)
		for t in 8:
			bot.play_turn(s)
			var a := Pulse.resolve(s.tree, s.ctx())
			var c := s.ctx()
			c.explain = true
			var b := Pulse.resolve(s.tree, c)
			check_eq(b.total, a.total, "seed %d turn %d" % [sd, t])
			check_eq(b.contrib, a.contrib)
			_check_traces(s.tree, c, "seed %d turn %d" % [sd, t])
			s.end_turn()
			if s.phase != RunState.Phase.PLAY:
				break


func test_tip_trace_lists_bonuses() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"fruit", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"flower", Hex.DIRS[0], _t([Vector2i.ZERO], 0))
	tree.land[Vector2i(2, -2)] = Land.Type.SPRING
	var res := Pulse.resolve(tree, _ex())
	var labels: Array = res.tip_trace[Hex.DIRS[1]].map(func(s): return s.label)
	check(labels.has("相邻的花"), "flower bonus listed: %s" % str(labels))
	check(labels.has("相邻的泉眼"), "spring bonus listed: %s" % str(labels))


func test_effect_text() -> void:
	var n := TreeNode.new()
	n.age = 2
	n.depth = 3
	check_eq(Pulse.effect_text(Cards.get_def(&"fruit"), n), "×3")
	check_eq(Pulse.effect_text(Cards.get_def(&"stem"), n), "+3")
	check_eq(Pulse.effect_text(Cards.get_def(&"node"), n), "+深度 3")
	check_eq(Pulse.effect_text(Cards.get_def(&"fork"), n), "复制")
	check_eq(Pulse.effect_text(Cards.get_def(&"vine"), n), "相乘")


func test_why_not_reasons() -> void:
	var tree := TreeModel.create(4)
	var ctx := Pulse.Context.for_season(1)
	Growth.place(tree, &"fruit", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	tree.land[Hex.DIRS[3]] = Land.Type.ROCK
	tree.land[Hex.DIRS[5]] = Land.Type.SPRING
	check(Growth.why_not(tree, &"stem", Hex.DIRS[1], ctx).contains("已经长了果"), "occupied")
	check(Growth.why_not(tree, &"stem", Hex.DIRS[3], ctx).contains("岩石"), "rock")
	check(Growth.why_not(tree, &"stem", Hex.DIRS[5], ctx).contains("泉眼"), "spring")
	check(Growth.why_not(tree, &"stem", Hex.DIRS[1] * 2, ctx).contains("末端"), "behind end card")
	check(Growth.why_not(tree, &"stem", Hex.DIRS[0], ctx).contains("没有芽点朝向"), "seed bud direction")
	check(Growth.why_not(tree, &"stem", Vector2i(-3, 3), ctx).contains("太远"), "far away")
	check(Growth.why_not(tree, &"vine", Vector2i(-3, 3), ctx).contains("末梢"), "graft needs tips")
	check(Growth.why_not(tree, &"stem", Vector2i(9, 9), ctx).contains("牌桌外"), "off board")
	var t2 := TreeModel.create(4)
	Growth.place(t2, &"stem", Hex.DIRS[1], _t([Vector2i.ZERO], 1))
	check(Growth.why_not(t2, &"oak", Hex.DIRS[1] * 2, ctx).contains("深度"), "oak depth")
	check_eq(Growth.why_not(t2, &"stem", Hex.DIRS[1] * 2, ctx), "")


func test_bud_report_and_hand_reason() -> void:
	var tree := TreeModel.create(4)
	var ctx := Pulse.Context.for_season(1)
	check_eq(Growth.open_bud_count(tree, ctx), 3)
	for d in [1, 3, 5]:
		Growth.place(tree, &"fruit", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	check_eq(Growth.open_bud_count(tree, ctx), 0)
	var occ := Growth.bud_report(tree, ctx).filter(func(b): return b.status == &"occupied")
	check_eq(occ.size(), 3)
	check(Growth.hand_reason(tree, &"stem", ctx).contains("修剪"), "suggest pruning")
