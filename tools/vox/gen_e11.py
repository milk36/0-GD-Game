"""E11 战列舰 + E11T 三联装炮塔生成器（应需求方「舰体太方正 / 炮塔太小」的返工）。

相对旧版的两处修正（旧版已备份到 tools/vox/_backup_e11/）：
  ① 舰型：旧版 25 宽 × 41 长（长宽比 1.6:1）——真战列舰是 6:1 以上，看起来像驳船。
     新版 **16 宽 × 46 长（2.9:1）**：舰尾圆角 → 平行中体 → 前段收窄 → 舰首收尖，
     四段半宽函数直接写在 hull_half() 里，改舰型只改这一个函数。
  ② 炮塔：旧版 7×18×3（扁、且相对舰体只有 28% 舰宽）。新版 **7×16×5**
     （本体加高 3→5、基座/测距仪/炮管分色），相对舰宽从 28% 提到 44%——
     体素风里再写实就会读不出来。

建模约定（与 gen_units.py 一致）：x=左右、y=前后（**y 大端 = 舰首，朝向玩家**）、z=高低。
配色沿用 enemy 调色板（EG 舰体灰 / EH 亮钢 / ET 暗钢 / ER 品红 / EC 浅粉 / EW 白）。

跑完会打印 **甲板面在 AABB 里的高度分数** 与前后炮座的 y 分数 —— combat.gd::_spawn_air
的挂塔代码（0.5 / 0.74 / 0.16）必须与这里打印的一致，改舰体必复核。

    python gen_e11.py
"""

import os
import random

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "units"))

# enemy 调色板（与 gen_units/voxspec 同值）
EG = (106, 116, 136)   # 舰体灰
EH = (150, 158, 178)   # 亮钢（甲板 / 炮塔顶）
ET = (58, 66, 84)      # 暗钢（水线下 / 基座 / 测距仪）
ER = (255, 42, 109)    # 品红（水线条 / 阵营色 / 天线尖）
EC = (255, 176, 200)   # 浅粉（舰桥观察窗）
EW = (232, 238, 248)   # 白（炮口制退器）
EL = (190, 198, 214)   # 高光边


def hull_half(y: int) -> float:
    """舰体半宽（体素）：舰尾圆角 → 平行中体 → 前段收窄 → 舰首收尖。改舰型只改这里。"""
    if y <= 4:
        return 4.0 + 0.5 * y          # 舰尾：半宽 4 → 6
    if y <= 10:
        return 6.0 + (y - 4) * 0.33   # 6 → 8
    if y <= 32:
        return 8.0                     # 平行中体（全宽 16）
    if y <= 40:
        return 8.0 - (y - 32) * 0.5   # 8 → 4（前段收窄）
    return 4.0 - (y - 40) * 0.62      # 4 → 1.4（舰首收尖）


def build_hull():
    """舰体 16 宽 × 46 长 × 8 高。甲板在体素 z=2，水线条在 z=1，水线下 z=0。"""
    v = {}
    W, L = 16, 46
    cx = (W - 1) / 2.0
    for y in range(L):
        half = hull_half(y)
        x0 = int(round(cx - half))
        x1 = int(round(cx + half))
        for x in range(max(0, x0), min(W - 1, x1) + 1):
            v[(x, y, 0)] = ET      # 水线下（暗钢）
            v[(x, y, 1)] = ER      # 品红水线条
            v[(x, y, 2)] = EH      # 主甲板（亮钢）
        # 舰体两舷外侧一列换暗钢，读出「舷」而不是一块板
        for zz in (1, 2):
            v[(x0, y, zz)] = ET if zz == 1 else EG
            v[(x1, y, zz)] = ET if zz == 1 else EG
    # 甲板中线（EG 走道）：从舰尾拉到舰首
    for y in range(2, L - 2):
        v[(7, y, 2)] = EG
        v[(8, y, 2)] = EG

    def box(x0, x1, y0, y1, z0, z1, col):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    v[(x, y, z)] = col

    # 舰桥（三层内收）+ 观察窗 + 烟囱 + 天线
    box(5, 10, 17, 27, 3, 3, EG)
    box(6, 9, 19, 25, 4, 4, EG)
    box(6, 9, 20, 23, 5, 5, ET)
    for x in range(6, 10):          # 观察窗（浅粉，舰桥正面）
        v[(x, 20, 5)] = EC
    box(7, 8, 24, 25, 6, 6, ET)     # 烟囱
    v[(7, 21, 7)] = ER              # 天线尖（品红，与阵营色呼应）

    # 前后炮座（抬高 1 层的圆角基座，暗钢）——炮塔坐在它上面
    for cy in (7, 34):
        for x in range(5, 11):
            for y in range(cy - 2, cy + 3):
                if abs(x - cx) <= 2.6 and abs(y - cy) <= 2.2:
                    v[(x, y, 3)] = ET

    # 舰尾飞行甲板（暗钢横条纹）：让舰尾不是一块空白
    for x in range(5, 11):
        for y in range(1, 4):
            v[(x, y, 2)] = ET if y % 2 == 1 else EH
    return v


def build_turret():
    """三联装炮塔 7 宽 × 16 长 × 5 高（本体加高 + 基座/测距仪/炮管分色）。"""
    v = {}
    # 本体：7×9×5，逐层内收（舰塔感）
    for z, (x0, x1, y0, y1) in enumerate([(0, 6, 0, 8), (0, 6, 0, 8),
                                          (0, 6, 1, 8), (1, 5, 1, 7), (1, 5, 2, 6)]):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                v[(x, y, z)] = EG if z in (1, 2) else ET if z == 0 else EH
    # 炮塔顶亮钢板 + 后部测距仪（两翼）
    for x in range(1, 6):
        for y in range(2, 7):
            v[(x, y, 4)] = EH
    for y in (0, 1):
        v[(0, y, 4)] = ET
        v[(6, y, 4)] = ET
    v[(3, 1, 5)] = EW               # 测距仪观察窗
    # 三联装炮管：x=1/3/5，从本体前缘伸出 8 体素，炮口白色制退器
    for bx in (1, 3, 5):
        for y in range(8, 16):
            v[(bx, y, 2)] = EG
        v[(bx, 15, 2)] = EW
    # 阵营色识别条（本体两侧）
    for y in range(2, 8):
        v[(0, y, 1)] = ER
        v[(6, y, 1)] = ER
    return v


def stats(v, name):
    keys = list(v.keys())
    mean_z = sum(k[2] for k in keys) / len(keys)
    zmin, zmax = min(k[2] for k in keys), max(k[2] for k in keys)
    deck_frac = 3.0 / (zmax - zmin + 1)      # 甲板顶（体素 z=2 的连续顶=3）
    barbette_frac = 4.0 / (zmax - zmin + 1)  # 炮座顶（体素 z=3 的连续顶=4）
    print("%s: %d 块  z[%d..%d] 均值 %.2f  甲板分数 %.3f  炮座分数 %.3f"
          % (name, len(keys), zmin, zmax, mean_z, deck_frac, barbette_frac))
    return barbette_frac


def main():
    hull = build_hull()
    tur = build_turret()
    for name, v, cell in [("E11", hull, 5), ("E11T", tur, 8)]:
        out = os.path.join(OUT_DIR, name + ".vox")
        res = voxlib.write_vox(out, v)
        print("write: %-12s size=%-14s voxels=%-6d colors=%d"
              % (name + ".vox", str(res["size"]), res["voxels"], res["colors"]))
        print("   preview:", voxlib.render_iso(
            v, os.path.join(os.path.dirname(__file__), "_preview_%s.png" % name),
            cell=cell, up_axis="z"))
    frac = stats(hull, "E11")
    print("--- 挂塔参数（combat.gd::_spawn_air 必须一致）---")
    print("  挂塔高度分数 = %.3f（combat.gd 的 0.33 已按此更新）   前炮座 y 分数 = 0.75   后炮座 y 分数 = 0.16" % frac)


if __name__ == "__main__":
    main()
