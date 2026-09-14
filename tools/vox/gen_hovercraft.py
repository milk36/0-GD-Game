"""E16 野牛气垫登陆艇（LCAC）生成器。

体型要求：**厚重感** —— 不做修长舰型，而是「宽体方箱 + 气垫围裙 + 抬高的舰桥 + 三具导管
螺旋桨」，比 E11 战列舰宽 1.4 倍、高 1.4 倍（22×30×11 体素 → 6.6×9.0×3.3 世界单位），
长度只有它的 0.65 → 整体比例是「矮胖厚实」，一眼读出「登陆艇」而不是「军舰」。

结构（x=左右、y=前后、**舰首在 y 大端** = 迎向玩家、z=高低）：
  气垫围裙（z 0~1，暗钢，比舰体略宽 → 浮起来的厚重底边）
  → 舰体（z 2~6，主装甲灰 + 阵营红识别带）
  → 主甲板（z 7，亮钢；中部货舱凹陷 + 艏跳板 + 甲板标线）
  → 舰桥（左舷前部两级 + 观察窗）
  → 舰尾三具导管螺旋桨（涵道 + 桨叶十字）

配色沿用 enemy 调色板（EG/EH/ET/ER/EC/EW）→ 与既有敌方单位同一阵营识别。

    python gen_hovercraft.py
"""

import os

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "units"))

W, L, H = 22, 30, 11        # 体素尺寸
CX = (W - 1) / 2.0

EG = (106, 116, 136)   # 主装甲灰：舰体
EH = (150, 158, 178)   # 亮钢：甲板 / 顶面
ET = (58, 66, 84)      # 暗钢：气垫围裙 / 货舱 / 涵道
ER = (255, 42, 109)    # 阵营品红：识别带
EC = (255, 176, 200)   # 浅粉：观察窗
EW = (232, 238, 248)   # 白：甲板标线
EL = (190, 198, 214)   # 高光：桨叶


def hull_half(y):
    """舰体半宽：气垫艇是宽体方箱 —— 只有艏艉小幅收，中体几乎不收（厚重感来源）。"""
    if y <= 2:
        return 10.0
    if y <= 24:
        return 10.5
    if y <= 27:
        return 10.5 - 0.5 * (y - 24)      # 前段微收 10.5→9
    return 9.0                             # 艏跳板段（保持宽，不收尖）


def build():
    v = {}

    def box(x0, x1, y0, y1, z0, z1, col):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    v[(x, y, z)] = col

    # ---------- 气垫围裙（比舰体宽 1 圈，暗钢 → 读出「浮在气垫上」的厚重底边）----------
    for y in range(L):
        half = hull_half(y)
        x0 = max(0, int(round(CX - half)))
        x1 = min(W - 1, int(round(CX + half)))
        for x in range(x0, x1 + 1):
            v[(x, y, 0)] = ET
            v[(x, y, 1)] = ET
        v[(x0, y, 0)] = ET
        v[(x1, y, 0)] = ET

    # ---------- 舰体（分层：暗底 / 品红识别带 / 装甲灰 / 亮钢甲板）----------
    for y in range(L):
        half = hull_half(y)
        x0 = max(1, int(round(CX - half)))
        x1 = min(W - 2, int(round(CX + half)))
        for x in range(x0, x1 + 1):
            v[(x, y, 2)] = ET            # 底部暗带（水线）
            v[(x, y, 3)] = ER            # 阵营识别带（品红）
            v[(x, y, 4)] = EG
            v[(x, y, 5)] = EG
            v[(x, y, 6)] = EG
            v[(x, y, 7)] = EH            # 主甲板
        # 舷侧纵向加强筋（每 5 列一条暗缝）→ 大面积灰不出「空」
        if y % 5 == 2:
            for x in range(x0, x1 + 1):
                v[(x, y, 5)] = ET

    # ---------- 甲板：中部货舱凹陷 + 甲板标线 ----------
    box(4, 17, 8, 20, 6, 6, ET)          # 货舱（凹陷，暗）
    box(5, 16, 9, 19, 6, 6, ET)
    # 货舱里的载荷（大小/颜色错落的箱体与车辆 → 读出「正在运输」）
    box(6, 8, 10, 12, 6, 7, EH)
    box(10, 12, 13, 15, 6, 7, EG)
    box(6, 8, 15, 18, 6, 7, MID := (56, 64, 72))
    box(12, 14, 10, 12, 6, 7, ER)        # 红蒙布车辆
    box(9, 11, 16, 18, 6, 7, EH)
    v[(7, 11, 7)] = EW
    v[(13, 14, 7)] = EW                  # 载荷上的标线
    for x in (2, 19):                    # 两侧甲板标线
        for y in range(4, 26, 3):
            v[(x, y, 7)] = EW

    # ---------- 艏跳板（放倒的斜坡，宽而不收尖）----------
    box(4, 17, 25, 29, 7, 7, EH)
    box(5, 16, 26, 29, 6, 6, EG)
    box(6, 15, 27, 29, 5, 5, ET)
    box(7, 14, 28, 29, 4, 4, ET)         # 跳板末端搭到地面高度

    # ---------- 舰桥（左舷前部，两级 + 观察窗）----------
    box(1, 6, 19, 25, 8, 9, EG)
    box(2, 5, 20, 24, 10, 10, EH)
    for x in range(2, 6):                # 正面观察窗排（朝向玩家）
        v[(x, 25, 9)] = EC
    v[(2, 20, 10)] = EC
    v[(5, 20, 10)] = EC

    # ---------- 舰尾三具导管螺旋桨（涵道 + 桨叶十字 + 轴心）----------
    for nx in (3, 9, 15):
        box(nx, nx + 3, 0, 4, 5, 9, ET)          # 涵道外壳
        box(nx + 1, nx + 2, 0, 4, 6, 8, EG)      # 涵道内壁
        for y in (1, 3):                          # 桨叶十字（高光色，转起来读得出）
            box(nx + 1, nx + 2, y, y, 6, 8, EL)
        box(nx + 1, nx + 2, 2, 2, 6, 8, EL)
        v[(nx + 1, 2, 7)] = ER                   # 轴心（阵营色）

    # ---------- 艉门 + 舷侧识别块 ----------
    box(7, 14, 0, 1, 5, 7, ET)
    for sx in (0, W - 1):
        for y in range(6, 24, 6):
            v[(sx, y, 5)] = ER
    return v


def main():
    v = build()
    xs = [k[0] for k in v]
    ys = [k[1] for k in v]
    zs = [k[2] for k in v]
    out = os.path.join(OUT_DIR, "E16.vox")
    res = voxlib.write_vox(out, v)
    print("write: E16.vox  size=%-14s voxels=%-6d colors=%d"
          % (str(res["size"]), res["voxels"], res["colors"]))
    print("   bbox %d×%d×%d → %.1f×%.1f×%.1f 世界单位（×0.3）"
          % (max(xs) - min(xs) + 1, max(ys) - min(ys) + 1, max(zs) - min(zs) + 1,
             (max(xs) - min(xs) + 1) * 0.3, (max(ys) - min(ys) + 1) * 0.3,
             (max(zs) - min(zs) + 1) * 0.3))
    print("   对比：E11 战列舰 4.8×13.8×2.4 → 本艇宽 1.4×、高 1.4×、长 0.65×（矮胖厚实）")
    print("   preview:", voxlib.render_iso(
        v, os.path.join(os.path.dirname(__file__), "_preview_E13.png"), cell=6, up_axis="z"))


if __name__ == "__main__":
    main()
