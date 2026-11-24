extends SceneTree
## 开发工具：连拍一次脉动的计分演出（流动 → 末梢 → 牌型 → 重击 → 达标）。
## godot --path game -s tools/pulse_shots.gd -- <目录> [greedy_turns] [seed] [间隔毫秒] [张数]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var turns: int = int(a[1]) if a.size() > 1 else 3
	var run_seed: int = int(a[2]) if a.size() > 2 else 5
	var step: int = int(a[3]) if a.size() > 3 else 250
	var n: int = int(a[4]) if a.size() > 4 else 16
	var game = root.get_node("Game")
	game.profile = Profile.load_from("")
	game.volume = 0.0
	game.music_volume = 0.0
	game.ambience_volume = 0.0
	game.apply_volumes()
	game.run = RunState.create(run_seed)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var r: RunState = game.run
	for t in turns:
		_greedy(r)
		r.end_turn()
		if r.phase != RunState.Phase.PLAY:
			break
	_greedy(r)
	# near：差一点达标（看「达标」横幅）；over：差一点到 10 倍（看「超额」印章）
	if a.has("near"):
		r.score = maxi(0, r.target() - 5)
	if a.has("over"):
		r.score = r.target() * 10 - 5
	change_scene_to_file(game.SCENES[&"season"])
	for i in 30:
		await process_frame
	current_scene._end_turn()
	for i in n:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < step:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("p%02d.png" % i))
	print("done")
	quit()


func _greedy(s: RunState) -> void:
	while s.plays > 0:
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
			return
		s.place(bi, bk)
