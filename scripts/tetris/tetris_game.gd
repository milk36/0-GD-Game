extends Control
## 赛博朋克俄罗斯方块主控:状态机、重力、输入调度、计分、暂停与结算。

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

enum State { PLAYING, CLEARING, PAUSED, GAME_OVER }

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

@onready var board_view: Control = $Center/Layout/BoardView
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
	_spawn()
	_update_hud()


func _process(delta: float) -> void:
	match state:
		State.PLAYING:
			_handle_input(delta)
			if state == State.PLAYING:
				_gravity(delta)
		State.CLEARING:
			clear_timer -= delta
			board_view.clear_progress = 1.0 - clampf(clear_timer / CLEAR_TIME, 0.0, 1.0)
			board_view.queue_redraw()
			if clear_timer <= 0.0:
				_finish_clear()
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
	board.remove_rows(rows)
	var n := rows.size()
	lines += n
	score += SCORE_TABLE[n] * level
	level = lines / 10 + 1
	if score > hi_score:
		hi_score = score
		_save_hi()
	board_view.stop_clear()
	state = State.PLAYING
	_spawn()
	_update_hud()


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
	if state == State.PLAYING or state == State.CLEARING:
		state = State.PAUSED
		pause_overlay.visible = true
	elif state == State.PAUSED:
		state = State.PLAYING
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
