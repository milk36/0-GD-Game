extends Control
## 棋盘渲染:网格、霓虹格子(多层半透明描边模拟辉光)、当前块、幽灵块、
## 消行故障动画、硬降震动、道具碎片格与道具特效。全部 _draw 自绘。

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

# ---- 道具碎片格(可多格并存) ----
var item_cells: Array[Vector2i] = []   # 棋盘坐标
var item_ratios: Array[float] = []     # 各格剩余时间比例

# ---- 道具特效预闪 ----
var fx_active := false
var fx_kind := -1                  # DEFS.Item
var fx_rows: Array[int] = []
var fx_cols: Array[int] = []
var fx_cells: Array[Vector2i] = []
var fx_progress := 0.0             # 0→1,由 tetris_game 每帧同步
var _bolt_zigzags: Array = []      # 雷电:每列 3 条候选锯齿折线(每次预闪重新生成)


func _process(delta: float) -> void:
	if shake_time > 0.0:
		shake_time -= delta
	if clearing_rows.size() > 0 or shake_time > 0.0 \
			or item_cells.size() > 0 or fx_active:
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


func set_item_cells(cells: Array, ratios: Array) -> void:
	item_cells = []
	for c in cells:
		var ci: Vector2i = c
		item_cells.append(ci)
	item_ratios = []
	for r in ratios:
		var rf: float = r
		item_ratios.append(rf)
	queue_redraw()


func show_item_fx(kind: int, rows: Array, cols: Array, cells: Array) -> void:
	fx_active = true
	fx_kind = kind
	fx_rows = []
	for r in rows:
		fx_rows.append(r)
	fx_cols = []
	for c in cols:
		fx_cols.append(c)
	fx_cells = []
	for c in cells:
		fx_cells.append(c)
	_bolt_zigzags = []
	if kind == DEFS.Item.BOLT or kind == DEFS.Item.THUNDER:
		for c in cols:
			var zl: Array = []
			for k in 3:
				zl.append(_gen_zigzag(int(c)))
			_bolt_zigzags.append(zl)
	fx_progress = 0.0
	queue_redraw()


func hide_item_fx() -> void:
	fx_active = false
	_bolt_zigzags = []
	queue_redraw()


func _gen_zigzag(col: int) -> PackedVector2Array:
	## 从可视棋盘顶到底的锯齿折线点集(段高 14~22px,x 抖动 ±9)。
	var pts := PackedVector2Array()
	var cx := col * CELL + CELL / 2.0
	pts.append(Vector2(cx, 0.0))
	var y := 0.0
	while y < BOARD_H:
		y = minf(y + 14.0 + randf() * 8.0, float(BOARD_H))
		pts.append(Vector2(cx + randf_range(-9.0, 9.0), y))
	return pts


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

	if fx_active:
		_draw_item_fx(off)

	if item_cells.size() > 0:
		_draw_item_cells(off)

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
		var g_rect := Rect2(
			off + Vector2(gx * CELL, (g_y - Board.HIDDEN) * CELL) + Vector2(2, 2),
			Vector2(CELL - 4, CELL - 4))
		_draw_ghost_cell(g_rect, col)
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


## ---- 道具碎片格(金色脉动框 + 倒计时弧,可多格) ----
func _draw_item_cells(off: Vector2) -> void:
	for i in item_cells.size():
		var cell: Vector2i = item_cells[i]
		if cell.y < Board.HIDDEN:
			continue
		var ratio := item_ratios[i] if i < item_ratios.size() else 1.0
		var pos := off + Vector2(cell.x * CELL, (cell.y - Board.HIDDEN) * CELL)
		var t := float(Time.get_ticks_msec()) / 1000.0
		var pulse := 0.55 + 0.45 * sin(t * 6.0 + i * 1.3)  # 各格相位错开
		var col := DEFS.ITEM_CELL_COLOR
		# 脉动外框(双层)
		draw_rect(Rect2(pos - Vector2(3, 3), Vector2(CELL + 6, CELL + 6)),
			Color(col, 0.25 * pulse), false, 3.0)
		draw_rect(Rect2(pos + Vector2(3, 3), Vector2(CELL - 6, CELL - 6)),
			Color(col, 0.9 * pulse), false, 1.5)
		# 倒计时弧(格子右上角)
		var center := pos + Vector2(CELL - 8, 8)
		draw_arc(center, 5.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 12,
			Color(col, 0.95), 2.0)
		# 中心菱形标记
		var mid := pos + Vector2(CELL / 2.0, CELL / 2.0)
		var d := 4.0 + 1.5 * pulse
		draw_line(mid - Vector2(d, 0), mid + Vector2(d, 0), Color(col, 0.9), 1.5)
		draw_line(mid - Vector2(0, d / 2.0), mid + Vector2(0, d / 2.0), Color(col, 0.9), 1.5)


## ---- 道具特效预闪(专属演出,全部由 fx_progress 驱动 → 暂停天然冻结) ----
func _fx_blink() -> float:
	## 预闪通用脉动系数（各演出共用同一节拍）
	return 0.35 + 0.45 * absf(sin(fx_progress * TAU * 2.0))


func _draw_item_fx(off: Vector2) -> void:
	var col: Color = DEFS.ITEM_COLORS.get(fx_kind, Color.WHITE)
	# 进化版复用基础版演出(只是目标更多)
	var visual := fx_kind
	if visual == DEFS.Item.STORM_WIND:
		visual = DEFS.Item.WIND
	elif visual == DEFS.Item.TORRENT:
		visual = DEFS.Item.RAIN
	elif visual == DEFS.Item.THUNDER:
		visual = DEFS.Item.BOLT
	match visual:
		DEFS.Item.WIND:
			_draw_wind_fx(off, col)
		DEFS.Item.RAIN:
			_draw_rain_fx(off, col)
		DEFS.Item.BOLT:
			_draw_bolt_fx(off, col)
		DEFS.Item.FLIP:
			_draw_flip_fx(off, col)
		DEFS.Item.PRUNE:
			_draw_prune_fx(off, col)


func _draw_flip_fx(off: Vector2, col: Color) -> void:
	## 翻转:中央对称轴亮起,左右两条竖直扫描线向中轴收拢,扫过半区微光。
	var blink := _fx_blink()
	var mid_x := off.x + BOARD_W / 2.0
	draw_line(Vector2(mid_x, off.y), Vector2(mid_x, off.y + BOARD_H),
		Color(col, 0.45 + 0.45 * blink), 2.0)
	var half := BOARD_W / 2.0
	for side in 2:
		var dir := -1.0 if side == 0 else 1.0
		var head_x := off.x + half + dir * half * (1.0 - fx_progress)
		var tail_x := off.x + half + dir * half * (1.0 - fx_progress * 0.4)
		draw_line(Vector2(head_x, off.y), Vector2(head_x, off.y + BOARD_H),
			Color(col, 0.9), 2.5)
		draw_line(Vector2(tail_x, off.y), Vector2(tail_x, off.y + BOARD_H),
			Color(col, 0.3), 1.2)
		var edge_x := off.x if side == 0 else off.x + BOARD_W
		draw_rect(Rect2(Vector2(minf(edge_x, head_x), off.y),
			Vector2(absf(head_x - edge_x), BOARD_H)), Color(col, 0.07))


func _draw_prune_fx(off: Vector2, col: Color) -> void:
	## 削峰:每列最顶端格同时亮起,格顶一对向上的刀光指示。
	var blink := _fx_blink()
	for cell in fx_cells:
		if cell.y < Board.HIDDEN:
			continue
		var pos := off + Vector2(cell.x * CELL, (cell.y - Board.HIDDEN) * CELL)
		var rect := Rect2(pos + Vector2(3, 3), Vector2(CELL - 6, CELL - 6))
		draw_rect(rect, Color(col, 0.40))
		draw_rect(rect, Color(1, 1, 1, 0.9 * blink), false, 2.0)
		var cx := pos.x + CELL / 2.0
		var top := pos.y - 2.0
		draw_line(Vector2(cx - 5, top - 11), Vector2(cx, top), Color(col, 0.9), 2.0)
		draw_line(Vector2(cx + 5, top - 11), Vector2(cx, top), Color(col, 0.9), 2.0)


func _draw_wind_fx(off: Vector2, col: Color) -> void:
	## 风:行青色高亮(0~0.15s) → 左右两条速度线横向扫过。
	var blink := _fx_blink()
	for r in fx_rows:
		if r < Board.HIDDEN:
			continue
		var y := (r - Board.HIDDEN) * CELL
		draw_rect(Rect2(off + Vector2(0, y + 2), Vector2(BOARD_W, CELL - 4)),
			Color(col, 0.30 * blink))
		draw_line(off + Vector2(0, y + 1), off + Vector2(BOARD_W, y + 1),
			Color(col, blink), 1.5)
	var p2 := clampf(
		(fx_progress * DEFS.ITEM_FX_TIME - DEFS.ITEM_WIND_HL_TIME)
		/ (DEFS.ITEM_FX_TIME - DEFS.ITEM_WIND_HL_TIME), 0.0, 1.0)
	if p2 <= 0.0:
		return
	var span := float(BOARD_W) + WIND_STREAK_LEN * 2.0
	for r in fx_rows:
		if r < Board.HIDDEN:
			continue
		var ym := (r - Board.HIDDEN) * CELL + CELL / 2.0
		_draw_wind_streak(off + Vector2(-WIND_STREAK_LEN + p2 * span, ym), 1.0, col)
		_draw_wind_streak(off + Vector2(float(BOARD_W) + WIND_STREAK_LEN - p2 * span, ym),
			-1.0, col)


const WIND_STREAK_LEN := 110.0


func _draw_wind_streak(head: Vector2, dir: float, col: Color) -> void:
	## 单条风痕:头部亮、向后 3 段渐隐渐细。
	for i in 3:
		var fi := float(i)
		var a := 0.85 * (1.0 - fi / 3.0)
		var x0 := head.x - dir * WIND_STREAK_LEN * (fi / 3.0)
		var x1 := head.x - dir * WIND_STREAK_LEN * ((fi + 1.0) / 3.0)
		draw_line(Vector2(x0, head.y), Vector2(x1, head.y),
			Color(col, a), 3.0 - 0.7 * fi)


func _draw_rain_fx(off: Vector2, col: Color) -> void:
	## 雨:散点格按 30ms 间隔逐个蓝白闪现,已闪现格上方雨滴循环坠落。
	var blink := _fx_blink()
	var elapsed := fx_progress * DEFS.ITEM_FX_TIME
	var lit := clampi(int(elapsed / DEFS.ITEM_RAIN_STEP), 0, fx_cells.size())
	for i in fx_cells.size():
		var cell: Vector2i = fx_cells[i]
		if cell.y < Board.HIDDEN:
			continue
		var pos := off + Vector2(cell.x * CELL, (cell.y - Board.HIDDEN) * CELL)
		var rect := Rect2(pos + Vector2(4, 4), Vector2(CELL - 8, CELL - 8))
		if i < lit:
			draw_rect(rect, Color(col, 0.45))
			draw_rect(rect, Color(1, 1, 1, 0.9 * blink), false, 2.0)
			for k in 2:
				var ph := fposmod(fx_progress * 6.0 + float(i) * 0.37 + float(k) * 0.5, 1.0)
				var drop_y := pos.y + ph * 72.0 - 72.0
				draw_line(Vector2(pos.x + 8 + k * 12, drop_y),
					Vector2(pos.x + 8 + k * 12, drop_y + 14.0),
					Color(col.lightened(0.4), 0.7 * (1.0 - ph)), 1.5)
		else:
			draw_rect(rect, Color(col, 0.16), false, 1.2)


func _draw_bolt_fx(off: Vector2, col: Color) -> void:
	## 雷:列高亮 + 锯齿电光自顶部向底部扫描(0.2s) → 整列闪白。
	var blink := _fx_blink()
	for c in fx_cols:
		var x := c * CELL
		draw_rect(Rect2(off + Vector2(x + 2, 0), Vector2(CELL - 4, BOARD_H)),
			Color(col, 0.22 * blink))
	var zig_p := clampf(fx_progress * DEFS.ITEM_FX_TIME / DEFS.ITEM_BOLT_ZIG_TIME,
		0.0, 1.0)
	if zig_p < 1.0:
		var head_y := zig_p * float(BOARD_H)
		for ci in fx_cols.size():
			if ci >= _bolt_zigzags.size():
				continue
			var zl: Array = _bolt_zigzags[ci]
			var pts: PackedVector2Array = zl[(int(fx_progress * 24.0) + ci) % zl.size()]
			_draw_zigzag_to_y(off, pts, head_y, col)
	else:
		var flash := 0.5 + 0.5 * sin(fx_progress * TAU * 6.0)
		for c in fx_cols:
			var x := c * CELL
			draw_rect(Rect2(off + Vector2(x + 2, 0), Vector2(CELL - 4, BOARD_H)),
				Color(1, 1, 1, 0.35 + 0.3 * flash))
			draw_rect(Rect2(off + Vector2(x + 1, 0), Vector2(CELL - 2, BOARD_H)),
				Color(col, blink), false, 2.0)


func _draw_zigzag_to_y(off: Vector2, pts: PackedVector2Array, head_y: float,
		col: Color) -> void:
	## 绘制锯齿折线到 head_y 为止(电光下扫),黄粗白细双层 + 头部亮点。
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if a.y >= head_y:
			break
		var b2 := b
		if b.y > head_y:
			b2.y = head_y
		draw_line(off + a, off + b2, Color(col.lightened(0.3), 0.95), 2.5)
		draw_line(off + a, off + b2, Color(1, 1, 1, 0.6), 1.0)
	draw_circle(off + Vector2(pts[0].x, head_y), 3.0, Color(1, 1, 1, 0.9))
