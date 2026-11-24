class_name Fx
extends RefCounted
## 动效工具：缓动曲线、补间、震动、粒子。
## 所有动效都要考虑 Game.reduce_motion。

## 缓出（快进慢停）。
static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


## 缓入缓出。
static func ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## 回弹（盖章落定）。
static func back_out(t: float) -> float:
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)


## 弹性（数字弹跳）。
static func elastic_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	return pow(2.0, -9.0 * t) * sin((t * 10.0 - 0.75) * (TAU / 3.0)) + 1.0


## 让对象的某个脚本属性缓动到目标值。
## prop 可以是 "lift"、"modulate:a"、"position:x" 这样的路径。
static func prop(node: Object, prop: StringName, to: float, dur: float, easing: Callable = Callable(), delay: float = 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	var n := node as Node
	if n == null:
		return
	var path := NodePath(String(prop))
	var cur: Variant = n.get_indexed(path)
	if typeof(cur) != TYPE_FLOAT and typeof(cur) != TYPE_INT:
		return
	var from := float(cur)
	var tw: Tween = n.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	if easing.is_valid():
		tw.tween_method(func(t: float) -> void:
			var e: float = easing.call(t)
			n.set_indexed(path, from + (to - from) * e), 0.0, 1.0, dur)
	else:
		tw.tween_method(func(t: float) -> void:
			n.set_indexed(path, from + (to - from) * t), 0.0, 1.0, dur)


## 纸片抬起：悬停/选中时离桌一点。
static func lift(card: CardView, up: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	if Game.reduce_motion:
		card.lift = 1.0 if up else 0.0
		return
	var tw := card.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "lift", 1.0 if up else 0.0, 0.16)


## 落牌压印：先扁后弹。
static func stamp(card: CardView) -> void:
	if card == null or not is_instance_valid(card):
		return
	if Game.reduce_motion:
		return
	var tw := card.create_tween()
	tw.tween_method(func(v: float): card.stamp_t = v, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE)


## 数字滚动到目标值。
static func count_to(label: Label, to: int, dur: float = 0.5) -> void:
	if label == null or not is_instance_valid(label):
		return
	var from: int = label.get_meta(&"num", label.text.to_int())
	label.set_meta(&"num", to)
	if from == to or Game.reduce_motion or dur <= 0.0:
		label.text = Pulse.big(to)
		return
	var tw := label.create_tween()
	tw.tween_method(func(v: float): label.text = Pulse.big(roundf(v)), float(from), float(to), dur).set_trans(Tween.TRANS_CUBIC)


## 震动：给节点加一个 shake_t 属性，由它自己决定怎么抖。
static func shake(node: Object, amount: float = 2.0, dur: float = 0.2) -> void:
	if node == null or not is_instance_valid(node):
		return
	if Game.reduce_motion:
		return
	var n := node as Node
	if n == null:
		return
	if "shake_amp" in node:
		node.set("shake_amp", amount / 2.0)
	var tw: Tween = n.create_tween()
	tw.tween_method(func(v: float): node.set("shake_t", v), 1.0, 0.0, dur).set_trans(Tween.TRANS_SINE)


## 顿帧：时间几乎停住一瞬（大额计分的冲击感）。用真实时间计时，不受自身减速影响。
static func hitstop(tree: SceneTree, sec: float = 0.08, scale: float = 0.05) -> void:
	if Game.reduce_motion or tree == null:
		return
	Engine.time_scale = scale
	await tree.create_timer(sec, true, false, true).timeout
	Engine.time_scale = 1.0


## 震动偏移量（配合 shake_t 使用）。
static func shake_offset(t: float, amount: float) -> Vector2:
	if t <= 0.0:
		return Vector2.ZERO
	var a := amount * t
	return Vector2(sin(t * 47.0) * a, cos(t * 39.0) * a * 0.7)


## 一片飘落的叶子（修剪时用）。
static func falling_leaves(parent: Node, pos: Vector2, art_id: StringName = &"leaf") -> void:
	if parent == null or not is_instance_valid(parent) or Game.reduce_motion:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = 10
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 12.0
	p.direction = Vector2(0, 1)
	p.spread = 40.0
	p.gravity = Vector2(0, 60)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.11
	p.damping_min = 20.0
	p.damping_max = 40.0
	var tex := CardArt.texture(art_id)
	if tex != null:
		p.texture = tex
	p.color = Color(Palette.STONE, 0.9)
	parent.add_child(p)
	p.emitting = true
	# 一阵子之后自己消失
	var tw := p.create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(p.queue_free)


## 墨迹扩散：一次性的墨点动画，由调用方在 _draw 里画。
static func ink_spread(t: float, radius: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 0.0
	return radius * ease_out(t)
