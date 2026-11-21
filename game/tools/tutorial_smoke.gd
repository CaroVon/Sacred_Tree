extends SceneTree
## 开发工具：自动走完新手指导，检查每一步的限制是否生效，并在关键步骤截图。
## godot --path game -s tools/tutorial_smoke.gd -- <截图目录>

var game
var shots := ""
var problems: Array[String] = []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	shots = a[0] if a.size() > 0 else ""
	_go.call_deferred()


func _wait(n := 4) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots.path_join(name + ".png"))


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		problems.append(msg)


func _go() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	game = root.get_node("Game")
	game.reduce_motion = true
	var save_before: bool = FileAccess.file_exists(game.SAVE_PATH)
	var save_text: String = FileAccess.get_file_as_string(game.SAVE_PATH) if save_before else ""
	game.start_tutorial()
	await _wait(6)
	var sc = current_scene
	var tut: Tutorial = game.tutorial
	var run: RunState = game.run

	# 第一步是说明：此时不能结束回合
	sc._end_turn()
	_expect(run.turn == 1, "说明步骤里不应能结束回合")
	await _shot("tut_01_intro")
	var guard := 0
	var shot_steps := {1: "tut_02_stem", 4: "tut_05_fruit", 6: "tut_07_vine", 9: "tut_10_prune"}
	while run.phase == RunState.Phase.PLAY and guard < 60:
		guard += 1
		var st := tut.current()
		if st.get("info", false):
			sc.tut_next.pressed.emit()
		elif st.has("cards"):
			var want: StringName = st.cards[0]
			# 不允许的牌应当被禁用
			for i in run.hand.size():
				if run.hand[i] != want:
					_expect(sc._targets_of(i).is_empty(), "第 %d 步不应允许 %s" % [tut.step + 1, run.hand[i]])
			var i := run.hand.find(want)
			_expect(i >= 0, "第 %d 步手里没有 %s" % [tut.step + 1, want])
			if i < 0:
				break
			sc._select(i)
			await _wait()
			if shot_steps.has(tut.step):
				await _shot(shot_steps[tut.step])
			var tg: Dictionary = sc._targets()
			_expect(not tg.is_empty(), "第 %d 步 %s 没有可放的位置" % [tut.step + 1, want])
			if tg.is_empty():
				break
			sc._on_cell_clicked(tg.keys()[0])
		elif st.has("prune"):
			sc._toggle_prune()
			await _wait()
			if shot_steps.has(tut.step):
				await _shot(shot_steps[tut.step])
			# 剪树心旁的茎不应被允许
			for n: TreeNode in run.tree.nodes.values():
				if n.type == &"stem":
					sc._on_cell_clicked(n.key)
					break
			_expect(run.sap == 0, "修剪步骤只应允许剪枯枝")
			for n: TreeNode in run.tree.nodes.values():
				if n.type == st.prune:
					sc._on_cell_clicked(n.key)
					break
		else:
			sc._end_turn()
		await _wait()
	await _wait(6)
	await _shot("tut_11_done")
	_expect(run.phase == RunState.Phase.REWARD, "指导结束时应在春季末")
	_expect(sc.modal.visible and sc.modal_title.text == "新手指导完成", "应显示指导完成弹窗")
	var save_after: bool = FileAccess.file_exists(game.SAVE_PATH)
	_expect(save_after == save_before and (not save_after or FileAccess.get_file_as_string(game.SAVE_PATH) == save_text), "指导不应改动存档")
	print("tutorial steps reached: %d/%d, season score %d, sap %d" % [tut.step + 1, tut.steps.size(), run.score, run.sap])
	if problems.is_empty():
		print("TUTORIAL OK")
	else:
		for p in problems:
			print("PROBLEM: ", p)
	quit()
