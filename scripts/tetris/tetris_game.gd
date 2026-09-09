extends Control
## 赛博朋克俄罗斯方块主控:状态机、重力、输入调度、计分、暂停与结算、
## 道具系统(风/雨/雷电碎片格,获取后自动触发)。

const DEFS := preload("res://scripts/tetris/tetris_defs.gd")
const Board := preload("res://scripts/tetris/board.gd")
const Bag := preload("res://scripts/tetris/bag.gd")

const SCORE_TABLE := [0, 100, 300, 500, 800]
const CLEAR_TIME := 0.28
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const DAS_DELAY := 0.16
const DAS_REPEAT := 0.045
const SAVE_PATH := "user://tetris_score.dat"
const FLOAT_TIME := 1.4

enum State { PLAYING, CLEARING, ITEM_FX, PAUSED, GAME_OVER }

var board: RefCounted
var bag: RefCounted
var current: Dictionary = {}
var next_queue: Array[int] = []
var hold_type := -1
var hold_used := false

var state := State.PLAYING
var score := 0
var lines := 0
var level := 1
var hi_score := 0

var drop_timer := 0.0
var lock_timer := 0.0
var lock_resets := 0
var clear_timer := 0.0
var das_dir := 0
var das_timer := 0.0

# ---- 道具系统 ----
var item_cells: Array = []          # 并存碎片格 [{cell: Vector2i, life: float}]
var item_spawn_timer := 0.0          # 距下次刷新倒计时
var item_params: Dictionary = {}     # 当前模式参数(DEFS.ITEM_PARAMS)
var item_queue: Array[int] = []      # 待执行道具队列(多格同消时依次连发)
var fx_kind := -1                    # ITEM_FX 待执行的道具
var item_fx_timer := 0.0
var fx_rows: Array[int] = []         # 风/飓风:目标行
var fx_cols: Array[int] = []         # 雷/雷暴:目标列
var fx_rain_cells: Array = []        # 雨/暴雨:目标格 [{pos, t}]
var fx_peak_cells: Array = []        # 削峰:每列最顶端格 [{pos, t}]
var float_time := 0.0                # 浮字剩余时间
var _paused_from := State.PLAYING    # 暂停前的状态(恢复用)
var _tick_step := -1                 # 碎片格倒计时滴答档位(避免重复播同一秒)

@onready var board_view: Control = $Center/Layout/BoardView
@onready var particles: Control = $Center/Layout/BoardView/Particles
@onready var float_label: Label = $FloatLabel
@onready var mode_label: Label = $Center/Layout/LeftPanel/ModeLabel
@onready var hold_preview: Control = $Center/Layout/RightPanel/HoldBox/HoldPreview
@onready var next_preview: Control = $Center/Layout/RightPanel/NextBox/NextPreview
@onready var score_label: Label = $Center/Layout/RightPanel/Stats/ScoreValue
@onready var level_label: Label = $Center/Layout/RightPanel/Stats/LevelValue
@onready var lines_label: Label = $Center/Layout/RightPanel/Stats/LinesValue
@onready var hi_label: Label = $Center/Layout/RightPanel/Stats/HiValue
@onready var pause_overlay: Control = $PauseOverlay
@onready var gameover_overlay: Control = $GameOverOverlay
@onready var gameover_score: Label = $GameOverOverlay/Center/Box/FinalScore
@onready var new_record: Label = $GameOverOverlay/Center/Box/NewRecord


func _ready() -> void:
	_load_hi()
	board = Board.new()
	bag = Bag.new()
	board_view.board = board
	while next_queue.size() < 4:
		next_queue.append(bag.next())
	($PauseOverlay/Center/Box/ResumeButton as Button).pressed.connect(_toggle_pause)
	($PauseOverlay/Center/Box/RestartButton as Button).pressed.connect(_restart)
	($PauseOverlay/Center/Box/MenuButton as Button).pressed.connect(_back_to_menu)
	($GameOverOverlay/Center/Box/RetryButton as Button).pressed.connect(_restart)
	($GameOverOverlay/Center/Box/MenuButton as Button).pressed.connect(_back_to_menu)
	item_params = DEFS.ITEM_PARAMS.get(DEFS.fun_mode, DEFS.ITEM_PARAMS[false])
	item_spawn_timer = item_params.first
	_sync_item_cells()
	_sync_mode_label()
	_spawn()
	_update_hud()


func _process(delta: float) -> void:
	# 浮字淡出(任何状态)
	if float_label.visible:
		float_time -= delta
		float_label.modulate.a = clampf(float_time / FLOAT_TIME, 0.0, 1.0)
		if float_time <= 0.0:
			float_label.visible = false

	match state:
		State.PLAYING:
			_handle_input(delta)
			if state == State.PLAYING:
				_gravity(delta)
				_update_item(delta)
		State.CLEARING:
			clear_timer -= delta
			board_view.clear_progress = 1.0 - clampf(clear_timer / CLEAR_TIME, 0.0, 1.0)
			board_view.queue_redraw()
			if clear_timer <= 0.0:
				_finish_clear()
		State.ITEM_FX:
			item_fx_timer -= delta
			board_view.fx_progress = 1.0 - clampf(item_fx_timer / DEFS.ITEM_FX_TIME, 0.0, 1.0)
			if item_fx_timer <= 0.0:
				_execute_item()
		State.PAUSED:
			if Input.is_action_just_pressed("tetris_pause"):
				_toggle_pause()
		State.GAME_OVER:
			pass


func _handle_input(delta: float) -> void:
	if Input.is_action_just_pressed("tetris_pause"):
		_toggle_pause()
		return
	if Input.is_action_just_pressed("tetris_rotate_cw"):
		_try_rotate(1)
	if Input.is_action_just_pressed("tetris_rotate_ccw"):
		_try_rotate(-1)
	if Input.is_action_just_pressed("tetris_hard_drop"):
		_hard_drop()
		return
	if Input.is_action_just_pressed("tetris_hold"):
		_hold()
	# 横向移动 + DAS 连发
	var dir := 0
	if Input.is_action_pressed("tetris_left"):
		dir -= 1
	if Input.is_action_pressed("tetris_right"):
		dir += 1
	if dir != das_dir:
		das_dir = dir
		das_timer = DAS_DELAY
		if dir != 0:
			_try_move(dir, 0)
	elif das_dir != 0:
		das_timer -= delta
		while das_timer <= 0.0:
			_try_move(das_dir, 0)
			das_timer += DAS_REPEAT


func _gravity(delta: float) -> void:
	var interval := _drop_interval()
	if Input.is_action_pressed("tetris_soft_drop"):
		interval = minf(interval, 0.045)
	var grounded: bool = not board.can_place(current.type, current.rot, current.x, current.y + 1)
	if grounded:
		drop_timer = 0.0
		lock_timer += delta
		if lock_timer >= LOCK_DELAY:
			_lock_piece()
	else:
		lock_timer = 0.0
		drop_timer += delta
		while drop_timer >= interval:
			drop_timer -= interval
			if _try_move(0, 1) and Input.is_action_pressed("tetris_soft_drop"):
				score += 1
				_update_hud()


func _drop_interval() -> float:
	return maxf(0.05, 1.0 * pow(0.85, level - 1))


func _try_move(dx: int, dy: int) -> bool:
	if board.can_place(current.type, current.rot, current.x + dx, current.y + dy):
		current.x += dx
		current.y += dy
		_after_piece_changed()
		return true
	return false


func _try_rotate(dir: int) -> void:
	if DEFS.TYPES[current.type] == "O":
		return
	var new_rot: int = wrapi(current.rot + dir, 0, 4)
	var kicks := [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
	for kick in kicks:
		if board.can_place(current.type, new_rot, current.x + kick.x, current.y + kick.y):
			current.rot = new_rot
			current.x += kick.x
			current.y += kick.y
			_after_piece_changed()
			return


func _hard_drop() -> void:
	var dist := 0
	while _try_move(0, 1):
		dist += 1
	score += dist * 2
	board_view.shake()
	_update_hud()
	_lock_piece()


func _hold() -> void:
	if hold_used:
		return
	hold_used = true
	var t: int = current.type
	if hold_type < 0:
		hold_type = t
		_spawn()
	else:
		var h: int = hold_type
		hold_type = t
		_reset_piece(h)
	hold_preview.show_types([hold_type])


func _spawn() -> void:
	_reset_piece(next_queue.pop_front())
	while next_queue.size() < 3:
		next_queue.append(bag.next())
	next_preview.show_types(next_queue.slice(0, 3))


func _reset_piece(type_index: int) -> void:
	current = {
		"type": type_index,
		"rot": 0,
		"x": DEFS.SPAWN_X,
		"y": DEFS.SPAWN_Y,
	}
	lock_timer = 0.0
	lock_resets = 0
	drop_timer = 0.0
	if not board.can_place(current.type, current.rot, current.x, current.y):
		_game_over()
		return
	_after_piece_changed()


func _after_piece_changed() -> void:
	if not board.can_place(current.type, current.rot, current.x, current.y + 1) \
			and lock_resets < MAX_LOCK_RESETS:
		lock_timer = 0.0
		lock_resets += 1
	board_view.current = current
	board_view.queue_redraw()


func _lock_piece() -> void:
	var lock_out: bool = board.lock(current.type, current.rot, current.x, current.y)
	board_view.current = {}
	var rows: Array[int] = board.full_rows()
	hold_used = false
	if lock_out and rows.is_empty():
		_game_over()
		return
	if rows.is_empty():
		_spawn()
	else:
		state = State.CLEARING
		clear_timer = CLEAR_TIME
		board_view.start_clear(rows)


func _finish_clear() -> void:
	var rows: Array[int] = board_view.clearing_rows
	# 消行前收集被消格子(供粒子取色)
	var burst_data: Array = []
	for r in rows:
		for x in Board.WIDTH:
			var t: int = board.cells[r][x]
			if t > 0:
				burst_data.append({"pos": Vector2i(x, r), "t": t})
	board.remove_rows(rows)
	for bd in burst_data:
		particles.burst_cell(bd.pos, bd.t, 9)
	var n := rows.size()
	lines += n
	score += SCORE_TABLE[n] * level
	level = floori(lines / 10.0) + 1
	if score > hi_score:
		hi_score = score
		_save_hi()
	board_view.stop_clear()
	state = State.PLAYING
	_spawn()
	_update_hud()
	# 碎片格判定:所在行被消 → 熄灭并入道具队列;否则坐标随下移修正
	var acquired := false
	for i in range(item_cells.size() - 1, -1, -1):
		var cell: Vector2i = item_cells[i].cell
		if rows.has(cell.y):
			item_cells.remove_at(i)
			_enqueue_item(randi() % DEFS.BASIC_ITEM_COUNT)
			acquired = true
		else:
			var shift := 0
			for r in rows:
				if r < cell.y:
					shift += 1
			if shift > 0:
				item_cells[i].cell = Vector2i(cell.x, cell.y - shift)
	_sync_item_cells()
	_update_tick_sfx()
	if acquired:
		SFX.play("item_get")
		_start_next_item()


# ---------------- 道具系统 ----------------

func _enqueue_item(kind: int) -> void:
	## 道具入队;队尾相邻同类基础道具合并进化(风风→飓风/雨雨→暴雨/雷雷→雷暴)。
	if DEFS.EVOLVE_MAP.has(kind) and not item_queue.is_empty() \
			and item_queue.back() == kind:
		item_queue.pop_back()
		item_queue.append(DEFS.EVOLVE_MAP[kind])
	else:
		item_queue.append(kind)

func _update_item(delta: float) -> void:
	## 碎片格刷新与存活计时(仅 PLAYING 调用,暂停天然冻结)。
	# 刷新:未达并存上限时计时
	if item_cells.size() < int(item_params.max_cells):
		item_spawn_timer -= delta
		if item_spawn_timer <= 0.0:
			var c: Vector2i = board.random_filled_cell()
			if c.x >= 0 and not _has_item_cell(c):
				item_cells.append({"cell": c, "life": float(item_params.life)})
				item_spawn_timer = float(item_params.interval)
				SFX.play("shard_spawn")
			else:
				item_spawn_timer = 1.0  # 棋盘空或撞已有格,1s 后重试
	# 存活:逐格倒计时,归零单独熄灭
	var expired := false
	for i in range(item_cells.size() - 1, -1, -1):
		item_cells[i].life = item_cells[i].life - delta
		if item_cells[i].life <= 0.0:
			item_cells.remove_at(i)
			expired = true
	if expired:
		_show_float("数据丢失…", Color("#8b90a8"))
		SFX.play("shard_expire")
	_sync_item_cells()
	_update_tick_sfx()


func _update_tick_sfx() -> void:
	## 碎片格剩余 ≤3s 时逐秒滴答(音高/音量递增)。取"最快到期"的那一格为准。
	if item_cells.is_empty():
		_tick_step = -1
		return
	var ml := INF
	for d in item_cells:
		ml = minf(ml, float(d.life))
	if ml > 3.0:
		_tick_step = -1
		return
	if ml <= 0.0:
		return
	var s := int(ceil(ml))
	if s != _tick_step:
		_tick_step = s
		SFX.play("shard_tick%d" % clampi(3 - s, 0, 2))


func _has_item_cell(c: Vector2i) -> bool:
	for d in item_cells:
		if d.cell == c:
			return true
	return false


func _sync_item_cells() -> void:
	## 同步碎片格与剩余时间比例到棋盘视图。
	var cells: Array[Vector2i] = []
	var ratios: Array[float] = []
	for d in item_cells:
		cells.append(d.cell)
		ratios.append(clampf(d.life / float(item_params.life), 0.0, 1.0))
	board_view.set_item_cells(cells, ratios)


func _start_next_item() -> void:
	## 从道具队列取下一个道具执行;无可用目标则依次跳过,全部作废时提示。
	while not item_queue.is_empty():
		var kind: int = item_queue.pop_front()
		if not _select_item_targets(kind):
			continue
		fx_kind = kind
		_show_float("⌁ " + DEFS.ITEM_NAMES[kind], DEFS.ITEM_COLORS[kind])
		state = State.ITEM_FX
		item_fx_timer = DEFS.ITEM_FX_TIME
		var show_cells: Array = []
		if kind == DEFS.Item.RAIN or kind == DEFS.Item.TORRENT:
			for cd in fx_rain_cells:
				show_cells.append(cd.pos)
		elif kind == DEFS.Item.PRUNE:
			for cd in fx_peak_cells:
				show_cells.append(cd.pos)
		var is_wind := kind == DEFS.Item.WIND or kind == DEFS.Item.STORM_WIND
		var is_bolt := kind == DEFS.Item.BOLT or kind == DEFS.Item.THUNDER
		board_view.show_item_fx(
			kind,
			fx_rows if is_wind else [],
			fx_cols if is_bolt else [],
			show_cells)
		return
	_show_float("数据丢失…", Color("#8b90a8"))
	SFX.play("item_fizzle")


func _select_item_targets(kind: int) -> bool:
	## 为道具选定目标;返回 false 表示无可消目标(道具作废)。
	fx_rows = []
	fx_cols = []
	fx_rain_cells = []
	fx_peak_cells = []
	match kind:
		DEFS.Item.WIND, DEFS.Item.STORM_WIND:
			var rows: Array[int] = board.filled_row_indices()
			if rows.is_empty():
				return false
			rows.shuffle()
			var take := 2
			if kind == DEFS.Item.STORM_WIND:
				take = DEFS.STORM_WIND_ROWS
			take = mini(take, rows.size())
			for i in take:
				fx_rows.append(rows[i])
		DEFS.Item.RAIN, DEFS.Item.TORRENT:
			var all: Array[Vector2i] = board.all_filled_cells()
			if all.is_empty():
				return false
			all.shuffle()
			var n := DEFS.RAIN_MAX_CELLS
			if kind == DEFS.Item.TORRENT:
				n = DEFS.TORRENT_MAX_CELLS
			n = mini(n, all.size())
			for i in n:
				var c: Vector2i = all[i]
				fx_rain_cells.append({
					"pos": c,
					"t": board.cells[c.y][c.x],
				})
		DEFS.Item.BOLT, DEFS.Item.THUNDER:
			# 从有方块的列中随机选,避免稀疏棋盘高概率作废
			var filled_cols: Array[int] = board.filled_column_indices()
			if filled_cols.is_empty():
				return false
			filled_cols.shuffle()
			fx_cols = []
			var take_c := 2
			if kind == DEFS.Item.THUNDER:
				take_c = DEFS.THUNDER_MAX_COLS
			take_c = mini(take_c, filled_cols.size())
			for i in take_c:
				fx_cols.append(filled_cols[i])
		DEFS.Item.FLIP:
			# 翻转无消除目标;棋盘为空时翻转无意义,作废
			if board.all_filled_cells().is_empty():
				return false
		DEFS.Item.PRUNE:
			fx_peak_cells = board.peak_cells()
			if fx_peak_cells.is_empty():
				return false
	return true


func _execute_item() -> void:
	## ITEM_FX 结束:执行清除 + 粒子 + 计分;队列未空则继续连发。
	var cleared: Array = []
	# 冲击音:与粒子爆发同帧,是道具的"听觉主体"
	match fx_kind:
		DEFS.Item.WIND, DEFS.Item.STORM_WIND:
			SFX.play("wind_cast")
		DEFS.Item.RAIN, DEFS.Item.TORRENT:
			SFX.play("rain_cast")
		DEFS.Item.BOLT, DEFS.Item.THUNDER:
			SFX.play("bolt_cast")
	match fx_kind:
		DEFS.Item.WIND, DEFS.Item.STORM_WIND:
			# 消行前判定:风带走其他碎片格 → 道具滚道具,入队连发
			for i in range(item_cells.size() - 1, -1, -1):
				if fx_rows.has(item_cells[i].cell.y):
					item_cells.remove_at(i)
					_enqueue_item(randi() % DEFS.BASIC_ITEM_COUNT)
			for r in fx_rows:
				cleared.append_array(board.collect_row_cells(r))
				particles.wind_streaks_row(r, 10)
			board.remove_rows(fx_rows)
			# 剩余碎片格坐标随下移修正
			for i in item_cells.size():
				var cell: Vector2i = item_cells[i].cell
				var shift := 0
				for r in fx_rows:
					if r < cell.y:
						shift += 1
				if shift > 0:
					item_cells[i].cell = Vector2i(cell.x, cell.y - shift)
			_sync_item_cells()
		DEFS.Item.RAIN, DEFS.Item.TORRENT:
			cleared = fx_rain_cells
			board.clear_cells(fx_rain_cells)
			for cc in fx_rain_cells:
				particles.rain_drops(cc.pos, 3)
		DEFS.Item.BOLT, DEFS.Item.THUNDER:
			for c in fx_cols:
				cleared.append_array(board.collect_column_cells(c))
				particles.bolt_arcs(c, 16)
			board.clear_cells(cleared)
		DEFS.Item.FLIP:
			# 整棋盘水平镜像;零消除零分,纯解场工具
			board.flip_horizontal()
			# 碎片格坐标随镜像
			for i in item_cells.size():
				var ic: Vector2i = item_cells[i].cell
				item_cells[i].cell = Vector2i(Board.WIDTH - 1 - ic.x, ic.y)
			_sync_item_cells()
			# 当前块不受翻转影响;若与镜像后的堆叠碰撞则向上抬升找合法位
			if not board.can_place(current.type, current.rot, current.x, current.y):
				var lifted := false
				for k in range(1, 6):
					if board.can_place(current.type, current.rot, current.x, current.y - k):
						current.y -= k
						lifted = true
						break
				if not lifted:
					board_view.hide_item_fx()
					fx_kind = -1
					_game_over()
					return
			_after_piece_changed()
			board_view.shake()
		DEFS.Item.PRUNE:
			cleared = fx_peak_cells
			board.clear_cells(fx_peak_cells)
	fx_kind = -1
	board_view.hide_item_fx()
	for cc in cleared:
		particles.burst_cell(cc.pos, cc.t, 14)
	if not cleared.is_empty():
		SFX.play("item_clear")
		score += cleared.size() * DEFS.ITEM_SCORE_PER_CELL * level
		if score > hi_score:
			hi_score = score
			_save_hi()
		_update_hud()
	state = State.PLAYING
	if not item_queue.is_empty():
		_start_next_item()


func _show_float(text: String, color: Color) -> void:
	float_label.text = text
	float_label.modulate = color
	float_label.visible = true
	float_time = FLOAT_TIME


func _sync_mode_label() -> void:
	if DEFS.fun_mode:
		mode_label.text = "⚡ FUN MODE · 欢乐模式"
		mode_label.add_theme_color_override("font_color", Color("#ff2a6d"))
	else:
		mode_label.text = "STANDARD · 标准模式"
		mode_label.add_theme_color_override("font_color", Color("#5a6486"))


# ---------------- 通用流程 ----------------

func _game_over() -> void:
	state = State.GAME_OVER
	board_view.current = {}
	board_view.queue_redraw()
	gameover_score.text = "本局得分  %d" % score
	new_record.visible = score > 0 and score >= hi_score
	gameover_overlay.visible = true


func _toggle_pause() -> void:
	if state == State.GAME_OVER:
		_back_to_menu()
		return
	if state == State.PLAYING or state == State.CLEARING or state == State.ITEM_FX:
		_paused_from = state
		state = State.PAUSED
		pause_overlay.visible = true
	elif state == State.PAUSED:
		state = _paused_from
		pause_overlay.visible = false


func _restart() -> void:
	get_tree().reload_current_scene()


func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _update_hud() -> void:
	score_label.text = str(score)
	level_label.text = str(level)
	lines_label.text = str(lines)
	hi_label.text = str(hi_score)


func _load_hi() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f:
		hi_score = int(f.get_64())


func _save_hi() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_64(hi_score)
