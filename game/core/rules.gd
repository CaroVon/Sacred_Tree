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
## 每年每季的目标。由 tools/calibrate.py 校准（2026-11-22 起全阶段参与，含第 1 年）：
## 梯度：季内每季 ≥ 上一季 ×2.5，天灾季 ≥ 冬季（每年的高潮），每年春 ≥ 上一年春 ×8。
## 难度锚点：规划者 bot 有传说通关约 50%，无传说 ≥ 35%。
const TARGETS := [
	[87, 220, 550, 1400, 1400],
	[4100, 15000, 39000, 98000, 98000],
	[97000, 480000, 1300000, 3300000, 3300000],
]
const SEASON_NAMES: Array[String] = ["春", "夏", "秋", "冬", "天灾"]
const TURNS := 5
const CALAMITY_TURNS := 3
## 每个天灾季，天灾最多从牌桌上移走几张牌（控制破坏强度）。
const CALAMITY_REMOVE_CAP := 2
## 雷击劈断的枝最多几张。
const LIGHTNING_CUT := 2
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
## 天灾季后传说三选一的选项数。
## 当铺这类「剪掉时按流出得养分」的牌，每张最多得这么多（防止养分滚雪球）。
const PRUNE_OUT_SAP_CAP := 30
const LEGEND_CHOICES := 3
## 传说之选是否每年都有（否则只在第 1 年天灾之后）。
const LEGEND_EVERY_YEAR := false
const RELIC_SLOTS := 6
## 每到新的一年，树心自动多长 1 个芽点（防止树长满后无处可放）。
const SEED_PORT_PER_YEAR := 1
## 空芽点少于这个数时，季末选牌保证至少一张能分枝的牌。
const LOW_BUDS := 2
## 超额奖励：本季累计达到目标的 10 倍、100 倍、1000 倍……每一档多得这么多养分（最多 3 档）。
const OVERKILL_SAP := 2
const OVERKILL_MAX_TIERS := 3
## 传说「解印」在牌桌上时，季末释放封存再 ×这个数。
const BREAK_PASSIVE_MULT := 1.5
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
## 一个新流派至少有这么多张牌（牌组加牌桌）才算主流派；都不够时古木算主流派。
const MAIN_FAMILY_MIN := 3


static func radius_for_year(year: int) -> int:
	return RADII[clampi(year, 1, RADII.size()) - 1]


## 神树之心每季成熟一次，输出翻倍：春 1、夏 2、秋 4、冬 8；第 y 年再乘以 y。天灾季沿用冬季。
static func seed_out(season: int, year: int = 1) -> int:
	return year * (1 << (mini(season, 4) - 1))


## 季节特性：春多抽 1、夏多放 1、秋末端 ×1.5、冬季末最老的末梢枯萎。
const SEASON_TRAITS: Array[String] = [
	"每回合多抽 1 张", "每回合多放 1 张", "末端牌流出养分 ×1.5", "季末最老的 %d 个末梢枯萎", "",
]
const WINTER_WITHER := 2


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
