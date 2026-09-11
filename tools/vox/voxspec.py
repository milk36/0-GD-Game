"""voxspec —— 声明式单位 spec 编译器（AI 体素管线 L2 的确定性落盘出口）。

spec（JSON）→ 展开 op 为体素表 → 校验约束 → voxlib.write_vox 落盘。
设计见 llmdoc/ai-voxel-pipeline.html（§4 op 集合、§5 校验、§9 评审修订）。

核心约定：
  * 坐标与 gen_units.py 完全一致：x=左右（axis c 为镜像轴，2c-x 镜像）、
    y=前后（数值小 = 游戏 -Z）、z=高低；输出即 MagicaVoxel 原生 Z-up 坐标。
  * solid / paint 语义分离（§9.2）：box/symbox/oct/profile/dots 只添加体素
    （重写已有坐标 = 换色，无害）；paint 只对已存在体素改色，绝不新增。
  * 颜色只能引用命名调色板（PALETTES），不开放自由造色；调色板 ≤255 色由
    voxlib.write_vox 兜底。
  * v1 无随机 op：随机类建模必须显式 seed 的规则在引入随机 op 时生效。

用法：
    python voxspec.py check  specs/e1.json                 # 编译+校验，不落盘
    python voxspec.py build  specs/e1.json [--out DIR]      # 编译+校验+写 .vox
    python voxspec.py verify specs/e1.json --ref ../..assets/vox/units/E1.vox
                                                             # 逐体素比对（零回归闸门 / 漂移检测）
"""

import json
import os
import sys

import voxlib

# ---------------------------------------------------------------- 命名调色板
# 与 gen_units.py 逐色一致（零回归闸门依赖这点，改色请两边同步）。

PALETTES = {
    "player": {
        "G": (106, 116, 132),   # 枪灰
        "LG": (152, 162, 180),  # 亮枪灰（顶面甲板）
        "D": (56, 64, 72),      # 暗灰（腹部/底壳）
        "R": (232, 50, 62),     # 红（涂装主色）
        "C": (0, 240, 255),     # 青（座舱脊线）
        "W": (245, 249, 255),   # 白（机鼻）
        "Y": (255, 230, 0),     # 黄（引擎喷口）
        "K": (42, 48, 58),      # 近黑
    },
    "enemy": {
        "EG": (106, 116, 136),  # 主体金属灰
        "ER": (255, 42, 109),   # 品红——阵营色 / 发光件
        "ED": (172, 46, 78),    # 暗红装甲
        "ET": (58, 66, 84),     # 暗钢（结构 / 骨架）
        "EH": (150, 158, 178),  # 亮钢（顶面 / 舷缘）
        "EL": (190, 198, 214),  # 高光边
        "EK": (34, 38, 48),     # 近黑（缝隙 / 进气口 / 炮口）
        "EC": (255, 176, 200),  # 浅粉（能量 / 座舱玻璃）
        "ES": (196, 166, 96),   # 黄铜 / 金
        "EW": (232, 238, 248),  # 白（机鼻 / 识别带）
        "EY": (255, 208, 80),   # 引擎黄
        "EO": (255, 130, 50),   # 排气橙
    },
}

# 量级带（§9.6 实测：assets/vox/units/ 主体资产），越带只警告不拦截。
BAND = {"width": (11, 21), "length": (5, 29), "voxels": (150, 3000)}

SOLID_OPS = ("box", "symbox", "oct", "profile", "dots")
PAINT_OPS = ("paint",)
ALL_OPS = SOLID_OPS + PAINT_OPS


class SpecError(Exception):
    """spec 语法 / 语义错误：拒绝编译。"""


# ---------------------------------------------------------------- 小工具

def _rng(v, what):
    """区间参数 [a,b] / [a] / a → range(a, b+1)。闭区间，与 gen_units 一致。"""
    if isinstance(v, int):
        lo = hi = v
    elif isinstance(v, list) and 1 <= len(v) <= 2 and all(isinstance(i, int) for i in v):
        lo = v[0]
        hi = v[-1]
    else:
        raise SpecError("%s 应为 int / [a] / [a,b]，收到 %r" % (what, v))
    if hi < lo:
        raise SpecError("%s 区间 [%d,%d] 上界小于下界" % (what, lo, hi))
    return range(lo, hi + 1)


def _col(name, palette):
    if name not in palette:
        raise SpecError("颜色 %r 不在引用的调色板中（可用：%s）"
                        % (name, " ".join(sorted(palette))))
    return palette[name]


def _load_spec(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    for key in ("name", "category", "palettes", "axis", "parts"):
        if key not in spec:
            raise SpecError("spec 缺少顶层字段 %r" % key)
    if spec["category"] not in ("air", "ground"):
        raise SpecError("category 只能是 air / ground，收到 %r" % spec["category"])
    palette = {}
    for p in spec["palettes"]:
        if p not in PALETTES:
            raise SpecError("未知调色板 %r（可用：%s）" % (p, " ".join(sorted(PALETTES))))
        palette.update(PALETTES[p])
    spec.setdefault("facing", "+Y" if spec["category"] == "air" else "-Y")
    default_facing = "+Y" if spec["category"] == "air" else "-Y"
    if spec["facing"] not in ("+Y", "-Y", "none"):
        raise SpecError("facing 只能是 +Y / -Y / none")
    # 玩家机（player 调色板）机头朝 -Y（背向屏幕下方）是合法的；
    # 敌机机头必须 +Y 迎向玩家，否则俯视读感错误。
    if (spec["category"] == "air" and spec["facing"] == "-Y"
            and "enemy" in spec["palettes"]):
        raise SpecError("敌机（enemy 调色板）机头须朝 +Y 迎向玩家")
    if not spec["parts"]:
        raise SpecError("parts 为空")
    return spec, palette


# ---------------------------------------------------------------- op 展开

def _oct_cells(cx, cy, r, cut):
    """八边形（切角方形）内格集合，条件与 gen_units._oct_skip 一致。"""
    cells = set()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if max(abs(dx), abs(dy)) <= r and abs(dx) + abs(dy) <= r + cut:
                cells.add((cx + dx, cy + dy))
    return cells


def _op_symbox(v, c, op, palette):
    col = _col(op["col"], palette)
    for x in _rng(op["x"], "x"):
        for y in _rng(op["y"], "y"):
            for z in _rng(op["z"], "z"):
                v[(x, y, z)] = col
                mx = 2 * c - x
                if mx != x:
                    v[(mx, y, z)] = col


def _op_box(v, c, op, palette):
    col = _col(op["col"], palette)
    for x in _rng(op["x"], "x"):
        for y in _rng(op["y"], "y"):
            for z in _rng(op["z"], "z"):
                v[(x, y, z)] = col


def _op_oct(v, c, op, palette):
    col = _col(op["col"], palette)
    cells = _oct_cells(op["cx"], op["cy"], op["r"], op["cut"])
    # edge：可选外缘换色。mode=ring → oct(r,cut)-oct(r-1,cut) 外一圈；
    #       mode=cheb → 仅切比雪夫半径 == r 的一圈。默认 ring。
    edge_col = None
    edge_cells = set()
    if "edge" in op:
        e = op["edge"]
        edge_col = _col(e["col"], palette)
        mode = e.get("mode", "ring")
        inner = _oct_cells(op["cx"], op["cy"], op["r"] - 1, op["cut"])
        for (x, y) in cells:
            if mode == "ring":
                if (x, y) not in inner:
                    edge_cells.add((x, y))
            elif mode == "cheb":
                if max(abs(x - op["cx"]), abs(y - op["cy"])) == op["r"]:
                    edge_cells.add((x, y))
            else:
                raise SpecError("oct.edge.mode 只能是 ring / cheb，收到 %r" % mode)
    for z in _rng(op["z"], "z"):
        for (x, y) in cells:
            v[(x, y, z)] = edge_col if (x, y) in edge_cells else col


def _op_profile(v, c, op, palette):
    """剖面拉伸：沿 y 逐行按 half 表铺 z 层。

    参数：y [a,b]、half（行半宽表，长度须等于行数）、x0（起始 dx，默认 0）、
    z（{"层号": "色名"}，键为 int）、edge（可选 {"z":[层..], "within":n, "col":色}，
    每行外侧 n 格的指定层换色——表达「翼尖红」这类相对条件，模型不必算术）。
    """
    ys = _rng(op["y"], "y")
    half = op["half"]
    if not isinstance(half, list) or len(half) != len(ys) or not all(
            isinstance(h, int) and h >= 0 for h in half):
        raise SpecError("profile.half 须为与 y 行数等长的非负整数表")
    x0 = op.get("x0", 0)
    layers = {}
    for zs, name in op["z"].items():
        try:
            zi = int(zs)
        except ValueError:
            raise SpecError("profile.z 的层号须为整数字符串，收到 %r" % zs)
        layers[zi] = _col(name, palette)
    edge = None
    if "edge" in op:
        e = op["edge"]
        edge = ([int(z) for z in e["z"]], e["within"],
                _col(e["col"], palette))
    for i, y in enumerate(ys):
        h = half[i]
        for dx in range(x0, h + 1):
            x = c + dx
            for zi, col in layers.items():
                if edge and zi in edge[0] and dx > h - edge[1]:
                    v[(x, y, zi)] = edge[2]
                else:
                    v[(x, y, zi)] = col
            mx = 2 * c - x
            if mx != x:
                for zi, col in layers.items():
                    if edge and zi in edge[0] and dx > h - edge[1]:
                        v[(mx, y, zi)] = edge[2]
                    else:
                        v[(mx, y, zi)] = col


def _op_dots(v, c, op, palette):
    col = _col(op["col"], palette)
    for pt in op["pts"]:
        if not (isinstance(pt, list) and len(pt) == 3):
            raise SpecError("dots.pts 的每项须为 [x,y,z]，收到 %r" % (pt,))
        x, y, z = pt
        v[(x, y, z)] = col
        if op.get("mirror", False):
            mx = 2 * c - x
            if mx != x:
                v[(mx, y, z)] = col


def _op_paint(v, c, op, palette):
    """只改已存在体素的颜色，不新增——覆盖涂色不会长出新块。"""
    col = _col(op["col"], palette)
    sel = op["sel"]
    keys = set(sel.keys())
    if keys == {"box"}:
        pts = {(x, y, z)
               for x in _rng(sel["box"]["x"], "paint.x")
               for y in _rng(sel["box"]["y"], "paint.y")
               for z in _rng(sel["box"]["z"], "paint.z")}
    elif keys == {"pts"}:
        pts = {(p[0], p[1], p[2]) for p in sel["pts"]}
    else:
        raise SpecError("paint.sel 须为 {\"box\":...} 或 {\"pts\":[...]}，收到 %s" % sorted(keys))
    if op.get("mirror", False):
        extra = {(2 * c - x, y, z) for (x, y, z) in pts}
        pts |= extra
    for p in pts:
        if p in v:
            v[p] = col


_OP_IMPL = {"box": _op_box, "symbox": _op_symbox, "oct": _op_oct,
            "profile": _op_profile, "dots": _op_dots, "paint": _op_paint}


def compile_part(ops, c, palette):
    v = {}
    for i, op in enumerate(ops):
        if not isinstance(op, dict) or "op" not in op:
            raise SpecError("第 %d 个 op 不是对象或缺 \"op\" 字段" % i)
        name = op["op"]
        if name not in ALL_OPS:
            raise SpecError(
                "op %r 不在集合中（%s）。v1 无随机 op；表达不了的造型"
                "应扩展 op 或用 dots 枚举，不要往 spec 里塞代码" % (name, " ".join(ALL_OPS)))
        _OP_IMPL[name](v, c, op, palette)
    return v


# ---------------------------------------------------------------- 校验

def _flood_main_ratio(v):
    """6 连通最大分量占比 + 漂浮块坐标（最多 10 个）。"""
    if not v:
        return 0.0, []
    seen = set()
    best = 0
    best_cells = None
    for start in v:
        if start in seen:
            continue
        stack = [start]
        comp = []
        seen.add(start)
        while stack:
            x, y, z = stack.pop()
            comp.append((x, y, z))
            for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                n = (x + d[0], y + d[1], z + d[2])
                if n in v and n not in seen:
                    seen.add(n)
                    stack.append(n)
        if len(comp) > best:
            best, best_cells = len(comp), set(comp)
    floating = [k for k in v if k not in best_cells]
    return best / len(v), sorted(floating)[:10]


def check_part(name, v, c):
    """返回 warnings 列表（致命问题直接 raise SpecError）。"""
    warns = []
    if not v:
        raise SpecError("[%s] 编译结果为空" % name)

    # 左右对称：逐 (y,z) 行比对 x 与 2c-x 颜色。
    bad = [(x, y, z) for (x, y, z) in v if v.get((2 * c - x, y, z)) != v[(x, y, z)]]
    if bad:
        sample = ", ".join("(%d,%d,%d)" % b for b in sorted(bad)[:5])
        raise SpecError("[%s] 左右不对称（共 %d 处，如 %s）；用 sym 系 op 或补镜像"
                        % (name, len(bad), sample))

    # 连通性：主分量应覆盖 ≥99%。
    ratio, floating = _flood_main_ratio(v)
    if ratio < 0.99:
        warns.append("[%s] 主连通分量仅 %.1f%%；漂浮块示例 %s"
                     % (name, ratio * 100, ", ".join("(%d,%d,%d)" % f for f in floating)))

    # 量级带（越带警告，不拦截）。
    xs, ys, zs = zip(*v.keys())
    w, l, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1, max(zs) - min(zs) + 1
    if not (BAND["width"][0] <= w <= BAND["width"][1]):
        warns.append("[%s] 宽 %d 超出实测带 %s（正交 34 相机下可能认不出/过大）"
                     % (name, w, BAND["width"]))
    if not (BAND["length"][0] <= l <= BAND["length"][1]):
        warns.append("[%s] 长 %d 超出实测带 %s" % (name, l, BAND["length"]))
    if not (BAND["voxels"][0] <= len(v) <= BAND["voxels"][1]):
        warns.append("[%s] 体素数 %d 超出实测带 %s" % (name, len(v), BAND["voxels"]))
    return warns


# ---------------------------------------------------------------- 构建 / 比对

def compile_spec(spec_path):
    spec, palette = _load_spec(spec_path)
    parts = []
    for part in spec["parts"]:
        if "file" not in part or "ops" not in part:
            raise SpecError("part 缺 file / ops 字段")
        # part 可用自己的 axis（独立坐标系的多部件，如旋翼层）
        c = part.get("axis", spec["axis"])
        v = compile_part(part["ops"], c, palette)
        warns = check_part(part["file"], v, c)
        parts.append({"file": part["file"], "voxels": v, "warnings": warns,
                       "assembly": tuple(part.get("assembly", (0, 0, 0)))})
    return spec, parts


def build(spec_path, out_dir, preview=False, cell=4):
    spec, parts = compile_spec(spec_path)
    made = []
    prev_dir = os.path.dirname(os.path.abspath(__file__))
    for part in parts:
        out = os.path.join(out_dir, part["file"])
        # 排序后落盘：同 spec 字节级可复现（XYZI 顺序与 gen_units 产物不同，
        # 但体素集合一致——游戏与导入插件均按集合读取，顺序无功能影响）。
        ordered = {k: part["voxels"][k] for k in sorted(part["voxels"])}
        info = voxlib.write_vox(out, ordered)
        png = None
        if preview:
            png = voxlib.render_iso(
                part["voxels"],
                os.path.join(prev_dir, "_spec_preview_" + os.path.splitext(part["file"])[0] + ".png"),
                cell=cell, up_axis="z")
        made.append((out, info, png))
    return spec, parts, made


def verify(spec_path, ref_path):
    """零回归闸门 / 漂移检测：按 (x,y,z)→(r,g,b) 比对，不比调色板索引。"""
    spec, parts = compile_spec(spec_path)
    ref = voxlib.vox_to_colors(ref_path)
    # 参考文件可能整体平移过（write_vox 以包围盒 min 归一化）——对齐包围盒后再比。
    def _norm(vox):
        xs, ys, zs = zip(*vox.keys())
        ox, oy, oz = min(xs), min(ys), min(zs)
        return {(x - ox, y - oy, z - oz): rgb for (x, y, z), rgb in vox.items()}

    ok_all = True
    for part in parts:
        mine, theirs = _norm(part["voxels"]), _norm(ref)
        if part["file"] != os.path.basename(ref_path):
            continue
        missing = sorted(set(theirs) - set(mine))
        extra = sorted(set(mine) - set(theirs))
        diffc = sorted(k for k in set(mine) & set(theirs) if mine[k] != theirs[k])
        if missing or extra or diffc:
            ok_all = False
            for tag, lst in (("缺失", missing), ("多余", extra), ("色异", diffc)):
                if lst:
                    print("  %s %d 处，如 %s" % (tag, len(lst),
                          ", ".join("(%d,%d,%d) %s≠%s" % (k + (mine.get(k), theirs.get(k)))
                                    if tag == "色异" else "(%d,%d,%d)" % k
                                    for k in lst[:6])))
        else:
            print("  PASS：%s 与参考逐体素一致（%d 体素）" % (part["file"], len(mine)))
    return ok_all


# ---------------------------------------------------------------- CLI

def _default_out():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..",
                                        "assets", "vox", "units"))


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "build", "verify"):
        print(__doc__)
        return 2
    cmd, spec_path = argv[1], argv[2]
    if cmd == "check":
        spec, parts = compile_spec(spec_path)
        _report(spec, parts)
        return 0
    if cmd == "build":
        out = _default_out()
        if "--out" in argv:
            out = argv[argv.index("--out") + 1]
        os.makedirs(out, exist_ok=True)
        spec, parts, made = build(spec_path, out, preview=True)
        _report(spec, parts)
        for out_path, info, png in made:
            print("write: %s size=%s voxels=%d colors=%d preview=%s"
                  % (out_path, info["size"], info["voxels"], info["colors"], png))
        return 0
    if cmd == "verify":
        if "--ref" not in argv:
            print("verify 需要 --ref <参考.vox>")
            return 2
        return 0 if verify(spec_path, argv[argv.index("--ref") + 1]) else 1
    return 2


def _report(spec, parts):
    print("spec %s：category=%s facing=%s axis=%d" % (spec["name"], spec["category"],
                                                      spec["facing"], spec["axis"]))
    for part in parts:
        xs, ys, zs = zip(*part["voxels"].keys())
        print("  part %-10s bbox=%d×%d×%d voxels=%d"
              % (part["file"], max(xs) - min(xs) + 1, max(ys) - min(ys) + 1,
                 max(zs) - min(zs) + 1, len(part["voxels"])))
        for w in part["warnings"]:
            print("    WARN: %s" % w)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
