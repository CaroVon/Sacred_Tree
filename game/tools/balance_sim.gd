extends SceneTree
## 平衡模拟：无头批量跑局，输出每季通过率与得分分布。
## godot --headless --path game -s tools/balance_sim.gd -- <runs> <greedy|planner> <real|free> [seed_start] [out.csv]
##   real：按真实目标，统计到达率、条件通过率、通关率。
##   free：忽略目标一路打完三年，统计每季得分的分位数（用来校准目标）。


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var runs := int(a[0]) if a.size() > 0 else 100
	var policy := Bot.Policy.PLANNER if a.size() > 1 and a[1] == "planner" else Bot.Policy.GREEDY
	var free := a.size() > 2 and a[2] == "free"
	var seed0 := int(a[3]) if a.size() > 3 else 1
	var out := a[4] if a.size() > 4 else ""
	var t0 := Time.get_ticks_msec()
	var bot := Bot.make(policy)
	var results := []
	for r in runs:
		results.append(bot.run_game(seed0 + r, free))
	var lines: Array[String] = []
	lines.append("# %d 局，策略 %s，模式 %s，用时 %.1f 秒" % [runs, Bot.Policy.keys()[policy], "free" if free else "real", (Time.get_ticks_msec() - t0) / 1000.0])
	if free:
		lines.append("year,season,target,p10,p25,p50,p75,p90,share_ge_target")
	else:
		lines.append("year,season,target,reached,passed,pass_rate_given_reached,cumulative")
	for y in range(1, Rules.YEARS + 1):
		for st in range(1, Rules.STAGES + 1):
			var scores: Array[int] = []
			var passed := 0
			for res in results:
				for sg in res.stages:
					if sg.year == y and sg.season == st:
						scores.append(sg.score)
						if sg.passed:
							passed += 1
			var tgt := Rules.target(st, y)
			if free:
				scores.sort()
				lines.append("%d,%s,%d,%s,%s,%s,%s,%s,%.2f" % [y, Rules.season_name(st), tgt,
					_pct(scores, 0.1), _pct(scores, 0.25), _pct(scores, 0.5), _pct(scores, 0.75), _pct(scores, 0.9),
					passed / maxf(1.0, scores.size())])
			else:
				lines.append("%d,%s,%d,%d,%d,%.2f,%.2f" % [y, Rules.season_name(st), tgt, scores.size(), passed,
					passed / maxf(1.0, scores.size()), passed / float(runs)])
	if not free:
		var won := results.filter(func(r): return r.won).size()
		lines.append("# 通关 %d / %d（%.1f%%）" % [won, runs, 100.0 * won / runs])
	for l in lines:
		print(l)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines) + "\n")
	quit()


func _pct(a: Array[int], p: float) -> String:
	if a.is_empty():
		return "-"
	return str(a[clampi(int(p * (a.size() - 1)), 0, a.size() - 1)])
