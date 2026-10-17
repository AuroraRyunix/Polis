"""Draws rel/windows/Polis.ico and rel/macos/Polis-icon.png from the mark
in priv/logo/mark.svg.

The mark is squares on a 24-unit grid: filled ones in the ink
(`currentColor`), one in the accent (`var(--accent, #...)`), and - in some
of the family's marks, not this one - outlined ones (`fill="none"` with a
stroke). They are read from the SVG's `<rect>` elements and redrawn here
with Pillow rather than rendered, because a renderer is a dependency nobody
has installed and a handful of rectangles is not. Anything in the SVG that
is not a rect this script understands stops it, so a new mark cannot be
half-drawn in silence.

    python rel/windows/build_icon.py

Needs Pillow. Both files are committed: the launcher's resource script and
`vpk pack --icon` want the .ico, rel/macos/build_app.sh wants the PNG, and CI
should not need Python to make a release.
"""

import re
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
MARK = HERE.parent.parent / "priv" / "logo" / "mark.svg"

INK = (27, 27, 26, 255)
PAPER = (255, 255, 255, 255)


def hex_colour(text):
    text = text.lstrip("#")
    return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def attributes(tag):
    return dict(re.findall(r'([\w-]+)="([^"]*)"', tag))


def read_mark():
    """[(x, y, w, h, kind, colour, stroke_width)] from the SVG's rects."""
    svg = MARK.read_text(encoding="utf-8")
    inner = re.search(r"<svg[^>]*>(.*)</svg>", svg, re.S).group(1)
    leftover = re.sub(r"<rect\b[^>]*/>", "", inner).strip()
    if leftover:
        raise SystemExit(f"{MARK} has more than rects in it, which this script does not draw: {leftover[:80]}")

    shapes = []
    for tag in re.findall(r"<rect\b[^>]*/>", inner):
        a = attributes(tag)
        x, y, w, h = (float(a[k]) for k in ("x", "y", "width", "height"))
        style = a.get("style", "")
        accent = re.search(r"var\(--accent,\s*(#[0-9a-fA-F]{6})\)", style + a.get("fill", ""))

        if a.get("fill") == "none" and a.get("stroke") == "currentColor":
            shapes.append((x, y, w, h, "outline", INK, float(a.get("stroke-width", "1"))))
        elif accent:
            shapes.append((x, y, w, h, "fill", hex_colour(accent.group(1)), 0))
        elif a.get("fill") == "currentColor":
            shapes.append((x, y, w, h, "fill", INK, 0))
        else:
            raise SystemExit(f"{MARK}: a rect this script does not know how to colour: {tag}")

    if not shapes:
        raise SystemExit(f"{MARK} has no rects")
    return shapes


def draw(shapes, size, scale=16):
    # Drawn large and scaled down: the small sizes get their edges from the
    # resampling, not from rounding a 0.67-pixel gap to nothing.
    side = 28 * scale
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    pen = ImageDraw.Draw(image)
    pen.rounded_rectangle((0, 0, side - 1, side - 1), radius=4 * scale, fill=PAPER)

    for x, y, w, h, kind, colour, stroke in shapes:
        left, top = (x + 2) * scale, (y + 2) * scale
        right, bottom = left + w * scale - 1, top + h * scale - 1
        if kind == "fill":
            pen.rectangle((left, top, right, bottom), fill=colour)
        else:
            # An SVG stroke straddles the edge: half outside, half inside.
            half = stroke * scale / 2
            pen.rectangle(
                (left - half, top - half, right + half, bottom + half),
                outline=colour,
                width=max(1, round(stroke * scale)),
            )

    return image.resize((size, size), Image.LANCZOS)


def write_mac_png(shapes, path):
    # macOS draws its icons inside a margin (824 of 1024); a tile that fills
    # the canvas looks a size too big beside everybody else's in the Dock.
    # Drawn at 32 units a pixel (896 square) so 824 is a step down, not up.
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    canvas.paste(draw(shapes, 824, scale=32), (100, 100))
    canvas.save(path)


def main():
    shapes = read_mark()
    sizes = [256, 128, 64, 48, 32, 24, 16]
    draw(shapes, 256).save(HERE / "Polis.ico", format="ICO", sizes=[(s, s) for s in sizes])
    print(f"wrote {HERE / 'Polis.ico'}")
    png = HERE.parent / "macos" / "Polis-icon.png"
    write_mac_png(shapes, png)
    print(f"wrote {png}")


if __name__ == "__main__":
    main()
