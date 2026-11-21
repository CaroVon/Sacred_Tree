class_name SeasonPath
extends Control
## 年轮路径：三年 × 五季，每季一枚石盘，用细线串成一条路。
## 走过的石盘刻金、打勾；当前季发光呼吸；天灾季用土红色环；以后的季节只是淡淡的轮廓。
## 每枚石盘下面写着这一季的目标分数。

var year: int = 1
var season: int = 1
var _clock: float = 0.0

const ROW_H := 108.0
const DISC_R := 30.0
const LABEL_W := 74.0


func _init() -> void:
	custom_minimum_size = Vector2(620, ROW_H * Rules.YEARS + 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(dt: float) -> void:
	_clock += dt
	queue_redraw()


func _disc_pos(y: int, st: int) -> Vector2:
	var span := size.x - LABEL_W - DISC_R * 2.0 - 12.0
	var x := LABEL_W + DISC_R + 6.0 + span * float(st - 1) / float(Rules.STAGES - 1)
	return Vector2(x, ROW_H * (y - 1) + DISC_R + 12.0)


func _draw() -> void:
	var title := Palette.title()
	var body := Palette.body()
	var num := Palette.numeric()
	var breathe := 0.5 + 0.5 * sin(_clock * 2.4) if not Game.reduce_motion else 0.5
	for y in range(1, Rules.YEARS + 1):
		var cur_year := y == year
		var ly := ROW_H * (y - 1) + DISC_R + 12.0
		# 年份
		var yt := "第%d年" % y
		draw_string(title, Vector2(0, ly + 9), yt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
			Palette.INK if cur_year else Color(Palette.SOFT, 0.8))
		# 串起来的路：走过的一段是金线，没走的是淡虚线
		for st in range(1, Rules.STAGES):
			var a := _disc_pos(y, st)
			var b := _disc_pos(y, st + 1)
			var walked := y < year or (y == year and st < season)
			var pa := a + Vector2(DISC_R, 0)
			var pb := b - Vector2(DISC_R, 0)
			if walked:
				draw_line(pa, pb, Palette.GOLD, 3.0, true)
			else:
				draw_dashed_line(pa, pb, Color(Palette.RULE, 0.9), 2.0, 7.0)
		# 年与年之间：从上一年最后一枚往下一年第一枚的弧线
		if y < Rules.YEARS:
			var a := _disc_pos(y, Rules.STAGES) + Vector2(0, DISC_R)
			var b := _disc_pos(y + 1, 1) + Vector2(0, -DISC_R)
			var walked_y := y < year
			var pts := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				var ctrl := Vector2((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
				var p := a.lerp(ctrl + Vector2(0, 0), t).lerp(ctrl.lerp(b, t), t)
				pts.append(p)
			if walked_y:
				draw_polyline(pts, Color(Palette.GOLD, 0.8), 2.0, true)
			else:
				for i in range(0, pts.size() - 1, 2):
					draw_line(pts[i], pts[i + 1], Color(Palette.RULE, 0.8), 1.6, true)
		# 石盘
		for st in range(1, Rules.STAGES + 1):
			var c := _disc_pos(y, st)
			var done := y < year or (y == year and st < season)
			var current := y == year and st == season
			var cal := Rules.is_calamity(st)
			var ring := Palette.TERRA if cal else Palette.GOLD
			# 投影
			draw_circle(c + Vector2(2, 4), DISC_R, Color(Palette.INK, 0.25))
			if current:
				for i in 4:
					draw_circle(c, DISC_R + 5.0 + i * 4.0 + breathe * 5.0, Color(ring, 0.12 - i * 0.025))
				draw_circle(c, DISC_R, Palette.INK)
				draw_arc(c, DISC_R - 2.5, 0, TAU, 48, ring, 3.0, true)
			elif done:
				draw_circle(c, DISC_R, Palette.CELL.lerp(Palette.GOLD, 0.25))
				draw_arc(c, DISC_R - 2.0, 0, TAU, 48, Color(ring, 0.9), 2.0, true)
			else:
				draw_circle(c, DISC_R, Color(Palette.SHEET, 0.95))
				draw_arc(c, DISC_R - 2.0, 0, TAU, 48, Color(ring if cal else Palette.RULE, 0.8), 1.5, true)
			# 季名
			var nm := Rules.season_name(st)
			var fs := 22 if nm.length() == 1 else 17
			var col := Palette.CREAM if current else (Palette.TERRA if cal else Palette.INK)
			if not current and not done and not cur_year:
				col = Color(col, 0.55)
			var sz := title.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(title, c + Vector2(-sz.x * 0.5, fs * 0.36), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			# 走过的：右上角一枚小勾
			if done:
				var k := c + Vector2(DISC_R * 0.62, -DISC_R * 0.62)
				draw_circle(k, 9, Palette.OLIVE)
				draw_polyline(PackedVector2Array([k + Vector2(-4, 0), k + Vector2(-1, 3), k + Vector2(4, -3)]), Palette.CREAM, 2.0, true)
			# 目标
			var tg := _short(Rules.target(st, y))
			var tsz := num.get_string_size(tg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			draw_string(num, c + Vector2(-tsz.x * 0.5, DISC_R + 20), tg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Palette.INK if current else Color(Palette.SOFT, 0.85))


static func _short(v: int) -> String:
	if v >= 10000:
		return "%s万" % Pulse.num(snappedf(v / 10000.0, 0.1))
	return str(v)
