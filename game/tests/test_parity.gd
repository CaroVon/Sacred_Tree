extends "res://tests/base_test.gd"
## 与网页原型逐步比对：同样的操作序列，可放置格、父牌、朝向、每个节点的养分和总分必须完全一致。
## 夹具由 tools/parity/export_fixtures.mjs 从 shentree_prototype.html 生成。

const FIXTURE := "res://tests/fixtures/parity.json"


func _key(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func _kstr(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]


func test_matches_prototype() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not check(data is Array, "fixture missing"):
		return
	var steps_checked := 0
	for si in data.size():
		var sc: Dictionary = data[si]
		var ctx := Pulse.Context.prototype(int(sc.season))
		var tree := TreeModel.create(4)
		for st_i in sc.steps.size():
			var st: Dictionary = sc.steps[st_i]
			var tag := "scenario %d step %d" % [si, st_i]
			var k := _key(st.key)
			if st.op == "place":
				var tg := Growth.targets_for(tree, StringName(st.type), ctx)
				var keys: Array = tg.keys().map(_kstr)
				keys.sort()
				var expect_keys: Array = st.targets.duplicate()
				expect_keys.sort()
				if not check_eq(keys, expect_keys, tag + " targets"):
					return
				var info: Growth.Target = tg[k]
				if not check_eq(Array(info.parents), st.parents.map(_key), tag + " parents"):
					return
				if not check_eq(info.facing, int(st.facing), tag + " facing"):
					return
				Growth.place(tree, StringName(st.type), k, info)
			else:
				var set := Growth.subtree(tree, k)
				check_eq(set.size(), int(st.removed), tag + " removed")
				Growth.remove_set(tree, set)
			var res := Pulse.resolve(tree, ctx)
			if not check_eq(res.total, int(st.total), tag + " total"):
				return
			for ks: String in st.out:
				var p := ks.split(",")
				var kk := Vector2i(int(p[0]), int(p[1]))
				if not check_eq(res.out.get(kk), int(st.out[ks]), tag + " out@" + ks):
					return
			steps_checked += 1
	check(steps_checked > 1000, "too few steps checked: %d" % steps_checked)
