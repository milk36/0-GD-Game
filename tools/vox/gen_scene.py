"""程序化生成一座体素小岛（.vox），并渲染等距预览图。

用 voxlib 绕开 MagicaVoxel GUI 直接"造场景"：
    值噪声高度场 + 径向衰减成岛 + 沙滩带 + 树木 + 小屋 + 岸礁
产出：
    ../../assets/vox/island_scene.vox   可直接用 MagicaVoxel 打开继续编辑
    _preview_island.png                 自检预览图

v2（2026-09-11）：去除水体——沿用 gen_pirate.py 的设计约定「不写水体积素」，
所有内容从 z=0 往上长，海面由游戏的海面片提供（旧版自带方形海洋底座，
在游戏里呈现为凸出海面的蓝色方台）。

运行：
    python gen_scene.py
"""

import math
import random
import os

import voxlib

SIZE = (72, 72, 30)
SEED = 20260910

# 调色板（RGB）——无水体色，11 色
C_SAND = (222, 202, 140)
C_GRASS = (86, 158, 74)
C_GRASS2 = (64, 132, 60)
C_ROCK = (118, 118, 126)
C_SNOW = (235, 238, 242)
C_TRUNK = (110, 76, 44)
C_LEAF = (52, 128, 52)
C_LEAF2 = (72, 152, 64)
C_WALL = (196, 168, 130)
C_ROOF = (168, 62, 50)
C_DOOR = (84, 56, 34)


def value_noise(w, h, scale, rng):
    """双线性插值 + 3 倍频的简易值噪声，返回采样函数。"""
    gw, gh = w // scale + 2, h // scale + 2
    grid = [[rng.random() for _ in range(gw)] for _ in range(gh)]

    def sample(u, v):
        iu, iv = int(u), int(v)
        fu, fv = u - iu, v - iv
        fu = fu * fu * (3 - 2 * fu)  # smoothstep
        fv = fv * fv * (3 - 2 * fv)
        a = grid[iv][iu]
        b = grid[iv][iu + 1]
        c = grid[iv + 1][iu]
        d = grid[iv + 1][iu + 1]
        return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv

    return sample


def build():
    rng = random.Random(SEED)
    w, h, depth = SIZE
    n1 = value_noise(w, h, 18, rng)
    n2 = value_noise(w, h, 7, rng)
    n3 = value_noise(w, h, 3, rng)

    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    vox = {}

    def top_color(hh, x, y):
        if hh >= 22:
            return C_SNOW
        if hh >= 18:
            return C_ROCK
        if hh <= 3:
            return C_SAND
        return C_GRASS if (x * 7 + y * 13) % 5 else C_GRASS2

    # ---- 地形（贴地生长：hh<=0 为海面空缺，不写任何体素）
    heights = {}
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / (min(w, h) / 2.0)
            e = n1(x / 18.0, y / 18.0) * 0.55                 + n2(x / 7.0, y / 7.0) * 0.30                 + n3(x / 3.0, y / 3.0) * 0.15
            e = e * 1.25 - max(0.0, d - 0.42) * 2.2   # 径向衰减 → 岛（岸线略外扩）
            hh = int(e * 26)
            hh = max(0, min(depth - 2, hh))
            heights[(x, y)] = hh
            if hh == 0:
                continue
            inner = C_SAND if hh <= 3 else C_ROCK
            for z in range(0, hh + 1):  # 实心柱落到 z=0
                vox[(x, y, z)] = top_color(hh, x, y) if z == hh else inner

    # ---- 岸礁：低矮沙滩外缘散几块灰礁石
    shore = [(x, y) for (x, y), hh in heights.items() if hh == 1]
    rng.shuffle(shore)
    for (x, y) in shore[:9]:
        vox[(x, y, 1)] = C_ROCK if (x + y) % 2 else (146, 146, 154)

    # ---- 树木
    spots = [(x, y) for (x, y), hh in heights.items()
             if 5 <= hh <= 14 and 2 < x < w - 3 and 2 < y < h - 3]
    rng.shuffle(spots)
    placed = []
    for (x, y) in spots:
        if len(placed) >= 14:
            break
        if any(abs(x - px) + abs(y - py) < 6 for px, py in placed):
            continue
        base = heights[(x, y)]
        trunk = rng.randint(3, 5)
        for z in range(base + 1, base + 1 + trunk):
            vox[(x, y, z)] = C_TRUNK
        r = 2
        lz = base + trunk
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                for dz in range(-1, r):
                    if dx * dx + dy * dy + dz * dz * 1.6 <= r * r + 1:
                        p = (x + dx, y + dy, lz + dz)
                        if p not in vox or vox[p] in (C_GRASS, C_GRASS2):
                            vox[p] = C_LEAF if (dx + dy + dz) % 3 else C_LEAF2
        placed.append((x, y))

    # ---- 小屋（放在岛心附近最高平台）
    bx = by = None
    best = -1
    for y in range(h // 2 - 4, h // 2 + 5):
        for x in range(w // 2 - 4, w // 2 + 5):
            flat = min(heights[(x + dx, y + dy)]
                       for dx in range(-3, 5) for dy in range(-3, 5))
            if flat > best:
                best, bx, by = flat, x, y
    ground = max(best, 3)
    for dx in range(-3, 4):
        for dy in range(-3, 4):
            for z in range(0, heights[(bx + dx, by + dy)] + 1):
                vox[(bx + dx, by + dy, z)] = C_SAND  # 找平地基（落到底）
            for z in range(heights[(bx + dx, by + dy)] + 1, ground + 1):
                vox[(bx + dx, by + dy, z)] = C_SAND
    wall_h = 4
    for dx in range(-3, 4):
        for dy in range(-3, 4):
            edge = max(abs(dx), abs(dy)) == 3
            for z in range(ground + 1, ground + 1 + wall_h):
                if edge and not (dy == -3 and dx == 0):  # 南墙留门
                    vox[(bx + dx, by + dy, z)] = C_WALL
            if max(abs(dx), abs(dy)) <= 3:
                rr = 3 - max(abs(dx), abs(dy))
                for z in range(wall_h + 1 - rr, wall_h + 1):  # 金字塔屋顶
                    vox[(bx + dx, by + dy, ground + z)] = C_ROOF
    vox[(bx, by - 3, ground + 1)] = C_DOOR
    vox[(bx, by - 3, ground + 2)] = C_DOOR

    return vox


def main():
    vox = build()
    out_dir = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "vox")
    os.makedirs(out_dir, exist_ok=True)
    out_vox = os.path.abspath(os.path.join(out_dir, "island_scene.vox"))
    info = voxlib.write_vox(out_vox, vox)
    print("write:", out_vox, info)
    png = os.path.join(os.path.dirname(__file__), "_preview_island.png")
    print("preview:", voxlib.render_iso(vox, png, cell=5, up_axis="z"))


if __name__ == "__main__":
    main()
