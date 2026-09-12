extends Object
## 瓦片雄鹰 M1 敌机型号表 + 波次脚本（数据驱动：调难度只改这里，不动 combat.gd）。
##
## 与方块雄鹰的 `stages.gd` **不共享**（design §9：原作冻结、瓦片版自建对应物）——
## 但敌机密度按关 1「碧海突袭」取同量级，保证两作并排试玩时压力相当。
## 单位资产原样复用 `assets/vox/units/*.vox`（单位不瓦片化，design §1.2）。

## 型号表字段：
##   vox    单位资产名（assets/vox/units/<vox>.vox）
##   head   需要单独挂的炮头资产（炮台类；炮头 look_at 玩家，按 AABB 对齐落座）
##   rotor  需要单独挂的旋翼层资产（只转这一层，机身朝向稳定）
##   hp     血量（自机弹每发 1 点）
##   layer  高度层 = altitude.gd 的常量名：GROUND 贴陆/贴海面，LOW 掠海，AIR 与玩家同空域，
##          HIGH 精英/大型单位。**战斗层只认这一列**，不许在自己的行为里写 y（altitude.gd 头注）
##   beh    行为：turret 炮台 · ring 环形炮台 · drift 直线掠过 · weave 蛇形推进
##                strafe 大幅横移扫场 · heli 直升机 · bomber 投弹 · raider 掠海冲撞
##                elite 精英炮舰（phase 交替 + 濒死逃逸）· fortress 浮空盾堡（小 boss 级）
##   hit    命中判定半径（XZ 半宽；与方块雄鹰同值，保证手感一致）
##   score  击落得分    stars 掉落星数
##   gun    开火模式："" 不开火 · aimed 自机狙 · ring 环形弹幕      n/spread 弹数与散布角
##   cd     开火间隔（秒）      bspeed 弹速      range_z 允许开火的前后区间（局部 z）
##   vz     相对地面的前进速度（空中单位会叠加滚动速度 → 实际更快压向玩家）
##   ram    是否撞击伤害（无人机/掠海炮艇：撞到玩家扣装甲）
##   flee   精英单位 hp 掉到 40% 以下的额外逃逸速度（缺省 6.0）
##
## 【分层纪律】体量越大的单位越往上放：掠海冲撞 E9 在 LOW、主力机群在 AIR、
## 精英/大型（E6 炮舰 / E8 轰炸机 / E10 盾堡）在 HIGH。弹幕仍统一在 AIR 层（combat.gd 头注），
## 所以 LOW/HIGH 单位开火时会补一发枪焰把两层在视觉上接起来。
const ENEMY := {
	"E1": {
		"vox": "E1", "head": "E1H", "hp": 3, "layer": "GROUND", "beh": "turret",
		"hit": Vector2(1.3, 1.3), "score": 50, "stars": 1,
		"gun": "aimed", "n": 3, "spread": 14.0, "bspeed": 8.0, "cd": 2.2,
		"range_z": Vector2(-34.0, 6.0),
	},
	"E2": {
		"vox": "E2", "hp": 4, "layer": "GROUND", "beh": "ring",
		"hit": Vector2(1.7, 1.7), "score": 80, "stars": 2,
		"gun": "ring", "n": 14, "bspeed": 6.2, "cd": 2.7,
		"range_z": Vector2(-34.0, 40.0),
	},
	"E3": {
		"vox": "E3", "rotor": "E3R", "hp": 3, "layer": "AIR", "beh": "drift",
		"hit": Vector2(1.3, 1.3), "score": 30, "stars": 1,
		"gun": "", "vz": 10.0, "ram": true,
	},
	"E4": {
		"vox": "E4", "hp": 4, "layer": "AIR", "beh": "weave",
		"hit": Vector2(1.3, 1.3), "score": 50, "stars": 1,
		"gun": "aimed", "n": 1, "spread": 0.0, "bspeed": 7.0, "cd": 2.6,
		"vz": 5.0, "range_z": Vector2(-40.0, 40.0),
	},
	# ---- 精英段（M1 §16.2）：资产全部复用，只加型号行 + 行为分支 ----
	"E5": {
		# 巡洋机（19×24）：横向扫场，5 发扇形压制 —— 弹幕密度的主要来源
		"vox": "E5", "hp": 5, "layer": "AIR", "beh": "strafe",
		"hit": Vector2(1.8, 2.2), "score": 120, "stars": 2,
		"gun": "aimed", "n": 5, "spread": 42.0, "bspeed": 7.5, "cd": 1.9,
		"vz": 3.0, "range_z": Vector2(-42.0, 40.0),
	},
	"E6": {
		# 精英炮舰（29×20×12，全表最大）：HIGH 层缓推，环形/自机狙交替，濒死加速逃逸
		"vox": "E6", "hp": 20, "layer": "HIGH", "beh": "elite",
		"hit": Vector2(3.0, 2.2), "score": 400, "stars": 5,
		"gun": "mix", "n": 3, "spread": 16.0, "bspeed": 7.0, "cd": 2.2,
		"ring_n": 12, "ring_spd": 6.0, "flee": 6.0,
		"vz": 1.5, "range_z": Vector2(-34.0, 6.0),
	},
	"E7": {
		# 武装直升机（11×20）：主旋翼独立一层，双管短点射
		"vox": "E7", "rotor": "E7R", "hp": 5, "layer": "AIR", "beh": "heli",
		"hit": Vector2(1.6, 2.4), "score": 180, "stars": 2,
		"gun": "aimed", "n": 2, "spread": 20.0, "bspeed": 7.5, "cd": 2.4,
		"vz": 2.5, "range_z": Vector2(-44.0, 40.0),
	},
	"E8": {
		# 飞翼轰炸机（21×18×2）：HIGH 层直压，定期向四周撒慢速炸弹
		"vox": "E8", "hp": 10, "layer": "HIGH", "beh": "bomber",
		"hit": Vector2(2.6, 2.2), "score": 300, "stars": 4,
		"gun": "ring", "n": 8, "bspeed": 4.5, "cd": 3.2,
		"vz": 2.0, "range_z": Vector2(-40.0, 40.0),
	},
		"E9": {
			# 双体炮艇（19×16）：掠海冲撞 + 前向点射（LOW 层唯一单位，靠枪焰接上 AIR 弹幕）
			"vox": "E9", "hp": 4, "layer": "LOW", "beh": "raider",
			"hit": Vector2(2.0, 2.0), "score": 150, "stars": 2,
			"gun": "aimed", "n": 1, "spread": 0.0, "bspeed": 6.5, "cd": 1.8,
			"vz": 8.0, "ram": true, "range_z": Vector2(-40.0, 40.0),
		},
	"E10": {
		# 浮空盾堡（19×19×8）：小 boss 级，HIGH 层极缓推进，环形/自机狙交替
		"vox": "E10", "hp": 24, "layer": "HIGH", "beh": "fortress",
		"hit": Vector2(2.6, 2.6), "score": 800, "stars": 6,
		"gun": "mix", "n": 3, "spread": 16.0, "bspeed": 7.0, "cd": 2.0,
		"ring_n": 12, "ring_spd": 6.0,
		"vz": 1.5, "range_z": Vector2(-40.0, 8.0),
	},
	"E11": {
		# 战列舰（25×41×8，全表最长）：LOW 层低速压进；舰桥前后两座三联装炮塔
		# **独立限速旋转**追踪玩家（combat.gd::battleship），对准后交替齐射
		# turret_scale：炮塔在舰体本地空间的放大倍数。1.0 = 正确比例（炮塔曾因
		# **子节点复合缩放 bug** 只渲染 1/3，修复后已经是合理尺寸）；
		# 2.0 会把舰体整个盖住（对照图 tools/tile_eagle/tile_battleship_2x.png），要更大改这个数
		"vox": "E11", "hp": 30, "layer": "LOW", "beh": "battleship", "turret_scale": 1.0,
		"hit": Vector2(3.0, 5.5), "score": 600, "stars": 5,
		"gun": "aimed", "n": 3, "spread": 8.0, "bspeed": 7.5, "cd": 2.6,
		"vz": 1.2, "range_z": Vector2(-44.0, 6.0),
	},
	"E13": {
		# 喷气式飞翼（27×19×5，YB-49 风）：HIGH 层大翼展直压，周期性投下
		# 「横向弹墙」（留缺口，combat.gd::carpet）——走位要看缺口，不看弹
		"vox": "E13", "hp": 14, "layer": "HIGH", "beh": "carpet",
		"hit": Vector2(3.4, 2.6), "score": 450, "stars": 4,
		"gun": "", "cd": 3.0, "vz": 2.4,
	},
	"E12": {
		# 重型武装直升机（13×25×8）：串列座舱 + 短翼挂巢 + 五叶主旋翼。
		# 机枪短点射压制（aimed 快弹）+ 追踪导弹（combat.gd::gunship，限转可躲）
		"vox": "E12", "rotor": "E12R", "hp": 6, "layer": "AIR", "beh": "gunship",
		"hit": Vector2(1.7, 2.6), "score": 260, "stars": 3,
		"gun": "aimed", "n": 2, "spread": 5.0, "bspeed": 9.5, "cd": 0.55,
		"vz": 2.2, "range_z": Vector2(-44.0, 40.0),
	},
	"BOSS": {
		# 方舟战舰（17×24×6 × 0.5 = 8.5×12×3）：一轮周期的压轴。
		# layer=AIR 刻意不放 HIGH——Boss 战必须与玩家同一平面才读得清（altitude.gd 头注）；
		# vz=-7.0 正好抵消滚动速度 → 与玩家相对静止（combat.gd 的 hold 处理），Boss 战是定点的。
		# scale 0.5 与方块雄鹰同值（全表唯一例外，见 combat.gd::_new_unit_node）。
		"vox": "boss", "scale": 0.5, "hp": 80, "layer": "AIR", "beh": "boss",
		"hit": Vector2(7.0, 3.4), "score": 2000, "stars": 0,
		"gun": "", "vz": -7.0, "hold": true,
	},
}

## 波次脚本：`t` = 关卡脚本时钟（秒），到点刷 `spawn` 里的整组；表跑完从头循环
## （走廊是无尽的，循环即"无尽模式"）。
## 前 8 组（t ≤ 98）照关 1 的密度节奏：约每 12~14 秒一组、每组 3~5 架，全部是基础机型。
## 后 7 组（t ≥ 112）是 M1 的**精英段**：每 ~20 秒引入一款大型单位，密度反而更低
## （精英单位自身就是压力源），一轮总长约 232 秒后从头循环。
const WAVES := [
	{"t": 6.0, "spawn": [{"t": "E1", "x": -8.0}, {"t": "E1", "x": 8.0}]},
	{"t": 16.0, "spawn": [
		{"t": "E3", "x": -12.0, "vx": 3.0}, {"t": "E3", "x": -4.0, "vx": -3.0},
		{"t": "E3", "x": 4.0, "vx": 3.0}, {"t": "E3", "x": 12.0, "vx": -3.0}]},
	{"t": 28.0, "spawn": [{"t": "E2", "x": 0.0}, {"t": "E1", "x": -9.0}, {"t": "E1", "x": 9.0}]},
	{"t": 42.0, "spawn": [
		{"t": "E4", "x": -8.0}, {"t": "E4", "x": -4.0}, {"t": "E4", "x": 0.0},
		{"t": "E4", "x": 4.0}, {"t": "E4", "x": 8.0}]},
	{"t": 56.0, "spawn": [
		{"t": "E1", "x": -10.0}, {"t": "E1", "x": 0.0}, {"t": "E1", "x": 10.0}, {"t": "E2", "x": -5.0}]},
	{"t": 70.0, "spawn": [{"t": "E4", "x": -9.0}, {"t": "E4", "x": 9.0}, {"t": "E3", "x": 0.0, "vx": 0.0}]},
	{"t": 84.0, "spawn": [{"t": "E2", "x": -6.0}, {"t": "E2", "x": 6.0}, {"t": "E1", "x": 0.0}]},
	{"t": 98.0, "spawn": [
		{"t": "E3", "x": -12.0, "vx": 4.0}, {"t": "E3", "x": 0.0, "vx": -4.0},
		{"t": "E3", "x": 12.0, "vx": 4.0}, {"t": "E1", "x": -6.0}, {"t": "E1", "x": 6.0}]},
	# ---- 精英段 ----
	{"t": 112.0, "spawn": [{"t": "E5", "x": -8.0}, {"t": "E5", "x": 8.0}]},          # 巡洋机 编队
	{"t": 130.0, "spawn": [
		{"t": "E7", "x": 0.0}, {"t": "E3", "x": -10.0, "vx": 3.0}, {"t": "E3", "x": 10.0, "vx": -3.0}]},
	{"t": 148.0, "spawn": [{"t": "E8", "x": 0.0}, {"t": "E1", "x": -9.0}, {"t": "E1", "x": 9.0}]},
	{"t": 166.0, "spawn": [
		{"t": "E9", "x": -11.0, "vx": 2.5}, {"t": "E9", "x": 0.0, "vx": -2.5}, {"t": "E4", "x": 8.0}]},
	{"t": 186.0, "spawn": [{"t": "E6", "x": -4.0}, {"t": "E5", "x": 9.0}]},          # 精英炮舰
	{"t": 212.0, "spawn": [{"t": "E10", "x": 0.0}]},                                # 浮空盾堡
	{"t": 232.0, "spawn": [
		{"t": "E5", "x": 0.0}, {"t": "E4", "x": -8.0}, {"t": "E4", "x": 8.0}]},
	# 战列舰先于方舟登场：双炮塔独立旋转是它全部的戏，配两架战斗机护航
	{"t": 242.0, "spawn": [{"t": "E11", "x": 0.0}, {"t": "E4", "x": -10.0}, {"t": "E4", "x": 10.0}]},
	{"t": 246.0, "spawn": [{"t": "E12", "x": -8.0}, {"t": "E12", "x": 8.0}]},   # 武直双机交叉进场
	{"t": 252.0, "spawn": [{"t": "E13", "x": 0.0}]},                            # 喷气飞翼 弹墙压轴（Boss 前最后一关）
	# ---- 压轴：方舟战舰（M3）。精英段清完、走廊空下来之后登场，打完进入下一轮循环。
	# 摆在最后而不是中间：一轮 232 秒的强度曲线是「基础 → 精英 → Boss」，与原作逐关同构。
	{"t": 250.0, "spawn": [{"t": "BOSS", "x": 0.0}]},
]


## 取型号表条目；未登记型号回退 E3（保证流程不炸）
static func get_enemy(t: String) -> Dictionary:
	return ENEMY.get(t, ENEMY["E3"])


## 场上的空中/地面单位一律按 0.3 世界单位/体素缩放（与玩家机同精度）
const SCALE := 0.3
