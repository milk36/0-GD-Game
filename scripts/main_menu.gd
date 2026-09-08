extends Control
## 游戏大厅主菜单：展示游戏列表，已实现的游戏跳转对应场景。

const GAME_SCENES := {
	"俄罗斯方块": "res://scenes/tetris.tscn",
}


@onready var _list: VBoxContainer = $UILayer/Center/Panel/Margin/List
@onready var _status: Label = $UILayer/Center/Panel/Margin/List/StatusLabel


func _ready() -> void:
	for child in _list.get_children():
		if child is Button:
			child.pressed.connect(_on_game_selected.bind(child.text))
	_status.text = ""


func _on_game_selected(game_name: String) -> void:
	if GAME_SCENES.has(game_name):
		get_tree().change_scene_to_file(GAME_SCENES[game_name])
	else:
		_status.text = "「%s」开发中，敬请期待~" % game_name
