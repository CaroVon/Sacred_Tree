class_name Profile
extends RefCounted
## 多局之间的收藏与解锁（与单局存档分开）。默认存 user://profile.json；path 为空时只在内存里（测试用）。
##
## 解锁：流派与启程者随里程碑解锁；奖励池只出已解锁流派的牌。
## 图鉴：每张牌的最高单次贡献、出场局数；联动谱记录首次触发的搭配。

const DEFAULT_FAMILIES: Array[StringName] = [&"wood", &"gear", &"forge"]
const DEFAULT_STARTERS: Array[StringName] = [&"gardener", &"artisan"]

## 里程碑：id -> {名称, 条件说明, 解锁的流派 / 启程者}
const UNLOCKS := {
	&"year2": {"name": "第一次进入第 2 年", "families": [&"star"], "starters": [&"stargazer"]},
	&"year3": {"name": "第一次进入第 3 年", "families": [&"coin"], "starters": [&"trader"]},
	&"resonance3": {"name": "任一流派共鸣达到 3 层（6 张）", "families": [&"mirror"], "starters": []},
	&"bigpulse": {"name": "单次脉动收获超过 100000", "families": [&"seal"], "starters": []},
	&"win": {"name": "第一次让神树成年（通关）", "families": [&"star", &"coin", &"mirror", &"seal"],
		"starters": [&"stargazer", &"trader"]},
}

var path: String = ""
var data: Dictionary = {}


static func load_from(p: String) -> Profile:
	var pr := Profile.new()
	pr.path = p
	pr.data = _defaults()
	if p != "" and FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			for k in d:
				pr.data[k] = d[k]
	return pr


static func _defaults() -> Dictionary:
	return {
		"families": DEFAULT_FAMILIES.map(func(x): return String(x)),
		"starters": DEFAULT_STARTERS.map(func(x): return String(x)),
		"milestones": [], "cards": {}, "combos": {}, "best_pulse": 0, "runs": 0,
	}


func save() -> void:
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


# ---------- 查询 ----------

func families() -> Array[StringName]:
	var out: Array[StringName] = []
	for f in data.families:
		out.append(StringName(f))
	return out


func has_family(f: StringName) -> bool:
	return data.families.has(String(f))


func has_starter(id: StringName) -> bool:
	return data.starters.has(String(id))


## 某流派还没解锁时的解锁条件说明。
func unlock_hint_family(f: StringName) -> String:
	for m in UNLOCKS:
		if UNLOCKS[m].families.has(f):
			return UNLOCKS[m].name
	return ""


func unlock_hint_starter(id: StringName) -> String:
	for m in UNLOCKS:
		if UNLOCKS[m].starters.has(id):
			return UNLOCKS[m].name
	return ""


func card_stats(id: StringName) -> Dictionary:
	return data.cards.get(String(id), {})


func combo_found(id: StringName) -> bool:
	return data.combos.has(String(id))


# ---------- 记录 ----------

func record_run_start() -> void:
	data.runs = int(data.runs) + 1
	save()


## 一次脉动之后：更新每张牌的最高贡献与出场局数、联动谱、单次脉动纪录。返回给玩家看的消息。
func record_pulse(run: RunState, tree: TreeModel, res: Pulse.Result) -> Array[String]:
	var msgs: Array[String] = []
	for n: TreeNode in tree.nodes.values():
		if n.is_seed():
			continue
		var id := String(n.def().base_id())
		var st: Dictionary = data.cards.get(id, {"best": 0, "runs": 0, "last": -1})
		var v: int = res.contrib.get(n.key, res.out.get(n.key, 0))
		st.best = maxi(int(st.best), v)
		if int(st.get("last", -1)) != run.seed_value:
			st.last = run.seed_value
			st.runs = int(st.runs) + 1
		data.cards[id] = st
	for c in Combos.detect(tree, res):
		if not data.combos.has(String(c)):
			data.combos[String(c)] = {"year": run.year, "season": run.season}
			msgs.append("联动谱新条目：%s" % Combos.LIST[c].name)
	data.best_pulse = maxi(int(data.best_pulse), res.total)
	if res.total >= 100000:
		msgs.append_array(_reach(&"bigpulse"))
	for f in res.resonance:
		if int(res.resonance[f]) >= 3:
			msgs.append_array(_reach(&"resonance3"))
			break
	save()
	return msgs


## 一局的进度变化之后（进入新的一年、通关）。返回解锁消息。
func record_progress(run: RunState) -> Array[String]:
	var msgs: Array[String] = []
	if run.year >= 2:
		msgs.append_array(_reach(&"year2"))
	if run.year >= 3:
		msgs.append_array(_reach(&"year3"))
	if run.phase == RunState.Phase.WON:
		msgs.append_array(_reach(&"win"))
	save()
	return msgs


func _reach(m: StringName) -> Array[String]:
	var msgs: Array[String] = []
	if data.milestones.has(String(m)):
		return msgs
	data.milestones.append(String(m))
	var u: Dictionary = UNLOCKS[m]
	for f in u.families:
		if not data.families.has(String(f)):
			data.families.append(String(f))
			msgs.append("解锁流派：%s（%s）" % [CardDef.FAMILY_NAMES[f], u.name])
	for s in u.starters:
		if not data.starters.has(String(s)):
			data.starters.append(String(s))
			var sd := Cards.starter(s)
			msgs.append("解锁启程者：%s" % (sd.display_name if sd else String(s)))
	return msgs
