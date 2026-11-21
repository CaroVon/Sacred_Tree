class_name CardArt
extends RefCounted
## 新美学的插画资产加载与绘制。
##
## 资产在 game/assets/art/ 下，是「失落文明古典典藏图册」风格的彩色竖版图版
## （牌用 3:4 竖版，器物/天灾用 1:1 方形图标）。
## 由 game/tools/card_art/generate_art.py 用 MiniMax image-01 生成。

const DIR := "res://assets/art/"

static var _cache: Dictionary = {}


## 取得插画纹理；没有资产时返回 null。
static func texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D = null
	var path := DIR + String(id) + ".png"
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			tex = r
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	_cache[id] = tex
	return tex


static func has(id: StringName) -> bool:
	return texture(id) != null


## 画一版图：裁切填满 rect（cover），像贴上去的一小幅印刷品。
static func draw_plate(ci: CanvasItem, id: StringName, rect: Rect2) -> void:
	var tex := texture(id)
	if tex == null:
		_draw_placeholder(ci, id, rect)
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	# cover：按较大缩放比铺满，再居中裁切
	var s: float = maxf(rect.size.x / ts.x, rect.size.y / ts.y)
	var sz := ts * s
	var src := Rect2((ts - Vector2(rect.size.x / s, rect.size.y / s)) * 0.5,
		Vector2(rect.size.x / s, rect.size.y / s))
	ci.draw_texture_rect_region(tex, rect, src)


## 画一枚图标：完整放进 rect（contain），不裁切。
static func draw_icon(ci: CanvasItem, id: StringName, rect: Vector2, color: Color = Color.WHITE) -> void:
	var tex := texture(id)
	if tex == null:
		_draw_placeholder(ci, id, Rect2(rect, Vector2.ZERO))
		return
	var ts := tex.get_size()
	if ts.x <= 0.0:
		return
	var s: float = minf(rect.x / ts.x, rect.y / ts.y)
	var sz := ts * s
	ci.draw_texture_rect(tex, Rect2((rect - sz) * 0.5, sz), false, color)


## 没有资产时的占位：一枚几何纹章。
static func _draw_placeholder(ci: CanvasItem, id: StringName, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	draw_emblem(ci, Vector2(rect.position) + rect.size * 0.5, minf(rect.size.x, rect.size.y) * 0.4, Palette.OCHRE)


## 几何纹章：一个圆盘 + 放射的星芒，缺图时的占位符。
static func draw_emblem(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, Color(col, 0.85))
	ci.draw_circle(c, r * 0.62, Palette.SHEET)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 0.75, c + d * r * 1.25, col, maxf(1.0, r * 0.06), true)
