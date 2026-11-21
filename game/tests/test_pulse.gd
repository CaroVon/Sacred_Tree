extends "res://tests/base_test.gd"


func _t(parents: Array, facing: int) -> Growth.Target:
	var t := Growth.Target.new()
	t.parents.assign(parents)
	t.facing = facing
	return t


## 设计文档中的计分示例：22，嫁接后 112。
func _design_tree() -> TreeModel:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Vector2i(1, -1), _t([Vector2i(0, 0)], 1))
	Growth.place(tree, &"fork", Vector2i(2, -2), _t([Vector2i(1, -1)], 1))
	Growth.place(tree, &"fruit", Vector2i(3, -2), _t([Vector2i(2, -2)], 0))
	Growth.place(tree, &"stem", Vector2i(2, -3), _t([Vector2i(2, -2)], 2))
	Growth.place(tree, &"fruit", Vector2i(2, -4), _t([Vector2i(2, -3)], 2))
	return tree


func test_design_example() -> void:
	var tree := _design_tree()
	var ctx := Pulse.Context.prototype(1)
	check_eq(Pulse.resolve(tree, ctx).total, 22)
	Growth.place(tree, &"vine", Vector2i(3, -3), _t([Vector2i(3, -2), Vector2i(2, -4)], -1))
	var res := Pulse.resolve(tree, ctx)
	check_eq(res.total, 112)
	check_eq(Array(res.tip_list), [Vector2i(3, -3)])


func test_seed_alone_is_tip() -> void:
	var tree := TreeModel.create(4)
	for s in range(1, 5):
		check_eq(Pulse.resolve(tree, Pulse.Context.prototype(s)).total, Rules.seed_out(s))


func test_fork_ports_follow_facing() -> void:
	var tree := _design_tree()
	check_eq(Array(Growth.ports_of(tree.at(Vector2i(2, -2)))), [0, 2])


func test_graft_targets() -> void:
	var tree := TreeModel.create(4)
	Growth.place(tree, &"stem", Vector2i(1, -1), _t([Vector2i(0, 0)], 1))
	Growth.place(tree, &"fork", Vector2i(2, -2), _t([Vector2i(1, -1)], 1))
	Growth.place(tree, &"fruit", Vector2i(3, -2), _t([Vector2i(2, -2)], 0))
	Growth.place(tree, &"fruit", Vector2i(2, -3), _t([Vector2i(2, -2)], 2))
	var tg := Growth.targets_for(tree, &"vine", Pulse.Context.prototype(1))
	if check(tg.has(Vector2i(3, -3)), "vine should fit between the two fruits"):
		check_eq(tg[Vector2i(3, -3)].parents.size(), 2)


func test_flower_aura() -> void:
	var tree := TreeModel.create(4)
	# 树心芽点方向 1、3、5：(1,-1) (-1,0) (0,1)
	Growth.place(tree, &"fruit", Vector2i(1, -1), _t([Vector2i(0, 0)], 1))
	Growth.place(tree, &"flower", Vector2i(-1, 0), _t([Vector2i(0, 0)], 3))
	check_eq(Pulse.resolve(tree, Pulse.Context.prototype(1)).total, 4)
	# 花 (-1,0) 的子枝：茎接在花上不行（末端），改为在 (-1,1) 放一个与花相邻的末梢
	Growth.place(tree, &"stem", Vector2i(0, 1), _t([Vector2i(0, 0)], 5))
	Growth.place(tree, &"fruit", Vector2i(-1, 1), _t([Vector2i(0, 1)], 3))
	# 果(-1,1) = (1+3)*2 = 8，与花相邻 +3；果(1,-1)=2；花=2
	check_eq(Pulse.resolve(tree, Pulse.Context.prototype(1)).total, 2 + 2 + 8 + 3)


func test_prune_subtree_includes_graft() -> void:
	var tree := _design_tree()
	Growth.place(tree, &"vine", Vector2i(3, -3), _t([Vector2i(3, -2), Vector2i(2, -4)], -1))
	var set := Growth.subtree(tree, Vector2i(2, -3))
	check_eq(set.size(), 3)  # 茎、果、藤
	Growth.remove_set(tree, set)
	check_eq(tree.size(), 4)
	check_eq(tree.at(Vector2i(3, -2)).children.size(), 0)
	check_eq(Pulse.resolve(tree, Pulse.Context.prototype(1)).total, 8)
