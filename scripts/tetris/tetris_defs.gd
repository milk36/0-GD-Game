extends RefCounted
## 俄罗斯方块共享常量:方块形状、霓虹配色、出生点。

const TYPES := ["I", "O", "T", "S", "Z", "J", "L"]

## 每种方块的 4 个旋转态;每态为 4 个格子坐标(相对包围盒左上角)。
const SHAPES := {
	"I": [
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)],
		[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)],
	],
	"O": [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
	],
	"T": [
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	],
	"S": [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	],
	"Z": [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
	],
	"J": [
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	],
	"L": [
		[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)],
	],
}

const COLORS := {
	"I": Color("#00f0ff"),
	"O": Color("#ffe600"),
	"T": Color("#bd00ff"),
	"S": Color("#00ff9f"),
	"Z": Color("#ff2a6d"),
	"J": Color("#2979ff"),
	"L": Color("#ff9100"),
}

const SPAWN_X := 3
const SPAWN_Y := 0

## ---- 道具系统(风/雨/雷电) ----
enum Item { WIND, RAIN, BOLT }

## 模式开关(由主菜单入口写入):false=标准,true=欢乐。
static var fun_mode := false

## 模式参数:碎片格首刷延迟 / 刷新间隔 / 存活时限 / 并存上限。
const ITEM_PARAMS := {
	false: {"first": 15.0, "interval": 20.0, "life": 15.0, "max_cells": 1},
	true: {"first": 5.0, "interval": 6.0, "life": 10.0, "max_cells": 3},
}

const ITEM_NAMES := ["WIND · 风已注入", "RAIN · 雨已注入", "BOLT · 雷已注入"]
const ITEM_COLORS := {
	Item.WIND: Color("#7ef9ff"),
	Item.RAIN: Color("#4d7bff"),
	Item.BOLT: Color("#ffe600"),
}
const ITEM_CELL_COLOR := Color("#ffd23f")

const ITEM_FIRST_DELAY := 15.0
const ITEM_INTERVAL := 20.0
const ITEM_LIFE := 15.0
const ITEM_FX_TIME := 0.35
const RAIN_MAX_CELLS := 10
const ITEM_SCORE_PER_CELL := 5


static func shape(type_index: int, rot: int) -> Array:
	return SHAPES[TYPES[type_index]][wrapi(rot, 0, 4)]


static func color(type_index: int) -> Color:
	return COLORS[TYPES[type_index]]
