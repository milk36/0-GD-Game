extends Control
## 消除粒子系统:纯数据数组 + _draw 自绘,挂在 BoardView 下覆盖棋盘。
## 每个粒子 {p, v, c, life, max_life, size},带重力与阻尼,淡出消失。

const DEFS := preload("res://scripts/tetris/tetris_defs.gd")
const Board := preload("res://scripts/tetris/board.gd")

const CELL := 32
const GRAVITY := 340.0
const DAMP := 0.985
const MAX_PARTICLES := 3200

var _particles: Array[Dictionary] = []


func burst_cell(cell: Vector2i, cell_type: int, count: int) -> void:
	## 在棋盘某格(cell 为含隐藏行的棋盘坐标)爆出粒子;cell_type 为 board.cells 值。
	if cell_type <= 0:
		return
	var col: Color = DEFS.color(cell_type - 1)
	var center := Vector2(
		cell.x * CELL + CELL / 2.0,
		(cell.y - Board.HIDDEN) * CELL + CELL / 2.0)
	for i in count:
		if _particles.size() >= MAX_PARTICLES:
			_particles.pop_front()
		var ang := randf() * TAU
		var speed := randf_range(50.0, 180.0)
		var white := randf() < 0.2
		_particles.append({
			"p": center,
			"v": Vector2(cos(ang), sin(ang)) * speed,
			"c": col.lightened(0.6) if white else col,
			"life": randf_range(0.4, 0.7),
			"max_life": 0.7,
			"size": randf_range(2.0, 4.0),
		})
	queue_redraw()


func _process(delta: float) -> void:
	if _particles.is_empty():
		return
	var alive: Array[Dictionary] = []
	for pt in _particles:
		var v: Vector2 = pt.v
		v.y += GRAVITY * delta
		pt.v = v * DAMP
		pt.p = pt.p + pt.v * delta
		pt.life = pt.life - delta
		if pt.life > 0.0:
			alive.append(pt)
	_particles = alive
	queue_redraw()


func _draw() -> void:
	for pt in _particles:
		var a: float = clampf(pt.life / pt.max_life, 0.0, 1.0)
		var c: Color = pt.c
		c.a = a
		var s: float = pt.size
		draw_rect(Rect2(pt.p - Vector2(s, s) / 2.0, Vector2(s, s)), c)
