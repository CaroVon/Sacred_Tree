class_name RelicDef
extends Resource
## 守林人的器物：作用于全局规则。具体效果由 RunState / Pulse 按 id 读取。

@export var id: StringName
@export var display_name: String = ""
## 集市价格（养分）；出售返还一半。
@export var price: int = 8
## 所属流派（空 = 通用），用于奖励引导与图鉴分组。
@export var family: StringName = &""
@export_multiline var desc: String = ""
