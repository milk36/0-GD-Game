"""把海盗主题的外来 64×64 资产接入瓦片走廊（M2：pirate 兼容性验证）。

背景（design §11 调整 ③ / §10 M2）：M0 试点用的是新产的 16 体素海战瓦片集，
海盗主题的 64×64 资产留到 M2 验证「外来大块资产能否零规格冲突地接入 4×4 超级瓦通路」。
结论：**能，但有 3 处必须归一**——这正是本脚本存在的意义（逐条见下方报告字段）。

为什么要导入管线、而不是直接把 pirate_fort.vox 当 span=4 超级瓦：

  ① 内容包围盒不是 16 的倍数（实测 55×49）
     → 不影响接入：span 只决定占位掩码与落位公式，几何由 AABB 居中，不必顶满画布。
       归一动作：平移到原点（去掉画布留白）。
  ② z=0 底层只覆盖 54%（1461 / 55×49），且**一滴水都没有**
     → 相邻海面瓦的水接不进来，瓦界会露出「看穿到背景色」的洞（README §3.8「底层先铺水色」）。
       归一动作：用本产线的 `_sea_color`（mod 16 噪声 + 全局浪带）补齐整张 64×64 水面板，
       与 sea_* 逐像素同源 → 瓦界无缝。
  ③ 外来底层与水面同高（z=0 的沙滩顶面 = 世界 y 0.30 = 水面）
     → 游戏端水面材质按「朝上的面 × 世界 y < 水位线」判定水/陆（water.gdshader 决定 ②），
       沙滩会被误判成水跟着一起起伏、还吃浪光 → 亮沙滩上一圈明暗波动，非常刺眼。
       归一动作：**整个结构抬 1 体素**坐到水面板上（沙滩顶面 → 0.60，与岛/沙洲同级），
       顺带解决「沙滩淹在水里」的观感问题。

配色兼容性（不 remap 的依据）：外来陆上结构 石(86,88,98)/沙(198,176,122)/草(80,144,74)
与本产线 ROCK2(86,90,100)/SAND2(182,158,108)/GRASS(64,138,78) 同族 → 直接保留。

产出：
    assets/vox/tiles/fort_4x4.vox   span=4（19.2 世界单位），36 体素高 ≈ 10.8 世界单位
    控制台打印兼容性报告（原 bbox / 底层覆盖率 / 抬升 / 最终 bbox / 高度）

运行：
    python gen_pirate_tiles.py
"""

import os
import random

import voxlib

import gen_tiles as gt

SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                   "assets", "vox", "pirate", "pirate_fort.vox"))
OUT_DIR = gt.OUT_DIR
S = 64                       # 4×4 超级瓦 = 64 体素
SEED = gt.SEED + 23          # 独立种子：与 gen_tiles 的水面板噪声解耦


def import_super_tile(src_path, name):
    """外来 64×64 资产 → span=4 超级瓦。返回 (blocks, report)。"""
    raw = voxlib.vox_to_colors(src_path)
    if not raw:
        raise SystemExit("%s 是空的" % src_path)

    xs = [k[0] for k in raw]
    ys = [k[1] for k in raw]
    zs = [k[2] for k in raw]
    x0, y0, z0 = min(xs), min(ys), min(zs)
    w = max(xs) - x0 + 1
    h = max(ys) - y0 + 1
    base_cells = w * h
    base_cover = sum(1 for k in raw if k[2] == z0)
    base_water = sum(1 for k, c in raw.items()
                     if k[2] == z0 and c in (gt.SEA_D, gt.SEA_B, gt.SEA_C, gt.SHAL))

    # ① 平移到原点 ② 整体抬 1 体素（z=0 留给水面板）
    struct = {}
    for (x, y, z), c in raw.items():
        nx, ny = x - x0, y - y0
        if not (0 <= nx < S and 0 <= ny < S):
            raise SystemExit("[%s] 内容 %d×%d 超出 %d×%d 画布" % (name, w, h, S, S))
        struct[(nx, ny, z + 1 - z0)] = c

    # ③ 补齐水面板：mod 16 噪声网格 + 全局浪带 → 与相邻海面瓦逐像素同源
    rng = random.Random(SEED)
    n4 = gt.pnoise(4, rng)
    n8 = gt.pnoise(8, rng)
    v = dict(struct)
    for y in range(S):
        for x in range(S):
            wu, wv = (x % gt.TILE) / float(gt.TILE), (y % gt.TILE) / float(gt.TILE)
            v[(x, y, 0)] = gt._sea_color(x, y, n4(wu, wv) * 0.7 + n8(wu, wv) * 0.3)

    kx = [k[0] for k in struct]
    ky = [k[1] for k in struct]
    kz = [k[2] for k in struct]
    report = {
        "name": name,
        "src_bbox": "%d×%d×%d" % (w, h, max(zs) - z0 + 1),
        "base_cover": "%.0f%%（%d/%d，其中水体素 %d）"
                      % (base_cover * 100.0 / base_cells, base_cover, base_cells, base_water),
        "lifted": z0 == 0,
        "struct_bbox": "%d×%d×%d" % (max(kx) - min(kx) + 1, max(ky) - min(ky) + 1,
                                     max(kz) - min(kz) + 1),
        "height_world": (max(kz) + 1) * gt.VOXEL if hasattr(gt, "VOXEL") else (max(kz) + 1) * 0.3,
        "voxels": len(v),
        "struct_voxels": len(struct),
    }
    return v, report


def main():
    v, rep = import_super_tile(SRC, "fort_4x4")
    out = os.path.join(OUT_DIR, "fort_4x4.vox")
    info = voxlib.write_vox(out, v)
    print("write: %-16s size=%-14s voxels=%-6d colors=%d"
          % ("fort_4x4.vox", str(info["size"]), info["voxels"], info["colors"]))
    png = os.path.join(os.path.dirname(__file__), "_preview_fort_4x4.png")
    print("   preview:", voxlib.render_iso(v, png, cell=4, up_axis="z"))

    print("--- pirate 兼容性报告（design §17.1）---")
    print("  源资产 bbox        : %s" % rep["src_bbox"])
    print("  源 z=0 底层覆盖率  : %s" % rep["base_cover"])
    print("  整体抬升 1 体素    : %s（底层与水面同高会误触发水面材质的水位线判定）" % rep["lifted"])
    print("  结构 bbox（抬升后）: %s   高 ≈ %.2f 世界单位" % (rep["struct_bbox"], rep["height_world"]))
    print("  方块数             : 结构 %d + 水面板 %d = %d"
          % (rep["struct_voxels"], rep["voxels"] - rep["struct_voxels"], rep["voxels"]))
    print("  配色               : 陆上结构保留外来调色板（与本产线 ROCK2/SAND2/GRASS 同族）；"
          "水面由本产线重铺")


if __name__ == "__main__":
    main()
