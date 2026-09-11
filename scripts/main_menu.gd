extends Control
## 游戏大厅主菜单：展示游戏列表，已实现的游戏跳转对应场景。

const TetrisDefs := preload("res://scripts/tetris/tetris_defs.gd")

const GAME_SCENES := {
	"俄罗斯方块": "res://scenes/tetris.tscn",
	"俄罗斯方块·欢乐模式": "res://scenes/tetris.tscn",
	"方块雄鹰": "res://scenes/voxel_eagle.tscn",
	"瓦片雄鹰": "res://scenes/tile_eagle.tscn",
}


@onready var _list: VBoxContainer = $UILayer/Center/Panel/Margin/List
@onready var _status: Label = $UILayer/Center/Panel/Margin/List/StatusLabel


func _ready() -> void:
	for child in _list.get_children():
		if child is Button:
			child.pressed.connect(_on_game_selected.bind(child.text))
	_status.text = ""
	# 大厅空闲时逐帧预热程序化音效，进游戏后首次触发不再有合成抖动
	SFX.prewarm_async()


func _on_game_selected(game_name: String) -> void:
	if GAME_SCENES.has(game_name):
		TetrisDefs.fun_mode = game_name == "俄罗斯方块·欢乐模式"
		get_tree().change_scene_to_file(GAME_SCENES[game_name])
	else:
		_status.text = "「%s」开发中，敬请期待~" % game_name
