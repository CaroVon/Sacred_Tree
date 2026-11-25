class_name CoachMark
extends Control
## 新手指导的画面引导：压暗全屏、在目标处开洞并加光圈，一只弹跳的箭头指过去，旁边一张气泡卡写「做什么 + 为什么」。
## 目标由 targets_fn 每帧给出（全局矩形数组），牌桌平移缩放、手牌动画时自动跟随。
## 本层不拦截点击（只有气泡卡里的按钮可点），规则限制由 Tutorial 负责。

signal continue_pressed
signal skip_pressed

const CARD_W := 400.0
const ARROW_LEN := 64.0
const GAP := 14.0

## () -> Array[Rect2]：当前要聚光的目标；返回空数组时只显示气泡卡（居中靠上）。
var targets_fn: Callable = func() -> Array: return []
## () -> bool：返回 true 时整层隐藏（脉动演出、弹窗期间）。
var hold_fn: Callable = func() -> bool: return false

var _dim: ColorRect
var _mat: ShaderMaterial
var _arrow: Control
var _card: PrintBox
var _step_lbl: Label
var _action: RichTextLabel
var _why: RichTextLabel
var _term: RichTextLabel
var _term_text: String = ""
var _btn: Button
var _rects: Array = []
var _arrow_from := Vector2.ZERO
var _arrow_to := Vector2.ZERO
var _t := 0.0
var _shown := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/coach_mark.gdshader")
	_dim.material = _mat
	add_child(_dim)
	_arrow = Control.new()
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_build_card()
	modulate.a = 0.0
	visible = false


func _build_card() -> void:
	_card = PrintBox.new()
	_card.bg = Palette.CREAM
	_card.shadow_color = Palette.OCHRE
	_card.shadow_offset = Vector2(6, 6)
	_card.padding = 18
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(CARD_W - 36, 0)
	_card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_step_lbl = Label.new()
	_step_lbl.theme_type_variation = &"SoftLabel"
	_step_lbl.add_theme_font_size_override("font_size", 15)
	_step_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_step_lbl)
	var skip := Button.new()
	skip.text = "跳过指导"
	skip.flat = true
	skip.add_theme_font_size_override("font_size", 14)
	skip.add_theme_color_override("font_color", Palette.SOFT)
	skip.pressed.connect(func(): skip_pressed.emit())
	top.add_child(skip)
	_action = _rich(27, Palette.INK)
	_action.add_theme_font_override("normal_font", Palette.title())
	v.add_child(_action)
	_why = _rich(18, Palette.INK.lightened(0.15))
	v.add_child(_why)
	_term = _rich(16, Palette.OLIVE.darkened(0.25))
	v.add_child(_term)
	_btn = Button.new()
	_btn.text = "继续　[空格]"
	_btn.theme_type_variation = &"PrimaryButton"
	_btn.pressed.connect(func(): continue_pressed.emit())
	v.add_child(_btn)


func _rich(fs: int, col: Color) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_color_override("default_color", col)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.meta_underlined = false
	r.meta_hover_started.connect(_on_term_hover)
	r.meta_hover_ended.connect(func(_m): _term.text = _term_text; _term.visible = _term_text != "")
	r.meta_clicked.connect(_on_term_hover)
	return r


## 名词标记：「{芽点}」→ 金色下划线、可悬停的词。
static func markup(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var a := s.find("{", i)
		if a < 0:
			out += s.substr(i)
			break
		var b := s.find("}", a)
		if b < 0:
			out += s.substr(i)
			break
		var w := s.substr(a + 1, b - a - 1)
		out += s.substr(i, a - i) + "[url=%s][u][color=#9A6F2A]%s[/color][/u][/url]" % [w, w]
		i = b + 1
	return out


## 去掉名词标记的纯文本（顶部提示栏用）。
static func plain(s: String) -> String:
	return s.replace("{", "").replace("}", "")


func _on_term_hover(meta) -> void:
	var w := String(meta)
	if Glossary.SHORT.has(w):
		_term.text = "[b]%s[/b]：%s" % [w, Glossary.SHORT[w]]
		_term.visible = true


## 显示一拍。terms：本拍第一次出现的名词（底部「新词」行）。
func show_beat(step_text: String, action: String, why: String, terms: Array, can_continue: bool) -> void:
	_step_lbl.text = step_text
	_action.text = markup(action)
	# 标题字体把个别字画成方块（如「回」），碰到时换正文字体
	_action.add_theme_font_override("normal_font", Palette.title_for(action))
	_why.text = markup(why)
	_why.visible = why != ""
	var lines: Array[String] = []
	for w in terms:
		if Glossary.SHORT.has(w):
			lines.append("[b]新词 · %s[/b]　%s" % [w, Glossary.SHORT[w]])
	_term_text = "\n".join(lines)
	_term.text = _term_text
	_term.visible = _term_text != ""
	_btn.visible = can_continue
	_card.reset_size()
	_shown = true
	if not visible:
		visible = true
	_t = 0.0
	if Game.reduce_motion:
		modulate.a = 1.0
	_update_layout()


func hide_beat() -> void:
	_shown = false


func has_continue() -> bool:
	return _shown and _btn.visible and visible and modulate.a > 0.5


func continue_button() -> Button:
	return _btn


## 当前聚光矩形（测试用）。
func current_rects() -> Array:
	return _rects


func _process(delta: float) -> void:
	_t += delta
	var want: bool = _shown and not hold_fn.call()
	var a := 1.0 if want else 0.0
	modulate.a = a if Game.reduce_motion else move_toward(modulate.a, a, delta * 5.0)
	visible = modulate.a > 0.01
	_card.mouse_filter = Control.MOUSE_FILTER_STOP if want else Control.MOUSE_FILTER_IGNORE
	if visible:
		_update_layout()


func _update_layout() -> void:
	var vp := size
	var rects: Array = targets_fn.call() if targets_fn.is_valid() else []
	# 超过 4 个洞：合成一个包围框
	if rects.size() > 4:
		var u: Rect2 = rects[0]
		for r in rects:
			u = u.merge(r)
		rects = [u]
	_rects = rects
	var packed: Array[Vector4] = []
	for i in 4:
		if i < rects.size():
			var r: Rect2 = rects[i].grow(8)
			packed.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		else:
			packed.append(Vector4.ZERO)
	_mat.set_shader_parameter("canvas_size", vp)
	_mat.set_shader_parameter("holes", packed)
	_mat.set_shader_parameter("hole_count", mini(rects.size(), 4))
	_mat.set_shader_parameter("pulse", 0.0 if Game.reduce_motion else 1.0)
	var cs := _card.get_combined_minimum_size()
	cs.x = maxf(cs.x, CARD_W)
	_card.size = cs
	if rects.is_empty():
		_card.position = Vector2((vp.x - cs.x) * 0.5, vp.y * 0.16)
		_arrow_from = Vector2.ZERO
		_arrow_to = Vector2.ZERO
		_arrow.queue_redraw()
		return
	var u: Rect2 = rects[0]
	for r in rects:
		u = u.merge(r)
	u = u.grow(10)
	var c := u.get_center()
	# 箭头方向：目标靠右 → 从左边指；靠左 → 从右边指；否则从上方（目标太靠上就从下方）
	# 0：从左边指向右；1：从右边指向左；2：从上方指下；3：从下方指上
	var side := 2
	if c.x > vp.x * 0.74:
		side = 0
	elif c.x < vp.x * 0.22:
		side = 1
	elif u.position.y <= cs.y + ARROW_LEN + 60.0:
		side = 3
	var dir: Vector2 = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP][side]
	var tip: Vector2 = [Vector2(u.position.x, c.y), Vector2(u.end.x, c.y), Vector2(c.x, u.position.y), Vector2(c.x, u.end.y)][side]
	var bob := 0.0 if Game.reduce_motion else sin(_t * 5.0) * 7.0
	_arrow_to = tip - dir * (4.0 + bob)
	_arrow_from = _arrow_to - dir * ARROW_LEN
	var tail := _arrow_from - dir * GAP
	var pos: Vector2 = [Vector2(tail.x - cs.x, tail.y - cs.y * 0.5), Vector2(tail.x, tail.y - cs.y * 0.5),
		Vector2(tail.x - cs.x * 0.5, tail.y - cs.y), Vector2(tail.x - cs.x * 0.5, tail.y)][side]
	pos.x = clampf(pos.x, 16.0, vp.x - cs.x - 16.0)
	pos.y = clampf(pos.y, 16.0, vp.y - cs.y - 16.0)
	_card.position = pos
	_arrow.queue_redraw()


func _draw_arrow() -> void:
	if _arrow_from == _arrow_to:
		return
	var d := (_arrow_to - _arrow_from).normalized()
	var n := Vector2(-d.y, d.x)
	var head := 22.0
	var base := _arrow_to - d * head
	var shaft_w := 9.0
	var pts := PackedVector2Array([
		_arrow_from + n * shaft_w * 0.5, base + n * shaft_w * 0.5, base + n * head * 0.75,
		_arrow_to, base - n * head * 0.75, base - n * shaft_w * 0.5, _arrow_from - n * shaft_w * 0.5])
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(4, 4))
	_arrow.draw_colored_polygon(sh, Color(Palette.INK, 0.5))
	_arrow.draw_colored_polygon(pts, Color("#F2CF7A"))
	pts.append(pts[0])
	_arrow.draw_polyline(pts, Palette.INK, 2.5, true)
