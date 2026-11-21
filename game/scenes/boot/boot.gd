extends Node
## 启动：载入牌库，然后进入主菜单。


func _ready() -> void:
	Cards.ensure_loaded()
	Game.goto(&"menu")
