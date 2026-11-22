extends Control
## 集市：每季结束后开放。用养分购买牌、器物、年轮印记、芽点、地块改造和删牌服务。
## 器物装在屏幕上方的装备槽里，右键可出售。

enum Pick { NONE, MARK, CLEAR_ROCK, FERTILE, PORT }

var run: RunState
var pick: Pick = Pick.NONE
var pick_mark: StringName = &""
## 芽点服务：已选中的牌（NO_CELL = 还没选）。
var port_from: Vector2i = BoardView.NO_CELL

var board: BoardView
var hint: Label
var relic_bar: RelicBar
var lbl_sap: Label
var offers: HFlowContainer
var relic_offers: HFlowContainer
var services: VBoxContainer
var deck_box: HFlowContainer
var refine_box: HFlowContainer


const PANEL_W := 900.0
const OFFER_W := 150.0
const OFFER_H := 255.0
var tabs: TabBar
var _tab_nodes: Array = []
## 集市卖的牌下方写效果说明的高度。
const OFFER_DESC_H := 128.0

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
	board.margins = Vector4(70, 190, PANEL_W + 80, 200)
	board.show_buds = false
	board.ctx = run.ctx()
	board.cell_clicked.connect(_on_cell)
	board.cell_hovered.connect(_on_hover)
	add_child(board)
	board.set_mood(run.season, &"")

	# 上方：装备槽（右键出售）
	relic_bar = RelicBar.new()
	relic_bar.sell_price = run.relic_sell_price
	relic_bar.sell_mode = true
	relic_bar.sell_requested.connect(_sell_relic)
	add_child(relic_bar)

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
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(gap)
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
	relic_bar.position = Vector2(250, 16)

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
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	page.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	# 分页：买牌与器物 / 树的服务 / 删牌与精炼（一屏只放一类，不再是一条长列表）
	tabs = TabBar.new()
	tabs.add_tab("牌与器物")
	tabs.add_tab("树的服务")
	tabs.add_tab("删牌与精炼")
	tabs.add_theme_font_size_override("font_size", 20)
	tabs.tab_changed.connect(func(_i): _apply_tab())
	outer.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(right)
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
	shelf.custom_minimum_size = Vector2(0, OFFER_H + OFFER_DESC_H + 26)
	shelf.draw.connect(func():
		# 石台：牌立在一条带金边的石条上
		var y := OFFER_H + OFFER_DESC_H + 6.0
		shelf.draw_rect(Rect2(0, y, shelf.size.x, 14), Palette.CELL.darkened(0.06))
		shelf.draw_line(Vector2(0, y), Vector2(shelf.size.x, y), Palette.GOLD, 2.0)
		shelf.draw_rect(Rect2(0, y + 14, shelf.size.x, 5), Color(Palette.INK, 0.18)))
	right.add_child(shelf)
	offers = HFlowContainer.new()
	offers.add_theme_constant_override("h_separation", 14)
	offers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offers.offset_left = 4
	shelf.add_child(offers)
	right.add_child(_heading("器物（装备槽 %d 格，右键槽位可出售）" % Rules.RELIC_SLOTS))
	relic_offers = HFlowContainer.new()
	relic_offers.add_theme_constant_override("h_separation", 14)
	relic_offers.add_theme_constant_override("v_separation", 10)
	right.add_child(relic_offers)
	right.add_child(_heading("年轮、芽点与土地"))
	services = VBoxContainer.new()
	services.add_theme_constant_override("separation", 6)
	right.add_child(services)
	right.add_child(_heading("删牌（每张 %d 养分）" % run.service_price(Rules.REMOVE_CARD_PRICE)))
	deck_box = HFlowContainer.new()
	deck_box.add_theme_constant_override("h_separation", 8)
	deck_box.add_theme_constant_override("v_separation", 8)
	right.add_child(deck_box)
	right.add_child(_heading("精炼（每张 %d 养分，每张牌只能精炼一次）" % run.service_price(Rules.REFINE_PRICE)))
	refine_box = HFlowContainer.new()
	refine_box.add_theme_constant_override("h_separation", 8)
	refine_box.add_theme_constant_override("v_separation", 8)
	right.add_child(refine_box)
	var leave := Button.new()
	if run.is_calamity():
		leave.text = "离开集市，进入第%d年（牌桌外扩一圈）" % (run.year + 1)
	else:
		leave.text = "离开集市，进入%s季" % Rules.season_name(run.season + 1)
	leave.theme_type_variation = &"PrimaryButton"
	leave.add_theme_font_size_override("font_size", 24)
	leave.custom_minimum_size = Vector2(0, 58)
	leave.pressed.connect(_leave)
	outer.add_child(leave)

	# 按小标题把摊位分成三页
	var group := 0
	for ch in right.get_children():
		if ch is Label and (ch.text.begins_with("年轮") or ch.text.begins_with("删牌")):
			group = 1 if ch.text.begins_with("年轮") else 2
		_tab_nodes.append([ch, group])
	if run.free_buds() < Rules.LOW_BUDS:
		tabs.current_tab = 0
		tabs.set_tab_title(1, "树的服务（推荐：芽点）")
	_apply_tab()

	fly_layer = Control.new()
	fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fly_layer)
	_refresh()


func _apply_tab() -> void:
	for pair in _tab_nodes:
		if is_instance_valid(pair[0]):
			pair[0].visible = int(pair[1]) == tabs.current_tab


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
			Pick.PORT:
				var n := run.tree.at(c)
				if port_from == BoardView.NO_CELL and n != null and not n.is_seed() \
						and n.extra_ports.size() < Rules.MAX_EXTRA_PORTS and not Growth.free_port_dirs(n).is_empty():
					np[c] = true
	if pick == Pick.PORT and port_from != BoardView.NO_CELL:
		np[port_from] = true
		for d in Growth.free_port_dirs(run.tree.at(port_from)):
			var c: Vector2i = port_from + Hex.DIRS[d]
			if Hex.in_board(c, run.tree.radius):
				tg[c] = true
	board.node_pick = np
	board.set_state(run.tree, run.preview(), tg, false, {})

	for ch in offers.get_children():
		ch.queue_free()
	for i in run.market_cards.size():
		var id := run.market_cards[i]
		var cv := CardView.make(id)
		cv.draggable = false
		cv.desc_h = OFFER_DESC_H
		cv.custom_minimum_size = Vector2(OFFER_W, OFFER_H + OFFER_DESC_H)
		var price := run.card_price(id)
		cv.disabled = run.sap < price
		cv.note = "%d 养分" % price
		cv.pressed.connect(_buy.bind(i))
		offers.add_child(cv)
	if run.market_cards.is_empty():
		var l := Label.new()
		l.text = "已经买空了。"
		l.theme_type_variation = &"SoftLabel"
		offers.add_child(l)

	for ch in relic_offers.get_children():
		ch.queue_free()
	for i in run.market_relics.size():
		relic_offers.add_child(_relic_offer(i))
	if run.market_relics.is_empty():
		var l := Label.new()
		l.text = "没有器物了。"
		l.theme_type_variation = &"SoftLabel"
		relic_offers.add_child(l)

	for ch in services.get_children():
		ch.queue_free()
	for m in Rules.MARKS:
		var info: Dictionary = Rules.MARKS[m]
		var mp := run.service_price(int(info.price))
		_service("年轮「%s」（%d）：%s" % [info.name, mp, info.desc], run.sap >= mp,
			pick == Pick.MARK and pick_mark == m, _start_pick.bind(Pick.MARK, m))
	var low := run.free_buds() < Rules.LOW_BUDS
	var pb := _service(("★ 推荐（树上只剩 %d 个空芽点）· " % run.free_buds() if low else "") + "芽点（%d）：选一张牌，再选一个方向，给它多加一个芽点（每张最多 %d 个）" % [run.service_price(Rules.PORT_PRICE), Rules.MAX_EXTRA_PORTS],
		run.sap >= run.service_price(Rules.PORT_PRICE), pick == Pick.PORT, _start_pick.bind(Pick.PORT, &""))
	if low:
		services.move_child(pb, 0)
	_service("清除岩石（%d）：把一块岩石变回平地" % run.service_price(Rules.CLEAR_ROCK_PRICE), run.sap >= run.service_price(Rules.CLEAR_ROCK_PRICE),
		pick == Pick.CLEAR_ROCK, _start_pick.bind(Pick.CLEAR_ROCK, &""))
	_service("养成沃土（%d）：%s" % [run.service_price(Rules.MAKE_FERTILE_PRICE), Land.desc_of(Land.Type.FERTILE)], run.sap >= run.service_price(Rules.MAKE_FERTILE_PRICE),
		pick == Pick.FERTILE, _start_pick.bind(Pick.FERTILE, &""))

	for ch in deck_box.get_children():
		ch.queue_free()
	var counts := run.deck_counts()
	var ids := counts.keys()
	ids.sort()
	for ch in refine_box.get_children():
		ch.queue_free()
	for id in ids:
		if not Cards.get_def(id).is_plus():
			var plus := Cards.get_def(StringName(String(id) + "+"))
			var rb := Button.new()
			rb.text = "%s → %s" % [Cards.get_def(id).display_name, plus.display_name]
			rb.disabled = not run.can_refine(id)
			rb.tooltip_text = plus.desc
			rb.pressed.connect(_refine.bind(id))
			refine_box.add_child(rb)
		var b := Button.new()
		b.text = "%s ×%d" % [Cards.get_def(id).display_name, counts[id]]
		b.disabled = run.sap < run.service_price(Rules.REMOVE_CARD_PRICE)
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
		Pick.PORT:
			if port_from == BoardView.NO_CELL:
				hint.text = "芽点：先点一张树上的牌。"
			else:
				hint.text = "芽点：点%s周围点亮的一格，芽点就朝那个方向（再点这张牌换一张）。" % Cards.get_def(run.tree.at(port_from).type).display_name
		_ when run.market_discount < 1.0:
			hint.text = "流浪商人说到做到：这次集市的牌和器物半价。"
		_:
			hint.text = "神树带着现在的形状进入下一季。把鼠标移到格子上查看地块；滚轮缩放，右键拖动平移。"


## 器物摊位：一幅器物版画 + 名字、说明、价格。
func _relic_offer(i: int) -> Button:
	var rid := run.market_relics[i]
	var r := Cards.relic(rid)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(408, 104)
	btn.disabled = not run.can_buy_relic(i)
	btn.tooltip_text = "装备槽已满：先在下方右键出售一件" if run.relics_full() else ""
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = 6
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	var art := ArtView.new()
	var cut := StringName("relic_cut_" + String(rid))
	art.art_id = cut if CardArt.has(cut) else rid
	art.mode = 1
	art.custom_minimum_size = Vector2(80, 80)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var n := Label.new()
	n.text = "%s　%d 养分" % [r.display_name, run.relic_price(rid)]
	n.theme_type_variation = &"TitleLabel"
	n.add_theme_font_size_override("font_size", 20)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(n)
	var d := Label.new()
	d.text = r.desc
	d.theme_type_variation = &"SoftLabel"
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(d)
	btn.pressed.connect(_buy_relic.bind(i))
	return btn


func _buy_relic(i: int) -> void:
	if run.buy_relic(i):
		Game.sfx(&"place", 1.2)
		Game.save()
		_refresh()


func _sell_relic(i: int) -> void:
	if run.sell_relic(i):
		Game.sfx(&"prune", 1.1)
		Game.save()
		_refresh()


func _service(text: String, enabled: bool, active: bool, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled and not active
	b.theme_type_variation = &"ActiveButton" if active else &""
	b.pressed.connect(fn)
	services.add_child(b)
	return b


func _start_pick(mode: Pick, mark: StringName) -> void:
	port_from = BoardView.NO_CELL
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
		Pick.PORT:
			if port_from == BoardView.NO_CELL or c == port_from:
				var n := run.tree.at(c)
				if c == port_from:
					port_from = BoardView.NO_CELL
				elif n and not n.is_seed() and not Growth.free_port_dirs(n).is_empty() and n.extra_ports.size() < Rules.MAX_EXTRA_PORTS:
					port_from = c
				_refresh()
				return
			var d := Hex.dir_between(port_from, c)
			ok = d >= 0 and run.add_port(port_from, d)
			if ok:
				port_from = BoardView.NO_CELL
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


func _refine(id: StringName) -> void:
	if run.refine(id):
		Game.sfx(&"place", 1.3)
		Game.save()
		_refresh()


func _remove(id: StringName) -> void:
	if run.remove_card(id):
		Game.save()
		_refresh()


func _leave() -> void:
	run.leave_market()
	Game.notices.append_array(Game.profile.record_progress(run))
	Game.save()
	Game.goto(&"map")


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and pick != Pick.NONE:
		pick = Pick.NONE
		port_from = BoardView.NO_CELL
		_refresh()
		get_viewport().set_input_as_handled()
