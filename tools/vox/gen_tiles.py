"""生成「瓦片雄鹰」M0 首批瓦片集（16×16 体素，边长 4.8 世界单位）。

规格（llmdoc/tile-eagle-design.html §2，已登记 tools/vox/README.md）：
- 瓦片边长 16 体素 = 4.8 世界单位（游戏端体素缩放 0.3 不变）
- 底面中心锚点：本产线只保证「内容从 z=0 往上长、底层先铺 1 层水色」，
  锚点修正由游戏端 tiles.gd 按 AABB 反推 lift 完成
- 北向：vox +Y = 游戏 -Z；rot 四向；镜像须翻绕序（本批无镜像瓦片）

产线约束（design §4.3）：
- 边缘无缝：噪声/正弦按 (x mod 16, y mod 16) 周期采样，正弦周期必须整除 16（此处 8）
- 单层水面：海面 1 体素高，靠颜色分带表现浪纹；浪尖瓦才抬到 2 层
- 高瓦（礁/沙洲/岛）底层一律先铺 1 层水色——「从 z=0 往上长」，不产生悬空洞

产出（assets/vox/tiles/）：
    sea_a/b/c.vox   深蓝海面三相位变体（对角浪纹带，可循环平铺）
    sea_crest.vox   白浪尖特征瓦（局部抬 1 层）
    shoal.vox       浅滩沙斑
    reef_s.vox      灰岩礁（高 ≤5，不对称，游戏端 rot 四向增加变化）
    isle_sand.vox   近岸水 + 破碎沙滩缘（岛图章外圈）
    isle_grass.vox  草岛芯（高 ≤6，岛图章中心）
    seam_test.vox   2×2 sea_a 平铺接缝测试（32×32，肉眼查跨瓦片连续性）
    _preview_*.png  单件等距预览；_preview_layout.png 混拼排布预览

运行：
    python gen_tiles.py
"""

import math
import os
import random

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "tiles"))
TILE = 16      # 瓦片边长（体素）
SEED = 20260911

# ---------------------------------------------------------------- 色板
# 海面色带对齐方块雄鹰关 1（sea=#0a2540 的海面 plane + 浪痕向白分带），
# 保证对照实验里两作海色同源。
SEA_D = (10, 37, 64)      # #0a2540 深海（关 1 海面色）
SEA_B = (26, 60, 96)      # 浪纹亮带
SEA_C = (46, 88, 126)     # 浪纹高亮带
FOAM = (223, 233, 255)    # 浪尖白
SHAL = (44, 92, 134)      # 近岸浅水
SAND = (214, 192, 138)    # 沙滩
SAND2 = (182, 158, 108)   # 沙滩暗斑
GRASS = (64, 138, 78)     # 草地
GRASS2 = (44, 108, 60)    # 草地暗部
ROCK = (116, 120, 130)    # 岩石
ROCK2 = (86, 90, 100)     # 岩石暗部
ROCK_TOP = (196, 202, 212)  # 岩顶受光


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


BAND_PERIOD = 8.0          # 浪纹周期（必须整除瓦片边长 16 → 跨瓦连续）
BAND_PHASE = 0.0           # 全局相位：所有海面系瓦共用，浪带才能连续贯穿整条走廊


def _band(x, y):
    """对角涌浪带（-1..1）。相位由全局常量决定，禁止逐瓦改动——改了浪带就会在瓦界断开。"""
    return math.sin(2 * math.pi * (x + y) / BAND_PERIOD + BAND_PHASE)


def _sea_color(x, y, n):
    """浪带 + 噪声分色：所有海面系瓦共用，保证色带跨瓦对齐。

    亮带刻意收窄（w>0.72 才高亮）——宽亮带会让人字纹观感变重，深水占比高才像海。
    """
    w = _band(x, y)
    if w > 0.72 and n > 0.40:
        return SEA_C
    if w > 0.20 and n > 0.68:
        return SEA_B
    return SEA_D


def pnoise(cells, rng):
    """周期性 value noise：cells×cells 格点（格点按 mod 周期复用）+ 双线性插值。

    采样坐标 u,v ∈ [0,1) 对应瓦片内 16 格 → 跨瓦片天然无缝（周期 16 整除边长）。
    """
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]

    def at(u, v):
        x, y = u * cells, v * cells
        x0, y0 = int(x) % cells, int(y) % cells
        x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
        fx, fy = x - int(x), y - int(y)
        sx = fx * fx * (3 - 2 * fx)
        sy = fy * fy * (3 - 2 * fy)
        top = grid[y0][x0] * (1 - sx) + grid[y0][x1] * sx
        bot = grid[y1][x0] * (1 - sx) + grid[y1][x1] * sx
        return top * (1 - sy) + bot * sy

    return at


# ---------------------------------------------------------------- 海面系

def build_sea(seed_tag, rng):
    """深蓝海面：全局浪带分色 + 本变体独立的大尺度噪声斑（seed_tag 仅用于区分噪声网格）。

    变体差异全部来自噪声斑与浪尖密度——浪带相位固定共用，否则相邻瓦浪纹会断。
    """
    v = {}
    n4 = pnoise(4, rng)
    n8 = pnoise(8, rng)
    for y in range(TILE):
        for x in range(TILE):
            u, vv = x / TILE, y / TILE
            v[(x, y, 0)] = _sea_color(x, y, n4(u, vv) * 0.7 + n8(u, vv) * 0.3)
    return v


def build_crest(rng):
    """白浪尖：泡沫收在亮浪带内（细碎划线），只少量抬 1 层——避免满屏白色雪点。"""
    v = {}
    for y in range(TILE):
        for x in range(TILE):
            w = _band(x, y)
            v[(x, y, 0)] = SEA_C if w > 0.55 else SEA_D
            if w > 0.55:
                k = (x * 5 + y * 3) % 11
                if k < 1:
                    v[(x, y, 0)] = FOAM
                if k == 3:
                    v[(x, y, 1)] = FOAM
    return v


def build_shoal(rng):
    """浅滩环：近岸水色 + 稀疏沙点（全部贴 z=0 不抬高，与海面平接，无板状边缘）。"""
    v = {}
    n8 = pnoise(8, rng)
    n16 = pnoise(16, rng)
    c = (TILE - 1) / 2.0
    for y in range(TILE):
        for x in range(TILE):
            u, vv = x / TILE, y / TILE
            d_norm = max(abs(x - c), abs(y - c)) / c
            # 底色与海面同源（只在大噪声处轻微提亮一档）——否则浅滩瓦会拼出一块"沙矩形"
            base = _sea_color(x, y, n16(u, vv))
            v[(x, y, 0)] = SEA_B if (n8(u, vv) > 0.55 and _band(x, y) < 0.45) else base
            # 沙点向瓦心聚拢，外缘留水：与满铺沙台相邻时读作"沙滩外浅滩"
            if n16(u, vv) + (0.30 - d_norm * 0.30) > 0.72 and rng.random() < 0.55:
                v[(x, y, 0)] = SAND
    return v


# ---------------------------------------------------------------- 高瓦系

def build_sand(rng):
    """沙洲（1×1 瓦）：小尺度圆形沙斑，轮廓带噪声——方形沙块读起来像贴图错误。

    只用于开阔水面的零星沙洲；成规模的岛请用 2×2 超级瓦 island_2x2。
    """
    v = {}
    n4 = pnoise(4, rng)
    n8 = pnoise(8, rng)
    c = (TILE - 1) / 2.0
    for y in range(TILE):
        for x in range(TILE):
            u, vv = x / TILE, y / TILE
            r = math.hypot(x - c, y - c) + (n4(u, vv) - 0.5) * 4.2 + (n8(u, vv) - 0.5) * 1.6
            v[(x, y, 0)] = _sea_color(x, y, n8(u, vv))
            if r < 5.0:
                v[(x, y, 1)] = SAND if n8(u, vv) < 0.8 else SAND2
    return v


def build_grass(rng):
    """岛图章中心：沙基 + 草丘（中心高边缘低，最高 6 层）。"""
    v = {}
    n4 = pnoise(4, rng)
    n8 = pnoise(8, rng)
    c = (TILE - 1) / 2.0
    for y in range(TILE):
        for x in range(TILE):
            u, vv = x / TILE, y / TILE
            d = max(abs(x - c), abs(y - c))
            v[(x, y, 0)] = SAND if d < 7.0 else SHAL
            edge = 6.6 + n4(u, vv) * 1.6
            if d < edge:
                # 丘体压低加宽（最高 3 层）：台阶过陡会读成"金字形祭坛"而不是植被岛
                h = int(round((edge - d) * 0.55 + n8(u, vv) * 0.9)) + 1
                h = max(1, min(h, 3))
                for z in range(1, h + 1):
                    top = z == h
                    col = GRASS if rng.random() < (0.9 if top else 0.78) else GRASS2
                    v[(x, y, z)] = col
            elif d < edge + 1.1 and rng.random() < 0.6:
                v[(x, y, 1)] = SAND  # 过渡沙沿
    return v


def build_reef(rng):
    """灰岩礁：3 座随机峰位的高斯衰减石堆（不对称，rot 四向增加变化）。"""
    v = {}
    peaks = [(rng.uniform(3, 13), rng.uniform(3, 13), rng.uniform(2.6, 4.4))
             for _ in range(3)]
    for y in range(TILE):
        for x in range(TILE):
            v[(x, y, 0)] = SEA_D
            h = 0
            for px, py, ph in peaks:
                d = math.hypot(x - px, y - py)
                h = max(h, int(round(ph - d * 0.75)))
            h = max(0, min(h, 4))
            for z in range(1, h + 1):
                col = ROCK if rng.random() < 0.75 else ROCK2
                if z == h:
                    col = _lerp(col, ROCK_TOP, 0.5)
                v[(x, y, z)] = col
    return v


def build_island(rng, S=32):
    """2×2 超级瓦（32×32 体素 = 9.6 世界单位）：有机轮廓的小岛。

    轮廓 = 径向距离 + 双频噪声扰动 → 自然是曲线岛缘。
    单张资产一次摆放，不存在多瓦拼接的方块感/接缝（多瓦拼岛做不出这个效果）。
    """
    v = {}
    n4 = pnoise(4, rng)
    n8 = pnoise(8, rng)
    n8b = pnoise(8, rng)
    c = (S - 1) / 2.0
    RAD = S * 0.38
    for y in range(S):
        for x in range(S):
            u, vv = x / S, y / S
            warp = (n4(u, vv) - 0.5) * 6.5 + (n8(u, vv) - 0.5) * 2.5
            r = math.hypot(x - c, y - c) + warp
            # 岛外水面必须沿用全局浪带公式，否则四周会出现一块"没有浪纹的方形水"
            # （浪带相位对 16 体素格移不变，故直接按局部坐标取值即与相邻海面瓦对齐）
            # 岛外水面：弱化噪声权重（与相邻海面瓦的斑块差异越小，方形轮廓越不明显）
            if r < RAD + 1.6:
                v[(x, y, 0)] = SHAL          # 贴岸浅水
            elif r < RAD + 4.0:
                v[(x, y, 0)] = SEA_B         # 近岸过渡（对比轻，不会框出方形）
            else:
                # 噪声权重与海面瓦同分布（n4*0.7+n8*0.3）：否则岛外水面的色带统计与
                # 相邻海面瓦不一致，会显出一块"方形深水"
                v[(x, y, 0)] = _sea_color(x, y, n4(u, vv) * 0.7 + n8b(u, vv) * 0.3)
            if r < RAD:
                v[(x, y, 1)] = SAND if n8(u, vv) < 0.8 else SAND2
            if r < RAD - 3.8:
                h = int(round((RAD - 3.8 - r) * 0.30 + n8(u, vv) * 1.1)) + 1
                h = max(1, min(h, 3))
                for z in range(2, 2 + h):
                    v[(x, y, z)] = GRASS if rng.random() < 0.85 else GRASS2
            if RAD - 1.2 < r < RAD + 2.4 and n4(u, vv) > 0.74:
                v[(x, y, 1)] = ROCK          # 岸边零星礁石
                v[(x, y, 2)] = ROCK_TOP
    return v


# ---------------------------------------------------------------- 测试与预览

def build_seam(sea_a):
    """接缝测试：sea_a 2×2 平铺成 32×32，验收跨瓦片浪纹连续、无错位。"""
    v = {}
    for (x, y, z), col in sea_a.items():
        v[(x, y, z)] = col
        v[(x + TILE, y, z)] = col
        v[(x, y + TILE, z)] = col
        v[(x + TILE, y + TILE, z)] = col
    return v


def build_layout(tiles):
    """排布预览：4×4 海面变体混拼 + 中央 3×3 岛图章 + 一块礁石。"""
    v = {}
    kinds = ["sea_a", "sea_b", "sea_c", "sea_d", "sea_e", "sea_f",
             "sea_c", "sea_a", "sea_e", "sea_b", "sea_f", "sea_d"]
    tiles = dict(tiles)
    tiles["island_2x2"] = build_island(random.Random(SEED + 7))
    for ty in range(4):
        for tx in range(4):
            t = tiles[kinds[(tx + ty * 2) % len(kinds)]]
            for (x, y, z), col in t.items():
                v[(x + tx * TILE, y + ty * TILE, z)] = col
    for (x, y, z), col in tiles["island_2x2"].items():
        v[(x + 3 * TILE, y + 3 * TILE, z)] = col
    for (x, y, z), col in tiles["reef_s"].items():
        v[(x + 1 * TILE + 4, y + 1 * TILE + 2, z)] = col
    return v


def _write(name, vox, cell):
    out = os.path.join(OUT_DIR, name)
    info = voxlib.write_vox(out, vox)
    print("write: %-16s size=%-14s voxels=%-6d colors=%d"
          % (name, str(info["size"]), info["voxels"], info["colors"]))
    png = os.path.join(os.path.dirname(__file__), "_preview_%s.png" % name[:-4])
    print("   preview:", voxlib.render_iso(vox, png, cell=cell, up_axis="z"))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = random.Random(SEED)
    # 海面六变体：相位均分 + 各自独立大噪声格点 + 浪尖密度差异，混拼打破单瓦重复感
    tiles = {
        "sea_a": build_sea("a", rng),
        "sea_b": build_sea("b", rng),
        "sea_c": build_sea("c", rng),
        "sea_d": build_sea("d", rng),
        "sea_e": build_sea("e", rng),
        "sea_f": build_sea("f", rng),
        "sea_crest": build_crest(rng),
        "shoal": build_shoal(rng),
        "reef_s": build_reef(rng),
        "isle_sand": build_sand(rng),
        "isle_grass": build_grass(rng),
    }
    for name, vox in tiles.items():
        _write(name + ".vox", vox, 7)
    _write("island_2x2.vox", build_island(rng), 5)
    _write("seam_test.vox", build_seam(tiles["sea_a"]), 5)

    png = os.path.join(os.path.dirname(__file__), "_preview_tiles_layout.png")
    print("layout :", voxlib.render_iso(build_layout(tiles), png, cell=2, up_axis="z"))


if __name__ == "__main__":
    main()
