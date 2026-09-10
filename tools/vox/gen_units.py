"""生成「方块雄鹰」试点单位的 .vox 资产：玩家机 + Boss 方舟战舰。

造型原型：需求方提供的参考截图（金属枪灰机身 + 红色涂装，Sky Force 风格）。
产出（Godot 坐标经 vox_reader.gd 的 vox(x,y,z)→godot(x,z,y) 转换后）：
    ../../assets/vox/units/player.vox   玩家机（15×19×7 体素 × 0.3 ≈ 4.5×5.7×2.1 世界单位）
    ../../assets/vox/units/boss.vox     Boss 方舟战舰（25×16×7 体素 × 0.5 ≈ 12.5×8×3.5）
    _preview_player.png / _preview_boss.png  自检预览图

运行：
    python gen_units.py
"""

import os

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "units"))

# 调色板（与 game.gd 旧 PAL_PLAYER 一致，保证材质/配色连续）
G = (106, 116, 132)   # 枪灰（机身侧面）
LG = (152, 162, 180)  # 亮枪灰（顶面甲板：与底部暗色形成强对比，避免俯视时"像底面"）
D = (56, 64, 72)      # 暗灰（腹部/底壳）
R = (232, 50, 62)     # 红（涂装主色）
C = (0, 240, 255)     # 青（座舱脊线，俯视主要识别特征）
W = (245, 249, 255)   # 白（机鼻）
Y = (255, 230, 0)     # 黄（引擎喷口）
K = (42, 48, 58)      # 近黑（舰桥暗部）


def build_player():
    """玩家机（俯视 15 宽 × 19 长，高 7）：机鼻白 → 红颈带 → 枪灰机身
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
                # 顶面甲板：中央青色脊线（俯视主要识别特征）+ 亮灰，强对比避免"像底面"
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
    """Boss 方舟战舰（俯视 17 宽 × 24 长，高 7）：楔形舰艏 → 长条甲板
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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    jobs = [
        ("player.vox", build_player(), "_preview_player.png", 3),
        ("boss.vox", build_boss(), "_preview_boss.png", 3),
    ]
    for name, vox, png, cell in jobs:
        out = os.path.join(OUT_DIR, name)
        print("write:", out, voxlib.write_vox(out, vox))
        print("preview:", voxlib.render_iso(vox, os.path.join(os.path.dirname(__file__), png),
                                            cell=cell, up_axis="z"))


if __name__ == "__main__":
    main()
