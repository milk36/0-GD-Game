"""生成「方块雄鹰」的 .vox 单位资产：玩家机 + Boss 方舟战舰 + E1~E6 六类敌机。

造型原型：需求方提供的参考截图（金属枪灰机身 + 红色涂装，Sky Force 风格）。
坐标约定（与 vox_reader.gd 的 vox(x,y,z) → godot(x,z,y) 转换配套）：
    x = 左右（建模时只画 x>=c 的右半边，再按 2c-x 镜像）
    y = 前后（机头 / 朝向，数值小 = 游戏里的 -Z）
    z = 高低（层，0 最底）

**分辨率约定（重要）**：全部单位按 **0.3 世界单位 / 体素** 建模，在 game.gd 里统一
`scale = 0.3`（Boss 例外，用 0.5）。所以体素数 = 造型细节量。玩家机 19 体素长、
Boss 24；敌机必须落在同一量级（17~29），否则在正交 34 的相机里只是"几个大方块"，
认不出是什么 —— 旧版 E1~E5 只有 3~5 体素宽，就是这个问题。

产出（assets/vox/units/）：
    player.vox  玩家机  15×19×6 → 4.5×5.7×1.8
    boss.vox    Boss    17×24×6 ×0.5 → 8.5×12×3.0
    E1.vox      炮台基座   9×9×3    → 2.7×2.7×0.9
    E1H.vox     双管炮塔   9×16×6   → 2.7×4.8×1.8（炮管朝 -Y）
    E2.vox      环形机     17×17×8  → 5.1×5.1×2.4
    E3.vox      四旋翼     17×17×6  → 5.1×5.1×1.8
    E4.vox      战斗机     19×20×6  → 5.7×6.0×1.8
    E5.vox      巡洋机     19×24×7  → 5.7×7.2×2.1
    E6.vox      精英炮舰   29×20×12 → 8.7×6.0×3.6
    _preview_*.png  自检预览图

运行：
    python gen_units.py
"""

import math
import os

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "units"))

# ---------------------------------------------------------------- 调色板
# 玩家机 / Boss 配色（与 game.gd 旧 PAL_PLAYER 一致）
G = (106, 116, 132)   # 枪灰
LG = (152, 162, 180)  # 亮枪灰（顶面甲板）
D = (56, 64, 72)      # 暗灰（腹部/底壳）
R = (232, 50, 62)     # 红（涂装主色）
C = (0, 240, 255)     # 青（座舱脊线）
W = (245, 249, 255)   # 白（机鼻）
Y = (255, 230, 0)     # 黄（引擎喷口）
K = (42, 48, 58)      # 近黑

# 敌机配色（前 7 色沿用旧 PAL_ENEMY，保证阵营观感连续）
EG = (106, 116, 136)  # 主体金属灰
ER = (255, 42, 109)   # 品红 —— 阵营色 / 发光件
ED = (172, 46, 78)    # 暗红装甲
ET = (58, 66, 84)     # 暗钢（结构 / 骨架）
EH = (150, 158, 178)  # 亮钢（顶面 / 舷缘）
EL = (190, 198, 214)  # 高光边
EK = (34, 38, 48)     # 近黑（缝隙 / 进气口 / 炮口）
EC = (255, 176, 200)  # 浅粉（能量 / 座舱玻璃）
ES = (196, 166, 96)   # 黄铜 / 金
EW = (232, 238, 248)  # 白（机鼻 / 识别带）
EY = (255, 208, 80)   # 引擎黄
EO = (255, 130, 50)   # 排气橙


# ---------------------------------------------------------------- 建模小工具

def _sym(v, c, x, y, z, col):
    """写入 (x,y,z) 并镜像到 2c-x（对称轴在整数列 c 上）。"""
    v[(x, y, z)] = col
    mx = 2 * c - x
    if mx != x:
        v[(mx, y, z)] = col


def _symbox(v, c, x0, x1, y0, y1, z0, z1, col):
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                _sym(v, c, x, y, z, col)


def _oct_skip(dx, dy, r, cut):
    """切角方形 → 八边形：（|dx|,|dy| 的最大值 <= r）且（曼哈顿距离 <= r+cut）。"""
    return max(abs(dx), abs(dy)) > r or (abs(dx) + abs(dy)) > r + cut


def build_player():
    """玩家机（俯视 15 宽 × 19 长，高 6）：机鼻白 → 红颈带 → 枪灰机身
    → 后掠翼（红翼尖）→ 双引擎尾，青色座舱气泡，机身侧面红条。"""
    Wd, Ld, Hd = 15, 19, 7
    c = 7  # 中轴
    half = [1, 1, 2, 2, 2, 3, 3, 4, 5, 6, 7, 7, 7, 7, 6, 4, 3, 2, 2]
    v = {}

    def put(x, y, z, col):
        v[(x, y, z)] = col
        v[(2 * c - x, y, z)] = col

    for y in range(Ld):
        h = half[y]
        for dx in range(h + 1):
            x = c + dx
            wing = dx > 1 and 7 <= y <= 14  # 后掠翼段
            if wing:
                tip = dx >= h - 1                      # 翼尖红
                put(x, y, 1, R if tip else G)
                put(x, y, 2, R if tip else LG)         # 翼面顶：亮灰
            else:
                put(x, y, 0, D)                        # 腹部暗色（最低层）
                put(x, y, 1, G)
                stripe = dx == 1 and 5 <= y <= 15      # 机身侧面红条
                put(x, y, 2, R if stripe else G)
                # 顶面甲板：中央青色脊线 + 亮灰，强对比避免"像底面"
                if y == 0:
                    put(x, y, 3, W)                    # 白机鼻
                elif y <= 2:
                    put(x, y, 3, R)                    # 红颈带
                elif dx == 0:
                    put(x, y, 3, C)                    # 青色脊线贯穿机身
                else:
                    put(x, y, 3, LG)
    for y in range(3, 7):                              # 座舱气泡
        put(c, y, 4, C)
        put(c, y, 5, C)
    put(c, 4, 4, G)                                    # 座舱前缘框
    for dx in (2,):                                    # 双引擎喷口
        put(c + dx, Ld - 1, 0, Y)
        put(c + dx, Ld - 1, 1, Y)
    for dx in (0, 1):                                  # 尾部封板
        put(c + dx, Ld - 1, 0, D)
        put(c + dx, Ld - 1, 2, R)                      # 红尾带
    return v


def build_boss():
    """Boss 方舟战舰（俯视 17 宽 × 24 长，高 6）：楔形舰艏 → 长条甲板
    （中央红芯走道 + 白色刻线）→ 双侧炮塔（红芯）→ 舰桥岛（青窗）→ 双引擎。"""
    Wd, Ld, Hd = 17, 24, 7
    c = 8
    half = [2, 3, 4, 5, 6, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 7, 7, 6, 6, 5, 5, 4, 3]
    v = {}

    def put(x, y, z, col):
        v[(x, y, z)] = col
        v[(2 * c - x, y, z)] = col

    for y in range(Ld):
        h = half[y]
        for dx in range(h + 1):
            edge = dx == h
            put(c + dx, y, 0, D)                       # 底壳（最低层，暗色）
            put(c + dx, y, 1, K if edge else G)        # 舷侧暗带
            # 甲板（上层）：中央红芯走道 / 白刻线 / 亮灰面
            if dx <= 1:
                put(c + dx, y, 2, R if 10 <= y <= 13 else W if y % 4 == 1 else LG)
            else:
                put(c + dx, y, 2, K if edge else LG)
    for y in range(0, 3):                              # 舰艏白描
        for dx in range(half[y] - 1):
            put(c + dx, y, 2, W)
    for dx in range(2, 5):                             # 双侧炮塔（红芯）
        for y in (6, 7):
            put(c + dx, y, 3, LG)
        put(c + dx, 6, 4, R)
        put(c + dx, 7, 4, R)
    for dx in range(-2, 3):                            # 舰桥岛（青窗带）
        for y in (15, 16, 17):
            put(c + dx, y, 3, G if abs(dx) == 2 else D)
            put(c + dx, y, 4, C if y == 16 and abs(dx) <= 1 else D)
        put(c + dx, 17, 5, D)
    for dx in (3, 4):                                  # 尾部双引擎
        put(c + dx, Ld - 1, 0, Y)
        put(c + dx, Ld - 1, 1, Y)
    return v


# ================================================================ 敌机 E1~E6
# 尺寸对齐"0.3 世界单位/体素"：见文件头的分辨率约定。旧版敌机只有 3~5 体素宽，
# 在游戏相机里就是几个大方块；这里按 9~29 体素重做，与玩家机 / Boss 同量级。


def build_e1_base():
    """E1 防空炮台基座（11×11×3 → 3.3×3.3×0.9）：八边形装甲底板 + 黄铜螺栓环
    + 内收安装座 + 中央回转轴孔。"""
    c = 5
    v = {}
    for y in range(11):
        for x in range(11):
            dx, dy = x - c, y - c
            if _oct_skip(dx, dy, 5, 1):
                continue
            m, s = max(abs(dx), abs(dy)), abs(dx) + abs(dy)
            v[(x, y, 0)] = EK if (m == 5 or s == 6) else ET        # 底板：外缘压暗
            if m <= 4 and s <= 5:
                v[(x, y, 1)] = ET if m == 4 else EG                # 主结构层
            if m <= 3 and s <= 4:
                v[(x, y, 2)] = EH if m <= 2 else EK                # 安装座
    for d in ((4, 0), (-4, 0), (0, 4), (0, -4)):                   # 黄铜螺栓
        v[(c + d[0], c + d[1], 1)] = ES
    for d in ((3, 0), (-3, 0), (0, 3), (0, -3)):                   # 黄铜螺栓（内圈）
        v[(c + d[0], c + d[1], 2)] = ES
    v[(c + 2, c, 2)] = ER                                          # 警示红块
    v[(c - 2, c, 2)] = ER
    v[(c, c + 2, 2)] = ER
    v[(c, c - 2, 2)] = ER
    v[(c, c, 1)] = EK                                              # 回转轴孔
    v[(c, c, 2)] = EK
    return v


def build_e1_head():
    """E1 双管防空炮塔（11 宽 × 18 长 × 6 高 → 3.3×5.4×1.8）。
    **炮管朝 -Y**（游戏 -Z），由 look_at 始终指向玩家；后部配重抵消炮管前倾。"""
    c = 5
    v = {}
    # 塔体：八边形，y 0..10（回转中心在 y=5）
    for y in range(0, 11):
        for x in range(11):
            dx, dy = x - c, y - 5
            if _oct_skip(dx, dy, 5, 1):
                continue
            m, s = max(abs(dx), abs(dy)), abs(dx) + abs(dy)
            v[(x, y, 0)] = ET                                      # 底圈
            if m <= 4 and s <= 5:
                v[(x, y, 1)] = EG if m == 4 else EH                # 塔身（提亮，别沉底）
                v[(x, y, 2)] = EH if m >= 3 else EL
            if m <= 3 and s <= 4:
                v[(x, y, 3)] = EH
            if m <= 2 and s <= 3:
                v[(x, y, 4)] = EL                                      # 顶盖
    # 前脸传感器（青色眼，俯视时的朝向指示）
    for dx in (-2, -1, 0, 1, 2):
        v[(c + dx, 0, 2)] = EC
    for dx in (-1, 0, 1):
        v[(c + dx, 0, 3)] = EC
    # 侧装甲板 + 黄铜弹箱
    _symbox(v, c, c + 4, c + 4, 4, 6, 1, 3, ED)
    _symbox(v, c, c + 3, c + 3, 8, 9, 1, 3, ES)
    _symbox(v, c, c + 1, c + 2, 9, 9, 3, 4, ET)
    v[(c, 10, 4)] = ET                                             # 天线
    v[(c, 10, 5)] = ER
    # 双炮管（x = c±3，向 -Y 伸出），含炮口制退器
    for y in range(-8, 1):
        for z in (2, 3):
            _sym(v, c, c + 3, y, z, ET if z == 2 else EG)
    for y in (-8, -7):
        for z in (1, 2, 3, 4):
            _sym(v, c, c + 3, y, z, EK if z in (1, 4) else ER)
    return v


def build_e2():
    """E2 环形机（17×17×8 → 5.1×5.1×2.4）：八边形厚壁能量环 + 环心悬浮核心
    + 四座顶置发射器。中心 z0~z4 贯通，俯视能直接看穿环孔。"""
    c = 8
    v = {}
    for y in range(17):
        for x in range(17):
            d = math.hypot(x - c, y - c)
            if d > 8.6:
                continue
            if 3.4 <= d <= 7.6:                                    # 环体（厚 4.2）
                v[(x, y, 0)] = ET
                v[(x, y, 1)] = ED if d > 6.6 else (ER if d > 4.4 else EC)
                v[(x, y, 2)] = ER if d > 4.4 else EC
                v[(x, y, 3)] = EG if d > 5.6 else EH
                v[(x, y, 4)] = EH if d > 5.6 else EL
    # 黄铜分段（8 等分，像环上的加强箍）
    for a in range(8):
        ang = a * math.pi / 4.0
        for rr in (5.4, 6.6):
            px = int(round(c + math.cos(ang) * rr))
            py = int(round(c + math.sin(ang) * rr))
            for z in (1, 2, 3, 4):
                v[(px, py, z)] = ES
    # 四座顶置发射器（正方向，浅粉 → 顶端品红）
    for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        bx, by = c + dx * 6, c + dy * 6
        for z in (5, 6):
            v[(bx, by, z)] = EC
            v[(bx + dy, by + dx, z)] = ER if z == 6 else EC        # 两侧翼片
        v[(bx, by, 7)] = ER
    # 环心悬浮核心（八面体，与环之间留出可见缝隙）
    for z in range(2, 7):
        r = 2.6 - abs(z - 4) * 0.6
        for y in range(17):
            for x in range(17):
                if math.hypot(x - c, y - c) <= r:
                    v[(x, y, z)] = EC if r > 1.5 else ER
    v[(c, c, 4)] = EW
    v[(c, c, 3)] = ER
    return v


def build_e3():
    """E3 四旋翼无人机·机身（15×15×4）：中央机身 + 座舱玻璃 + 4 条斜向悬臂 +
    四个旋翼吊舱 + 下挂机炮。桨叶在 E3R.vox（独立旋翼层，运行时只转这一层）。"""
    c = 8
    v = {}
    # 机身（机头朝 +Y，y 4..13）
    for y in range(4, 14):
        h = 2 if y < 12 else 1
        for dx in range(-h, h + 1):
            v[(c + dx, y, 1)] = ET                                 # 腹部
            v[(c + dx, y, 2)] = EG
            v[(c + dx, y, 3)] = EH if abs(dx) <= 1 else EG
    for z in (1, 2, 3):
        v[(c, 14, z)] = EW                                         # 白机鼻
    for dx in (-1, 0, 1):                                          # 座舱玻璃
        for y in (9, 10):
            v[(c + dx, y, 3)] = EC
    v[(c, 11, 3)] = EC
    # 4 条斜向悬臂（X 形）
    for sx in (-1, 1):
        for sy in (-1, 1):
            for t in range(5):
                ax = c + sx * (2 + t)
                ay = 8 + sy * (1 + t)
                v[(ax, ay, 2)] = ET
                v[(ax - sy, ay - sx, 2)] = ET
            px, py = c + sx * 6, 8 + sy * 5
            # 旋翼吊舱（桨叶另出 E3R，装配后桨盘恰在吊舱上方 1 格，与旧单体版同观感）
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    if abs(ox) + abs(oy) > 1:
                        continue
                    v[(px + ox, py + oy, 2)] = ET
                    v[(px + ox, py + oy, 3)] = EG
    # 下挂机炮
    _symbox(v, c, c, c + 1, 6, 9, 0, 0, ET)
    v[(c, 10, 0)] = ET
    v[(c, 11, 0)] = ER
    return v


def build_e3_rotor():
    """E3 旋翼层（19×17×1）：四个吊舱位置各一组「桨毂 + 十字长桨」，单独成层
    挂在机身上方，运行时只旋转这一层（机身朝向稳定、读得出机型轮廓）。
    桨盘整体中心对称于机身 AABB 中心 (8, 8) → 旋转轴不偏心。"""
    c = 8
    v = {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            px, py = c + sx * 6, 8 + sy * 5
            v[(px, py, 0)] = EC                                    # 桨毂
            for d in range(-3, 4):                                 # 长桨叶（十字）
                if d == 0:
                    continue
                col = EC if abs(d) == 3 else (EL if abs(d) == 2 else EH)
                v[(px + d, py, 0)] = col
                v[(px, py + d, 0)] = col
    return v


def build_e4():
    """E4 战斗机（19×20×6 → 5.7×6.0×1.8）：三角后掠翼（带翼面刻线）+ 白机鼻
    + 红翼尖 + 翼尖挂弹 + 浅粉座舱盖 + 双垂尾 + 双引擎 + 进气道。机头朝 +Y。"""
    c = 9
    v = {}
    prof = {0: 3, 1: 4, 2: 5, 3: 7, 4: 8, 5: 9, 6: 9, 7: 9, 8: 8, 9: 7,
            10: 6, 11: 5, 12: 4, 13: 3, 14: 3, 15: 3, 16: 3, 17: 2, 18: 1, 19: 1}
    for y, h in prof.items():
        for dx in range(-h, h + 1):
            x = c + dx
            if abs(dx) <= 2:                                       # 机身：3 层
                v[(x, y, 0)] = EK
                v[(x, y, 1)] = ED if abs(dx) == 2 else EG
                v[(x, y, 2)] = EH
            else:                                                  # 机翼：薄薄一层 + 刻线
                if abs(dx) >= h - 1:
                    v[(x, y, 1)] = ER                              # 翼尖红
                elif (abs(dx) * 2 + y) % 5 == 0:
                    v[(x, y, 1)] = ET                              # 翼面刻线
                else:
                    v[(x, y, 1)] = EG
                if abs(dx) <= 4 and y <= 10:
                    v[(x, y, 2)] = EH                              # 翼根加厚
    for y in (17, 18, 19):                                         # 白色机鼻
        for dx in range(-1, 2):
            if (c + dx, y, 1) in v:
                v[(c + dx, y, 1)] = EW
                v[(c + dx, y, 2)] = EW
    for y in range(11, 15):                                        # 座舱盖
        for dx in (-1, 0, 1):
            v[(c + dx, y, 2)] = EC
            v[(c + dx, y, 3)] = EC
    v[(c, 14, 3)] = EG                                             # 座舱前框
    v[(c, 11, 3)] = EG
    for y in range(3, 11):                                         # 背脊
        v[(c, y, 3)] = EG
    for dx in (-2, 2):                                             # 双垂尾
        for y in (0, 1, 2, 3):
            v[(c + dx, y, 3)] = ED
            v[(c + dx, y, 4)] = ED
    for dx in (-1, 1):                                             # 双引擎尾喷
        v[(c + dx, 0, 1)] = EO
        v[(c + dx, 1, 1)] = EY
        v[(c + dx, 0, 2)] = ET
        v[(c + dx, 1, 2)] = ET
    for sx in (-1, 1):                                             # 进气道（机身两侧）
        for y in (9, 10, 11):
            v[(c + sx * 2, y, 1)] = EK
            v[(c + sx * 3, y, 1)] = ET
    for sx in (-1, 1):                                             # 翼尖挂弹吊舱
        px = c + sx * 8
        for y in (6, 7, 8):
            v[(px, y, 1)] = EH
        v[(px, 5, 1)] = ER
        v[(px, 9, 1)] = ET
        for y in (7, 8):                                           # 翼下挂弹
            v[(px - sx, y, 0)] = EL
        v[(px - sx, 6, 0)] = ER
    return v


def build_e5():
    """E5 巡洋机（19×24×7 → 5.7×7.2×2.1）：长机身 + 矩形直翼 + 双发吊舱
    + 双垂尾 + 白色识别带（解决"暗红一片认不出"）。机头朝 +Y。"""
    c = 9
    v = {}
    prof = {0: 3, 1: 3, 2: 3, 3: 4, 4: 5}
    for y in range(5, 13):
        prof[y] = 9                                                # 矩形直翼
    prof[13] = 8
    prof[14] = 6
    for y in (15, 16, 17, 18):
        prof[y] = 4                                                # 前机身
    prof[19] = 3
    prof[20] = 3
    prof[21] = 3
    prof[22] = 2
    prof[23] = 1
    for y, h in prof.items():
        for dx in range(-h, h + 1):
            x = c + dx
            if abs(dx) <= 3:                                       # 机身：4 层
                v[(x, y, 0)] = EK
                v[(x, y, 1)] = ED
                v[(x, y, 2)] = EG
                v[(x, y, 3)] = EH
            else:                                                  # 直翼：薄翼 + 后缘暗红
                v[(x, y, 1)] = ED if abs(dx) >= h - 1 else EG
                if abs(dx) <= 6:
                    v[(x, y, 2)] = EH
    for dx in range(-9, 10):                                       # 白色识别带（横贯机身与机翼）
        v[(c + dx, 10, 2)] = EW
        if (c + dx, 10, 1) in v:
            v[(c + dx, 10, 1)] = EG
    for dx in range(-9, 10):                                       # 尾缘暗红描边
        if (c + dx, 13, 1) in v:
            v[(c + dx, 13, 1)] = ED
    for sx in (-1, 1):                                             # 翼下挂架
        for y in (7, 8, 9):
            v[(c + sx * 8, y, 0)] = ET
        v[(c + sx * 8, 6, 0)] = ER
    for y in (20, 21, 22):                                         # 白机鼻
        for dx in range(-1, 2):
            if (c + dx, y, 2) in v:
                v[(c + dx, y, 2)] = EW
                v[(c + dx, y, 3)] = EW
    for y in (17, 18, 19):                                         # 座舱
        for dx in (-1, 0, 1):
            v[(c + dx, y, 3)] = EC
            v[(c + dx, y, 4)] = EC
    v[(c, 19, 4)] = EG
    for sx in (-1, 1):                                             # 双发吊舱（翼下）
        px = c + sx * 6
        for y in range(7, 12):
            for z in (0, 1, 2):
                v[(px, y, z)] = ET if z == 0 else EG
                v[(px - sx, y, z)] = ET if z == 0 else EG
        v[(px, 6, 1)] = EY                                          # 尾喷
        v[(px, 6, 2)] = EY
        v[(px - sx, 6, 1)] = EY
        v[(px, 12, 1)] = EK                                         # 进气口
    for sx in (-1, 1):                                             # 双垂尾
        for y in (0, 1, 2, 3):
            for z in (4, 5, 6):
                v[(c + sx * 3, y, z)] = ED if z < 6 else EG
    for y in (0, 1, 2):                                            # 尾喷口（机尾中央）
        v[(c, y, 1)] = EO
    v[(c, 0, 2)] = ET
    for sx in (-1, 1):                                             # 机炮吊舱
        _symbox(v, c, c + 1, c + 1, 21, 22, 1, 1, ET)
    v[(c, 23, 1)] = ET
    v[(c, 22, 1)] = ES
    return v


def build_e6():
    """E6 精英炮舰（17×26×14，引擎外伸后 28 长 → 5.1×8.4×4.2）：尖艏舰体
    + 前/后双联主炮（均朝艏）+ 四座舷侧副炮 + 艏楼 / 艉楼 + 舰桥（青窗）+ 烟囱
    + 雷达桅 + 三联引擎。舰艏朝 +Y。
    前两版 29×20 / 21×26 在俯视相机里都偏"宽胖浮台"，这里收窄到 17 并加大艏锥。"""
    c = 8
    v = {}
    prof = {}
    for y in range(26):
        if y <= 2:
            h = 6
        elif y <= 6:
            h = 7
        elif y <= 19:
            h = 8
        elif y == 20:
            h = 7
        elif y == 21:
            h = 6
        elif y == 22:
            h = 5
        elif y == 23:
            h = 4
        elif y == 24:
            h = 3
        else:
            h = 1
        prof[y] = h

    # 舰体（水线红条只在最底一层，避免整条船变成"红边平台"）
    for y, h in prof.items():
        for dx in range(-h, h + 1):
            x = c + dx
            edge = abs(dx) >= h - 1
            v[(x, y, 0)] = EK if edge else ET
            v[(x, y, 1)] = ED if edge else ET
            v[(x, y, 2)] = EG
            v[(x, y, 3)] = EG
            v[(x, y, 4)] = EK if edge else EH                      # 主甲板
    for y in range(6, 19, 2):                                      # 舷窗（青）
        h = prof[y]
        v[(c + h, y, 2)] = EC
        v[(c - h, y, 2)] = EC
    for y in (24, 25):                                             # 艏部白描
        for dx in range(-2, 3):
            if (c + dx, y, 4) in v:
                v[(c + dx, y, 4)] = EW

    # 艉楼（抬高甲板，形成层次而不是一块平板）
    for y in range(0, 5):
        for dx in range(-5, 6):
            for z in (5, 6):
                v[(c + dx, y, z)] = EG if abs(dx) < 5 else ET
            v[(c + dx, y, 7)] = EH
    # 艏楼
    for y in range(19, 25):
        hh = min(prof[y], 5)
        for dx in range(-hh, hh + 1):
            for z in (5, 6):
                v[(c + dx, y, z)] = EG if abs(dx) < hh else ET
            v[(c + dx, y, 7)] = EH

    # 上层建筑岛 + 舰桥
    for y in range(9, 19):
        for dx in range(-4, 5):
            edge = abs(dx) == 4
            for z in (5, 6, 7, 8):
                v[(c + dx, y, z)] = ET if edge else EG
        for dx in range(-4, 5):
            v[(c + dx, y, 9)] = EH
    for dx in range(-2, 3):                                        # 青窗带
        v[(c + dx, 9, 6)] = EC
        v[(c + dx, 18, 6)] = EC
    for y in range(13, 17):                                        # 舰桥
        for dx in range(-2, 3):
            for z in (10, 11):
                v[(c + dx, y, z)] = EG
        for dx in range(-2, 3):
            v[(c + dx, y, 11)] = EH
    for dx in range(-2, 3):
        v[(c + dx, 13, 10)] = EC
    for z in (12, 13):                                             # 桅杆
        v[(c, 15, z)] = ET
    v[(c, 15, 13)] = ER
    v[(c + 1, 15, 13)] = ER
    for y in (10, 11):                                             # 烟囱
        for dx in range(-2, 3):
            for z in (9, 10, 11):
                v[(c + dx, y, z)] = ET
        for dx in range(-2, 3):
            v[(c + dx, y, 11)] = ER

    # 前后双联主炮（都朝艏 +Y，避免艉炮伸出船外）
    for ty, bl in ((20, (23, 24, 25)), (3, (6, 7, 8))):
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                if max(abs(dx), abs(dy)) <= 3 and abs(dx) + abs(dy) <= 4:
                    v[(c + dx, ty + dy, 8)] = EH
                    if max(abs(dx), abs(dy)) <= 2:
                        v[(c + dx, ty + dy, 9)] = EG
        for dx in range(-2, 3):
            v[(c + dx, ty, 10)] = EH
        v[(c, ty, 10)] = ED
        for dx in (-1, 1):
            for by in bl:
                v[(c + dx, by, 9)] = ET
            v[(c + dx, bl[-1] + 1, 9)] = ER

    # 四座舷侧副炮（炮口朝外）
    for sx in (-1, 1):
        for ty in (12, 17):
            px = c + sx * 6
            for dx in range(-1, 2):
                for dy in range(-1, 2):
                    v[(px + dx, ty + dy, 5)] = EH
            v[(px, ty, 6)] = EG
            for t in range(1, 4):
                v[(px + sx * t, ty, 5)] = ET
            v[(px + sx * 4, ty, 5)] = ER

    # 三联引擎（向艉外伸，才看得见）
    for dx in (-5, 0, 5):
        for y in (-2, -1, 0):
            for z in (1, 2, 3):
                v[(c + dx, y, z)] = ET
        v[(c + dx, -2, 2)] = EY
    return v


def build_e12():
    """E12 重型武装直升机·机身（13×25×8）：串列双座舱（前炮手 EC 玻璃 / 后驾驶员
    EC 玻璃）+ 短翼双挂巢 + 细尾梁 + 水平尾翼 + 垂尾 + 静态尾桨 + 机鼻机枪塔。
    机头朝 **+Y**（迎向玩家）。主旋翼另出 E12R（五叶桨盘，独立层旋转）。"""
    c = 6
    v = {}
    # 机身核心（y 8..20，宽 3 / z 2..4）
    for y in range(8, 21):
        for dx in range(-1, 2):
            v[(c + dx, y, 2)] = ET
            v[(c + dx, y, 3)] = EG
            v[(c + dx, y, 4)] = EH
    # 发动机舱（y 6..10，两侧加宽到 dx ±3）
    for y in range(6, 11):
        for sdx in (-3, 3):
            v[(c + sdx, y, 2)] = ET
            v[(c + sdx, y, 3)] = EG
            v[(c + sdx, y, 4)] = ET
    # 串列座舱：后驾驶员（y 15..19，z 4）+ 前炮手（y 19..22，z 3，更低的机鼻斜面）
    for y in range(15, 20):
        for dx in (-1, 0, 1):
            v[(c + dx, y, 4)] = EC if y >= 16 else EH
    for y in range(19, 23):
        for dx in (-1, 0, 1):
            v[(c + dx, y, 3)] = EC if y <= 21 else EG
    v[(c, 22, 4)] = EW                                                 # 机鼻顶
    for z in (3, 4):                                                   # 机鼻斜面收尖
        v[(c, 23, z)] = EW
    # 机鼻机枪塔（y 23..24，z 1..2；机枪口 ER）
    for y in (23, 24):
        v[(c, y, 1)] = ET
        v[(c, y, 2)] = EG
    v[(c, 24, 1)] = ER
    # 短翼（y 10..12，dx ±6）：翼面 + 翼下导弹巢（ET 深）+ 翼尖照明（EW）
    for y in (10, 11, 12):
        for dx in range(-6, 7):
            v[(c + dx, y, 2)] = EH if abs(dx) >= 2 else v.get((c + dx, y, 2), EG)
    for y in (10, 11, 12):
        for sdx in (-6, 6):
            v[(c + sdx, y, 3)] = ET                                    # 翼下挂巢
    v[(c - 6, 11, 4)] = EW
    v[(c + 6, 11, 4)] = EW
    # 尾梁（y 2..7，宽 1，z 3）+ 水平尾翼（y 2..3，dx ±3）
    for y in range(2, 8):
        v[(c, y, 3)] = EG
    for y in (2, 3):
        for dx in range(-3, 4):
            v[(c + dx, y, 3)] = EH
    # 垂尾（y 0..3，z 5..7）+ 静态尾桨（z=6，y=1 小十字）
    for y in range(0, 4):
        for z in (5, 6):
            v[(c, y, z)] = ET
    v[(c, 2, 7)] = EH
    for d in range(-2, 3):
        if d != 0:
            v[(c + d, 1, 6)] = EH
    v[(c, 1, 5)] = EH
    v[(c, 1, 7)] = EH
    # 起落撬（y 5 / y 17 两侧短撬，z=0）
    for py in (5, 17):
        for sdx in (-2, 2):
            v[(c + sdx, py, 0)] = ET
            v[(c + sdx, py + 1, 0)] = ET
    return v


def build_e12_rotor():
    """E12 主旋翼桨盘（19×19×1）：**五叶**（每 72° 一片，与 E3/E7 的四叶十字区分）。
    极坐标整格散点画叶，中心对称性由奇数叶天然破缺——旋转读感比四叶更"直升机"。"""
    c = 8
    v = {(c, c, 0): ER}                                                # 桨毂（阵营色）
    for k in range(5):
        a = math.tau * k / 5.0
        for t in range(2, 9):                                          # 桨叶半径 2..8
            px = c + int(round(math.cos(a) * t))
            py = c + int(round(math.sin(a) * t))
            col = EC if t >= 7 else (EL if t >= 4 else EH)
            v[(px, py, 0)] = col
    return v

def build_e13():
    """E13 喷气式飞翼（YB-49 风，27×19×5 → 8.1×5.7×1.5）：整架就是一片翼——
    前缘后掠、后缘 W 形三段缺口（中央 / 翼段 / 翼尖拖尾），超扁平两体素。
    后缘埋 4 组喷气排气凹口（暗钢 + 亮缘），双垂尾，中央座舱鼓包。
    机头朝 **+Y**（迎向玩家）。俯视轮廓是本机的全部识别特征。"""
    c = 13
    # 前缘半宽表（y=0 后缘中央 → y=18 机头尖）
    prof = [8, 10, 11, 12, 13, 13, 13, 13, 13, 13, 12, 11, 10, 9, 8, 7, 5, 3, 1]
    # 后缘 W 形：三段的起始 y（中央段最靠后，翼尖拖得最远）
    def y_start(dx):
        a = abs(dx)
        if a <= 8:
            return 0
        if a <= 11:
            return 3
        return 6
    v = {}
    for y in range(19):
        h = prof[y]
        for dx in range(-h, h + 1):
            ys = max(y_start(dx), 0)
            if y < ys:
                continue
            top = EH if (abs(dx) == h or y == 18) else EG     # 前缘/鼻尖提亮
            v[(c + dx, y, 1)] = ET                            # 下层暗钢
            v[(c + dx, y, 0)] = ET
            v[(c + dx, y, 2)] = top
    # 背脊进气暗线（z=2，中央两侧 y 6..12）
    for y in range(6, 13):
        for dx in (-2, 2):
            v[(c + dx, y, 2)] = ET
    # 中央座舱鼓包（y 13..16，z=3）
    for y in range(13, 17):
        for dx in (-1, 0, 1):
            v[(c + dx, y, 3)] = EG
    for dx in (-1, 0, 1):
        v[(c + dx, 15, 3)] = EC                               # 座舱玻璃
    v[(c, 16, 3)] = EW                                        # 鼻尖白
    # 后缘喷气排气口 ×4（埋入式：凹口 ET + 上缘亮线 EL）
    for ex in (-10, -7, 7, 10):
        ys = y_start(ex)
        v[(c + ex, ys, 1)] = ET
        v[(c + ex, ys + 1, 2)] = EL
        v[(c + ex, ys + 2, 2)] = EL
    # 双垂尾（后缘 W 谷两侧，z 3..4）
    for vx in (-10, 10):
        for dy in range(1, 4):
            for dz in (3, 4):
                v[(c + vx, dy + 1, dz)] = ET
        v[(c + vx, 2, 5)] = EH
    return v


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    jobs = [
        ("player.vox", build_player(), "_preview_player.png", 3),
        ("boss.vox", build_boss(), "_preview_boss.png", 3),
        ("E1.vox", build_e1_base(), "_preview_E1.png", 7),
        ("E1H.vox", build_e1_head(), "_preview_E1H.png", 6),
        ("E2.vox", build_e2(), "_preview_E2.png", 6),
        ("E3.vox", build_e3(), "_preview_E3.png", 6),
        ("E3R.vox", build_e3_rotor(), "_preview_E3R.png", 6),
        ("E4.vox", build_e4(), "_preview_E4.png", 6),
        ("E5.vox", build_e5(), "_preview_E5.png", 6),
        ("E6.vox", build_e6(), "_preview_E6.png", 6),
        # E11/E11T 由 tools/vox/gen_e11.py 专管（返工版舰型 17×46，勿在本文件重建）
        ("E12.vox", build_e12(), "_preview_E12.png", 5),
        ("E12R.vox", build_e12_rotor(), "_preview_E12R.png", 5),
        ("E13.vox", build_e13(), "_preview_E13.png", 4),
    ]
    for name, vox, png, cell in jobs:
        out = os.path.join(OUT_DIR, name)
        info = voxlib.write_vox(out, vox)
        print("write: %-12s size=%-14s voxels=%-5d colors=%d"
              % (name, str(info["size"]), info["voxels"], info["colors"]))
        print("   preview:", voxlib.render_iso(
            vox, os.path.join(os.path.dirname(__file__), png), cell=cell, up_axis="z"))


if __name__ == "__main__":
    main()
