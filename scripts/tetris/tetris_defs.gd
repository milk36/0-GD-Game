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

## ---- 道具系统(风/雨/雷电/翻转/削峰 + 三种进化版) ----
enum Item { WIND, RAIN, BOLT, FLIP, PRUNE, STORM_WIND, TORRENT, THUNDER }

## 模式开关(由主菜单入口写入):false=标准,true=欢乐。
static var fun_mode := false

## 模式参数:碎片格首刷延迟 / 刷新间隔 / 存活时限 / 并存上限。
const ITEM_PARAMS := {
	false: {"first": 15.0, "interval": 20.0, "life": 15.0, "max_cells": 1},
	true: {"first": 5.0, "interval": 6.0, "life": 10.0, "max_cells": 3},
}

const ITEM_NAMES := [
	"WIND · 风已注入", "RAIN · 雨已注入", "BOLT · 雷已注入",
	"FLIP · 镜像翻转", "PRUNE · 削峰修整",
	"STORM · 飓风撕扯", "TORRENT · 暴雨倾盆", "THUNDER · 雷暴降临",
]
const ITEM_COLORS := {
	Item.WIND: Color("#7ef9ff"),
	Item.RAIN: Color("#4d7bff"),
	Item.BOLT: Color("#ffe600"),
	Item.FLIP: Color("#bd5cff"),
	Item.PRUNE: Color("#00ff9f"),
	Item.STORM_WIND: Color("#7ef9ff"),
	Item.TORRENT: Color("#4d7bff"),
	Item.THUNDER: Color("#ffe600"),
}
const ITEM_CELL_COLOR := Color("#ffd23f")

## 基础道具随机池大小(风/雨/雷/翻转/削峰等概率;进化版不入随机池)。
const BASIC_ITEM_COUNT := 5

## 队列中相邻同类基础道具合并的进化映射(翻转/削峰不参与进化)。
const EVOLVE_MAP := {
	Item.WIND: Item.STORM_WIND,
	Item.RAIN: Item.TORRENT,
	Item.BOLT: Item.THUNDER,
}

## 进化道具的强化目标数(基础版:风 2 行 / 雨 10 格 / 雷 2 列)。
const STORM_WIND_ROWS := 3
const TORRENT_MAX_CELLS := 20
const THUNDER_MAX_COLS := 3

const ITEM_FIRST_DELAY := 15.0
const ITEM_INTERVAL := 20.0
const ITEM_LIFE := 15.0
const ITEM_FX_TIME := 0.35
const RAIN_MAX_CELLS := 10
const ITEM_SCORE_PER_CELL := 5

## 道具专属演出分段(基于 ITEM_FX_TIME 内的进度切分):
## 风:行高亮时长,之后左右速度线扫过;雷:锯齿电光扫描时长,之后整列闪白;
## 雨:散点格逐个闪现的时间间隔。
const ITEM_WIND_HL_TIME := 0.15
const ITEM_BOLT_ZIG_TIME := 0.2
const ITEM_RAIN_STEP := 0.03


static func shape(type_index: int, rot: int) -> Array:
	return SHAPES[TYPES[type_index]][wrapi(rot, 0, 4)]


static func color(type_index: int) -> Color:
	return COLORS[TYPES[type_index]]
