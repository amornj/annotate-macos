#!/usr/bin/env python3
"""
Generate placeholder Chrome extension icons as valid PNGs.
Uses only struct and zlib (no PIL/Pillow required).
Creates an orange rounded square with a pencil-like diagonal mark.
"""

import struct
import zlib
import os

def make_png(width, height, rgba_data):
    """Create a valid PNG file from raw RGBA pixel data."""

    def chunk(chunk_type, data):
        c = chunk_type + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    # PNG signature
    signature = b"\x89PNG\r\n\x1a\n"

    # IHDR chunk
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    # bit depth=8, color type=6 (RGBA), compression=0, filter=0, interlace=0

    # IDAT chunk: build raw image data with filter bytes
    raw = b""
    for y in range(height):
        raw += b"\x00"  # filter type: None
        row_start = y * width * 4
        raw += rgba_data[row_start : row_start + width * 4]

    compressed = zlib.compress(raw)

    # IEND chunk
    return signature + chunk(b"IHDR", ihdr_data) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")


def distance(x1, y1, x2, y2):
    return ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5


def generate_icon(size):
    """
    Generate an icon: orange rounded square background with a white
    diagonal pencil/pen stroke mark.
    """
    pixels = bytearray(size * size * 4)

    # Colors
    bg_r, bg_g, bg_b = 0xFF, 0x6D, 0x00  # vibrant orange
    pencil_r, pencil_g, pencil_b = 0xFF, 0xFF, 0xFF  # white pencil mark
    tip_r, tip_g, tip_b = 0x3D, 0x3D, 0x3D  # dark gray pencil tip

    corner_radius = max(2, size // 5)

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4

            # --- Rounded rectangle mask ---
            inside = True
            alpha = 255

            # Check corners for rounding
            corners = []
            if x < corner_radius and y < corner_radius:
                corners.append((corner_radius, corner_radius))
            if x >= size - corner_radius and y < corner_radius:
                corners.append((size - corner_radius - 1, corner_radius))
            if x < corner_radius and y >= size - corner_radius:
                corners.append((corner_radius, size - corner_radius - 1))
            if x >= size - corner_radius and y >= size - corner_radius:
                corners.append((size - corner_radius - 1, size - corner_radius - 1))

            for cx, cy in corners:
                d = distance(x, y, cx, cy)
                if d > corner_radius:
                    inside = False
                elif d > corner_radius - 1.2:
                    alpha = int(255 * max(0.0, corner_radius - d))

            if not inside:
                pixels[idx] = 0
                pixels[idx + 1] = 0
                pixels[idx + 2] = 0
                pixels[idx + 3] = 0
                continue

            # --- Background: subtle gradient for depth ---
            grad = (x + y) / (2.0 * size)
            r = int(bg_r * (1.0 - 0.18 * grad))
            g = int(bg_g * (1.0 - 0.18 * grad))
            b = int(bg_b * (1.0 - 0.18 * grad))

            # --- Pencil body: diagonal line from upper-right to lower-left ---
            p1x = size * 0.73
            p1y = size * 0.14
            p2x = size * 0.18
            p2y = size * 0.78

            dx = p2x - p1x
            dy = p2y - p1y
            length = (dx * dx + dy * dy) ** 0.5
            ux = dx / length
            uy = dy / length
            nx = -uy
            ny = ux

            vx = x - p1x
            vy = y - p1y
            along = vx * ux + vy * uy
            perp = abs(vx * nx + vy * ny)

            pencil_width = max(1.5, size * 0.10)
            tip_length = size * 0.12

            if 0 <= along <= length and perp < pencil_width:
                edge_aa = max(0.0, min(1.0, pencil_width - perp))

                if along > length - tip_length:
                    tip_progress = (along - (length - tip_length)) / tip_length
                    max_width_at_tip = pencil_width * (1.0 - tip_progress)
                    if perp < max_width_at_tip:
                        edge_aa = max(0.0, min(1.0, max_width_at_tip - perp))
                        tr = int(tip_r * (1.0 - 0.3 * tip_progress) + pencil_r * 0.3 * tip_progress)
                        tg = int(tip_g * (1.0 - 0.3 * tip_progress) + pencil_g * 0.3 * tip_progress)
                        tb = int(tip_b * (1.0 - 0.3 * tip_progress) + pencil_b * 0.3 * tip_progress)
                        r = int(r * (1.0 - edge_aa) + tr * edge_aa)
                        g = int(g * (1.0 - edge_aa) + tg * edge_aa)
                        b = int(b * (1.0 - edge_aa) + tb * edge_aa)
                else:
                    signed_perp = vx * nx + vy * ny
                    shade = 0.85 + 0.15 * (signed_perp / pencil_width)
                    pr = int(pencil_r * shade)
                    pg = int(pencil_g * shade)
                    pb = int(pencil_b * shade)
                    pr = max(0, min(255, pr))
                    pg = max(0, min(255, pg))
                    pb = max(0, min(255, pb))
                    r = int(r * (1.0 - edge_aa) + pr * edge_aa)
                    g = int(g * (1.0 - edge_aa) + pg * edge_aa)
                    b = int(b * (1.0 - edge_aa) + pb * edge_aa)

            # --- Small eraser cap at the top of the pencil ---
            eraser_len = size * 0.07
            if -eraser_len <= along < 0 and perp < pencil_width * 0.85:
                edge_aa = max(0.0, min(1.0, pencil_width * 0.85 - perp))
                er, eg, eb = 0xE8, 0x40, 0x40
                r = int(r * (1.0 - edge_aa) + er * edge_aa)
                g = int(g * (1.0 - edge_aa) + eg * edge_aa)
                b = int(b * (1.0 - edge_aa) + eb * edge_aa)

            r = max(0, min(255, r))
            g = max(0, min(255, g))
            b = max(0, min(255, b))
            alpha = max(0, min(255, alpha))

            pixels[idx] = r
            pixels[idx + 1] = g
            pixels[idx + 2] = b
            pixels[idx + 3] = alpha

    return bytes(pixels)


def main():
    sizes = [16, 32, 48, 128]
    output_dir = "/Users/home/projects/annotate/icons"

    for size in sizes:
        print(f"Generating {size}x{size} icon...")
        rgba = generate_icon(size)
        png_data = make_png(size, size, rgba)
        path = os.path.join(output_dir, f"icon{size}.png")
        with open(path, "wb") as f:
            f.write(png_data)
        print(f"  Wrote {path} ({len(png_data)} bytes)")

    print("\nAll icons generated successfully.")


if __name__ == "__main__":
    main()
