class_name CardView
extends Button
## 一张手牌（或奖励牌）。自绘，支持点选和拖拽到棋盘。
##
## 版式（参考图那一套）：
##   上部  —— 一整幅印刷图版（占满卡片宽度，3:4 竖版）
##   下部  —— 石板色的题名带：牌名 + 分类铭牌 + 数值
## 卡片四周一道细双线框，像拓印出来的卡片。
##
## 整张卡按宽度等比缩放：手牌用小号，集市/图鉴/弹窗用大号。

signal drag_started(index: int)

## 紧凑版（图鉴列表用）：只画图版和牌名。
@export var compact: bool = false:
	set(v):
		compact = v
		queue_redraw()

var card_id: StringName
var index: int = -1
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
var note: String = "":
	set(v):
		note = v
		queue_redraw()
## 提示是不是「错误」提示（红字）还是普通说明（橄榄字）。
var note_alert: bool = false:
	set(v):
		note_alert = v
		queue_redraw()
var draggable: bool = true
## 牌背朝上（抽牌翻面动画的前半段）。
var show_back: bool = false:
	set(v):
		if v != show_back:
			show_back = v
			queue_redraw()
## 抬起的动画进度 0..1（由 fx 补间驱动）。
var lift: float = 0.0:
	set(v):
		lift = v
		queue_redraw()
## 落牌时的压印动画进度 0..1。
var stamp_t: float = 0.0:
	set(v):
		stamp_t = v
		queue_redraw()

## 伪 3D 倾斜（悬停跟随鼠标、静止时轻摆）。
var _tilt: Vector2 = Vector2.ZERO
var _tilt_clock: float = 0.0
static var _tilt_shader: Shader

## 卡片的基准尺寸；实际大小按宽度等比缩放。
const W := 200.0
const H := 340.0
const ART_ASPECT := 1.3333    # 图版高 / 宽（3:4 竖版）
const BAND_MIN := 62.0        # 题名带最小高度（会随卡宽缩放）


static func make(id: StringName, idx: int = -1) -> CardView:
	var c := CardView.new()
	c.card_id = id
	c.index = idx
	return c


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(W, H)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _ready() -> void:
	var def := Cards.get_def(card_id)
	if def:
		tooltip_text = "%s（%s）\n%s" % [def.display_name, def.tag_line(), def.desc]
	if not compact:
		_enable_tilt(def)


func _enable_tilt(def: CardDef) -> void:
	if _tilt_shader == null:
		_tilt_shader = load("res://ui/card_tilt.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _tilt_shader
	# 金色系的牌（金果、心材、嫁接藤）带鎏金反光
	var foil := def != null and (def.id == &"gold" or def.id == &"heartwood" or def.color_key == &"gold")
	m.set_shader_parameter("foil", 1.0 if foil else 0.0)
	m.set_shader_parameter("time_offset", randf() * 10.0)
	material = m
	_tilt_clock = randf() * 10.0
	set_process(true)


func _process(dt: float) -> void:
	var m := material as ShaderMaterial
	if m == null:
		return
	_tilt_clock += dt
	var target := Vector2.ZERO
	var sheen := 0.25
	if not Game.reduce_motion:
		if is_hovered() and not show_back:
			var rel := ((get_local_mouse_position() - size * 0.5) / (size * 0.5)).clamp(Vector2(-1, -1), Vector2(1, 1))
			target = Vector2(-rel.x * 0.30, -rel.y * 0.24)
			sheen = 1.0
		else:
			target = Vector2(sin(_tilt_clock * 1.1) * 0.05, cos(_tilt_clock * 0.83) * 0.04)
	_tilt = _tilt.lerp(target, 1.0 - exp(-dt * 10.0))
	m.set_shader_parameter("card_size", size)
	m.set_shader_parameter("tilt", _tilt)
	m.set_shader_parameter("sheen", sheen)


# ---------- 绘制 ----------

func _draw() -> void:
	var def := Cards.get_def(card_id)
	if def == null:
		return
	var accent := Palette.card_color(def.color_key)
	if show_back:
		CardBack.draw(self, Rect2(Vector2.ZERO, size))
		return
	if compact:
		_draw_compact(def, accent)
		return

	# 等比缩放系数
	var k: float = size.x / W
	# 图版尽量按 3:4 竖版填满宽度，题名带留够空间
	var art_h: float = minf(size.x * ART_ASPECT, size.y - BAND_MIN * k)
	var band: float = size.y - art_h

	var hover_t: float = 1.0 if is_hovered() and not disabled else 0.0
	var sel_t: float = 1.0 if selected else 0.0
	var up := maxf(hover_t * 0.5, sel_t)
	var lf := lift
	var y := -up * 6.0 * k - lf * 20.0 * k
	var tilt := deg_to_rad(-1.4 * sel_t - 1.8 * hover_t)
	var sx := 1.0
	var sy := 1.0
	if stamp_t > 0.0:
		var st := sin(stamp_t * PI)
		sx = 1.0 + 0.09 * st
		sy = 1.0 - 0.11 * st

	draw_set_transform(Vector2(size.x * 0.5, y), tilt, Vector2(sx, sy))
	var o := Vector2(-size.x * 0.5, -y)
	var r := Rect2(o, size)

	# 卡片底：奶油石板
	draw_rect(r, Palette.SHEET)

	# ---------- 上部：印刷图版 ----------
	var art_rect := Rect2(o.x, o.y, size.x, art_h)
	CardArt.draw_plate(self, def.art_id(), art_rect)
	# 图版与题名带之间的细金线
	draw_line(Vector2(o.x, art_rect.position.y + art_rect.size.y),
		Vector2(o.x + size.x, art_rect.position.y + art_rect.size.y), Palette.GOLD, maxf(1.0, 1.5 * k))

	# ---------- 下部：题名带 ----------
	var band_rect := Rect2(o.x, art_rect.position.y + art_rect.size.y, size.x, size.y - art_h)
	draw_rect(band_rect, Palette.SHEET)
	PrintStyle.halftone(self, band_rect.grow(-2.0 * k), Color(Palette.INK, 0.035), 6.0 * k, 1.0 * k, 45.0)

	var title := Palette.title_for(def.display_name)
	var name_fs := int(round(24.0 * k))
	var tsz := title.get_string_size(def.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs)
	var name_y := band_rect.position.y + 30.0 * k
	draw_string(title, Vector2(o.x + (size.x - tsz.x) * 0.5, name_y), def.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs, Palette.INK)
	# 牌名两侧的菱形饰纹
	var dia := maxf(2.5, 4.0 * k)
	for sgn: float in [-1.0, 1.0]:
		var dx := o.x + size.x * 0.5 + sgn * (tsz.x * 0.5 + 14.0 * k)
		var dy := name_y - 8.0 * k
		draw_colored_polygon(PackedVector2Array([
			Vector2(dx, dy - dia), Vector2(dx + dia, dy), Vector2(dx, dy + dia), Vector2(dx - dia, dy)]),
			Palette.GOLD)

	# 数值（右下，与牌名同一行）
	var vtext := _value_text(def)
	if vtext != "":
		var vf := Palette.numeric()
		var vfs := int(round(17.0 * k))
		var vsz := vf.get_string_size(vtext, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs)
		draw_string(vf, Vector2(o.x + size.x - 11.0 * k - vsz.x, name_y), vtext,
			HORIZONTAL_ALIGNMENT_LEFT, -1, vfs, accent)

	# 第二行：分类铭牌（或者「为什么不能出」的提示）
	var body := Palette.body()
	var sub_y := band_rect.position.y + 46.0 * k
	if disabled:
		# 不可用：在题名带上盖一枚小红牌，别去糊住插画
		var tag := "暂不可用"
		var tfs := int(round(12.0 * k))
		var tsz2 := body.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs)
		var plaque := Rect2(o.x + (size.x - tsz2.x - 16.0 * k) * 0.5, sub_y - 13.0 * k,
			tsz2.x + 16.0 * k, 18.0 * k)
		draw_rect(plaque, Color(Palette.TERRA, 0.16))
		draw_rect(plaque, Color(Palette.TERRA, 0.7), false, maxf(1.0, 1.0 * k))
		draw_string(body, plaque.position + Vector2(8.0 * k, 13.0 * k), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Palette.TERRA)
	elif note != "":
		var ncol := Palette.TERRA if note_alert else Palette.OLIVE
		draw_rect(Rect2(o.x, sub_y - 13.0 * k, size.x, 20.0 * k), Color(ncol, 0.12))
		draw_string(body, Vector2(o.x + 11.0 * k, sub_y), note,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 22.0 * k, int(round(12.0 * k)), ncol)
	else:
		# 新流派显示流派名（流派色）；木系显示类别
		var cat := def.category_name() if def.family.is_empty() else def.family_label()
		if not def.family.is_empty():
			accent = Palette.family_color(def.families()[0])
		var cat_fs := int(round(12.0 * k))
		var csz := body.get_string_size(cat, HORIZONTAL_ALIGNMENT_LEFT, -1, cat_fs)
		var plaque := Rect2(o.x + (size.x - csz.x - 16.0 * k) * 0.5, sub_y - 13.0 * k,
			csz.x + 16.0 * k, 18.0 * k)
		draw_rect(plaque, Color(accent, 0.16))
		draw_rect(plaque, Color(accent, 0.65), false, maxf(1.0, 1.0 * k))
		draw_string(body, plaque.position + Vector2(8.0 * k, 13.0 * k), cat,
			HORIZONTAL_ALIGNMENT_LEFT, -1, cat_fs, accent.darkened(0.15))
		# 芽点（左下角）
		var bx := o.x + 11.0 * k
		for i in def.ports.size():
			draw_circle(Vector2(bx + i * 11.0 * k, band_rect.position.y + band_rect.size.y - 11.0 * k),
				maxf(2.0, 3.4 * k), accent)
		if def.is_graft():
			draw_string(body, Vector2(o.x + 11.0 * k, band_rect.position.y + band_rect.size.y - 6.0 * k),
				"嫁接", HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(12.0 * k)), accent)
		# 稀有度（右下角）：稀有一枚、传说两枚金色菱形
		for i in def.rarity:
			var c := Vector2(o.x + size.x - (12.0 + i * 11.0) * k, band_rect.position.y + band_rect.size.y - 11.0 * k)
			var d := maxf(3.0, 4.2 * k)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]),
				Palette.GOLD if def.rarity >= 2 else Palette.STONE)

	# ---------- 边框与角饰 ----------
	_draw_frame(o, size, accent, up, k)

	# ---------- 左上角序号 ----------
	if index >= 0 and index < 9:
		_draw_index_badge(o, index + 1, accent, k)

	if disabled:
		# 整张卡退成一层淡影，题名带上的小红牌说明原因
		draw_rect(Rect2(o.x, art_rect.position.y, size.x, art_h), Color(Palette.PAPER, 0.42))
		draw_rect(r, Color(Palette.PAPER, 0.18))

	if has_focus():
		PrintStyle.dashed_rect(self, Rect2(o - Vector2(4, 4), size + Vector2(8, 8)), Palette.WATER, 2.0, 7.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 紧凑版（图鉴）：博物馆展签——衬纸里装一幅图版，下面一块展签写牌名和类别。
func _draw_compact(def: CardDef, accent: Color) -> void:
	var hov := is_hovered() and not disabled
	var up := 3.0 if (hov or selected) else 0.0
	var r := Rect2(Vector2(0, -up), size)
	# 投影：悬停时离墙更远
	draw_rect(Rect2(r.position + Vector2(3, 4 + up), r.size), Color(Palette.INK, 0.18 + up * 0.04))
	# 衬纸
	draw_rect(r, Palette.CREAM)
	draw_rect(r, Color(Palette.INK, 0.55), false, 1.0)
	# 图版 + 金色双线框
	var pad := 8.0
	var art_rect := Rect2(r.position + Vector2(pad, pad), Vector2(size.x - pad * 2, size.x - pad * 2))
	CardArt.draw_plate(self, def.art_id(), art_rect)
	draw_rect(art_rect.grow(2.0), Palette.GOLD, false, 1.2)
	draw_rect(art_rect.grow(4.0), Color(Palette.GOLD, 0.45), false, 1.0)
	# 展签
	var ly := art_rect.end.y + 8.0
	var title := Palette.title_for(def.display_name)
	draw_string(title, Vector2(r.position.x + pad, ly + 18), def.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2, 18, Palette.INK)
	draw_line(Vector2(r.position.x + pad, ly + 25), Vector2(r.position.x + pad + 26, ly + 25), Palette.GOLD, 1.2)
	draw_string(Palette.caption(), Vector2(r.position.x + pad, ly + 41), def.category_name(),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2, 12, accent.darkened(0.15))
	if selected:
		draw_rect(r.grow(2.0), accent, false, 2.5)
	if disabled:
		draw_rect(r, Color(Palette.PAPER, 0.5))


## 卡片外框：细双线，像拓印出来的。
func _draw_frame(o: Vector2, sz: Vector2, accent: Color, up: float, k: float) -> void:
	var r := Rect2(o, sz)
	draw_rect(r, Palette.INK, false, maxf(1.0, 1.6 * k))
	draw_rect(r.grow(-4.0 * k), Color(accent, 0.55 - up * 0.25), false, maxf(1.0, k))
	# 四角的角饰
	var L := 7.0 * k
	var inset := 8.0 * k
	var pts := [
		[Vector2(o.x + inset, o.y + inset), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(o.x + sz.x - inset, o.y + inset), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(o.x + inset, o.y + sz.y - inset), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(o.x + sz.x - inset, o.y + sz.y - inset), Vector2(-1, 0), Vector2(0, -1)],
	]
	for p in pts:
		var q: Vector2 = p[0]
		var d1: Vector2 = p[1]
		var d2: Vector2 = p[2]
		draw_line(q, q + d1 * L, Color(accent, 0.75), maxf(1.0, 1.2 * k), true)
		draw_line(q, q + d2 * L, Color(accent, 0.75), maxf(1.0, 1.2 * k), true)


## 牌面底部显示的主要效果值。
func _value_text(def: CardDef) -> String:
	match def.effect:
		CardDef.Effect.ADD:
			return "+%s" % Pulse.num(def.value)
		CardDef.Effect.ADD_DEPTH:
			return "+深度"
		CardDef.Effect.MUL:
			return "×%s" % Pulse.num(def.value)
		CardDef.Effect.SUB_CLAMP:
			return "−%s" % Pulse.num(def.value)
		CardDef.Effect.GRAFT:
			if def.graft_sum:
				return "和×%s" % Pulse.num(def.value)
			return "×%s" % Pulse.num(def.value) if def.value != 0.0 else "嫁接"
	return ""


## 左上角的序号徽章（对应键盘 1-9）。
func _draw_index_badge(o: Vector2, n: int, accent: Color, k: float) -> void:
	var c := o + Vector2(18.0 * k, 16.0 * k)
	draw_circle(c, 11.0 * k, Palette.INK)
	draw_circle(c, 11.0 * k, Color(accent, 0.9), false, maxf(1.0, 1.5 * k))
	var s := str(n)
	var fs := Palette.numeric()
	var fs_size := int(round(13.0 * k))
	var sz := fs.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_size)
	draw_string(fs, c - Vector2(sz.x * 0.5, -4.5 * k), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_size, Palette.SHEET)


func _get_drag_data(_at: Vector2) -> Variant:
	if disabled or not draggable:
		return null
	var holder := Control.new()
	var p := CardView.make(card_id)
	p.draggable = false
	p.selected = true
	p.modulate = Color(1, 1, 1, 0.9)
	p.size = size
	p.position = -size * 0.5
	holder.add_child(p)
	set_drag_preview(holder)
	drag_started.emit(index)
	return {"hand_index": index, "type": String(card_id)}
