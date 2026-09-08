extends RefCounted
## 棋盘数据与规则:碰撞检测、锁定、满行查找与消除。

const DEFS := preload("res://scripts/tetris/tetris_defs.gd")

const WIDTH := 10
const HEIGHT := 22
const HIDDEN := 2  # 顶部隐藏缓冲行数

## HEIGHT x WIDTH 的二维数组;0 = 空,否则为方块类型索引 + 1。
var cells: Array = []


func _init() -> void:
	for y in HEIGHT:
		var row := []
		row.resize(WIDTH)
		row.fill(0)
		cells.append(row)


func can_place(type_index: int, rot: int, x: int, y: int) -> bool:
	for c in DEFS.shape(type_index, rot):
		var gx: int = x + c.x
		var gy: int = y + c.y
		if gx < 0 or gx >= WIDTH or gy >= HEIGHT:
			return false
		if gy >= 0 and cells[gy][gx] != 0:
			return false
	return true


func lock(type_index: int, rot: int, x: int, y: int) -> bool:
	## 写入棋盘;返回是否发生 lock out(整块都在隐藏区,判负)。
	var all_hidden := true
	for c in DEFS.shape(type_index, rot):
		var gy: int = y + c.y
		cells[gy][x + c.x] = type_index + 1
		if gy >= HIDDEN:
			all_hidden = false
	return all_hidden


func full_rows() -> Array[int]:
	var rows: Array[int] = []
	for y in HEIGHT:
		var full := true
		for x in WIDTH:
			if cells[y][x] == 0:
				full = false
				break
		if full:
			rows.append(y)
	return rows


func remove_rows(rows: Array[int]) -> void:
	rows.sort()
	for i in rows.size():
		cells.remove_at(rows[i] - i)
	for i in rows.size():
		var row := []
		row.resize(WIDTH)
		row.fill(0)
		cells.insert(0, row)
