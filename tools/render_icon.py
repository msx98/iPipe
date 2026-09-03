#!/usr/bin/env python3
"""Rasterize the iPipe icon SVG into a PNG using only the standard library.

Renders the subset of SVG used by assets/icon.svg: a filled <rect> with
rounded corners (rx/ry) and filled <polygon>/<path> elements, each with an
optional fill colour (hex #RRGGBB/#RRGGBBAA or a handful of named colours).
Super-samples 2x2 per output pixel for anti-aliasing.

Usage: render_icon.py <input.svg> <output.png> [scale]
"""

import math
import re
import struct
import sys
import zlib


NAMED_COLORS = {
    "white": (255, 255, 255),
    "black": (0, 0, 0),
    "red": (229, 57, 53),
}

SVG_TAG = re.compile(r"<([a-z]+)\b([^>]*?)/?>", re.IGNORECASE)
ATTR = re.compile(r"([a-zA-Z:]+)\s*=\s*([\"'])(.*?)\2")


def parse_fill(value):
    value = (value or "").strip()
    if value.startswith("#"):
        hexv = value[1:]
        if len(hexv) in (3, 4):
            hexv = "".join(c * 2 for c in hexv)
        if len(hexv) == 6:
            return tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
        if len(hexv) == 8:
            return tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4, 6))
        raise ValueError(f"bad hex colour {value}")
    if value in NAMED_COLORS:
        return NAMED_COLORS[value] + (255,)
    raise ValueError(f"unsupported colour {value!r}")


def parse_points(value):
    return [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", value)]


def rgb_to_unit(rgb):
    return tuple(c / 255.0 for c in rgb)


class SVG:
    def __init__(self, source):
        self.width = 1024
        self.height = 1024
        self.shapes = []
        for match in SVG_TAG.finditer(source):
            tag = match.group(1).lower()
            attrs = dict(((k.lower(), v) for k, _, v in ATTR.findall(match.group(2))))
            if tag == "svg":
                self.width = float(attrs.get("width", 1024))
                self.height = float(attrs.get("height", 1024))
            elif tag in ("rect", "path", "polygon"):
                fill = attrs.get("fill") or attrs.get("fill-rule") or ""
                if not fill and tag == "rect":
                    fill = "black"
                self.shapes.append((tag, attrs, fill))
        if not self.shapes:
            raise ValueError("no rect/path/polygon elements found in SVG")


def sdf_rounded_box(x, y, cx, cy, hw, hh, r):
    qx = abs(x - cx) - (hw - r)
    qy = abs(y - cy) - (hh - r)
    ox, oy = max(qx, 0.0), max(qy, 0.0)
    outside = math.hypot(ox, oy)
    inside = min(max(qx, qy), 0.0)
    return outside + inside - r


def sdf_triangle(x, y, a, b, c):
    def dist_segment(p, u, v):
        l2 = (v[0] - u[0]) ** 2 + (v[1] - u[1]) ** 2
        t = max(min(((p[0] - u[0]) * (v[0] - u[0]) + (p[1] - u[1]) * (v[1] - u[1])) / l2, 1.0), 0.0) if l2 else 0.0
        px = u[0] + (v[0] - u[0]) * t
        py = u[1] + (v[1] - u[1]) * t
        return math.hypot(p[0] - px, p[1] - py)

    d = min(dist_segment((x, y), a, b), dist_segment((x, y), b, c), dist_segment((x, y), c, a))

    def cross(o, u, v):
        return (u[0] - o[0]) * (v[1] - o[1]) - (u[1] - o[1]) * (v[0] - o[0])

    c1 = cross(a, b, (x, y))
    c2 = cross(b, c, (x, y))
    c3 = cross(c, a, (x, y))
    inside = (c1 >= 0 and c2 >= 0 and c3 >= 0) or (c1 < 0 and c2 < 0 and c3 < 0)
    return -d if inside else d


def coverage(delta):
    return max(min(0.5 - delta, 1.0), 0.0)


def render(svg, scale=1.0):
    out_w = int(svg.width * scale)
    out_h = int(svg.height * scale)
    rows = []

    for y in range(out_h):
        row = bytearray()
        for x in range(out_w):
            ar = ag = ab = aa = 0.0
            for sy in (0, 1):
                for sx in (0, 1):
                    px = (x + (sx + 0.5) / 2.0) / scale
                    py = (y + (sy + 0.5) / 2.0) / scale
                    r = g = b = a = 0.0
                    for shape, attrs, fill in svg.shapes:
                        fill_unit = rgb_to_unit(parse_fill(fill))
                        cov = shape_coverage(shape, attrs, px, py)
                        if cov <= 0:
                            continue
                        fr, fg, fb, fa = fill_unit
                        sa = cov * fa
                        a = sa + a * (1.0 - sa)
                        r = fr * sa + r * (1.0 - sa)
                        g = fg * sa + g * (1.0 - sa)
                        b = fb * sa + b * (1.0 - sa)
                    if a > 0:
                        r /= a
                        g /= a
                        b /= a
                    ar += r
                    ag += g
                    ab += b
                    aa += a
            n = 4.0
            row += bytes((int(round(ar / n * 255)),
                          int(round(ag / n * 255)),
                          int(round(ab / n * 255)),
                          int(round(aa / n * 255))))
        rows.append(bytes(row))
    return out_w, out_h, rows


def shape_coverage(shape, attrs, x, y):
    if shape == "rect":
        w = float(attrs.get("width", 0))
        h = float(attrs.get("height", 0))
        rx = float(attrs.get("rx", attrs.get("ry", 0)))
        ry = float(attrs.get("ry", rx))
        cx = float(attrs.get("x", 0)) + w / 2
        cy = float(attrs.get("y", 0)) + h / 2
        d = sdf_rounded_box(x, y, cx, cy, w / 2, h / 2, min(rx, ry))
        return coverage(d)
    if shape == "polygon":
        pts = parse_points(attrs.get("points", ""))
        if len(pts) < 6:
            return 0.0
        p0 = (pts[0], pts[1])
        for i in range(2, len(pts) - 2, 2):
            d = sdf_triangle(x, y, p0, (pts[i], pts[i + 1]), (pts[i + 2], pts[i + 3]))
            if d < 0:
                return 1.0
        return 0.0
    return 0.0


def write_png(path, width, height, rows):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = b"".join(b"\x00" + row for row in rows)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", ihdr))
        fh.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        fh.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) not in (3, 4):
        sys.stderr.write(f"usage: {sys.argv[0]} <input.svg> <output.png> [scale]\n")
        return 1
    source = open(sys.argv[1], encoding="utf-8").read()
    svg = SVG(source)
    scale = float(sys.argv[3]) if len(sys.argv) == 4 else 1.0
    width, height, rows = render(svg, scale)
    write_png(sys.argv[2], width, height, rows)
    print(f"wrote {sys.argv[2]} ({width}x{height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())