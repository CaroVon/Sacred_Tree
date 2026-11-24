extends SceneTree
## 开发工具：通过各场景的输入入口（选牌 → 点格子 → 结束回合 → 选奖励 → 地图 → 器物 → 集市）自动打完整局，
## 用来发现界面层的运行时错误。godot --headless --path game -s tools/ui_smoke.gd -- [runs]

var game
var easy := false
var events_seen := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	easy = args.has("easy")
	_go.call_deferred(int(args[0]) if args.size() > 0 else 5)


func _settle() -> void:
	for i in 3:
		await process_frame


func _go(runs: int) -> void:
	game = root.get_node("Game")
	# 开发工具不碰玩家的收藏与解锁：用只在内存里的 profile
	game.profile = Profile.load_from("")
	# 开发工具静音（不在玩家的音箱里放音乐）
	game.music_volume = 0.0
	game.ambience_volume = 0.0
	game.apply_volumes()
	# 默认关闭动画加速；传 anim 参数时保留动画以覆盖动画路径
	game.reduce_motion = not OS.get_cmdline_user_args().has("anim")
	var summary := []
	for r in runs:
		game.new_run(100 + r)
		await _settle()
		var guard := 0
		while game.run.phase != RunState.Phase.LOST and game.run.phase != RunState.Phase.WON:
			# 动画模式下换场景有转场：等转场结束、新场景就位
			if current_scene == null or game._wiping or (current_scene.get("board") != null and current_scene.board.has_method("is_animating") and current_scene.board.is_animating()):
				await _settle()
				continue
			guard += 1
			if guard > 400:
				summary.append("seed %d: STUCK in %s" % [100 + r, current_scene.name])
				break
			var sc = current_scene
			match String(sc.name):
				"YearMap":
					game.goto(&"season")
				"Market":
					_shop(sc)
					sc._leave()
				"Event":
					events_seen += 1
					for i in RunEvents.LIST[game.run.event_id].options.size():
						if RunEvents.blocked(game.run, game.run.event_id, i) == "":
							sc._choose(i)
							break
					game.goto(&"market")
				"Season":
					_play_season_step(sc)
				_:
					game.goto(&"season")
			await _settle()
		summary.append("seed %d: %s 第%d年 %s 累计 %d 器物 %d 树 %d" % [100 + r, RunState.Phase.keys()[game.run.phase],
			game.run.year, Rules.season_name(game.run.season), game.run.score, game.run.relics.size(), game.run.tree.size()])
	summary.append("事件页：%d 次" % events_seen)
	for l in summary:
		print(l)
	game.clear_save()
	quit()


func _play_season_step(sc) -> void:
	var s: RunState = game.run
	match s.phase:
		RunState.Phase.REWARD:
			sc._choose_reward(0)
			return
		RunState.Phase.RELIC:
			sc._choose_relic(0)
			if s.phase == RunState.Phase.RELIC:
				sc._replace_relic(0, 0)
			return
		RunState.Phase.DISCARD:
			sc._select(0)
			return
	if s.can_harvest() and s.turn >= 3:
		sc._harvest()
		return
	# 每季第 2 回合试一次移栽
	if s.turn == 2 and s.can_transplant() and s.tree.size() > 2:
		for n: TreeNode in s.tree.sorted():
			var tg := s.transplant_targets(n.key)
			if not tg.is_empty():
				sc._toggle_transplant()
				sc._on_cell_hovered(n.key)
				sc._on_cell_clicked(n.key)
				var to: Vector2i = tg.keys()[0]
				sc._on_cell_hovered(to)
				sc._on_cell_clicked(to)
				break
	if not _any_play(s) and s.can_prune() and s.tree.size() > 3:
		var k: Vector2i = s.tree.sorted()[-1].key
		sc._toggle_prune()
		sc._on_cell_hovered(k)
		sc._on_cell_clicked(k)
	while s.plays > 0 and s.phase == RunState.Phase.PLAY:
		var best := -1
		var bi := -1
		var bk := Vector2i.ZERO
		for i in s.hand.size():
			for k in s.targets_for_hand(i):
				var v := s.preview_place(i, k)
				if v > best:
					best = v
					bi = i
					bk = k
		if bi < 0:
			break
		var before := s.plays
		sc._select(bi)
		sc._on_cell_hovered(bk)
		sc._on_cell_clicked(bk)
		if s.plays == before:
			break
	if easy and s.turn == s.turns_this_season():
		s.score = maxi(s.score, s.target())
	sc._end_turn()


func _shop(sc) -> void:
	var s: RunState = game.run
	s.sap += 40  # 让集市的每条路径都被走到
	sc._buy(0)
	sc._buy_relic(0)
	if s.relics.size() > 3:
		sc._sell_relic(0)
	sc._remove(&"dead")
	for n: TreeNode in s.tree.sorted():
		if not n.is_seed() and not Growth.free_port_dirs(n).is_empty():
			sc._start_pick(sc.Pick.PORT, &"")
			sc._on_cell(n.key)
			var d: int = Growth.free_port_dirs(n)[0]
			sc._on_cell(n.key + Hex.DIRS[d])
			break
	var tip := s.tree.sorted()[-1].key
	sc._start_pick(sc.Pick.MARK, &"tough")
	sc._on_cell(tip)
	for c in s.tree.land:
		if s.tree.land[c] == Land.Type.ROCK:
			sc._start_pick(sc.Pick.CLEAR_ROCK, &"")
			sc._on_cell(c)
			break
	sc._start_pick(sc.Pick.FERTILE, &"")
	for c in Hex.all_cells(s.tree.radius):
		if s.can_make_fertile(c):
			sc._on_cell(c)
			break


func _any_play(s: RunState) -> bool:
	for i in s.hand.size():
		if s.can_play(i):
			return true
	return false
