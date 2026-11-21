class_name Rules
extends RefCounted
## 全部可调参数集中在这里（对应网页原型最上方的“配置”区）。
## 一局 = YEARS 年；每年 = 春夏秋冬四季 + 一个天灾季（第 5 季）。

## 网页原型与测试用的牌桌半径；实际对局按年份扩张，见 radius_for_year。
const RADIUS := 4
## 牌桌逐年扩张：第 1/2/3 年的半径。
const RADII := [5, 6, 7]
const YEARS := 3
const STAGES := 5          # 每年的季数（含天灾季）
const CALAMITY_STAGE := 5
## 每年每季的目标。第一年前四季与网页原型一致；其余由 tools/balance_sim.gd 校准：
## 规划者策略通关约 50%，贪心策略基本过不了第一年天灾。
const TARGETS := [
	[50, 180, 500, 1200, 1000],
	[1000, 3000, 18000, 45000, 18000],
	[4500, 18000, 120000, 270000, 120000],
]
const SEASON_NAMES: Array[String] = ["春", "夏", "秋", "冬", "天灾"]
const TURNS := 5
const CALAMITY_TURNS := 3
const HAND := 6
const PLAYS := 3
const PRUNES := 1
## 每回合可移栽次数（把一张牌连同子枝挪到另一个芽点）。
const TRANSPLANTS := 1
const REDRAW_COST := 2
const SKIP_REWARD_SAP := 3
const REWARD_CHOICES := 3
const RELIC_CHOICES := 3
const SEASON_CLEAR_SAP := 4
const CALAMITY_CLEAR_SAP := 8
## 提前收获：本季每剩 1 回合得多少养分。
const HARVEST_SAP_PER_TURN := 2
## 器物槽数量；出售器物返还的比例。
const RELIC_SLOTS := 6
const RELIC_SELL_RATIO := 0.5

const START_DECK := {
	&"stem": 4, &"node": 2, &"fork": 3, &"tri": 1,
	&"fruit": 3, &"flower": 2, &"vine": 1, &"dead": 2,
}
## 开局土地与每年新增土地。
const START_LAND := {Land.Type.FERTILE: 5, Land.Type.ROCK: 5, Land.Type.SPRING: 3}
const YEARLY_LAND := {Land.Type.FERTILE: 1, Land.Type.ROCK: 1, Land.Type.SPRING: 1}
## 牌桌每年外扩一圈时，新圈上额外撒的地块。
const RING_LAND := {Land.Type.FERTILE: 2, Land.Type.ROCK: 2, Land.Type.SPRING: 1}

## 年轮印记：作用于树上的某一张牌。
const MARKS := {
	&"tough": {"name": "坚韧", "short": "韧", "price": 4, "desc": "不会在冬季枯萎，也不会被天灾伤害"},
	&"rich": {"name": "丰饶", "short": "丰", "price": 4, "desc": "流出养分 +2"},
	&"fireproof": {"name": "耐火", "short": "耐", "price": 4, "desc": "离开牌桌时火候额外 +3"},
	&"gilded": {"name": "镀金", "short": "金", "price": 5, "desc": "被剪掉时这张牌给的养分 ×2"},
	&"echo": {"name": "回响", "short": "响", "price": 12, "desc": "流出养分 ×2"},
}
## 芽点服务：给一张牌在指定方向加 1 个芽点。
const PORT_PRICE := 5
const MAX_EXTRA_PORTS := 2
const MARKET_CARD_OFFERS := 5
const MARKET_RELIC_OFFERS := 2
const REMOVE_CARD_PRICE := 3
const CLEAR_ROCK_PRICE := 3
const MAKE_FERTILE_PRICE := 4
## 精炼一张牌的价格。
const REFINE_PRICE := 6
## 每季选牌之后遇到局间事件的概率（天灾季之后不触发）。
const EVENT_CHANCE := 0.5
## 抽选时，已有主流派的牌权重倍数。
const FAMILY_BIAS := 4.0


static func radius_for_year(year: int) -> int:
	return RADII[clampi(year, 1, RADII.size()) - 1]


## 神树之心每季成熟一次，输出翻倍：春 1、夏 2、秋 4、冬 8；第 y 年再乘以 y。天灾季沿用冬季。
static func seed_out(season: int, year: int = 1) -> int:
	return year * (1 << (mini(season, 4) - 1))


## 季节特性：春多抽 1、夏多放 1、秋末端 ×1.5、冬季末最老的末梢枯萎。
const SEASON_TRAITS: Array[String] = [
	"每回合多抽 1 张", "每回合多放 1 张", "末端牌流出养分 ×1.5", "季末最老的 %d 个末梢枯萎", "",
]
const WINTER_WITHER := 3


static func season_trait(season: int) -> String:
	var t := SEASON_TRAITS[season - 1]
	return t % WINTER_WITHER if t.contains("%d") else t


static func hand_size(season: int) -> int:
	return HAND + (1 if season == 1 else 0)


static func plays_per_turn(season: int) -> int:
	return PLAYS + (1 if season == 2 else 0)


static func season_end_mult(season: int) -> float:
	return 1.5 if season == 3 else 1.0


static func is_winter(season: int) -> bool:
	return season == 4


static func is_calamity(season: int) -> bool:
	return season == CALAMITY_STAGE


static func turns(season: int) -> int:
	return CALAMITY_TURNS if is_calamity(season) else TURNS


static func season_count() -> int:
	return STAGES


static func target(season: int, year: int = 1) -> int:
	return TARGETS[year - 1][season - 1]


static func season_name(season: int) -> String:
	return SEASON_NAMES[season - 1]


static func mark_name(id: StringName) -> String:
	return MARKS[id].name
