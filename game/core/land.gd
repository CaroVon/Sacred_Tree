class_name Land
extends RefCounted
## 土地地块：作用于某一个格子。

enum Type { PLAIN, FERTILE, ROCK, SPRING, ORE, LAVA, STARWELL, GOLDSAND }

const NAMES := ["平地", "沃土", "岩石", "泉眼", "矿脉", "熔岩", "星井", "金沙"]
const DESCS := [
	"",
	"长在这里的牌流出养分 +%d",
	"无法生长",
	"无法生长；相邻的末梢 +%d",
	"长在这里的齿轮牌流出 +4，其他牌 +1",
	"长在这里的牌离开牌桌时火候额外 +3",
	"长在这里的牌流出 + 当前回合数",
	"长在这里的牌每次脉动产出 1 养分",
]
const FERTILE_BONUS := 2
const SPRING_BONUS := 2
## 新流派地块（每年外扩时随机撒在新圈上）。
const SPECIALS: Array[int] = [Type.ORE, Type.LAVA, Type.STARWELL, Type.GOLDSAND]
## 地块离树心的最小距离。
const MIN_DIST := 2


static func name_of(t: int) -> String:
	return NAMES[t]


static func desc_of(t: int) -> String:
	match t:
		Type.FERTILE:
			return DESCS[t] % FERTILE_BONUS
		Type.SPRING:
			return DESCS[t] % SPRING_BONUS
	return DESCS[t]


static func blocks_growth(t: int) -> bool:
	return t == Type.ROCK or t == Type.SPRING


## 在空的平地上随机撒地块。counts: Type -> 数量。返回新增的格子。
## min_dist 可以限定只撒在外圈（牌桌扩张时用）。
static func scatter(tree: TreeModel, rng: RandomNumberGenerator, counts: Dictionary, min_dist: int = MIN_DIST) -> Array[Vector2i]:
	var free: Array[Vector2i] = []
	for c in Hex.all_cells(tree.radius):
		if Hex.distance(c, TreeModel.SEED_KEY) >= maxi(min_dist, MIN_DIST) and not tree.has(c) and tree.land_at(c) == Type.PLAIN:
			free.append(c)
	var added: Array[Vector2i] = []
	for t in counts:
		for i in counts[t]:
			if free.is_empty():
				return added
			var c: Vector2i = free.pop_at(rng.randi_range(0, free.size() - 1))
			tree.land[c] = t
			added.append(c)
	return added
