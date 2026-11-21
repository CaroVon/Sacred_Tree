extends SceneTree
## 无头测试入口：godot --headless --path game -s tests/run_tests.gd
## 自动发现 tests/test_*.gd 中所有 test_ 开头的方法。


func _initialize() -> void:
	var dir := "res://tests"
	var total := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f: String in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var t = load(dir.path_join(f)).new()
		for m in t.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			t.current = "%s::%s" % [f.get_basename(), name]
			var before: int = t.failures.size()
			t.call(name)
			total += 1
			if t.failures.size() > before:
				failed += 1
				print("FAIL  ", t.current)
				for x in t.failures.slice(before, before + 8):
					print("      ", x)
			else:
				print("ok    ", t.current)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
