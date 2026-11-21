@tool
class_name PrintBox
extends Container
## 带硬阴影的纸片容器：纸色底、墨色描边、套色错位的彩色阴影。
## 所有界面里的「纸片」都用它，是这套美术的基础件。

@export var bg: Color = Palette.SHEET:
	set(v):
		bg = v
		queue_redraw()
@export var border_color: Color = Palette.INK
@export var border: float = 2.0
@export var shadow_color: Color = Palette.OLIVE:
	set(v):
		shadow_color = v
		queue_redraw()
@export var shadow_offset: Vector2 = Vector2(6, 6)
@export var padding: float = 14.0:
	set(v):
		padding = v
		queue_sort()
## 内侧细线，像印张的双线框。
@export var inner_border: bool = false
## 纸面极淡的网点。
@export var halftone: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var r := Rect2(Vector2(padding, padding), size - Vector2(padding, padding) * 2)
		for c in get_children():
			if c is Control and c.visible:
				fit_child_in_rect(c, r)


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and c.visible:
			m = m.max(c.get_combined_minimum_size())
	return m + Vector2(padding, padding) * 2


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if shadow_offset != Vector2.ZERO and shadow_color.a > 0:
		draw_rect(Rect2(shadow_offset, size), shadow_color)
	draw_rect(r, bg)
	if halftone:
		PrintStyle.halftone(self, r.grow(-2.0), Color(Palette.INK, 0.035), 6.0, 1.0, 45.0)
	if inner_border and size.x > 12.0 and size.y > 12.0:
		draw_rect(r.grow(-5.0), Color(Palette.RULE, 0.85), false, 1.0)
	if border > 0:
		draw_rect(r, border_color, false, border)
