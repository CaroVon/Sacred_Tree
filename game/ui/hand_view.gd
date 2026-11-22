class_name HandView
extends Control
## 扇形手牌。每张牌是绝对定位的 CardView，位置/角度/缩放每帧向目标值弹性靠拢。
##
## 动画：
##   抽牌 —— 从牌库沿弧线飞出，途中从牌背翻到牌面，多张依次错开；
##   出牌 —— 飞向牌桌上的目标格并缩小淡出（由 mark_played 指定终点）；
##   弃牌 —— 翻回牌背，扫进弃牌堆。
## 悬停的牌抬起放大，左右邻牌让开。所有动画服从 Game.reduce_motion。

signal card_pressed(index: int)
signal card_drag_started(index: int)

const CARD_W := 150.0
const CARD_H := 255.0
## 悬停放大倍率与抬起高度。
const HOVER_SCALE := 1.22
const HOVER_LIFT := 40.0
## 静止时牌底离屏幕底边的距离。
const REST_GAP := 34.0
## 牌与牌之间最大的间距、扇形每张的倾角（弧度）。
const MAX_SPACING := 150.0
const FAN_ROT := 0.042
const FAN_DROP := 5.0
## 自动收起：鼠标离开屏幕底部这么高的区域、也没悬停手牌时，整手下沉 TUCK 像素。
const WAKE_ZONE := 300.0
const TUCK := 150.0
## 手牌区域的最大宽度。
const MAX_WIDTH := 900.0
## 抽牌飞行时长与错开间隔。
const DRAW_DUR := 0.46
const DRAW_STAGGER := 0.085
const LEAVE_DUR := 0.34

## 牌库 / 弃牌堆在本控件坐标系里的位置（由场景设置）。
var deck_point: Vector2 = Vector2(80, 900)
var discard_point: Vector2 = Vector2(1840, 900)
## 下一批新抽的牌额外推迟多久出发（结束回合时等脉动播完）。
var draw_delay: float = 0.0

## 当前在手里的牌（按手牌顺序）。
var _slots: Array[Slot] = []
## 正在离场的牌。
var _leaving: Array[Slot] = []
var _hover: int = -1
## 收起程度 0..1（1 = 完全收起）。
var _tuck: float = 0.0
var _empty_label: Label


class Slot:
	var cv: CardView
	var pos: Vector2          # 支点（牌底中点）位置
	var rot: float = 0.0
	var scl: float = 1.0
	var alpha: float = 1.0
	# 飞行（抽牌 / 离场）
	var flying: bool = false
	var delay: float = 0.0
	var t: float = 0.0
	var dur: float = 0.4
	var from: Vector2
	var from_rot: float = 0.0
	var from_scl: float = 1.0
	var to: Vector2
	var to_scl: float = 1.0
	var to_alpha: float = 1.0
	var flip_from: float = 0.0   # 1 = 牌背，0 = 牌面
	var flip_to: float = 0.0
	var flip: float = 0.0
	var arc: float = 200.0
	var spin: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _ready() -> void:
	_empty_label = Label.new()
	_empty_label.text = "手牌为空。结束回合会补抽。"
	_empty_label.theme_type_variation = &"SoftLabel"
	_empty_label.add_theme_color_override("font_color", Palette.CREAM)
	_empty_label.add_theme_color_override("font_outline_color", Color(Palette.INK, 0.8))
	_empty_label.add_theme_constant_override("outline_size", 5)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.visible = false
	add_child(_empty_label)


## 当前在手里的所有 CardView（按顺序）。
func cards() -> Array[CardView]:
	var out: Array[CardView] = []
	for s in _slots:
		out.append(s.cv)
	return out


## 某张手牌当前的全局中心位置（给飞行起点用）。
func card_center(i: int) -> Vector2:
	if i < 0 or i >= _slots.size():
		return global_position + size * 0.5
	return global_position + _slots[i].pos - Vector2(0, CARD_H * 0.5 * _slots[i].scl)


## 标记第 i 张牌被打出：下次 sync 时它会飞向 to_global 并消失。
func mark_played(i: int, to_global: Vector2) -> void:
	if i < 0 or i >= _slots.size():
		return
	var s: Slot = _slots[i]
	_slots.remove_at(i)
	_reindex()
	_start_leave(s, to_global - global_position + Vector2(0, CARD_H * 0.16), 0.16, 0.0, 0.0, 0.24)
	if _hover == i:
		_hover = -1


## 整手扫进弃牌堆（重抽时）；随后 sync 会把新牌全部当作新抽的。
func discard_all() -> void:
	for j in _slots.size():
		_start_leave(_slots[j], discard_point, 0.42, 1.0, 0.0, LEAVE_DUR, j * 0.05)
	_slots.clear()
	_hover = -1


## 用新的手牌列表同步：保留没变的牌，多出来的从牌库抽，少掉的扫进弃牌堆。
func sync(ids: Array) -> void:
	var used: Array[bool] = []
	used.resize(_slots.size())
	used.fill(false)
	var next: Array[Slot] = []
	var fresh: Array[int] = []
	var cursor := 0
	for i in ids.size():
		var id := StringName(ids[i])
		var found := -1
		for j in range(cursor, _slots.size()):
			if not used[j] and _slots[j].cv.card_id == id:
				found = j
				break
		if found >= 0:
			used[found] = true
			cursor = found + 1
			next.append(_slots[found])
		else:
			next.append(null)
			fresh.append(i)
	# 没被保留的：弃到弃牌堆
	var di := 0
	for j in _slots.size():
		if not used[j]:
			_start_leave(_slots[j], discard_point, 0.42, 1.0, 0.0, LEAVE_DUR, di * 0.05)
			di += 1
	# 新抽的牌
	var n := 0
	for i in fresh:
		var s := Slot.new()
		s.cv = _make_card(StringName(ids[i]))
		next[i] = s
		if Game.reduce_motion:
			s.flying = false
		else:
			s.flying = true
			s.delay = draw_delay + n * DRAW_STAGGER + (0.14 if not _leaving.is_empty() else 0.0)
			s.t = 0.0
			s.dur = DRAW_DUR
			s.from = deck_point
			s.from_rot = -0.5
			s.from_scl = 0.45
			s.flip_from = 1.0
			s.flip_to = 0.0
			s.to_alpha = 1.0
			s.arc = 180.0 + 20.0 * n
			s.pos = deck_point
			s.rot = s.from_rot
			s.scl = s.from_scl
			s.flip = 1.0
			s.cv.show_back = true
			s.cv.visible = false
		n += 1
	draw_delay = 0.0
	_slots = next
	_reindex()
	_hover = -1
	if Game.reduce_motion:
		_snap_all()
	_empty_label.visible = _slots.is_empty()
	# 新抽的牌：每张出发时一声轻响
	if n > 0 and not Game.reduce_motion:
		for k in n:
			var tw := create_tween()
			tw.tween_interval(maxf(0.01, _slots[fresh[k]].delay))
			tw.tween_callback(Game.sfx.bind(&"click", 1.5 + 0.08 * k))


func _make_card(id: StringName) -> CardView:
	var cv := CardView.make(id, -1)
	cv.custom_minimum_size = Vector2(CARD_W, CARD_H)
	cv.size = Vector2(CARD_W, CARD_H)
	cv.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)
	cv.pressed.connect(func(): card_pressed.emit(cv.index))
	cv.drag_started.connect(func(i: int): card_drag_started.emit(i))
	cv.mouse_entered.connect(func(): _hover = cv.index)
	cv.mouse_exited.connect(func():
		if _hover == cv.index:
			_hover = -1)
	add_child(cv)
	return cv


func _reindex() -> void:
	for i in _slots.size():
		_slots[i].cv.index = i


func _start_leave(s: Slot, to: Vector2, to_scl: float, flip_to: float, to_alpha: float, dur: float, delay: float = 0.0) -> void:
	if Game.reduce_motion:
		s.cv.queue_free()
		return
	s.cv.disabled = true
	s.cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.cv.z_index = 5
	s.flying = true
	s.delay = delay
	s.t = 0.0
	s.dur = dur
	s.from = s.pos
	s.from_rot = s.rot
	s.from_scl = s.scl
	s.to = to
	s.to_scl = to_scl
	s.flip_from = s.flip
	s.flip_to = flip_to
	s.to_alpha = to_alpha
	s.arc = 90.0
	s.spin = 0.35 if flip_to > 0.5 else 0.0
	_leaving.append(s)


## 扇形里第 i 张牌的目标支点、角度、缩放。
func _target(i: int) -> Array:
	var n := _slots.size()
	var spacing := minf(MAX_SPACING, MAX_WIDTH / maxf(1.0, n))
	var o := float(i) - (n - 1) * 0.5
	var x := size.x * 0.5 + o * spacing
	var y := size.y - REST_GAP + o * o * FAN_DROP + TUCK * Fx.ease_in_out(_tuck)
	var rot := o * FAN_ROT
	var scl := 1.0
	var cv := _slots[i].cv
	if _hover >= 0 and _hover < n:
		if i == _hover:
			y = size.y - REST_GAP - HOVER_LIFT
			rot = 0.0
			scl = HOVER_SCALE
		else:
			var d := i - _hover
			x += signf(d) * 34.0 / absf(d)
	if cv.selected and i != _hover:
		y -= 60.0 - TUCK * Fx.ease_in_out(_tuck) * 0.6
		rot = 0.0
	return [Vector2(x, y), rot, scl]


func _snap_all() -> void:
	for i in _slots.size():
		var s := _slots[i]
		var tg := _target(i)
		s.pos = tg[0]
		s.rot = tg[1]
		s.scl = tg[2]
		s.flying = false
		s.flip = 0.0
		s.cv.show_back = false
		s.cv.visible = true
		_apply(s)


func _process(dt: float) -> void:
	var k := 1.0 - exp(-dt * 16.0)
	# 自动收起：鼠标在牌桌上（或正在拖牌）时手牌下沉，别挡住牌桌下沿
	var m := get_local_mouse_position()
	var dragging := get_viewport().gui_is_dragging()
	var want := dragging or (_hover < 0 and m.y < size.y - WAKE_ZONE)
	if _slots.is_empty():
		want = false
	if Game.reduce_motion:
		_tuck = 1.0 if want else 0.0
	else:
		_tuck = move_toward(_tuck, 1.0 if want else 0.0, dt * (5.0 if want else 8.0))
	for i in _slots.size():
		_slots[i].cv.name_on_top = _tuck if i != _hover else 0.0
	for i in _slots.size():
		var s := _slots[i]
		var tg := _target(i)
		if s.flying:
			if s.delay > 0.0:
				s.delay -= dt
				s.cv.visible = false
				continue
			s.cv.visible = true
			s.t = minf(1.0, s.t + dt / s.dur)
			var e := Fx.ease_out(s.t)
			var to: Vector2 = tg[0]
			var ctrl := (s.from + to) * 0.5 + Vector2(0, -s.arc)
			s.pos = _bezier(s.from, ctrl, to, e)
			s.rot = lerpf(s.from_rot, tg[1], e)
			s.scl = lerpf(s.from_scl, tg[2], e)
			s.flip = lerpf(s.flip_from, s.flip_to, clampf((s.t - 0.15) / 0.6, 0.0, 1.0))
			if s.t >= 1.0:
				s.flying = false
				s.flip = 0.0
		else:
			s.pos = s.pos.lerp(tg[0], k)
			s.rot = lerpf(s.rot, tg[1], k)
			s.scl = lerpf(s.scl, tg[2], k)
		s.cv.z_index = 10 if i == _hover else 0
		_apply(s)
	for j in range(_leaving.size() - 1, -1, -1):
		var s := _leaving[j]
		if s.delay > 0.0:
			s.delay -= dt
			continue
		s.t = minf(1.0, s.t + dt / s.dur)
		var e := Fx.ease_in_out(s.t)
		var ctrl := (s.from + s.to) * 0.5 + Vector2(0, -s.arc)
		s.pos = _bezier(s.from, ctrl, s.to, e)
		s.rot = s.from_rot + s.spin * e
		s.scl = lerpf(s.from_scl, s.to_scl, e)
		s.flip = lerpf(s.flip_from, s.flip_to, e)
		s.alpha = lerpf(1.0, s.to_alpha, clampf((s.t - 0.5) * 2.0, 0.0, 1.0))
		_apply(s)
		if s.t >= 1.0:
			s.cv.queue_free()
			_leaving.remove_at(j)
	if _empty_label and _empty_label.visible:
		_empty_label.position = Vector2((size.x - _empty_label.size.x) * 0.5, size.y - 90.0)


func _apply(s: Slot) -> void:
	var cv := s.cv
	# 翻面：横向压扁到 0 再展开，过半时换面
	var fx := absf(cos(s.flip * PI))
	cv.show_back = s.flip > 0.5
	cv.scale = Vector2(s.scl * maxf(fx, 0.02), s.scl)
	cv.rotation = s.rot
	cv.position = s.pos - cv.pivot_offset
	cv.modulate.a = s.alpha


static func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + c * 2.0 * u * t + b * t * t
