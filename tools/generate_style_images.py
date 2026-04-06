#!/usr/bin/env python3
"""
Generate placeholder style images for each era.

These are synthetic gradient/texture images that approximate the color
palette and tone of each historical period. Replace with real reference
photos for production use.

Usage:
    pip install Pillow numpy
    python tools/generate_style_images.py
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "mobile", "assets", "styles"
)
SIZE = 256


def _add_vignette(img: Image.Image, strength: float = 0.5) -> Image.Image:
    """Add a dark vignette effect around edges."""
    arr = np.array(img, dtype=np.float32)
    h, w = arr.shape[:2]
    y, x = np.ogrid[:h, :w]
    cy, cx = h / 2, w / 2
    r = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    r_max = np.sqrt(cx ** 2 + cy ** 2)
    vignette = 1.0 - strength * (r / r_max) ** 2
    vignette = np.clip(vignette, 0, 1)
    arr = arr * vignette[:, :, np.newaxis]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def _add_grain(img: Image.Image, amount: float = 15) -> Image.Image:
    """Add film grain noise."""
    arr = np.array(img, dtype=np.float32)
    noise = np.random.normal(0, amount, arr.shape)
    arr = np.clip(arr + noise, 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


def taisho_style() -> Image.Image:
    """大正時代 (1912-1926): Warm sepia, hand-colored look, soft."""
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    # Warm sepia gradient with slight color variations
    for y in range(SIZE):
        for x in range(SIZE):
            t = y / SIZE
            r = int(180 + 40 * t + 10 * np.sin(x * 0.05))
            g = int(140 + 30 * t + 8 * np.sin(x * 0.07 + 1))
            b = int(90 + 20 * t + 5 * np.sin(x * 0.03 + 2))
            draw.point((x, y), fill=(min(r, 255), min(g, 255), min(b, 255)))
    img = img.filter(ImageFilter.GaussianBlur(radius=2))
    img = _add_vignette(img, 0.6)
    img = _add_grain(img, 20)
    return img


def showa_early_style() -> Image.Image:
    """昭和初期 (1926-1945): High contrast black and white."""
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        for x in range(SIZE):
            v = int(80 + 100 * (y / SIZE) + 30 * np.sin(x * 0.1))
            v = min(max(v, 0), 255)
            draw.point((x, y), fill=(v, v, v))
    img = img.filter(ImageFilter.SHARPEN)
    img = _add_vignette(img, 0.4)
    img = _add_grain(img, 25)
    return img


def showa_mid_style() -> Image.Image:
    """昭和中期 (1945-1970): Faded Kodachrome color film."""
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        for x in range(SIZE):
            t = y / SIZE
            r = int(200 + 30 * t + 15 * np.sin(x * 0.04))
            g = int(170 + 40 * t + 10 * np.cos(x * 0.06))
            b = int(120 + 20 * t + 8 * np.sin(x * 0.08 + 0.5))
            draw.point((x, y), fill=(min(r, 255), min(g, 255), min(b, 255)))
    img = img.filter(ImageFilter.GaussianBlur(radius=1))
    img = _add_vignette(img, 0.3)
    img = _add_grain(img, 12)
    return img


def meiji_style() -> Image.Image:
    """明治時代 (1868-1912): Dark sepia, strong vignette, low contrast."""
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        for x in range(SIZE):
            t = y / SIZE
            r = int(140 + 30 * t + 8 * np.sin(x * 0.06))
            g = int(110 + 25 * t + 6 * np.sin(x * 0.04 + 1))
            b = int(70 + 15 * t + 4 * np.sin(x * 0.05 + 2))
            draw.point((x, y), fill=(min(r, 255), min(g, 255), min(b, 255)))
    img = img.filter(ImageFilter.GaussianBlur(radius=3))
    img = _add_vignette(img, 0.7)
    img = _add_grain(img, 30)
    return img


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    styles = {
        "taisho": taisho_style,
        "showa_early": showa_early_style,
        "showa_mid": showa_mid_style,
        "meiji": meiji_style,
    }
    for name, gen_fn in styles.items():
        path = os.path.join(OUTPUT_DIR, f"{name}.jpg")
        img = gen_fn()
        img.save(path, quality=95)
        print(f"Generated: {path}")
    print("✓ All style images generated")


if __name__ == "__main__":
    main()
