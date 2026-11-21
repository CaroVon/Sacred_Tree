extends Control
## 主菜单：一个场景，而不是一张表单。
## 右边是 3D 牌桌，一棵神树一枚枚翻立着长出来（有存档时就是你那棵树）；
## 左边是题名和一列石刻铭牌式的菜单。

const REVEAL_STEP := 0.16

var board: Board3D
var _tree: TreeModel
var _run: RunState
var _order: Array[TreeNode] = []
var _shown: int = 0
var _timer: float = 0.0


func _ready() -> void:
	if Game.tutorial:
		Game.tutorial = null
		Game.run = null
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---------- 牌桌与展示树 ----------
	_run = Game.load_save() if Game.has_save() else null
	if _run == null or _run.tree.size() < 4:
		_run = Showcase.grow(23, 6)
	_tree = _run.tree
	_order = Showcase.order_of(_tree)
	board = Board3D.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.margins = Vector4(780, 70, 60, 70)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.show_buds = false
	board.ctx = _run.ctx()
	add_child(board)
	board.set_mood(_run.season if _run.season <= 4 else 1, &"")
	board.set_relics.call_deferred(_run.relics)
	_shown = 0 if not Game.reduce_motion else _order.size()
	_show_partial()
	set_process(true)

	# ---------- 左列：题名 + 菜单 ----------
	var col := VBoxContainer.new()
	col.position = Vector2(110, 0)
	col.custom_minimum_size = Vector2(560, 0)
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_KEEP_WIDTH)
	col.offset_left = 110
	col.offset_right = 110 + 560
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var plate := PrintBox.new()
	plate.padding = 36
	plate.shadow_offset = Vector2(8, 10)
	plate.shadow_color = Color(Palette.INK, 0.45)
	plate.inner_border = true
	col.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	plate.add_child(v)

	var title := Label.new()
	title.text = "神树"
	title.theme_type_variation = &"DisplayLabel"
	title.add_theme_font_size_override("font_size", 120)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "S H E N   S H U"
	sub.theme_type_variation = &"PlaqueLabel"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Palette.GOLD.darkened(0.15))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(_gold_rule())
	var lead := Label.new()
	lead.text = "在六边形土地上培育神树。\n每回合把牌接到枝头，养分从树心流向所有末梢。\n树的形状就是牌型，长得越茂盛，收获越多。"
	lead.theme_type_variation = &"SoftLabel"
	lead.add_theme_font_size_override("font_size", 17)
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lead)
	v.add_child(_gold_rule())

	var first: Button = null
	if Game.has_save():
		var bc := _btn(v, "继续", true)
		bc.pressed.connect(Game.continue_run)
		first = bc
	var bn := _btn(v, "新的一局", not Game.has_save())
	bn.pressed.connect(func(): Game.new_run())
	if first == null:
		first = bn
	var bt := _btn(v, "新手指导" + ("" if Game.tutorial_done else "（推荐第一次玩先看）"), false)
	bt.pressed.connect(Game.start_tutorial)
	var bc2 := _btn(v, "牌组图鉴", false)
	bc2.pressed.connect(func(): Game.open_codex(&"menu"))
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 10)
	v.add_child(opts)
	var bm := _btn(opts, "", false)
	bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var upd_m := func(): bm.text = "减少动效：" + ("开" if Game.reduce_motion else "关")
	upd_m.call()
	bm.pressed.connect(func():
		Game.reduce_motion = not Game.reduce_motion
		Game.save_settings()
		upd_m.call())
	var bv := _btn(opts, "", false)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var upd_v := func(): bv.text = "音量：%d%%" % roundi(Game.volume * 100)
	upd_v.call()
	bv.pressed.connect(func():
		var steps := [0.0, 0.25, 0.5, 0.75, 1.0]
		Game.volume = steps[(steps.find(snappedf(Game.volume, 0.25)) + 1) % steps.size()]
		Game.save_settings()
		Game.sfx(&"click")
		upd_v.call())
	var bq := _btn(v, "退出", false)
	bq.pressed.connect(func(): get_tree().quit())
	first.grab_focus.call_deferred()

	var sign := Label.new()
	sign.text = "一局三年 · 每年春夏秋冬加一场天灾 · 三年之后神树成年"
	sign.theme_type_variation = &"SoftLabel"
	sign.add_theme_font_size_override("font_size", 15)
	sign.add_theme_color_override("font_color", Palette.INK.lightened(0.2))
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sign)

	# 入场：题名纸片从下方浮上来
	if not Game.reduce_motion:
		col.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.15)
		tw.tween_property(col, "modulate:a", 1.0, 0.5)
		plate.pivot_offset = Vector2(280, 300)
		plate.scale = Vector2.ONE * 0.96
		var tw2 := create_tween()
		tw2.tween_interval(0.15)
		tw2.tween_property(plate, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	if _shown >= _order.size():
		return
	_timer += dt
	if _timer < (0.6 if _shown == 0 else REVEAL_STEP):
		return
	_timer = 0.0
	var n := _order[_shown]
	board.stamp_at(n.key, Color.WHITE)
	_shown += 1
	_show_partial()
	if _shown % 3 == 0:
		Game.sfx(&"place", 1.2 + 0.03 * _shown)


func _show_partial() -> void:
	var upto := _order[_shown - 1].order if _shown > 0 else -1
	var t := Showcase.partial(_tree, upto) if _shown < _order.size() else _tree
	board.set_state(t, _run.explained(t), {}, false, {})


func _gold_rule() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 14)
	c.draw.connect(func():
		var y := c.size.y * 0.5
		var w := c.size.x
		c.draw_line(Vector2(w * 0.12, y), Vector2(w * 0.44, y), Palette.GOLD, 1.2, true)
		c.draw_line(Vector2(w * 0.56, y), Vector2(w * 0.88, y), Palette.GOLD, 1.2, true)
		var m := Vector2(w * 0.5, y)
		c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -5), m + Vector2(5, 0), m + Vector2(0, 5), m + Vector2(-5, 0)]), Palette.GOLD))
	return c


func _btn(parent: Node, text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(0, 52)
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	parent.add_child(b)
	return b
