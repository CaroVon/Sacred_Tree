class_name PileView
extends Control
## 牌堆：一叠牌背，厚度随张数变化，上面盖一枚数字印。
## 牌库和弃牌堆都用它；抽牌/弃牌动画以它的中心为起点/终点。

@export var title: String = "牌库"
var count: int = 0:
	set(v):
		if v != count:
			count = v
			_bump = 1.0
			set_process(true)
		queue_redraw()
## 弃牌堆的牌是正面朝上的一点点歪斜，用另一种色调区分。
@export var face_up: bool = false
var _bump: float = 0.0

const CARD := Vector2(96, 150)


func _init() -> void:
	custom_minimum_size = Vector2(130, 196)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(dt: float) -> void:
	_bump = maxf(0.0, _bump - dt * 4.0)
	if _bump <= 0.0:
		set_process(false)
	queue_redraw()


## 牌堆顶的中心（本地坐标）。
func top_point() -> Vector2:
	return Vector2(size.x * 0.5, CARD.y * 0.5 + 10.0)


func _draw() -> void:
	var layers: int = clampi(int(ceil(count / 3.0)), 0, 7)
	var x0 := (size.x - CARD.x) * 0.5
	var y0 := 10.0 + layers * 2.0
	# 桌面上的投影
	if count > 0:
		draw_rect(Rect2(Vector2(x0 + 6, y0 + 8), CARD), Color(Palette.INK, 0.35))
	if count <= 0:
		PrintStyle.dashed_rect(self, Rect2(Vector2(x0, y0), CARD), Color(Palette.CREAM, 0.6), 2.0, 8.0)
	for i in range(layers, -1, -1):
		if count <= 0:
			break
		var off := Vector2(i * 0.6, -i * 2.0)
		var rot := deg_to_rad((i % 3 - 1) * 1.2) if face_up else 0.0
		var r := Rect2(Vector2(x0, y0) + off, CARD)
		draw_set_transform(r.get_center(), rot, Vector2.ONE)
		var lr := Rect2(-CARD * 0.5, CARD)
		if face_up:
			draw_rect(lr, Palette.SHEET.darkened(0.04 * i))
			draw_rect(lr, Palette.INK, false, 1.2)
			draw_rect(lr.grow(-4), Color(Palette.OCHRE, 0.5), false, 1.0)
		else:
			CardBack.draw(self, lr)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 数字印
	var c := Vector2(size.x * 0.5, y0 + CARD.y - 6)
	var rr := 19.0 + 5.0 * Fx.back_out(1.0 - _bump) * _bump
	draw_circle(c, rr, Palette.INK)
	draw_arc(c, rr, 0, TAU, 32, Palette.GOLD, 2.0, true)
	var f := Palette.numeric()
	var s := str(count)
	var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(f, c + Vector2(-sz.x * 0.5, 6.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.CREAM)
	# 名字
	var bf := Palette.caption()
	var tsz := bf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	var ty := size.y - 4
	draw_string_outline(bf, Vector2((size.x - tsz.x) * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 6, Color(Palette.INK, 0.9))
	draw_string(bf, Vector2((size.x - tsz.x) * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Palette.CREAM)
