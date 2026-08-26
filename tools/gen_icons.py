#!/usr/bin/env python3
"""Генерация иконки Cellka: тёмный фон + столбики уровня сигнала.

Пишет PNG во все mipmap-плотности и adaptive-icon XML (API 26+).
Запускается в CI (см. .github/workflows/release.yml), локально:
    pip install pillow && python3 tools/gen_icons.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

RES = Path('android/app/src/main/res')
MASTER = 432  # мастер-канва, ресайзим вниз

# Плотности для bitmap-иконок.
MIPMAPS = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

BG = (18, 18, 24, 255)
# Столбики как на шкале сигнала: слабые жёлто-красные, сильные зелёные.
BAR_COLORS = [
    (255, 69, 58, 255),
    (255, 159, 10, 255),
    (255, 204, 0, 255),
    (52, 199, 89, 255),
]
BAR_HEIGHTS = [0.16, 0.28, 0.40, 0.52]

ADAPTIVE_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\">
    <background android:drawable=\"@color/cellka_icon_bg\"/>
    <foreground android:drawable=\"@mipmap/ic_launcher\"/>
</adaptive-icon>
"""

COLORS_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<resources>
    <color name=\"cellka_icon_bg\">#121218</color>
</resources>
"""


def render_master(size: int = MASTER) -> Image.Image:
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=BG,
    )
    bar_w = int(size * 0.13)
    gap = int(size * 0.055)
    x0 = int(size * 0.155)
    base = int(size * 0.78)
    for i, h in enumerate(BAR_HEIGHTS):
        x = x0 + i * (bar_w + gap)
        y = base - int(size * h)
        d.rounded_rectangle(
            [x, y, x + bar_w, base],
            radius=int(bar_w * 0.35),
            fill=BAR_COLORS[i],
        )
    return img


def main() -> None:
    master = render_master()
    for folder, px in MIPMAPS.items():
        out = RES / folder
        out.mkdir(parents=True, exist_ok=True)
        icon = master.resize((px, px), Image.LANCZOS)
        icon.save(out / 'ic_launcher.png')
        icon.save(out / 'ic_launcher_round.png')

    anydpi = RES / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(ADAPTIVE_XML)
    (anydpi / 'ic_launcher_round.xml').write_text(ADAPTIVE_XML)

    values = RES / 'values'
    values.mkdir(parents=True, exist_ok=True)
    (values / 'cellka_icon.xml').write_text(COLORS_XML)

    total = len(MIPMAPS) * 2 + 3
    print(f'icons written: {total} files under {RES}')


if __name__ == '__main__':
    main()
