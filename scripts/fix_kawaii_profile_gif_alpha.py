"""Repair the broken black matte in the pre-existing animated Kawaii GIF.

Pillow indexed transparency requires a TRANSPARENT palette entry on EVERY frame.
The former file used transparency=255 while the fully opaque black matte was
index 0, which Qt displayed as a black rectangle.

This script never changes the character artwork or the actual calicata data.
Requires Pillow, numpy, scipy. Run with --fix to rewrite, or --check to assert.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import shutil
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / "images/kawaii/pompompurin-calicata-crash-10s.gif"

def audit(file: Path) -> None:
    img = Image.open(file)
    assert img.n_frames == 80, "Expected full 10-second sequence"
    duration = 0
    for n in range(img.n_frames):
        img.seek(n)
        duration += img.info.get("duration", 0)
        rgba = np.asarray(img.convert("RGBA"))
        assert rgba[0, 0, 3] == 0, f"Opaque background in frame {n}"
        assert float((rgba[:, :, 3] == 0).mean()) > 0.35, f"Matte on frame {n}"
        assert float((rgba[:, :, 3] > 0).mean()) > 0.005, f"Missing artwork on frame {n}"
    assert abs(duration - 10000) <= 80, f"Duration drift: {duration} ms"
    print("PASS: 80-frame / 10-second transparent GIF; no opaque black matte", img.n_frames, duration)
    img.close()

def fix() -> None:
    img = Image.open(ASSET)
    frames = []
    durations = []
    for n in range(img.n_frames):
        img.seek(n)
        rgb = np.array(img.convert("RGB"), dtype=np.uint8)
        # The old encoder also corrupted frames 11 and 13: those frames have
        # a flat brown matte instead of black. Derive the matte from each
        # frame's border rather than assuming pure black.
        corner = rgb[0, 0].astype(np.int16)
        distance = np.max(np.abs(rgb.astype(np.int16) - corner), axis=2)
        matte_candidate = distance < 9
        labels, _ = ndimage.label(matte_candidate)
        border = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
        border = border[border != 0]
        outside = np.isin(labels, border)

        quantized = Image.fromarray(rgb).quantize(colors=255,
                          method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        pixels = (np.asarray(quantized, dtype=np.uint8).astype(np.uint16) + 1).astype(np.uint8)
        pixels[outside] = 0
        output = Image.fromarray(pixels, mode="P")
        palette = ([0, 0, 0] + quantized.getpalette()[:255 * 3])[:768]
        palette += [0] * (768 - len(palette))
        output.putpalette(palette)
        output.info["transparency"] = 0
        frames.append(output)
        durations.append(img.info.get("duration", 120))

    backup = Path(tempfile.gettempdir()) / "inge_pompompurin_crash_before_alpha_fix.gif"
    if not backup.exists():
        shutil.copy2(ASSET, backup)
    dest = ASSET.with_name("_calicata_alpha_verify.gif")
    frames[0].save(dest, save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, disposal=2, optimize=False,
                   transparency=0)
    try:
        audit(dest)
    finally:
        frames.clear()
        img.close()
    # Close audit's input file before attempting Windows rename/unlink.
    dest.replace(ASSET)
    print("UPDATED", ASSET, "original backed up to", backup)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fix", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.fix:
        fix()
    else:
        audit(ASSET)
