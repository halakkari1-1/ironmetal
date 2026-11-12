#!/usr/bin/env python3
"""Builds the colour-grading tables (LUTs) of the arenas: assets/arena/lut_<map>.png.

Each file is a strip of 32 squares of 32 x 32 pixels: red runs across a square, green down it, blue from one
square to the next. Arena._grade() cuts the strip into a 32 x 32 x 32 texture and gives it to the environment
(Environment.adjustment_color_correction), which looks every finished pixel up in it. The table is applied after
tone mapping, so the values here are ordinary screen colours.

A look is a split tone: shadows pushed towards one colour, highlights towards another, with a gentle contrast
curve and a saturation trim. Strongly coloured pixels (team colours, health bars drawn in the 3D view, tracers)
are pulled far less than grey ones, so they keep their hue.

Run from the godot/ folder:   python3 tools/textures/make_luts.py
Needs numpy and Pillow.
"""
import os
import numpy as np
from PIL import Image

N = 32

# shadows / highlights: the colour each end leans to and the largest shift of a channel (0..1 of full range); contrast: S-curve amount;
# sat: saturation multiplier; lift: added to black (a little haze in the darkest tones).
LOOKS = {
    # burnt orange dusk over cold blue-teal shadows: the strongest of the five
    "scrapyard": dict(shadows=((0.10, 0.42, 0.66), 0.14), highlights=((1.0, 0.62, 0.30), 0.10), contrast=0.10, sat=1.04, lift=0.004),
    # night: steel-blue shadows, a touch of warmth kept in the brightest tones so fires stay orange
    "refinery": dict(shadows=((0.10, 0.34, 0.74), 0.11), highlights=((1.0, 0.80, 0.58), 0.06), contrast=0.08, sat=0.98, lift=0.006),
    # open desert: golden light, clean blue shadows, the lightest touch
    "dustbowl": dict(shadows=((0.16, 0.44, 0.76), 0.11), highlights=((1.0, 0.80, 0.46), 0.08), contrast=0.07, sat=1.03, lift=0.0),
    # rose dusk: peach highlights over blue shadows, to open up a scene that is otherwise all pink
    "shanty": dict(shadows=((0.14, 0.34, 0.74), 0.15), highlights=((1.0, 0.66, 0.42), 0.09), contrast=0.09, sat=1.0, lift=0.004),
    # amber afternoon over slate-blue shadows
    "outpost": dict(shadows=((0.14, 0.40, 0.70), 0.12), highlights=((1.0, 0.74, 0.36), 0.09), contrast=0.08, sat=1.04, lift=0.0),
}


def grade(rgb: np.ndarray, look: dict) -> np.ndarray:
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
    mx, mn = rgb.max(-1), rgb.min(-1)
    chroma = mx - mn                                   # 0 grey .. 1 pure colour
    keep = 1.0 - 0.75 * np.clip(chroma * 1.6, 0, 1)   # strong colours are toned much less
    out = rgb.copy()
    luma = np.array([0.2126, 0.7152, 0.0722])
    w_dark = (1.0 - lum) ** 2 * np.clip(lum * 8.0, 0, 1)        # darks, fading out at pure black
    w_light = lum ** 2 * np.clip((1.0 - lum) * 8.0, 0, 1)       # lights, fading out at pure white
    for (tint, amount), weight in ((look["shadows"], w_dark), (look["highlights"], w_light)):
        t = np.array(tint)
        t = t - t @ luma                  # a pure colour push: brightness stays where it was
        t = t / np.abs(t).max()           # amount = the largest shift of any channel
        out += t * amount * (weight * keep)[..., None]
    # contrast around middle grey, on brightness only
    c = look["contrast"]
    l2 = out @ np.array([0.2126, 0.7152, 0.0722])
    s = l2 + c * (l2 - 0.5) * (1.0 - np.abs(2.0 * l2 - 1.0)) * 2.0
    out += (s - l2)[..., None]
    # saturation
    l3 = out @ np.array([0.2126, 0.7152, 0.0722])
    out = l3[..., None] + (out - l3[..., None]) * look["sat"]
    out = out * (1.0 - look["lift"]) + look["lift"]
    # pure white and pure black stay put
    return np.clip(out, 0.0, 1.0)


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    dest = os.path.normpath(os.path.join(here, "..", "..", "assets", "arena"))
    v = np.linspace(0.0, 1.0, N)
    b, g, r = np.meshgrid(v, v, v, indexing="ij")      # [blue slice][green row][red column]
    rgb = np.stack([r, g, b], -1)
    for name, look in LOOKS.items():
        cube = grade(rgb.reshape(-1, 3), look).reshape(N, N, N, 3)
        strip = np.concatenate(list(cube), axis=1)     # slices side by side
        Image.fromarray((strip * 255.0 + 0.5).astype(np.uint8), "RGB").save(os.path.join(dest, "lut_%s.png" % name), optimize=True)
        d = np.abs(cube - rgb).max()
        print("lut_%s.png  largest change %.3f" % (name, d))


if __name__ == "__main__":
    main()
