extends Control
## 棋盘渲染:网格、霓虹格子(多层半透明描边模拟辉光)、当前块、幽灵块、
## 消行故障动画、硬降震动。全部 _draw 自绘,不依赖 Bloom。

const DEFS := preload("res://scripts/tetris/tetris_defs.gd")
const Board := preload("res://scripts/tetris/board.gd")

const CELL := 32
const BOARD_W := Board.WIDTH * CELL
const BOARD_H := (Board.HEIGHT - Board.HIDDEN) * CELL

var board: RefCounted = null
var current: Dictionary = {}
var clearing_rows: Array[int] = []
var clear_progress := 0.0  # 0→1,由 tetris_game 每帧同步
var shake_time := 0.0


func _process(delta: float) -> void:
	if shake_time > 0.0:
		shake_time -= delta
	if clearing_rows.size() > 0 or shake_time > 0.0:
		queue_redraw()


func shake() -> void:
	shake_time = 0.18
	queue_redraw()


func start_clear(rows: Array[int]) -> void:
	clearing_rows = rows.duplicate()
	clear_progress = 0.0
	queue_redraw()


func stop_clear() -> void:
	clearing_rows = []
	queue_redraw()


func _draw() -> void:
	var off := Vector2.ZERO
	if shake_time > 0.0:
		off = Vector2(randf_range(-2.5, 2.5), randf_range(1.0, 3.0))

	# 棋盘底色
	draw_rect(Rect2(off, Vector2(BOARD_W, BOARD_H)), Color("#0a0e1a"))
	# 内部网格
	var grid_c := Color("#16203a")
	for x in Board.WIDTH + 1:
		draw_line(off + Vector2(x * CELL, 0), off + Vector2(x * CELL, BOARD_H), grid_c)
	for y in 21:
		draw_line(off + Vector2(0, y * CELL), off + Vector2(BOARD_W, y * CELL), grid_c)

	if board != null:
		_draw_locked(off)

	if not current.is_empty() and board != null:
		_draw_active(off)

	_draw_frame(off)


func _draw_locked(off: Vector2) -> void:
	var clearing_set := {}
	for r in clearing_rows:
		clearing_set[r] = true
	for y in range(Board.HIDDEN, Board.HEIGHT):
		for x in Board.WIDTH:
			var t: int = board.cells[y][x]
			if t == 0:
				continue
			var rect := Rect2(
				off + Vector2(x * CELL, (y - Board.HIDDEN) * CELL) + Vector2(2, 2),
				Vector2(CELL - 4, CELL - 4))
			if clearing_set.has(y):
				_draw_clearing_cell(rect, DEFS.color(t - 1))
			else:
				_draw_neon_cell(rect, DEFS.color(t - 1))


func _draw_active(off: Vector2) -> void:
	var ghost_y := _ghost_y()
	var col: Color = DEFS.color(current.type)
	for c in DEFS.shape(current.type, current.rot):
		var gx: int = current.x + c.x
		var gy: int = current.y + c.y
		var g_y: int = ghost_y + c.y
		# 幽灵块(落点指示)
		var g_rect := Rect2(
			off + Vector2(gx * CELL, (g_y - Board.HIDDEN) * CELL) + Vector2(2, 2),
			Vector2(CELL - 4, CELL - 4))
		_draw_ghost_cell(g_rect, col)
		# 当前块(只画可视区)
		if gy >= Board.HIDDEN:
			var rect := Rect2(
				off + Vector2(gx * CELL, (gy - Board.HIDDEN) * CELL) + Vector2(2, 2),
				Vector2(CELL - 4, CELL - 4))
			_draw_neon_cell(rect, col, true)


func _ghost_y() -> int:
	var y: int = current.y
	while board.can_place(current.type, current.rot, current.x, y + 1):
		y += 1
	return y


func _draw_frame(off: Vector2) -> void:
	draw_rect(Rect2(off - Vector2(3, 3), Vector2(BOARD_W + 6, BOARD_H + 6)),
		Color("#00f0ff", 0.10), false, 6.0)
	draw_rect(Rect2(off - Vector2(1, 1), Vector2(BOARD_W + 2, BOARD_H + 2)),
		Color("#00f0ff", 0.8), false, 2.0)


func _draw_neon_cell(r: Rect2, col: Color, bright := false) -> void:
	var fill := col.darkened(0.2 if bright else 0.45)
	fill.a = 0.95 if bright else 0.85
	draw_rect(r, fill)
	var glow_a := 0.16 if bright else 0.10
	for i in 3:
		draw_rect(r.grow(1.5 + i * 2.0), Color(col, glow_a * (1.0 - i / 3.0)), false, 2.0)
	draw_rect(r, col.lightened(0.25), false, 1.6)
	draw_line(r.position + Vector2(2, r.size.y - 3),
		r.position + Vector2(r.size.x - 3, r.size.y - 3),
		Color(col.lightened(0.5), 0.5), 1.0)


func _draw_ghost_cell(r: Rect2, col: Color) -> void:
	draw_rect(r, Color(col, 0.10))
	draw_rect(r, Color(col, 0.45), false, 1.2)


func _draw_clearing_cell(r: Rect2, col: Color) -> void:
	var p := clear_progress
	draw_rect(r, Color(col, 0.6 * (1.0 - p)))
	var flash := Color(1, 1, 1, clampf(1.0 - p * 1.4, 0.0, 1.0))
	var shift: float = sin(p * 40.0 + r.position.y) * 6.0 * (1.0 - p)
	draw_rect(Rect2(r.position + Vector2(shift, 0), r.size), flash, false, 2.0)
