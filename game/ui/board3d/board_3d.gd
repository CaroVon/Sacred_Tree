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
const WOOD_Y := 0.02          # 枝条离地高度（地块厚 0.14，枝条从侧面长出、在缝隙里拱起）
const LABEL_Y := 0.2          # 标注挂在地块顶面略上方
const POP_DUR := 0.42         # 立牌翻立的时长
## 图解视图（立牌折倒、铺开旧版式的六边形牌片）。
var diagram: bool = false
var _fold: float = 0.0

## 牌桌内容变化时（新放/剪掉的牌）是否播放翻立/折倒动画。
var animate_changes: bool = true

var _bg: TextureRect
var _bg_old: TextureRect
var _bg_id: StringName = &""
var _parallax: Vector2 = Vector2.ZERO
## 背景压暗一点，让牌桌和面板跳出来。
const BG_DIM := Color(0.86, 0.84, 0.82)
const BG_OVERSCAN := 1.05
var _view: TextureRect
var _vp: SubViewport
## 3D 视口像素 / 画布单位（窗口比 1920×1080 大时 > 1，保证 3D 画面清晰）。
var _px: float = 1.0
var _fill: DirectionalLight3D
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
var _ghost: MeshInstance3D
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
## 计分演出：末梢收获时是否在牌桌上画「+N」（季节界面改由飞向计数槽的数字表现，避免同一个数出现两次）。
var tip_numbers := true
## 计分演出的单项特效：格子闪光、镜头推近、全屏闪光。
var _cell_flash: Array = []          # [cells, color, t, dur]
var _cam_punch: float = 0.0
var _sflash: float = 0.0
var _sflash_col: Color = Color.WHITE
var _next_bolt: float = 3.0


static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


class Piece:
	var node: Node3D
	## 地块本体（树心是树墩，没有 mat）。
	var body: Node3D
	var mat: ShaderMaterial
	var type: StringName
	var pop_t: float = -1.0      # 落下进度（<0 = 不在落下）
	var bounce_t: float = -1.0   # 脉动末梢的弹跳
	var leave_t: float = 0.0
	var lift: float = 0.0        # 悬停抬起（平滑）
	var tint: Color = Color.WHITE
	var glow: float = 0.0


## 地块：外接圆半径、厚度、倒角。格距 √3，留出缝隙让枝干露出来。
const TILE_R := 0.82
const TILE_H := 0.14
const TILE_BEVEL := 0.035


# ======================================================================
# 搭场景
# ======================================================================

func _ready() -> void:
	super._ready()
	show_labels = false
	# 背景：每季一幅神殿庭院（换季时交叉淡入），随鼠标轻微视差
	for i in 2:
		var b := TextureRect.new()
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.show_behind_parent = true
		b.modulate = BG_DIM
		add_child(b)
		move_child(b, 0)
		if i == 0:
			_bg = b
		else:
			_bg_old = b
	_bg.texture = CardArt.texture(&"board_bg")
	_bg_old.visible = false

	# 3D 视口按窗口的真实像素渲染（不再按 1920×1080 画布渲染后缩放），再由 TextureRect 画回画布
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.use_debanding = true
	_vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
	_vp.own_world_3d = true
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.show_behind_parent = true
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_view)
	# 绘制顺序：背景 → 旧背景（淡出中）→ 3D 视口
	move_child(_bg, 0)
	move_child(_bg_old, 1)
	move_child(_view, 2)

	_world = Node3D.new()
	_vp.add_child(_world)
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#D9D2C4")
	_env.ambient_light_energy = 0.28
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.05
	_env.tonemap_white = 6.0
	# 只让真正的高光（脉动金光、传说金框）溢出一点光晕
	_env.glow_enabled = true
	_env.glow_intensity = 0.55
	_env.glow_strength = 0.9
	_env.glow_bloom = 0.0
	_env.glow_hdr_threshold = 1.1
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = _env
	_world.add_child(we)
	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-52, -38, 0)
	_light.light_color = Color("#FFF7EA")
	_light.light_energy = 0.9
	# 真实的柔和阴影：地块、枝干、树墩都投影到石台上
	_light.shadow_enabled = true
	_light.shadow_bias = 0.02
	_light.shadow_normal_bias = 1.0
	_light.shadow_opacity = 0.7
	_light.shadow_blur = 1.6
	_light.light_angular_distance = 0.0
	_light.directional_shadow_max_distance = 40.0
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_world.add_child(_light)
	# 补光：从镜头一侧打来的冷色弱光，让背光面不发死
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-30, 150, 0)
	_fill.light_color = Color("#C9D6E8")
	_fill.light_energy = 0.25
	_fill.shadow_enabled = false
	_world.add_child(_fill)
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
	_motes.amount = 16
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
	# [主光色, 主光强, 俯角, 方位, 环境光色, 环境光强, 台面色调, 补光色, 补光强, 曝光]
	# 春晨清亮、夏午高光、秋暮斜阳、冬月冷光、天灾季昏沉
	var m: Array
	match season:
		1: m = [Color("#FFF6E6"), 0.92, -48.0, -40.0, Color("#DCE6DA"), 0.30, Color(0.96, 1.02, 0.95), Color("#CFE0F0"), 0.28, 1.05]
		2: m = [Color("#FFF0D2"), 1.0, -66.0, -20.0, Color("#EDE2CC"), 0.30, Color(1.04, 1.0, 0.92), Color("#D6E2EE"), 0.22, 1.08]
		3: m = [Color("#FFC98E"), 0.95, -30.0, -62.0, Color("#E6CDB2"), 0.26, Color(1.06, 0.95, 0.84), Color("#B8C8E0"), 0.30, 1.02]
		4: m = [Color("#D2E0F4"), 0.80, -40.0, -120.0, Color("#C8D2E0"), 0.34, Color(0.90, 0.95, 1.04), Color("#9FB4D8"), 0.30, 1.0]
		_: m = [Color("#F0C2A0"), 0.78, -42.0, -30.0, Color("#C9B8B0"), 0.24, Color(0.96, 0.88, 0.84), Color("#A090B0"), 0.25, 0.95]
	var tint: Color = m[6]
	_light.light_color = m[0]
	_base_energy = m[1]
	_light.light_energy = _base_energy
	_light.rotation_degrees = Vector3(m[2], m[3], 0)
	_env.ambient_light_color = m[4]
	_env.ambient_light_energy = m[5]
	_fill.light_color = m[7]
	_fill.light_energy = m[8]
	_env.tonemap_exposure = m[9]
	match _calamity:
		&"drought":
			_light.light_color = Color("#FFB870")
			tint = Color(1.10, 0.92, 0.74)
		&"eclipse":
			_base_energy *= 0.45
			_light.light_energy = _base_energy
			_env.ambient_light_color = Color("#8C86A8")
			tint = Color(0.82, 0.82, 0.92)
		&"wildfire":
			_light.light_color = Color("#FF9A60")
			tint = Color(1.06, 0.86, 0.78)
		&"flood":
			_light.light_color = Color("#C8D8E8")
			tint = Color(0.88, 0.94, 1.02)
	_set_backdrop(StringName("bg_calamity") if season >= 5 else StringName("bg_" + ["spring", "summer", "autumn", "winter"][clampi(season, 1, 4) - 1]))
	_ground_mat.set_shader_parameter("season_tint", tint)
	for lm in _land_mats:
		lm.set_shader_parameter("season_tint", tint)
	_build_weather()


## 换背景：旧图留在上层淡出。
func _set_backdrop(id: StringName) -> void:
	if id == _bg_id or not CardArt.has(id):
		return
	var first := _bg_id == &""
	_bg_id = id
	_bg_old.texture = _bg.texture
	_bg.texture = CardArt.texture(id)
	if first or Game.reduce_motion:
		_bg_old.visible = false
		return
	_bg_old.visible = true
	_bg_old.modulate = BG_DIM
	var tw := _bg_old.create_tween()
	tw.tween_property(_bg_old, "modulate:a", 0.0, 1.2)
	tw.tween_callback(func(): _bg_old.visible = false)


func _build_weather() -> void:
	if _weather:
		_weather.queue_free()
		_weather = null
	if Game.reduce_motion:
		return
	_weather = Node3D.new()
	_world.add_child(_weather)
	# 季节粒子（天灾季叠在天灾天气下面，用较淡的一层）
	var calm := 0.5 if _calamity != &"" else 1.0
	match clampi(_season, 1, 5):
		1:  # 春：粉白花瓣缓缓飘落 + 花粉
			_particles(int(26 * calm), 9.0, Vector3(10, 0.5, 8), Vector3(0, 4.0, -1), Vector3(0.4, -1, 0.1), 25.0,
				Vector3(0.05, -0.12, 0), 0.15, 0.4, 0.6, 1.1, Color("#F4C9CF"), 0.85, Vector2(0.14, 0.09))
			_particles(int(18 * calm), 7.0, Vector3(9, 1.5, 7), Vector3(0, 1.4, 0), Vector3(0, 1, 0), 180.0,
				Vector3.ZERO, 0.03, 0.1, 0.4, 0.8, Color("#FFF2B8"), 0.7, Vector2(0.05, 0.05))
		2:  # 夏：萤火虫在台面上方游荡（发光，触发辉光）
			_particles(int(22 * calm), 6.0, Vector3(9, 0.9, 7), Vector3(0, 1.0, 0), Vector3(0, 1, 0), 180.0,
				Vector3.ZERO, 0.08, 0.25, 0.6, 1.0, Color(2.4, 2.0, 0.8), 1.0, Vector2(0.07, 0.07))
		3:  # 秋：橙红落叶打着旋
			_particles(int(22 * calm), 8.0, Vector3(10, 0.5, 8), Vector3(0, 4.0, -1), Vector3(0.6, -1, 0), 30.0,
				Vector3(0.1, -0.25, 0), 0.2, 0.5, 0.8, 1.4, Color("#D9783A"), 0.95, Vector2(0.16, 0.10))
		4:  # 冬：细雪
			_particles(int(70 * calm), 7.0, Vector3(11, 0.5, 9), Vector3(0, 4.5, -1), Vector3(0.1, -1, 0), 10.0,
				Vector3(0, -0.3, 0), 0.25, 0.5, 0.4, 1.0, Color("#F4F7FF"), 0.9, Vector2(0.06, 0.06))
	if _calamity == &"":
		return
	match _calamity:
		&"pests":
			# 虫害：成团乱飞的小黑虫
			_particles(60, 3.0, Vector3(7, 0.8, 6), Vector3(0, 0.9, 0), Vector3(0, 1, 0), 180.0,
				Vector3.ZERO, 0.6, 1.4, 0.5, 0.9, Color(0.16, 0.14, 0.12), 0.9, Vector2(0.08, 0.08))
		&"drought":
			# 干旱：缓缓上升的热浪尘
			_particles(40, 4.0, Vector3(9, 0.1, 8), Vector3(0, 0.1, 0), Vector3(0, 1, 0), 15.0,
				Vector3(0, 0.15, 0), 0.2, 0.5, 1.0, 2.2, Color(1.0, 0.78, 0.45), 0.35, Vector2(0.08, 0.08))
		&"wildfire":
			# 山火：发光的余烬向上飘 + 低处的烟
			_particles(55, 3.5, Vector3(9, 0.2, 7), Vector3(0, 0.2, 0), Vector3(0.2, 1, 0), 25.0,
				Vector3(0.1, 0.4, 0), 0.4, 1.0, 0.5, 1.0, Color(3.0, 1.2, 0.3), 1.0, Vector2(0.06, 0.06))
			_particles(16, 6.0, Vector3(9, 0.3, 7), Vector3(0, 1.5, 0), Vector3(0.3, 1, 0), 20.0,
				Vector3(0.1, 0.08, 0), 0.2, 0.4, 3.0, 5.0, Color(0.25, 0.2, 0.18), 0.22, Vector2(0.1, 0.1))
		&"flood", &"lightning":
			# 洪水 / 雷击：斜落的雨丝；雷击另有间歇闪光（在 _process 里）
			_particles(160 if _calamity == &"flood" else 110, 0.9, Vector3(11, 0.5, 9), Vector3(0, 5.0, -1), Vector3(0.15, -1, 0), 3.0,
				Vector3(0, -9.0, 0), 6.0, 8.0, 1.0, 1.0, Color(0.75, 0.82, 0.95), 0.45, Vector2(0.015, 0.4))
			if _calamity == &"lightning":
				_particles(20, 5.0, Vector3(9, 0.5, 8), Vector3(0, 2.4, 0), Vector3(1, 0, 0), 10.0,
					Vector3.ZERO, 0.5, 1.0, 2.0, 4.0, Color(0.35, 0.38, 0.45), 0.18, Vector2(0.1, 0.1))
		&"gale":
			# 大风：横扫的风线 + 被卷走的叶子
			_particles(60, 1.2, Vector3(1, 1.2, 8), Vector3(-10, 1.0, 0), Vector3(1, 0, 0), 4.0,
				Vector3.ZERO, 12.0, 16.0, 1.0, 1.0, Color(0.95, 0.95, 0.9), 0.25, Vector2(0.6, 0.012))
			_particles(26, 2.0, Vector3(1, 1.0, 8), Vector3(-10, 1.0, 0), Vector3(1, 0.1, 0), 15.0,
				Vector3.ZERO, 7.0, 10.0, 0.8, 1.3, Color("#8A9A50"), 0.9, Vector2(0.14, 0.09))
		&"eclipse":
			# 日蚀：稀疏飘浮的暗紫尘
			_particles(30, 8.0, Vector3(9, 1.5, 8), Vector3(0, 1.5, 0), Vector3(0, 1, 0), 180.0,
				Vector3.ZERO, 0.05, 0.15, 1.0, 2.0, Color(0.45, 0.4, 0.7), 0.4, Vector2(0.1, 0.1))


## 一层天气粒子。col 的分量可以 > 1（发光，触发辉光）。quad：粒子的宽高（世界单位）。
func _particles(amount: int, life: float, box: Vector3, pos: Vector3, dir: Vector3, spread: float, grav: Vector3,
		vmin: float, vmax: float, smin: float, smax: float, col: Color, alpha: float, quad: Vector2) -> void:
	if amount <= 0:
		return
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.position = pos
	p.direction = dir
	p.spread = spread
	p.gravity = grav
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	# 花瓣、叶子（略扁的粒子）打旋；雨丝、风线（细长）保持方向
	var leafy := quad.x != quad.y and maxf(quad.x, quad.y) < minf(quad.x, quad.y) * 3.0
	p.angle_max = 360.0 if leafy else 0.0
	p.angular_velocity_min = -90.0 if leafy else 0.0
	p.angular_velocity_max = 90.0 if leafy else 0.0
	var q := QuadMesh.new()
	q.size = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _dot_texture()
	q.material = m
	p.mesh = q
	p.color_ramp = _fade_ramp(col, alpha)
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
	# 新流派的牌没有立牌时用流派色徽记（整张图版立起来不像立牌）；木系老牌仍可退回图版
	var def := Cards.get_def(id)
	if t == null and def != null and def.family.is_empty():
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
	return 0.5 if n.is_seed() else TILE_H + 0.04


# ======================================================================
# 相机与坐标
# ======================================================================

func _layout() -> void:
	if _cam == null:
		return
	_px = clampf(get_viewport().get_final_transform().get_scale().x, 0.5, 2.0) if is_inside_tree() else 1.0
	_vp.size = Vector2i(maxi(2, int(size.x * _px)), maxi(2, int(size.y * _px)))
	_fit_radius = board_radius()
	_ground_mat.set_shader_parameter("radius", float(_fit_radius))
	_fit_camera()
	_clamp_pan()
	_apply_view()
	if tree != null and size.x > 20.0:
		_auto_frame(tree, true)


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
	var o := _cam.project_ray_origin(p * _px)
	var d := _cam.project_ray_normal(p * _px)
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
	_user_view = false
	if _cam:
		_apply_view()


func _clamp_pan() -> void:
	# 放大后允许平移到牌桌边缘（再多留一格，给不对称的边距——例如集市右侧的大面板——留余地）
	var lim := (board_radius() + 2.0) * Hex.SQRT3 * (1.0 - 1.0 / zoom)
	if pan.length() > lim:
		pan = pan.normalized() * lim if lim > 0.0 else Vector2.ZERO


## 缩放/平移输入：滚轮或 Ctrl+滚轮（触控板捏合）缩放；触控板双指滑动、右键/中键拖动平移；
## 双击右键复位。处理了返回 true。
func _view_input(e: InputEvent) -> bool:
	if e is InputEventMagnifyGesture or e is InputEventPanGesture or (e is InputEventMouseButton and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]):
		_user_view = true
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
		for y: float in [0.0, 0.5]:
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
	return _cam.unproject_position(w) / _px


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
	var o := _cam.project_ray_origin(p * _px)
	var d := _cam.project_ray_normal(p * _px)
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
	_auto_frame(t)
	_sync3d()


## 玩家没手动缩放过时，镜头自动框住整棵树：树小时放大一点，并把树放在画面中央。
var _user_view := false


func _auto_frame(t: TreeModel, force: bool = false) -> void:
	if _user_view or t == null or _cam == null or not auto_frame:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var far := 0
	for k in t.nodes:
		var w := _wpos(k)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
		far = maxi(far, Hex.distance(k, Vector2i.ZERO))
	var extent := float(far) + 2.0
	var z := clampf((board_radius() + 1.0) / (extent - 0.4), 1.0, AUTO_ZOOM_MAX)
	var c := (lo + hi) * 0.5 if z > 1.001 else Vector2.ZERO
	if not force and absf(z - zoom) < 0.04 and c.distance_to(pan) < 0.3:
		return
	zoom = z
	pan = c
	_clamp_pan()
	_apply_view()
	# 再按屏幕微调：让树的中心正好落在可用区域（margins 之内）的中央
	if z > 1.001:
		var want := Vector2(margins.x + (size.x - margins.x - margins.z) * 0.5, margins.y + (size.y - margins.y - margins.w) * 0.5)
		var mid3 := Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
		for i in 3:
			var got := _proj(mid3)
			var g0 := _ground_at(want)
			var g1 := _ground_at(got)
			pan += Vector2(g1.x - g0.x, g1.z - g0.z)
			_clamp_pan()
			_apply_view()


## 自动取景的最大放大倍数；设为 false 可关掉（集市等场景）。
const AUTO_ZOOM_MAX := 1.5
var auto_frame := true


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
		# 新地块有专属贴图时直接用，没有就借沃土贴图染色
		var own: StringName = Land.ART.get(lt, &"")
		if own != &"" and CardArt.has(own):
			art = own
			tint = Color.WHITE
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
		m.set_shader_parameter("opacity", 0.92)
		m.render_priority = -20
		_land_mats.append(m)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.70, 1.70)
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
				sm.radial_segments = 14
				sm.rings = 7
				rk.mesh = sm
				rk.material_override = _mat(&"rock3d", func():
					var rmat := StandardMaterial3D.new()
					rmat.albedo_color = Palette.STONE.darkened(0.15)
					rmat.roughness = 0.95
					var nt := NoiseTexture2D.new()
					var fn := FastNoiseLite.new()
					fn.frequency = 0.08
					nt.noise = fn
					nt.seamless = true
					nt.as_normal_map = true
					nt.bump_strength = 4.0
					rmat.normal_enabled = true
					rmat.normal_texture = nt
					return rmat)
				var a := TAU * (i / 3.0) + c.x
				rk.position = _wpos(c, rr * 0.2) + Vector3(cos(a), 0, sin(a)) * 0.36
				rk.scale = Vector3(1.15, 0.6, 0.9)
				rk.rotation.y = a
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
				_burst(pc.node.position + Vector3(0, 0.3, 0), Color(Palette.OLIVE, 0.9), 14, 1.6)
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
		_pieces[n.key] = pc
	_drop_pending.clear()


func _make_piece(n: TreeNode) -> Piece:
	var pc := Piece.new()
	pc.type = n.type
	pc.node = Node3D.new()
	if n.is_seed():
		pc.body = _stump()
	else:
		var mi := make_tile(n.type)
		pc.mat = mi.get_surface_override_material(0)
		pc.body = mi
	pc.node.add_child(pc.body)
	return pc


## 一张牌的地块：厚纸板六棱柱，顶面印插画，侧面是流派色的纸边。
static func make_tile(id: StringName) -> MeshInstance3D:
	var def := Cards.get_def(id)
	var mi := MeshInstance3D.new()
	mi.mesh = _cached_mesh(&"tile", func(): return HexMesh.prism(TILE_R, 0.0, TILE_H, Rect2(0, 0, 1, 1), HexMesh.POINTY, 0.0, TILE_BEVEL))
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/board3d/tile.gdshader")
	# 顶面平印牌面插画的主体部分（与图解视图同样的取景：上部偏中的方形）
	var tex: Texture2D = CardArt.texture(def.art_id()) if def else null
	m.set_shader_parameter("art", tex)
	m.set_shader_parameter("has_art", tex != null)
	if tex:
		var ts := tex.get_size()
		var side: float = ts.x * 0.96
		m.set_shader_parameter("uv_rect", Vector4((ts.x - side) * 0.5 / ts.x, ts.y * 0.2 / ts.y, side / ts.x, side / ts.y))
	var col := Palette.OLIVE
	var rar := 0
	if def:
		col = Palette.family_color(def.families()[0]) if not def.family.is_empty() else Palette.card_color(def.color_key)
		rar = clampi(def.rarity, 0, 2)
	m.set_shader_parameter("paper", Palette.SHEET.darkened(0.16).lerp(col, 0.3))
	m.set_shader_parameter("frame", col.darkened(0.35))
	m.set_shader_parameter("rarity", rar)
	mi.set_surface_override_material(0, m)
	mi.set_surface_override_material(1, _flat(StringName("tile_side_%s" % col.to_html()), col.darkened(0.25)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


## 树心：一截带年轮的树墩，根须向四周伸进石台。
func _stump() -> Node3D:
	var root := Node3D.new()
	var bark := _bark_mat()
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.62
	cm.height = 0.5
	cm.radial_segments = 28
	cm.rings = 2
	trunk.mesh = cm
	trunk.position.y = 0.25
	trunk.material_override = bark
	root.add_child(trunk)
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.47
	tm.bottom_radius = 0.47
	tm.height = 0.02
	tm.radial_segments = 28
	top.mesh = tm
	top.position.y = 0.505
	top.material_override = _mat(&"rings", func():
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """shader_type spatial;
uniform vec4 wood : source_color = vec4(0.80, 0.64, 0.44, 1.0);
uniform vec4 ring : source_color = vec4(0.52, 0.36, 0.22, 1.0);
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p) + 0.03 * sin(atan(p.y, p.x) * 5.0);
	float r = smoothstep(0.35, 0.5, abs(fract(d * 7.0) - 0.5));
	vec3 c = mix(ring.rgb, wood.rgb, r);
	c = mix(c, ring.rgb * 0.7, smoothstep(0.9, 1.0, length(p)));
	ALBEDO = c;
	ROUGHNESS = 0.8;
}"""
		m.shader = sh
		return m)
	root.add_child(top)
	# 树根张开的裙边：下宽上窄的一圈，像树干扎进石台
	var skirt := MeshInstance3D.new()
	var sk := CylinderMesh.new()
	sk.top_radius = 0.55
	sk.bottom_radius = 0.8
	sk.height = 0.12
	sk.radial_segments = 28
	skirt.mesh = sk
	skirt.position.y = 0.06
	skirt.material_override = bark
	root.add_child(skirt)
	# 神树之心：树墩上方一颗发光的种子
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 24
	sm.rings = 12
	orb.mesh = sm
	orb.position.y = 0.72
	orb.name = "Orb"
	orb.material_override = _mat(&"heart_orb", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#F6D27A")
		m.emission_enabled = true
		m.emission = Color("#FFC860")
		m.emission_energy_multiplier = 1.6
		m.roughness = 0.3
		return m)
	root.add_child(orb)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


static func _bark_mat() -> Material:
	return _mat(&"bark3d", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#7A5C40")
		m.roughness = 0.88
		var nt := NoiseTexture2D.new()
		var fn := FastNoiseLite.new()
		fn.frequency = 0.04
		fn.fractal_octaves = 3
		nt.noise = fn
		nt.width = 128
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		m.normal_enabled = true
		m.normal_texture = nt
		m.normal_scale = 0.8
		m.uv1_scale = Vector3(2.0, 1.0, 1.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)


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
	return _wpos(k, h)


## 木质枝条：从父格到子格的平滑拱形树枝（从地块侧面长出、在缝隙里露出），粗细随深度递减；
## 嫁接边是带金光的细藤。脉动时一层金光从父端往子端生长。
func _sync_wood(t: TreeModel) -> void:
	for ch in _wood_root.get_children():
		ch.queue_free()
	_glows.clear()
	var bark := _bark_mat()
	var vine := _mat(&"vine3d", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Palette.GOLD.lerp(Palette.OLIVE, 0.2).lightened(0.15)
		m.roughness = 0.5
		m.metallic = 0.2
		m.emission_enabled = true
		m.emission = Palette.GOLD
		m.emission_energy_multiplier = 0.25
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)
	var glow := _mat(&"wood_glow3d", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.82, 0.45, 0.85)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color("#FFC860")
		m.emission_energy_multiplier = 3.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)
	for n: TreeNode in t.nodes.values():
		for ch in n.children:
			var child := t.at(ch)
			var graft := child != null and not child.is_seed() and child.def().is_graft()
			var a := _wpos(n.key, WOOD_Y)
			var b := _wpos(ch, WOOD_Y)
			var L := a.distance_to(b)
			var holder := Node3D.new()
			_wood_root.add_child(holder)
			holder.position = a
			holder.look_at(b, Vector3.UP)
			var r0 := _wood_r(n.depth) if not graft else 0.06
			var r1 := _wood_r(n.depth + 1) if not graft else 0.05
			var key := StringName("tube_%d_%s" % [n.depth, graft])
			var mesh := _cached_mesh(key, func(): return TubeMesh.arch(Hex.SQRT3, r0, r1, 0.07 if not graft else 0.13, 14, 10))
			var tube := MeshInstance3D.new()
			tube.mesh = mesh
			tube.material_override = vine if graft else bark
			tube.scale = Vector3(1, 1, L / Hex.SQRT3)
			tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			holder.add_child(tube)
			var gh := Node3D.new()
			holder.add_child(gh)
			var gm := MeshInstance3D.new()
			gm.mesh = mesh
			gm.scale = Vector3(1.45, 1.3, L / Hex.SQRT3)
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
	return maxf(0.05, 0.10 * pow(0.9, float(depth)))


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
	# 窗口缩放改变了真实像素比：重新按真实像素渲染
	if absf(get_viewport().get_final_transform().get_scale().x - _px) > 0.01 and _px < 1.999 and _px > 0.501:
		_layout()
	# 背景视差：随鼠标反向轻移
	var m := get_local_mouse_position() / size - Vector2(0.5, 0.5) if size.x > 0.0 else Vector2.ZERO
	var want := -m.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * size * (BG_OVERSCAN - 1.0) if motion else Vector2.ZERO
	_parallax = _parallax.lerp(want, 1.0 - exp(-dt * 3.0))
	for b in [_bg, _bg_old]:
		b.size = size * BG_OVERSCAN
		b.position = -size * (BG_OVERSCAN - 1.0) * 0.5 + _parallax
	var anim := is_animating()
	if _was_animating and not anim:
		_sync3d()
	_was_animating = anim
	# 镜头震动
	var sh := Fx.shake_offset(shake_t, 0.05 * shake_amp)
	if _cam_punch > 0.0:
		_cam_punch = maxf(0.0, _cam_punch - dt * 0.35)
		_place_cam(_cam_d / zoom * (1.0 - Fx.ease_out(minf(1.0, _cam_punch * 10.0)) * _cam_punch), 0.0, 0.0, Vector3(pan.x, 0.0, pan.y))
	_cam.h_offset = _ho / zoom + sh.x
	_cam.v_offset = _vo / zoom + sh.y
	if not _cell_flash.is_empty() or _sflash > 0.0 or _wave_t >= 0.0:
		for f in _cell_flash:
			f[2] += dt
		_cell_flash = _cell_flash.filter(func(f): return f[2] < f[3])
		_sflash = maxf(0.0, _sflash - dt * 2.5)
		if _wave_t >= 0.0:
			_wave_t += dt
			if _wave_t > 0.9:
				_wave_t = -1.0
		queue_redraw()
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
	# 神树之心：轻轻浮动；脉动开始时一下子亮起、胀大
	var sp: Piece = _pieces.get(Vector2i.ZERO)
	if sp and sp.body:
		var orb := sp.body.get_node_or_null("Orb") as MeshInstance3D
		if orb:
			orb.position.y = 0.72 + (0.04 * sin(_clock * 1.8) if motion else 0.0)
			var burst := 0.0
			if anim_t >= 0.0:
				burst = 1.0 - clampf(anim_t / 0.6, 0.0, 1.0)
			orb.scale = Vector3.ONE * (1.0 + 0.7 * burst)
			var om := orb.material_override as StandardMaterial3D
			om.emission_energy_multiplier = 1.6 + 6.0 * burst + (0.4 * sin(_clock * 2.0) if motion else 0.0)
	# 末梢收获：立牌弹一下 + 金屑
	if anim_t >= 0.0:
		for k in _anim_tips_done:
			if not _tip_fx.has(k):
				_tip_fx[k] = true
				if _pieces.has(k):
					_pieces[k].bounce_t = 0.0
					_burst(_wpos(k, 0.7), Color("#F2C46A"), 16, 2.4)
	# 地块：落下、脉动弹跳、悬停抬起、剪枝染红、路径以外压暗
	var tracing := trace_target != NO_CELL and anim_t < 0.0 and not _trace_nodes.is_empty()
	_fold = move_toward(_fold, 1.0 if diagram else 0.0, dt * 4.0) if motion else (1.0 if diagram else 0.0)
	var fold_e := Fx.ease_in_out(_fold)
	var smooth := 1.0 - exp(-dt * 14.0) if motion else 1.0
	for k in _pieces:
		var pc: Piece = _pieces[k]
		var y := 0.0
		var scl := 1.0
		if pc.pop_t >= 0.0:
			pc.pop_t += dt / POP_DUR
			var t := minf(pc.pop_t, 1.0)
			# 从半空落下，落地时压扁一下再弹回
			y += 1.4 * (1.0 - Fx.ease_in_out(minf(t * 1.4, 1.0)))
			scl = lerpf(0.75, 1.0, Fx.back_out(t))
			if pc.pop_t >= 1.0:
				pc.pop_t = -1.0
				_burst(_wpos(k, 0.05), Color(Palette.CREAM.darkened(0.12), 0.9), 18, 1.4)
				Fx.shake(self, 0.8, 0.18)
		if pc.bounce_t >= 0.0:
			pc.bounce_t += dt / 0.38
			var t := minf(pc.bounce_t, 1.0)
			y += 0.32 * sin(t * PI)
			scl *= 1.0 + 0.12 * sin(t * PI)
			pc.glow = maxf(pc.glow, 1.0 - t)
			if pc.bounce_t >= 1.0:
				pc.bounce_t = -1.0
		var hot: bool = k == hover and not prune_mode and anim_t < 0.0
		pc.lift = lerpf(pc.lift, 0.10 if hot else 0.0, smooth)
		pc.glow = maxf(0.0, pc.glow - dt * 2.0) if motion else 0.0
		pc.body.position.y = y + pc.lift
		pc.body.scale = Vector3.ONE * scl
		pc.body.visible = fold_e < 0.98
		var col := Color.WHITE
		var is_seed := tree != null and tree.has(k) and tree.at(k).is_seed()
		if highlight.has(k) or (prune_mode and k == hover and not is_seed):
			col = Color(1.0, 0.55, 0.5)
		elif tracing and not _trace_nodes.has(k):
			col = Color(0.55, 0.55, 0.58)
		if pc.mat:
			pc.tint = pc.tint.lerp(col, smooth)
			pc.mat.set_shader_parameter("modulate", pc.tint)
			pc.mat.set_shader_parameter("glow", maxf(pc.glow * 2.0, 0.6 if hot else 0.0))
	for i in range(_leaving.size() - 1, -1, -1):
		var pc := _leaving[i]
		pc.leave_t += dt / 0.4
		var t := minf(pc.leave_t, 1.0)
		pc.body.position.y = 0.6 * sin(t * PI)
		pc.body.rotation.z = t * 1.2
		pc.body.scale = Vector3.ONE * maxf(0.01, 1.0 - t * 0.9)
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


## 预览地块：悬停可放置格时，一块半透明的地块浮在格子上方。
var _ghost_mat: ShaderMaterial


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
		var mi := make_tile(gt)
		_ghost_mat = mi.get_surface_override_material(0)
		_ghost_mat.set_shader_parameter("glow", 0.8)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost = mi
		_ghost_type = gt
		_piece_root.add_child(_ghost)
	_ghost.visible = true
	var bob := 0.04 * sin(_clock * 3.0) if not Game.reduce_motion else 0.0
	_ghost.position = _wpos(hover, 0.22 + bob)


## 计分演出：一组格子亮起（牌型），地块发光、弹一下并迸出彩屑。
func flash_cells(cells: Array, col: Color, dur: float = 0.8) -> void:
	if Game.reduce_motion:
		return
	_cell_flash.append([cells, col, 0.0, dur])
	for c in cells:
		if _pieces.has(c):
			var pc: Piece = _pieces[c]
			pc.bounce_t = 0.0
			pc.glow = 1.0
			if pc.mat:
				pc.mat.set_shader_parameter("glow_color", col.lightened(0.2))
		_burst(_wpos(c, 0.3), col.lightened(0.3), 8, 1.8)


## 镜头猛地推近一点再弹回（amount = 推近的比例，0.05 = 5%）。
func punch_camera(amount: float) -> void:
	if Game.reduce_motion:
		return
	_cam_punch = maxf(_cam_punch, amount)


## 全屏闪一下（大额脉动）。
func flash_screen(col: Color, strength: float = 1.0) -> void:
	if Game.reduce_motion:
		return
	_sflash = strength
	_sflash_col = col


## 一圈金色冲击波从树心扩散（大额脉动）。
func shockwave(col: Color) -> void:
	if Game.reduce_motion:
		return
	_wave_t = 0.0
	_wave_col = col
	_burst(_wpos(Vector2i.ZERO, 0.6), col.lightened(0.3), 40, 4.5)


var _wave_t: float = -1.0
var _wave_col: Color = Color.WHITE


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

	# ---------- 雷击闪光 / 大额脉动的全屏闪光 ----------
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.92, 0.95, 1.0, 0.22 * _flash))
	if _sflash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(_sflash_col, 0.45 * _sflash * _sflash))
	# ---------- 冲击波：从树心扩散的一圈六边形光环 ----------
	if _wave_t >= 0.0:
		var wr := 0.6 + Fx.ease_out(_wave_t / 0.9) * (board_radius() + 1.5) * Hex.SQRT3
		var ring := PackedVector2Array()
		for i in 7:
			var ang := deg_to_rad(60.0 * i - 30.0)
			ring.append(_proj(Vector3(cos(ang) * wr, 0.05, sin(ang) * wr)))
		draw_polyline(ring, Color(_wave_col, 0.9 * (1.0 - _wave_t / 0.9)), 10.0 * k * (1.0 - _wave_t / 0.9) + 2.0, true)
	# ---------- 牌型逐个点亮 ----------
	for f in _cell_flash:
		var fa: float = 1.0 - f[2] / f[3]
		for c in f[0]:
			var hp := _proj_hex(c, 0.95, 0.16)
			draw_colored_polygon(hp, Color(f[1], 0.38 * fa))
			hp.append(hp[0])
			draw_polyline(hp, Color(f[1].lightened(0.3), 0.95 * fa), 4.0 * k, true)

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

	# ---------- 末梢：地块外一圈细细的赭色描边（收获数字只在脉动和悬停时出现）----------
	var land_a := 1.0 - Fx.ease_in_out(_fold)
	if land_a > 0.02 and pulse != null and anim_t < 0.0:
		for key in pulse.tips:
			if not t.has(key) or t.at(key).is_seed():
				continue
			var tr := _proj_hex(key, 0.84, 0.01)
			tr.append(tr[0])
			draw_polyline(tr, Color(Palette.OCHRE.lightened(0.15), 0.7 * land_a), 2.0 * k, true)

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
				if tip_numbers:
					_text_outlined(title, p + Vector2(0, -s * 1.1 - rise), "+%s" % Pulse.big(pulse.contrib[n.key]),
						int((22 + 8 * clampf(1.0 - dt * 3.0, 0.0, 1.0)) * k), Palette.TERRA)
		elif flash.has(n.key) and not tracing and n.key != hover:
			_text_outlined(body, p + Vector2(0, -s * 1.05), "+%s" % Pulse.big(flash[n.key]), int(15 * k), Color(Palette.TERRA, 0.85))
		if n.key == _blink and _blink_t > 0.0:
			var hp := _proj_hex(n.key, 1.0, 0.01)
			hp.append(hp[0])
			draw_polyline(hp, Color(Palette.OCHRE, _blink_t), 5.0 * k, true)

	# ---------- 警示：将枯萎 / 刚被天灾打中 ----------
	if anim_t < 0.0:
		for c in warn:
			var wp := _proj_hex(c, 0.95, 0.015)
			wp.append(wp[0])
			draw_polyline(wp, Color(Palette.TERRA, 0.55 + 0.35 * breathe), 3.0 * k, true)
			_pill(center_of(c) + Vector2(0, s * 0.55), String(warn[c]), int(13 * k), Color.WHITE, Color(Palette.TERRA, 0.92))

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
			_pill(center_of(c) + Vector2(0, -s * 1.05), ("+%s" if d > 0 else "−%s") % Pulse.big(absi(d)), int(14 * k), col, Color(Palette.SHEET, 0.96))

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
			_text(body, p + Vector2(0, 21 * k), Pulse.big(v), int(12 * k), Color(Palette.GOLD.lightened(0.3), a))
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
			_text_outlined(body, p + Vector2(0, 20 * k), "收 %s" % Pulse.big(pulse.contrib[c]), int(11 * k), Color(Palette.TERRA, a), halo)
		else:
			_text_outlined(body, p + Vector2(0, 20 * k), Pulse.big(v), int(11 * k), Color(Palette.INK, a), halo)
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
				lines.append(["末梢收获 %s" % Pulse.big(pulse.contrib[n.key]), int(15 * sk), Palette.TERRA, body])
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
	# 左侧一幅清晰的牌面插画（2D 原图，不依赖 3D 采样）
	var art: Texture2D = null if n.is_seed() else CardArt.texture(n.def().art_id())
	var art_w := 0.0
	if art:
		h = maxf(h, 150.0 * sk)
		art_w = (h - 16.0) * 0.72
		w += art_w + 10.0
	var anchor := _proj(_wpos(n.key, standee_height(n) + 0.2))
	var rect := Rect2(anchor + Vector2(-w * 0.5, -h - 18.0), Vector2(w, h))
	rect.position.x = clampf(rect.position.x, 8.0, size.x - w - 8.0)
	rect.position.y = maxf(8.0, rect.position.y)
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(Palette.INK, 0.35))
	draw_rect(rect, Color(Palette.SHEET, 0.97))
	draw_rect(rect, Palette.INK, false, 1.5)
	draw_rect(rect.grow(-4), Color(Palette.GOLD, 0.6), false, 1.0)
	var tx := rect.position.x + 13.0
	if art:
		var ar := Rect2(rect.position + Vector2(8, 8), Vector2(art_w, h - 16.0))
		draw_texture_rect(art, ar, false)
		draw_rect(ar, Color(Palette.INK, 0.6), false, 1.0)
		tx += art_w + 6.0
	var y := rect.position.y + 8.0
	for l in lines:
		y += l[1]
		draw_string(l[3], Vector2(tx, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1], l[2])
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
		_pill(_proj(_wpos(trace_target, 0.0)) + Vector2(0, s * 0.7), "收获 %s" % Pulse.big(pulse.contrib[trace_target]), int(14 * k), Palette.TERRA.darkened(0.1), Color(Palette.SHEET, 0.96))
