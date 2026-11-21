extends "res://tests/base_test.gd"
## 第二阶段机制：成熟、几何牌型、季节特性。


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


func _ctx(season: int = 1, maturity := false, patterns := false) -> Pulse.Context:
	var c := Pulse.Context.prototype(season)
	c.maturity = maturity
	c.patterns = patterns
	return c


func test_fruit_matures_with_cap() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	var f := Growth.place(tree, &"fruit", Vector2i(2, -2), _t([Vector2i(1, -1)], 1))
	var expect := {0: 8, 1: 10, 2: 12, 3: 14, 4: 16, 5: 16, 9: 16}  # 4 × (2 + min(0.5·age, 2))
	for age in expect:
		f.age = age
		check_eq(Pulse.resolve(tree, _ctx(1, true)).total, expect[age], "age %d" % age)
	f.age = 3
	check_eq(Pulse.resolve(tree, _ctx(1, false)).total, 8, "maturity off")


func test_gold_matures_to_x5() -> void:
	var tree := TreeModel.create(4)
	var g := Growth.place(tree, &"gold", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	g.age = 10
	check_eq(Pulse.resolve(tree, _ctx(4, true)).total, 8 * 5)


func test_ages_increase_each_pulse() -> void:
	var s := RunState.create(1)
	s.end_turn()
	s.end_turn()
	check_eq(s.tree.at(TreeModel.SEED_KEY).age, 2)


func _chain(length: int) -> TreeModel:
	# 从树心沿方向 1 直线长出 length 张茎
	var tree := TreeModel.create(8)
	var prev := Vector2i.ZERO
	for i in length:
		var c := prev + Hex.DIRS[1]
		Growth.place(tree, &"stem", c, _t([prev], 1))
		prev = c
	return tree


func test_long_stem() -> void:
	var five := _chain(5)
	check_eq(Pulse.resolve(five, _ctx(1, false, true)).total, 1 + 15)
	var six := _chain(6)
	var res := Pulse.resolve(six, _ctx(1, false, true))
	check_eq(res.total, (1 + 18) * 2)
	check_eq(res.patterns.size(), 1)
	check_eq(res.patterns[0].id, &"long")


func test_star_doubles_outflow() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"tri", Vector2i(2, -2), _t([Vector2i(1, -1)], 1))
	# 三叉朝向 1，芽点 0/1/2
	for d in [0, 1, 2]:
		Growth.place(tree, &"stem", Vector2i(2, -2) + Hex.DIRS[d], _t([Vector2i(2, -2)], d))
	# 三叉流出 (4-2)=2；星芒 ×2 → 4；三根茎各 7
	check_eq(Pulse.resolve(tree, _ctx(1)).total, 3 * 5)
	var res := Pulse.resolve(tree, _ctx(1, false, true))
	check_eq(res.total, 3 * 7)
	check_eq(res.patterns[0].id, &"star")


func test_loop_graft_doubles() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"fork", Vector2i(2, -2), _t([Vector2i(1, -1)], 1))
	Growth.place(tree, &"fruit", Vector2i(3, -2), _t([Vector2i(2, -2)], 0))
	Growth.place(tree, &"fruit", Vector2i(2, -3), _t([Vector2i(2, -2)], 2))
	Growth.place(tree, &"vine", Vector2i(3, -3), _t([Vector2i(3, -2), Vector2i(2, -3)], -1))
	check_eq(Pulse.resolve(tree, _ctx(1)).total, 64)
	check_eq(Pulse.resolve(tree, _ctx(1, false, true)).total, 128)


func test_graft_across_seed_is_not_loop() -> void:
	# 两个父牌只在树心汇合，不算闭环
	var tree := TreeModel.create(4)
	Growth.place(tree, &"fruit", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"fruit", Vector2i(0, 1), _t([Vector2i.ZERO], 5))
	Growth.place(tree, &"vine", Vector2i(1, 0), _t([Vector2i(1, -1), Vector2i(0, 1)], -1))
	var res := Pulse.resolve(tree, _ctx(1, false, true))
	check_eq(res.total, 4)
	check(res.patterns.is_empty(), "no loop")


func test_symmetry() -> void:
	var tree := TreeModel.create(4)
	var dirs := [1, 3, 5]
	for d in dirs:
		var a: Vector2i = Hex.DIRS[d]
		Growth.place(tree, &"stem", a, _t([Vector2i.ZERO], d))
	check(not Pulse.is_symmetric(tree), "three arms are not point-symmetric")
	# 对称位置放不同类的牌也不算
	var tree2 := TreeModel.create(4)
	for d in [0, 1, 2]:
		Growth.place(tree2, &"stem", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	for d in [3, 4, 5]:
		Growth.place(tree2, &"fruit", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	check(not Pulse.is_symmetric(tree2), "types differ at mirrored cells")
	var tree3 := TreeModel.create(4)
	for d in [0, 1, 2, 3, 4, 5]:
		Growth.place(tree3, &"fruit", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	check(Pulse.is_symmetric(tree3), "six fruits around the seed")
	var res := Pulse.resolve(tree3, _ctx(1, false, true))
	check_eq(res.total, int(floor(6 * 2 * 1.5)))


func test_autumn_end_mult() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Vector2i(1, -1), _t([Vector2i.ZERO], 1))
	Growth.place(tree, &"fruit", Vector2i(2, -2), _t([Vector2i(1, -1)], 1))
	# 秋季树心 4：(4+3)×2 = 14，×1.5 = 21
	check_eq(Pulse.resolve(tree, Pulse.Context.prototype(3)).total, 14)
	var c := Pulse.Context.for_season(3)
	c.maturity = false
	c.patterns = false
	check_eq(Pulse.resolve(tree, c).total, 21)


func test_season_hand_and_plays() -> void:
	check_eq(Rules.hand_size(1), Rules.HAND + 1)
	check_eq(Rules.hand_size(2), Rules.HAND)
	check_eq(Rules.plays_per_turn(2), Rules.PLAYS + 1)
	check_eq(Rules.plays_per_turn(3), Rules.PLAYS)
	var s := RunState.create(5)
	check_eq(s.hand.size(), Rules.HAND + 1)
	check_eq(s.plays, Rules.PLAYS)


func test_winter_wither_removes_oldest_tips() -> void:
	var s := RunState.create(5)
	for d in [1, 3, 5]:
		Growth.place(s.tree, &"stem", Hex.DIRS[d], _t([Vector2i.ZERO], d))
	Growth.place(s.tree, &"fruit", Hex.DIRS[1] * 2, _t([Hex.DIRS[1]], 1))
	# 末梢按放置顺序：茎(3)、茎(5)、果(1×2)；最老的两个是两根茎
	var gone := s.wither(2)
	check_eq(gone, [Hex.DIRS[3], Hex.DIRS[5]] as Array[Vector2i])
	check_eq(s.tree.size(), 3)
	check(s.discard.has(&"stem"), "withered cards go to discard")
