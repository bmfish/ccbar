from PIL import Image, ImageDraw, ImageFont
import os

SIZES = [16, 32, 64, 128, 256, 512, 1024]

def make_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pad = int(size * 0.08)

    # Rounded rect background with gradient effect
    r = int(size * 0.22)
    # Draw gradient background (pink to purple)
    for y in range(size):
        ratio = y / size
        ri = int(255 * (1 - ratio) + 157 * ratio)
        gi = int(110 * (1 - ratio) + 78 * ratio)
        bi = int(180 * (1 - ratio) + 237 * ratio)
        for x in range(size):
            # Check if inside rounded rect
            in_rect = True
            if x < pad or x >= size - pad or y < pad or y >= size - pad:
                in_rect = False
            elif x < pad + r and y < pad + r:
                if (x - pad - r) ** 2 + (y - pad - r) ** 2 > r * r:
                    in_rect = False
            elif x >= size - pad - r and y < pad + r:
                if (x - size + pad + r) ** 2 + (y - pad - r) ** 2 > r * r:
                    in_rect = False
            elif x < pad + r and y >= size - pad - r:
                if (x - pad - r) ** 2 + (y - size + pad + r) ** 2 > r * r:
                    in_rect = False
            elif x >= size - pad - r and y >= size - pad - r:
                if (x - size + pad + r) ** 2 + (y - size + pad + r) ** 2 > r * r:
                    in_rect = False
            if in_rect:
                img.putpixel((x, y), (ri, gi, bi, 255))

    # Draw lightning bolt ⚡
    cx, cy = size // 2, size // 2
    s = size * 0.35
    bolt = [
        (cx - s * 0.15, cy - s * 1.0),
        (cx + s * 0.45, cy - s * 0.05),
        (cx + s * 0.05, cy - s * 0.05),
        (cx + s * 0.25, cy + s * 1.0),
        (cx - s * 0.35, cy + s * 0.1),
        (cx + s * 0.05, cy + s * 0.1),
    ]
    bolt = [(int(x), int(y)) for x, y in bolt]
    draw.polygon(bolt, fill=(255, 255, 255, 230))

    # Small sparkle dots
    import random
    random.seed(42)
    for _ in range(6):
        sx = int(size * 0.15 + random.random() * size * 0.7)
        sy = int(size * 0.15 + random.random() * size * 0.7)
        sr = max(1, int(size * 0.015))
        draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(255, 255, 255, 120))

    return img

# Generate all sizes
iconset_dir = '/tmp/ccBar.iconset'
os.makedirs(iconset_dir, exist_ok=True)

mapping = {
    16: ['icon_16x16.png'],
    32: ['icon_16x16@2x.png', 'icon_32x32.png'],
    64: ['icon_32x32@2x.png'],
    128: ['icon_128x128.png'],
    256: ['icon_128x128@2x.png', 'icon_256x256.png'],
    512: ['icon_256x256@2x.png', 'icon_512x512.png'],
    1024: ['icon_512x512@2x.png'],
}

for size, names in mapping.items():
    img = make_icon(size)
    for name in names:
        img.save(os.path.join(iconset_dir, name))
        print(f'  {name} ({size}x{size})')

print('✅ iconset 生成完成')
