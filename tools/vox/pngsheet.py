"""把多张 PNG 拼成接触表（contact sheet），纯标准库实现（含 PNG 解码）。

没有 PIL 时用来人工核对渲染结果：把 N 张截图拼成一张，一次看完。
渲染产物由 tools/vox/asset_review.gd 生成。

用法：
    python pngsheet.py out.png 4 E1_play.png E2_play.png ...   # 每行 4 张
    python pngsheet.py out.png 4 --scale 0.7 a.png b.png ...
"""

import struct
import sys
import zlib

import voxlib


def read_png(path):
    """返回 (w, h, rgba: bytearray)。支持 8bit 灰度/RGB/RGBA，非隔行。"""
    d = open(path, "rb").read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("不是 PNG: %s" % path)
    p, idat = 8, []
    w = h = bd = ct = 0
    while p + 8 <= len(d):
        ln = struct.unpack(">I", d[p:p + 4])[0]
        tag = d[p + 4:p + 8]
        data = d[p + 8:p + 8 + ln]
        if tag == b"IHDR":
            w, h, bd, ct, _comp, _filt, inter = struct.unpack(">IIBBBBB", data)
            if bd != 8 or inter != 0:
                raise ValueError("仅支持 8bit 非隔行：%s (bd=%d inter=%d)" % (path, bd, inter))
        elif tag == b"IDAT":
            idat.append(data)
        elif tag == b"IEND":
            break
        p += 12 + ln

    raw = zlib.decompress(b"".join(idat))
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ct]
    stride = w * ch
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        o = y * w * 4
        if ch == 4:
            out[o:o + w * 4] = line
        elif ch == 3:
            for x in range(w):
                out[o + x * 4:o + x * 4 + 3] = line[x * 3:x * 3 + 3]
                out[o + x * 4 + 3] = 255
        elif ch == 1:
            for x in range(w):
                v = line[x]
                out[o + x * 4:o + x * 4 + 4] = bytes((v, v, v, 255))
        prev = line
    return w, h, out


def make_sheet(paths, out_path, cols=4, scale=1.0, gap=4, bg=(12, 13, 18)):
    tiles = [read_png(p) for p in paths]
    tw = max(t[0] for t in tiles)
    th = max(t[1] for t in tiles)
    cw = max(1, int(tw * scale))
    chh = max(1, int(th * scale))
    rows = (len(tiles) + cols - 1) // cols
    W = cols * cw + (cols + 1) * gap
    H = rows * chh + (rows + 1) * gap
    sheet = bytearray(bytes(bg) * (W * H))

    for i, (w, h, px) in enumerate(tiles):
        cx = gap + (i % cols) * (cw + gap)
        cy = gap + (i // cols) * (chh + gap)
        for y in range(chh):
            sy = min(h - 1, int(y / scale))
            for x in range(cw):
                sx = min(w - 1, int(x / scale))
                si = (sy * w + sx) * 4
                di = ((cy + y) * W + cx + x) * 3
                sheet[di] = px[si]
                sheet[di + 1] = px[si + 1]
                sheet[di + 2] = px[si + 2]
    voxlib.write_png(out_path, W, H, sheet)
    return (W, H)


if __name__ == "__main__":
    out = sys.argv[1]
    cols = int(sys.argv[2])
    args = sys.argv[3:]
    scale = 1.0
    if args and args[0] == "--scale":
        scale = float(args[1])
        args = args[2:]
    print(make_sheet(args, out, cols=cols, scale=scale))
