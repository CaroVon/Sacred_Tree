class_name CardDef
extends Resource
## 牌的静态定义。效果用 effect 枚举 + 参数描述，规则层据此计算，不含任何画面逻辑。

enum Effect { NONE, ADD, ADD_DEPTH, MUL, SUB_CLAMP, GRAFT }
enum Category { CONDUCT, BRANCH, END, AURA, GRAFT, TIME, PRUNE }

const CATEGORY_NAMES := ["传导", "分枝", "末端", "相邻", "嫁接", "时间", "修剪"]

@export var id: StringName
@export var display_name: String = ""
@export var category: Category = Category.CONDUCT
## 芽点：相对朝向的偏移（0 = 正前方，±1 = 左右 60°，±2 = 左右后方 120°）。
@export var ports: PackedInt32Array = PackedInt32Array()
@export var effect: Effect = Effect.NONE
@export var value: float = 0.0
## 相邻的其他末梢各加多少。
@export var aura: int = 0
## 相邻的传导类牌流出养分各加多少（苔）。
@export var aura_conduct: int = 0
## 被剪掉时得到的养分（默认 1）。
@export var prune_value: int = 1
## 被剪掉时，下次脉动所有末梢加多少（落叶）。
@export var prune_tip_bonus: int = 0
## 燃尽：被剪掉后不回手牌，本季移出牌组（下季回来）。
@export var exhaust_on_prune: bool = false
## 主题色键：green / blue / red / pink / gold / grey。
@export var color_key: StringName = &"green"
@export var in_reward_pool: bool = true
## 集市价格（养分）。
@export var price: int = 5
## 只能接在深度不小于该值的位置（0 = 不限）。
@export var min_depth: int = 0
## 成熟：每经历一次脉动，乘数/加值增加多少；mature_cap 为累计上限。
@export var mature_step: float = 0.0
@export var mature_cap: float = 0.0
## 花苞类：经历 ripen_age 次脉动后，value 变为 ripe_value（0 = 不使用）。
@export var ripen_age: int = 0
@export var ripe_value: float = 0.0
## 嫁接方式：false = 父牌养分相乘；true = 相加后乘以 value。
@export var graft_sum: bool = false
## 嫁接至少需要的相邻末梢数。
@export var graft_min: int = 2
@export_multiline var desc: String = ""

# ---------- 流派与构筑（阶段 C） ----------
## 所属流派（可双流派）；空 = 木（基础流派）。
@export var family: Array[StringName] = []
## 跨流派关键词（末梢、传导、燃料、联动、时机、养分、镜像、封存）；空则按类别推断。
@export var keywords: Array[StringName] = []
## 稀有度：0 普通 / 1 稀有 / 2 传说。
@export var rarity: int = 0

# ---------- 修饰器（基础效果之后依次结算，0 表示不用） ----------
## 每个相邻同流派牌 +x（联动）。
@export var adj_family_add: int = 0
## ×(1 + x·相邻同流派牌数)。
@export var adj_family_mul: float = 0.0
## ×(1 + x·牌桌上同流派牌数)。
@export var family_count_mul: float = 0.0
## 流入改为“流入与相邻已结算牌中最高流出”的较大者（传动轴）。
@export var copy_max_neighbor: bool = false
## ×(1 + x·火候)。
@export var heat_mul: float = 0.0
## + x·本局累计燃烧牌数。
@export var burned_add: float = 0.0
## 相邻末梢的收获 ×(1 + x)（擒纵）。
@export var aura_tip_mul: float = 0.0
## 嫁接的父牌改为“相邻的该流派牌”（不要求是末梢），如枢纽。
@export var graft_family: StringName = &""
## 嫁接相加后再乘以父牌数。
@export var graft_count_mul: bool = false
## 嫁接结果再乘以这个倍数（精炼后的藤）。
@export var graft_self_mult: float = 1.0

# ---------- 星辰：时机 ----------
## + x·回合数。
@export var turn_add: float = 0.0
## × 回合数（满月）。
@export var turn_mul: bool = false
## 奇数回合 ×x（潮汐）。
@export var odd_turn_mul: float = 0.0
## 每季最后一回合 ×x（流星）。
@export var last_turn_mult: float = 0.0
## × 季节序号（春 1 … 冬 4，天灾季按 4）。
@export var season_mul: bool = false
## 整树总分 ×(1 + x·牌桌上的星辰牌数)（星图，可多张叠乘）。
@export var star_total_mult: float = 0.0
## 作为末梢计算长茎时，深度额外 +x（彗尾）。
@export var depth_bonus: int = 0

# ---------- 商会：养分 ----------
## + x·当前养分。
@export var sap_add: float = 0.0
## ×(1 + x·当前养分)。
@export var sap_mul: float = 0.0
## 每次脉动花这么多养分；脉动前养分不够则这张牌流出 0（契约）。
@export var pulse_cost: int = 0
## 回合末养分按比例生息（每张最多 +5）。
@export var interest: float = 0.0
## 放下时要花的养分。
@export var play_cost: int = 0
## 被剪掉时额外得到“流出 × x”的养分（当铺）。
@export var prune_out_sap: float = 0.0
## + x·本局在集市累计花费的养分（账本）。
@export var spent_add: float = 0.0
## ×(器物数 + 1)（丰饶角）。
@export var relic_mul: bool = false

# ---------- 镜像：对称位置 ----------
## 流出至少为“点对称位置那张牌的流出 × x”（对面先结算时生效）。
@export var mirror_copy: float = 0.0
## 作为末梢时，收获至少等于对称位置末梢的收获（倒影）。
@export var mirror_tip: bool = false
## 对称位置是同类牌时 ×x。
@export var mirror_same_mult: float = 0.0
## 牌桌上每有一对对称的同类牌 +x（万花筒）。
@export var pair_add: int = 0
## 幻影：共鸣计数时还算作“最接近下一阈值”的另一个流派。
@export var wild: bool = false

# ---------- 封印：封存 ----------
## 相邻末梢的收获被封存进这张牌（当回合不计分）。
@export var seal_adjacent: bool = false
## 自己的收获被封存（当回合不计分）。
@export var seal_self: bool = false
## 封存的释放倍率：每封存过一次脉动 +x（季末或提前收获时释放：存量 ×(1 + x·次数)）。
@export var seal_rate: float = 0.5
## 相邻封印牌的释放倍率额外 +x（符文石）。
@export var release_adj_bonus: float = 0.0
## 相邻的牌视为坚韧（护符）。
@export var aura_tough: bool = false
## 天灾季 ×x（雷印）。
@export var calamity_mult: float = 0.0
## 被剪掉时立即释放牌桌上全部封存，倍率再 ×x（解印）。
@export var release_on_prune: float = 0.0
## 每次脉动给相邻的封印牌的存量 +x（锁链）。
@export var seal_feed: int = 0

# ---------- 桥牌 ----------
## 牌桌上每燃烧一张牌，得这么多养分（铸币炉）。
@export var sap_on_burn: int = 0
## 燃烧时火候额外 + 当前回合数（星火）。
@export var heat_on_burn_turn: bool = false

# ---------- 副作用（由 RunState 结算） ----------
## 每次脉动产出养分。
@export var pulse_sap: int = 0
## 每次脉动增加火候。
@export var pulse_heat: int = 0
## 被燃烧（离开牌桌）时额外的火候。
@export var heat_on_burn: int = 0
## 被燃烧后，下次脉动总分倍率 +x（余烬）。
@export var burn_total_mult: float = 0.0
## 每次脉动后烧掉相邻收获最低的末梢（献祭台）。
@export var burn_adjacent: bool = false
## 天生坚韧：不会枯萎，也不会被天灾伤害。
@export var innate_tough: bool = false

@export_group("传说：改写规则")
## 浴火（凤凰羽）：牌桌上有它时，剪下 / 烧掉回到手牌的牌当回合就能再打出。
@export var burn_fresh: bool = false
## 逆行：星辰牌把每一回合都当作本季最后一回合。
@export var retro: bool = false
## 永动机：齿轮牌把牌桌上其他齿轮牌都算作相邻（最多 link_all_cap 张）。
@export var link_all: bool = false
@export var link_all_cap: int = 6
## 合伙契约：牌桌上每 x 张非商会牌，也算 1 张商会牌计入共鸣。
@export var partner_per: int = 0
## 合伙契约最多多算几张商会牌。
@export var partner_cap: int = 99
## 万象镜：没有对称牌的末梢在对面映出幻影，额外计入收获 ×x；每三个幻影算一对对称。
@export var phantom_mirror: float = 0.0

const FAMILY_NAMES := {
	&"wood": "木", &"gear": "齿轮", &"forge": "熔炉", &"star": "星辰",
	&"coin": "商会", &"mirror": "镜像", &"seal": "封印",
}
const KEYWORD_NAMES := {
	&"tip": "末梢", &"conduct": "传导", &"fuel": "燃料", &"link": "联动",
	&"timing": "时机", &"sap": "养分", &"mirror": "镜像", &"store": "封存",
}
const RARITY_NAMES := ["普通", "稀有", "传说"]


func families() -> Array[StringName]:
	if family.is_empty():
		return [&"wood"] as Array[StringName]
	return family


func has_family(f: StringName) -> bool:
	return families().has(f)


func family_label() -> String:
	return "·".join(families().map(func(f): return FAMILY_NAMES.get(f, String(f))))


## 关键词：数据里写了就用，否则按类别推断。
func keyword_list() -> Array[StringName]:
	if not keywords.is_empty():
		return keywords
	var out: Array[StringName] = []
	if is_end():
		out.append(&"tip")
	elif category == Category.CONDUCT:
		out.append(&"conduct")
	return out


## 一行身份标签：「齿轮 · 传导 · 联动」；木系「传导」。稀有度非普通时附在最后。
func tag_line() -> String:
	var parts: Array[String] = []
	if not family.is_empty():
		parts.append(family_label())
	else:
		parts.append(category_name())
	for k in keyword_list():
		var kn: String = KEYWORD_NAMES.get(k, String(k))
		if not parts.has(kn):
			parts.append(kn)
	if rarity > 0:
		parts.append(RARITY_NAMES[rarity])
	return " · ".join(parts)


func keyword_label() -> String:
	return "、".join(keyword_list().map(func(k): return KEYWORD_NAMES.get(k, String(k))))


## 精炼过的牌 id 以 “+” 结尾（例如 stem+）。
func is_plus() -> bool:
	return String(id).ends_with("+")


func base_id() -> StringName:
	return StringName(String(id).trim_suffix("+")) if is_plus() else id


## 插画用的 id：精炼版沿用原牌的图。
func art_id() -> StringName:
	return base_id()


func is_graft() -> bool:
	return effect == Effect.GRAFT


func is_end() -> bool:
	return ports.is_empty()


## 当前（考虑成熟后）的效果数值。
func current_value(age: int, maturity: bool = true) -> float:
	if not maturity:
		return value
	if ripen_age > 0:
		return ripe_value if age >= ripen_age else value
	return value + maturity_bonus(age)


## 把流入的养分 v 加工成流出的养分。
func apply(v: int, node: TreeNode, maturity: bool = true) -> int:
	var x := current_value(node.age, maturity)
	match effect:
		Effect.ADD:
			return v + int(x)
		Effect.ADD_DEPTH:
			return v + node.depth
		Effect.MUL:
			return int(floor(v * x))
		Effect.SUB_CLAMP:
			return maxi(0, v - int(x))
	return v


## 嫁接：父牌养分合成为藤的流出养分。
func combine(inflows: Array[int]) -> int:
	if graft_sum:
		var s := 0
		for v in inflows:
			s += v
		return int(floor(s * value * graft_self_mult))
	var p := 1
	for v in inflows:
		p *= v
	return int(floor(p * graft_self_mult)) if graft_self_mult != 1.0 else p


func maturity_bonus(age: int) -> float:
	if mature_step == 0.0:
		return 0.0
	if mature_step < 0.0:
		return maxf(age * mature_step, -mature_cap)
	return minf(age * mature_step, mature_cap)


func ports_label() -> String:
	if is_graft():
		return "嫁接"
	if ports.is_empty():
		return "末端"
	return "芽点 %d" % ports.size()


func category_name() -> String:
	return CATEGORY_NAMES[category]
