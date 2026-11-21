class_name Tutorial
extends RefCounted
## 新手指导：一局固定发牌顺序的春季，逐步提示玩家完成放牌、分叉、脉动、末梢、嫁接、修剪。
## 每一步规定允许用哪些牌、能接在谁后面、能否结束回合/修剪，满足条件后自动进入下一步。

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


func _init() -> void:
	steps = [
		{"title": "神树之种", "info": true,
			"text": "牌桌中央的黑色六边形是神树之种。每回合结束时，树心会发出养分（春季 1 点），沿着枝干流向所有末梢。所有末梢的养分加起来，就是这一回合的得分。"},
		{"title": "长出第一根枝", "cards": [&"stem"],
			"text": "树心伸出的 3 根粉色短线就是它的芽点。点手牌里的「茎」（或者直接把它拖到牌桌上），再点任意一个粉色虚线格。茎会让流过的养分 +3。",
			"done": func(r: RunState): return _count(r, &"stem") >= 1},
		{"title": "芽点与分叉", "cards": [&"fork"], "parent": &"stem",
			"text": "新牌只能接在空着的芽点上（粉色短线）。芽点以牌长出来的方向为“前方”：茎只有正前方 1 个芽点。把「分叉」接到茎的前方——分叉有左前、右前 2 个芽点，养分流到这里会复制成两份。",
			"done": func(r: RunState): return _count(r, &"fork") >= 1},
		{"title": "脉动", "end_turn": true,
			"text": "每回合最多放 2 张牌。右上方的“下次脉动预计”告诉你结束回合能得多少分。点「结束回合并脉动」（或按空格），看养分如何流动。",
			"done": func(r: RunState): return r.turn > _start_turn},
		{"title": "末梢收获", "cards": [&"fruit"], "parent": &"fork",
			"text": "得分只来自末梢——没有子牌的牌，用粉色虚线框标出。在分叉的两个芽点上各放一个「果」：果让养分 ×2，而且每经历一次脉动就更成熟。",
			"done": func(r: RunState): return _fork_children(r) >= 2},
		{"title": "先预览，再决定", "end_turn": true,
			"text": "选中一张牌后把鼠标移到虚线格上，会看到半透明的预览牌，受影响的末梢上浮出 +/− 变化。不选牌时把鼠标移到任意一张牌上，牌桌会播放养分流到它为止的过程，左上角写出完整算式。试试看，然后结束回合。",
			"done": func(r: RunState): return r.turn > _start_turn},
		{"title": "嫁接：养分相乘", "cards": [&"vine"],
			"text": "「藤」可以放在同时挨着两个末梢的空格上，把它们嫁接起来——几股养分在藤处相乘！找到挨着两个果的那个格子，把藤放上去，看看预计分数的变化。",
			"done": func(r: RunState): return _count(r, &"vine") >= 1},
		{"title": "为修剪做准备", "cards": [&"dead"], "parent": TreeNode.SEED,
			"text": "再把「枯枝」接到树心另一个空芽点上。枯枝本身很弱，但剪掉它能换到养分。",
			"done": func(r: RunState): return _count(r, &"dead") >= 1},
		{"title": "乘法的威力", "end_turn": true,
			"text": "分叉让路径变多，嫁接让路径相乘——这就是神树的核心。结束回合，看看这一次脉动。",
			"done": func(r: RunState): return r.turn > _start_turn},
		{"title": "修剪", "prune": &"dead",
			"text": "修剪会剪掉一张牌和它后面的所有枝，并换成养分（枯枝值 3 点）。养分可以用来重抽手牌，也能在集市里买东西。点「修剪」（或按 P），再点枯枝。",
			"done": func(r: RunState): return r.sap > 0},
		{"title": "自由生长", "free": true,
			"text": "本季累计早已超过目标 50。剩下的回合自由发挥：可以继续放牌、修剪，或者直接结束回合。春季结束后指导就完成了。"},
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


func next() -> void:
	if step < steps.size() - 1:
		step += 1
		step_changed.emit()


## 每次操作后调用：满足当前步的条件就前进（可连续前进多步）。
func update(r: RunState) -> void:
	var moved := false
	while step < steps.size() - 1 and current().has("done") and current().done.call(r):
		step += 1
		_start_turn = r.turn
		moved = true
	if moved:
		step_changed.emit()


func card_allowed(type: StringName) -> bool:
	if is_free():
		return true
	return current().get("cards", []).has(type)


func can_end_turn() -> bool:
	return is_free() or current().get("end_turn", false)


func can_prune_mode() -> bool:
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
