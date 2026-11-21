class_name Combos
extends RefCounted
## 联动谱：有名字的跨牌 / 跨流派搭配。脉动时检测，首次触发会记进图鉴（Profile）。
## 每条只描述“怎么搭出来”，不改变计分——计分全部来自牌本身的效果。

const LIST := {
	&"fruitvine": {"name": "果藤", "desc": "藤的两个以上父牌都是果或金果：经典的值×值。", "hint": "果 + 藤"},
	&"steam": {"name": "蒸汽机", "desc": "齿轮与熔炉同时共鸣：集群越大，烧得越旺。", "hint": "齿轮共鸣 + 熔炉共鸣"},
	&"gearbox": {"name": "传动系统", "desc": "一个枢纽同时接上三张以上齿轮牌。", "hint": "枢纽 + 3 张齿轮"},
	&"inferno": {"name": "炼狱", "desc": "祭坛挨着熔炉：每次脉动都在添柴。", "hint": "祭坛 + 熔炉"},
	&"starsea": {"name": "星海", "desc": "两张以上星图叠乘整树总分。", "hint": "星图 ×2"},
	&"compound": {"name": "复利", "desc": "金库与契约同在：养分越多，契约越值。", "hint": "金库 + 契约"},
	&"mirrorfire": {"name": "镜中火", "desc": "两张镜炉在点对称的位置互相映照。", "hint": "镜炉 ×2（对称位置）"},
	&"runeseal": {"name": "符文封印", "desc": "封印匣挨着符文石：封得越久，放得越多。", "hint": "封印匣 + 符文石"},
	&"illusion": {"name": "幻术", "desc": "幻影替另一个流派凑满了共鸣。", "hint": "幻影 + 任一流派共鸣"},
	&"triad": {"name": "三重共鸣", "desc": "三个流派同时共鸣。", "hint": "任意三个流派各 2 张以上"},
	&"comet": {"name": "长夜星轨", "desc": "连星与长茎同时成立。", "hint": "连星 + 长茎"},
	&"perfect": {"name": "完美对称", "desc": "整棵树点对称。", "hint": "6 张以上，每张都有对称的同类"},
}


## 这次脉动成立的联动（id 列表）。tree 为脉动时的树，res 为它的结算结果。
static func detect(tree: TreeModel, res: Pulse.Result) -> Array[StringName]:
	var out: Array[StringName] = []
	var by_type := {}
	for n: TreeNode in tree.nodes.values():
		if not n.is_seed():
			var b := n.def().base_id()
			by_type[b] = int(by_type.get(b, 0)) + 1
	# 果藤
	for n: TreeNode in tree.nodes.values():
		if n.is_seed() or n.def().base_id() != &"vine" or n.parents.size() < 2:
			continue
		var fruits := 0
		for p in n.parents:
			var pn := tree.at(p)
			if pn and not pn.is_seed() and pn.def().base_id() in [&"fruit", &"gold"]:
				fruits += 1
		if fruits >= 2:
			out.append(&"fruitvine")
			break
	if res.resonance.has(&"gear") and res.resonance.has(&"forge"):
		out.append(&"steam")
	for n: TreeNode in tree.nodes.values():
		if not n.is_seed() and n.def().base_id() == &"gear_hub" and n.parents.size() >= 3:
			out.append(&"gearbox")
			break
	if _adjacent(tree, &"forge_altar", &"forge_furnace"):
		out.append(&"inferno")
	if int(by_type.get(&"star_chart", 0)) >= 2:
		out.append(&"starsea")
	if by_type.has(&"coin_vault") and by_type.has(&"coin_contract"):
		out.append(&"compound")
	for n: TreeNode in tree.nodes.values():
		if not n.is_seed() and n.def().base_id() == &"bridge_mirrorforge":
			var m := tree.at(-n.key)
			if m and not m.is_seed() and m.def().base_id() == &"bridge_mirrorforge":
				out.append(&"mirrorfire")
				break
	if _adjacent(tree, &"seal_box", &"seal_rune"):
		out.append(&"runeseal")
	if by_type.has(&"mirror_phantom"):
		for f in res.resonance:
			if f != &"mirror":
				out.append(&"illusion")
				break
	if res.resonance.size() >= 3:
		out.append(&"triad")
	var ids := res.patterns.map(func(p): return p.id)
	if ids.has(&"line") and ids.has(&"long"):
		out.append(&"comet")
	if ids.has(&"sym"):
		out.append(&"perfect")
	return out


static func _adjacent(tree: TreeModel, a: StringName, b: StringName) -> bool:
	for n: TreeNode in tree.nodes.values():
		if n.is_seed() or n.def().base_id() != a:
			continue
		for nb in Hex.neighbors(n.key):
			var m := tree.at(nb)
			if m and not m.is_seed() and m.def().base_id() == b:
				return true
	return false
