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
		return int(floor(s * value))
	var p := 1
	for v in inflows:
		p *= v
	return p


func maturity_bonus(age: int) -> float:
	if mature_step == 0.0:
		return 0.0
	return minf(age * mature_step, mature_cap)


func ports_label() -> String:
	if is_graft():
		return "嫁接"
	if ports.is_empty():
		return "末端"
	return "芽点 %d" % ports.size()


func category_name() -> String:
	return CATEGORY_NAMES[category]
