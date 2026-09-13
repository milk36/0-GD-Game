"""Boss 方舟（boss.vox）精细化重做。

需求反馈：「模型比较粗、比例小没压迫感、细节不够，不符合 Boss 设定」。
旧版 17×24×6 → 8.5×12×3 世界单位（×0.5），实际只是一块平板 + 两个红盒子 + 一个深色方块；
和 E11 战列舰（4.8×13.8×2.4）同量级 —— Boss 没有「旗舰」的存在感。

新版 **22×32×13 → 11×16×6.5 世界单位**（体积约旧版 5 倍、比战列舰宽 2.3 倍高 2.7 倍），
结构从「一块板」变成分层旗舰：舰底/红水线/舷侧装甲缝 + 舷灯 → 主甲板（中线走道 + 横向缝 +
标线）→ 左右舷侧舷台（进气辉光 + 排气羽 + 舷缝）→ 四级内收舰桥（三层观察窗 +
桅杆红灯）→ 艏部双联主炮（抬高的炮座 + 顶板 + 白炮口）+ 两座舷侧副炮 → 舰首冲角 +
舰尾推进鳍（青色辉光）+ 舰尾识别带。

配色沿用旧 boss 的八色（与 gen_units 的 player 族同值，保持 Boss 的「红色识别带 +
青窗 + 黄引擎」livery 不变，只重做几何）。

挂点耦合（改尺寸必复核）：
  * combat.gd::BOSS_HOLD_Z —— 悬停位，按 16 单位舰长取 -10（视野上缘 ≈ -18.3）
  * waves.gd 的 "BOSS" hit —— 命中半径 Vector2(x, z)，按半宽/半长取 (5.5, 8.0)
  * scale 0.5 不变（waves.gd 注释：全表唯一例外）

    python gen_boss.py
"""

import os

import voxlib

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                       "assets", "vox", "units"))

W, L, H = 20, 38, 12          # 体素尺寸（舰长沿 +y，舰首在 y 大端 = 迎向玩家）
CX = (W - 1) / 2.0

# 旧 boss 的八色调色板（与新模型一致，保持同一 livery）
DARK = (42, 48, 58)     # 近黑：装甲缝 / 舰底 / 炮座
MID = (56, 64, 72)      # 中暗灰：舷侧下段 / 走道
GUN = (106, 116, 132)   # 主装甲灰
LIGHT = (152, 162, 180)  # 亮钢：甲板 / 顶面 / 炮塔顶
RED = (232, 50, 62)     # 阵营红：水线条 / 识别带 / 桅杆灯
WHITE = (245, 249, 255)  # 白：炮口制退器 / 甲板标线
YELLOW = (255, 230, 0)  # 引擎黄：排气羽
CYAN = (0, 240, 255)    # 青：观察窗 / 舷灯 / 推进辉光


def hull_half(y):
    """舰体半宽：舰尾圆角 → 平行中体 → 前段收窄 → 舰首收尖。改舰型只改这里。
    长宽比 38:20 = 1.9:1（旧版 32:22 = 1.45，读起来像驳船/要塞）。"""
    if y <= 4:
        return 6.0 + 0.5 * y          # 舰尾 6→8
    if y <= 8:
        return 8.0 + 0.375 * (y - 4)  # 8→9.5
    if y <= 26:
        return 9.5                     # 平行中体（全宽 20）
    if y <= 32:
        return 9.5 - 0.58 * (y - 26)  # 9.5→6
    return 6.0 - 1.0 * (y - 32)       # 6→1（舰首收尖）


def build():
    v = {}

    def box(x0, x1, y0, y1, z0, z1, col):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    v[(x, y, z)] = col

    def barrels(xs, y0, y1, z, col=GUN, tip=WHITE):
        """炮管组：细长（1×n），炮口白点 —— 俯视下靠长度与颜色读出来"""
        for bx in xs:
            for y in range(y0, y1 + 1):
                v[(bx, y, z)] = col
            v[(bx, y1, z)] = tip

    def turret(cx, cy, half_x, half_y, z0, barrels_x, by0, by1):
        """炮塔：抬高炮座（暗）→ 本体（灰）→ 顶板（亮）→ 炮管（伸出本体的方向）"""
        box(cx - half_x - 1, cx + half_x + 1, cy - half_y - 1, cy + half_y + 1,
            z0, z0, MID)                                  # 炮座
        box(cx - half_x, cx + half_x, cy - half_y, cy + half_y, z0 + 1, z0 + 2, GUN)
        box(cx - half_x + 1, cx + half_x - 1, cy - half_y + 1, cy + half_y - 1,
            z0 + 3, z0 + 3, LIGHT)                        # 顶板

    # ---------- 舰体（分五层：舰底 / 红水线 / 舷侧下 / 舷侧上 / 主甲板）----------
    for y in range(L):
        half = hull_half(y)
        x0 = max(0, int(round(CX - half)))
        x1 = min(W - 1, int(round(CX + half)))
        for x in range(x0, x1 + 1):
            v[(x, y, 0)] = DARK
            v[(x, y, 1)] = RED
            v[(x, y, 2)] = MID
            v[(x, y, 3)] = GUN
            v[(x, y, 4)] = LIGHT
        # 舷侧装甲缝（每 4 列一条）→ 读出「分舱」而不是一块整板
        if y % 4 == 2 and x1 - x0 > 8:
            for x in range(x0 + 1, x1):
                v[(x, y, 2)] = DARK
                v[(x, y, 3)] = DARK
        # 舷灯（青，隔 3 格）
        if y % 3 == 0 and x1 - x0 > 6:
            v[(x0, y, 3)] = CYAN
            v[(x1, y, 3)] = CYAN

    # ---------- 主甲板（68° 俯视下最大可见面，细节优先）----------
    for y in range(2, L - 2):
        v[(9, y, 4)] = MID
        v[(10, y, 4)] = MID                     # 中线走道
        if y % 6 == 0:
            for x in range(2, W - 2):
                v[(x, y, 4)] = MID              # 横向甲板缝
    for y in range(4, 34, 4):                    # 甲板标线：中线白虚线（不是散块）
        v[(9, y, 4)] = WHITE
        v[(10, y, 4)] = WHITE

    # ---------- 舰桥（四级内收 + 三层观察窗 + 桅杆）----------
    box(6, 13, 16, 22, 5, 6, GUN)
    for y in range(17, 22, 2):
        v[(6, y, 6)] = CYAN
        v[(13, y, 6)] = CYAN
    for x in range(7, 13, 2):
        v[(x, 22, 6)] = CYAN                     # 正面窗排（朝向玩家）
    box(7, 12, 17, 21, 7, 7, LIGHT)
    box(7, 12, 17, 21, 8, 8, GUN)
    for x in range(8, 12, 2):
        v[(x, 21, 8)] = CYAN
    box(8, 11, 18, 20, 9, 9, LIGHT)
    box(8, 11, 18, 20, 10, 10, MID)
    v[(8, 20, 10)] = CYAN
    v[(11, 20, 10)] = CYAN
    box(9, 10, 18, 19, 11, 11, DARK)
    v[(9, 19, 11)] = RED                         # 桅杆顶灯

    # ---------- 前后双三联装主炮（炮管对称朝外 → 俯视轮廓清晰）----------
    turret(9, 30, 3, 3, 5, None, 0, 0)           # 艏炮
    barrels((7, 9, 11), 33, 37, 7)               # 艏炮炮管朝 +y（迎向玩家）
    turret(9, 8, 3, 3, 5, None, 0, 0)            # 艉炮
    barrels((7, 9, 11), 1, 5, 7)                 # 艉炮炮管朝 -y

    # ---------- 舷侧副炮 ×2（炮管朝 +y，短）----------
    for tx in (3, 15):
        box(tx, tx + 1, 18, 20, 5, 6, GUN)
        box(tx, tx + 1, 18, 20, 7, 7, LIGHT)
        barrels((tx, tx + 1), 21, 24, 6)

    # ---------- 舰尾引擎组（三个喷口 + 排气羽）----------
    box(6, 13, 0, 5, 2, 6, GUN)
    box(6, 13, 0, 5, 6, 6, LIGHT)
    for ex in (7, 9, 11):
        box(ex, ex + 1, 0, 0, 3, 5, CYAN)        # 喷口辉光
        v[(ex, 1, 4)] = YELLOW                   # 排气羽
    box(5, 14, 0, 0, 4, 4, RED)                  # 舰尾识别带

    # ---------- 舰首冲角 ----------
    box(8, 11, 34, 37, 4, 4, LIGHT)
    box(9, 10, 35, 37, 5, 5, RED)
    v[(9, 37, 5)] = WHITE
    return v


def main():
    v = build()
    xs = [k[0] for k in v]
    ys = [k[1] for k in v]
    zs = [k[2] for k in v]
    out = os.path.join(OUT_DIR, "boss.vox")
    res = voxlib.write_vox(out, v)
    print("write: boss.vox  size=%-14s voxels=%-6d colors=%d"
          % (str(res["size"]), res["voxels"], res["colors"]))
    print("   bbox %d×%d×%d 体素 → %.1f×%.1f×%.1f 世界单位（scale 0.5）"
          % (max(xs) - min(xs) + 1, max(ys) - min(ys) + 1, max(zs) - min(zs) + 1,
             (max(xs) - min(xs) + 1) * 0.5, (max(ys) - min(ys) + 1) * 0.5,
             (max(zs) - min(zs) + 1) * 0.5))
    print("   preview:", voxlib.render_iso(
        v, os.path.join(os.path.dirname(__file__), "_preview_boss.png"),
        cell=7, up_axis="z"))
    print("   挂点复核：BOSS_HOLD_Z 建议 -9（舰长 19，视野上缘 ≈ -18.3，舰首略出框 = 压顶感）；"
          "hit 建议 Vector2(5.0, 9.5)")


if __name__ == "__main__":
    main()
