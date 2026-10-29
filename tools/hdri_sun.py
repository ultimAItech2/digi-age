#!/usr/bin/env python3
"""Print the sun direction of a Radiance .hdr panorama (brightest region).

Usage: python3 -I tools/hdri_sun.py assets/third_party/processed/hdri/<name>.hdr
Prints azimuth (degrees, 0 = panorama centre, positive to the right) and
elevation (degrees above the horizon), plus the Godot DirectionalLight3D
rotation that points along the sun's rays for a PanoramaSkyMaterial.
"""
import math
import struct
import sys


def read_hdr(path):
    with open(path, "rb") as handle:
        data = handle.read()
    pos = data.index(b"\n\n") + 2
    line_end = data.index(b"\n", pos)
    header = data[pos:line_end].decode().split()
    height, width = int(header[1]), int(header[3])
    pos = line_end + 1
    pixels = []
    for _ in range(height):
        if data[pos] == 2 and data[pos + 1] == 2 and (data[pos + 2] << 8 | data[pos + 3]) == width:
            pos += 4
            row = [bytearray(width) for _ in range(4)]
            for channel in range(4):
                x = 0
                while x < width:
                    count = data[pos]
                    pos += 1
                    if count > 128:
                        count -= 128
                        value = data[pos]
                        pos += 1
                        row[channel][x:x + count] = bytes([value]) * count
                    else:
                        row[channel][x:x + count] = data[pos:pos + count]
                        pos += count
                    x += count
            pixels.append(row)
        else:
            raw = data[pos:pos + width * 4]
            pos += width * 4
            pixels.append([bytearray(raw[c::4]) for c in range(4)])
    return width, height, pixels


def luminance(r, g, b, e):
    if e == 0:
        return 0.0
    scale = math.ldexp(1.0, e - 136)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) * scale


def main():
    width, height, pixels = read_hdr(sys.argv[1])
    block = max(1, width // 256)
    best = (0.0, 0, 0)
    for y in range(0, height, block):
        row = pixels[y]
        for x in range(0, width, block):
            value = luminance(row[0][x], row[1][x], row[2][x], row[3][x])
            if value > best[0]:
                best = (value, x, y)
    u = best[1] / width
    v = best[2] / height
    azimuth = (u - 0.5) * 360.0
    elevation = (0.5 - v) * 180.0
    print("sun pixel u=%.4f v=%.4f  azimuth=%.1f  elevation=%.1f  luminance=%.1f" % (u, v, azimuth, elevation, best[0]))
    # Godot PanoramaSkyMaterial: u=0.5 faces -Z, u increases toward +X. A light with
    # rotation_degrees (-elevation, yaw, 0) shines along the sun's rays when yaw = 180 - azimuth.
    print("DirectionalLight3D rotation_degrees = Vector3(%.1f, %.1f, 0)" % (-elevation, 180.0 - azimuth))


main()
