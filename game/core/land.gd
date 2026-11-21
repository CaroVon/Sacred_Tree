class_name Land
extends RefCounted
## 土地地块：作用于某一个格子。

enum Type { PLAIN, FERTILE, ROCK, SPRING }

const NAMES := ["平地", "沃土", "岩石", "泉眼"]
const DESCS := [
	"",
	"长在这里的牌流出养分 +%d",
	"无法生长",
	"无法生长；相邻的末梢 +%d",
]
const FERTILE_BONUS := 2
const SPRING_BONUS := 2
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
static func scatter(tree: TreeModel, rng: RandomNumberGenerator, counts: Dictionary) -> Array[Vector2i]:
	var free: Array[Vector2i] = []
	for c in Hex.all_cells(tree.radius):
		if Hex.distance(c, TreeModel.SEED_KEY) >= MIN_DIST and not tree.has(c) and tree.land_at(c) == Type.PLAIN:
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
