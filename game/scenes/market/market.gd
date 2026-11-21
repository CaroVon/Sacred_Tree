extends Control
## 集市：用养分购买牌、年轮印记、地块改造和删牌服务，然后进入下一年。

enum Pick { NONE, MARK, CLEAR_ROCK, FERTILE }

var run: RunState
var pick: Pick = Pick.NONE
var pick_mark: StringName = &""

var board: BoardView
var hint: Label
var relic_bar: RelicBar
var lbl_sap: Label
var offers: HFlowContainer
var services: VBoxContainer
var deck_box: HFlowContainer


const PANEL_W := 900.0
const OFFER_W := 172.0
const OFFER_H := 292.0

var deck_pile: PileView
var fly_layer: Control
var coin: PanelContainer


func _ready() -> void:
	run = Game.run
	if run.phase != RunState.Phase.MARKET:
		Game.goto(&"map")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---------- 整屏牌桌（器物立在两侧） ----------
	board = Board3D.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.margins = Vector4(70, 110, PANEL_W + 80, 200)
	board.show_buds = false
	board.ctx = run.ctx()
	board.cell_clicked.connect(_on_cell)
	board.cell_hovered.connect(_on_hover)
	add_child(board)
	board.set_mood(run.season, &"")
	board.set_relics.call_deferred(run.relics)

	# 左上：题名 + 提示丝带
	var tl := VBoxContainer.new()
	tl.position = Vector2(36, 26)
	tl.add_theme_constant_override("separation", 8)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl)
	var title := Label.new()
	title.text = "集市"
	title.theme_type_variation = &"DisplayLabel"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Palette.CREAM)
	title.add_theme_color_override("font_outline_color", Color(Palette.INK, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	tl.add_child(title)
	var hb := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(Palette.SHEET, 0.92)
	hsb.border_color = Color(Palette.OCHRE, 0.8)
	hsb.border_width_top = 1
	hsb.border_width_bottom = 1
	hsb.content_margin_left = 16
	hsb.content_margin_right = 16
	hsb.content_margin_top = 5
	hsb.content_margin_bottom = 5
	hb.add_theme_stylebox_override("panel", hsb)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(hb)
	hint = Label.new()
	hint.theme_type_variation = &"SoftLabel"
	hint.add_theme_color_override("font_color", Palette.INK)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(820, 0)
	hb.add_child(hint)

	# 左下：牌库（买下的牌飞进来）
	deck_pile = PileView.new()
	deck_pile.title = "牌组"
	deck_pile.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	deck_pile.grow_vertical = Control.GROW_DIRECTION_BEGIN
	deck_pile.offset_left = 40
	deck_pile.offset_bottom = -22
	add_child(deck_pile)

	# ---------- 右边：摊位 ----------
	var page := PrintBox.new()
	page.padding = 26
	page.shadow_offset = Vector2(8, 10)
	page.shadow_color = Color(Palette.INK, 0.45)
	page.inner_border = true
	page.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	page.offset_left = -PANEL_W - 30
	page.offset_right = -30
	page.offset_top = 26
	page.offset_bottom = -26
	add_child(page)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	page.add_child(right)
	var head := HBoxContainer.new()
	right.add_child(head)
	var stall := Label.new()
	stall.text = "摊位"
	stall.theme_type_variation = &"SubtitleLabel"
	stall.add_theme_font_size_override("font_size", 30)
	head.add_child(stall)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	# 养分：一枚铜钱铭牌
	coin = PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Palette.INK
	csb.border_color = Palette.GOLD
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(22)
	csb.content_margin_left = 18
	csb.content_margin_right = 18
	csb.content_margin_top = 4
	csb.content_margin_bottom = 4
	coin.add_theme_stylebox_override("panel", csb)
	head.add_child(coin)
	lbl_sap = Label.new()
	lbl_sap.theme_type_variation = &"NumericLabel"
	lbl_sap.add_theme_font_size_override("font_size", 26)
	lbl_sap.add_theme_color_override("font_color", Palette.GOLD.lightened(0.3))
	coin.add_child(lbl_sap)

	right.add_child(_heading("买牌"))
	var shelf := Control.new()
	shelf.custom_minimum_size = Vector2(0, OFFER_H + 26)
	shelf.draw.connect(func():
		# 石台：牌立在一条带金边的石条上
		var y := OFFER_H + 6.0
		shelf.draw_rect(Rect2(0, y, shelf.size.x, 14), Palette.CELL.darkened(0.06))
		shelf.draw_line(Vector2(0, y), Vector2(shelf.size.x, y), Palette.GOLD, 2.0)
		shelf.draw_rect(Rect2(0, y + 14, shelf.size.x, 5), Color(Palette.INK, 0.18)))
	right.add_child(shelf)
	offers = HFlowContainer.new()
	offers.add_theme_constant_override("h_separation", 22)
	offers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offers.offset_left = 8
	shelf.add_child(offers)
	right.add_child(_heading("年轮印记与土地"))
	services = VBoxContainer.new()
	services.add_theme_constant_override("separation", 6)
	right.add_child(services)
	right.add_child(_heading("删牌（每张 %d 养分）" % Rules.REMOVE_CARD_PRICE))
	deck_box = HFlowContainer.new()
	deck_box.add_theme_constant_override("h_separation", 8)
	deck_box.add_theme_constant_override("v_separation", 8)
	right.add_child(deck_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var leave := Button.new()
	leave.text = "离开集市，进入第%d年" % (run.year + 1)
	leave.theme_type_variation = &"PrimaryButton"
	leave.add_theme_font_size_override("font_size", 24)
	leave.custom_minimum_size = Vector2(0, 58)
	leave.pressed.connect(_leave)
	right.add_child(leave)

	fly_layer = Control.new()
	fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fly_layer)
	_refresh()


func _heading(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_font_size_override("font_size", 24)
	return l


func _refresh() -> void:
	if lbl_sap.text != "" and lbl_sap.text != "养分 %d" % run.sap:
		_punch(coin)
	lbl_sap.text = "养分 %d" % run.sap
	deck_pile.count = run.deck.size() + run.discard.size() + run.hand.size()
	if relic_bar:
		relic_bar.set_relics(run.relics)
	# 选择模式下点亮可选位置
	var tg := {}
	var np := {}
	for c in Hex.all_cells(run.tree.radius):
		match pick:
			Pick.MARK:
				if run.can_mark(pick_mark, c):
					np[c] = true
			Pick.CLEAR_ROCK:
				if run.can_clear_rock(c):
					tg[c] = true
			Pick.FERTILE:
				if run.can_make_fertile(c) and not run.tree.has(c):
					tg[c] = true
				elif run.can_make_fertile(c):
					np[c] = true
	board.node_pick = np
	board.set_state(run.tree, run.preview(), tg, false, {})

	for ch in offers.get_children():
		ch.queue_free()
	for i in run.market_cards.size():
		var id := run.market_cards[i]
		var cv := CardView.make(id)
		cv.draggable = false
		cv.custom_minimum_size = Vector2(OFFER_W, OFFER_H)
		var price := Cards.get_def(id).price
		cv.disabled = run.sap < price
		cv.note = "%d 养分" % price
		cv.pressed.connect(_buy.bind(i))
		offers.add_child(cv)
	if run.market_cards.is_empty():
		var l := Label.new()
		l.text = "已经买空了。"
		l.theme_type_variation = &"SoftLabel"
		offers.add_child(l)

	for ch in services.get_children():
		ch.queue_free()
	for m in Rules.MARKS:
		var info: Dictionary = Rules.MARKS[m]
		_service("年轮「%s」（%d）：%s" % [info.name, info.price, info.desc], run.sap >= int(info.price),
			pick == Pick.MARK and pick_mark == m, _start_pick.bind(Pick.MARK, m))
	_service("清除岩石（%d）：把一块岩石变回平地" % Rules.CLEAR_ROCK_PRICE, run.sap >= Rules.CLEAR_ROCK_PRICE,
		pick == Pick.CLEAR_ROCK, _start_pick.bind(Pick.CLEAR_ROCK, &""))
	_service("养成沃土（%d）：%s" % [Rules.MAKE_FERTILE_PRICE, Land.desc_of(Land.Type.FERTILE)], run.sap >= Rules.MAKE_FERTILE_PRICE,
		pick == Pick.FERTILE, _start_pick.bind(Pick.FERTILE, &""))

	for ch in deck_box.get_children():
		ch.queue_free()
	var counts := run.deck_counts()
	for id in Cards.all_ids():
		if not counts.has(id):
			continue
		var b := Button.new()
		b.text = "%s ×%d" % [Cards.get_def(id).display_name, counts[id]]
		b.disabled = run.sap < Rules.REMOVE_CARD_PRICE
		b.tooltip_text = Cards.get_def(id).desc
		b.pressed.connect(_remove.bind(id))
		deck_box.add_child(b)

	match pick:
		Pick.MARK:
			hint.text = "点一张树上的牌，刻上年轮「%s」。再点一次按钮取消。" % Rules.mark_name(pick_mark)
		Pick.CLEAR_ROCK:
			hint.text = "点一块岩石把它清除。"
		Pick.FERTILE:
			hint.text = "点一块平地（可以已经长了牌）把它养成沃土。"
		_:
			hint.text = "神树带着现在的形状进入下一年。把鼠标移到格子上查看地块。"


func _service(text: String, enabled: bool, active: bool, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled and not active
	b.theme_type_variation = &"ActiveButton" if active else &""
	b.pressed.connect(fn)
	services.add_child(b)


func _start_pick(mode: Pick, mark: StringName) -> void:
	if pick == mode and pick_mark == mark:
		pick = Pick.NONE
	else:
		pick = mode
		pick_mark = mark
	_refresh()


func _on_cell(c: Vector2i) -> void:
	var ok := false
	match pick:
		Pick.MARK:
			ok = run.buy_mark(pick_mark, c)
		Pick.CLEAR_ROCK:
			ok = run.clear_rock(c)
		Pick.FERTILE:
			ok = run.make_fertile(c)
	if ok:
		pick = Pick.NONE
		Game.save()
		_refresh()


func _on_hover(c: Vector2i) -> void:
	if pick != Pick.NONE:
		board.queue_redraw()
		return
	var parts: Array[String] = []
	var n := run.tree.at(c)
	if n and not n.is_seed():
		parts.append(Cards.get_def(n.type).display_name + "：" + Cards.get_def(n.type).desc)
		for m in n.marks:
			parts.append("年轮「%s」" % Rules.mark_name(m))
	var lt := run.tree.land_at(c)
	if lt != Land.Type.PLAIN:
		parts.append("%s：%s" % [Land.name_of(lt), Land.desc_of(lt)])
	if not parts.is_empty():
		hint.text = "；".join(parts)


func _buy(i: int) -> void:
	var from := Rect2()
	var id: StringName = &""
	if i < offers.get_child_count() and offers.get_child(i) is CardView:
		from = offers.get_child(i).get_global_rect()
		id = offers.get_child(i).card_id
	if run.buy_card(i):
		Game.sfx(&"place", 1.1)
		if id != &"":
			_fly_to_deck(id, from)
		Game.save()
		_refresh()


## 买下的牌：一张复制品沿弧线飞进左下角的牌组，飞到时牌组跳一下。
func _fly_to_deck(id: StringName, from: Rect2) -> void:
	if Game.reduce_motion or fly_layer == null:
		return
	var cv := CardView.make(id)
	cv.draggable = false
	cv.disabled = true
	cv.custom_minimum_size = from.size
	cv.size = from.size
	cv.pivot_offset = from.size * 0.5
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_layer.add_child(cv)
	cv.position = from.position
	var to := deck_pile.global_position + deck_pile.top_point() - from.size * 0.5
	var start := from.position
	var ctrl := start.lerp(to, 0.5) + Vector2(0, -260)
	var tw := cv.create_tween()
	tw.tween_method(func(t: float):
		var u := 1.0 - t
		cv.position = start * u * u + ctrl * 2.0 * u * t + to * t * t
		cv.scale = Vector2.ONE * lerpf(1.0, 0.4, t)
		cv.rotation = lerpf(0.0, -0.5, t), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		cv.queue_free()
		_punch(deck_pile))


func _punch(c: Control) -> void:
	if c == null or Game.reduce_motion:
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * 1.18, 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _remove(id: StringName) -> void:
	if run.remove_card(id):
		Game.save()
		_refresh()


func _leave() -> void:
	run.leave_market()
	Game.save()
	Game.goto(&"map")


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and pick != Pick.NONE:
		pick = Pick.NONE
		_refresh()
		get_viewport().set_input_as_handled()
