class_name Cards
extends RefCounted
## 数据注册表：从 res://data 载入全部牌、器物、天灾。纯静态，规则层和测试都可直接使用。

const CARD_DIR := "res://data/cards"
const RELIC_DIR := "res://data/relics"
const CALAMITY_DIR := "res://data/calamities"

static var _defs: Dictionary = {}        # StringName -> CardDef
static var _relics: Dictionary = {}      # StringName -> RelicDef
static var _calamities: Dictionary = {}  # StringName -> CalamityDef


static func ensure_loaded() -> void:
	if _defs.is_empty():
		_load_dir(CARD_DIR, _defs)
		_load_dir(RELIC_DIR, _relics)
		_load_dir(CALAMITY_DIR, _calamities)


static func _load_dir(path: String, into: Dictionary) -> void:
	for f in ResourceLoader.list_directory(path):
		if f.ends_with(".tres") or f.ends_with(".res"):
			var d = load(path.path_join(f))
			if d and "id" in d:
				into[d.id] = d


static func get_def(id: StringName) -> CardDef:
	ensure_loaded()
	return _defs.get(id)


static func has(id: StringName) -> bool:
	ensure_loaded()
	return _defs.has(id)


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
