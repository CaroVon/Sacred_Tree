class_name Cards
extends RefCounted
## 数据注册表：从 res://data 载入全部牌、器物、天灾。纯静态，规则层和测试都可直接使用。

const CARD_DIR := "res://data/cards"
const RELIC_DIR := "res://data/relics"
const CALAMITY_DIR := "res://data/calamities"
const STARTER_DIR := "res://data/starters"

static var _defs: Dictionary = {}        # StringName -> CardDef
static var _relics: Dictionary = {}      # StringName -> RelicDef
static var _calamities: Dictionary = {}  # StringName -> CalamityDef
static var _starters: Dictionary = {}    # StringName -> StarterDef
static var _plus: Dictionary = {}        # 精炼版缓存：StringName("x+") -> CardDef


static func ensure_loaded() -> void:
	if _defs.is_empty():
		_load_dir(CARD_DIR, _defs)
		_load_dir(RELIC_DIR, _relics)
		_load_dir(CALAMITY_DIR, _calamities)
		_load_dir(STARTER_DIR, _starters)


static func _load_dir(path: String, into: Dictionary) -> void:
	for f in ResourceLoader.list_directory(path):
		if f.ends_with(".tres") or f.ends_with(".res"):
			var d = load(path.path_join(f))
			if d and "id" in d:
				into[d.id] = d


static func get_def(id: StringName) -> CardDef:
	ensure_loaded()
	var d: CardDef = _defs.get(id)
	if d == null and String(id).ends_with("+"):
		d = _plus.get(id)
		if d == null:
			var base: CardDef = _defs.get(StringName(String(id).trim_suffix("+")))
			if base:
				d = make_plus(base)
				_plus[id] = d
	return d


static func has(id: StringName) -> bool:
	return get_def(id) != null


## 精炼：由原牌推导出“+”版。数值增强的规则统一写在这里，不必为每张牌单独做数据。
static func make_plus(base: CardDef) -> CardDef:
	var d: CardDef = base.duplicate()
	d.id = StringName(String(base.id) + "+")
	d.display_name = base.display_name + "+"
	d.price = base.price + 2
	d.prune_value = base.prune_value + 1
	d.in_reward_pool = false
	var notes: Array[String] = []
	match base.effect:
		CardDef.Effect.ADD:
			var add := maxi(1, ceili(base.value * 0.5))
			d.value = base.value + add
			notes.append("加值 +%d" % add)
		CardDef.Effect.MUL:
			d.value = base.value + 0.5
			notes.append("倍率 +0.5")
		CardDef.Effect.SUB_CLAMP:
			d.value = maxf(0.0, base.value - 1.0)
			notes.append("减值 −1")
		CardDef.Effect.GRAFT:
			d.graft_self_mult = base.graft_self_mult * 1.5
			notes.append("嫁接结果 ×1.5")
		_:
			if base.ports.size() > 0:
				d.effect = CardDef.Effect.ADD
				d.value = 1.0
				notes.append("流出 +1")
	if base.aura > 0:
		d.aura = base.aura + 2
		notes.append("相邻加成 +2")
	if base.aura_conduct > 0:
		d.aura_conduct = base.aura_conduct + 1
	for f in ["adj_family_mul", "family_count_mul", "heat_mul", "burned_add", "aura_tip_mul", "star_total_mult",
			"sap_mul", "mirror_copy", "interest", "burn_total_mult", "seal_rate", "release_adj_bonus"]:
		if float(base.get(f)) > 0.0:
			d.set(f, float(base.get(f)) * 1.5)
	for f in ["adj_family_add", "pair_add", "pulse_sap", "pulse_heat", "heat_on_burn", "seal_feed", "sap_on_burn"]:
		if int(base.get(f)) > 0:
			d.set(f, int(base.get(f)) + 1)
	if notes.is_empty():
		notes.append("特效增强 ×1.5")
	d.desc = base.desc + "（精炼：%s）" % "，".join(notes)
	return d


static func starter(id: StringName) -> StarterDef:
	ensure_loaded()
	return _starters.get(id)


static func starter_ids() -> Array[StringName]:
	ensure_loaded()
	return _sorted_keys(_starters)


static func all_ids() -> Array[StringName]:
	ensure_loaded()
	return _sorted_keys(_defs)


## 可以出现在奖励和集市里的牌。
static func pool_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all_ids():
		if _defs[id].in_reward_pool:
			out.append(id)
	return out


static func relic(id: StringName) -> RelicDef:
	ensure_loaded()
	return _relics.get(id)


static func relic_ids() -> Array[StringName]:
	ensure_loaded()
	return _sorted_keys(_relics)


static func calamity(id: StringName) -> CalamityDef:
	ensure_loaded()
	return _calamities.get(id)


static func calamity_ids() -> Array[StringName]:
	ensure_loaded()
	return _sorted_keys(_calamities)


static func _sorted_keys(d: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in d.keys():
		out.append(k)
	out.sort_custom(func(a, b): return String(a) < String(b))
	return out
