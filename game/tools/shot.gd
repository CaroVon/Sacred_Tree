extends SceneTree
## 开发工具：自动打开某个场景、可选执行几步贪心操作，然后截图退出。
## godot --path game -s tools/shot.gd -- <scene> <out.png> [greedy_turns] [seed]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: String = args[0] if args.size() > 0 else "season"
	var out: String = args[1] if args.size() > 1 else "user://shot.png"
	var turns: int = int(args[2]) if args.size() > 2 else 0
	var run_seed: int = int(args[3]) if args.size() > 3 else 5
	_run.call_deferred(scene, out, turns, run_seed)


func _run(scene: String, out: String, turns: int, run_seed: int) -> void:
	var game = root.get_node("Game")
	# 开发工具不碰玩家的收藏与解锁：用只在内存里的 profile
	game.profile = Profile.load_from("")
	game.run = RunState.create(run_seed)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	# demo：发一手新流派的牌，看共鸣面板与新牌牌面
	if OS.get_cmdline_user_args().has("demo"):
		var r: RunState = game.run
		r.hand.clear()
		r.hand_fresh.clear()
		for id in [&"gear_cog", &"gear_link", &"gear_cog", &"forge_furnace", &"forge_coal", &"gear_core", &"forge_ember"]:
			r.hand.append(id)
			r.hand_fresh.append(false)
		r.heat = 6
	for t in turns:
		_greedy(game.run)
		game.run.end_turn()
		if OS.get_cmdline_user_args().has("demo"):
			var r2: RunState = game.run
			r2.hand.clear()
			r2.hand_fresh.clear()
			for id in [&"gear_cog", &"gear_link", &"gear_hub", &"forge_furnace", &"gear_escape", &"gear_core", &"forge_bellows"]:
				r2.hand.append(id)
				r2.hand_fresh.append(false)
	if scene == "event":
		game.run.phase = RunState.Phase.EVENT
		game.run.event_id = &"wanderer"
		game.run.sap = 12
	if scene == "market":
		game.run.sap = 30
		game.run.relics.append(&"dew")
		game.run._open_market()
	var path: String = game.SCENES[StringName(scene)]
	change_scene_to_file(path)
	for i in 20:
		await process_frame
	if OS.get_cmdline_user_args().has("pulse") and current_scene.has_method("_end_turn"):
		current_scene._end_turn()
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 520:
			await process_frame
	elif current_scene.has_method("_select") and game.run.hand.size() > 0 and game.run.can_play(0):
		current_scene._select(0)
	if OS.get_cmdline_user_args().has("starter") and current_scene.has_method("_pick_starter"):
		current_scene._pick_starter()
	var bd = current_scene.get("board")
	if OS.get_cmdline_user_args().has("zoom") and bd != null and bd.has_method("zoom_at"):
		bd.zoom_at(bd.center_of(Vector2i.ZERO), 2.0)
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 1500:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size(), " visible=", root.get_visible_rect().size, " scene=", current_scene.size)
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
