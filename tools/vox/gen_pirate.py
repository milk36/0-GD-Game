"""生成「海盗湾」关卡的地图内容（.vox），并按用途切成多张独立资产。

设计要点：
- **不用水体积素**：所有内容从 z=0 往上长，落到游戏里就是"贴着海面"，与既有草岛 /
  暗礁 / 沉船的摆放方式一致（体素水块会和游戏的海面片打架）。
- **切成多张**：开放海面瓦片 / 海盗岛 / 要塞岛 / 海盗帆船 各自独立成文件，
  运行时可只加载level当前段需要的那几张，避免一次性解析一个超大地图。
- 生成后先看预览图确认，再决定如何接进 game.gd。

产出（assets/vox/pirate/）：
    pirate_sea.vox     64×64 开放海面瓦片（波浪 + 浪花 + 零星礁石），可循环平铺
    pirate_island.vox  72×72 海盗岛（沙滩 / 棕榈 / 木栈桥 / 小屋 / 篝火 / 黑旗）
    pirate_fort.vox    64×64 海盗要塞（石墙 + 炮台 + 塔楼 + 黑旗）
    pirate_ship.vox    26×74 三桅海盗帆船（黑帆 / 炮门 / 艉楼提灯）
    _preview_*.png     单件等距预览
    _layout.png        关卡排布预览（把多张按行进方向拼在一起看整体效果）

运行：
    python gen_pirate.py
"""

import math
import os
import random

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "pirate"))
SEED = 20260910

# ---------------------------------------------------------------- 调色板
DEEP = (22, 50, 94)     # 深海
SEA = (34, 84, 146)     # 海水
SHAL = (62, 132, 188)   # 浅海
FOAM = (178, 220, 238)  # 浪花
SAND = (228, 206, 150)  # 沙滩
SAND2 = (198, 176, 122)  # 沙滩暗部
GRASS = (80, 144, 74)   # 草地
GRASS2 = (58, 118, 56)  # 草地暗部
ROCK = (112, 114, 122)  # 岩石
ROCK2 = (86, 88, 98)    # 岩石暗部
TRUNK = (124, 88, 50)   # 棕榈树干
LEAF = (44, 118, 56)    # 棕榈叶
LEAF2 = (68, 148, 66)   # 棕榈叶亮部
WOOD = (154, 112, 68)   # 木材
WOOD2 = (112, 80, 46)   # 木材暗部
STONE = (154, 152, 146)  # 石墙
STONE2 = (116, 114, 110)  # 石墙暗部
SAIL = (236, 230, 212)  # 帆布
SAIL2 = (198, 190, 168)  # 帆布阴影
FLAG = (34, 34, 40)     # 黑旗
BONE = (238, 236, 228)  # 骷髅白
RED = (196, 58, 52)     # 红漆
GOLD = (222, 176, 72)   # 黄铜/金
LANT = (255, 198, 92)   # 提灯
IRON = (58, 60, 68)     # 铸铁（炮管）


def value_noise(w, h, scale, rng):
    """双线性 + smoothstep 的值噪声，返回 sample(u, v) -> [0,1]。"""
    gw, gh = w // scale + 2, h // scale + 2
    grid = [[rng.random() for _ in range(gw)] for _ in range(gh)]

    def sample(u, v):
        iu, iv = int(u), int(v)
        fu, fv = u - iu, v - iv
        fu = fu * fu * (3 - 2 * fu)
        fv = fv * fv * (3 - 2 * fv)
        a, b = grid[iv][iu], grid[iv][iu + 1]
        c, d = grid[iv + 1][iu], grid[iv + 1][iu + 1]
        return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv

    return sample


# ---------------------------------------------------------------- 通用小件

def stamp_palm(v, x, y, base, rng):
    """棕榈树：弯曲树干 + 放射状叶冠。"""
    trunk = rng.randint(5, 7)
    for i in range(trunk):
        v[(x + (i // 4), y, base + i)] = TRUNK
    tx, ty, tz = x + (trunk // 4), y, base + trunk
    for dx in range(-2, 3):
        for dy in range(-2, 3):
            for dz in (-1, 0, 1):
                if dx * dx + dy * dy + dz * dz * 1.4 <= 5:
                    p = (tx + dx, ty + dy, tz + dz)
                    if p not in v:
                        v[p] = LEAF if (dx + dy + dz) % 3 else LEAF2
    v[(tx, ty, tz + 1)] = LEAF2


def stamp_hut(v, x, y, base, rng, w=5, d=5, wall=3):
    """海盗小屋：木墙 + 红漆双坡屋顶 + 门洞。屋顶比墙多出一圈。"""
    for i in range(w):
        for j in range(d):
            edge = i in (0, w - 1) or j in (0, d - 1)
            for k in range(wall):
                if edge:
                    v[(x + i, y + j, base + k)] = WOOD if (i + j + k) % 2 else WOOD2
            if not edge:
                v[(x + i, y + j, base)] = WOOD2
    door = w // 2
    for k in range(wall):
        v.pop((x + door, y, base + k), None)          # 南面留门
    # 双坡屋顶：沿进深方向逐层收缩，形成人字坡
    ridge = 2
    for k in range(ridge):
        for i in range(w + k):
            for j in range(d + k):
                if (i + j) % 7 == 0:
                    continue
                v[(x - k // 2 + i, y - k // 2 + j, base + wall + k)] = RED if k == 0 else (198, 74, 62)


def stamp_flag(v, x, y, base, height=9):
    """旗杆 + 黑旗（带骷髅白点）。"""
    for k in range(height):
        v[(x, y, base + k)] = WOOD2
    top = base + height - 1
    for i in range(1, 6):
        for k in range(4):
            v[(x + i, y, top - k)] = FLAG
    v[(x + 2, y, top - 1)] = BONE
    v[(x + 2, y, top - 2)] = BONE


def stamp_campfire(v, x, y, base):
    """篝火：石圈 + 交叉木柴 + 橙黄火苗。"""
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        v[(x + dx, y + dy, base)] = ROCK
    v[(x, y, base)] = WOOD2
    v[(x, y, base + 1)] = (255, 150, 40)
    v[(x, y, base + 2)] = LANT


def stamp_jetty(v, x0, y0, length, horizontal, base=1):
    """木栈桥：桥面 + 桥桩（从岸边伸出去的一段）。"""
    for i in range(length):
        x = x0 + (i if horizontal else 0)
        y = y0 + (0 if horizontal else i)
        for w in range(-1, 2):
            px = x if horizontal else x + w
            py = y + w if horizontal else y
            v[(px, py, base + 1)] = WOOD if i % 2 else WOOD2
        if i % 3 == 0 and i > 0:
            for w in range(-1, 2):
                px = x if horizontal else x + w
                py = y + w if horizontal else y
                v[(px, py, base)] = WOOD2


def stamp_cannon(v, x, y, base, axis="x"):
    """铸铁火炮：炮管 + 轮架。axis 决定炮口朝向。"""
    for k in range(3):
        v[(x, y, base + k)] = IRON if k != 1 else (74, 76, 86)
    if axis == "x":
        for i in (1, 2, 3):
            v[(x + i, y, base + 1)] = IRON
    else:
        for i in (1, 2, 3):
            v[(x, y + i, base + 1)] = IRON
    v[(x, y, base - 1)] = WOOD2


# ---------------------------------------------------------------- ① 海面瓦片

def build_sea(S=64):
    """开放海面瓦片：单层水面 + 颜色分带表现浪纹，只有极少数浪尖抬起一格。
    正弦周期整除 S，平铺时接缝连续。
    注：早期版本用"高度场 + 大面积浪花"会糊成一块块浮冰，这里改成靠颜色分带。"""
    v = {}
    two_pi = 2.0 * math.pi
    for y in range(S):
        for x in range(S):
            w = (math.sin(two_pi * x / 32.0)
                 + 0.85 * math.sin(two_pi * y / 32.0 + 0.7)
                 + 0.6 * math.sin(two_pi * (x + y) / 64.0 + 1.9))
            if w > 2.0:
                v[(x, y, 0)] = FOAM
                v[(x, y, 1)] = FOAM          # 浪尖：唯一抬起的一格
            elif w > 0.8:
                v[(x, y, 0)] = SHAL
            elif w > -0.8:
                v[(x, y, 0)] = SEA
            else:
                v[(x, y, 0)] = DEEP
    # 零星礁石（露出水面的石尖）
    rng = random.Random(SEED + 3)
    for _ in range(9):
        cx, cy = rng.randrange(4, S - 4), rng.randrange(4, S - 4)
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                if rng.random() < 0.4:
                    continue
                v[(cx + dx, cy + dy, 0)] = ROCK if rng.random() < 0.6 else ROCK2
        if rng.random() < 0.6:
            v[(cx, cy, 1)] = ROCK2
    return v


# ---------------------------------------------------------------- ② 海盗岛

def build_island(S=72):
    """海盗岛：径向衰减成岛 → 沙滩/草地/岩石分色 → 棕榈林 → 木栈桥 → 小屋 + 篝火 + 黑旗。"""
    rng = random.Random(SEED + 11)
    n1 = value_noise(S, S, 16, rng)
    n2 = value_noise(S, S, 6, rng)
    c = (S - 1) / 2.0
    heights = {}
    v = {}
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - c, y - c) / (S * 0.40)
            e = n1(x / 16.0, y / 16.0) * 0.62 + n2(x / 6.0, y / 6.0) * 0.38
            e = e * 1.28 - max(0.0, d - 0.52) * 2.05   # 越靠外越低 → 入海
            hh = int(e * 20)
            hh = max(0, min(24, hh))
            heights[(x, y)] = hh
            if hh <= 0:
                continue
            for z in range(hh + 1):
                if z < hh:
                    v[(x, y, z)] = SAND2 if hh <= 3 else ROCK2
                else:
                    if hh <= 2:
                        v[(x, y, z)] = SAND
                    elif hh <= 11:
                        v[(x, y, z)] = GRASS if (x * 5 + y * 7) % 6 else GRASS2
                    elif hh <= 17:
                        v[(x, y, z)] = ROCK if (x + y) % 3 else ROCK2
                    else:
                        v[(x, y, z)] = ROCK2

    # 棕榈林
    spots = [(x, y) for (x, y), hh in heights.items()
             if 4 <= hh <= 12 and 3 < x < S - 4 and 3 < y < S - 4]
    rng.shuffle(spots)
    placed = []
    for (x, y) in spots:
        if len(placed) >= 11:
            break
        if any(abs(x - px) + abs(y - py) < 7 for px, py in placed):
            continue
        stamp_palm(v, x, y, heights[(x, y)], rng)
        placed.append((x, y))

    # 木栈桥：从岛南侧浅滩向 +y 伸出
    shore = [(x, y) for (x, y), hh in heights.items()
             if hh == 1 and y > S * 0.55 and abs(x - c) < 5]
    if shore:
        jx, jy = max(shore, key=lambda p: p[1])
        stamp_jetty(v, jx, jy, 11, horizontal=False)

    # 海盗小屋（岛内较平处）
    usable = [(x, y) for (x, y), hh in heights.items() if 4 <= hh <= 10]
    if len(usable) >= 2:
        rng.shuffle(usable)
        huts = []
        for (x, y) in usable:
            if len(huts) >= 2:
                break
            if any(abs(x - px) + abs(y - py) < 14 for px, py in huts):
                continue
            if abs(x - c) < 3 and abs(y - c) < 3:
                continue
            stamp_hut(v, x - 2, y - 2, heights[(x, y)], rng)
            huts.append((x, y))
        if huts:
            hx, hy = huts[0]
            stamp_campfire(v, hx + 5, hy + 1, heights.get((hx + 5, hy + 1), 4))

    # 岛心高处的黑旗（瞭望点）
    peak = max(heights.items(), key=lambda kv: kv[1])[0]
    if heights[peak] >= 5:
        stamp_flag(v, peak[0], peak[1], heights[peak], height=10)
    return v


# ---------------------------------------------------------------- ③ 海盗要塞

def build_fort(S=64):
    """海盗要塞岛：削平的岩台 + 方形石墙（带垛口）+ 四门火炮 + 中央塔楼 + 黑旗。"""
    rng = random.Random(SEED + 23)
    n1 = value_noise(S, S, 14, rng)
    n2 = value_noise(S, S, 5, rng)
    c = (S - 1) / 2.0
    heights = {}
    v = {}
    # 岩台：中心高、边缘入海，整体比海盗岛平
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - c, y - c) / (S * 0.42)
            e = n1(x / 14.0, y / 14.0) * 0.5 + n2(x / 5.0, y / 5.0) * 0.5
            e = e * 1.15 - max(0.0, d - 0.58) * 2.3
            hh = int(e * 12)
            hh = max(0, min(14, hh))
            if d < 0.34:
                hh = max(hh, 8)          # 中央削平的高台
            heights[(x, y)] = hh
            if hh <= 0:
                continue
            for z in range(hh + 1):
                if z == hh:
                    v[(x, y, z)] = SAND if hh <= 2 else (GRASS if hh <= 7 else STONE2)
                else:
                    v[(x, y, z)] = SAND2 if hh <= 3 else ROCK2

    # 方形石墙：以 (c,c) 为中心，边到 9
    base_z = heights.get((int(c), int(c)), 8)
    r = 9
    x0, y0 = int(c) - r, int(c) - r
    x1, y1 = int(c) + r, int(c) + r
    for k in range(5):
        for x in range(x0, x1 + 1):
            for y in (y0, y1):
                v[(x, y, base_z + k)] = STONE if (x + k) % 2 else STONE2
        for y in range(y0, y1 + 1):
            for x in (x0, x1):
                v[(x, y, base_z + k)] = STONE if (y + k) % 2 else STONE2
    # 垛口：墙顶隔一格立一块
    for x in range(x0, x1 + 1, 2):
        for y in (y0, y1):
            v[(x, y, base_z + 5)] = STONE
    for y in range(y0, y1 + 1, 2):
        for x in (x0, x1):
            v[(x, y, base_z + 5)] = STONE
    # 南墙开城门
    for x in range(int(c) - 1, int(c) + 2):
        for k in range(5):
            v.pop((x, y1, base_z + k), None)

    # 四门火炮架在墙上（朝外）
    stamp_cannon(v, int(c) - 1, y0, base_z + 5, axis="x")
    stamp_cannon(v, int(c) + 1, y1, base_z + 5, axis="x")
    stamp_cannon(v, x0, int(c), base_z + 5, axis="y")
    stamp_cannon(v, x1, int(c), base_z + 5, axis="y")

    # 中央塔楼
    t = 4
    tx, ty = int(c), int(c)
    for k in range(13):
        for x in range(tx - t, tx + t + 1):
            for y in range(ty - t, ty + t + 1):
                edge = x in (tx - t, tx + t) or y in (ty - t, ty + t)
                if not edge:
                    continue
                v[(x, y, base_z + 6 + k)] = STONE if (x * 3 + y + k) % 4 else STONE2
    for x in range(tx - t, tx + t + 1, 2):     # 塔顶垛口
        for y in (ty - t, ty + t):
            v[(x, y, base_z + 19)] = STONE
    for y in range(ty - t, ty + t + 1, 2):
        for x in (tx - t, tx + t):
            v[(x, y, base_z + 19)] = STONE
    # 塔身窗（金漆）
    for k in (3, 8):
        v[(tx, ty - t, base_z + 6 + k)] = GOLD
    v[(tx, ty, base_z + 19)] = WOOD2
    # 塔楼黑旗
    stamp_flag(v, tx, ty, base_z + 20, height=8)

    # 岩石岸点缀
    for _ in range(6):
        rx, ry = rng.randrange(3, S - 3), rng.randrange(3, S - 3)
        if heights.get((rx, ry), 0) > 0:
            continue
        v[(rx, ry, 0)] = ROCK
        if rng.random() < 0.7:
            v[(rx, ry, 1)] = ROCK2
    return v


# ---------------------------------------------------------------- ④ 海盗帆船

def _hull_half(y, L):
    """船体半宽剖面：艏尖 → 中段最宽 → 艉略收（三桅帆船）。"""
    t = y / float(L - 1)
    if t < 0.03:
        return 1
    if t < 0.10:
        return int(1 + (t - 0.03) / 0.07 * 4)
    if t < 0.30:
        return int(5 + (t - 0.10) / 0.20 * 6)
    if t < 0.70:
        return 11
    if t < 0.86:
        return int(11 - (t - 0.70) / 0.16 * 1)
    return 9


def build_ship(W=26, L=74):
    """三桅海盗帆船：深木色船体 + 金框炮门 + 红漆舷缘 + 两层方帆 + 艉楼提灯 + 主桅黑旗。
    船体只留"外壳 + 甲板 + 底"（内部空腔不可见），体素数砍掉 2/3。"""
    v = {}
    c = W // 2
    DECK = 9
    half = [_hull_half(y, L) for y in range(L)]
    for y in range(L):
        h = half[y]
        for dx in range(-h, h + 1):
            x = c + dx
            shell = abs(dx) >= h - 1
            for z in range(DECK + 1):
                if z <= 2 or z == DECK or shell:
                    v[(x, y, z)] = WOOD2 if (z <= 2 or z == DECK and (x + y) % 3) else WOOD
                if z == DECK:
                    v[(x, y, z)] = WOOD if (x + y) % 3 else WOOD2   # 甲板
            if abs(dx) == h:                                        # 舷墙 + 炮门
                v[(x, y, DECK + 1)] = WOOD2
                if 6 <= y <= L - 18 and y % 7 == 0:
                    v[(x, y, 6)] = IRON
                    v[(x, y, 5)] = GOLD
    for y in range(1, L - 1):                                       # 舷缘红漆
        h = half[y]
        for dx in (-h, h):
            v[(c + dx, y, DECK + 2)] = RED

    # 艉楼（两级台阶，越往艉越高）
    steps = [(L - 13, L - 1, 3), (L - 7, L - 1, 6)]
    for (ya, yb, hh) in steps:
        for y in range(ya, yb):
            h = half[y]
            for dx in range(-h, h + 1):
                for z in range(DECK + 1, DECK + 1 + hh):
                    if abs(dx) == h or y == yb - 1:
                        v[(c + dx, y, z)] = WOOD if (y + z) % 3 else WOOD2
        for y in range(ya, yb):
            h = half[y]
            for dx in range(-h, h + 1):
                v[(c + dx, y, DECK + 1 + hh)] = WOOD2               # 平台面
    for dx in range(-3, 4):                                         # 艉窗 + 提灯
        v[(c + dx, L - 1, DECK + 3)] = GOLD
    v[(c, L - 1, DECK + 8)] = LANT
    v[(c, L - 2, DECK + 8)] = (255, 226, 150)

    # 艏斜桅（向艏外侧前伸并上扬）
    for i in range(1, 9):
        v[(c, 3 - i, DECK + 1 + i)] = WOOD2
    v[(c, -5, DECK + 9)] = SAIL2

    # 三桅：桅杆 + 横桁 + 悬挂在其下的方帆
    masts = [int(L * 0.31), int(L * 0.51), int(L * 0.71)]
    mast_h = [21, 26, 19]
    for mi, my in enumerate(masts):
        base = DECK + 1
        top = base + mast_h[mi]
        for z in range(base, top):
            v[(c, my, z)] = WOOD2
        v[(c, my, top)] = GOLD
        for (dz, sw, sh) in ([11, 8, 6], [18, 6, 5]):
            zz = base + dz
            if zz >= top - 1:
                continue
            for dx in range(-sw, sw + 1):                           # 横桁
                v[(c + dx, my, zz)] = WOOD2
            for dx in range(-sw + 1, sw):                           # 帆：挂在横桁下方
                for k in range(1, sh + 1):
                    if zz - k <= base:
                        continue
                    v[(c + dx, my, zz - k)] = SAIL if (dx + k) % 5 else SAIL2
    # 主桅黑旗（骷髅）
    my = masts[1]
    top = DECK + 1 + mast_h[1]
    for i in range(1, 8):
        for k in range(5):
            v[(c + i, my, top - 1 - k)] = FLAG
    v[(c + 3, my, top - 3)] = BONE
    v[(c + 3, my, top - 1)] = BONE
    return v


# ---------------------------------------------------------------- 输出

def _write(name, vox, cell, previews):
    out = os.path.join(OUT_DIR, name)
    info = voxlib.write_vox(out, vox)
    print("write: %-18s size=%-14s voxels=%-6d colors=%d"
          % (name, str(info["size"]), info["voxels"], info["colors"]))
    png = os.path.join(os.path.dirname(__file__), "_preview_%s.png" % name[:-4])
    print("   preview:", voxlib.render_iso(vox, png, cell=cell, up_axis="z"))
    previews.append(name)


def build_layout(sea, island, fort, ship):
    """关卡排布预览：把多张切片按行进方向（+y）摆开，中间铺海面瓦片。"""
    v = {}
    SW = 64
    # 海面瓦片平铺 2 列 × 6 行
    for ty in range(6):
        for tx in range(2):
            for (x, y, z), col in sea.items():
                v[(x + tx * SW, y + ty * SW, z)] = col
    def place(src, ox, oy):
        for (x, y, z), col in src.items():
            v[(x + ox, y + oy, z)] = col
    cx = (2 * SW - 72) // 2
    place(island, cx + 20, 26)                 # 近端：海盗岛
    place(fort, cx - 4, 158)                   # 中段：要塞
    place(ship, cx + 18, 276)                  # 远端：帆船
    return v


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    previews = []
    sea = build_sea()
    island = build_island()
    fort = build_fort()
    ship = build_ship()

    _write("pirate_sea.vox", sea, 5, previews)
    _write("pirate_island.vox", island, 4, previews)
    _write("pirate_fort.vox", fort, 4, previews)
    _write("pirate_ship.vox", ship, 4, previews)

    layout = build_layout(sea, island, fort, ship)
    png = os.path.join(os.path.dirname(__file__), "_preview_layout.png")
    print("layout :", len(layout), "体素 ->", voxlib.render_iso(layout, png, cell=3, up_axis="z"))


if __name__ == "__main__":
    main()
