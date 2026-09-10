extends Object
## 方块雄鹰存档：user://voxel_eagle_save.json。
## 原子写入（tmp → rename），带版本号与默认值合并，为后续关卡/难度扩展留位。

const SAVE_PATH := "user://voxel_eagle_save.json"  # M2


## 默认存档（新玩家含 500★ 初始补给，可立即体验机库升级）
static func defaults() -> Dictionary:
	return {
		"version": 1,
		"stars": 500,
		"upgrades": {"main": 1, "wing": 0, "magnet": 0, "shield": 0, "bomb": 0},
		"medals": {},   # {"1": ["kill", "rescue", "star", "perfect"], ...}
		"best": {},     # {"1": 123456}
		"unlocked": 1,
	}


static func load_data() -> Dictionary:
	var d := defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		return d
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return d
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return d
	_merge(d, parsed)
	return d


## 递归合并：src 覆盖 base，保留 base 中新增的默认键
static func _merge(base: Dictionary, src: Dictionary) -> void:
	for k in src:
		if base.has(k) and typeof(base[k]) == TYPE_DICTIONARY and typeof(src[k]) == TYPE_DICTIONARY:
			_merge(base[k], src[k])
		else:
			base[k] = src[k]


static func save_data(d: Dictionary) -> bool:
	var f := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "  "))
	f.flush()
	f = null  # 释放句柄后再 rename（Windows 下打开句柄会锁文件）
	var err: int = DirAccess.rename_absolute(SAVE_PATH + ".tmp", SAVE_PATH)
	return err == OK


## 升级到 target_lv 的价格：100 × n^1.6，取整到 50（Lv1 为初始，不可购买）
static func upgrade_cost(target_lv: int) -> int:
	var raw := 100.0 * pow(float(target_lv), 1.6)
	return int(round(raw / 50.0)) * 50
