"""Original CC0 engineering fixture: textured synthetic terrain, never satellite imagery."""
from pathlib import Path
import math
import json
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / "src/retroplasma/resources/sample"
ROOT.mkdir(parents=True, exist_ok=True)


def height(east, north):
    return 25 + 75 * math.exp(-((east - 70) ** 2 + (north + 50) ** 2) / 55000) + 12 * math.sin(east / 70) * math.cos(north / 90)


def mesh(name, lo_e, lo_n, hi_e, hi_n, grid):
    lines = ["# Original InGe+ CC0 synthetic fixture. Positions: East North Up in metres."]
    for y in range(grid + 1):
        north = lo_n + (hi_n - lo_n) * y / grid
        for x in range(grid + 1):
            east = lo_e + (hi_e - lo_e) * x / grid
            lines.append(f"v {east:.6f} {north:.6f} {height(east, north):.6f}")
    for y in range(grid + 1):
        north = lo_n + (hi_n - lo_n) * y / grid
        for x in range(grid + 1):
            east = lo_e + (hi_e - lo_e) * x / grid
            lines.append(f"vt {(east+400)/800:.6f} {(north+400)/800:.6f}")
    for y in range(grid):
        for x in range(grid):
            a = y * (grid + 1) + x + 1
            b, c, d = a + 1, a + grid + 1, a + grid + 2
            lines += [f"f {a}/{a} {b}/{b} {d}/{d}", f"f {a}/{a} {d}/{d} {c}/{c}"]
    (ROOT / name).write_text("\n".join(lines) + "\n", encoding="utf-8")


def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


rows = bytearray()
for y in range(256):
    rows.append(0)
    north = 400 - y * 800 / 255
    for x in range(256):
        east = x * 800 / 255 - 400
        h = height(east, north)
        contour = int(h) % 10 < 1
        grid = x % 32 == 0 or y % 32 == 0
        color = (35, 47, 56) if contour else (200, 210, 215) if grid else (int(60 + h), int(115 + h * .5), int(55 + h * .2))
        rows.extend(color)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 256, 256, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
(ROOT / "terrain.png").write_bytes(png)
mesh("root-coarse.obj", -400, -400, 400, 400, 8)
mesh("root-fine.obj", -400, -400, 400, 400, 24)
nodes = [{"id": "root", "bounds": [-400, -400, 0, 400, 400, 150], "lods": [
    {"error": 40, "mesh": "root-coarse.obj", "texture": "terrain.png"},
    {"error": 8, "mesh": "root-fine.obj", "texture": "terrain.png"}]}]
for i, bounds in enumerate([(-400, -400, 0, 0), (0, -400, 400, 0), (-400, 0, 0, 400), (0, 0, 400, 400)]):
    lo_e, lo_n, hi_e, hi_n = bounds
    for level, grid in [("coarse", 8), ("fine", 24)]:
        mesh(f"tile{i}-{level}.obj", lo_e, lo_n, hi_e, hi_n, grid)
    nodes.append({"id": f"tile{i}", "parent": "root", "bounds": [lo_e, lo_n, 0, hi_e, hi_n, 150], "lods": [
        {"error": 10, "mesh": f"tile{i}-coarse.obj", "texture": "terrain.png"},
        {"error": 1, "mesh": f"tile{i}-fine.obj", "texture": "terrain.png"}]})
scene = {"format": "inge-retroplasma-scene-v1", "title": "Terreno sintético georreferenciado · prueba CC0",
         "source": "Fixture original InGe+; no imágenes ni fotogrametría de Google",
         "license": "CC0-1.0", "origin": {"latitude": -12.0464, "longitude": -77.0428, "altitude": 100}, "nodes": nodes}
(ROOT / "scene.json").write_text(json.dumps(scene, ensure_ascii=False, indent=2), encoding="utf-8")
(ROOT / "LICENSE.txt").write_text("Original procedural fixture generated for InGe+. Dedicated to CC0-1.0.\nSynthetic heightfield and contour texture, NOT Google content or a measured survey.\nhttps://creativecommons.org/publicdomain/zero/1.0/\n", encoding="utf-8")
print("RETROPLASMA_FIXTURE", ROOT, len(nodes), "nodes, 10 indexed textured OBJ LOD assets")
