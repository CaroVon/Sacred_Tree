extends Control
## 牌组图鉴：「牌」页逐张查看规则与牌桌演示；「规则与名词」页解释基本概念。

var tab_cards: Button
var tab_terms: Button
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var title_l: Label
var rules_l: Label
var note_l: Label
var chain_l: Label
var board: BoardView
var card_view: CardView
var controls: HBoxContainer

var current: StringName = &""
var age: int = 0
var compare: bool = false
var _demo: Dictionary = {}
var _loop_alive := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var t := Label.new()
	t.text = "牌组图鉴"
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override("font_size", 44)
	head.add_child(t)
	tab_cards = Button.new()
	tab_cards.text = "牌"
	tab_cards.pressed.connect(_show_cards)
	head.add_child(tab_cards)
	tab_terms = Button.new()
	tab_terms.text = "规则与名词"
	tab_terms.pressed.connect(_show_terms)
	head.add_child(tab_terms)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(_back)
	head.add_child(back)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(700, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	list_scroll.add_child(list_box)

	var detail := PrintBox.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.padding = 18
	body.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	detail.add_child(dv)
	title_l = Label.new()
	title_l.clip_text = true
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_font_size_override("font_size", 40)
	dv.add_child(title_l)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(split)
	var text_col := VBoxContainer.new()
	text_col.custom_minimum_size = Vector2(430, 0)
	text_col.add_theme_constant_override("separation", 10)
	split.add_child(text_col)
	# 左边：这张牌的大图 + 说明
	var card_col := VBoxContainer.new()
	card_col.add_theme_constant_override("separation", 10)
	card_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	text_col.add_child(card_col)
	card_view = CardView.make(&"stem")
	card_view.draggable = false
	card_view.custom_minimum_size = Vector2(230, 391)
	card_col.add_child(card_view)
	rules_l = Label.new()
	rules_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_l.add_theme_font_size_override("font_size", 18)
	text_col.add_child(rules_l)
	var board_col := VBoxContainer.new()
	board_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(board_col)
	var bbox := PrintBox.new()
	bbox.padding = 6
	bbox.shadow_offset = Vector2.ZERO
	bbox.border = 1.0
	bbox.border_color = Palette.RULE
	bbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_col.add_child(bbox)
	board = Board3D.new()
	board.custom_minimum_size = Vector2(0, 420)
	# 图鉴里示例树频繁切换，不播落下/飞走动画
	board.animate_changes = false
	board.cell_hovered.connect(_on_hover)
	board.hover_cleared.connect(_on_hover_cleared)
	board.pulse_finished.connect(_on_pulse_done)
	bbox.add_child(board)
	note_l = Label.new()
	note_l.theme_type_variation = &"SoftLabel"
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_col.add_child(note_l)
	chain_l = Label.new()
	chain_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chain_l.add_theme_color_override("font_color", Palette.OLIVE.darkened(0.35))
	board_col.add_child(chain_l)
	controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	board_col.add_child(controls)
	_show_cards()


func _exit_tree() -> void:
	_loop_alive = false


func _back() -> void:
	if Game.codex_return == &"season" and Game.run == null:
		Game.goto(&"menu")
	else:
		Game.goto(Game.codex_return)


# ---------- 牌页 ----------

func _show_cards() -> void:
	tab_cards.theme_type_variation = &"PrimaryButton"
	tab_terms.theme_type_variation = &""
	_clear_list()
	for cat in CardDef.CATEGORY_NAMES.size():
		var ids: Array[StringName] = []
		for id in Cards.all_ids():
			if Cards.get_def(id).category == cat:
				ids.append(id)
		if ids.is_empty():
			continue
		var h := Label.new()
		h.text = "%s牌　%s" % [CardDef.CATEGORY_NAMES[cat], CardDemo.CATEGORY_HELP[cat]]
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.theme_type_variation = &"SoftLabel"
		list_box.add_child(h)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 14)
		flow.add_theme_constant_override("v_separation", 14)
		list_box.add_child(flow)
		for id in ids:
			var cv := CardView.make(id)
			cv.draggable = false
			cv.compact = true
			cv.custom_minimum_size = Vector2(130, 184)
			cv.selected = id == current
			cv.pressed.connect(_select_card.bind(id))
			flow.add_child(cv)
	if current == &"" or not Cards.has(current):
		_select_card(&"stem")
	else:
		_select_card(current)


func _select_card(id: StringName) -> void:
	current = id
	age = 0
	compare = false
	for flow in list_box.get_children():
		for cv in flow.get_children():
			if cv is CardView:
				cv.selected = cv.card_id == id
	var def := Cards.get_def(id)
	title_l.text = def.display_name
	title_l.add_theme_font_override("font", Palette.title_for(def.display_name))
	if card_view:
		card_view.card_id = id
		card_view.queue_redraw()
	rules_l.text = "牌面：%s\n\n%s" % [def.desc, CardDemo.rules_text(def)]
	_rebuild_controls(def)
	_render_card_demo()


func _rebuild_controls(def: CardDef) -> void:
	for ch in controls.get_children():
		ch.queue_free()
	if def.mature_step > 0 or def.ripen_age > 0:
		var l := Label.new()
		l.text = "经历脉动："
		controls.add_child(l)
		for a in [0, 1, 2, 4]:
			var b := Button.new()
			b.text = "%d 次" % a
			b.theme_type_variation = &"PrimaryButton" if a == age else &""
			b.pressed.connect(func():
				age = a
				_rebuild_controls(def)
				_render_card_demo())
			controls.add_child(b)
	if def.id != &"stem":
		var c := Button.new()
		c.text = "对比：换成茎" if not compare else "对比中：点击换回%s" % def.display_name
		if def.is_graft():
			c.text = "对比：不放%s" % def.display_name if not compare else "对比中：点击放回%s" % def.display_name
		c.theme_type_variation = &"ActiveButton" if compare else &""
		c.pressed.connect(func():
			compare = not compare
			_rebuild_controls(def)
			_render_card_demo())
		controls.add_child(c)


func _render_card_demo() -> void:
	var d := CardDemo.build(current, age, compare)
	_demo = d
	var tree: TreeModel = d.tree
	var res := Pulse.resolve(tree, CardDemo.ctx())
	board.ctx = CardDemo.ctx()
	board.node_pick = {d.focus: true} if tree.has(d.focus) else {}
	board.set_state(tree, res, {}, false, {})
	var with_me := Pulse.resolve(CardDemo.build(current, age, false).tree, CardDemo.ctx()).total
	var as_stem := Pulse.resolve(CardDemo.build(current, age, true).tree, CardDemo.ctx()).total
	var def := Cards.get_def(current)
	var cmp := ""
	if current != &"stem":
		cmp = "\n这棵树放%s时得 %d 分；换成%s得 %d 分。" % [def.display_name, with_me, "茎" if not def.is_graft() else "不放", as_stem]
	note_l.text = "%s 本回合得分 %d。%s\n把鼠标移到牌上，看养分怎样一步步流过来。" % [d.note, res.total, cmp]
	_show_focus_chain(res, tree)
	board.play_pulse(tree, res, false)


func _show_focus_chain(res: Pulse.Result, tree: TreeModel) -> void:
	var tips := res.tip_list.duplicate()
	var lines: Array[String] = []
	for k in tips:
		lines.append("%s：%s" % [_nm(tree.at(k)), _path_text(res, tree, k)])
	chain_l.text = "各末梢收获：\n" + "\n".join(lines)


## 从树心到 k 的一行算式（只走第一父牌；嫁接写出相乘的两个数）。
func _path_text(res: Pulse.Result, tree: TreeModel, k: Vector2i) -> String:
	var path: Array[Vector2i] = []
	var x := k
	while true:
		path.push_front(x)
		var n := tree.at(x)
		if n.is_seed() or n.def().is_graft():
			break
		x = n.parents[0]
	var parts: Array[String] = []
	for p in path:
		var n := tree.at(p)
		if n.is_seed():
			parts.append("树心 %d" % res.out[p])
		else:
			var ops: Array[String] = []
			var tr: Array = res.trace[p]
			for st in (tr if n.def().is_graft() else tr.slice(1)):
				ops.append(String(st.op))
			parts.append("%s %s = %d" % [n.def().display_name, " ".join(ops), res.out[p]])
	var s := " → ".join(parts)
	if res.tips.has(k):
		var tt: Array = res.tip_trace[k]
		for st in tt.slice(1):
			s += " → %s %s" % [st.label, st.op]
		s += "，收获 %d" % res.contrib[k]
	return s


func _nm(n: TreeNode) -> String:
	return "树心" if n.is_seed() else n.def().display_name


func _on_pulse_done() -> void:
	if not _loop_alive or not is_inside_tree():
		return
	await get_tree().create_timer(1.2).timeout
	if _loop_alive and is_inside_tree() and board.tree and board.trace_target == BoardView.NO_CELL:
		board.play_pulse(board.tree, board.pulse, false)


func _on_hover(c: Vector2i) -> void:
	if board.tree == null or not board.tree.has(c):
		return
	board.stop_pulse()
	board.set_trace(c)
	var n := board.tree.at(c)
	chain_l.text = "%s：%s" % [_nm(n), _path_text(board.pulse, board.tree, c)]
	if not res_is_tip(c):
		chain_l.text += "\n（不是末梢，自己不计分，养分继续往后流）"


func res_is_tip(c: Vector2i) -> bool:
	return board.pulse != null and board.pulse.tips.has(c)


func _on_hover_cleared() -> void:
	board.set_trace(BoardView.NO_CELL)
	if board.pulse and board.tree:
		_show_focus_chain(board.pulse, board.tree)
		if not board.is_animating():
			board.play_pulse(board.tree, board.pulse, false)


# ---------- 规则与名词页 ----------

func _show_terms() -> void:
	tab_terms.theme_type_variation = &"PrimaryButton"
	tab_cards.theme_type_variation = &""
	_clear_list()
	for i in Glossary.TERMS.size():
		var b := Button.new()
		b.text = Glossary.TERMS[i].name
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_select_term.bind(i))
		list_box.add_child(b)
	_select_term(0)


func _select_term(i: int) -> void:
	var term: Dictionary = Glossary.TERMS[i]
	for j in list_box.get_child_count():
		var b := list_box.get_child(j)
		if b is Button:
			b.theme_type_variation = &"ActiveButton" if j == i else &""
	title_l.text = term.name
	rules_l.text = term.text
	for ch in controls.get_children():
		ch.queue_free()
	chain_l.text = ""
	var demo: Dictionary = Glossary.build_demo(term.demo) if term.demo != &"" else {}
	if demo.is_empty():
		board.visible = false
		board.get_parent().visible = false
		note_l.text = ""
		return
	board.get_parent().visible = true
	board.visible = true
	var tree: TreeModel = demo.tree
	var res := Pulse.resolve(tree, CardDemo.ctx())
	var pick := {}
	for c in demo.pick:
		pick[c] = true
	board.ctx = CardDemo.ctx()
	board.node_pick = pick
	board.set_state(tree, res, {}, false, {})
	note_l.text = "蓝色虚线框标出了这一条说的牌。本回合得分 %d。把鼠标移到牌上看算式。" % res.total if not pick.is_empty() else "本回合得分 %d。把鼠标移到牌上看算式。" % res.total
	_show_focus_chain(res, tree)


func _clear_list() -> void:
	for ch in list_box.get_children():
		ch.queue_free()
	board.get_parent().visible = true
	board.visible = true
