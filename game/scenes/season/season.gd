extends Control
## 核心玩法场景：牌桌 + 手牌 + 状态栏。把玩家输入翻译成 RunState 的行动，再刷新画面。

var run: RunState
var sel: int = -1
var prune_mode: bool = false
## 移栽模式：先点要挪的牌（transplant_from），再点新位置。
var transplant_mode: bool = false
var transplant_from: Vector2i = BoardView.NO_CELL
var flash: Dictionary = {}
var _hand_sig: String = ""

var board: BoardView
var hint: Label
var hand_view: HandView
## 计分演出：脉动时显示的分数（-1 = 直接显示 run.score）与飞字层。
var _score_shown: int = -1
var _score_target: int = 0
var fly_layer: Control
var stats_box: PrintBox
var hud: Control
var left_col: VBoxContainer
var hint_box: PanelContainer
var deck_pile: PileView
var discard_pile: PileView
var log_panel: PrintBox
var b_log: Button
var b_rules: Button
var b_diagram: Button
var _diagram_hold: bool = false
var lbl_season: Label
var lbl_turn: Label
var lbl_trait: Label
var lbl_patterns: Label
var lbl_relics: Label
var lbl_score: Label
var bar: ProgressBar
var lbl_pulse: Label
var lbl_sap: Label
var lbl_piles: Label
var lbl_acts: Label
var lbl_heat: Label
var lbl_res: Label
var b_end: SealButton
var b_prune: Button
var b_redraw: Button
var b_harvest: Button
var b_transplant: Button
var log_box: VBoxContainer
## 器物栏（顶栏里的一排器物图标）。
var relic_bar: RelicBar
## 整屏布局：左右两列宽度，网格四周留给 HUD 的边距。
const LEFT_W := 360.0
const RIGHT_W := 290.0
const SIDE_W := 380.0
const TOP_H := 112.0
const BOTTOM_H := 185.0
## 脉动结算单。
var sheet_panel: PrintBox
var sheet_box: VBoxContainer
var sheet_open: bool = true
var last_sheet: Pulse.Result
var last_sheet_tree: TreeModel
var modal: Control
var modal_title: Label
var modal_text: Label
var modal_btns: HFlowContainer
## 新手指导（没有则为 null）与它的提示面板。
var tut: Tutorial
var tut_panel: PrintBox
var rules_panel: PrintBox
var tut_title: Label
var tut_text: Label
var tut_next: Button


func _ready() -> void:
	run = Game.run
	if run == null:
		run = RunState.create()
		Game.run = run
	tut = Game.tutorial
	_build()
	if tut:
		_build_tutorial()
	_refresh()
	_show_phase_modal()


# ---------- 搭界面 ----------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ---------- 牌桌：铺满全屏，网格放在 HUD 之间 ----------
	board = Board3D.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.margins = Vector4(SIDE_W, TOP_H, SIDE_W, BOTTOM_H)
	board.chain_pos = Vector2(18, 330)
	board.chain_width = LEFT_W - 24
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	board.hover_cleared.connect(_on_hover_cleared)
	board.card_dropped.connect(_on_card_dropped)
	add_child(board)

	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	# ---------- 左列：季节铭牌 / 结算单 / 记录 ----------
	left_col = VBoxContainer.new()
	left_col.position = Vector2(18, 18)
	left_col.custom_minimum_size = Vector2(LEFT_W, 0)
	left_col.add_theme_constant_override("separation", 10)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(left_col)

	var stats := _panel(left_col)
	stats_box = stats
	_raise(stats)
	stats.inner_border = true
	# 面板底下淡印一幅神树版画（PrintBox 会把子控件铺满同一块矩形，先加的画在下面）
	var wm := ArtView.new()
	wm.art_id = &"tree"
	wm.mode = 0
	wm.modulate = Color(1, 1, 1, 0.10)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(wm)
	var sv := VBoxContainer.new()
	sv.mouse_filter = Control.MOUSE_FILTER_PASS
	stats.add_child(sv)
	var r1 := _row(sv, "", "")
	lbl_season = r1[0]
	lbl_turn = r1[1]
	lbl_season.theme_type_variation = &"TitleLabel"
	lbl_season.add_theme_font_size_override("font_size", 28)
	lbl_trait = Label.new()
	lbl_trait.theme_type_variation = &"SoftLabel"
	lbl_trait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(lbl_trait)
	lbl_score = _row(sv, "本季累计", "")[1]
	lbl_score.theme_type_variation = &"NumericLabel"
	lbl_score.add_theme_font_size_override("font_size", 20)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Palette.CELL
	bg.border_color = Palette.RULE
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Palette.OLIVE
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	sv.add_child(bar)
	lbl_sap = _row(sv, "养分储备", "")[1]
	lbl_acts = _row(sv, "可放 / 剪 / 移栽", "")[1]
	var heat_row := _row(sv, "火候 / 已燃烧", "")
	lbl_heat = heat_row[1]
	lbl_res = Label.new()
	lbl_res.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_res.add_theme_font_size_override("font_size", 15)
	lbl_res.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(lbl_res)
	# 牌库/弃牌和器物已经有实物显示，这两行文字隐藏
	var piles_row := _row(sv, "牌库 / 弃牌", "")
	lbl_piles = piles_row[1]
	lbl_piles.get_parent().visible = false
	lbl_relics = Label.new()
	lbl_relics.visible = false
	sv.add_child(lbl_relics)

	sheet_panel = _panel(left_col)
	_raise(sheet_panel)
	sheet_panel.border_color = Palette.OCHRE
	sheet_panel.visible = false
	sheet_box = VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 2)
	sheet_panel.add_child(sheet_box)

	b_log = Button.new()
	b_log.text = "记录 ▸　[L]"
	b_log.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b_log.pressed.connect(_toggle_log)
	left_col.add_child(b_log)
	log_panel = _panel(left_col)
	_raise(log_panel)
	log_panel.visible = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 220)
	log_panel.add_child(scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(log_box)

	# ---------- 上方中间：器物 + 提示丝带 ----------
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 14
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	relic_bar = RelicBar.new()
	relic_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(relic_bar)
	hint_box = PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(Palette.SHEET, 0.92)
	hsb.border_color = Color(Palette.OCHRE, 0.8)
	hsb.border_width_top = 1
	hsb.border_width_bottom = 1
	hsb.content_margin_left = 18
	hsb.content_margin_right = 18
	hsb.content_margin_top = 5
	hsb.content_margin_bottom = 5
	hint_box.add_theme_stylebox_override("panel", hsb)
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(hint_box)
	hint = Label.new()
	hint.theme_type_variation = &"SoftLabel"
	hint.add_theme_color_override("font_color", Palette.INK)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(900, 0)
	hint_box.add_child(hint)

	# ---------- 右上：小按钮 ----------
	var tr := HBoxContainer.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_right = -18
	tr.offset_top = 18
	tr.add_theme_constant_override("separation", 10)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(tr)
	b_diagram = Button.new()
	b_diagram.text = "图解 [Tab]"
	b_diagram.toggle_mode = true
	b_diagram.tooltip_text = "把立牌折倒，铺开带名字和数值的六边形牌片（按住 Tab 临时查看）"
	b_diagram.toggled.connect(func(_on): _update_diagram())
	tr.add_child(b_diagram)
	b_rules = Button.new()
	b_rules.text = "规则 ?"
	b_rules.pressed.connect(_toggle_rules)
	tr.add_child(b_rules)
	var bcodex := Button.new()
	bcodex.text = "牌组图鉴"
	bcodex.pressed.connect(func(): Game.open_codex(&"season"))
	tr.add_child(bcodex)
	var bmenu := Button.new()
	bmenu.text = "主菜单"
	bmenu.pressed.connect(_to_menu)
	tr.add_child(bmenu)

	# 规则说明：右上弹出的一页
	rules_panel = _panel(hud)
	_raise(rules_panel)
	rules_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	rules_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rules_panel.offset_right = -18
	rules_panel.offset_top = 76
	rules_panel.visible = false
	var rl := Label.new()
	rl.theme_type_variation = &"SoftLabel"
	rl.add_theme_color_override("font_color", Palette.INK)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.custom_minimum_size = Vector2(420, 0)
	rl.text = "· 树心每次脉动输出：春 1、夏 2、秋 4、冬 8（第 y 年再 ×y）。
· 选一张手牌（或拖到牌桌），虚线格就是可以接上的位置。每回合最多放 %d 张。
· 养分沿枝干流动，遇到分叉就复制；所有末梢相加就是得分。
· 花给相邻的其他末梢加养分；藤把挨着的末梢嫁接起来，养分相乘。
· 修剪剪掉一张牌和它后面的所有枝（每回合 %d 次），剪下的牌回到手牌，下回合可再打出；手牌超过上限要弃牌。
· 移栽把一张牌连同后面的枝整体挪到别的芽点（每回合 %d 次），成熟度保留。
· 本季累计达标后可以提前收获，剩余每回合得 %d 养分。每季结束都会进集市。
· 牌型：长茎（末梢深度 ≥6）该末梢 ×2；星芒（一张牌长出 3 条子枝）流出 ×2；闭环（藤的父牌同源）×2；对称 总分 ×1.5。
· 牌桌：滚轮或触控板捏合缩放，右键拖动平移，双击右键或 F 复位。牌桌每年外扩一圈。
· 快捷键：1–9 选牌，空格脉动，G 收获，P 修剪，T 移栽，R 重抽，按住 Tab 图解，L 记录，H 规则，Esc 取消。" % [Rules.PLAYS, Rules.PRUNES, Rules.TRANSPLANTS, Rules.HARVEST_SAP_PER_TURN]
	rules_panel.add_child(rl)

	# ---------- 右列：预计脉动 + 印章按钮 + 工具 ----------
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.grow_vertical = Control.GROW_DIRECTION_BOTH
	right.offset_right = -28
	right.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.add_theme_constant_override("separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(right)
	var pp := _panel(right)
	_raise(pp)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 0)
	pp.add_child(pv)
	var pcap := Label.new()
	pcap.text = "下次脉动预计"
	pcap.theme_type_variation = &"PlaqueLabel"
	pcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pcap)
	lbl_pulse = Label.new()
	lbl_pulse.theme_type_variation = &"NumericLabel"
	lbl_pulse.add_theme_font_size_override("font_size", 52)
	lbl_pulse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(lbl_pulse)
	lbl_patterns = Label.new()
	lbl_patterns.add_theme_color_override("font_color", Palette.OCHRE.darkened(0.15))
	lbl_patterns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_patterns.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(lbl_patterns)
	b_end = SealButton.new()
	b_end.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b_end.pressed.connect(_end_turn)
	right.add_child(b_end)
	b_harvest = _button(right, "提前收获　[G]")
	b_harvest.pressed.connect(_harvest)
	b_harvest.tooltip_text = "本季已达标时可以直接结束本季，剩余每回合折算 %d 养分。" % Rules.HARVEST_SAP_PER_TURN
	b_prune = _button(right, "修剪　[P]")
	b_prune.pressed.connect(_toggle_prune)
	b_prune.tooltip_text = "剪下的牌回到手牌，下回合可以重新打出。"
	b_transplant = _button(right, "移栽　[T]")
	b_transplant.pressed.connect(_toggle_transplant)
	b_transplant.tooltip_text = "把一张牌连同它后面的枝整体挪到另一个空芽点，保留成熟度。每回合 %d 次。" % Rules.TRANSPLANTS
	b_redraw = _button(right, "重抽手牌（%d 养分）　[R]" % Rules.REDRAW_COST)
	b_redraw.pressed.connect(_redraw)

	# ---------- 下方：牌库 / 弃牌堆 / 手牌 ----------
	deck_pile = PileView.new()
	deck_pile.title = "牌库"
	deck_pile.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	deck_pile.grow_vertical = Control.GROW_DIRECTION_BEGIN
	deck_pile.offset_left = 40
	deck_pile.offset_bottom = -22
	hud.add_child(deck_pile)
	discard_pile = PileView.new()
	discard_pile.title = "弃牌"
	discard_pile.face_up = true
	discard_pile.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	discard_pile.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	discard_pile.grow_vertical = Control.GROW_DIRECTION_BEGIN
	discard_pile.offset_right = -40
	discard_pile.offset_bottom = -22
	hud.add_child(discard_pile)

	hand_view = HandView.new()
	hand_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hand_view.card_pressed.connect(_select)
	hand_view.card_drag_started.connect(_on_drag_started)
	add_child(hand_view)
	resized.connect(_place_piles)
	_place_piles.call_deferred()

	fly_layer = Control.new()
	fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fly_layer)
	board.tip_harvested.connect(_on_tip_harvested)

	_build_modal()


## 牌桌上的纸片：墨线边 + 落在桌面上的投影。
func _raise(p: PrintBox) -> void:
	p.shadow_offset = Vector2(5, 6)
	p.shadow_color = Color(Palette.INK, 0.45)
	p.border = 1.5
	p.border_color = Palette.INK


## 把牌库/弃牌堆的位置告诉手牌（抽牌、弃牌动画的起点和终点）。
func _place_piles() -> void:
	if hand_view == null:
		return
	hand_view.deck_point = deck_pile.global_position - hand_view.global_position + deck_pile.top_point()
	hand_view.discard_point = discard_pile.global_position - hand_view.global_position + discard_pile.top_point()


func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible
	b_log.text = ("记录 ▾　[L]" if log_panel.visible else "记录 ▸　[L]")


## 图解视图：按钮常开，或按住 Tab 临时查看。
func _update_diagram() -> void:
	if board is Board3D:
		board.set_diagram(_diagram_hold or (b_diagram != null and b_diagram.button_pressed))


func _input(e: InputEvent) -> void:
	# Tab 抢在焦点切换之前处理
	if e is InputEventKey and e.keycode == KEY_TAB and not e.echo:
		_diagram_hold = e.pressed
		_update_diagram()
		get_viewport().set_input_as_handled()


func _toggle_rules() -> void:
	rules_panel.visible = not rules_panel.visible


func _panel(parent: Node) -> PrintBox:
	var p := PrintBox.new()
	p.shadow_offset = Vector2.ZERO
	p.border = 1.0
	p.border_color = Palette.RULE
	p.padding = 14
	parent.add_child(p)
	return p


func _row(parent: Node, left: String, right: String) -> Array[Label]:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var a := Label.new()
	a.text = left
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := Label.new()
	b.text = right
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(b)
	return [a, b]


func _button(parent: Node, text: String, variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.theme_type_variation = variation
	parent.add_child(b)
	return b


func _build_modal() -> void:
	modal = ColorRect.new()
	modal.color = Color(0, 0, 0, 0.45)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.visible = false
	add_child(modal)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(c)
	var box := PrintBox.new()
	box.shadow_color = Palette.OCHRE
	box.padding = 28
	c.add_child(box)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(760, 0)
	v.add_theme_constant_override("separation", 14)
	box.add_child(v)
	modal_title = Label.new()
	modal_title.theme_type_variation = &"TitleLabel"
	modal_title.add_theme_font_size_override("font_size", 36)
	v.add_child(modal_title)
	modal_text = Label.new()
	modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(modal_text)
	modal_btns = HFlowContainer.new()
	modal_btns.add_theme_constant_override("h_separation", 20)
	modal_btns.add_theme_constant_override("v_separation", 16)
	v.add_child(modal_btns)


# ---------- 刷新 ----------

func _targets() -> Dictionary:
	if transplant_mode and transplant_from != BoardView.NO_CELL:
		var out := {}
		var mvs := run.transplant_targets(transplant_from)
		for c in mvs:
			out[c] = mvs[c].target
		return out
	return _targets_of(sel)


func _targets_of(i: int) -> Dictionary:
	if i < 0 or i >= run.hand.size():
		return {}
	var tg := run.targets_for_hand(i)
	return tut.filter_targets(run, run.hand[i], tg) if tut else tg


func _refresh() -> void:
	if sel >= run.hand.size():
		sel = -1
	var res := run.explained()
	board.highlight = {}
	board.delta = {}
	board.ghost_type = &""
	board.ctx = run.ctx()
	board.set_state(run.tree, res, _targets(), prune_mode or (transplant_mode and transplant_from == BoardView.NO_CELL), flash)
	if transplant_mode and transplant_from != BoardView.NO_CELL:
		board.highlight = Growth.subtree(run.tree, transplant_from)

	lbl_season.text = run.season_label()
	lbl_turn.text = "回合 %d/%d" % [mini(run.turn, run.turns_this_season()), run.turns_this_season()]
	var shown := run.score if _score_shown < 0 else _score_shown
	lbl_score.text = "%d / %d" % [shown, run.target() if _score_shown < 0 else _score_target]
	bar.max_value = run.target() if _score_shown < 0 else _score_target
	bar.value = mini(shown, int(bar.max_value))
	_set_num(lbl_pulse, res.total)
	if run.is_calamity():
		var cd := Cards.calamity(run.calamity)
		lbl_trait.text = "天灾：%s——%s" % [cd.display_name, cd.desc]
		lbl_trait.add_theme_color_override("font_color", Palette.TERRA)
	else:
		lbl_trait.text = "季节特性：" + Rules.season_trait(run.season)
		lbl_trait.remove_theme_color_override("font_color")
	lbl_relics.text = "器物：" + ("无" if run.relics.is_empty() else "、".join(run.relics.map(func(r): return Cards.relic(r).display_name)))
	lbl_relics.tooltip_text = "
".join(run.relics.map(func(r): return "%s：%s" % [Cards.relic(r).display_name, Cards.relic(r).desc]))
	if relic_bar:
		relic_bar.set_relics(run.relics)
	if board is Board3D:
		if board._season != run.season or board._calamity != (run.calamity if run.is_calamity() else &""):
			board.set_mood(run.season, run.calamity)
	lbl_patterns.text = "" if res.patterns.is_empty() else "牌型：" + "、".join(res.patterns.map(func(p): return p.label))
	lbl_patterns.visible = not res.patterns.is_empty()
	var pend := run.pending_release()
	if res.stored_total > 0 or pend > 0:
		lbl_patterns.text += ("
" if lbl_patterns.text != "" else "") + "封存：本次 +%d，季末释放 %d" % [res.stored_total, pend]
		lbl_patterns.visible = true
	lbl_sap.text = str(run.sap)
	lbl_piles.text = "%d / %d" % [run.deck.size(), run.discard.size()]
	lbl_acts.text = "%d / %d / %d" % [run.plays, run.prunes, run.transplants]
	lbl_heat.text = "%d / %d" % [run.heat, run.burned_total]
	lbl_heat.get_parent().visible = run.heat > 0 or res.family_counts.has(&"forge")
	_refresh_resonance(res)

	var playing := run.phase == RunState.Phase.PLAY
	b_end.disabled = not playing or (tut != null and not tut.can_end_turn())
	b_harvest.disabled = not run.can_harvest() or tut != null
	b_harvest.text = ("提前收获 +%d 养分　[G]" % run.harvest_sap()) if run.can_harvest() else "提前收获（未达标）"
	b_harvest.theme_type_variation = &"PrimaryButton" if run.can_harvest() else &""
	b_prune.disabled = not run.can_prune() or (tut != null and not tut.can_prune_mode())
	b_prune.text = "取消修剪　[P]" if prune_mode else "修剪　[P]"
	b_prune.theme_type_variation = &"ActiveButton" if prune_mode else &""
	b_transplant.disabled = (not run.can_transplant() and not transplant_mode) or (tut != null and not tut.is_free())
	b_transplant.text = "取消移栽　[T]" if transplant_mode else "移栽　[T]"
	b_transplant.theme_type_variation = &"ActiveButton" if transplant_mode else &""
	b_redraw.disabled = not run.can_redraw() or (tut != null and not tut.is_free())

	_refresh_hand()
	_refresh_hint()

	for ch in log_box.get_children():
		ch.queue_free()
	for line in run.log_lines.slice(0, 14):
		var l := Label.new()
		l.text = line
		l.theme_type_variation = &"SoftLabel"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		log_box.add_child(l)


## 共鸣面板：牌桌上各流派的牌数与下一个阈值；已激活的层数用流派色。
func _refresh_resonance(res: Pulse.Result) -> void:
	var parts: Array[String] = []
	var tips: Array[String] = []
	for f in CardDef.FAMILY_NAMES:
		if f == &"wood" or not res.family_counts.has(f):
			continue
		var t := Pulse.resonance_text(f, res.family_counts[f])
		var tier: int = res.resonance.get(f, 0)
		parts.append(t + ("（%d 层）" % tier if tier > 0 else ""))
		tips.append("%s：%s" % [CardDef.FAMILY_NAMES[f], Pulse.resonance_desc(f)])
	lbl_res.visible = not parts.is_empty()
	lbl_res.text = "共鸣　" + "　".join(parts)
	lbl_res.tooltip_text = "牌桌上同一流派的牌达到 2 / 4 / 6 张时激活共鸣。
" + "
".join(tips)
	lbl_res.add_theme_color_override("font_color", Palette.OCHRE.darkened(0.2) if not res.resonance.is_empty() else Palette.SOFT)


func _refresh_hand() -> void:
	var sig := ",".join(run.hand.map(func(x): return String(x)))
	if sig != _hand_sig:
		_hand_sig = sig
		hand_view.sync(run.hand)
	deck_pile.count = run.deck.size()
	discard_pile.count = run.discard.size()
	var discarding := run.phase == RunState.Phase.DISCARD
	for ch in hand_view.cards():
		var can := not _targets_of(ch.index).is_empty()
		ch.disabled = not can and not discarding
		ch.selected = ch.index == sel
		if discarding:
			ch.note = "点击弃掉"
			ch.note_alert = true
		elif run.is_fresh(ch.index):
			ch.note = "刚剪下：下回合可用"
			ch.note_alert = false
		elif tut and not tut.card_allowed(ch.card_id):
			ch.note = "指导中暂不使用"
			ch.note_alert = true
		else:
			ch.note = "" if can else ("本回合已放满" if run.plays <= 0 else Growth.hand_reason(run.tree, ch.card_id, run.ctx()))
			ch.note_alert = not can
	# 本回合放满了：印章按钮呼吸，提示该脉动了
	b_end.urge = run.phase == RunState.Phase.PLAY and (run.plays <= 0 or hand_view.cards().all(func(c): return c.disabled))


func _refresh_hint() -> void:
	if run.phase == RunState.Phase.DISCARD:
		hint.text = "手牌超过上限 %d：点手牌弃掉，还需弃 %d 张。" % [run.hand_limit(), run.overflow()]
	elif transplant_mode and transplant_from == BoardView.NO_CELL:
		hint.text = "移栽模式：点一张牌，把它和它后面的枝一起挪走。"
	elif transplant_mode:
		hint.text = "移栽%s：点亮的格子是新位置（整段枝随新朝向旋转）。右键或 Esc 取消。" % _nm(run.tree.at(transplant_from))
	elif prune_mode:
		hint.text = "修剪模式：点一张牌，剪掉它和它后面的所有枝。"
	elif sel >= 0:
		hint.text = "选中%s：点亮的虚线格可以放。把鼠标移到格子上查看预计变化。" % Cards.get_def(run.hand[sel]).display_name
	else:
		hint.text = "选一张手牌开始生长，或者直接结束回合让神树脉动。"


# ---------- 输入 ----------

func _select(i: int) -> void:
	if run.phase == RunState.Phase.DISCARD:
		if run.discard_card(i):
			Game.sfx(&"click", 0.8)
			_hand_sig = ""
			_after_action()
		return
	Game.sfx(&"click", 1.2)
	sel = -1 if sel == i else i
	prune_mode = false
	_cancel_transplant()
	flash = {}
	_refresh()


func _on_drag_started(i: int) -> void:
	sel = i
	prune_mode = false
	flash = {}
	_refresh()


func _on_card_dropped(i: int, c: Vector2i) -> void:
	sel = i
	_place(c)


func _on_cell_clicked(c: Vector2i) -> void:
	if board.is_animating():
		return
	if transplant_mode:
		if transplant_from == BoardView.NO_CELL:
			if c != TreeModel.SEED_KEY and run.tree.has(c):
				if run.transplant_targets(c).is_empty():
					hint.text = "%s没有可以挪去的位置（藤不能作为移栽的起点；子枝里有接到外面的藤也不行）。" % _nm(run.tree.at(c))
					return
				transplant_from = c
				Game.sfx(&"click", 1.1)
				_refresh()
		elif c == transplant_from:
			transplant_from = BoardView.NO_CELL
			_refresh()
		elif run.transplant(transplant_from, c):
			Game.sfx(&"place")
			board.stamp_at(c, Palette.OCHRE)
			Fx.shake(board, 1.2, 0.15)
			_cancel_transplant()
			flash = {}
			_after_action()
		return
	if prune_mode:
		if tut and not tut.prune_allowed(run, c):
			return
		var gain := run.prune(c)
		if gain >= 0:
			Game.sfx(&"prune")
			# 剪掉的枝头飘落叶子
			Fx.falling_leaves(board, board.center_of(c))
			prune_mode = false
			flash = {}
			_after_action()
	elif sel >= 0:
		_place(c)


func _place(c: Vector2i) -> void:
	if board.is_animating() or not _targets().has(c):
		return
	var card_id := run.hand[sel]
	var played := sel
	if run.place(sel, c):
		hand_view.mark_played(played, board.global_position + board.center_of(c))
		Game.sfx(&"place")
		# 落牌：墨迹扩散 + 纸片压印
		var def := Cards.get_def(card_id)
		board.stamp_at(c, Palette.card_color(def.color_key))
		Fx.shake(board, 1.5, 0.18)
		sel = -1
		flash = {}
		_after_action()


func _on_cell_hovered(c: Vector2i) -> void:
	var now := run.preview().total
	board.highlight = {}
	board.delta = {}
	board.ghost_type = &""
	board.set_trace(BoardView.NO_CELL)
	board.set_chain("")
	if transplant_mode:
		if transplant_from == BoardView.NO_CELL and c != TreeModel.SEED_KEY and run.tree.has(c):
			board.highlight = Growth.subtree(run.tree, c)
			hint.text = "移栽%s：连同后面 %d 张一起挪走。" % [_nm(run.tree.at(c)), board.highlight.size() - 1]
		elif transplant_from != BoardView.NO_CELL:
			board.highlight = Growth.subtree(run.tree, transplant_from)
			var after := run.tree_after_transplant(transplant_from, c)
			if after:
				hint.text = "挪到这里：下次脉动 %d → %d" % [now, Pulse.resolve(after, run.ctx()).total]
		board.queue_redraw()
		return
	if sel >= 0 and board.targets.has(c):
		_preview_placement(c, now)
	elif sel >= 0:
		var why := Growth.why_not(run.tree, run.hand[sel], c, run.ctx())
		if tut and why == "":
			why = "新手指导这一步请按提示放在指定位置。"
		hint.text = ("不能放在这里：" + why) if why != "" else "这里不能放。"
	elif prune_mode and c != TreeModel.SEED_KEY and run.tree.has(c) and (tut == null or tut.prune_allowed(run, c)):
		var pv := run.preview_prune(c)
		if not pv.is_empty():
			board.highlight = Growth.subtree(run.tree, c)
			hint.text = "剪掉 %d 张，得 %d 养分；下次脉动 %d → %d" % [pv.count, pv.gain, now, pv.total]
	elif run.tree.has(c) and not board.is_animating() and not prune_mode:
		_show_flow(c)
	else:
		_refresh_hint()
		var lt := run.tree.land_at(c)
		if lt != Land.Type.PLAIN:
			hint.text = "%s：%s" % [Land.name_of(lt), Land.desc_of(lt)]
	board.queue_redraw()


## 悬停一张牌：牌桌上播放从树心到它的养分流动，左上角显示完整计算链。
func _show_flow(c: Vector2i) -> void:
	board.set_trace(c)
	var res := board.pulse
	var nodes := board._trace_nodes.keys()
	nodes.sort_custom(func(a, b): return run.tree.at(a).order < run.tree.at(b).order)
	var lines: Array[String] = []
	for x in nodes:
		var n := run.tree.at(x)
		if n.is_seed():
			lines.append("树心 输出 %d（第%d年%s，每季翻倍）" % [res.out[x], run.year, Rules.season_name(run.season)])
			continue
		var tr: Array = res.trace.get(x, [])
		var steps: Array = tr if n.def().is_graft() else tr.slice(1)
		var ops: Array[String] = []
		for st in steps:
			ops.append(String(st.op) if st.label == n.def().display_name else "%s %s" % [st.label, st.op])
		lines.append("→ %s：%s = %d" % [n.def().display_name, "，".join(ops), res.out[x]])
	var n := run.tree.at(c)
	if res.tips.has(c):
		var tt: Array = res.tip_trace.get(c, [])
		var parts: Array[String] = ["%d" % res.out[c]]
		for st in tt.slice(1):
			parts.append("%s %s" % [st.label, st.op])
		if parts.size() == 1:
			lines.append("末梢收获 %d（没有额外加成）" % res.contrib[c])
		else:
			lines.append("末梢收获：%s = %d" % ["，".join(parts), res.contrib[c]])
	else:
		lines.append("（%s不是末梢：养分继续流向后面的 %d 张牌，它自己不计分）" % [_nm(n), n.children.size()])
	board.set_chain("\n".join(lines))
	if n.is_seed():
		hint.text = "树心：每季成熟一次，输出的养分翻倍；第 y 年再乘以 y。"
	else:
		hint.text = "%s（%s）：%s" % [n.def().display_name, n.def().tag_line(), n.def().desc]
		if not n.marks.is_empty():
			hint.text += "  年轮：" + "、".join(n.marks.map(func(m): return Rules.mark_name(m)))


## 悬停目标格：画预览牌，标出每个末梢收获的增减，并用一句话说清楚为什么。
func _preview_placement(c: Vector2i, now: int) -> void:
	var after_tree := run.tree_after_place(sel, c)
	if after_tree == null:
		return
	board.ghost_type = run.hand[sel]
	var before := board.pulse
	var after := run.explained(after_tree)
	var gained: Array[String] = []
	var lost: Array[String] = []
	var d := {}
	for k in before.tip_list:
		var b: int = before.contrib[k]
		var a: int = after.contrib.get(k, 0)
		if not after.tips.has(k):
			d[k] = -b
			lost.append("%s −%d" % [_nm(run.tree.at(k)), b])
		elif a != b:
			d[k] = a - b
			gained.append("%s %+d" % [_nm(run.tree.at(k)), a - b])
	for k in after.tip_list:
		if not before.tips.has(k):
			d[k] = after.contrib[k]
			gained.append("新末梢%s +%d" % [_nm(after_tree.at(k)), after.contrib[k]])
	board.delta = d
	var parts: Array[String] = []
	if not gained.is_empty():
		parts.append("、".join(gained))
	if not lost.is_empty():
		parts.append("不再是末梢：" + "、".join(lost))
	var mult := ""
	if after.total_mult != 1.0:
		mult = "（整树 ×%s）" % Pulse.num(after.total_mult)
	hint.text = "放在这里：下次脉动 %d → %d%s。%s" % [now, after.total, mult, "；".join(parts)]


func _nm(n: TreeNode) -> String:
	return "树心" if n.is_seed() else n.def().display_name


## 数字变化时滚动过去，静止时不动。
func _set_num(label: Label, value: int) -> void:
	if label.text == str(value):
		return
	Fx.count_to(label, value, 0.45)


func _on_hover_cleared() -> void:
	board.highlight = {}
	board.delta = {}
	board.ghost_type = &""
	board.set_trace(BoardView.NO_CELL)
	board.set_chain("")
	board.queue_redraw()
	_refresh_hint()


func _toggle_prune() -> void:
	if not run.can_prune() and not prune_mode:
		return
	if tut and not tut.can_prune_mode() and not prune_mode:
		return
	prune_mode = not prune_mode
	sel = -1
	_cancel_transplant()
	_refresh()


func _toggle_transplant() -> void:
	if transplant_mode:
		_cancel_transplant()
	elif run.can_transplant() and (tut == null or tut.is_free()):
		transplant_mode = true
		transplant_from = BoardView.NO_CELL
		prune_mode = false
		sel = -1
	_refresh()


func _cancel_transplant() -> void:
	transplant_mode = false
	transplant_from = BoardView.NO_CELL


func _harvest() -> void:
	if board.is_animating() or tut != null or not run.can_harvest():
		return
	sel = -1
	prune_mode = false
	_cancel_transplant()
	run.harvest()
	Game.sfx(&"win")
	Game.save()
	_refresh()
	_show_phase_modal()


func _redraw() -> void:
	if tut and not tut.is_free():
		return
	if run.redraw():
		hand_view.discard_all()
		_hand_sig = ""
		sel = -1
		_after_action()


func _end_turn() -> void:
	if board.is_animating() or (tut and not tut.can_end_turn()):
		return
	var snap := run.tree.copy()
	last_sheet = run.explained()
	last_sheet_tree = snap
	var first_pulse := run.turn == 1
	var before := run.score
	var target_before := run.target()
	var res := run.end_turn()
	if res == null:
		return
	if tut == null:
		var msgs := Game.profile.record_pulse(run, snap, res)
		if run.phase == RunState.Phase.WON:
			msgs.append_array(Game.profile.record_progress(run))
		_toast(msgs)
	sel = -1
	prune_mode = false
	_cancel_transplant()
	flash = res.contrib.duplicate()
	hand_view.draw_delay = board.pulse_duration(snap)
	if not Game.reduce_motion:
		_score_shown = before
		_score_target = target_before
	_after_action()
	_build_sheet()
	board.play_pulse(snap, res)
	if relic_bar:
		relic_bar.flash(_active_relics(snap, res, first_pulse), 0.25)
	if board.is_animating():
		await board.pulse_finished
	if _score_shown >= 0:
		await _score_finale(res, before + res.total, target_before)
		if not is_inside_tree():
			return
	match run.phase:
		RunState.Phase.LOST:
			Game.sfx(&"lose")
		RunState.Phase.REWARD, RunState.Phase.RELIC, RunState.Phase.WON:
			Game.sfx(&"win")
	_show_phase_modal()


# ---------- 计分演出 ----------

## 一个末梢收获：数字从牌桌飞进左上角的季节铭牌，落地时分数跳一下。
func _on_tip_harvested(_cell: Vector2i, amount: int, at: Vector2) -> void:
	if _score_shown < 0 or amount <= 0:
		return
	var from := board.global_position + at
	var to := lbl_score.global_position + lbl_score.size * 0.5
	var l := Label.new()
	l.text = "+%d" % amount
	l.add_theme_font_override("font", Palette.title())
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Palette.TERRA)
	l.add_theme_color_override("font_outline_color", Palette.CREAM)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_layer.add_child(l)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.position = from - l.size * 0.5
	l.scale = Vector2.ONE * 1.25
	var ctrl := from.lerp(to, 0.3) + Vector2(0, -160)
	var tw := l.create_tween()
	tw.tween_interval(0.22)
	tw.tween_method(func(t: float):
		var u := 1.0 - t
		var p := from * u * u + ctrl * 2.0 * u * t + to * t * t
		l.position = p - l.size * 0.5
		l.scale = Vector2.ONE * lerpf(1.25, 0.6, t)
		l.modulate.a = 1.0 if t < 0.85 else (1.0 - t) / 0.15, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		l.queue_free()
		_bump_score(amount))


func _bump_score(amount: int) -> void:
	if _score_shown < 0:
		return
	var was := _score_shown
	_score_shown += amount
	_refresh_score_only()
	_punch(lbl_score, 1.3)
	if was < _score_target and _score_shown >= _score_target:
		_goal_flare()


func _refresh_score_only() -> void:
	var shown := run.score if _score_shown < 0 else _score_shown
	var tgt := run.target() if _score_shown < 0 else _score_target
	lbl_score.text = "%d / %d" % [shown, tgt]
	bar.max_value = tgt
	bar.value = mini(shown, tgt)


## 数字/控件的冲击：放大后弹回。
func _punch(c: Control, amount: float = 1.25) -> void:
	if c == null or Game.reduce_motion:
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * amount, 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 达标：季节铭牌金光一闪 + 一圈金屑。
func _goal_flare() -> void:
	Game.sfx(&"win", 1.3)
	if Game.reduce_motion:
		return
	var tw := stats_box.create_tween()
	tw.tween_property(stats_box, "shadow_color", Palette.GOLD, 0.08)
	tw.tween_property(stats_box, "shadow_color", Color(Palette.INK, 0.45), 0.9)
	_punch(stats_box, 1.04)
	var p := CPUParticles2D.new()
	p.position = lbl_score.global_position + lbl_score.size * 0.5
	p.amount = 36
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 380)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = Palette.GOLD.lightened(0.2)
	fly_layer.add_child(p)
	p.emitting = true
	var t2 := p.create_tween()
	t2.tween_interval(1.4)
	t2.tween_callback(p.queue_free)


## 收尾：牌型和整树倍率像印章一样砸下，分数滚到最终值。
func _score_finale(res: Pulse.Result, final: int, target_before: int) -> void:
	var names: Array[String] = []
	for pat in res.patterns:
		names.append(pat.label)
	if not names.is_empty() or res.total_mult != 1.0:
		var txt := "、".join(names)
		if res.total_mult != 1.0:
			txt += ("　" if txt != "" else "") + "×" + Pulse.num(res.total_mult)
		await _stamp_text(txt)
		if not is_inside_tree():
			return
	var was := _score_shown
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_score_shown = int(round(v))
		_refresh_score_only(), float(_score_shown), float(final), 0.35).set_trans(Tween.TRANS_CUBIC)
	await tw.finished
	if not is_inside_tree():
		return
	if was < target_before and final >= target_before:
		_goal_flare()
	_punch(lbl_score, 1.35)
	await get_tree().create_timer(0.25).timeout
	if not is_inside_tree():
		return
	_score_shown = -1
	_refresh_score_only()


## 牌桌中央盖一枚大字印章（牌型、倍率）。
func _stamp_text(txt: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", Palette.title_for(txt))
	l.add_theme_font_size_override("font_size", 64)
	l.add_theme_color_override("font_color", Palette.TERRA)
	l.add_theme_color_override("font_outline_color", Palette.CREAM)
	l.add_theme_constant_override("outline_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_layer.add_child(l)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.position = board.global_position + board.origin - l.size * 0.5 + Vector2(0, -board.hex_size * 2.0)
	l.rotation = deg_to_rad(-5.0)
	l.scale = Vector2.ONE * 2.4
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.chain().tween_callback(func():
		Game.sfx(&"place", 0.7)
		Fx.shake(board, 2.0, 0.25))
	tw.chain().tween_interval(0.55)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	await tw.finished
	l.queue_free()


## 本次脉动里真正起了作用的器物（只用于表现：让它们在牌桌上跳一下）。
func _active_relics(t: TreeModel, res: Pulse.Result, first_pulse: bool) -> Array:
	var out := []
	for rid in run.relics:
		match rid:
			&"dew":
				if first_pulse:
					out.append(rid)
			&"knife":
				if t.nodes.values().any(func(n): return not n.is_seed() and n.def().is_graft()):
					out.append(rid)
			&"beehive":
				if t.nodes.values().any(func(n): return not n.is_seed() and n.def().aura > 0):
					out.append(rid)
			&"ruler":
				if res.patterns.any(func(p): return p.id == &"long"):
					out.append(rid)
			&"root":
				out.append(rid)
	return out


func _after_action() -> void:
	Game.save()
	if tut:
		tut.update(run)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if modal.visible or not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_SPACE, KEY_ENTER:
			_end_turn()
		KEY_P:
			_toggle_prune()
		KEY_T:
			_toggle_transplant()
		KEY_G:
			_harvest()
		KEY_F:
			if board is Board3D:
				board.reset_view()
		KEY_R:
			_redraw()
		KEY_L:
			_toggle_log()
		KEY_H:
			_toggle_rules()
		KEY_ESCAPE:
			sel = -1
			prune_mode = false
			_cancel_transplant()
			_refresh()
		_:
			var i: int = e.keycode - KEY_1
			if i >= 0 and i < run.hand.size() and run.can_play(i):
				_select(i)
			else:
				return
	get_viewport().set_input_as_handled()


# ---------- 弹窗 ----------

## 右上角依次浮出几条消息（联动谱新条目、解锁），同时写进记录。
func _toast(msgs: Array[String]) -> void:
	var all := Game.notices.duplicate()
	all.append_array(msgs)
	Game.notices.clear()
	for i in all.size():
		run.add_log(all[i])
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Palette.INK, 0.88)
		sb.border_color = Palette.GOLD
		sb.set_border_width_all(1)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		box.add_theme_stylebox_override("panel", sb)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.text = all[i]
		l.add_theme_color_override("font_color", Palette.GOLD.lightened(0.35))
		l.add_theme_font_size_override("font_size", 18)
		box.add_child(l)
		fly_layer.add_child(box)
		box.position = Vector2(size.x - 520, 130 + i * 52)
		box.modulate.a = 0.0
		var tw := box.create_tween()
		tw.tween_interval(0.3 + i * 0.4)
		tw.tween_property(box, "modulate:a", 1.0, 0.25)
		tw.tween_interval(3.5)
		tw.tween_property(box, "modulate:a", 0.0, 0.6)
		tw.tween_callback(box.queue_free)


func _show_phase_modal() -> void:
	match run.phase:
		RunState.Phase.REWARD when tut != null:
			_finish_tutorial_modal()
		RunState.Phase.REWARD:
			var btns: Array = []
			for i in run.reward_options.size():
				btns.append({"card": run.reward_options[i], "fn": _choose_reward.bind(i)})
			btns.append({"label": "跳过，得 %d 养分" % Rules.SKIP_REWARD_SAP, "fn": _skip_reward})
			_open_modal("%s达标" % run.season_label(),
				"本季累计 %d / %d，另得 %d 养分。选一张牌加入牌组，然后去集市；神树会带着现在的形状进入下一季。" % [run.score, run.target(), Rules.SEASON_CLEAR_SAP], btns)
		RunState.Phase.RELIC:
			var btns: Array = []
			for i in run.relic_options.size():
				btns.append({"relic_id": run.relic_options[i], "fn": _choose_relic.bind(i), "relic": true})
			btns.append({"label": "跳过，得 %d 养分" % Rules.SKIP_REWARD_SAP, "fn": _skip_relic})
			_open_modal("度过%s" % Cards.calamity(run.calamity).display_name,
				"天灾季累计 %d / %d，得 %d 养分。选一件器物，然后进入集市。" % [run.score, run.target(), Rules.CALAMITY_CLEAR_SAP], btns)
		RunState.Phase.MARKET:
			Game.goto(&"market")
		RunState.Phase.EVENT:
			Game.goto(&"event")
		RunState.Phase.LOST:
			_open_modal("这一季没有达标", "%s累计 %d，目标 %d。神树停止了生长。" % [run.season_label(), run.score, run.target()],
				[{"label": "重新开始", "fn": func(): Game.new_run(), "primary": true}, {"label": "导出神树版画", "fn": _export_print}, {"label": "主菜单", "fn": func(): Game.goto(&"menu")}])
		RunState.Phase.WON:
			_open_modal("神树成年", "三年过去，神树长成了。牌桌上共有 %d 张牌，带着 %d 件器物。" % [run.tree.size() - 1, run.relics.size()],
				[{"label": "再培育一棵", "fn": func(): Game.new_run(), "primary": true}, {"label": "导出神树版画", "fn": _export_print}, {"label": "主菜单", "fn": func(): Game.goto(&"menu")}])
		_:
			modal.visible = false


func _open_modal(title: String, text: String, btns: Array) -> void:
	modal_title.text = title
	modal_text.text = text
	for ch in modal_btns.get_children():
		ch.queue_free()
	var first: Control = null
	var deal := 0
	for b in btns:
		var el: Button
		if b.has("card"):
			var cv := CardView.make(b.card)
			cv.draggable = false
			el = cv
		elif b.has("relic_id"):
			el = _relic_button(b)
		else:
			el = Button.new()
			el.text = b.label
			el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if b.get("relic", false):
				el.custom_minimum_size = Vector2(230, 110)
				el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				el.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if b.get("primary", false):
				el.theme_type_variation = &"PrimaryButton"
		el.pressed.connect(b.fn)
		modal_btns.add_child(el)
		# 发牌：依次淡入
		if el is CardView:
			# 发牌：依次从桌面抬起、淡入，带一点回弹
			el.modulate = Color(1, 1, 1, 0)
			el.lift = 1.6
			Fx.prop(el, "modulate:a", 1.0, 0.28, Fx.ease_out, 0.15 + deal * 0.11)
			Fx.prop(el, "lift", 0.0, 0.45, Fx.back_out, 0.15 + deal * 0.11)
			deal += 1
		if first == null:
			first = el
	modal.visible = true
	if not Game.reduce_motion:
		# 弹窗：底色淡入，纸片从下方浮上来
		modal.modulate.a = 0.0
		var box: Control = modal.get_child(0).get_child(0)
		box.pivot_offset = box.size * 0.5
		box.scale = Vector2.ONE * 0.92
		var tw := modal.create_tween()
		tw.set_parallel(true)
		tw.tween_property(modal, "modulate:a", 1.0, 0.22)
		tw.tween_property(box, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if first:
		first.grab_focus.call_deferred()


## 器物按钮：左边一幅器物版画，右边名字和说明。
func _relic_button(b: Dictionary) -> Button:
	var rid: StringName = b.relic_id
	var r := Cards.relic(rid)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(258, 118)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", Palette.INK)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	var art := ArtView.new()
	art.art_id = rid
	art.mode = 1
	art.custom_minimum_size = Vector2(76, 76)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var n := Label.new()
	n.text = r.display_name
	n.theme_type_variation = &"TitleLabel"
	n.add_theme_font_size_override("font_size", 22)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(n)
	var d := Label.new()
	d.text = r.desc
	d.theme_type_variation = &"SoftLabel"
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(150, 0)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(d)
	return btn


func _choose_reward(i: int) -> void:
	run.choose_reward(i)
	_after_season()


func _skip_reward() -> void:
	run.skip_reward()
	_after_season()


func _choose_relic(i: int) -> void:
	if run.relics_full():
		_ask_replace(i)
		return
	run.choose_relic(i)
	Game.save()
	Game.goto(&"market")


## 器物槽满了：选一件旧器物换下（按出售价返还养分）。
func _ask_replace(i: int) -> void:
	var nr := Cards.relic(run.relic_options[i])
	var btns: Array = []
	for j in run.relics.size():
		var old := Cards.relic(run.relics[j])
		btns.append({"label": "换下%s（+%d 养分）" % [old.display_name, run.relic_sell_price(run.relics[j])], "fn": _replace_relic.bind(i, j)})
	btns.append({"label": "返回", "fn": _show_phase_modal})
	_open_modal("器物槽已满", "要装上%s，需要先换下一件器物。" % nr.display_name, btns)


func _replace_relic(i: int, j: int) -> void:
	if run.choose_relic(i, j):
		Game.save()
		Game.goto(&"market")


func _skip_relic() -> void:
	run.skip_relic()
	Game.save()
	Game.goto(&"market")


func _after_season() -> void:
	modal.visible = false
	Game.save()
	Game.goto(&"event" if run.phase == RunState.Phase.EVENT else &"market")


## 把牌桌截成一张“神树版画”，存到 user://prints 并打开文件夹。
func _export_print() -> void:
	modal.visible = false
	flash = {}
	board.flash = {}
	board.queue_redraw()
	hud.visible = false
	hand_view.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	hud.visible = true
	hand_view.visible = true
	var r: Rect2 = get_viewport().get_final_transform() * board.grid_rect()
	var region := Rect2i(r).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var cut := img.get_region(region)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://prints"))
	var path := "user://prints/shentree_%s.png" % Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	cut.save_png(path)
	modal.visible = true
	modal_text.text += "
版画已保存：" + ProjectSettings.globalize_path(path)
	OS.shell_open(ProjectSettings.globalize_path("user://prints"))


func _to_menu() -> void:
	Game.save()
	Game.goto(&"menu")



# ---------- 新手指导 ----------

func _build_tutorial() -> void:
	# 指导面板替换侧栏里的规则说明
	tut_panel = PrintBox.new()
	tut_panel.shadow_color = Palette.OCHRE
	tut_panel.shadow_offset = Vector2(6, 6)
	tut_panel.padding = 16
	left_col.add_child(tut_panel)
	left_col.move_child(tut_panel, 1)
	tut_panel.border_color = Palette.INK
	rules_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	tut_panel.add_child(v)
	tut_title = Label.new()
	tut_title.theme_type_variation = &"TitleLabel"
	tut_title.add_theme_font_size_override("font_size", 24)
	tut_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tut_title)
	tut_text = Label.new()
	tut_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tut_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	tut_next = Button.new()
	tut_next.text = "继续"
	tut_next.theme_type_variation = &"PrimaryButton"
	tut_next.pressed.connect(func():
		tut.next()
		_refresh())
	row.add_child(tut_next)
	var skip := Button.new()
	skip.text = "跳过指导"
	skip.pressed.connect(_skip_tutorial)
	row.add_child(skip)
	tut.step_changed.connect(_refresh_tutorial)
	_refresh_tutorial()


func _refresh_tutorial() -> void:
	if tut == null or tut_panel == null:
		return
	var st := tut.current()
	tut_title.text = "新手指导 %d/%d · %s" % [tut.step + 1, tut.steps.size(), st.title]
	tut_text.text = st.text
	tut_next.visible = tut.is_info()
	if tut.is_info():
		tut_next.grab_focus.call_deferred()
	Game.sfx(&"click", 0.8)


func _finish_tutorial_modal() -> void:
	tut_panel.visible = false
	_open_modal("新手指导完成",
		"你已经学会了神树的全部基本操作。正式对局里还有这些：
"
		+ "· 一局三年，每年春夏秋冬四季加一个天灾季，每季要达到目标分数，否则神树停止生长。
"
		+ "· 季节各有特性：春多抽一张、夏多放一张、秋末端牌 ×1.5、冬季末最老的末梢会枯萎。
"
		+ "· 每季达标后三选一加一张新牌；度过天灾后选一件器物，再去集市花养分买牌、刻年轮、改造土地。
"
		+ "· 土地有沃土（+2）、岩石（不能长）、泉眼（相邻末梢 +2）。
"
		+ "· 树的形状还能组成长茎、星芒、闭环、对称等牌型，带来额外倍率。
"
		+ "三年之后，神树成年。",
		[{"label": "开始新的一局", "fn": _tutorial_to_new_run, "primary": true},
		 {"label": "返回主菜单", "fn": _skip_tutorial}])


func _tutorial_to_new_run() -> void:
	Game.finish_tutorial()
	Game.new_run()


func _skip_tutorial() -> void:
	Game.finish_tutorial()
	Game.goto(&"menu")



# ---------- 脉动结算单 ----------

func _build_sheet() -> void:
	for ch in sheet_box.get_children():
		ch.queue_free()
	var res := last_sheet
	if res == null:
		return
	if tut:
		return
	sheet_panel.visible = true
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text = "%s 本回合脉动结算：+%d" % ["▼" if sheet_open else "▲", res.total]
	head.tooltip_text = "点击收起/展开"
	head.add_theme_color_override("font_color", Palette.OCHRE.darkened(0.2))
	head.pressed.connect(_toggle_sheet)
	sheet_box.add_child(head)
	if not sheet_open:
		return
	var tips := res.tip_list.duplicate()
	tips.sort_custom(func(a, b): return res.contrib[a] > res.contrib[b])
	const MAX_ROWS := 6
	var hidden: int = maxi(0, tips.size() - MAX_ROWS)
	tips = tips.slice(0, MAX_ROWS)
	for k in tips:
		var n := last_sheet_tree.at(k)
		var tt: Array = res.tip_trace.get(k, [])
		var extra: Array[String] = []
		for st in tt.slice(1):
			extra.append("%s %s" % [st.label, st.op])
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		if extra.is_empty():
			b.text = "· %s：%d" % [_nm(n), res.contrib[k]]
		else:
			b.text = "· %s：%d，%s = %d" % [_nm(n), res.out[k], "，".join(extra), res.contrib[k]]
		b.tooltip_text = "点击在牌桌上找到它"
		b.pressed.connect(board.blink.bind(k))
		sheet_box.add_child(b)
	if hidden > 0:
		var more := Label.new()
		more.theme_type_variation = &"SoftLabel"
		more.text = "　……另有 %d 个末梢" % hidden
		sheet_box.add_child(more)
	for st in res.total_trace:
		var l := Label.new()
		l.text = "· %s：%s" % [st.label, st.op]
		l.add_theme_color_override("font_color", Palette.OCHRE)
		sheet_box.add_child(l)
	var foot := Label.new()
	foot.theme_type_variation = &"SoftLabel"
	var left := run.target() - run.score
	if run.phase == RunState.Phase.PLAY:
		foot.text = "本季累计 %d / %d，%s" % [run.score, run.target(), ("还差 %d" % left) if left > 0 else "已达标"]
	else:
		foot.text = "本季累计 %d / %d" % [run.score, run.target()]
	sheet_box.add_child(foot)


func _toggle_sheet() -> void:
	sheet_open = not sheet_open
	_build_sheet()
