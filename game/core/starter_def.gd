class_name StarterDef
extends Resource
## 启程者：开局身份 = 起手牌组 + 一件起手器物。决定开局倾向，但不锁死后续构筑。

@export var id: StringName
@export var display_name: String = ""
@export_multiline var desc: String = ""
## 起手牌组：牌 id -> 张数。
@export var deck: Dictionary = {}
## 起手器物（空 = 没有）。
@export var relic: StringName = &""
## 主打流派（界面用）。
@export var families: Array[StringName] = []
## 排序用。
@export var order: int = 0
