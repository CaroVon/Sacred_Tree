class_name Palette
extends RefCounted
## 配色与字体。方向是「失落文明的古典典藏图册」：
## 奶油白纸、赭金、焦橙、土红、橄榄绿、炭灰——地中海古典文明的哑光旧色。

# ---- 纸与墨 ----
const PAPER := Color("#E4DCC4")     # 背景纸
const SHEET := Color("#EDE3C9")     # 卡片纸
const CREAM := Color("#F2EBD8")     # 更亮的纸面
const INK := Color("#2B2925")       # 炭灰代替纯黑
const SOFT := Color("#6E6A5C")
const RULE := Color("#C4B99A")
const CELL := Color("#D9D0B6")

# ---- 套色（与生成的插画同一套色）----
const OLIVE := Color("#7B7A55")
const SAGE := Color("#A9A98C")
const OCHRE := Color("#C9914A")
const GOLD := Color("#B08A46")
const TERRA := Color("#B04A2A")
const STONE := Color("#8A8578")
const WATER := Color("#6C8794")
## 新流派的主题色。
const STEEL := Color("#5E7381")    # 齿轮：钢蓝
const EMBER := Color("#B4552F")    # 熔炉：赭红
const ASTRAL := Color("#4D5683")   # 星辰：靛蓝
const COIN := Color("#A6812F")     # 商会：金赭
const MIRROR := Color("#7D8C99")   # 镜像：银灰
const SEAL := Color("#7A4F6E")     # 封印：紫红

## 分类色键：green / blue / red / gold / pink / grey。
const TITLE_FONT_PATH := "res://assets/fonts/ZCOOLXiaoWei-Regular.ttf"
const BODY_FONT_PATH := "res://assets/fonts/NotoSerifSC-Subset.ttf"

static var _title: Font
static var _body: Font
static var _numeric: Font
static var _caption: Font

## ZCOOL XiaoWei 把「回」画成了一块实心方块。碰到这些字就换用正文字体。
## 用 game/tools/fonts/check_glyphs.py 可以重新体检标题字体。
const BAD_TITLE_GLYPHS := ["回"]


## 按文本挑字体：标题字体里有坏字形时退回正文字体。
static func title_for(text: String) -> Font:
	for c in BAD_TITLE_GLYPHS:
		if text.contains(c):
			return body()
	return title()


static func card_color(key: StringName) -> Color:
	match key:
		&"green": return OLIVE
		&"blue": return WATER
		&"red": return TERRA
		&"gold": return GOLD
		&"pink": return OCHRE
		&"grey": return STONE
		&"steel": return STEEL
		&"ember": return EMBER
		&"astral": return ASTRAL
		&"coin": return COIN
		&"mirror": return MIRROR
		&"seal": return SEAL
	return INK


## 流派主题色（木用橄榄绿）。
static func family_color(f: StringName) -> Color:
	match f:
		&"gear": return STEEL
		&"forge": return EMBER
		&"star": return ASTRAL
		&"coin": return COIN
		&"mirror": return MIRROR
		&"seal": return SEAL
	return OLIVE


## 器物 / 天灾 / 分类的强调色。
static func accent_color(key: StringName) -> Color:
	match key:
		&"green": return OLIVE
		&"blue": return WATER
		&"red": return TERRA
		&"gold": return GOLD
		&"pink": return OCHRE
		&"grey": return STONE
	return INK


static func _load_font(path: String) -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font(path) == OK:
		return f
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Font:
			return r
	return null


## 标题字：ZCOOL 小薇（手写体贴纸字）。
static func title() -> Font:
	if _title == null:
		var ff := _load_font(TITLE_FONT_PATH)
		if ff != null:
			ff.fallbacks = [body()]
			_title = ff
		else:
			_title = body()
	return _title


## 正文字：思源宋体子集。
static func body() -> Font:
	if _body == null:
		var ff := _load_font(BODY_FONT_PATH)
		if ff == null:
			ff = _system_font()
		else:
			ff.fallbacks = [_system_font()]
		_body = ff
	return _body


## 小字：宋体但更紧凑，用于标签与注释。
static func caption() -> Font:
	if _caption == null:
		var v := FontVariation.new()
		v.base_font = body()
		v.spacing_glyph = 1
		_caption = v
	return _caption


## 数字：宋体 + 字距，印刷品里的大数字感觉。
static func numeric() -> Font:
	if _numeric == null:
		var v := FontVariation.new()
		v.base_font = body()
		v.spacing_glyph = 2
		_numeric = v
	return _numeric


static func _system_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans SC", "Noto Sans CJK SC", "sans-serif"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


static func _box(bg: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s


## 印刷标签样式：纸色底 + 墨线边 + 一块错位的彩色套印阴影。
static func _label(bg: Color, border: Color, plate: Color, bw: int = 2, off: float = 3.0) -> StyleBoxFlat:
	var s := _box(bg, border, bw)
	s.shadow_size = int(off) + 2
	s.shadow_color = Color(plate, 0.42)
	s.shadow_offset = Vector2(off, off)
	return s


## 石刻铭牌样式：圆角 3、墨线（或金线）边、一块硬投影。
static func _plaque(bg: Color, border: Color, bw: int, shadow: Vector2) -> StyleBoxFlat:
	var st := _box(bg, border, bw)
	st.set_corner_radius_all(3)
	if shadow != Vector2.ZERO:
		st.shadow_color = Color(INK, 0.35)
		st.shadow_size = 1
		st.shadow_offset = shadow
	return st


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = 19
	t.set_color("font_color", "Label", INK)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		t.set_color(state, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.35))
	# 石刻铭牌：纸色底 + 墨线边 + 落在桌面上的投影；悬停时换金边、抬高；按下时压低
	t.set_stylebox("normal", "Button", _plaque(SHEET, INK, 1, Vector2(3, 4)))
	t.set_stylebox("hover", "Button", _plaque(CREAM, GOLD, 2, Vector2(4, 6)))
	t.set_stylebox("pressed", "Button", _plaque(CELL, GOLD.darkened(0.2), 2, Vector2(1, 1)))
	t.set_stylebox("disabled", "Button", _plaque(Color(SHEET, 0.55), Color(INK, 0.22), 1, Vector2.ZERO))
	var focus := _box(Color(0, 0, 0, 0), GOLD)
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(3)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_hover_color", "Button", INK)
	# 主按钮：墨色石板 + 金边
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _plaque(INK, GOLD, 2, Vector2(3, 4)))
	t.set_stylebox("hover", "PrimaryButton", _plaque(INK.lightened(0.12), GOLD.lightened(0.25), 2, Vector2(4, 7)))
	t.set_stylebox("pressed", "PrimaryButton", _plaque(INK.lightened(0.2), GOLD, 2, Vector2(1, 1)))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		t.set_color(state, "PrimaryButton", CREAM)
	# 切换中的按钮（修剪模式、正在选的服务）
	t.set_type_variation("ActiveButton", "Button")
	t.set_stylebox("normal", "ActiveButton", _plaque(TERRA, INK, 2, Vector2(3, 4)))
	t.set_stylebox("hover", "ActiveButton", _plaque(TERRA.lightened(0.12), GOLD, 2, Vector2(4, 6)))
	t.set_stylebox("pressed", "ActiveButton", _plaque(TERRA.lightened(0.2), GOLD, 2, Vector2(1, 1)))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		t.set_color(state, "ActiveButton", Color(SHEET))
	# 悬停提示：一张小纸片
	var tip := _plaque(Color(SHEET, 0.98), INK, 1, Vector2(3, 4))
	tip.content_margin_left = 12
	tip.content_margin_right = 12
	tip.content_margin_top = 8
	tip.content_margin_bottom = 8
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font("font", "TooltipLabel", body())
	t.set_font_size("font_size", "TooltipLabel", 16)
	# 滚动条：细金线
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(GOLD, 0.7)
	grab.set_corner_radius_all(3)
	grab.content_margin_left = 4
	grab.content_margin_right = 4
	var track := StyleBoxFlat.new()
	track.bg_color = Color(RULE, 0.35)
	track.set_corner_radius_all(3)
	track.content_margin_left = 4
	track.content_margin_right = 4
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", track)

	# ---------- 排版层级 ----------
	# 标题标签（牌名、章节标题）
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title())
	t.set_font_size("font_size", "TitleLabel", 30)
	# 大标题（主菜单、弹窗）
	t.set_type_variation("DisplayLabel", "Label")
	t.set_font("font", "DisplayLabel", title())
	t.set_font_size("font_size", "DisplayLabel", 64)
	# 小节标题
	t.set_type_variation("SubtitleLabel", "Label")
	t.set_font("font", "SubtitleLabel", title())
	t.set_font_size("font_size", "SubtitleLabel", 24)
	# 正文
	t.set_type_variation("BodyLabel", "Label")
	t.set_font("font", "BodyLabel", body())
	t.set_font_size("font_size", "BodyLabel", 19)
	# 弱化文字
	t.set_type_variation("SoftLabel", "Label")
	t.set_font("font", "SoftLabel", caption())
	t.set_color("font_color", "SoftLabel", SOFT)
	t.set_font_size("font_size", "SoftLabel", 16)
	# 数字
	t.set_type_variation("NumericLabel", "Label")
	t.set_font("font", "NumericLabel", numeric())
	t.set_font_size("font_size", "NumericLabel", 26)
	# 刻在石板上的小标题（铭牌风格）
	t.set_type_variation("PlaqueLabel", "Label")
	t.set_font("font", "PlaqueLabel", caption())
	t.set_color("font_color", "PlaqueLabel", SOFT)
	t.set_font_size("font_size", "PlaqueLabel", 14)
	return t
