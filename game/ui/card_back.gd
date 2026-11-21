class_name CardBack
extends RefCounted
## 牌背：深色石板 + 金色双线框 + 中央的日轮与神树纹章。
## 有生成的牌背图（assets/art/card_back.png）时优先用图，再压上同样的金框。


static func draw(ci: CanvasItem, r: Rect2) -> void:
	var k: float = r.size.x / 200.0
	var tex := CardArt.texture(&"card_back")
	if tex != null:
		CardArt.draw_plate(ci, &"card_back", r)
	else:
		ci.draw_rect(r, Palette.INK)
		# 极淡的网点，像拓印的石面
		PrintStyle.halftone(ci, r.grow(-4.0 * k), Color(Palette.OCHRE, 0.07), 7.0 * k, 1.2 * k, 45.0)
		var c := r.get_center()
		var rad: float = r.size.x * 0.26
		# 日轮
		ci.draw_circle(c + Vector2(0, -rad * 0.35), rad, Color(Palette.OCHRE, 0.85))
		ci.draw_circle(c + Vector2(0, -rad * 0.35), rad * 0.78, Palette.INK)
		for i in 16:
			var a := TAU * i / 16.0
			var d := Vector2(cos(a), sin(a))
			ci.draw_line(c + Vector2(0, -rad * 0.35) + d * rad * 1.12, c + Vector2(0, -rad * 0.35) + d * rad * 1.32,
				Color(Palette.GOLD, 0.7), maxf(1.0, 1.4 * k), true)
		# 神树：一根主干 + 两层对称分枝
		var base := c + Vector2(0, rad * 1.5)
		var top := c + Vector2(0, -rad * 0.6)
		var w := maxf(1.5, 3.0 * k)
		ci.draw_line(base, top, Palette.GOLD, w, true)
		for lv in 3:
			var y := lerpf(base.y, top.y, 0.35 + lv * 0.22)
			var spread := rad * (0.9 - lv * 0.22)
			for sgn: float in [-1.0, 1.0]:
				ci.draw_line(Vector2(c.x, y), Vector2(c.x + sgn * spread, y - spread * 0.7), Palette.GOLD, w * 0.7, true)
		# 台阶
		for i in 3:
			var hw := rad * (0.55 + i * 0.25)
			var y := base.y + i * 5.0 * k
			ci.draw_line(Vector2(c.x - hw, y), Vector2(c.x + hw, y), Color(Palette.GOLD, 0.8), maxf(1.0, 1.6 * k), true)
	# 金色双线框
	ci.draw_rect(r, Palette.INK, false, maxf(1.0, 1.6 * k))
	ci.draw_rect(r.grow(-5.0 * k), Palette.GOLD, false, maxf(1.0, 1.4 * k))
	ci.draw_rect(r.grow(-9.0 * k), Color(Palette.GOLD, 0.45), false, maxf(1.0, 1.0 * k))
