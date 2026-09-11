extends RefCounted
## 排布层：地貌节奏表 + 岛/沙洲超级瓦图章 + 字面量手工段；同种子恒定产出同布局。
##
## 走廊 = ROWS 行 × COLS 列的循环（循环长度 48 × 4.8 = 230.4，与方块雄鹰回绕跨度同量级）。
## rows[row] 是该行的瓦片记录列表（被高瓦占用的列不再铺海面，由高瓦自身满铺无缝）。
## 高瓦占用掩码 high_mask[row][col] 供 M1 地面单位落位反查。
##
## 【密度纪律 · M1 修订】地貌特征一律在 FEATURES 节奏表里**显式排布**，不做概率撒点。
## M0 是「每格 2.4% 概率撒 1×1 小岛/沙洲」——624 格上产出约 15 处零碎小点，
## 就是「小岛/沙洲密度偏高」的根因（观感上读作海面撒了一地碎屑）。
## 现在改成：每 48 行（230.4 世界单位）只有 4 处特征，且按尺寸分三档
## （大岛 19.2 / 小岛 9.6 / 沙洲 9.6 世界单位）——稀疏但每处都有分量。

const COLS := 13
const ROWS := 48                      # 13 × 4.8 = 62.4 宽（覆盖正交 34 视野 60.44）

const Tiles = preload("res://scripts/tile_eagle/tiles.gd")

const DEFAULT_SEED := 20260911

## 地貌节奏表：一处特征 = 一张超级瓦占 span×span 格（span 由 tiles.gd 的 SPAN 决定）。
## row 是特征的**宿主行**（跨度里最靠近相机的那一行）；列位由种子决定
## （rng 取 [0, COLS-span]），保证「同种子逐位复现、R 键换布局」。
## 行距刻意留大（特征之间至少空 4 行 = 19.2 世界单位）：大岛与沙洲挤在一个视野里
## 会立刻把"走廊"读成"群岛"，这正是本轮要消掉的东西。
const FEATURES: Array = [
	{"row": 12, "tile": "island_4x4"},     # 主岛：64 体素 = 4×4 格 = 19.2 世界单位
	{"row": 21, "tile": "sandbar_2x2"},
	{"row": 29, "tile": "island_2x2"},
	{"row": 36, "tile": "sandbar_2x2"},
]

## 开阔海段的浪尖密度（按行区间给 crest 概率）—— 0~25 平静、26~47 湍浪带，制造段落对比。
## 海面浪带 `_band` 是全局相位特征，故 crest/sea 一律 rot=0（旋转会错相位、瓦界浪纹断开）。
const CREST_BANDS: Array = [
	{"row": 0, "n": 26, "crest": 0.03},
	{"row": 26, "n": 22, "crest": 0.07},
]

## 手工段落（行 40~47）：字面量示范「可设计」——对角礁石引导线 + 浪尖带。
## 字符映射：. = 交给海面填充  a/b/c = 对应海瓦  C = 浪尖  r = 礁石（rot 按行列号确定性取）
const HAND_SECTION: Array[String] = [
	".............",
	"....r........",
	".........r...",
	"......C......",
	".............",
	".........r...",
	"....r........",
	".............",
]

var seed_val: int = DEFAULT_SEED
var rows: Array = []                  # rows[row] = [{tile:String, col:int, rot:int}]
var used_mask: Array = []             # used_mask[row][col]：任意瓦片已占位（后放者不得覆盖）
var high_mask: Array = []             # high_mask[row][col] = true：高瓦占用（M1 地面单位落位反查）
var features: Array = []              # 已摆下的超级瓦 [{tile, row0, col0, span}]（M1 战斗层挑着陆点用）


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	rows.clear()
	used_mask.clear()
	high_mask.clear()
	features.clear()
	for r in ROWS:
		rows.append([])
		var um := []
		um.resize(COLS)
		used_mask.append(um)
		var hm := []
		hm.resize(COLS)
		high_mask.append(hm)
	# 顺序即优先级：节奏表特征 > 手工段字面量 > 海面填充（填充按 used_mask 跳过已占格）
	for f in FEATURES:
		_stamp_feature(rng, f)
	_sec_hand()                            # 手工段：显式格子（覆盖节奏表没占到的格）
	for band in CREST_BANDS:
		_fill_sea(rng, int(band.row), int(band.n), float(band.crest))


# ---------------------------------------------------------------- 特征与填充

## 超级瓦图章：一张资产占 [row, row+span-1] × [col, col+span-1]。
## 两个落位要点（都由 game.gd `_spawn_row` 按 span 反推，这里只管写表）：
## 1) 记录挂在跨度里**最远**的那一行（row + span-1）——块中心 = 该行 + (span-1)/2，
##    挂远行才能保证整块在屏幕之外被释放（4×4 的跨度 19.2，挂错行会在屏幕内凭空消失）；
## 2) 跨界的摆放直接放弃（宁可少一处特征，也不能让超级瓦被循环边界撕成两半）。
func _stamp_feature(rng: RandomNumberGenerator, f: Dictionary) -> void:
	var id: String = f.tile
	var span: int = Tiles.span_of(id)
	var r0: int = int(f.row)
	var c0: int = rng.randi_range(0, COLS - span)
	if r0 + span > ROWS - HAND_SECTION.size():
		return                                 # 不许压到手工段
	if c0 + span > COLS:
		return
	for dy in span:
		for dx in span:
			if used_mask[r0 + dy][c0 + dx]:
				return                         # 有占位冲突则整块不摆
	rows[r0 + span - 1].append({"tile": id, "col": c0, "rot": 0})
	for dy in span:
		for dx in span:
			used_mask[r0 + dy][c0 + dx] = true
			high_mask[r0 + dy][c0 + dx] = true
	# 登记特征（row0 = 跨度里最靠近相机的那一行，与上面的记录行差 span−1）
	features.append({"tile": id, "row0": r0, "col0": c0, "span": span})


func _sec_hand() -> void:
	var r0 := ROWS - HAND_SECTION.size()
	for i in HAND_SECTION.size():
		var line: String = HAND_SECTION[i]
		for c in mini(line.length(), COLS):
			var id := ""
			var rot := 0
			match line[c]:
				".": pass
				"a": id = "sea_a"
				"b": id = "sea_b"
				"c": id = "sea_c"
				"C": id = "sea_crest"
				"r":
					# 礁石也一律 rot=0：它的底色水面已改成与海面瓦同分布（带浪带），
					# 旋转 90° 会把浪带相位也转过去 → 瓦界浪纹断开（waves/sea 同一条纪律）。
					id = "reef_s"
					rot = 0
			if id != "":
				_set_cell(r0 + i, c, id, rot)


func _fill_sea(rng: RandomNumberGenerator, r0: int, n: int, crest_p: float) -> void:
	for r in range(r0, mini(r0 + n, ROWS)):
		for c in COLS:
			if used_mask[r][c]:
				continue
			# 海面浪带是全局相位特征：一律 rot=0（任何旋转都会错相位，瓦界浪纹断开）
			var id := "sea_a"
			if rng.randf() < crest_p:
				id = "sea_crest"
			else:
				# 六变体近均分，打破单瓦图案重复感
				id = SEA_VARIANTS[rng.randi_range(0, SEA_VARIANTS.size() - 1)]
			_set_cell(r, c, id, 0)


const SEA_VARIANTS: Array[String] = ["sea_a", "sea_b", "sea_c", "sea_d", "sea_e", "sea_f"]


func _set_cell(r: int, c: int, id: String, rot: int = 0) -> void:
	if c < 0 or c >= COLS or used_mask[r][c]:
		return                          # 越界丢弃 / 已占位不覆盖（图章与手工段优先）
	rows[r].append({"tile": id, "col": c, "rot": rot})
	used_mask[r][c] = true
	if Tiles.is_high(id):
		high_mask[r][c] = true
