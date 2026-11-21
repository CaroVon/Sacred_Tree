class_name BoardView
extends Control
## 六边形牌桌。只负责绘制和把鼠标/拖放翻译成格子事件，不含规则。
## 可读性：常驻芽点线、牌上效果标签、末梢收获、悬停路径的养分流动、放置前后末梢增减。
##
## 美术：整块牌桌是一座「失落文明的庭院」；每格地块是一块铺石；
## 枝干是几何化的橄榄色刻线；可放置的位置是一枚压印的菱形符记。

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal hover_cleared
signal card_dropped(hand_index: int, cell: Vector2i)
## 脉动动画播完。
signal pulse_finished
## 脉动中某个末梢收获了（格子、收获值、在本控件里的屏幕位置）——计分演出用。
signal tip_harvested(cell: Vector2i, amount: int, at: Vector2)

const NO_CELL := Vector2i(9999, 9999)
const PATTERN_BADGES := {
	&"long": ["长", Palette.OLIVE], &"star": ["星", Palette.WATER], &"loop": ["环", Palette.GOLD],
}

var tree: TreeModel
var pulse: Pulse.Result
## 用来计算芽点（器物“古树根”会改变树心芽点）。
var ctx: Pulse.Context
var targets: Dictionary = {}       # Vector2i -> Growth.Target
var prune_mode: bool = false
var highlight: Dictionary = {}     # Vector2i -> true（修剪预览的子树）
var flash: Dictionary = {}         # Vector2i -> int（上次脉动的末梢收获）
var node_pick: Dictionary = {}     # Vector2i -> true（集市里可选的牌）
## 放置预览：末梢收获的变化（格子 -> 增减）。
var delta: Dictionary = {}
## 选中手牌悬停目标格时画的半透明预览牌。
var ghost_type: StringName = &""
var show_buds: bool = true
var show_labels: bool = true

var hover: Vector2i = NO_CELL
## 拖拽中的牌（用于在目标格上画半透明预览）。
var drag_type: StringName = &""

# 脉动动画：养分像油墨一样从树心按深度逐段流向末梢
const STEP := 0.16
const TAIL := 0.7
var anim_tree: TreeModel
var anim_pulse: Pulse.Result
var anim_t: float = -1.0
var _anim_dur: float = 0.0
var _anim_tips_done: Dictionary = {}

# 悬停路径：从树心到某张牌的养分流动（循环播放）
const TRACE_STEP := 0.45
const TRACE_HOLD := 1.2
var trace_target: Vector2i = NO_CELL
var _trace_nodes: Dictionary = {}
var _trace_t: float = 0.0
var _trace_depth: int = 0

# 结算单点击时的闪烁
var _blink: Vector2i = NO_CELL
var _blink_t: float = 0.0

## 落牌时的墨迹扩散动画。
var _stamp_at: Vector2i = NO_CELL
var _stamp_t: float = -1.0
var _stamp_col: Color = Palette.OCHRE

## 震动强度 0..1（Fx.shake 驱动）。
var shake_t: float = 0.0

var _buds: Array = []
var hex_size: float = 34.0
var origin: Vector2 = Vector2.ZERO
## 网格四周留给 HUD 的边距（左、上、右、下）。整屏牌桌时由场景设置。
var margins: Vector4 = Vector4.ZERO:
	set(v):
		margins = v
		_layout()
## 计算链面板的位置与最大宽度（本地坐标）；x < 0 表示用默认的左上角。
var chain_pos: Vector2 = Vector2(-1, -1)
var chain_width: float = 520.0
var chain_box: PanelContainer
var chain_label: Label
## 全局时间，用来让呼吸效果同步。
var _clock: float = 0.0


## 当前牌桌半径（随年份扩张）；还没有牌桌时用原型半径。
func board_radius() -> int:
	return tree.radius if tree else Rules.RADIUS


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_layout)
	set_process(true)


func _ready() -> void:
	chain_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.SHEET, 0.94)
	sb.border_color = Palette.OLIVE
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	chain_box.add_theme_stylebox_override("panel", sb)
	chain_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chain_box.visible = false
	add_child(chain_box)
	chain_label = Label.new()
	chain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chain_label.add_theme_font_size_override("font_size", 16)
	chain_box.add_child(chain_label)


## 在牌桌左上角显示一段“计算链”文字；空字符串则隐藏。
func set_chain(text: String) -> void:
	if chain_box == null:
		return
	chain_label.text = text
	chain_box.visible = text != ""
	var w := minf(size.x * 0.40, chain_width)
	chain_label.custom_minimum_size = Vector2(w, 0)
	chain_box.position = chain_pos if chain_pos.x >= 0.0 else Vector2(12, 12)
	chain_box.size = Vector2.ZERO
	chain_box.reset_size.call_deferred()


func set_state(t: TreeModel, p: Pulse.Result, tg: Dictionary, prune: bool, fl: Dictionary) -> void:
	tree = t
	pulse = p
	targets = tg
	prune_mode = prune
	flash = fl
	_buds = Growth.bud_report(t, ctx) if show_buds else []
	if trace_target != NO_CELL and not tree.has(trace_target):
		set_trace(NO_CELL)
	queue_redraw()


func is_animating() -> bool:
	return anim_t >= 0.0


## 立即停止脉动动画（不发 pulse_finished）。
func stop_pulse() -> void:
	anim_t = -1.0
	anim_tree = null
	anim_pulse = null
	queue_redraw()


## 播放一次脉动。snapshot 是脉动那一刻的树（脉动后树可能因天灾/枯萎而改变）。
func play_pulse(snapshot: TreeModel, res: Pulse.Result, sound: bool = true) -> void:
	if Game.reduce_motion:
		pulse_finished.emit()
		return
	anim_tree = snapshot
	anim_pulse = res
	var md := 0
	for n: TreeNode in snapshot.nodes.values():
		md = maxi(md, n.depth)
	_anim_dur = (md + 1) * STEP + TAIL
	anim_t = 0.0
	_anim_tips_done = {}
	if sound:
		Game.sfx(&"pulse")
	set_process(true)


## 一次脉动动画大概要播多久（秒）；减少动效时为 0。
func pulse_duration(t: TreeModel) -> float:
	if Game.reduce_motion or t == null:
		return 0.0
	var md := 0
	for n: TreeNode in t.nodes.values():
		md = maxi(md, n.depth)
	return (md + 1) * STEP + TAIL


## 高亮从树心到 k 的所有路径并循环播放养分流动；传 NO_CELL 取消。
func set_trace(k: Vector2i) -> void:
	trace_target = k
	_trace_nodes = {}
	_trace_t = 0.0
	if k != NO_CELL and tree and tree.has(k):
		var stack: Array[Vector2i] = [k]
		while not stack.is_empty():
			var x: Vector2i = stack.pop_back()
			if _trace_nodes.has(x):
				continue
			_trace_nodes[x] = true
			for p in tree.at(x).parents:
				stack.append(p)
		_trace_depth = tree.at(k).depth
		if not Game.reduce_motion:
			set_process(true)
	queue_redraw()


## 让某个格子闪一下（结算单里点某一行时）。
func blink(k: Vector2i) -> void:
	_blink = k
	_blink_t = 1.0
	set_process(true)


## 落牌时的一次墨迹扩散。
func stamp_at(c: Vector2i, col: Color) -> void:
	if Game.reduce_motion:
		return
	_stamp_at = c
	_stamp_t = 0.0
	_stamp_col = col
	set_process(true)
	Fx.shake(self, 2.5, 0.22)


func _process(delta_t: float) -> void:
	_clock += delta_t
	if anim_t >= 0.0:
		# 脉动中按住空格：2 倍速
		anim_t += delta_t * (2.0 if Input.is_key_pressed(KEY_SPACE) else 1.0)
		var reached := anim_t / STEP
		for k in anim_pulse.tip_list:
			if not _anim_tips_done.has(k) and reached >= anim_tree.at(k).depth + 1:
				_anim_tips_done[k] = anim_t
				# 音高随收获次数逐级上扬（Balatro 式的计分音阶）
				Game.sfx(&"tip", minf(2.2, 1.0 + 0.07 * _anim_tips_done.size()))
				tip_harvested.emit(k, int(anim_pulse.contrib.get(k, 0)), center_of(k))
				if _anim_tips_done.size() == 1:
					Fx.shake(self, 2.0, 0.22)
		if anim_t >= _anim_dur:
			anim_t = -1.0
			anim_tree = null
			anim_pulse = null
			pulse_finished.emit()
	if trace_target != NO_CELL and not Game.reduce_motion:
		_trace_t = fmod(_trace_t + delta_t, (_trace_depth + 1) * TRACE_STEP + TRACE_HOLD)
	if _blink_t > 0.0:
		_blink_t = maxf(0.0, _blink_t - delta_t)
	if _stamp_t >= 0.0:
		_stamp_t += delta_t
		if _stamp_t > 0.7:
			_stamp_t = -1.0
	queue_redraw()


func _layout() -> void:
	var r := board_radius()
	var w := Hex.SQRT3 * (r + 0.45) * 2.0
	var h := (1.5 * r + 0.9) * 2.0
	var avail := Vector2(size.x - margins.x - margins.z, size.y - margins.y - margins.w)
	hex_size = maxf(8.0, minf(avail.x / w, avail.y / h))
	origin = Vector2(margins.x, margins.y) + avail * 0.5
	queue_redraw()


## 六边形网格占据的矩形（全局坐标），导出版画时用。
func grid_rect() -> Rect2:
	var r := board_radius()
	var half := Vector2(Hex.SQRT3 * (r + 0.6), 1.5 * r + 1.1) * hex_size
	return Rect2(global_position + origin - half, half * 2.0)


func cell_at(p: Vector2) -> Vector2i:
	var c := Hex.from_pixel(p - origin, hex_size)
	return c if Hex.in_board(c, board_radius()) else NO_CELL


func center_of(c: Vector2i) -> Vector2:
	return origin + Hex.to_pixel(c, hex_size)


func _set_hover(c: Vector2i) -> void:
	if c == hover:
		return
	hover = c
	if c == NO_CELL:
		hover_cleared.emit()
	else:
		cell_hovered.emit(c)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_set_hover(cell_at(e.position))
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(e.position)
		if c != NO_CELL:
			cell_clicked.emit(c)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(NO_CELL)
	elif what == NOTIFICATION_DRAG_END:
		drag_type = &""
		queue_redraw()


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("hand_index")):
		return false
	drag_type = StringName(data.get("type", ""))
	var c := cell_at(at)
	_set_hover(c)
	return targets.has(c)


func _drop_data(at: Vector2, data: Variant) -> void:
	card_dropped.emit(int(data.hand_index), cell_at(at))


# ---------- 绘制 ----------

func _hex(c: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(Hex.corners(c, s), col)


func _hex_outline(c: Vector2, s: float, col: Color, w: float, dashed: bool = false) -> void:
	var pts := Hex.corners(c, s)
	for i in 6:
		var a := pts[i]
		var b := pts[(i + 1) % 6]
		if dashed:
			draw_dashed_line(a, b, col, w, s * 0.16)
		else:
			draw_line(a, b, col, w, true)


func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 带白描边的居中文字，保证压在纹理上也能看清。
func _text_outlined(font: Font, pos: Vector2, s: String, fs: int, col: Color, halo: Color = Palette.CREAM) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := pos - Vector2(w * 0.5, 0)
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.16)), halo)
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 带底色的小标签（算式、增减）。
func _pill(center: Vector2, s: String, fs: int, fg: Color, bg: Color) -> void:
	var font := Palette.body()
	var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(center - Vector2(sz.x * 0.5 + 5, fs * 0.62 + 3), Vector2(sz.x + 10, fs + 6))
	draw_rect(r, bg)
	draw_rect(r, fg, false, 1.0)
	draw_string(font, Vector2(r.position.x + 5, r.position.y + fs + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


func _draw() -> void:
	if tree == null:
		return
	var live_tree := tree
	var tree := anim_tree if anim_tree else live_tree
	var pulse := anim_pulse if anim_pulse else self.pulse
	var reached := anim_t / STEP if anim_t >= 0.0 else INF
	var tracing := trace_target != NO_CELL and anim_t < 0.0 and not _trace_nodes.is_empty()
	var trace_reached := (_trace_t / TRACE_STEP) if (tracing and not Game.reduce_motion) else INF
	var s := hex_size
	var k := s / 34.0
	var title := Palette.title()
	var body := Palette.body()
	var breathe := 0.5 + 0.5 * sin(_clock * 2.6)

	draw_set_transform(Fx.shake_offset(shake_t, 3.0), 0.0, Vector2.ONE)

	# ---------- 庭院背景 ----------
	_draw_courtyard()

	# ---------- 地块 ----------
	for c in Hex.all_cells(board_radius()):
		var p := center_of(c)
		_draw_land(c, p, s, k)
		if not tree.has(c) and targets.has(c):
			_draw_slot(c, p, s, k, breathe)

	# ---------- 芽点 ----------
	if show_buds and anim_t < 0.0:
		_draw_buds(tree, s, k, breathe)

	# ---------- 枝干 ----------
	_draw_branches(tree, s, k, reached)

	# ---------- 牌型徽记 ----------
	var badges := {}
	if pulse:
		for pat in pulse.patterns:
			if pat.id == &"sym":
				continue
			var info: Array = PATTERN_BADGES[pat.id]
			for c in pat.cells:
				badges[c] = info
		if pulse.total_mult > 1.0:
			_hex_outline(origin, s * (board_radius() + 0.9) * Hex.SQRT3, Palette.OCHRE, 2.0 * k, true)

	# ---------- 节点 ----------
	for n: TreeNode in tree.nodes.values():
		var p := center_of(n.key)
		var v: int = pulse.out.get(n.key, 0) if pulse else 0
		var is_tip: bool = pulse != null and pulse.tips.has(n.key)
		if anim_t >= 0.0 and reached < n.depth:
			v = 0
		if n.is_seed():
			_draw_seed(p, s, k, v)
		else:
			_draw_node(n, p, s, k, v, is_tip, pulse, tree, reached)
		if node_pick.has(n.key):
			_hex_outline(p, s - 2, Palette.WATER, (3.5 if n.key == hover else 2.2) * k, true)
		elif is_tip:
			_hex_outline(p, s - 2, Palette.OCHRE, 2.0 * k, true)
		if pulse and badges.has(n.key):
			var bp := p + Vector2(s * 0.62, -s * 0.55)
			draw_circle(bp, 10 * k, badges[n.key][1])
			_text(title, bp + Vector2(0, 5 * k), badges[n.key][0], int(13 * k), Palette.SHEET)
		if anim_t >= 0.0:
			if _anim_tips_done.has(n.key):
				var dt: float = anim_t - _anim_tips_done[n.key]
				var rise := minf(dt, 0.5) * 50.0 * k
				_text_outlined(title, p + Vector2(0, -s + 2 * k - rise), "+%d" % pulse.contrib[n.key],
					int((18 + 6 * clampf(1.0 - dt * 3.0, 0.0, 1.0)) * k), Palette.TERRA)
		elif flash.has(n.key) and not tracing:
			_text_outlined(body, p + Vector2(0, -s + 6 * k), "+%d" % flash[n.key], int(16 * k), Palette.TERRA)
		if n.key == _blink and _blink_t > 0.0:
			_hex_outline(p, s + 2, Color(Palette.OCHRE, _blink_t), 5.0 * k)

	# ---------- 悬停路径 ----------
	if tracing:
		_draw_trace(tree, pulse, s, k, trace_reached)

	# ---------- 放置预览 ----------
	if anim_t < 0.0:
		for c in delta:
			var d: int = delta[c]
			if d == 0:
				continue
			var col := Palette.OLIVE.darkened(0.15) if d > 0 else Palette.TERRA.darkened(0.05)
			_pill(center_of(c) + Vector2(0, -s * 0.98), ("+%d" if d > 0 else "−%d") % absi(d), int(14 * k), col, Color(Palette.SHEET, 0.96))

	# ---------- 预览牌 ----------
	var gt := drag_type if drag_type != &"" else ghost_type
	if gt != &"" and anim_t < 0.0 and targets.has(hover) and Cards.has(gt):
		_draw_ghost(gt, s, k)

	# ---------- 落牌墨迹 ----------
	if _stamp_t >= 0.0:
		_draw_stamp(s, k)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 庭院背景：一座失落文明的神庙大厅，压暗后当作牌桌的底。
func _draw_courtyard() -> void:
	var tex := CardArt.texture(&"board_bg")
	if tex != null:
		CardArt.draw_plate(self, &"board_bg", Rect2(Vector2.ZERO, size))
	# 只压四周（沿四边向内渐变，不越出牌桌矩形），中间保持原图亮度
	var clear := Color(Palette.INK, 0.0)
	var dark := Color(Palette.INK, 0.38)
	var w := minf(size.x, size.y) * 0.22
	var tl := Vector2.ZERO
	var tr := Vector2(size.x, 0)
	var br := size
	var bl := Vector2(0, size.y)
	var cols := PackedColorArray([dark, dark, clear, clear])
	draw_polygon(PackedVector2Array([tl, tr, tr + Vector2(-w, w), tl + Vector2(w, w)]), cols)
	draw_polygon(PackedVector2Array([tr, br, br + Vector2(-w, -w), tr + Vector2(-w, w)]), cols)
	draw_polygon(PackedVector2Array([br, bl, bl + Vector2(w, -w), br + Vector2(-w, -w)]), cols)
	draw_polygon(PackedVector2Array([bl, tl, tl + Vector2(w, w), bl + Vector2(w, -w)]), cols)


## 地块：一块铺石。底色 + 淡化的地形纹理 + 墨边，避免纹理喧宾夺主。
func _draw_land(c: Vector2i, p: Vector2, s: float, k: float) -> void:
	var lt := tree.land_at(c)
	var art := &"land_plain"
	var base := Palette.CELL
	match lt:
		Land.Type.FERTILE:
			art = &"land_fertile"
			base = Palette.OLIVE.lerp(Palette.CELL, 0.62)
		Land.Type.ROCK:
			art = &"land_rock"
			base = Palette.STONE.lerp(Palette.CELL, 0.45)
		Land.Type.SPRING:
			art = &"land_spring"
			base = Palette.WATER.lerp(Palette.CELL, 0.55)
		Land.Type.ORE, Land.Type.LAVA, Land.Type.STARWELL, Land.Type.GOLDSAND:
			art = Land.ART[lt] if CardArt.has(Land.ART[lt]) else &"land_plain"
			var lc: Color = {Land.Type.ORE: Palette.STEEL, Land.Type.LAVA: Palette.EMBER,
				Land.Type.STARWELL: Palette.ASTRAL, Land.Type.GOLDSAND: Palette.COIN}[lt]
			base = lc.lerp(Palette.CELL, 0.5)
		_:
			art = &"land_plain"
			base = Palette.CELL.darkened(0.10)
	var pts := Hex.corners(p, s - 2.0)
	# 投影
	var sh := PackedVector2Array()
	for v in pts:
		sh.append(v + Vector2(2.0, 2.4) * k)
	draw_colored_polygon(sh, Color(Palette.INK, 0.30))
	# 底色
	draw_colored_polygon(pts, base)
	# 地形纹理（淡化）
	var tex := CardArt.texture(art)
	if tex != null:
		var ts := tex.get_size()
		if ts.x > 0.0:
			# 每格取图版里的一小块，位置随格子变化，避免所有格子一个样
			var side: float = minf(ts.x, ts.y) * 0.45
			var ox: float = fposmod(float(c.x * 37 + c.y * 17) * 23.0, ts.x - side)
			var oy: float = fposmod(float(c.x * 29 - c.y * 41) * 19.0, ts.y - side)
			var src := Rect2(ox, oy, side, side)
			var uvs := PackedVector2Array()
			for v in pts:
				var u := (v - p) / (s * 2.0) + Vector2(0.5, 0.5)
				uvs.append((src.position + u * src.size) / ts)
			draw_polygon(pts, PackedColorArray([
				Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.85),
				Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.85)]), uvs, tex)
	# 内侧压暗，做出「石板」厚度
	draw_polyline(pts, Color(Palette.INK, 0.18), 3.0 * k, true)
	# 墨边
	var ol := pts
	ol.append(pts[0])
	draw_polyline(ol, Color(Palette.INK, 0.62), 1.6 * k, true)
	# 地块的铭牌式小标记
	match lt:
		Land.Type.FERTILE:
			draw_circle(p, 2.4 * k, Color(Palette.OLIVE, 0.9))
		Land.Type.ROCK:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-5, 2) * k, p + Vector2(0, -5) * k, p + Vector2(5, 2) * k]), Color(Palette.INK, 0.5))
		Land.Type.SPRING:
			PrintStyle.ring(self, p, s * 0.22, Color(Palette.WATER, 0.8), 1.6 * k)
		_:
			pass


## 卡槽：压印在石板上的符记。
func _draw_slot(c: Vector2i, p: Vector2, s: float, k: float, breathe: float) -> void:
	var hot: bool = hover == c
	var col := Color(Palette.OCHRE, 0.55 + breathe * 0.35) if hot else Color(Palette.OCHRE, 0.32)
	var r := s - 6.0
	# 一枚菱形符记
	var dia := PackedVector2Array([
		p + Vector2(0, -r * 0.62), p + Vector2(r * 0.62, 0),
		p + Vector2(0, r * 0.62), p + Vector2(-r * 0.62, 0)])
	draw_polyline(dia, col, 2.0 * k, true)
	# 内部的小十字
	var t := 5.0 * k
	draw_line(p - Vector2(t, 0), p + Vector2(t, 0), Color(col, 0.8), 1.2 * k, true)
	draw_line(p - Vector2(0, t), p + Vector2(0, t), Color(col, 0.8), 1.2 * k, true)
	if hot:
		_hex(p, s * 0.60, Color(Palette.OCHRE, 0.18))


## 芽点：橄榄色短线 = 可以接牌；灰带 × = 被挡住。
func _draw_buds(tree: TreeModel, s: float, k: float, breathe: float) -> void:
	for b in _buds:
		var from: Vector2i = b.from
		var cell: Vector2i = b.cell
		if b.status == &"occupied" and tree.at(cell).parents.has(from):
			continue
		var a := center_of(from)
		var dir := (center_of(cell) - a).normalized()
		var p0 := a + dir * s * 0.78
		var p1 := a + dir * s * 1.18
		if b.status == &"open":
			draw_line(p0, p1, Palette.OLIVE, 3.0 * k, true)
			var tip := p1 + dir * 5.0 * k
			var side := dir.orthogonal() * 3.4 * k
			var col := Color(Palette.OLIVE, 0.7 + breathe * 0.3)
			draw_colored_polygon(PackedVector2Array([tip, p1 + side, p1 - side]), col)
			draw_circle(p1, 3.0 * k, col)
		else:
			p1 = a + dir * s * 1.02
			var xc := Palette.TERRA.darkened(0.1)
			draw_line(p0, p1, Color(Palette.STONE, 0.95), 2.4 * k, true)
			var n := dir.orthogonal() * 5.0 * k
			var t := dir * 5.0 * k
			draw_line(p1 - n - t, p1 + n + t, xc, 2.6 * k, true)
			draw_line(p1 + n - t, p1 - n + t, xc, 2.6 * k, true)


## 枝干：几何化的刻线，粗细随深度递减。
func _draw_branches(tree: TreeModel, s: float, k: float, reached: float) -> void:
	var base_w := 4.4 * k
	# 底下一道浅色垫线，让枝干从地面上「浮」起来
	for n: TreeNode in tree.nodes.values():
		for ch in n.children:
			draw_line(center_of(n.key) + Vector2(1.6, 2.0) * k, center_of(ch) + Vector2(1.6, 2.0) * k,
				Color(Palette.CREAM, 0.35), _branch_width(n.depth, base_w) * 1.7, true)
	# 主干
	for n: TreeNode in tree.nodes.values():
		for ch in n.children:
			var a := center_of(n.key)
			var b := center_of(ch)
			var w := _branch_width(n.depth, base_w)
			draw_line(a, b, Palette.INK, w, true)
			# 刻线：高光一侧再补一条细线，像雕版
			var d := (b - a).normalized()
			var off := d.orthogonal() * w * 0.28
			draw_line(a + off, b + off, Color(Palette.OCHRE, 0.55), maxf(1.0, w * 0.28), true)
	# 脉动：已经流过的枝段点亮
	if anim_t >= 0.0:
		for n: TreeNode in tree.nodes.values():
			var lit := clampf(reached - n.depth, 0.0, 1.0)
			if lit <= 0.0:
				continue
			for ch in n.children:
				var a := center_of(n.key)
				var b := center_of(ch)
				draw_line(a, a.lerp(b, lit), Color(Palette.GOLD, 0.95), _branch_width(n.depth, base_w) * 1.9, true)


func _branch_width(depth: int, base: float) -> float:
	return maxf(1.6, base * (1.0 - float(depth) * 0.11))


## 树心：一枚深色印章。
func _draw_seed(p: Vector2, s: float, k: float, v: int) -> void:
	var title := Palette.title()
	var body := Palette.body()
	# 放射短线，像印章的光晕
	for i in 12:
		var a := TAU * i / 12.0
		draw_line(p + Vector2(cos(a), sin(a)) * s * 0.92, p + Vector2(cos(a), sin(a)) * s * 1.06,
			Color(Palette.OCHRE, 0.45), 1.2 * k, true)
	_hex(p, s - 6, Palette.INK)
	_hex_outline(p, s - 6, Color(Palette.OCHRE, 0.8), 1.4 * k)
	_text(title, p + Vector2(0, 5 * k), "种", int(19 * k), Palette.CREAM)
	if show_labels:
		_text_outlined(body, p + Vector2(0, -12 * k), "输出", int(9 * k), Palette.INK)
	_text_outlined(body, p + Vector2(0, 18 * k), str(v), int(12 * k), Palette.INK)


## 树上的一张牌：图版缩略 + 类别色环 + 名字。
func _draw_node(n: TreeNode, p: Vector2, s: float, k: float, v: int, is_tip: bool, pulse: Pulse.Result, tree: TreeModel, reached: float) -> void:
	var def := n.def()
	var title := Palette.title()
	var body := Palette.body()
	var col := Palette.card_color(def.color_key)
	var fill := Palette.SHEET
	if highlight.has(n.key):
		fill = Color(Palette.TERRA, 0.35)
	elif prune_mode and n.key == hover:
		fill = Color(Palette.TERRA, 0.28)
	var pts := Hex.corners(p, s - 6)
	# 投影
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(2.0, 2.2) * k)
	draw_colored_polygon(sh, Color(Palette.INK, 0.3))
	draw_colored_polygon(pts, fill)
	# 牌面图版（裁成中间的一块）
	var tex := CardArt.texture(def.art_id())
	if tex != null:
		var ts := tex.get_size()
		if ts.x > 0.0:
			# 取图版的一整幅（宽），让母题尽量完整
			var side: float = ts.x * 0.98
			var src := Rect2((ts.x - side) * 0.5, ts.y * 0.26, side, side)
			var uvs := PackedVector2Array()
			for q in pts:
				var u := (q - p) / (s * 2.0) + Vector2(0.5, 0.5)
				uvs.append((src.position + u * src.size) / ts)
			draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
				uvs, tex)
	_hex_outline(p, s - 6, Palette.INK, 1.8 * k)
	_hex_outline(p, s - 11, col, 3.0 * k)
	var fs := 17 if def.display_name.length() < 3 else 13
	_text_outlined(Palette.title_for(def.display_name), p + Vector2(0, 4 * k), def.display_name, int(fs * k), Palette.INK)
	if show_labels:
		_text_outlined(body, p + Vector2(0, -11 * k), Pulse.effect_text(def, n), int(10 * k), col.darkened(0.2))
	if not n.marks.is_empty():
		var ms := "".join(n.marks.map(func(m): return Rules.MARKS[m].short))
		_text_outlined(title, p + Vector2(-s * 0.55, s * 0.62), ms, int(12 * k), Palette.GOLD)
	if is_tip and pulse and pulse.contrib.has(n.key) and (anim_t < 0.0 or reached >= n.depth):
		_text_outlined(body, p + Vector2(0, 18 * k), "收 %d" % pulse.contrib[n.key], int(11 * k), Palette.TERRA)
	else:
		_text_outlined(body, p + Vector2(0, 18 * k), str(v), int(11 * k), Palette.INK)


## 悬停路径：其余部分变淡，路径上每张牌冒出这一步的算式。
func _draw_trace(tree: TreeModel, pulse: Pulse.Result, s: float, k: float, trace_reached: float) -> void:
	var w := 4.4 * k
	for n: TreeNode in tree.nodes.values():
		if not _trace_nodes.has(n.key):
			_hex(center_of(n.key), s - 4, Color(Palette.PAPER, 0.55))
	for x in _trace_nodes:
		var n := tree.at(x)
		for ch in n.children:
			if not _trace_nodes.has(ch):
				continue
			var a := center_of(x)
			var b := center_of(ch)
			var lit := clampf(trace_reached - n.depth, 0.0, 1.0)
			draw_line(a, b, Color(Palette.GOLD, 0.35), w * 2.2, true)
			draw_line(a, a.lerp(b, lit), Color(Palette.GOLD, 0.95), w * 2.2, true)
			if lit > 0.0 and lit < 1.0:
				draw_circle(a.lerp(b, lit), 7.0 * k, Palette.GOLD)
				draw_circle(a.lerp(b, lit), 3.5 * k, Palette.SHEET)
	for x in _trace_nodes:
		var n := tree.at(x)
		if trace_reached < n.depth:
			continue
		var label := _step_label(pulse, x)
		if label != "":
			_pill(center_of(x) + Vector2(0, -s * 0.98), label, int(13 * k), Palette.OLIVE.darkened(0.2), Color(Palette.SHEET, 0.96))
	if pulse and pulse.tips.has(trace_target) and trace_reached >= _trace_depth + 0.6:
		_pill(center_of(trace_target) + Vector2(0, s * 1.02), "收获 %d" % pulse.contrib[trace_target], int(14 * k), Palette.TERRA.darkened(0.1), Color(Palette.SHEET, 0.96))


## 预览牌：半透明的影子 + 类别色边。
func _draw_ghost(gt: StringName, s: float, k: float) -> void:
	var def := Cards.get_def(gt)
	var p := center_of(hover)
	var info = targets[hover]
	if info is Growth.Target:
		for par in info.parents:
			draw_line(center_of(par), p, Color(Palette.INK, 0.45), 4.4 * k, true)
	_hex(p, s - 6, Color(Palette.SHEET, 0.8))
	_hex_outline(p, s - 11, Color(Palette.card_color(def.color_key), 0.85), 3.0 * k)
	_text_outlined(Palette.title_for(def.display_name), p + Vector2(0, 4 * k), def.display_name,
		int((17 if def.display_name.length() < 3 else 13) * k), Color(Palette.INK, 0.75))


## 落牌的墨迹扩散。
func _draw_stamp(s: float, k: float) -> void:
	var p := center_of(_stamp_at)
	var t := clampf(_stamp_t / 0.55, 0.0, 1.0)
	var r := Fx.ink_spread(t, s * 0.9)
	if r <= 0.0:
		return
	var pts := Hex.corners(p, r)
	draw_colored_polygon(pts, Color(_stamp_col, 0.30 * (1.0 - t)))
	var ol := pts
	ol.append(pts[0])
	draw_polyline(ol, Color(_stamp_col, 0.6 * (1.0 - t)), 2.0 * k, true)


## 路径上一张牌这一步的简写：例如 “+3 = 4”、“×2 ×1.5 = 12”、“8 × 8 = 64”。
func _step_label(res: Pulse.Result, x: Vector2i) -> String:
	if res == null or not res.trace.has(x):
		return ""
	var tr: Array = res.trace[x]
	if tree.at(x).is_seed():
		return "输出 %d" % tr[-1].result
	var ops: Array[String] = []
	for st in tr:
		if st.op != "":
			ops.append(String(st.op).replace("嫁接相乘 ", "").replace("嫁接相加 ", ""))
	return "%s = %d" % [" ".join(ops), tr[-1].result]
