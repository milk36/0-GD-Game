extends Control
## 消除粒子系统:纯数据数组 + _draw 自绘,挂在 BoardView 下覆盖棋盘。
## 每个粒子 {p, v, c, life, max_life, size, kind, grav}:
## kind="dot"方块点(默认) / "trail"沿速度方向的拖尾线;grav 为重力系数。

const DEFS := preload("res://scripts/tetris/tetris_defs.gd")
const Board := preload("res://scripts/tetris/board.gd")

const CELL := 32
const GRAVITY := 340.0
const DAMP := 0.985
const MAX_PARTICLES := 3200
const TRAIL_LEN := 12.0

var _particles: Array[Dictionary] = []


func _append(pt: Dictionary) -> void:
	if _particles.size() >= MAX_PARTICLES:
		_particles.pop_front()
	_particles.append(pt)


func burst_cell(cell: Vector2i, cell_type: int, count: int) -> void:
	## 在棋盘某格(cell 为含隐藏行的棋盘坐标)爆出粒子;cell_type 为 board.cells 值。
	if cell_type <= 0:
		return
	var col: Color = DEFS.color(cell_type - 1)
	var center := Vector2(
		cell.x * CELL + CELL / 2.0,
		(cell.y - Board.HIDDEN) * CELL + CELL / 2.0)
	for i in count:
		var ang := randf() * TAU
		var speed := randf_range(50.0, 180.0)
		var white := randf() < 0.2
		_append({
			"p": center,
			"v": Vector2(cos(ang), sin(ang)) * speed,
			"c": col.lightened(0.6) if white else col,
			"life": randf_range(0.4, 0.7),
			"max_life": 0.7,
			"size": randf_range(2.0, 4.0),
			"kind": "dot",
			"grav": 1.0,
		})
	queue_redraw()


func wind_streaks_row(row_y: int, count: int) -> void:
	## 风:行内横向高速风痕(浅青拖尾线),免重力,双向随机。
	var col: Color = DEFS.ITEM_COLORS[DEFS.Item.WIND]
	var yc := (row_y - Board.HIDDEN) * CELL + CELL / 2.0
	for i in count:
		var dir := 1.0 if randf() < 0.5 else -1.0
		_append({
			"p": Vector2(randf() * Board.WIDTH * CELL, yc + randf_range(-10.0, 10.0)),
			"v": Vector2(dir * randf_range(260.0, 480.0), randf_range(-40.0, 40.0)),
			"c": col.lightened(randf_range(0.0, 0.5)),
			"life": randf_range(0.22, 0.4),
			"max_life": 0.4,
			"size": 2.0,
			"kind": "trail",
			"grav": 0.0,
		})
	queue_redraw()


func rain_drops(cell: Vector2i, count: int) -> void:
	## 雨:从被消格上方坠落的蓝白雨滴拖尾。
	var col: Color = DEFS.ITEM_COLORS[DEFS.Item.RAIN]
	var cx := cell.x * CELL + CELL / 2.0
	var top := (cell.y - Board.HIDDEN) * CELL
	for i in count:
		_append({
			"p": Vector2(cx + randf_range(-10.0, 10.0), top - randf_range(4.0, 30.0)),
			"v": Vector2(randf_range(-20.0, 20.0), randf_range(140.0, 280.0)),
			"c": col.lightened(randf_range(0.2, 0.7)),
			"life": randf_range(0.3, 0.5),
			"max_life": 0.5,
			"size": 2.0,
			"kind": "trail",
			"grav": 1.0,
		})
	queue_redraw()


func bolt_arcs(col_x: int, count: int) -> void:
	## 雷:列内随机高度爆出的黄白电弧短拖尾。
	var col: Color = DEFS.ITEM_COLORS[DEFS.Item.BOLT]
	var cx := col_x * CELL + CELL / 2.0
	var vis_h := (Board.HEIGHT - Board.HIDDEN) * CELL
	for i in count:
		var white := randf() < 0.4
		_append({
			"p": Vector2(cx + randf_range(-12.0, 12.0), randf() * vis_h),
			"v": Vector2(randf_range(-260.0, 260.0), randf_range(-160.0, 160.0)),
			"c": Color(1, 1, 1) if white else col.lightened(randf_range(0.1, 0.4)),
			"life": randf_range(0.15, 0.35),
			"max_life": 0.35,
			"size": 2.0,
			"kind": "trail",
			"grav": 0.3,
		})
	queue_redraw()


func _process(delta: float) -> void:
	if _particles.is_empty():
		return
	var alive: Array[Dictionary] = []
	for pt in _particles:
		var v: Vector2 = pt.v
		v.y += GRAVITY * float(pt.get("grav", 1.0)) * delta
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
		if pt.get("kind", "dot") == "trail":
			var v: Vector2 = pt.v
			if v.length() > 1.0:
				draw_line(pt.p, pt.p - v.normalized() * TRAIL_LEN, c, 1.6)
			continue
		var s: float = pt.size
		draw_rect(Rect2(pt.p - Vector2(s, s) / 2.0, Vector2(s, s)), c)
