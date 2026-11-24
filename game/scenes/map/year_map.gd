extends Control
## 年度地图：整屏的 3D 牌桌上是神树现在的样子（器物在上方装备槽），
## 右边一页纸写着这一年的年轮路径、本年天灾、牌组，从这里进入下一季。

var run: RunState

const PANEL_W := 760.0


func _ready() -> void:
	run = Game.run
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var board := Board3D.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.margins = Vector4(90, 70, PANEL_W + 90, 70)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.show_buds = false
	board.ctx = run.ctx()
	add_child(board)
	board.set_state(run.tree, run.preview(), {}, false, {})
	board.set_mood(run.season, run.calamity)
	Game.scene_audio(&"map", run.season)
	board.margins = Vector4(90, 150, PANEL_W + 90, 70)
	var rb := RelicBar.new()
	rb.position = Vector2(60, 24)
	add_child(rb)
	rb.set_relics(run.relics)

	# ---------- 右页 ----------
	var page := PrintBox.new()
	page.padding = 30
	page.shadow_offset = Vector2(8, 10)
	page.shadow_color = Color(Palette.INK, 0.45)
	page.inner_border = true
	page.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	page.offset_left = -PANEL_W - 36
	page.offset_right = -36
	page.offset_top = 36
	page.offset_bottom = -36
	add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	page.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "第%d年" % run.year
	title.theme_type_variation = &"DisplayLabel"
	title.add_theme_font_size_override("font_size", 60)
	head.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var now := Label.new()
	now.text = run.season_label()
	now.theme_type_variation = &"SubtitleLabel"
	now.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(now)

	var path := SeasonPath.new()
	path.year = run.year
	path.season = run.season
	col.add_child(path)

	# 本年天灾：一枚小图版 + 说明
	var cd := Cards.calamity(run.calamity)
	var cal := PrintBox.new()
	cal.padding = 12
	cal.shadow_offset = Vector2.ZERO
	cal.border = 1.0
	cal.border_color = Color(Palette.TERRA, 0.7)
	cal.bg = Palette.TERRA.lerp(Palette.SHEET, 0.88)
	col.add_child(cal)
	var cal_row := HBoxContainer.new()
	cal_row.add_theme_constant_override("separation", 14)
	cal.add_child(cal_row)
	var cal_art := ArtView.new()
	cal_art.art_id = cd.id
	cal_art.mode = 1
	cal_art.custom_minimum_size = Vector2(72, 72)
	cal_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cal_row.add_child(cal_art)
	var cal_col := VBoxContainer.new()
	cal_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cal_row.add_child(cal_col)
	var cal_t := Label.new()
	cal_t.text = "本年天灾 · " + cd.display_name
	cal_t.theme_type_variation = &"SubtitleLabel"
	cal_t.add_theme_color_override("font_color", Palette.TERRA)
	cal_col.add_child(cal_t)
	var cal_d := Label.new()
	cal_d.text = cd.desc
	cal_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cal_col.add_child(cal_d)

	var trait_l := Label.new()
	trait_l.text = ("%s · 天灾：%s" if run.is_calamity() else "%s · 季节特性：%s") % [run.season_label(), cd.desc if run.is_calamity() else Rules.season_trait(run.season)]
	trait_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(trait_l)

	var info := Label.new()
	info.theme_type_variation = &"SoftLabel"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rel := "无" if run.relics.is_empty() else "、".join(run.relics.map(func(r): return "%s（%s）" % [Cards.relic(r).display_name, Cards.relic(r).desc]))
	var counts := run.deck_counts()
	var deck_parts: Array[String] = []
	var ids := counts.keys()
	ids.sort()
	for id in ids:
		deck_parts.append("%s×%d" % [Cards.get_def(id).display_name, counts[id]])
	var on_tree := run.tree.size() - 1
	info.text = "养分储备 %d\n器物：%s\n牌组 %d 张（树上 %d 张，手里和牌堆 %d 张）：%s\n\n地块：%s" % [run.sap, rel,
		on_tree + run.deck.size() + run.discard.size() + run.hand.size(), on_tree, run.deck.size() + run.discard.size() + run.hand.size(),
		"  ".join(deck_parts), Land.legend()]
	if not Game.notices.is_empty():
		info.text = "★ " + "\n★ ".join(Game.notices) + "\n\n" + info.text
		Game.notices.clear()
	col.add_child(info)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var go := Button.new()
	go.text = "开始%s（目标 %s）" % [run.season_label(), Pulse.big(run.target())]
	go.theme_type_variation = &"PrimaryButton"
	go.add_theme_font_size_override("font_size", 26)
	go.custom_minimum_size = Vector2(0, 62)
	go.pressed.connect(func(): Game.goto(&"season"))
	col.add_child(go)
	go.grab_focus.call_deferred()
	var back := Button.new()
	back.text = "主菜单"
	back.pressed.connect(func(): Game.goto(&"menu"))
	col.add_child(back)

	if not Game.reduce_motion:
		page.modulate.a = 0.0
		page.offset_left += 60
		page.offset_right += 60
		var tw := create_tween().set_parallel(true)
		tw.tween_property(page, "modulate:a", 1.0, 0.35)
		tw.tween_property(page, "offset_left", page.offset_left - 60, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(page, "offset_right", page.offset_right - 60, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
