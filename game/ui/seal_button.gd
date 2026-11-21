class_name SealButton
extends Button
## 一枚大圆印章按钮（结束回合并脉动）。
## 墨色圆盘 + 金色双环 + 放射刻线；悬停放大，可提示时（没牌可放了）缓慢呼吸发光。

@export var main_text: String = "脉动"
@export var sub_text: String = "结束回合 · 空格"
## 是否提示玩家按下（例如本回合已放满）。
var urge: bool = false:
	set(v):
		urge = v
		queue_redraw()
var _hover_t: float = 0.0
var _press_t: float = 0.0
var _clock: float = 0.0


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(176, 176)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button_down.connect(func(): _press_t = 1.0)
	set_process(true)


func _process(dt: float) -> void:
	_clock += dt
	var target := 1.0 if is_hovered() and not disabled else 0.0
	_hover_t = move_toward(_hover_t, target, dt * 6.0)
	_press_t = maxf(0.0, _press_t - dt * 5.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var base_r: float = minf(size.x, size.y) * 0.5 - 10.0
	var motion := not Game.reduce_motion
	var breathe := (0.5 + 0.5 * sin(_clock * 3.0)) if (urge and motion and not disabled) else 0.0
	var r := base_r * (1.0 + 0.05 * Fx.ease_out(_hover_t) - 0.06 * _press_t)
	# 投影
	draw_circle(c + Vector2(4, 6), r, Color(Palette.INK, 0.35))
	# 呼吸光晕
	if urge and not disabled:
		for i in 4:
			draw_circle(c, r + 4.0 + i * 4.0 + breathe * 6.0, Color(Palette.GOLD, 0.10 - i * 0.02))
	var fill := Palette.INK if not disabled else Palette.STONE.darkened(0.25)
	draw_circle(c, r, fill)
	# 放射刻线
	var spin := _clock * 0.15 if motion else 0.0
	for i in 24:
		var a := TAU * i / 24.0 + spin
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.80, c + d * r * 0.90, Color(Palette.GOLD, 0.5 if not disabled else 0.25), 1.6, true)
	var ring := Palette.GOLD if not disabled else Color(Palette.SAGE, 0.6)
	draw_arc(c, r - 3.0, 0, TAU, 64, ring, 3.0, true)
	draw_arc(c, r * 0.74, 0, TAU, 64, Color(ring, 0.7), 1.4, true)
	# 文字
	var tf := Palette.title_for(main_text)
	var fs := int(r * 0.42)
	var tsz := tf.get_string_size(main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var txt_col := Palette.CREAM if not disabled else Color(Palette.CREAM, 0.5)
	draw_string(tf, c + Vector2(-tsz.x * 0.5, fs * 0.30), main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
	var bf := Palette.caption()
	var sfs := int(maxf(11.0, r * 0.14))
	var ssz := bf.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs)
	draw_string(bf, c + Vector2(-ssz.x * 0.5, r * 0.52), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(ring, 0.95))
