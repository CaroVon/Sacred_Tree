class_name ArtView
extends Control
## 画一张插画：牌面图版（裁切填满）或图标（完整放入）。
## 新的资产本身就是彩色图版，不再需要「白色剪影 + 错位套色版」。

@export var art_id: StringName = &"":
	set(v):
		art_id = v
		queue_redraw()
## 图版还是图标：图版裁切填满，图标完整放入。
@export var mode: int = 0:
	set(v):
		mode = v
		queue_redraw()
## 图标模式下的着色（白色 = 原色；乘到贴图上，所以别用深色）。
@export var tint: Color = Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
## 背景纸色；alpha 为 0 表示不画背景。
@export var paper: Color = Color(0, 0, 0, 0):
	set(v):
		paper = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	if art_id == &"":
		return
	if paper.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), paper)
	match mode:
		0:
			CardArt.draw_plate(self, art_id, Rect2(Vector2.ZERO, size))
		1:
			CardArt.draw_icon(self, art_id, size, tint)
		_:
			_draw_medallion()


## 圆形纹章：把图标裁进一个圆盘，外面套一圈金环。
## 小尺寸下即使图本身偏暗，看起来也像一枚有意为之的印章。
func _draw_medallion() -> void:
	var tex := CardArt.texture(art_id)
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 3.0
	if r <= 2.0:
		return
	# 底盘
	draw_circle(c, r, Palette.CREAM)
	if tex == null:
		CardArt.draw_emblem(self, c, r * 0.7, Palette.OCHRE)
	else:
		var ts := tex.get_size()
		if ts.x <= 0.0:
			return
		# 用一个多边形把图标裁到圆里
		var n := 28
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in n:
			var a := TAU * float(i) / float(n)
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * r)
			uvs.append(Vector2(0.5 + d.x * 0.5, 0.5 + d.y * 0.5))
		draw_polygon(pts, PackedColorArray(), uvs, tex)
	# 金环
	draw_arc(c, r, 0.0, TAU, 40, Palette.GOLD, 2.0, true)
	draw_arc(c, r - 3.0, 0.0, TAU, 40, Color(Palette.INK, 0.35), 1.0, true)
