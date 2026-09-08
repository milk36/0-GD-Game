extends Control
## Hold / Next 面板的方块小预览,自绘霓虹格子。

const DEFS := preload("res://scripts/tetris/tetris_defs.gd")

@export var cell := 18
@export var slots := 1

var _types: Array[int] = []


func show_types(types: Array) -> void:
	_types = []
	for t in types:
		var ti: int = t
		if ti >= 0:
			_types.append(ti)
	queue_redraw()


func _draw() -> void:
	var slot_h := size.y / maxf(slots, 1.0)
	for i in _types.size():
		if i >= slots:
			break
		var t: int = _types[i]
		var shape: Array = DEFS.shape(t, 0)
		var min_x: int = shape[0].x
		var min_y: int = shape[0].y
		var max_x: int = shape[0].x
		var max_y: int = shape[0].y
		for c in shape:
			min_x = min(min_x, c.x)
			min_y = min(min_y, c.y)
			max_x = max(max_x, c.x)
			max_y = max(max_y, c.y)
		var w := float(max_x - min_x + 1) * cell
		var h := float(max_y - min_y + 1) * cell
		var origin := Vector2((size.x - w) / 2.0, i * slot_h + (slot_h - h) / 2.0)
		var col: Color = DEFS.color(t)
		for c in shape:
			var pos := origin + Vector2(c.x - min_x, c.y - min_y) * cell
			var r := Rect2(pos + Vector2(2, 2), Vector2(cell - 4, cell - 4))
			draw_rect(r, col.darkened(0.45))
			draw_rect(r.grow(2), Color(col, 0.22), false, 1.0)
			draw_rect(r, col.lightened(0.15), false, 1.5)
