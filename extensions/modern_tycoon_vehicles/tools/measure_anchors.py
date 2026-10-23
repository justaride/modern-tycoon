"""Measure train sprite anchors from a base-set GRF (reference facts only).

Reads only sprite headers (width, height, x/y offset) of the default
8-direction train sprites, so our own sprites line up with track the same
way the base set does. No pixel data is read or copied.

Usage: measure_anchors.py path/to/ogfx1_base.grf [first_sprite=0x0BB1]

SPDX-License-Identifier: GPL-2.0-only
"""
import struct
import sys


def read_headers(path):
    b = open(path, 'rb').read()
    if b[:10] != b'\x00\x00GRF\x82\x0d\x0a\x1a\x0a':
        raise SystemExit('not a container v2 GRF')
    sprite_section = struct.unpack_from('<I', b, 10)[0] + 14
    pos, entries = 15, []
    while True:
        size = struct.unpack_from('<I', b, pos)[0]
        pos += 4
        if size == 0:
            break
        typ = b[pos]
        entries.append(struct.unpack_from('<I', b, pos + 1)[0] if typ == 0xFD else None)
        pos += 1 + size
    pos, info = sprite_section, {}
    while True:
        sid = struct.unpack_from('<I', b, pos)[0]
        pos += 4
        if sid == 0:
            break
        size = struct.unpack_from('<I', b, pos)[0]
        pos += 4
        typ, zoom, h, w, xo, yo = struct.unpack_from('<BBHHhh', b, pos)
        if zoom == 0 and typ & 0x04:
            info.setdefault(sid, (w, h, xo, yo))
        pos += size
    return entries, info


if __name__ == '__main__':
    entries, info = read_headers(sys.argv[1])
    first = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x0BB1
    names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
    for d in range(8):
        w, h, xo, yo = info[entries[first + d]]  # OpenTTD counts the header entry as sprite 0
        print(f"{names[d]:>2}: w={w} h={h} xoff={xo} yoff={yo}  centre_x={xo + w / 2} bottom={yo + h}")
