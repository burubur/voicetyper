#!/usr/bin/env python3
"""
VoiceTyper App Icon Generator
Generates high-resolution macOS squircle AppIcon with pure minimalist microphone glyph (SF Symbol style).
Outputs standard Apple .icns and preview .png without external dependencies (pure Python standard library).
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
        return (10, 15, 30, alpha // 3)

    # Gradient background: Premium Deep Obsidian Slate (#0B1120) to Midnight Violet (#1E1138)
    t = (ny + 1.0) / 2.0
    bg_r = int(11 * (1 - t) + 30 * t)
    bg_g = int(17 * (1 - t) + 17 * t)
    bg_b = int(32 * (1 - t) + 56 * t)

    # Subtle inner bevel glow / border ring
    if dist > 0.85:
        factor = (dist - 0.85) / (0.92 - 0.85)
        bg_r = int(bg_r * (1 - factor) + 99 * factor)
        bg_g = int(bg_g * (1 - factor) + 102 * factor)
        bg_b = int(bg_b * (1 - factor) + 241 * factor)

    # Option 1: Native macOS Menu Bar SF Symbol (mic.fill)
    # 1. Central Capsule
    cap_top = -0.32
    cap_bot = 0.08
    cap_r = 0.17

    in_capsule = False
    if abs(nx) <= cap_r and cap_top <= ny <= cap_bot:
        in_capsule = True
    elif (nx ** 2 + (ny - cap_top) ** 2) <= cap_r ** 2 and ny < cap_top:
        in_capsule = True
    elif (nx ** 2 + (ny - cap_bot) ** 2) <= cap_r ** 2 and ny > cap_bot:
        in_capsule = True

    # 2. Floating U-Cradle Arc
    cr_center_y = 0.08
    cr_inner = 0.24
    cr_outer = 0.31
    cr_dist = math.sqrt(nx ** 2 + (ny - cr_center_y) ** 2)

    in_cradle = False
    if cr_inner <= cr_dist <= cr_outer and ny >= cr_center_y:
        in_cradle = True
    # Upright arms
    if (cr_inner <= abs(nx) <= cr_outer) and (-0.08 <= ny <= cr_center_y):
        in_cradle = True
    # Rounded tips of cradle arms
    tip_cx = (cr_inner + cr_outer) / 2.0
    tip_r = (cr_outer - cr_inner) / 2.0
    if ny < -0.08:
        if ((abs(nx) - tip_cx) ** 2 + (ny - (-0.08)) ** 2) <= tip_r ** 2:
            in_cradle = True

    # 3. Small Bottom Stem (Floating, No base plate!)
    in_stem = False
    stem_w = 0.035
    if abs(nx) <= stem_w and (cr_center_y + cr_inner) <= ny <= 0.48:
        in_stem = True
    if ny > 0.48:
        if (nx ** 2 + (ny - 0.48) ** 2) <= stem_w ** 2:
            in_stem = True

    if in_capsule:
        # Crisp white with subtle soft top-to-bottom illumination
        g_t = (ny - (cap_top - cap_r)) / (cap_bot + cap_r - (cap_top - cap_r))
        return (clamp(255 - 15 * g_t), clamp(255 - 5 * g_t), 255, 255)
    elif in_cradle or in_stem:
        # Crisp luminous white to soft electric cyan
        return (248, 250, 255, 255)

    # Soft ambient glow around the microphone
    mic_dist = math.sqrt(nx ** 2 + (ny - 0.0) ** 2)
    if mic_dist < 0.55:
        glow = (1.0 - (mic_dist / 0.55)) * 0.16
        bg_r = int(bg_r + 99 * glow)
        bg_g = int(bg_g + 102 * glow)
        bg_b = int(bg_b + 241 * glow)

    return (bg_r, bg_g, bg_b, 255)

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
