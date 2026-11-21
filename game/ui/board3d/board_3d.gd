class_name Board3D
extends BoardView
## 3D 牌桌：BoardView 的直接替换。
##
## 美学：没有实体的台面——一片向四周淡出的「虚拟台面」，六边形格线若隐若现；
## 神树真的长在桌上：木质枝条从树心逐格延伸，每张牌在它的格子上立起一枚纸雕立牌（拟态）。
## 文字只在悬停时出现（悬停卡片、路径算式、放置增减）；脉动的收获数字是反馈，保留。
##
## 结构：背景图（2D）→ SubViewport 里的 3D 场景 → 本控件 _draw 画的 2D 标注（由相机投影定位）。
## 背景和 3D 视口都设了 show_behind_parent，所以画在本控件的 _draw 之下。
## 规则相关的状态、信号、动画计时全部继承 BoardView。

const PITCH := 64.0           # 相机俯角（更俯：前后排拉开，前排压不住后排）
const FOV := 30.0
const WOOD_Y := 0.07          # 枝条离地高度
const LABEL_Y := 0.7          # 标注挂在立牌的半高处
const POP_DUR := 0.42         # 立牌翻立的时长
const STANDEE_TILT := 0.72    # 立牌朝镜头倾斜的比例（相对俯角）；越大越「躺」，竖向遮挡越小
## 悬停透视：挡在目标格前面的立牌淡到这个不透明度。
const XRAY_ALPHA := 0.32
## 图解视图（立牌折倒、铺开旧版式的六边形牌片）。
var diagram: bool = false
var _fold: float = 0.0

## 牌桌内容变化时（新放/剪掉的牌）是否播放翻立/折倒动画。
var animate_changes: bool = true

var _bg: TextureRect
var _svc: SubViewportContainer
var _vp: SubViewport
var _world: Node3D
var _env: Environment
var _cam: Camera3D
var _light: DirectionalLight3D
var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _land_root: Node3D
var _wood_root: Node3D
var _piece_root: Node3D
var _fx_root: Node3D
var _motes: CPUParticles3D
var _weather: Node3D
var _ghost: Sprite3D
var _ghost_type: StringName = &""
var _heart: MeshInstance3D

var _land_sig: String = ""
var _land_mats: Array[ShaderMaterial] = []
var _pieces: Dictionary = {}         # Vector2i -> Piece
var _leaving: Array[Piece] = []
var _glows: Array = []               # [holder: Node3D, depth: int]
var _drop_pending: Dictionary = {}   # Vector2i -> true（下一次出现时翻立）
var _tip_fx: Dictionary = {}
var _was_animating: bool = false
var _cam_d: float = 20.0
var _ho: float = 0.0
var _vo: float = 0.0
## 视角：缩放倍数（1 = 正好放下整张牌桌）与平移（台面坐标）。
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.2
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var _drag_pan: bool = false
var _fit_radius: int = -1
## 当前季节（1–4 = 春夏秋冬，5 = 天灾季）与天灾。
var _season: int = 1
var _calamity: StringName = &""
var _base_energy: float = 0.7
var _flash: float = 0.0              # 雷击闪光
var _next_bolt: float = 3.0


static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


class Piece:
	var node: Node3D
	var sprite: Sprite3D
	var type: StringName
	var height: float = 1.0
	var pop_t: float = -1.0      # 翻立进度（<0 = 不在翻立）
	var bounce_t: float = -1.0   # 脉动末梢的弹跳
	var leave_t: float = 0.0
	var phase: float = 0.0       # 摇摆相位


# ======================================================================
# 搭场景
# ======================================================================

func _ready() -> void:
	super._ready()
	show_labels = false
	_bg = TextureRect.new()
	_bg.texture = CardArt.texture(&"board_bg")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	add_child(_bg)
	move_child(_bg, 0)

	_svc = SubViewportContainer.new()
	_svc.stretch = false
	_svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svc.show_behind_parent = true
	add_child(_svc)
	move_child(_svc, 1)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.own_world_3d = true
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_svc.add_child(_vp)

	_world = Node3D.new()
	_vp.add_child(_world)
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#ECE8E0")
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = _env
	_world.add_child(we)
	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-52, -38, 0)
	_light.light_color = Color("#FFF7EA")
	_light.light_energy = 0.7
	# 虚拟台面不接收实时阴影：用柔和的接触阴影块代替（也省性能）
	_light.shadow_enabled = false
	_light.shadow_bias = 0.03
	_light.shadow_opacity = 0.75
	_light.directional_shadow_max_distance = 60.0
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_world.add_child(_light)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.current = true
	_world.add_child(_cam)

	_build_ground()
	_land_root = Node3D.new()
	_world.add_child(_land_root)
	_wood_root = Node3D.new()
	_world.add_child(_wood_root)
	_piece_root = Node3D.new()
	_world.add_child(_piece_root)
	_fx_root = Node3D.new()
	_world.add_child(_fx_root)
	_build_motes()
	set_mood(1, &"")
	_layout()


## 虚拟台面：一张透明受光的大平面，格线由着色器画出、向四周淡出。
func _build_ground() -> void:
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(34, 34)
	_ground.mesh = pm
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://ui/board3d/ground.gdshader")
	_ground_mat.set_shader_parameter("radius", float(board_radius()))
	# 透明物体按距离排序；台面、地貌、接触阴影永远先画，立牌才不会被台面的半透明盖住
	_ground_mat.render_priority = -30
	_ground.material_override = _ground_mat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_ground)
	# 树心下面的一圈金光（脉动时亮起）
	_heart = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.75
	disc.height = 0.02
	disc.radial_segments = 32
	_heart.mesh = disc
	_heart.position.y = 0.012
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(Palette.GOLD, 0.55)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_texture = _dot_texture()
	hm.render_priority = -10
	_heart.material_override = hm
	_heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_heart)


## 光束里缓缓漂浮的浮尘（待机时的生命感）。
func _build_motes() -> void:
	if Game.reduce_motion:
		return
	_motes = CPUParticles3D.new()
	_motes.amount = 46
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(9, 1.6, 8)
	_motes.position = Vector3(0, 1.8, 0)
	_motes.direction = Vector3(0.3, 1, 0)
	_motes.spread = 60.0
	_motes.gravity = Vector3(0, 0.02, 0)
	_motes.initial_velocity_min = 0.05
	_motes.initial_velocity_max = 0.18
	_motes.scale_amount_min = 0.4
	_motes.scale_amount_max = 1.0
	_motes.mesh = _dot_quad(0.09)
	_motes.color_ramp = _fade_ramp(Color(1.0, 0.93, 0.75), 0.75)
	_world.add_child(_motes)


## 两头透明、中段为 col 的渐变（粒子淡入淡出用）。
static func _fade_ramp(col: Color, peak: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.set_color(1, Color(col, 0.0))
	g.add_point(0.3, Color(col, peak))
	g.add_point(0.7, Color(col, peak))
	return g


# ======================================================================
# 季节光照与天灾天气
# ======================================================================

## 四季改变光的方向、颜色和台面色调；天灾季叠加天气。
func set_mood(season: int, calamity: StringName) -> void:
	_season = season
	_calamity = calamity if Rules.is_calamity(season) else &""
	if _light == null:
		return
	# [光色, 光强, 俯角, 方位, 环境光色, 环境光强, 台面色调]
	var m: Array
	match season:
		1: m = [Color("#F4FBEF"), 0.70, -50.0, -40.0, Color("#E6EEE4"), 0.50, Color(0.96, 1.0, 0.95)]
		2: m = [Color("#FFF1D6"), 0.78, -64.0, -20.0, Color("#F1E8D6"), 0.50, Color(1.03, 1.0, 0.92)]
		3: m = [Color("#FFD9A8"), 0.70, -36.0, -62.0, Color("#EBD9C4"), 0.46, Color(1.04, 0.95, 0.86)]
		4: m = [Color("#DCE6F2"), 0.58, -44.0, -120.0, Color("#D8DDE4"), 0.52, Color(0.92, 0.95, 1.0)]
		_: m = [Color("#F2D2B6"), 0.62, -46.0, -30.0, Color("#D9CCC4"), 0.42, Color(0.98, 0.92, 0.88)]
	var tint: Color = m[6]
	_light.light_color = m[0]
	_base_energy = m[1]
	_light.light_energy = _base_energy
	_light.rotation_degrees = Vector3(m[2], m[3], 0)
	_env.ambient_light_color = m[4]
	_env.ambient_light_energy = m[5]
	if _calamity == &"drought":
		_light.light_color = Color("#FFC98A")
		tint = Color(1.08, 0.94, 0.78)
	_ground_mat.set_shader_parameter("season_tint", tint)
	for lm in _land_mats:
		lm.set_shader_parameter("season_tint", tint)
	_build_weather()


func _build_weather() -> void:
	if _weather:
		_weather.queue_free()
		_weather = null
	if Game.reduce_motion or _calamity == &"":
		return
	_weather = Node3D.new()
	_world.add_child(_weather)
	var p := CPUParticles3D.new()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.mesh = _dot_quad(0.08)
	match _calamity:
		&"pests":
			# 虫害：成团乱飞的小黑虫
			p.amount = 60
			p.lifetime = 3.0
			p.preprocess = 3.0
			p.emission_box_extents = Vector3(7, 0.8, 6)
			p.position = Vector3(0, 0.9, 0)
			p.spread = 180.0
			p.gravity = Vector3.ZERO
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 1.4
			p.scale_amount_min = 0.5
			p.scale_amount_max = 0.9
			p.color_ramp = _fade_ramp(Color(0.16, 0.14, 0.12), 0.9)
		&"drought":
			# 干旱：缓缓上升的热浪尘
			p.amount = 40
			p.lifetime = 4.0
			p.preprocess = 4.0
			p.emission_box_extents = Vector3(9, 0.1, 8)
			p.position = Vector3(0, 0.1, 0)
			p.direction = Vector3(0, 1, 0)
			p.spread = 15.0
			p.gravity = Vector3(0, 0.15, 0)
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.5
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.2
			p.color_ramp = _fade_ramp(Color(1.0, 0.78, 0.45), 0.35)
		_:
			# 雷击：低空飘过的阴云尘 + 间歇闪光（在 _process 里）
			p.amount = 24
			p.lifetime = 5.0
			p.preprocess = 5.0
			p.emission_box_extents = Vector3(9, 0.5, 8)
			p.position = Vector3(0, 2.2, 0)
			p.direction = Vector3(1, 0, 0)
			p.spread = 10.0
			p.gravity = Vector3.ZERO
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.0
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
			p.color_ramp = _fade_ramp(Color(0.35, 0.38, 0.45), 0.18)
	_weather.add_child(p)


# ======================================================================
# 材质与网格缓存
# ======================================================================

static func _mat(key: StringName, make: Callable) -> Material:
	if not _mat_cache.has(key):
		_mat_cache[key] = make.call()
	return _mat_cache[key]


static func _flat(key: StringName, col: Color, unshaded: bool = false) -> Material:
	return _mat(key, func():
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return m)


static func _cached_mesh(key: StringName, make: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = make.call()
	return _mesh_cache[key]


static var _dot: Texture2D


static func _dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 32
		gt.height = 32
		_dot = gt
	return _dot


static func _dot_quad(sz: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _dot_texture()
	q.material = m
	return q


## 一张牌的拟态立牌贴图；没有就退回牌面插画。
static var _placeholder_cache: Dictionary = {}


static func standee_texture(id: StringName) -> Texture2D:
	id = StringName(String(id).trim_suffix("+"))
	var t := CardArt.texture(StringName("standee_" + String(id)))
	if t == null:
		t = CardArt.texture(id)
	return t if t else placeholder_standee(id)


## 缺图时的占位立牌：流派色的纸雕徽记（一枚竖长的盾形剪纸 + 浅色内圈），不再隐形。
static func placeholder_standee(id: StringName) -> Texture2D:
	if _placeholder_cache.has(id):
		return _placeholder_cache[id]
	var def := Cards.get_def(id)
	var col := Palette.family_color(def.families()[0]) if def else Palette.OLIVE
	var w := 96
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := w * 0.5
	for y in h:
		for x in w:
			var dx := (x - cx) / (w * 0.46)
			var top := 20.0
			var inside := false
			if y >= top and y < h * 0.62:
				inside = absf(dx) <= 1.0
			elif y >= h * 0.62:
				var t := (y - h * 0.62) / (h * 0.38)
				inside = absf(dx) <= 1.0 - t
			elif y < top:
				var r := Vector2(x - cx, y - top).length()
				inside = r <= w * 0.46 and false
			if not inside:
				continue
			var ring := Vector2(x - cx, y - h * 0.42).length()
			var c := col
			if ring < w * 0.26 and ring > w * 0.18:
				c = Palette.CREAM
			elif absf(dx) > 0.88 or y < top + 4:
				c = col.darkened(0.3)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_placeholder_cache[id] = tex
	return tex


## 立牌高度（世界单位）：末端与相邻牌（果、花）最显眼，传导与修剪牌矮一些。
static func standee_height(n: TreeNode) -> float:
	if n.is_seed():
		return 2.4
	match n.def().category:
		CardDef.Category.END: return 1.85
		CardDef.Category.AURA: return 1.85
		CardDef.Category.GRAFT: return 1.7
		CardDef.Category.BRANCH: return 1.6
		CardDef.Category.TIME: return 1.6
		CardDef.Category.PRUNE: return 1.4
	return 1.4


# ======================================================================
# 相机与坐标
# ======================================================================

func _layout() -> void:
	if _cam == null:
		return
	_vp.size = Vector2i(maxi(2, int(size.x)), maxi(2, int(size.y)))
	_fit_radius = board_radius()
	_ground_mat.set_shader_parameter("radius", float(_fit_radius))
	_fit_camera()
	_clamp_pan()
	_apply_view()


func _place_cam(d: float, ho: float, vo: float, at: Vector3 = Vector3.ZERO) -> void:
	var p := deg_to_rad(PITCH)
	_cam.position = at + Vector3(0, sin(p), cos(p)) * d
	_cam.look_at(at, Vector3.UP)
	_cam.h_offset = ho
	_cam.v_offset = vo


## 按当前缩放与平移摆相机（基于 _fit_camera 算出的“整桌”机位）。
func _apply_view() -> void:
	_place_cam(_cam_d / zoom, _ho / zoom, _vo / zoom, Vector3(pan.x, 0.0, pan.y))
	origin = _proj(Vector3.ZERO)
	hex_size = maxf(8.0, (_proj(Vector3(Hex.SQRT3, 0, 0)) - origin).length() / Hex.SQRT3)
	queue_redraw()


## 屏幕点落在台面上的位置。
func _ground_at(p: Vector2) -> Vector3:
	var o := _cam.project_ray_origin(p)
	var d := _cam.project_ray_normal(p)
	if absf(d.y) < 0.0001:
		return Vector3.ZERO
	return o + d * (-o.y / d.y)


## 以屏幕点 at 为中心缩放。
func zoom_at(at: Vector2, factor: float) -> void:
	if _cam == null:
		return
	var before := _ground_at(at)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_apply_view()
	var after := _ground_at(at)
	pan += Vector2(before.x - after.x, before.z - after.z)
	_clamp_pan()
	_apply_view()


## 按屏幕像素平移。
func pan_by(px: Vector2) -> void:
	if _cam == null:
		return
	var a := _ground_at(size * 0.5)
	var b := _ground_at(size * 0.5 + px)
	pan -= Vector2(b.x - a.x, b.z - a.z)
	_clamp_pan()
	_apply_view()


func reset_view() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	if _cam:
		_apply_view()


func _clamp_pan() -> void:
	var lim := (board_radius() + 1.0) * Hex.SQRT3 * (1.0 - 1.0 / zoom)
	if pan.length() > lim:
		pan = pan.normalized() * lim if lim > 0.0 else Vector2.ZERO


## 缩放/平移输入：滚轮或 Ctrl+滚轮（触控板捏合）缩放；触控板双指滑动、右键/中键拖动平移；
## 双击右键复位。处理了返回 true。
func _view_input(e: InputEvent) -> bool:
	if e is InputEventMagnifyGesture:
		zoom_at(e.position, e.factor)
		return true
	if e is InputEventPanGesture:
		pan_by(-e.delta * 12.0)
		return true
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		var wheel := mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if wheel:
			if not mb.pressed:
				return true
			var f := mb.factor if mb.factor > 0.0 else 1.0
			# 精确触控板的双指滑动给出小于 1 的 factor：当作平移；鼠标滚轮与 Ctrl（捏合）当作缩放
			var smooth := f < 0.99 and not mb.ctrl_pressed
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					if smooth:
						pan_by(Vector2(0, -30.0 * f))
					else:
						zoom_at(mb.position, pow(1.12, f))
				MOUSE_BUTTON_WHEEL_DOWN:
					if smooth:
						pan_by(Vector2(0, 30.0 * f))
					else:
						zoom_at(mb.position, pow(1.0 / 1.12, f))
				MOUSE_BUTTON_WHEEL_LEFT:
					pan_by(Vector2(-30.0 * f, 0))
				MOUSE_BUTTON_WHEEL_RIGHT:
					pan_by(Vector2(30.0 * f, 0))
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed and mb.double_click:
				reset_view()
				_drag_pan = false
				return true
			_drag_pan = mb.pressed and zoom > 1.001
			return _drag_pan or not mb.pressed and zoom > 1.001
	if e is InputEventMouseMotion and _drag_pan:
		pan_by(-(e as InputEventMouseMotion).relative)
		return true
	return false


## 让六边形网格正好放进 margins 留出的矩形里。
func _fit_camera() -> void:
	var apos := Vector2(margins.x, margins.y)
	var avail := Vector2(size.x - margins.x - margins.z, size.y - margins.y - margins.w)
	if avail.x < 20.0 or avail.y < 20.0:
		apos = Vector2.ZERO
		avail = size
	var lo := 4.0
	var hi := 120.0
	for i in 22:
		var d := (lo + hi) * 0.5
		_place_cam(d, 0.0, 0.0)
		var bb := _grid_bbox()
		if bb.size.x <= avail.x and bb.size.y <= avail.y:
			hi = d
		else:
			lo = d
	_cam_d = hi
	var ho := 0.0
	var vo := 0.0
	for i in 5:
		_place_cam(_cam_d, ho, vo)
		var bb := _grid_bbox()
		var delta := (apos + avail * 0.5) - bb.get_center()
		var ppu := (_proj(Vector3(1, 0, 0)) - _proj(Vector3.ZERO)).length()
		if ppu <= 0.001:
			break
		ho -= delta.x / ppu
		vo += delta.y / ppu
	_ho = ho
	_vo = vo


## 网格（含立牌高度）的屏幕包围盒。
func _grid_bbox() -> Rect2:
	var bb := Rect2()
	var first := true
	for c in Hex.all_cells(board_radius()):
		if Hex.distance(c, Vector2i.ZERO) < board_radius():
			continue
		for y: float in [0.0, 1.2]:
			for p in _proj_hex(c, 1.0, y):
				if first:
					bb = Rect2(p, Vector2.ZERO)
					first = false
				else:
					bb = bb.expand(p)
	return bb


func _wpos(c: Vector2i, y: float = 0.0) -> Vector3:
	var p := Hex.to_pixel(c, 1.0)
	return Vector3(p.x, y, p.y)


func _proj(w: Vector3) -> Vector2:
	if _cam == null or not _cam.is_inside_tree():
		return Vector2.ZERO
	return _cam.unproject_position(w)


## 某格某高度的六个角投影到屏幕上（透视下的六边形）。
func _proj_hex(c: Vector2i, r: float, y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var w := _wpos(c, y)
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		out.append(_proj(w + Vector3(cos(a), 0, sin(a)) * r))
	return out


func _cell_y(c: Vector2i) -> float:
	var t := anim_tree if anim_tree else tree
	return LABEL_Y if t != null and t.has(c) else 0.0


func center_of(c: Vector2i) -> Vector2:
	return _proj(_wpos(c, _cell_y(c)))


func cell_at(p: Vector2) -> Vector2i:
	if _cam == null:
		return NO_CELL
	var o := _cam.project_ray_origin(p)
	var d := _cam.project_ray_normal(p)
	if absf(d.y) < 0.0001:
		return NO_CELL
	var t := (0.15 - o.y) / d.y
	var hit := o + d * t
	var c := Hex.from_pixel(Vector2(hit.x, hit.z), 1.0)
	return c if Hex.in_board(c, board_radius()) else NO_CELL


func grid_rect() -> Rect2:
	var bb := _grid_bbox().grow(hex_size * 0.6)
	bb.position += global_position
	return bb


# ======================================================================
# 状态同步
# ======================================================================

func set_state(t: TreeModel, p: Pulse.Result, tg: Dictionary, prune: bool, fl: Dictionary) -> void:
	super.set_state(t, p, tg, prune, fl)
	if board_radius() != _fit_radius:
		_layout()
	_sync3d()


func play_pulse(snapshot: TreeModel, res: Pulse.Result, sound: bool = true) -> void:
	super.play_pulse(snapshot, res, sound)
	_tip_fx = {}
	_sync3d()


func stamp_at(c: Vector2i, _col: Color) -> void:
	if Game.reduce_motion or not animate_changes:
		return
	_drop_pending[c] = true


func _sync3d() -> void:
	if _world == null:
		return
	var t := anim_tree if anim_tree else tree
	if t == null:
		return
	_sync_land(t)
	_sync_pieces(t)
	_sync_wood(t)


## 特殊地块：柔边贴花。平地不画任何东西（就是虚拟台面本身）。
func _sync_land(t: TreeModel) -> void:
	var sig := var_to_str(t.land)
	if sig == _land_sig:
		return
	_land_sig = sig
	for ch in _land_root.get_children():
		ch.queue_free()
	_land_mats.clear()
	var shader: Shader = load("res://ui/board3d/land_patch.gdshader")
	for c in Hex.all_cells(board_radius()):
		var lt := t.land_at(c)
		if lt == Land.Type.PLAIN:
			continue
		var art := &"land_fertile"
		var tint := Color.WHITE
		match lt:
			Land.Type.ROCK: art = &"land_rock"
			Land.Type.SPRING: art = &"land_spring"
			Land.Type.ORE: tint = Palette.STEEL
			Land.Type.LAVA: tint = Palette.EMBER
			Land.Type.STARWELL: tint = Palette.ASTRAL
			Land.Type.GOLDSAND: tint = Palette.COIN
		var tex := CardArt.texture(art)
		if tex == null:
			continue
		var ts := tex.get_size()
		var side: float = minf(ts.x, ts.y) * 0.5
		var ox: float = fposmod(float(c.x * 37 + c.y * 17) * 23.0, ts.x - side)
		var oy: float = fposmod(float(c.x * 29 - c.y * 41) * 19.0, ts.y - side)
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("uv_rect", Vector4(ox / ts.x, oy / ts.y, side / ts.x, side / ts.y))
		m.set_shader_parameter("seed", float(c.x * 7 + c.y * 13))
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("tint_amount", 0.0 if tint == Color.WHITE else 0.75)
		m.set_shader_parameter("ripple", 1.0 if lt == Land.Type.SPRING and not Game.reduce_motion else 0.0)
		m.set_shader_parameter("opacity", 0.8 if lt != Land.Type.ROCK else 0.7)
		m.render_priority = -20
		_land_mats.append(m)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.3, 2.3)
		mi.mesh = pm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = _wpos(c, 0.004 + 0.001 * float(c.x & 3))
		_land_root.add_child(mi)
		# 岩石：再立几块矮石头，让「不能长」一眼可见
		if lt == Land.Type.ROCK:
			for i in 3:
				var rk := MeshInstance3D.new()
				var sm := SphereMesh.new()
				var rr := 0.16 + 0.07 * float(posmod(c.x * 3 + c.y * 5 + i * 7, 4))
				sm.radius = rr
				sm.height = rr * 1.2
				sm.radial_segments = 7
				sm.rings = 3
				rk.mesh = sm
				rk.material_override = _flat(&"rock", Palette.STONE.lightened(0.15))
				var a := TAU * (i / 3.0) + c.x
				rk.position = _wpos(c, rr * 0.35) + Vector3(cos(a), 0, sin(a)) * 0.38
				_land_root.add_child(rk)
	set_mood(_season, _calamity)


func _sync_pieces(t: TreeModel) -> void:
	for k in _pieces.keys():
		var pc: Piece = _pieces[k]
		if not t.has(k) or t.at(k).type != pc.type:
			_pieces.erase(k)
			if animate_changes and not Game.reduce_motion:
				pc.leave_t = 0.0
				_leaving.append(pc)
				_burst(pc.node.position + Vector3(0, 0.4, 0), Color(Palette.OLIVE, 0.9), 12, 1.4)
			else:
				pc.node.queue_free()
	for n: TreeNode in t.nodes.values():
		if _pieces.has(n.key):
			continue
		var pc := _make_piece(n)
		pc.node.position = _wpos(n.key, 0.0)
		_piece_root.add_child(pc.node)
		if _drop_pending.has(n.key):
			_drop_pending.erase(n.key)
			pc.pop_t = 0.0
			pc.sprite.rotation.x = -PI * 0.5
		_pieces[n.key] = pc
	_drop_pending.clear()


func _make_piece(n: TreeNode) -> Piece:
	var pc := Piece.new()
	pc.type = n.type
	pc.height = standee_height(n)
	pc.phase = float(n.key.x * 31 + n.key.y * 17) * 0.37
	pc.node = Node3D.new()
	pc.node.add_child(_blob(1.0 + pc.height * 0.25, 0.42))
	var sp := _standee_sprite(n.type if not n.is_seed() else &"seed", pc.height)
	pc.node.add_child(sp)
	pc.sprite = sp
	return pc


func _standee_sprite(id: StringName, h: float) -> Sprite3D:
	var tex := standee_texture(id)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.shaded = true
	sp.double_sided = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tex:
		sp.pixel_size = h / maxf(1.0, tex.get_size().y)
		sp.offset = Vector2(0, tex.get_size().y * 0.5)
	sp.rotation.x = -deg_to_rad(PITCH) * STANDEE_TILT
	return sp


## 切换图解视图：立牌像立体书合上一样折倒，台面上铺开旧版式的六边形牌片。
func set_diagram(on: bool) -> void:
	if on == diagram:
		return
	diagram = on
	if Game.reduce_motion:
		_fold = 1.0 if on else 0.0
	queue_redraw()


## 立牌顶端的世界坐标（考虑后仰角）。
func _standee_top(k: Vector2i, h: float) -> Vector3:
	var tilt := -deg_to_rad(PITCH) * STANDEE_TILT
	return _wpos(k, 0.0) + Vector3(0, h * cos(tilt), h * sin(tilt))


## 木质枝条：从父格到子格的锥形圆木，粗细随深度递减；嫁接边是金绿色的藤。
func _sync_wood(t: TreeModel) -> void:
	for ch in _wood_root.get_children():
		ch.queue_free()
	_glows.clear()
	var bark := _flat(&"bark", Color("#5B4632"))
	var vine := _flat(&"vine_wood", Palette.OLIVE.lerp(Palette.GOLD, 0.35))
	var glow := _mat(&"wood_glow", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#F6CB72")
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return m)
	for n: TreeNode in t.nodes.values():
		var r0 := _wood_r(n.depth)
		# 关节：一颗小圆球让枝条衔接得圆润
		var joint := MeshInstance3D.new()
		joint.mesh = _cached_mesh(StringName("joint_%d" % n.depth), func():
			var s := SphereMesh.new()
			s.radius = r0 * 1.15
			s.height = r0 * 2.3
			s.radial_segments = 10
			s.rings = 5
			return s)
		joint.material_override = bark
		joint.position = _wpos(n.key, WOOD_Y)
		_wood_root.add_child(joint)
		for ch in n.children:
			var child := t.at(ch)
			var graft := child != null and not child.is_seed() and child.def().is_graft()
			var a := _wpos(n.key, WOOD_Y)
			var b := _wpos(ch, WOOD_Y)
			var L := a.distance_to(b)
			var r1 := _wood_r(n.depth + 1)
			var holder := Node3D.new()
			_wood_root.add_child(holder)
			holder.position = a
			holder.look_at(b, Vector3.UP)
			var cyl := MeshInstance3D.new()
			cyl.mesh = _cached_mesh(StringName("wood_%d_%s" % [n.depth, graft]), func():
				var c := CylinderMesh.new()
				c.top_radius = (r1 if not graft else 0.05)
				c.bottom_radius = (r0 if not graft else 0.06)
				c.height = Hex.SQRT3
				c.radial_segments = 8
				c.rings = 1
				return c)
			cyl.material_override = vine if graft else bark
			# 圆柱默认沿 +Y：底面（粗端）朝父格。绕 X 转 +90° 后 +Y 指向 -Z（look_at 的前方）……
			# 圆柱的 bottom 在 -Y，所以这里转 -90°：bottom 朝 +Z（父端），top 朝 -Z（子端）。
			cyl.rotation.x = -PI * 0.5
			cyl.position = Vector3(0, 0, -L * 0.5)
			cyl.scale = Vector3(1, L / Hex.SQRT3, 1)
			holder.add_child(cyl)
			# 脉动时从父端往子端生长的金光
			var gh := Node3D.new()
			holder.add_child(gh)
			var gm := MeshInstance3D.new()
			gm.mesh = cyl.mesh
			gm.rotation.x = -PI * 0.5
			gm.position = Vector3(0, 0, -L * 0.5)
			gm.scale = Vector3(1.35, L / Hex.SQRT3, 1.35)
			gm.material_override = glow
			gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gh.add_child(gm)
			gh.scale = Vector3(1, 1, 0.001)
			gh.visible = false
			_glows.append([gh, n.depth])


## 接触阴影：贴在台面上的一块柔和暗斑，略偏向背光的一侧。
func _blob(w: float, a: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, w * 0.62)
	mi.mesh = pm
	mi.material_override = _mat(StringName("blob_%.2f" % a), func():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _dot_texture()
		m.albedo_color = Color(0.17, 0.14, 0.11, a)
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.render_priority = -10
		return m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.12, 0.01, 0.08)
	return mi


static func _wood_r(depth: int) -> float:
	return maxf(0.045, 0.17 * pow(0.86, float(depth)))


# ======================================================================
# 每帧
# ======================================================================

func _gui_input(e: InputEvent) -> void:
	if _view_input(e):
		accept_event()
		return
	super._gui_input(e)


func _process(dt: float) -> void:
	super._process(dt)
	if _world == null:
		return
	var motion := not Game.reduce_motion
	var anim := is_animating()
	if _was_animating and not anim:
		_sync3d()
	_was_animating = anim
	# 镜头震动
	var sh := Fx.shake_offset(shake_t, 0.05)
	_cam.h_offset = _ho + sh.x
	_cam.v_offset = _vo + sh.y
	# 脉动金光沿枝条推进
	var reached := anim_t / STEP if anim_t >= 0.0 else -1.0
	for g in _glows:
		var gh: Node3D = g[0]
		if reached < 0.0:
			gh.visible = false
			continue
		var lit := clampf(reached - float(g[1]), 0.0, 1.0)
		gh.visible = lit > 0.0
		gh.scale = Vector3(1, 1, maxf(0.001, lit))
	# 树心的金光：平时缓慢呼吸，脉动开始时闪亮扩散
	var hm: StandardMaterial3D = _heart.material_override
	var ha := 0.35 + (0.15 * sin(_clock * 2.0) if motion else 0.0)
	var hs := 1.0
	if anim_t >= 0.0:
		var hk := clampf(anim_t / 0.6, 0.0, 1.0)
		ha = maxf(ha, 1.0 - hk)
		hs = 1.0 + 1.6 * Fx.ease_out(hk)
	hm.albedo_color = Color(Palette.GOLD.lightened(0.2), ha)
	_heart.scale = Vector3(hs, 1, hs)
	# 末梢收获：立牌弹一下 + 金屑
	if anim_t >= 0.0:
		for k in _anim_tips_done:
			if not _tip_fx.has(k):
				_tip_fx[k] = true
				if _pieces.has(k):
					_pieces[k].bounce_t = 0.0
					_burst(_wpos(k, 0.7), Color("#F2C46A"), 16, 2.4)
	# 立牌
	var tracing := trace_target != NO_CELL and anim_t < 0.0 and not _trace_nodes.is_empty()
	var tilt := -deg_to_rad(PITCH) * STANDEE_TILT
	_fold = move_toward(_fold, 1.0 if diagram else 0.0, dt * 4.0) if motion else (1.0 if diagram else 0.0)
	var fold_e := Fx.ease_in_out(_fold)
	# 悬停透视的焦点：悬停的格子（选牌/拖牌时就是目标格）
	var focus := hover if (hover != NO_CELL and anim_t < 0.0 and _fold < 0.5) else NO_CELL
	var fpos := _wpos(focus) if focus != NO_CELL else Vector3.ZERO
	for k in _pieces:
		var pc: Piece = _pieces[k]
		var sp := pc.sprite
		var y := 0.0
		var scl := 1.0
		if pc.pop_t >= 0.0:
			pc.pop_t += dt / POP_DUR
			var t := minf(pc.pop_t, 1.0)
			sp.rotation.x = lerpf(-PI * 0.5, tilt, Fx.back_out(t))
			scl = lerpf(0.6, 1.0, Fx.ease_out(t))
			if pc.pop_t >= 1.0:
				pc.pop_t = -1.0
				_burst(_wpos(k, 0.05), Color(Palette.CREAM.darkened(0.12), 0.9), 18, 1.4)
				Fx.shake(self, 0.8, 0.18)
		else:
			sp.rotation.x = tilt
		# 图解视图：折倒并隐去
		if _fold > 0.0:
			sp.rotation.x = lerpf(sp.rotation.x, -PI * 0.5, fold_e)
		sp.visible = _fold < 0.98
		if pc.bounce_t >= 0.0:
			pc.bounce_t += dt / 0.38
			var t := minf(pc.bounce_t, 1.0)
			y += 0.28 * sin(t * PI)
			scl *= 1.0 + 0.18 * sin(t * PI)
			if pc.bounce_t >= 1.0:
				pc.bounce_t = -1.0
		# 微风：轻轻摇摆；悬停的那一枚稍微抬起
		sp.rotation.z = (sin(_clock * 1.4 + pc.phase) * 0.035) if motion else 0.0
		if k == hover and not prune_mode and anim_t < 0.0:
			scl *= 1.08
		sp.position.y = y
		sp.scale = Vector3.ONE * scl
		# 剪枝预览染红、悬停路径以外的变暗
		var col := Color.WHITE
		var is_seed := tree != null and tree.has(k) and tree.at(k).is_seed()
		if highlight.has(k) or (prune_mode and k == hover and not is_seed):
			col = Color(1.0, 0.55, 0.5)
		elif tracing and not _trace_nodes.has(k):
			col = Color(0.55, 0.55, 0.55)
		# 悬停透视：挡在焦点格前面（离镜头更近、左右相近）的立牌变淡
		if focus != NO_CELL and k != focus:
			var w := _wpos(k)
			var dz := w.z - fpos.z
			if dz > 0.1 and dz < 3.3 and absf(w.x - fpos.x) < 1.6:
				col.a = XRAY_ALPHA
		col.a *= 1.0 - fold_e * 0.8
		sp.modulate = sp.modulate.lerp(col, 1.0 - exp(-dt * 14.0)) if motion else col
	for i in range(_leaving.size() - 1, -1, -1):
		var pc := _leaving[i]
		pc.leave_t += dt / 0.4
		var t := minf(pc.leave_t, 1.0)
		pc.sprite.rotation.x = lerpf(tilt, -PI * 0.5, Fx.ease_in_out(t))
		pc.sprite.rotation.z = t * 0.8
		pc.node.position.y = 0.6 * sin(t * PI)
		pc.sprite.scale = Vector3.ONE * maxf(0.01, 1.0 - t * 0.7)
		if pc.leave_t >= 1.0:
			pc.node.queue_free()
			_leaving.remove_at(i)
	_update_ghost()
	# 雷击：间歇闪光
	if _calamity == &"lightning" and motion:
		_next_bolt -= dt
		if _next_bolt <= 0.0:
			_next_bolt = randf_range(3.5, 7.0)
			_flash = 1.0
		_flash = maxf(0.0, _flash - dt * 3.5)
		_light.light_energy = _base_energy + 2.2 * _flash * (0.6 + 0.4 * sin(_clock * 60.0))
	elif _flash > 0.0:
		_flash = 0.0
		_light.light_energy = _base_energy


## 预览立牌：悬停可放置格时，一枚半透明的立牌浮在格子上方。
func _update_ghost() -> void:
	var gt := drag_type if drag_type != &"" else ghost_type
	var show := gt != &"" and anim_t < 0.0 and targets.has(hover) and Cards.has(gt) and not (tree and tree.has(hover))
	if not show:
		if _ghost:
			_ghost.visible = false
		return
	if _ghost == null or _ghost_type != gt:
		if _ghost:
			_ghost.queue_free()
		var n := TreeNode.new()
		n.type = gt
		_ghost = _standee_sprite(gt, standee_height(n))
		_ghost.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		_ghost.modulate = Color(1, 1, 1, 0.55)
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost_type = gt
		_piece_root.add_child(_ghost)
	_ghost.visible = true
	var bob := 0.06 * sin(_clock * 3.0) if not Game.reduce_motion else 0.0
	_ghost.position = _wpos(hover, 0.12 + bob)


## 一次性的粒子：尘土 / 金屑 / 叶屑。
func _burst(at: Vector3, col: Color, amount: int, speed: float) -> void:
	if Game.reduce_motion:
		return
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -3.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.mesh = _dot_quad(0.14)
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col, 0.0))
	p.color_ramp = grad
	_fx_root.add_child(p)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(p.queue_free)


# ======================================================================
# 2D 标注层（画在 3D 之上）
# ======================================================================

func _draw() -> void:
	if tree == null or _cam == null:
		return
	var t := anim_tree if anim_tree else tree
	var pulse := anim_pulse if anim_pulse else self.pulse
	var tracing := trace_target != NO_CELL and anim_t < 0.0 and not _trace_nodes.is_empty()
	var trace_reached := (_trace_t / TRACE_STEP) if (tracing and not Game.reduce_motion) else INF
	var s := hex_size
	var k := s / 34.0
	var title := Palette.title()
	var body := Palette.body()
	var breathe := 0.5 + 0.5 * sin(_clock * 2.6)
	var gt := drag_type if drag_type != &"" else ghost_type

	# ---------- 雷击闪光 ----------
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.92, 0.95, 1.0, 0.22 * _flash))

	# ---------- 可放置格：台面上一块柔光 ----------
	if anim_t < 0.0:
		for c in targets:
			if t.has(c):
				continue
			var hot: bool = hover == c
			var poly := _proj_hex(c, 0.8, 0.01)
			var a := (0.30 + breathe * 0.22) if hot else (0.10 + breathe * 0.10)
			draw_colored_polygon(poly, Color(Palette.OCHRE, a))
			var ol := poly.duplicate()
			ol.append(poly[0])
			draw_polyline(ol, Color(Palette.OCHRE, 0.75 if hot else 0.4), (2.4 if hot else 1.4) * k, true)

	# ---------- 芽点（只在选牌 / 拖牌时显示，平时保持画面干净）----------
	if show_buds and anim_t < 0.0 and (gt != &"" or not targets.is_empty()):
		_draw_buds(t, s, k, breathe)

	# ---------- 牌型：台面上的彩色光晕（不用文字）----------
	if pulse:
		for pat in pulse.patterns:
			if pat.id == &"sym" or not PATTERN_BADGES.has(pat.id):
				continue
			var col: Color = PATTERN_BADGES[pat.id][1]
			for c in pat.cells:
				draw_colored_polygon(_proj_hex(c, 0.72, 0.01), Color(col, 0.22 + 0.08 * breathe))
		if pulse.total_mult > 1.0:
			var big := PackedVector2Array()
			var R := (board_radius() + 0.9) * Hex.SQRT3
			for i in 6:
				var ang := deg_to_rad(60.0 * i)
				big.append(_proj(Vector3(cos(ang) * R, 0.0, sin(ang) * R)))
			big.append(big[0])
			draw_polyline(big, Color(Palette.OCHRE, 0.35 + 0.2 * breathe), 2.0 * k, true)

	# ---------- 景观视图的地面编码：类别色光圈 + 末梢标记 + 立牌顶上的收获数 ----------
	var land_a := 1.0 - Fx.ease_in_out(_fold)
	if land_a > 0.02:
		for n: TreeNode in t.nodes.values():
			if n.is_seed():
				continue
			var col := Palette.card_color(n.def().color_key)
			var ring := _proj_hex(n.key, 0.74, 0.012)
			draw_colored_polygon(ring, Color(col, 0.20 * land_a))
			var ol := ring.duplicate()
			ol.append(ring[0])
			draw_polyline(ol, Color(col, 0.65 * land_a), 1.8 * k, true)
			var is_tip := pulse != null and pulse.tips.has(n.key)
			if is_tip:
				var tr := _proj_hex(n.key, 0.88, 0.012)
				tr.append(tr[0])
				draw_polyline(tr, Color(Palette.OCHRE, 0.85 * land_a), 2.6 * k, true)
				if anim_t < 0.0 and pulse.contrib.has(n.key) and n.key != hover:
					var top := _proj(_standee_top(n.key, standee_height(n)))
					_pill(top + Vector2(0, -9 * k), str(pulse.contrib[n.key]), int(12 * k),
						Color(Palette.TERRA.darkened(0.1), land_a), Color(Palette.SHEET, 0.9 * land_a))

	# ---------- 图解视图：旧版式的六边形牌片 ----------
	if _fold > 0.02:
		_draw_diagram(t, pulse, k, Fx.ease_in_out(_fold))

	# ---------- 节点：只画反馈与高亮，不画名字 ----------
	for n: TreeNode in t.nodes.values():
		var p := center_of(n.key)
		if node_pick.has(n.key):
			var hp := _proj_hex(n.key, 0.92, 0.01)
			for i in 6:
				draw_dashed_line(hp[i], hp[(i + 1) % 6], Palette.WATER, (3.5 if n.key == hover else 2.4) * k, 6.0 * k)
		if anim_t >= 0.0:
			if _anim_tips_done.has(n.key):
				var dt: float = anim_t - _anim_tips_done[n.key]
				var rise := minf(dt, 0.5) * 60.0 * k
				var glow_a := clampf(1.0 - dt * 2.5, 0.0, 1.0)
				if glow_a > 0.0:
					draw_circle(p, s * (0.7 + dt * 1.2), Color("#F2C46A", 0.32 * glow_a))
				_text_outlined(title, p + Vector2(0, -s * 1.1 - rise), "+%d" % pulse.contrib[n.key],
					int((22 + 8 * clampf(1.0 - dt * 3.0, 0.0, 1.0)) * k), Palette.TERRA)
		elif flash.has(n.key) and not tracing and n.key != hover:
			_text_outlined(body, p + Vector2(0, -s * 1.05), "+%d" % flash[n.key], int(15 * k), Color(Palette.TERRA, 0.85))
		if n.key == _blink and _blink_t > 0.0:
			var hp := _proj_hex(n.key, 1.0, 0.01)
			hp.append(hp[0])
			draw_polyline(hp, Color(Palette.OCHRE, _blink_t), 5.0 * k, true)

	# ---------- 悬停路径 ----------
	if tracing:
		_draw_trace3d(t, pulse, s, k, trace_reached)

	# ---------- 放置预览：末梢增减 ----------
	if anim_t < 0.0:
		for c in delta:
			var d: int = delta[c]
			if d == 0:
				continue
			var col := Palette.OLIVE.darkened(0.15) if d > 0 else Palette.TERRA.darkened(0.05)
			_pill(center_of(c) + Vector2(0, -s * 1.05), ("+%d" if d > 0 else "−%d") % absi(d), int(14 * k), col, Color(Palette.SHEET, 0.96))

	# ---------- 预览牌：从父牌连过来的虚线 + 名字 ----------
	if gt != &"" and anim_t < 0.0 and targets.has(hover) and Cards.has(gt):
		var def := Cards.get_def(gt)
		var gp := _proj(_wpos(hover, 0.1))
		var info = targets[hover]
		if info is Growth.Target:
			for par in info.parents:
				draw_dashed_line(_proj(_wpos(par, WOOD_Y)), gp, Color(Palette.INK, 0.6), 3.0 * k, 8.0 * k)
		_pill(_proj(_wpos(hover, 0.0)) + Vector2(0, s * 0.55), def.display_name, int(13 * k), Palette.INK, Color(Palette.SHEET, 0.92))

	# ---------- 悬停一张牌：信息卡 ----------
	if anim_t < 0.0 and hover != NO_CELL and t.has(hover) and not prune_mode and gt == &"":
		_draw_node_card(t.at(hover), pulse, k)



## 图解视图：每格一块六边形牌片（插画 + 类别色内框 + 牌名 + 效果 + 流出/收获），铺在台面上。
func _draw_diagram(t: TreeModel, pulse: Pulse.Result, k: float, a: float) -> void:
	var title := Palette.title()
	var body := Palette.body()
	for n: TreeNode in t.nodes.values():
		var c := n.key
		var p := _proj(_wpos(c, 0.02))
		var outer := _proj_hex(c, 0.9, 0.02)
		var v: int = pulse.out.get(c, 0) if pulse else 0
		# 投影
		var sh := PackedVector2Array()
		for q in outer:
			sh.append(q + Vector2(2.0, 3.0) * k)
		draw_colored_polygon(sh, Color(Palette.INK, 0.28 * a))
		if n.is_seed():
			draw_colored_polygon(outer, Color(Palette.INK, a))
			var ol := outer.duplicate()
			ol.append(outer[0])
			draw_polyline(ol, Color(Palette.GOLD, a), 2.0 * k, true)
			_text(title, p + Vector2(0, 7 * k), "种", int(22 * k), Color(Palette.CREAM, a))
			_text(body, p + Vector2(0, -13 * k), "输出", int(9 * k), Color(Palette.CREAM, 0.8 * a))
			_text(body, p + Vector2(0, 21 * k), str(v), int(12 * k), Color(Palette.GOLD.lightened(0.3), a))
			continue
		var def := n.def()
		var col := Palette.card_color(def.color_key)
		draw_colored_polygon(outer, Color(Palette.SHEET, a))
		var tex := CardArt.texture(def.art_id())
		if tex:
			var ts := tex.get_size()
			var side: float = ts.x * 0.98
			var src := Rect2((ts.x - side) * 0.5, ts.y * 0.26, side, side)
			var uvs := PackedVector2Array()
			for i in 6:
				var ang := deg_to_rad(60.0 * i - 30.0)
				var u := Vector2(cos(ang), sin(ang)) * 0.5 + Vector2(0.5, 0.5)
				uvs.append((src.position + u * src.size) / ts)
			var cols := PackedColorArray()
			for i in 6:
				cols.append(Color(1, 1, 1, 0.78 * a))
			draw_polygon(outer, cols, uvs, tex)
		var ol := outer.duplicate()
		ol.append(outer[0])
		draw_polyline(ol, Color(Palette.INK, 0.8 * a), 1.6 * k, true)
		var inner := _proj_hex(c, 0.76, 0.02)
		inner.append(inner[0])
		draw_polyline(inner, Color(col, a), 3.0 * k, true)
		var is_tip := pulse != null and pulse.tips.has(c)
		if is_tip:
			for i in 6:
				draw_dashed_line(outer[i], outer[(i + 1) % 6], Color(Palette.OCHRE, a), 2.2 * k, 6.0 * k)
		var fs := 17 if def.display_name.length() < 3 else 13
		var halo := Color(Palette.CREAM, a)
		_text_outlined(Palette.title_for(def.display_name), p + Vector2(0, 5 * k), def.display_name, int(fs * k), Color(Palette.INK, a), halo)
		_text_outlined(body, p + Vector2(0, -12 * k), Pulse.effect_text(def, n), int(10 * k), Color(col.darkened(0.25), a), halo)
		if is_tip and pulse.contrib.has(c):
			_text_outlined(body, p + Vector2(0, 20 * k), "收 %d" % pulse.contrib[c], int(11 * k), Color(Palette.TERRA, a), halo)
		else:
			_text_outlined(body, p + Vector2(0, 20 * k), str(v), int(11 * k), Color(Palette.INK, a), halo)
		if not n.marks.is_empty():
			var ms := "".join(n.marks.map(func(m): return Rules.MARKS[m].short))
			_text_outlined(title, p + Vector2(-hex_size * 0.55, hex_size * 0.5), ms, int(12 * k), Color(Palette.GOLD, a), halo)


## 悬停卡片：名字、类别、效果、本次流出 / 收获、年轮。
func _draw_node_card(n: TreeNode, pulse: Pulse.Result, k: float) -> void:
	var lines: Array = []   # [文本, 字号, 颜色, 字体]
	var body := Palette.body()
	var sk := maxf(1.0, k * 0.85)
	if n.is_seed():
		lines.append(["树心", int(20 * sk), Palette.INK, Palette.title()])
		lines.append(["每次脉动输出 %d" % (pulse.out.get(n.key, 0) if pulse else 0), int(14 * sk), Palette.SOFT, body])
	else:
		var def := n.def()
		var col := Palette.card_color(def.color_key)
		lines.append([def.display_name, int(20 * sk), Palette.INK, Palette.title_for(def.display_name)])
		if not def.family.is_empty():
			col = Palette.family_color(def.families()[0])
		lines.append([def.tag_line(), int(13 * sk), col.darkened(0.2), body])
		lines.append([Pulse.effect_text(def, n) + "　" + def.desc, int(13 * sk), Palette.SOFT, body])
		if pulse:
			if pulse.tips.has(n.key) and pulse.contrib.has(n.key):
				lines.append(["末梢收获 %d" % pulse.contrib[n.key], int(15 * sk), Palette.TERRA, body])
			else:
				lines.append(["流出 %d" % pulse.out.get(n.key, 0), int(15 * sk), Palette.INK, body])
		if not n.marks.is_empty():
			lines.append(["年轮：" + "、".join(n.marks.map(func(m): return Rules.mark_name(m))), int(13 * sk), Palette.GOLD.darkened(0.2), body])
	var w := 0.0
	var h := 14.0
	for l in lines:
		var f: Font = l[3]
		w = maxf(w, f.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1]).x)
		h += l[1] + 6.0
	w += 26.0
	var anchor := _proj(_wpos(n.key, standee_height(n) + 0.2))
	var rect := Rect2(anchor + Vector2(-w * 0.5, -h - 6.0), Vector2(w, h))
	rect.position.x = clampf(rect.position.x, 8.0, size.x - w - 8.0)
	rect.position.y = maxf(8.0, rect.position.y)
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(Palette.INK, 0.35))
	draw_rect(rect, Color(Palette.SHEET, 0.97))
	draw_rect(rect, Palette.INK, false, 1.5)
	draw_rect(rect.grow(-4), Color(Palette.GOLD, 0.6), false, 1.0)
	var y := rect.position.y + 8.0
	for l in lines:
		y += l[1]
		draw_string(l[3], Vector2(rect.position.x + 13.0, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1], l[2])
		y += 6.0


func _draw_trace3d(t: TreeModel, pulse: Pulse.Result, s: float, k: float, trace_reached: float) -> void:
	var w := 4.0 * k
	for x in _trace_nodes:
		var n := t.at(x)
		for ch in n.children:
			if not _trace_nodes.has(ch):
				continue
			var a := _proj(_wpos(x, WOOD_Y + 0.05))
			var b := _proj(_wpos(ch, WOOD_Y + 0.05))
			var lit := clampf(trace_reached - n.depth, 0.0, 1.0)
			draw_line(a, b, Color(Palette.GOLD, 0.35), w * 2.0, true)
			draw_line(a, a.lerp(b, lit), Color("#E9B65A", 0.95), w * 2.0, true)
			if lit > 0.0 and lit < 1.0:
				draw_circle(a.lerp(b, lit), 7.0 * k, Palette.GOLD)
				draw_circle(a.lerp(b, lit), 3.5 * k, Palette.SHEET)
	for x in _trace_nodes:
		var n := t.at(x)
		if trace_reached < n.depth:
			continue
		var label := _step_label(pulse, x)
		if label != "":
			_pill(center_of(x) + Vector2(0, -s * 1.05), label, int(13 * k), Palette.OLIVE.darkened(0.2), Color(Palette.SHEET, 0.96))
	if pulse and pulse.tips.has(trace_target) and trace_reached >= _trace_depth + 0.6:
		_pill(_proj(_wpos(trace_target, 0.0)) + Vector2(0, s * 0.7), "收获 %d" % pulse.contrib[trace_target], int(14 * k), Palette.TERRA.darkened(0.1), Color(Palette.SHEET, 0.96))
