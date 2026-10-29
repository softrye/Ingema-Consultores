"""Silueta blanca del símbolo InGe+ para el acceso (Login V1, 2026-10-12).

Origen: images/INGEPLUS_ICON_SOLO_SIMBOLO.png (sin redibujar ni modificar la
forma). Cada píxel con tinta (azul, verde o azul oscuro) pasa a blanco con una
opacidad proporcional a su intensidad, de modo que los trazos internos blancos
del original quedan como espacio negativo y los bordes conservan su suavizado.
Solo se recorta al símbolo (círculo y "+", columnas 222-880): el fragmento de
barra azul en x 899-921 del archivo original no forma parte del símbolo.

Uso: python scripts/make_white_symbol.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "images" / "INGEPLUS_ICON_SOLO_SIMBOLO.png"
TARGET = ROOT / "qml" / "Mobile" / "assets" / "inge_symbol_white.png"
SYMBOL_BOX = (222, 136, 881, 830)   # x0, y0, x1, y1 (x1/y1 exclusivos)
INK_FLOOR, INK_FULL = 20, 160       # tinta = 255 - min(R, G, B)
PADDING = 12


def main() -> None:
    image = Image.open(SOURCE).convert("RGBA").crop(SYMBOL_BOX)
    width, height = image.size
    side = max(width, height) + 2 * PADDING
    out = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    src, dst = image.load(), out.load()
    ox, oy = (side - width) // 2, (side - height) // 2
    for y in range(height):
        for x in range(width):
            r, g, b, a = src[x, y]
            ink = 255 - min(r, g, b)
            level = (ink - INK_FLOOR) / (INK_FULL - INK_FLOOR)
            alpha = round(max(0.0, min(1.0, level)) * a)
            if alpha:
                dst[ox + x, oy + y] = (255, 255, 255, alpha)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    out.save(TARGET, optimize=True)
    print(f"{TARGET} {side}x{side}")


if __name__ == "__main__":
    main()
