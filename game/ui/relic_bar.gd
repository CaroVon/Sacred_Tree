class_name RelicBar
extends PanelContainer
## 器物栏：横排一列器物，每件是一枚图版图标 + 名字。
## 没有器物时显示一句提示。

signal relic_pressed(id: StringName)

var _ids: Array[StringName] = []


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.SHEET
	sb.border_color = Palette.INK
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_rebuild()


## 设置器物列表（StringName 数组）。
func set_relics(ids: Array) -> void:
	_ids.clear()
	for i in ids:
		_ids.append(StringName(i))
	_rebuild()


func _rebuild() -> void:
	for ch in get_children():
		ch.queue_free()
	if _ids.is_empty():
		var l := Label.new()
		l.text = "器物：无"
		l.theme_type_variation = &"SoftLabel"
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)
	for rid in _ids:
		row.add_child(_make_item(rid))


func _make_item(rid: StringName) -> Control:
	var r := Cards.relic(rid)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(66, 0)
	col.tooltip_text = "%s：%s" % [r.display_name, r.desc]
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var art := ArtView.new()
	art.art_id = StringName("relic_cut_" + String(rid)) if CardArt.has(StringName("relic_cut_" + String(rid))) else rid
	art.mode = 1
	art.custom_minimum_size = Vector2(64, 66)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(art)
	var n := Label.new()
	n.text = r.display_name
	n.theme_type_variation = &"PlaqueLabel"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", Palette.INK)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(n)
	return col
