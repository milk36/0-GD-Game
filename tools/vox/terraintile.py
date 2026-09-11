"""terraintile —— 地形/结构瓦 spec 编译器（M2：结构瓦片批量扩充的产线）。

与 voxspec（单位 spec 编译器）的关系：**共用 op 展开，另立 schema**（design §11 调整 ②
定的方向）。单位 spec 关心「左右对称 / 机头朝向 / 体量带」；地形瓦关心的是另一套约束——
画布必须是 16×span、底层是水、内容从 z=1 长起、高度有上限。所以校验层完全不同，
op 层则原样复用（`voxspec.compile_part`），不复制代码。

地形 spec（JSON）字段：
    name    必填，产出 <name>.vox
    span    必填，1 / 2 / 4 —— 占 N×N 格（16×span 体素见方）
    notes   选填，人类可读说明
    base    选填，缺省 "sea" = 自动铺一整张与 sea_* 同源的水面板；"none" = 不铺（几乎不用）
    parts   必填，op 列表（box / oct / ring / dots / paint）

地形瓦比单位多出的硬约束（编译期拦截，不靠肉眼）：
  * 画布 = 16×span，所有坐标必须在画布内；
  * **禁止写 z=0**——那一层属于水面板（「底层先铺 1 层水色」README §3.8），内容从 z=1 长起；
  * 高度 ≤ ZMAX（24 体素 = 7.2 世界单位；游戏端瓦片包围盒与相机视野的上限）；
  * 不支持镜像系 op（symbox / profile / mirror）——16 宽瓦的对称轴在 7.5，整数轴镜像必偏半格；
    需要对称请用显式 box 成对给出（报错信息里写清楚）。

用法：
    python terraintile.py check specs/terrain/fort_wall.json      # 编译+校验，不落盘
    python terraintile.py build specs/terrain                     # 批量：目录下全部 .json
"""

import glob
import json
import os
import random
import sys

import voxlib
import voxspec
from voxspec import SpecError

import gen_tiles as gt

OUT_DIR = gt.OUT_DIR
CELL = gt.TILE              # 16 体素 = 1 格
ZMAX = 24                   # 24 体素 = 7.2 世界单位
NO_MIRROR_OPS = ("symbox", "profile")

# 地形调色板：直接引用 gen_tiles 的共享色库（含 M2 新增的 WOOD/WOOD2），
# 保证结构瓦与程序化瓦永远同一套颜色。
TILE_PALETTE = {
    "SEA_D": gt.SEA_D, "SEA_B": gt.SEA_B, "SEA_C": gt.SEA_C, "FOAM": gt.FOAM,
    "SHAL": gt.SHAL, "SAND": gt.SAND, "SAND2": gt.SAND2,
    "GRASS": gt.GRASS, "GRASS2": gt.GRASS2,
    "ROCK": gt.ROCK, "ROCK2": gt.ROCK2, "ROCK_TOP": gt.ROCK_TOP,
    "WOOD": gt.WOOD, "WOOD2": gt.WOOD2,
}


def load_spec(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    for key in ("name", "span", "parts"):
        if key not in spec:
            raise SpecError("%s: 缺少顶层字段 %r" % (os.path.basename(path), key))
    if spec["span"] not in (1, 2, 4):
        raise SpecError("%s: span 只能是 1 / 2 / 4" % spec["name"])
    spec.setdefault("base", "sea")
    if spec["base"] not in ("sea", "none"):
        raise SpecError("%s: base 只能是 sea / none" % spec["name"])
    # 镜像系 op 在地形瓦里必偏半格（对称轴 7.5），编译期就拦下
    for i, op in enumerate(spec["parts"]):
        if not isinstance(op, dict):
            raise SpecError("%s: 第 %d 个 op 不是对象" % (spec["name"], i))
        if op.get("op") in NO_MIRROR_OPS or op.get("mirror"):
            raise SpecError("%s: 地形瓦不支持镜像系 op（%s / mirror）——16 宽瓦的对称轴在 7.5，"
                            "整数轴镜像必偏半格；需要对称请用显式 box 成对给出"
                            % (spec["name"], op.get("op")))
    return spec


def build(spec):
    """spec → (blocks, info)。抛 SpecError 表示 spec 不合法。"""
    s = CELL * int(spec["span"])
    # c=0：地形瓦 v1 不用镜像系 op（load_spec 已拦），c 只被那几个 op 引用
    struct = voxspec.compile_part(spec["parts"], 0, TILE_PALETTE)

    # 编译后统一校验「结果」而不是逐 op 校验参数——box/oct/ring/dots/paint 的越界
    # 形态各不相同，查结果一处就全覆盖了
    for (x, y, z) in struct:
        if not (0 <= x < s and 0 <= y < s):
            raise SpecError("%s: 有体素 (%d,%d,%d) 超出画布 [0,%d)²"
                            % (spec["name"], x, y, z, s))
        if z == 0:
            raise SpecError("%s: 有 op 写到了 z=0——那一层属于水面板，内容必须从 z=1 长起"
                            % spec["name"])
        if z > ZMAX:
            raise SpecError("%s: 有体素 z=%d 超过 ZMAX=%d（%.1f 世界单位）"
                            % (spec["name"], z, ZMAX, ZMAX * 0.3))

    v = dict(struct)
    if spec["base"] == "sea":
        rng = random.Random(gt.SEED + 31)          # 每张结构瓦独立噪声，与 gen_tiles 解耦
        n4 = gt.pnoise(4, rng)
        n8 = gt.pnoise(8, rng)
        for y in range(s):
            for x in range(s):
                wu = (x % gt.TILE) / float(gt.TILE)
                wv = (y % gt.TILE) / float(gt.TILE)
                v[(x, y, 0)] = gt._sea_color(x, y, n4(wu, wv) * 0.7 + n8(wu, wv) * 0.3)

    zs = [k[2] for k in struct]
    info = {
        "name": spec["name"], "span": spec["span"], "canvas": s,
        "struct": len(struct), "voxels": len(v),
        "height": (max(zs) + 1) * 0.3 if zs else 0.0,
    }
    return v, info


def run(paths, write):
    for p in paths:
        spec = load_spec(p)
        v, info = build(spec)
        line = ("%-12s span=%d 画布 %d²  结构 %d + 水 %d = %d 块  高 %.1f"
                % (info["name"], info["span"], info["canvas"], info["struct"],
                   info["voxels"] - info["struct"], info["voxels"], info["height"]))
        if not write:
            print("check: " + line)
            continue
        out = os.path.join(OUT_DIR, info["name"] + ".vox")
        res = voxlib.write_vox(out, v)
        print("write: %-12s size=%-14s voxels=%-6d colors=%d"
              % (info["name"] + ".vox", str(res["size"]), res["voxels"], res["colors"]))
        png = os.path.join(os.path.dirname(__file__), "_preview_%s.png" % info["name"])
        print("   preview:", voxlib.render_iso(v, png, cell=6 if info["span"] == 1 else 4,
                                              up_axis="z"))
        print("   " + line)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "build"):
        print(__doc__)
        raise SystemExit("用法: python terraintile.py <check|build> <spec.json | 目录>")
    mode, target = sys.argv[1], sys.argv[2]
    if os.path.isdir(target):
        paths = sorted(glob.glob(os.path.join(target, "*.json")))
    else:
        paths = [target]
    if not paths:
        raise SystemExit("没有找到 spec：%s" % target)
    try:
        run(paths, write=(mode == "build"))
    except SpecError as e:
        print("SPEC ERROR: %s" % e)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
