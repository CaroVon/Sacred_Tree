extends Control
## 局间事件：背景是神树现在的样子，中间一页展签写着事件与选项。
## 选完后同一页换成结果，再点「前往集市」。

var run: RunState
var page_col: VBoxContainer
var opts_box: VBoxContainer
var title_l: Label
var text_l: Label
var art: ArtView

const PAGE_W := 860.0


func _ready() -> void:
	run = Game.run
	if run == null or run.phase != RunState.Phase.EVENT:
		Game.goto(&"market" if run and run.phase == RunState.Phase.MARKET else &"map")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var board := Board3D.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.margins = Vector4(60, 60, 60, 60)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.show_buds = false
	board.ctx = run.ctx()
	add_child(board)
	board.set_state(run.tree, run.preview(), {}, false, {})
	board.set_mood(run.season, &"")
	var veil := ColorRect.new()
	veil.color = Color(Palette.INK, 0.35)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var rb := RelicBar.new()
	rb.position = Vector2(40, 24)
	add_child(rb)
	rb.set_relics(run.relics)

	var page := PrintBox.new()
	page.padding = 34
	page.inner_border = true
	page.shadow_offset = Vector2(8, 10)
	page.shadow_color = Color(Palette.INK, 0.5)
	page.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	page.grow_horizontal = Control.GROW_DIRECTION_BOTH
	page.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(page)
	page_col = VBoxContainer.new()
	page_col.add_theme_constant_override("separation", 14)
	page_col.custom_minimum_size = Vector2(PAGE_W, 0)
	page.add_child(page_col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	page_col.add_child(head)
	art = ArtView.new()
	art.mode = 1
	art.custom_minimum_size = Vector2(150, 150)
	head.add_child(art)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.add_theme_constant_override("separation", 8)
	head.add_child(tcol)
	var kicker := Label.new()
	kicker.text = "%s · 途中" % run.season_label()
	kicker.theme_type_variation = &"PlaqueLabel"
	kicker.add_theme_color_override("font_color", Palette.GOLD.darkened(0.2))
	tcol.add_child(kicker)
	title_l = Label.new()
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_font_size_override("font_size", 40)
	tcol.add_child(title_l)
	text_l = Label.new()
	text_l.theme_type_variation = &"SoftLabel"
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.add_theme_font_size_override("font_size", 19)
	text_l.custom_minimum_size = Vector2(PAGE_W - 180, 0)
	tcol.add_child(text_l)

	opts_box = VBoxContainer.new()
	opts_box.add_theme_constant_override("separation", 10)
	page_col.add_child(opts_box)
	var sap_l := Label.new()
	sap_l.name = "Sap"
	sap_l.theme_type_variation = &"SoftLabel"
	page_col.add_child(sap_l)
	_show_event()
	if not Game.reduce_motion:
		page.modulate.a = 0.0
		page.create_tween().tween_property(page, "modulate:a", 1.0, 0.3)


func _show_event() -> void:
	var info: Dictionary = RunEvents.LIST[run.event_id]
	title_l.text = info.title
	text_l.text = info.text
	var aid: StringName = info.get("art", &"tree")
	var cut := StringName("relic_cut_" + String(aid))
	art.art_id = cut if CardArt.has(cut) else aid
	(page_col.get_node("Sap") as Label).text = "养分 %d · 器物 %d/%d" % [run.sap, run.relics.size(), Rules.RELIC_SLOTS]
	for ch in opts_box.get_children():
		ch.queue_free()
	var first: Button = null
	for i in info.options.size():
		var o: Dictionary = info.options[i]
		var b := Button.new()
		var why := RunEvents.blocked(run, run.event_id, i)
		b.text = o.label + ("　（%s）" % why if why != "" else "")
		b.disabled = why != ""
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 21)
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(_choose.bind(i))
		opts_box.add_child(b)
		if first == null and not b.disabled:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _choose(i: int) -> void:
	if not run.choose_event(i):
		return
	Game.sfx(&"place", 1.1)
	Game.save()
	for ch in opts_box.get_children():
		ch.queue_free()
	for line in run.event_result:
		var l := Label.new()
		l.text = "· " + line
		l.add_theme_font_size_override("font_size", 21)
		l.add_theme_color_override("font_color", Palette.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		opts_box.add_child(l)
	(page_col.get_node("Sap") as Label).text = "养分 %d · 器物 %d/%d" % [run.sap, run.relics.size(), Rules.RELIC_SLOTS]
	var go := Button.new()
	go.text = "前往集市"
	go.theme_type_variation = &"PrimaryButton"
	go.add_theme_font_size_override("font_size", 24)
	go.custom_minimum_size = Vector2(0, 56)
	go.pressed.connect(func(): Game.goto(&"market"))
	opts_box.add_child(go)
	go.grab_focus.call_deferred()
