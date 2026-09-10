"""MagicaVoxel .vox 读写库（纯标准库，无第三方依赖）。

用途：绕开 MagicaVoxel 的 GUI，用代码直接生成 / 修改体素场景，
      并用等距投影渲染 PNG 预览图，方便在没有 GUI 的环境里自检结果。

.vox 格式（ephtracy 公开规范，RIFF 风格）：
    "VOX " + int32 version(150)
    MAIN chunk
      ├ SIZE  : int32 x, y, z                      模型尺寸
      ├ XYZI  : int32 numVoxels + (x,y,z,colorIdx)* 体素（colorIdx 1..255）
      ├ RGBA  : 256 * (r,g,b,a)                    调色板，第 k 项对应索引 k+1
      └ nTRN / nGRP / nSHP                         场景图（平移 / 组 / 模型引用）

坐标系：MagicaVoxel 是 Z-up，Godot 是 Y-up，转换 godot(x, y, z) = vox(x, z, y)。
"""

import struct
import zlib


# ---------------------------------------------------------------- 读取

def _u32(b, p):
    return struct.unpack_from("<I", b, p)[0]


def _i32(b, p):
    return struct.unpack_from("<i", b, p)[0]


def _chunk(b, p):
    return {
        "id": b[p:p + 4],
        "content": p + 12,
        "cs": _u32(b, p + 4),
        "children": p + 12 + _u32(b, p + 4),
        "chs": _u32(b, p + 8),
        "next": p + 12 + _u32(b, p + 4) + _u32(b, p + 8),
    }


def _read_dict(b, p):
    n = _i32(b, p)
    p += 4
    d = {}
    for _ in range(n):
        kl = _i32(b, p)
        p += 4
        k = b[p:p + kl].decode("utf8", "replace")
        p += kl
        vl = _i32(b, p)
        p += 4
        v = b[p:p + vl].decode("utf8", "replace")
        p += vl
        d[k] = v
    return d, p


def _rotation_matrix(r):
    """把 nTRN 的 _r 字节解码成 3x3 行主序矩阵（约定见 vox 规范）。"""
    i1, i2 = r & 3, (r >> 2) & 3
    s1 = -1 if (r & 16) else 1
    s2 = -1 if (r & 32) else 1
    row0 = [0, 0, 0]
    row1 = [0, 0, 0]
    row0[i1] = s1
    row1[i2] = s2
    row2 = [
        row0[1] * row1[2] - row0[2] * row1[1],
        row0[2] * row1[0] - row0[0] * row1[2],
        row0[0] * row1[1] - row0[1] * row1[0],
    ]
    return [row0, row1, row2]


def read_vox(path):
    """读 .vox，返回 {"models": [{"size":(x,y,z), "voxels":[(x,y,z,ci)]}],
    "palette": [(r,g,b,a) x256], "instances": [(model_idx, (tx,ty,tz), rot|None)]}"""
    with open(path, "rb") as f:
        b = f.read()
    if b[:4] != b"VOX ":
        raise ValueError("不是合法的 .vox 文件: %s" % path)

    models, palette = [], None
    trn, grp, shp = {}, {}, {}

    main = _chunk(b, 8)
    p, end = main["children"], main["children"] + main["chs"]
    cur_size = (0, 0, 0)
    while p + 12 <= end:
        c = _chunk(b, p)
        cs, cid = c["content"], c["id"]
        if cid == b"SIZE":
            cur_size = (_u32(b, cs), _u32(b, cs + 4), _u32(b, cs + 8))
        elif cid == b"XYZI":
            nv = _u32(b, cs)
            vs = [tuple(b[cs + 4 + i * 4: cs + 8 + i * 4]) for i in range(nv)]
            models.append({"size": cur_size, "voxels": vs})
        elif cid == b"RGBA":
            palette = [tuple(b[cs + i * 4: cs + i * 4 + 4]) for i in range(256)]
        elif cid == b"nTRN":
            nid = _i32(b, cs)
            _, q = _read_dict(b, cs + 4)
            child = _i32(b, q)
            q += 12  # child + reserved + layer
            nframes = _i32(b, q)
            q += 4
            t, rot = (0, 0, 0), None
            if nframes > 0:
                d, _ = _read_dict(b, q)
                if "_t" in d:
                    t = tuple(int(v) for v in d["_t"].split())
                if "_r" in d:
                    rot = d["_r"].encode("latin1")[0]
            trn[nid] = {"child": child, "t": t, "r": rot}
        elif cid == b"nGRP":
            nid = _i32(b, cs)
            _, q = _read_dict(b, cs + 4)
            n = _i32(b, q)
            q += 4
            grp[nid] = [_i32(b, q + 4 * i) for i in range(n)]
        elif cid == b"nSHP":
            nid = _i32(b, cs)
            _, q = _read_dict(b, cs + 4)
            n = _i32(b, q)
            q += 4
            ms = []
            for _ in range(n):
                mid = _i32(b, q)
                q += 4
                _, q = _read_dict(b, q)
                ms.append(mid)
            shp[nid] = ms
        p = c["next"]

    instances = []

    def walk(nid, acc):
        if nid in trn:
            n = trn[nid]
            if n["r"] is None:
                walk(n["child"], (acc[0] + n["t"][0], acc[1] + n["t"][1], acc[2] + n["t"][2]))
            else:
                # 有旋转时子节点坐标需先旋转（此处仅记录，调用方按需处理）
                walk(n["child"], (acc[0] + n["t"][0], acc[1] + n["t"][1], acc[2] + n["t"][2]))
        elif nid in grp:
            for k in grp[nid]:
                walk(k, acc)
        elif nid in shp:
            for mid in shp[nid]:
                instances.append((mid, acc))

    root = 0
    if root in trn or root in grp or root in shp:
        walk(root, (0, 0, 0))
    else:
        instances = [(i, (0, 0, 0)) for i in range(len(models))]

    return {"models": models, "palette": palette, "instances": instances, "trn": trn}


def vox_to_colors(path):
    """把 .vox 展平成 {(x,y,z): (r,g,b)}（MagicaVoxel 原始 Z-up 坐标）。"""
    d = read_vox(path)
    pal = d["palette"] or [(0, 0, 0, 255)] * 256
    out = {}
    for mid, t in d["instances"]:
        if mid >= len(d["models"]):
            continue
        for (x, y, z, ci) in d["models"][mid]["voxels"]:
            c = pal[ci - 1] if 0 < ci <= 255 else (255, 0, 255, 255)
            out[(x + t[0], y + t[1], z + t[2])] = (c[0], c[1], c[2])
    return out


# ---------------------------------------------------------------- 写入

def _mk(chunk_id, content, children=b""):
    return (chunk_id
            + struct.pack("<II", len(content), len(children))
            + content + children)


def _dict_bytes(pairs):
    out = struct.pack("<i", len(pairs))
    for k, v in pairs:
        kb, vb = k.encode("ascii"), v.encode("ascii")
        out += struct.pack("<i", len(kb)) + kb + struct.pack("<i", len(vb)) + vb
    return out


def _trn(node_id, child, t=(0, 0, 0), layer=0):
    """nTRN：与 MagicaVoxel 0.99 完全一致的布局（Godot 导入插件依赖它）"""
    return _mk(b"nTRN", struct.pack("<iiiiii", node_id, 0, child, -1, layer, 1)
               + _dict_bytes([("_t", "%d %d %d" % t)]))


def _grp(node_id, children):
    return _mk(b"nGRP", struct.pack("<ii", node_id, 0)
               + struct.pack("<i", len(children))
               + b"".join(struct.pack("<i", c) for c in children))


def _shp(node_id, model_ids):
    out = struct.pack("<ii", node_id, 0) + struct.pack("<i", len(model_ids))
    for mid in model_ids:
        out += struct.pack("<i", mid) + _dict_bytes([])
    return _mk(b"nSHP", out)


def _scene_graph():
    """根 nTRN(0) → nGRP(1) → nTRN(2) → nSHP(3)，与官方样例字节结构一致"""
    root = _mk(b"nTRN", bytes.fromhex("000000000000000001000000ffffffffffffffff01000000")
               + _dict_bytes([]))
    return root + _grp(1, [2]) + _trn(2, 3) + _shp(3, [0])


def write_vox(path, voxels, size=None):
    """voxels: {(x,y,z): (r,g,b)} → 写入 .vox。自动构建调色板（最多 255 色）。
    默认附带标准场景图节点（nTRN/nGRP/nSHP），否则 Godot 的导入插件会解析失败。"""
    if not voxels:
        raise ValueError("空体素集")
    if size is None:
        xs, ys, zs = zip(*voxels.keys())
        ox, oy, oz = min(xs), min(ys), min(zs)
        size = (max(xs) - ox + 1, max(ys) - oy + 1, max(zs) - oz + 1)
    else:
        ox, oy, oz = 0, 0, 0

    colors = sorted({v for v in voxels.values()})
    if len(colors) > 255:
        raise ValueError("颜色数 %d 超过 255，请减少调色板" % len(colors))
    index = {c: i + 1 for i, c in enumerate(colors)}

    sx, sy, sz = size
    body = _mk(b"SIZE", struct.pack("<III", sx, sy, sz))
    raw = bytearray()
    n = 0
    for (x, y, z), c in voxels.items():
        px, py, pz = x - ox, y - oy, z - oz
        if 0 <= px < sx and 0 <= py < sy and 0 <= pz < sz:
            raw += bytes((px, py, pz, index[c]))
            n += 1
    body += _mk(b"XYZI", struct.pack("<I", n) + bytes(raw))

    pal = bytearray(256 * 4)
    for c, i in index.items():
        pal[(i - 1) * 4: i * 4] = bytes((c[0], c[1], c[2], 255))
    body += _mk(b"RGBA", bytes(pal))
    body += _scene_graph()

    data = b"VOX " + struct.pack("<I", 150) + _mk(b"MAIN", b"", body)
    with open(path, "wb") as f:
        f.write(data)
    return {"size": size, "voxels": n, "colors": len(colors)}


# ---------------------------------------------------------------- 预览渲染

def write_png(path, w, h, buf):
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw += buf[y * stride:(y + 1) * stride]

    def ck(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += ck(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += ck(b"IDAT", zlib.compress(bytes(raw), 6))
    png += ck(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def _fill_tri(buf, w, h, tri, rgb):
    (x0, y0), (x1, y1), (x2, y2) = tri
    minx, maxx = int(max(0, min(x0, x1, x2))), int(min(w - 1, max(x0, x1, x2)))
    miny, maxy = int(max(0, min(y0, y1, y2))), int(min(h - 1, max(y0, y1, y2)))
    if minx > maxx or miny > maxy:
        return
    d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    if d == 0:
        return
    r, g, bl = rgb
    for py in range(miny, maxy + 1):
        base = py * w * 3
        for px in range(minx, maxx + 1):
            l1 = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / d
            l2 = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / d
            l3 = 1.0 - l1 - l2
            if l1 >= 0 and l2 >= 0 and l3 >= 0:
                i = base + px * 3
                buf[i] = r
                buf[i + 1] = g
                buf[i + 2] = bl


def render_iso(voxels, out_png, cell=4, margin=12, bg=(16, 17, 22), up_axis="z"):
    """2:1 等距投影渲染（画家算法，自下而上 + 由远及近），输出 PNG。
    up_axis="z"：输入为 MagicaVoxel 原生坐标（Z 朝上）；
    up_axis="y"：输入已是 Godot 坐标（Y 朝上）。"""
    if not voxels:
        raise ValueError("无体素可渲染")
    if up_axis == "z":
        voxels = {(x, z, y): c for (x, y, z), c in voxels.items()}
    W, H = cell * 2, cell
    pts = []
    for (x, y, z) in voxels:
        pts.append(((x - z) * W, (x + z) * H - y * 2 * H))
    minx = min(p[0] for p in pts) - W
    maxx = max(p[0] for p in pts) + W
    miny = min(p[1] for p in pts) - 2 * H
    maxy = max(p[1] for p in pts) + 2 * H

    w = int(maxx - minx) + margin * 2
    h = int(maxy - miny) + margin * 2
    buf = bytearray(bytes(bg) * (w * h))

    def proj(px, py, pz):
        return ((px - pz) * W - minx + margin, (px + pz) * H - py * 2 * H - miny + margin)

    shade = {"top": 1.0, "px": 0.76, "pz": 0.55}
    order = sorted(voxels.keys(), key=lambda k: (k[1], k[0] + k[2], k[0]))
    for (x, y, z) in order:
        c = voxels[(x, y, z)]
        faces = [
            (shade["top"], [(x, y + 1, z), (x + 1, y + 1, z), (x + 1, y + 1, z + 1), (x, y + 1, z + 1)]),
            (shade["px"], [(x + 1, y, z), (x + 1, y + 1, z), (x + 1, y + 1, z + 1), (x + 1, y, z + 1)]),
            (shade["pz"], [(x, y, z + 1), (x + 1, y, z + 1), (x + 1, y + 1, z + 1), (x, y + 1, z + 1)]),
        ]
        for s, quad in faces:
            rgb = (int(c[0] * s), int(c[1] * s), int(c[2] * s))
            q = [proj(*p) for p in quad]
            _fill_tri(buf, w, h, (q[0], q[1], q[2]), rgb)
            _fill_tri(buf, w, h, (q[0], q[2], q[3]), rgb)
    write_png(out_png, w, h, buf)
    return (w, h)


# ---------------------------------------------------------------- CLI

if __name__ == "__main__":
    import sys

    if len(sys.argv) >= 3 and sys.argv[1] == "inspect":
        d = read_vox(sys.argv[2])
        print("models   :", len(d["models"]))
        for i, m in enumerate(d["models"]):
            print("  #%d size=%s voxels=%d" % (i, m["size"], len(m["voxels"])))
        print("palette  :", "yes" if d["palette"] else "no")
        print("instances:", d["instances"])
        for nid, n in d["trn"].items():
            print("  nTRN %d -> child %d t=%s r=%s" % (nid, n["child"], n["t"], n["r"]))
