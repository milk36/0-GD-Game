"""gen_spec —— 一条命令：spec → 编译校验 → .vox + 等距预览 + 审计摘要。

阶段 1 交付物（llmdoc/ai-voxel-pipeline.html §7）。headless 纯 Python，
不依赖 Godot；视觉验收（游戏相机认物）仍需 GPU 步骤，结束后会打印提示：

    python gen_spec.py specs/e1.json          # 单个 spec
    python gen_spec.py specs/                 # 目录下全部 *.json
    python gen_spec.py specs/ --out <dir>     # 自定义产物目录（默认 assets/vox/units）
"""

import glob
import os
import sys

import voxlib
import voxspec

GODOT = "D:/Tools/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 预览 cell 按包围盒宽自适应（对齐 gen_units.py：小资产 cell 大）。
def _cell(width):
    return 7 if width <= 12 else 6


def run(spec_path, out_dir, write):
    spec, parts = voxspec.compile_spec(spec_path)
    print("== %s（%s / facing %s）" % (spec["name"], spec["category"], spec["facing"]))
    if write:
        os.makedirs(out_dir, exist_ok=True)
    prev_dir = os.path.dirname(os.path.abspath(__file__))
    for part in parts:
        xs, ys, zs = zip(*part["voxels"].keys())
        size = (max(xs) - min(xs) + 1, max(ys) - min(ys) + 1, max(zs) - min(zs) + 1)
        # 默认只编译+审计+预览（不碰正式资产）；--write 才排序落盘（字节可复现）。
        # 既有验证样本（E1/E4/player）的真源仍是 gen_units.py——重建它们会得到
        # 体素集合一致但 XYZI 顺序不同的字节，无功能差异，按 §9.4 不做无谓迁移。
        wrote = ""
        if write:
            out = os.path.join(out_dir, part["file"])
            ordered = {k: part["voxels"][k] for k in sorted(part["voxels"])}
            info = voxlib.write_vox(out, ordered)
            wrote = " -> %s" % out
        png = os.path.join(prev_dir, "_spec_preview_" + os.path.splitext(part["file"])[0] + ".png")
        voxlib.render_iso(part["voxels"], png, cell=_cell(size[0]), up_axis="z")
        print("  %-11s size=%-12s voxels=%-4d colors≈%d%s" %
              (part["file"], str(size), len(part["voxels"]),
               len({tuple(v) for v in part["voxels"].values()}), wrote))
        print("  preview %s" % png)
        for w in part["warnings"]:
            print("  WARN: %s" % w)
    # 多部件单位：按 part 的 assembly 平移合成一张装配预览
    # （视觉初筛看整体——独立旋翼层单看必然"缺旋翼"，等距图会误报）。
    if len(parts) > 1:
        merged = {}
        for part in parts:
            asm = part.get("assembly", (0, 0, 0))
            for (x, y, z), col in part["voxels"].items():
                merged[(x + asm[0], y + asm[1], z + asm[2])] = col
        png = os.path.join(prev_dir, "_spec_preview_%s_all.png" % spec["name"].lower())
        w = max(p["voxels"] and max(x for x, _, _ in p["voxels"]) - min(x for x, _, _ in p["voxels"]) + 1 or 0
                for p in parts)
        voxlib.render_iso(merged, png, cell=_cell(w), up_axis="z")
        print("  assembled  preview %s（assembly 平移合成，运行时挂载以 game.gd 为准）" % png)
    return spec, parts


def main(argv):
    targets = argv[1:]
    write = "--write" in argv
    targets = [t for t in targets if t != "--write"]
    out = voxspec._default_out()
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        targets = [t for j, t in enumerate(targets) if j not in (i, i + 1)]
    if not targets:
        print(__doc__)
        return 2
    specs = []
    for t in targets:
        specs.extend(sorted(glob.glob(os.path.join(t, "*.json"))) if os.path.isdir(t) else [t])
    if not specs:
        print("没有找到 spec 文件：%s" % " ".join(targets))
        return 2
    any_warn = False
    for s in specs:
        _, parts = run(s, out, write)
        any_warn = any(any_warn or p["warnings"] for p in parts)
    print()
    print("headless 部分完成。视觉验收（认物不可省，需 GPU）：")
    print('  "%s" --path <项目> -s res://tools/vox/asset_review.gd' % GODOT)
    print('  "%s" --path <项目> -s res://tools/vox/ingame_view.gd' % GODOT)
    print("回灌比对（零回归 / 漂移检测）：")
    print("  python voxspec.py verify %s --ref <参考.vox>" % specs[0])
    return 1 if any_warn else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
