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
	board.auto_frame = false
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.margins = Vector4(780, 70, 60, 70)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.show_buds = false
	board.ctx = _run.ctx()
	add_child(board)
	board.set_mood(_run.season if _run.season <= 4 else 1, &"")
	Game.scene_audio(&"menu")
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
	bn.pressed.connect(_pick_starter)
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
	# 音量：音效 / 音乐 / 环境音，各自循环 0–100%
	var vols := HBoxContainer.new()
	vols.add_theme_constant_override("separation", 10)
	v.add_child(vols)
	for spec in [["音效", "volume"], ["音乐", "music_volume"], ["环境", "ambience_volume"]]:
		var bv := _btn(vols, "", false)
		bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var prop: String = spec[1]
		var label: String = spec[0]
		var upd_v := func(): bv.text = "%s：%d%%" % [label, roundi(float(Game.get(prop)) * 100)]
		upd_v.call()
		bv.pressed.connect(func():
			var steps := [0.0, 0.25, 0.5, 0.75, 1.0]
			Game.set(prop, steps[(steps.find(snappedf(float(Game.get(prop)), 0.25)) + 1) % steps.size()])
			Game.apply_volumes()
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


## 开新局前选启程者：已解锁的可选，未解锁的写出解锁条件。
func _pick_starter() -> void:
	var veil := ColorRect.new()
	veil.color = Color(Palette.INK, 0.55)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	var page := PrintBox.new()
	page.padding = 30
	page.inner_border = true
	page.shadow_offset = Vector2(8, 10)
	page.shadow_color = Color(Palette.INK, 0.45)
	page.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	page.grow_horizontal = Control.GROW_DIRECTION_BOTH
	page.grow_vertical = Control.GROW_DIRECTION_BOTH
	veil.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	page.add_child(col)
	var t := Label.new()
	t.text = "选择启程者"
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override("font_size", 40)
	col.add_child(t)
	var sub := Label.new()
	sub.text = "启程者决定你的起手牌组和一件起手器物。之后的选牌、集市和事件仍然可以把牌组带向任何方向。"
	sub.theme_type_variation = &"SoftLabel"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(1120, 0)
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var first: Button = null
	var ids := Cards.starter_ids()
	ids.sort_custom(func(a, b): return Cards.starter(a).order < Cards.starter(b).order)
	for id in ids:
		var st := Cards.starter(id)
		var open := Game.profile.has_starter(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(270, 300)
		b.disabled = not open
		b.clip_text = true
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_right = -14
		v.offset_top = 12
		v.offset_bottom = -12
		v.add_theme_constant_override("separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var art := ArtView.new()
		art.mode = 1
		art.art_id = StringName("relic_cut_" + String(st.relic)) if st.relic != &"" and CardArt.has(StringName("relic_cut_" + String(st.relic))) else &"tree"
		art.custom_minimum_size = Vector2(0, 90)
		v.add_child(art)
		var n := Label.new()
		n.text = st.display_name
		n.theme_type_variation = &"TitleLabel"
		n.add_theme_font_size_override("font_size", 26)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		var fam := Label.new()
		fam.text = " · ".join(st.families.map(func(f): return CardDef.FAMILY_NAMES.get(f, String(f)) + ("" if f == &"wood" or Game.profile.has_family(f) else "（未解锁）")))
		fam.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fam.add_theme_color_override("font_color", Palette.family_color(st.families[0]) if not st.families.is_empty() else Palette.OLIVE)
		v.add_child(fam)
		var d := Label.new()
		d.text = st.desc if open else "未解锁：" + Game.profile.unlock_hint_starter(id)
		d.theme_type_variation = &"SoftLabel"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 15)
		v.add_child(d)
		for ch in v.get_children():
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(func(): Game.new_run(-1, id))
		row.add_child(b)
		if open and first == null:
			first = b
	var fams := Label.new()
	var locked: Array[String] = []
	for f in CardDef.FAMILY_NAMES:
		if not Game.profile.has_family(f):
			locked.append("%s（%s）" % [CardDef.FAMILY_NAMES[f], Game.profile.unlock_hint_family(f)])
	fams.text = "未解锁的流派不会出现在选牌和集市里：" + "、".join(locked) if not locked.is_empty() else "所有流派都已解锁。"
	fams.theme_type_variation = &"SoftLabel"
	fams.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fams.custom_minimum_size = Vector2(1120, 0)
	col.add_child(fams)
	var back := Button.new()
	back.text = "返回"
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(veil.queue_free)
	col.add_child(back)
	if first:
		first.grab_focus.call_deferred()


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
