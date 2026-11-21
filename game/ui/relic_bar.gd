class_name RelicBar
extends PanelContainer
## 装备槽：屏幕上方一排固定数量的器物槽（Rules.RELIC_SLOTS）。
## 有器物的槽显示图标与名字，悬停看说明；空槽是一圈虚线。
## sell_mode 为真时（集市里）右键或点击「卖」可以出售，发出 sell_requested(index)。

signal relic_pressed(id: StringName)
signal sell_requested(index: int)

const SLOT_W := 74.0
const SLOT_H := 92.0

var _ids: Array[StringName] = []
var _slots: Array[Control] = []
## 集市中：显示出售价格，右键出售。
var sell_mode: bool = false:
	set(v):
		sell_mode = v
		_rebuild()
## 出售价格查询（id -> int），由场景提供。
var sell_price: Callable


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.SHEET, 0.92)
	sb.border_color = Color(Palette.INK, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(Palette.INK, 0.25)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rebuild()


## 设置器物列表（StringName 数组）。
func set_relics(ids: Array) -> void:
	var want: Array[StringName] = []
	for i in ids:
		want.append(StringName(i))
	if want == _ids and not _slots.is_empty():
		return
	_ids = want
	_rebuild()


## 屏幕上某件器物槽的中心（全局坐标）；没有返回 (-1,-1)。
func slot_global_center(id: StringName) -> Vector2:
	var i := _ids.find(id)
	if i < 0 or i >= _slots.size():
		return Vector2(-1, -1)
	return _slots[i].global_position + _slots[i].size * 0.5


## 这些器物刚刚生效：依次跳起并闪金光。
func flash(ids: Array, delay: float = 0.0) -> void:
	if Game.reduce_motion:
		return
	var n := 0
	for i in _ids.size():
		if not ids.has(_ids[i]) or i >= _slots.size():
			continue
		var art: Control = _slots[i].get_meta("art")
		var tw := create_tween()
		tw.tween_interval(delay + n * 0.12)
		tw.tween_property(art, "position:y", art.position.y - 12.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(art, "modulate", Color(1.5, 1.3, 0.8), 0.16)
		tw.tween_property(art, "position:y", art.position.y, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(art, "modulate", Color.WHITE, 0.4)
		n += 1


func _rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	_slots.clear()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)
	var cap := Label.new()
	cap.text = "器物\n%d/%d" % [_ids.size(), Rules.RELIC_SLOTS]
	cap.theme_type_variation = &"SoftLabel"
	cap.add_theme_font_size_override("font_size", 13)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	for i in maxi(Rules.RELIC_SLOTS, _ids.size()):
		var slot := _make_slot(_ids[i] if i < _ids.size() else &"", i)
		row.add_child(slot)
		_slots.append(slot)


func _make_slot(rid: StringName, index: int) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.draw.connect(_draw_slot.bind(slot, rid))
	var art := ArtView.new()
	art.mode = 1
	art.position = Vector2(5, 2)
	art.size = Vector2(SLOT_W - 10, SLOT_H - 26)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(art)
	slot.set_meta("art", art)
	if rid == &"":
		slot.tooltip_text = "空槽：在集市购买器物，或在天灾季后选择器物"
		return slot
	var r := Cards.relic(rid)
	var cut := StringName("relic_cut_" + String(rid))
	art.art_id = cut if CardArt.has(cut) else rid
	var tip := "%s：%s" % [r.display_name, r.desc]
	if sell_mode and sell_price.is_valid():
		tip += "\n右键出售（+%d 养分）" % int(sell_price.call(rid))
	slot.tooltip_text = tip
	var n := Label.new()
	n.text = r.display_name
	n.theme_type_variation = &"PlaqueLabel"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", Palette.INK)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.position = Vector2(0, SLOT_H - 22)
	n.size = Vector2(SLOT_W, 20)
	slot.add_child(n)
	slot.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_RIGHT and sell_mode:
				sell_requested.emit(index)
			elif e.button_index == MOUSE_BUTTON_LEFT:
				relic_pressed.emit(rid))
	slot.mouse_entered.connect(slot.queue_redraw)
	slot.mouse_exited.connect(slot.queue_redraw)
	return slot


func _draw_slot(slot: Control, rid: StringName) -> void:
	var r := Rect2(Vector2(1, 1), slot.size - Vector2(2, 2))
	if rid == &"":
		# 空槽：虚线框
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
		for i in 4:
			slot.draw_dashed_line(pts[i], pts[i + 1], Color(Palette.SOFT, 0.55), 1.5, 5.0)
		return
	var hot := slot.get_global_rect().has_point(slot.get_global_mouse_position())
	slot.draw_rect(r, Color(Palette.CREAM, 0.9 if hot else 0.6))
	slot.draw_rect(r, Color(Palette.GOLD, 0.95 if hot else 0.6), false, 1.5)
	if sell_mode and hot:
		slot.draw_rect(r.grow(-3), Color(Palette.TERRA, 0.7), false, 1.0)
