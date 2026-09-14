"""E14 / E15 零式战斗机生成器（红 / 金两种涂装）。

体型要求：**小巧** —— 13×15×5 体素 → 3.9×4.5×1.5 世界单位，比现有 E4 战斗机
（19×20×5 → 5.7×6.0×1.5）短 0.75×、窄 0.68× —— 二战零式的特点就是轻、小、灵活。

结构（x=左右、y=前后、**机头在 y 大端** = 迎向玩家、z=高低）：
  下单翼（椭圆翼形，翼展随弦向变化）+ 圆角翼尖
  → 机身（三段：尾锥 / 中段 / 发动机罩，罩前带螺旋桨）
  → 座舱气泡罩（青）
  → 垂直尾翼 + 水平尾翼
  → 主起落架短桩 + 翼炮
  → 机翼白日徽（白圆，红/金机身上的高对比标识）

两种涂装只换机体主色（def 层也只换 vox）：
  E14 = 红（232,50,62）   E15 = 金（255,208,80）
其余（暗罩/青罩/白徽/暗起落架）保持一致 → 一眼看出是同一机型的两个中队。

    python gen_zero.py
"""

import os

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "units"))

W, L, H = 13, 15, 5        # 体素尺寸

DARK = (42, 48, 58)        # 发动机罩 / 尾翼 / 起落架 / 螺旋桨
CYAN = (0, 240, 255)       # 座舱罩
WHITE = (232, 238, 248)    # 机翼白日徽 / 螺旋桨毂
RED = (232, 50, 62)        # 涂装 A：红
GOLD = (255, 208, 80)      # 涂装 B：金

# 机翼半展（按弦向 y 变化 → 椭圆翼形；x 中心 6）
WING = {5: 4, 6: 6, 7: 6, 8: 5, 9: 3}


def build(body):
    v = {}

    def box(x0, x1, y0, y1, z0, z1, col):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    v[(x, y, z)] = col

    # ---------- 下单翼（椭圆）+ 翼尖圆角 ----------
    for y, half in WING.items():
        box(6 - half, 6 + half, y, y, 2, 2, body)
    box(4, 8, 5, 9, 2, 2, body)          # 翼根加厚（与机身接合）
    v[(0, 7, 2)] = body                   # 翼尖补圆角
    v[(12, 7, 2)] = body
    # 翼前缘暗色（读得出翼型朝向）+ 翼炮
    for x in (1, 11):
        v[(x, 5, 2)] = DARK
    v[(3, 9, 2)] = DARK
    v[(9, 9, 2)] = DARK                   # 翼炮口（暗）

    # ---------- 机身：尾锥 → 中段 → 发动机罩 ----------
    box(6, 6, 0, 1, 1, 3, body)           # 尾锥（细）
    box(5, 7, 2, 12, 1, 3, body)          # 中段
    box(5, 7, 13, 14, 1, 3, DARK)         # 发动机罩（暗）
    v[(6, 14, 2)] = WHITE                 # 螺旋桨毂
    box(5, 7, 14, 14, 1, 3, DARK)         # 螺旋桨（正面看是一根竖条）

    # ---------- 座舱气泡罩（青，偏后 → 零式的长机身比例）----------
    box(6, 6, 9, 11, 3, 4, CYAN)
    v[(6, 10, 4)] = CYAN

    # ---------- 尾翼 ----------
    box(6, 6, 0, 2, 3, 4, DARK)           # 垂直尾翼
    box(4, 8, 0, 1, 2, 2, DARK)           # 水平尾翼

    # ---------- 主起落架（短桩，机腹）----------
    box(2, 3, 6, 7, 0, 1, DARK)
    box(9, 10, 6, 7, 0, 1, DARK)

    # ---------- 机翼白日徽（白圆，红/金机身上的高对比标识）----------
    for cx in (1, 10):
        box(cx, cx + 1, 6, 7, 2, 2, WHITE)
    return v


def main():
    for name, body, cell in (("E14", RED, 12), ("E15", GOLD, 12)):
        v = build(body)
        xs = [k[0] for k in v]
        ys = [k[1] for k in v]
        zs = [k[2] for k in v]
        out = os.path.join(OUT_DIR, name + ".vox")
        res = voxlib.write_vox(out, v)
        print("write: %-9s size=%-14s voxels=%-6d colors=%d  机体色 %s"
              % (name + ".vox", str(res["size"]), res["voxels"], res["colors"], str(body)))
        print("   bbox %d×%d×%d → %.1f×%.1f×%.1f 世界单位（×0.3）"
              % (max(xs) - min(xs) + 1, max(ys) - min(ys) + 1, max(zs) - min(zs) + 1,
                 (max(xs) - min(xs) + 1) * 0.3, (max(ys) - min(ys) + 1) * 0.3,
                 (max(zs) - min(zs) + 1) * 0.3))
        print("   preview:", voxlib.render_iso(
            v, os.path.join(os.path.dirname(__file__), "_preview_%s.png" % name),
            cell=cell, up_axis="z"))
    print("   对比：E4 战斗机 5.7×6.0×1.5 → 零式短 0.75×、窄 0.68×（小巧）")


if __name__ == "__main__":
    main()
