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
    sea_a/b/c/d/e/f.vox  深蓝海面六变体（对角浪纹带，可循环平铺）
    sea_crest.vox        白浪尖特征瓦（底色同海面瓦 + 1 体素宽碎浪线；M1 §16.3 重做）
    shoal.vox            浅滩沙斑
    reef_s.vox           灰岩礁（高 ≤5，不对称，游戏端 rot 四向增加变化）
    island_4x4.vox       草岛超级瓦 64×64 = 4×4 格 = 19.2 世界单位（主岛）
    island_2x2.vox       草岛超级瓦 32×32 = 2×2 格 = 9.6 世界单位（小岛）
    sandbar_2x2.vox      沙洲超级瓦 32×32 = 2×2 格 = 9.6 世界单位（低平沙洲）
    seam_test.vox        2×2 sea_a 平铺接缝测试（32×32，肉眼查跨瓦片连续性）
    _preview_*.png       单件等距预览；_preview_layout.png 混拼排布预览

尺寸纪律（M1 修订）：**岛/沙洲一律走超级瓦整张资产，尺寸只有 4×4 / 2×2 两档**。
M0 的 1×1 `isle_grass`（草岛芯）/`isle_sand`（沙洲）已废弃删除——1×1 的岛在 62.4 宽的走廊里
摆出来就是「撒了一地小白点」，且多瓦拼装做不出有机岸线（design §13.4 ⑨）。
64 = 4×16 顺带把 M2 计划里的 pirate 64×64 切片通路提前验证了。

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


## 抬升体素距瓦边的最小体素数。贴边的抬升块会对着邻居瓦的 z=0 水面立起侧立面，
## 在瓦界留下一排 1 体素高的小墙（_mesh_probe 实测"贴瓦边的竖直面顶点"→ 目标 0）。
## 取 3 而不是 2：探针阈值是 |顶点| > 半宽 − 1.5 = 6.5，而网格原点按"键均值"居中、
## 均值 ≈ 7.49（不是 7.5），于是 margin=2 时最外那个块的竖直面落在 6.511 上——刚好越界
## （实测 24 个顶点，来自 x=13 与 y=13 那两个块）。margin=3 把最外面压到 ≈5.5，留足余量。
CREST_MARGIN = 3


## 礁石岩体距瓦边的最小体素数（同 CREST_MARGIN 的道理：不在瓦界立侧立面）
REEF_MARGIN = 3


def build_crest(rng):
    """白浪尖（M1 §16.3 重做）：底色与海面瓦同源 + **一条收窄的碎浪线**。

    相对 M0 的三处修正（M0 版会把整块瓦读成一个亮方块，design §14.3 记录）：
    1. 底色不再用 `w>0.55 ? SEA_C : SEA_D`——那让亮浪带内的**整块瓦**都变成 SEA_C，
       13×48 的走廊里那块瓦就是个亮方块。现在底色走 `_sea_color`，与 sea_* 逐像素同源；
    2. 浪花线收到 `(x+y) mod 8 == 2` 这一条 1 体素宽的对角线（sin 峰值处），
       两侧 `±1`（s==1/3）才是 SEA_C 过渡带 —— 白线只占瓦面 1/8，读作"浪尖"而非"亮斑"；
    3. 沿线的 FOAM 再按 n4 噪声断续（`n4>0.30`，4 体素一段）+ 抬升块每 7 体素断一次，
       避免变成一条贯穿走廊的长白带；
    4. **抬升只在内圈**（距瓦边 ≥ CREST_MARGIN）：保住 3D 浪花的立体感，
       又不在瓦界立侧立面。颜色线不受边距限制 → 浪花在视觉上仍跨瓦连续。
    """
    v = {}
    n4 = pnoise(4, rng)
    n8 = pnoise(8, rng)
    period = int(BAND_PERIOD)
    for y in range(TILE):
        for x in range(TILE):
            u, vv = x / TILE, y / TILE
            v[(x, y, 0)] = _sea_color(x, y, n4(u, vv) * 0.7 + n8(u, vv) * 0.3)
            s = (x + y) % period          # 浪带相位（0..7）；BAND_PHASE=0 时峰值在 s==2
            if s == 1 or s == 2 or s == 3:
                v[(x, y, 0)] = SEA_C      # 浪线过渡带
                if s == 2 and n4(u, vv) > 0.30:
                    v[(x, y, 0)] = FOAM   # 浪线芯（断续）
                    inner = (CREST_MARGIN <= x < TILE - CREST_MARGIN
                             and CREST_MARGIN <= y < TILE - CREST_MARGIN)
                    if inner and (x - y) % 7 != 0:
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

def build_sandbank(rng, S=32):
    """沙洲超级瓦（S×S 体素，2×2 → 32 = 9.6 世界单位）：低平沙bank + 中央矮沙丘。

    轮廓 = 径向距离 + 双频噪声扰动，与岛同一套手法；沙面最高只到 z=2（约 1.2 世界单位），
    比岛的草丘矮一档 —— 沙洲在观感上要明确低于「岛」这一个层级。
    瓦外水面沿用与海面瓦同分布的取色公式（否则 2×2 的方框会露出来）。
    """
    v = {}
    k = S / 32.0
    n4 = pnoise(4, rng)
    n8 = pnoise(8, rng)
    nw4 = pnoise(4, rng)               # 瓦外水面：mod 16 网格，与海面瓦同尺度（同 build_island）
    nw8 = pnoise(8, rng)
    c = (S - 1) / 2.0
    RAD = S * 0.32
    for y in range(S):
        for x in range(S):
            u, vv = x / S, y / S
            wu, wv = (x % 16) / float(TILE), (y % 16) / float(TILE)
            # 扰动幅度刻意小于岛的 warp：沙洲半径大，再大就会顶到瓦边被切出直线
            r = math.hypot(x - c, y - c) + (n4(u, vv) - 0.5) * 5.2 * k + (n8(u, vv) - 0.5) * 2.0 * k
            v[(x, y, 0)] = _sea_color(x, y, nw4(wu, wv) * 0.7 + nw8(wu, wv) * 0.3)
            if r < RAD:
                v[(x, y, 1)] = SAND if n8(u, vv) < 0.8 else SAND2
            if r < RAD * 0.52:
                h = 1 if n4(u, vv) < 0.62 else 2
                for z in range(2, 2 + h):
                    v[(x, y, z)] = SAND if rng.random() < 0.85 else SAND2
            if RAD * 0.86 < r < RAD * 1.02 and n4(u, vv) > 0.72:
                v[(x, y, 1)] = ROCK          # 滩缘零星礁石
    return v


def build_island(rng, S=32):
    """草岛超级瓦（S×S 体素）：有机轮廓的岛。4×4 → 64（19.2 世界单位，主岛）/ 2×2 → 32（9.6，小岛）。

    轮廓 = 径向距离 + 双频噪声扰动 → 自然是曲线岛缘。
    单张资产一次摆放，不存在多瓦拼接的方块感/接缝（多瓦拼岛做不出这个效果）。
    全部几何常量按 k = S/32 等比缩放，两种尺寸出的是同一族造型（主岛多一层台地）。
    S 必须是 16 的整数倍（mod 16 的噪声网格与海面瓦对齐才成立）。

    三条必须守住的边距纪律（改 RAD / warp 前先算一遍，按「体素索引相对 c=(S-1)/2」算）：
    - 滩面（z=1 的沙）最大半径 = RAD + warp_max；瓦最远的几何面在 d=16.5（S=32），
      留 ≥1 体素余量即可，否则沙顶到瓦边会在瓦界立起一道「沙崖」（邻居的 z=0 水面接不住 z=1 的沙）；
    - 岛外水面（r > RAD+2.2k）必须与相邻海面瓦逐像素同源 → 噪声按 **mod 16 网格**采样
      （64=4×16、32=2×16 整除），否则噪声尺度差 4 倍，瓦界会显出一个「方形水斑」；
    - 浪带 `_band` 对 16 体素格移不变，跨瓦天然对齐，不用管。
    """
    v = {}
    k = S / 32.0
    n4 = pnoise(4, rng)                # 轮廓扰动（瓦内归一化坐标）
    n8 = pnoise(8, rng)                # 丘体/颜色
    nw4 = pnoise(4, rng)               # 岛外水面：mod 16 网格，与海面瓦同尺度
    nw8 = pnoise(8, rng)
    c = (S - 1) / 2.0
    RAD = S * 0.30
    INNER = RAD - S * 0.075            # 草丘外沿 → 沙环宽度
    HMAX = 3 if S <= 32 else 4         # 丘高上限：主岛多一层台地，不然 19.2 宽的岛顶是块平地
    hk = HMAX / 3.0
    for y in range(S):
        for x in range(S):
            u, vv = x / S, y / S
            wu, wv = (x % 16) / float(TILE), (y % 16) / float(TILE)
            warp = (n4(u, vv) - 0.5) * 4.0 * k + (n8(u, vv) - 0.5) * 1.4 * k
            r = math.hypot(x - c, y - c) + warp
            # 岛外水面必须沿用全局浪带公式，否则四周会出现一块"没有浪纹的方形水"
            # （浪带相位对 16 体素格移不变，故直接按局部坐标取值即与相邻海面瓦对齐）
            if r < RAD + 0.9 * k:
                v[(x, y, 0)] = SHAL          # 贴岸浅水
            elif r < RAD + 2.2 * k:
                v[(x, y, 0)] = SEA_B         # 近岸过渡（对比轻，不会框出方形）
            else:
                # 噪声权重与海面瓦同分布（n4*0.7+n8*0.3）且采样网格同尺度：否则岛外
                # 水面的色带统计与相邻海面瓦不一致，会显出一块"方形深水"
                v[(x, y, 0)] = _sea_color(x, y, nw4(wu, wv) * 0.7 + nw8(wu, wv) * 0.3)
            if r < RAD:
                v[(x, y, 1)] = SAND if n8(u, vv) < 0.8 else SAND2
            if r < INNER:
                h = int(round(((INNER - r) * 0.30 + n8(u, vv) * 1.1) * hk)) + 1
                h = max(1, min(h, HMAX))
                for z in range(2, 2 + h):
                    v[(x, y, z)] = GRASS if rng.random() < 0.85 else GRASS2
            if RAD - 1.2 * k < r < RAD + 2.4 * k and n4(u, vv) > 0.74:
                v[(x, y, 1)] = ROCK          # 岸边零星礁石
                v[(x, y, 2)] = ROCK_TOP
    return v


def build_reef(rng):
    """灰岩礁：3 座随机峰位的高斯衰减石堆（不对称，rot 四向增加变化）。

    M1 §16.3 顺带修两处与「跨瓦一致」纪律冲突的地方（都是探针先发现的）：
    1. 底色水面原为**整块扁平 SEA_D** —— 相邻海面瓦有浪带、礁瓦没有，于是在
       230 单位长的走廊里，礁瓦会显成一个"把浪带切断的暗方块"。现在走 `_sea_color`，
       与 sea_* 同分布（噪声网格同尺度、都按 mod 16 采）。
    2. 岩体原本能长到瓦边（峰位 `uniform(3,13)` + 衰减半径最大 5.9 → 溢出瓦外被切平），
       在瓦界立起一圈灰色小墙（探针实测 114 个贴边竖直面顶点）。现在岩体只长在
       **内圈 margin 3** 以内：外缘本来就是 h=1 的薄边，裁掉后读作"岩堆四周是水"，很自然。
    因为底色带了浪带，**礁石瓦从此必须 rot=0**（旋转会错浪带相位 → 瓦界浪纹断开）。
    """
    v = {}
    n4 = pnoise(4, rng)
    n8 = pnoise(8, rng)
    # 峰位收进内圈，且衰减半径上限（ph/0.75 ≈ 5.9）不再溢出瓦边
    lo, hi = 4.5, 11.5
    peaks = [(rng.uniform(lo, hi), rng.uniform(lo, hi), rng.uniform(2.6, 4.4))
             for _ in range(3)]
    for y in range(TILE):
        for x in range(TILE):
            u, vv = x / TILE, y / TILE
            v[(x, y, 0)] = _sea_color(x, y, n4(u, vv) * 0.7 + n8(u, vv) * 0.3)
            if not (REEF_MARGIN <= x < TILE - REEF_MARGIN
                    and REEF_MARGIN <= y < TILE - REEF_MARGIN):
                continue                       # 内圈之外只留水：不在瓦界立侧立面
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


def build_layout(seas, reef, island, sandbar):
    """排布预览：6×6 海面变体混拼 + 一张 4×4 主岛 + 一张 2×2 沙洲 + 一块礁石。

    用来一次看清「三类地貌的相对尺寸与层级」——岛 19.2 > 沙洲 9.6 > 礁 4.8 世界单位
    （design §14 的尺寸纪律）。
    """
    v = {}
    kinds = ["sea_a", "sea_b", "sea_c", "sea_d", "sea_e", "sea_f",
             "sea_c", "sea_a", "sea_e", "sea_b", "sea_f", "sea_d"]
    for ty in range(6):
        for tx in range(6):
            t = seas[kinds[(tx + ty * 2) % len(kinds)]]
            for (x, y, z), col in t.items():
                v[(x + tx * TILE, y + ty * TILE, z)] = col
    for (x, y, z), col in island.items():
        v[(x, y, z)] = col                          # 4×4 主岛落在左上角（0..63）
    for (x, y, z), col in sandbar.items():
        v[(x + 4 * TILE, y + 2 * TILE, z)] = col    # 2×2 沙洲落在右侧（64..95, 32..63）
    for (x, y, z), col in reef.items():
        v[(x + 1 * TILE + 4, y + 4 * TILE + 9, z)] = col
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
    }
    for name, vox in tiles.items():
        _write(name + ".vox", vox, 7)
    # 超级瓦（岛/沙洲）各用独立种子：增删其中一种不会改变另一种的造型（与共享 rng 解耦）
    island4 = build_island(random.Random(SEED + 11), 64)
    island2 = build_island(random.Random(SEED + 13), 32)
    sandbar = build_sandbank(random.Random(SEED + 17), 32)
    _write("island_4x4.vox", island4, 4)
    _write("island_2x2.vox", island2, 5)
    _write("sandbar_2x2.vox", sandbar, 5)
    _write("seam_test.vox", build_seam(tiles["sea_a"]), 5)

    png = os.path.join(os.path.dirname(__file__), "_preview_tiles_layout.png")
    lay = build_layout(tiles, tiles["reef_s"], island4, sandbar)
    print("layout :", voxlib.render_iso(lay, png, cell=2, up_axis="z"))


if __name__ == "__main__":
    main()
