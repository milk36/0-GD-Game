extends Object
## 瓦片雄鹰存档：user://tile_eagle_save.json。
##
## 【为什么不复用 voxel_eagle/save_manager.gd】那一份的字段是方块雄鹰的进度语义
## （stars 货币 / upgrades 机库升级 / medals 奖章 / unlocked 关卡），瓦片雄鹰是对照实验田、
## 没有这些系统——共用一个文件只会让两边都背着一堆读不懂的字段。所以另立文件、同套手法
## （原子写入 tmp→rename / 版本号 / 默认值递归合并），字段只留本作真的有的：
## best 最高分 / boss_kills 方舟击破数 / rescued_total 累计救援。

const SAVE_PATH := "user://tile_eagle_save.json"


static func defaults() -> Dictionary:
	return {
		"version": 1,
		"best": 0,           # 单局最高分
		"boss_kills": 0,     # 方舟战舰累计击破数
		"rescued_total": 0,  # 累计救起幸存者
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
