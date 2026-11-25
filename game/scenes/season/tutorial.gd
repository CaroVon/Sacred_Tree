class_name Tutorial
extends RefCounted
## 新手指导：一局固定发牌顺序的春季，逐步引导玩家完成放牌、分叉、脉动、末梢、嫁接、修剪。
## 每一步规定允许用哪些牌、能接在谁后面、能否结束回合/修剪，满足条件后进入下一步。
## 画面引导（聚光、箭头、气泡卡）由 season.gd 按 beat() 给出的「一拍」绘制。

signal step_changed

## 发牌顺序（正好是起始牌组的 18 张）。
const DRAW_ORDER: Array[StringName] = [
	&"stem", &"fork", &"fruit", &"fruit", &"vine",
	&"dead", &"flower",
	&"stem", &"node",
	&"stem", &"fruit",
	&"fork", &"tri", &"flower", &"stem", &"node", &"fork", &"dead",
]

var step: int = 0
var _start_turn: int = 1
var steps: Array[Dictionary] = []
## 一步完成后插入的「看结果」一拍：玩家点「继续」才进入下一步。
var pending_after: Dictionary = {}
## 已经解释过的名词（每个只在第一次出现时带「新词」说明）。
var seen_terms: Dictionary = {}
## 最后一步（自由生长）的说明卡点过「继续」后不再显示。
var free_dismissed: bool = false


## 每一步：title、规则限制（info / cards+parent / end_turn / prune / free），以及引导文字。
## 文字里的 {名词} 会画成可悬停的金色下划线词。target 见 season.gd 的 _tut_rects。
## 放牌步骤：action/why 用于「还没选牌」，place/place_why 用于「已经选中」，after 是放完之后的「看结果」一拍。
func _init() -> void:
	steps = [
		{"title": "树心", "info": true, "target": "seed",
			"action": "这是{树心}",
			"why": "每回合结束时，它会发出{养分}（春天 1 点），沿着枝干往外流。"},
		{"title": "芽点", "info": true, "target": "seed",
			"action": "树心伸出的短线叫{芽点}",
			"why": "新牌只能接在空着的芽点上。树心有 3 个芽点。"},
		{"title": "长出第一根枝", "cards": [&"stem"],
			"action": "点手牌里的「茎」",
			"why": "也可以直接把它拖到牌桌上。",
			"place": "放在发光的格子上",
			"place_why": "发光的格子正对着树心的芽点。",
			"after": {"target": "forecast", "action": "右边的预计分数变高了",
				"why": "「下次脉动预计」就是结束回合时能得的分。茎让流过的养分 +3。"},
			"done": func(r: RunState): return _count(r, &"stem") >= 1},
		{"title": "分叉", "cards": [&"fork"], "parent": &"stem",
			"action": "点「分叉」",
			"why": "{分叉}有 2 个芽点：养分流到这里会复制成两份。",
			"place": "接在茎的前方",
			"place_why": "茎只有正前方 1 个芽点——牌从哪个方向长出来，那边就是它的前方。",
			"after": {"target": "node:fork", "action": "分叉长出了 2 个新芽点",
				"why": "把枝伸长，后面才有地方继续接牌。"},
			"done": func(r: RunState): return _count(r, &"fork") >= 1},
		{"title": "放牌次数", "info": true, "target": "acts",
			"action": "每回合最多放 3 张牌",
			"why": "左上角「可放 / 剪 / 移栽」显示本回合还剩几次。现在还能放 1 张，不过先结束回合看看。"},
		{"title": "脉动", "end_turn": true, "target": "end",
			"action": "点「脉动」结束回合",
			"why": "也可以按空格。结束回合时神树{脉动}一次：养分从树心流出，一路流到每根枝的尽头。",
			"after": {"target": "score", "action": "这回合的得分进了{本季累计}",
				"why": "每季 5 回合，累计达到目标就能进入下一季。"},
			"done": func(r: RunState): return r.turn > _start_turn},
		{"title": "末梢", "info": true, "target": "tips",
			"action": "后面没有再接牌的，叫{末梢}",
			"why": "只有末梢计分。现在分叉就是唯一的末梢；往它后面接牌，养分会继续往后流。"},
		{"title": "结果", "cards": [&"fruit"], "parent": &"fork",
			"action": "点「果」",
			"action2": "再放一个「果」",
			"why": "{果}让收获 ×2，而且每经历一次脉动，倍率还会再涨。",
			"place": "放在分叉的芽点上",
			"place_why": "分叉的两个芽点各放一个果。",
			"after": {"target": "node:fruit", "action": "现在有两个末梢了",
				"why": "分叉把养分复制成两份，两个果各收获一次——得分翻倍。"},
			"done": func(r: RunState): return _fork_children(r) >= 2},
		{"title": "看懂一张牌", "info": true, "target": "node:fruit",
			"action": "把鼠标移到一个果上",
			"why": "牌桌会播放养分流到它的过程，左边写出完整算式。选中手牌后悬停在格子上，还能预览放下去的分数变化。"},
		{"title": "再次脉动", "end_turn": true, "target": "end",
			"action": "点「脉动」结束回合",
			"why": "看两个果一起收获。",
			"done": func(r: RunState): return r.turn > _start_turn},
		{"title": "嫁接", "cards": [&"vine"],
			"action": "点「藤」",
			"why": "{藤}可以同时接在两个相邻的末梢上，把它们的养分相乘——这叫{嫁接}。",
			"place": "放在同时挨着两个果的格子上",
			"place_why": "放下后留意右边的预计分数。",
			"after": {"target": "forecast", "action": "相乘！预计分数大涨",
				"why": "两股养分在藤处相乘，藤成了新的末梢，两个果不再单独计分。"},
			"done": func(r: RunState): return _count(r, &"vine") >= 1},
		{"title": "枯枝", "cards": [&"dead"], "parent": TreeNode.SEED,
			"action": "点「枯枝」",
			"why": "枯枝本身很弱，但剪掉它能换到养分。",
			"place": "接在树心另一个空芽点上",
			"place_why": "",
			"done": func(r: RunState): return _count(r, &"dead") >= 1},
		{"title": "乘法的威力", "end_turn": true, "target": "end",
			"action": "点「脉动」结束回合",
			"why": "分叉让路径变多，嫁接让路径相乘——这就是神树的核心。",
			"after": {"target": "score", "action": "本季目标已经达成",
				"why": "累计分超过了目标，这一季稳了。"},
			"done": func(r: RunState): return r.turn > _start_turn},
		{"title": "修剪", "prune": &"dead", "target": "prune",
			"action": "点「修剪」按钮",
			"why": "{修剪}会剪掉一张牌和它后面的所有枝，换成养分。也可以按 P。",
			"place": "点枯枝，把它剪掉",
			"place_why": "枯枝值 3 点养分。",
			"after": {"target": "sap", "action": "得到 3 点养分",
				"why": "养分可以重抽手牌，也是集市里买东西的货币。"},
			"done": func(r: RunState): return r.sap > 0},
		{"title": "自由生长", "free": true,
			"action": "剩下的回合自由发挥",
			"why": "可以继续放牌、修剪，或者直接点「脉动」。春季结束后指导就完成了。"},
	]


static func make_run() -> RunState:
	var s := RunState.create(20261119)
	s.tree.land.clear()
	s.hand.clear()
	s.discard.clear()
	s.deck.clear()
	for i in range(DRAW_ORDER.size() - 1, -1, -1):
		s.deck.append(DRAW_ORDER[i])
	s.draw()
	s.log_lines.clear()
	s.add_log("新手指导开始。")
	return s


func current() -> Dictionary:
	return steps[step]


func is_info() -> bool:
	return current().get("info", false)


func is_free() -> bool:
	return current().get("free", false)


## 当前这一拍要不要玩家点「继续」。
func needs_continue() -> bool:
	return not pending_after.is_empty() or is_info() or (is_free() and not free_dismissed)


## 点「继续」：看完结果 → 进下一步；说明步骤 → 进下一步；自由生长 → 收起说明卡。
func next(r: RunState = null) -> void:
	if not pending_after.is_empty():
		pending_after = {}
		_advance(r)
	elif is_info():
		_advance(r)
	elif is_free():
		free_dismissed = true
		step_changed.emit()


func _advance(r: RunState) -> void:
	if step < steps.size() - 1:
		step += 1
		if r:
			_start_turn = r.turn
	step_changed.emit()
	if r:
		update(r)


## 每次操作后调用：满足当前步的条件就前进；带「看结果」一拍的步骤先停在那一拍。
func update(r: RunState) -> void:
	if not pending_after.is_empty():
		return
	var moved := false
	while step < steps.size() - 1 and current().has("done") and current().done.call(r):
		if current().has("after"):
			pending_after = current().after
			step_changed.emit()
			return
		step += 1
		_start_turn = r.turn
		moved = true
	if moved:
		step_changed.emit()


## 当前一拍：{target, action, why, cont}。ui：{sel: 选中的牌 id 或 &""，prune_mode: bool}。
func beat(r: RunState, ui: Dictionary) -> Dictionary:
	if not pending_after.is_empty():
		var a := pending_after
		return {"target": a.get("target", ""), "action": a.action, "why": a.get("why", ""), "cont": true}
	var st := current()
	if st.get("free", false):
		if free_dismissed:
			return {}
		return {"target": "", "action": st.action, "why": st.why, "cont": true}
	if st.get("info", false):
		return {"target": st.get("target", ""), "action": st.action, "why": st.why, "cont": true}
	if st.has("cards"):
		var want: StringName = st.cards[0]
		if ui.get("sel", &"") == want:
			return {"target": "cells", "action": st.place, "why": st.get("place_why", ""), "cont": false}
		var act: String = st.action
		if st.has("action2") and _count(r, want) >= 1:
			act = st.action2
		return {"target": "card:" + String(want), "action": act, "why": st.why, "cont": false}
	if st.has("prune"):
		if ui.get("prune_mode", false):
			return {"target": "node:" + String(st.prune), "action": st.place, "why": st.place_why, "cont": false}
		return {"target": "prune", "action": st.action, "why": st.why, "cont": false}
	if st.get("end_turn", false):
		return {"target": "end", "action": st.action, "why": st.why, "cont": false}
	return {}


## 取出这一拍里第一次出现的名词，并记为已解释。
func take_new_terms(texts: Array) -> Array:
	var out: Array = []
	for t in texts:
		var s: String = t
		var i := 0
		while true:
			var a := s.find("{", i)
			if a < 0:
				break
			var b := s.find("}", a)
			if b < 0:
				break
			var w := s.substr(a + 1, b - a - 1)
			if not seen_terms.has(w):
				seen_terms[w] = true
				out.append(w)
			i = b + 1
	return out


func card_allowed(type: StringName) -> bool:
	if not pending_after.is_empty():
		return false
	if is_free():
		return true
	return current().get("cards", []).has(type)


func can_end_turn() -> bool:
	if not pending_after.is_empty():
		return false
	return is_free() or current().get("end_turn", false)


func can_prune_mode() -> bool:
	if not pending_after.is_empty():
		return false
	return is_free() or current().has("prune")


func prune_allowed(r: RunState, k: Vector2i) -> bool:
	if is_free():
		return true
	var n := r.tree.at(k)
	return n != null and current().has("prune") and n.type == current().prune


## 只保留本步规定父牌后面的位置。
func filter_targets(r: RunState, type: StringName, targets: Dictionary) -> Dictionary:
	if not card_allowed(type):
		return {}
	if is_free() or not current().has("parent"):
		return targets
	var want: StringName = current().parent
	var out := {}
	for k in targets:
		var t: Growth.Target = targets[k]
		if t.parents.size() == 1 and r.tree.at(t.parents[0]).type == want:
			out[k] = t
	return out


func _count(r: RunState, type: StringName) -> int:
	var n := 0
	for node: TreeNode in r.tree.nodes.values():
		if node.type == type:
			n += 1
	return n


func _fork_children(r: RunState) -> int:
	for node: TreeNode in r.tree.nodes.values():
		if node.type == &"fork":
			return node.children.size()
	return 0
