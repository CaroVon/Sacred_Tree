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
	game.run = RunState.create(run_seed)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for t in turns:
		_greedy(game.run)
		game.run.end_turn()
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
	for i in 5:
		await process_frame
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
