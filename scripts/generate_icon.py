#!/usr/bin/env python3
"""
VoiceTyper App Icon Generator
Generates high-resolution macOS squircle AppIcon with neon gradient, microphone glyph, and soundwave EQ bars.
Outputs standard Apple .icns format without external dependencies (pure Python standard library).
"""

import math
import os
import struct
import sys
import zlib

def clamp(v):
    return max(0, min(255, int(v)))

def create_png(width, height, draw_fn):
    raw_bytes = bytearray()
    for y in range(height):
        raw_bytes.append(0)  # Filter byte: None
        for x in range(width):
            r, g, b, a = draw_fn(x, y, width, height)
            raw_bytes.extend((clamp(r), clamp(g), clamp(b), clamp(a)))

    def make_chunk(chunk_type, data):
        c = chunk_type + data
        crc = zlib.crc32(c) & 0xFFFFFFFF
        return struct.pack('>I', len(data)) + c + struct.pack('>I', crc)

    png = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    png += make_chunk(b'IHDR', ihdr_data)
    idat_data = zlib.compress(bytes(raw_bytes), 9)
    png += make_chunk(b'IDAT', idat_data)
    png += make_chunk(b'IEND', b'')
    return png

def draw_icon(x, y, w, h):
    nx = (x + 0.5) / w * 2.0 - 1.0
    ny = (y + 0.5) / h * 2.0 - 1.0

    # macOS superellipse / squircle distance (|x|^4.5 + |y|^4.5)^(1/4.5)
    p = 4.5
    dist = (abs(nx) ** p + abs(ny) ** p) ** (1.0 / p)

    if dist > 0.92:
        # Anti-aliased outer edge
        edge = (dist - 0.92) / (0.96 - 0.92)
        if edge >= 1.0:
            return (0, 0, 0, 0)
        alpha = int((1.0 - edge) * 255)
        return (15, 23, 42, alpha // 3)

    # Gradient background: Obsidian dark slate (#0F172A) to deep purple/cyan (#3B0764)
    t = (ny + 1.0) / 2.0
    r = int(15 * (1 - t) + 40 * t)
    g = int(23 * (1 - t) + 15 * t)
    b = int(42 * (1 - t) + 75 * t)

    # Subtle inner glow / border ring
    if dist > 0.86:
        factor = (dist - 0.86) / (0.92 - 0.86)
        r = int(r * (1 - factor) + 99 * factor)
        g = int(g * (1 - factor) + 102 * factor)
        b = int(b * (1 - factor) + 241 * factor)

    # Microphone capsule: centered at x=0, y from -0.35 to 0.05, radius 0.18
    in_mic = False
    if abs(nx) <= 0.18 and -0.35 <= ny <= 0.05:
        in_mic = True
    elif (nx ** 2 + (ny - (-0.35)) ** 2) <= 0.18 ** 2 and ny < -0.35:
        in_mic = True
    elif (nx ** 2 + (ny - 0.05) ** 2) <= 0.18 ** 2 and ny > 0.05:
        in_mic = True

    # Microphone cradle
    in_cradle = False
    cr_dist = math.sqrt(nx ** 2 + (ny - 0.05) ** 2)
    if 0.24 <= cr_dist <= 0.32 and ny >= 0.0:
        in_cradle = True

    # Stand base
    in_stand = False
    if abs(nx) <= 0.04 and 0.30 <= ny <= 0.45:
        in_stand = True
    if abs(nx) <= 0.22 and 0.45 <= ny <= 0.52:
        in_stand = True

    # Soundwave bars left & right
    in_wave = False
    if abs(nx - (-0.52)) <= 0.04 and abs(ny - 0.0) <= 0.18:
        in_wave = True
    if abs(nx - (-0.38)) <= 0.04 and abs(ny - 0.0) <= 0.30:
        in_wave = True
    if abs(nx - 0.38) <= 0.04 and abs(ny - 0.0) <= 0.30:
        in_wave = True
    if abs(nx - 0.52) <= 0.04 and abs(ny - 0.0) <= 0.18:
        in_wave = True

    if in_mic:
        mic_t = (ny + 0.5) / 0.7
        return (clamp(255 - 40 * mic_t), 255, 255, 255)
    elif in_cradle or in_stand:
        return (56, 189, 248, 255)
    elif in_wave:
        return (192, 132, 252, 255)

    return (r, g, b, 255)

def generate_icns(output_path):
    sizes = [
        (b'icp4', 16),
        (b'icp5', 32),
        (b'icp6', 64),
        (b'ic07', 128),
        (b'ic08', 256),
        (b'ic09', 512),
    ]

    chunks = bytearray()
    for chunk_type, sz in sizes:
        png = create_png(sz, sz, draw_icon)
        chunk_len = len(png) + 8
        chunks += chunk_type + struct.pack('>I', chunk_len) + png

    total_len = len(chunks) + 8
    icns_data = b'icns' + struct.pack('>I', total_len) + bytes(chunks)

    output_dir = os.path.dirname(os.path.abspath(output_path))
    os.makedirs(output_dir, exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(icns_data)

    png_path = os.path.join(output_dir, "AppIcon.png")
    png_preview = create_png(512, 512, draw_icon)
    with open(png_path, 'wb') as f:
        f.write(png_preview)

    print(f"✓ Generated {output_path} ({len(icns_data)} bytes)")
    print(f"✓ Generated {png_path} ({len(png_preview)} bytes)")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "Resources/AppIcon.icns"
    generate_icns(out)
