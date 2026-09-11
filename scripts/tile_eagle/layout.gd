extends RefCounted
## 排布层：段落生成器 + 岛/礁图章 + 字面量手工段；同种子恒定产出同布局。
##
## 走廊 = ROWS 行 × COLS 列的循环（循环长度 48 × 4.8 = 230.4，与方块雄鹰回绕跨度同量级）。
## rows[row] 是该行的瓦片记录列表（被高瓦占用的列不再铺海面，由高瓦自身满铺无缝）。
## 高瓦占用掩码 high_mask[row][col] 供 M1 地面单位落位反查，M0 先记上。

const COLS := 13
const ROWS := 48                      # 13 × 4.8 = 62.4 宽（覆盖正交 34 视野 60.44）

const Tiles = preload("res://scripts/tile_eagle/tiles.gd")

const DEFAULT_SEED := 20260911

# 手工段落（行 34~41）：字面量示范「可设计」——对角礁石引导线 + 浪尖带。
# 字符映射：. = 按权重随机海面  a/b/c = 对应海瓦  C = 浪尖  s = 浅滩  r = 礁石(rot 随机)
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


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	rows.clear()
	used_mask.clear()
	high_mask.clear()
	for r in ROWS:
		rows.append([])
		var um := []
		um.resize(COLS)
		used_mask.append(um)
		var hm := []
		hm.resize(COLS)
		high_mask.append(hm)
	# 段落节奏：开阔海 → 岛链 → 开阔海 → 手工段 → 湍浪带
	_sec_open(rng, 0, 14, 0.03, 0.0)
	_sec_islands(rng, 14, 12)
	_sec_open(rng, 26, 8, 0.03, 0.0)
	_sec_hand()                            # 手工段：显式格子（优先级最高）
	_sec_open(rng, 34, 14, 0.08, 0.0)      # 34~39 补空档 + 填满手工段空白格 + 湍浪带


# ---------------------------------------------------------------- 段落

func _sec_open(rng: RandomNumberGenerator, r0: int, n: int, crest_p: float, shoal_p: float) -> void:
	for r in range(r0, r0 + n):
		_fill_sea_row(rng, r, crest_p, shoal_p)


func _sec_islands(rng: RandomNumberGenerator, r0: int, n: int) -> void:
	# 一站岛 = 一张 2×2 超级瓦（9.6×9.6 世界单位，有机轮廓）+ 外圈浅滩环
	var centers := [
		Vector2i(rng.randi_range(1, COLS - 3), r0 + 2 + rng.randi_range(0, 2)),
		Vector2i(rng.randi_range(1, COLS - 3), r0 + 7 + rng.randi_range(0, 2)),
	]
	for rc in centers:
		_stamp_island(rng, rc)
	for r in range(r0, r0 + n):
		_fill_sea_row(rng, r, 0.03, 0.0)


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
				"s": id = "shoal"
				"r":
					id = "reef_s"
					rot = (r0 + i + c) % 4   # 用行列号做确定性 rot，避免手工段依赖随机
			if id != "":
				_set_cell(r0 + i, c, id, rot)


# ---------------------------------------------------------------- 图章与填充

## 岛图章：一张 2×2 超级瓦占据 (rc.y, rc.x)..(rc.y+1, rc.x+1)，记录挂在**较远**的那一行
## （super span 的落位由 game.gd 按「宿主行 - 半格」推出中心；挂远行可保证释放发生在屏幕外）。
func _stamp_island(rng: RandomNumberGenerator, rc: Vector2i) -> void:
	var r := rc.y
	var c := rc.x
	if r + 1 >= ROWS or c + 1 >= COLS:
		return                                    # 跨界会撕裂超级瓦，放弃这次摆放
	for dy in 2:
		for dx in 2:
			if used_mask[r + dy][c + dx]:
				return                            # 有占位冲突则整块不摆
	rows[r + 1].append({"tile": "island_2x2", "col": c, "rot": 0})
	for dy in 2:
		for dx in 2:
			used_mask[r + dy][c + dx] = true
			high_mask[r + dy][c + dx] = true
	# 不再另铺浅滩环：岛屿资产自带近岸浅水（build_island 的 SHAL 带），
	# 外圈再铺一圈浅滩瓦会拼出一个显眼的"沙矩形"


func _fill_sea_row(rng: RandomNumberGenerator, r: int, crest_p: float, shoal_p: float) -> void:
	for c in COLS:
		if used_mask[r][c]:
			continue
		var roll := rng.randf()
		# 海面浪带是全局相位特征：一律 rot=0（任何旋转都会错相位，瓦界浪纹断开）
		var id := "sea_a"
		if roll < crest_p:
			id = "sea_crest"
		elif roll < crest_p + shoal_p:
			id = "shoal"
		elif roll < crest_p + shoal_p + 0.012:
			id = "isle_grass"          # 零星小岛（1×1 瓦，自带沙滩与草丘）
		elif roll < crest_p + shoal_p + 0.024:
			id = "isle_sand"           # 零星沙洲
		else:
			# 六变体近均分 + 微权重差，打破单瓦图案重复感
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
