extends SceneTree
## 开发工具：批量截取可读性相关界面。godot --path game -s tools/readability_shots.gd -- <目录>

var game
var out := ""
var _backup := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://"
	_go.call_deferred()


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)


func _go() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	game = root.get_node("Game")
	game.volume = 0.0
	# 截图过程会触发自动存档，先备份玩家的存档，结束后还原
	_backup = FileAccess.get_file_as_string(game.SAVE_PATH) if FileAccess.file_exists(game.SAVE_PATH) else ""

	# 图鉴
	game.open_codex(&"menu")
	await _wait_ms(1400)
	var cx = current_scene
	for id in [&"fork", &"vine", &"flower"]:
		cx._select_card(id)
		await _wait_ms(900)
		await _shot("codex_" + id)
	cx._select_card(&"fruit")
	cx.age = 2
	cx._render_card_demo()
	await _wait_ms(300)
	var fruit_cell := Vector2i(2, -2)
	cx.board._set_hover(fruit_cell)
	await _wait_ms(900)
	await _shot("codex_fruit_hover")
	cx._show_terms()
	cx._select_term(1)
	await _wait_ms(400)
	await _shot("codex_terms_buds")

	# 对局：先自动长几回合
	game.run = RunState.create(33)
	var bot := Bot.make(Bot.Policy.GREEDY)
	for i in 2:
		bot.play_turn(game.run)
		game.run.end_turn()
	game.goto(&"season")
	await _wait_ms(1400)
	var sc = current_scene
	var run: RunState = game.run
	# 悬停某个末梢：路径流动 + 计算链
	var tip: Vector2i = run.preview().tip_list[-1]
	sc.board._set_hover(tip)
	await _wait_ms(1300)
	await _shot("season_hover_flow")
	sc.board._set_hover(Vector2i(9999, 9999))
	# 选牌 + 悬停目标格：预览与增减
	for i in run.hand.size():
		if not sc._targets_of(i).is_empty():
			sc._select(i)
			break
	await _wait_ms(200)
	if sc.sel >= 0:
		var tg: Dictionary = sc._targets()
		sc.board._set_hover(tg.keys()[0])
		await _wait_ms(300)
		await _shot("season_place_preview")
		# 悬停一个不能放的格子
		sc.board._set_hover(Vector2i(-3, 3))
		await _wait_ms(300)
		await _shot("season_why_not")
	sc.board._set_hover(Vector2i(9999, 9999))
	if sc.sel >= 0:
		sc._select(sc.sel)
	game.reduce_motion = true
	sc._end_turn()
	await _wait_ms(400)
	await _shot("season_sheet")
	_restore_save()
	quit()


func _restore_save() -> void:
	if _backup == "":
		game.clear_save()
	else:
		var f := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
