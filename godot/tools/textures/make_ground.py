#!/usr/bin/env python3
"""Builds the extra layers of the arena floor (see scripts/game/ground.gdshader): assets/ground/layer_*.png.

  layer_gravel_ch.png   512  RGB colour of stony soil, A its height          from ambientCG Ground105 (CC0)
  layer_gravel_nr.png   512  RG normal (x, y), B roughness
  layer_mud_ch.png      512  RGB colour of dried, cracked mud, A its height  from ambientCG Ground031 (CC0)
  layer_mud_nr.png      512  RG normal (x, y), B roughness
  layer_detail.png      256  R fine grit (brightness around 0.5), GB its normal (x, y): the close-up layer (generated)
  layer_macro.png       256  broad masks over tens of metres (generated, tileable): R where gravel gathers,
                             G where mud gathers, B light and dark patches, A a mask that mixes two dirt samples

Run from the godot/ folder:
    python3 tools/textures/make_ground.py <folder>     all six; <folder> holds the unzipped ambientCG downloads
                                                        (Ground105_4K-PNG/, Ground031_2K-PNG/), which are too
                                                        large to keep in the repository
    python3 tools/textures/make_ground.py              only the two generated ones
Needs numpy, scipy and Pillow. After a change, let Godot reimport (the .import files keep their settings).
"""
import glob
import os
import sys
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

rng = np.random.default_rng(7)


def noise(n: int, beta: float, seed: int, lo: float = 1.0, hi: float = 1e9) -> np.ndarray:
    """Tileable noise in 0..1: random phases with a 1/f^beta spectrum, between the frequencies lo and hi."""
    r = np.random.default_rng(seed)
    fx = np.fft.fftfreq(n)[:, None] * n
    fy = np.fft.fftfreq(n)[None, :] * n
    f = np.sqrt(fx * fx + fy * fy)
    amp = np.where((f >= lo) & (f <= hi), 1.0 / np.maximum(f, 1.0) ** beta, 0.0)
    spec = amp * np.exp(2j * np.pi * r.random((n, n)))
    a = np.real(np.fft.ifft2(spec))
    a -= a.min()
    return a / a.max()


def cells(n: int, count: int, seed: int):
    """Tileable Voronoi: distance to the nearest and second nearest point (in pixels) and the nearest point's id."""
    r = np.random.default_rng(seed)
    pts = r.random((count, 2)) * n
    tree = cKDTree(pts, boxsize=n)
    yy, xx = np.mgrid[0:n, 0:n]
    d, i = tree.query(np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5], -1), k=2)
    return d[:, 0].reshape(n, n), d[:, 1].reshape(n, n), i[:, 0].reshape(n, n), r


def normal_rg(h: np.ndarray, strength: float) -> np.ndarray:
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    z = 1.0 / np.sqrt(dx * dx + dy * dy + 1.0)
    return np.stack([-dx * z * 0.5 + 0.5, -dy * z * 0.5 + 0.5], -1)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def save(name: str, a: np.ndarray) -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    dest = os.path.normpath(os.path.join(here, "..", "..", "assets", "ground", name))
    mode = {1: "L", 3: "RGB", 4: "RGBA"}[a.shape[2] if a.ndim == 3 else 1]
    Image.fromarray((np.clip(a, 0, 1) * 255.0 + 0.5).astype(np.uint8), mode).save(dest, optimize=True)
    print(name, a.shape)


def to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1.0 / 2.4) - 0.055)


def load(src: str, name: str, kind: str, n: int, mode: str) -> np.ndarray:
    hits = glob.glob(os.path.join(src, "%s_*" % name, "%s_*_%s.*" % (name, kind)))
    if not hits:
        raise SystemExit("missing %s %s under %s" % (name, kind, src))
    return np.asarray(Image.open(hits[0]).convert(mode).resize((n, n), Image.LANCZOS)).astype(np.float64) / 255.0


def photo_layer(src: str, name: str, out: str, mean, min_rough: float, n: int = 512) -> None:
    """One layer from an ambientCG set (CC0): colour with its height in alpha, and normal x y with roughness.
    The colour is scaled, in linear light, to the average the shader and the maps' tints are tuned for."""
    col = to_linear(load(src, name, "Color", n, "RGB"))
    col = to_srgb(col * (np.array(mean) / col.mean((0, 1))))
    h = load(src, name, "Displacement", n, "L")
    h = (h - np.percentile(h, 1)) / max(1e-6, np.percentile(h, 99) - np.percentile(h, 1))
    save("layer_%s_ch.png" % out, np.concatenate([col, np.clip(h, 0, 1)[..., None]], -1))
    nrm = load(src, name, "NormalGL", n, "RGB")
    rough = np.maximum(load(src, name, "Roughness", n, "L"), min_rough)   # never glossy: only oil and water shine
    save("layer_%s_nr.png" % out, np.concatenate([nrm[..., :2], rough[..., None]], -1))


def detail(n: int = 256) -> None:
    grit = noise(n, 0.35, 31, lo=18)
    d1, d2, cid, r = cells(n, 900, 32)                 # scattered small pebbles
    peb = np.sqrt(np.clip(1.0 - (d1 / 3.2) ** 2, 0, 1)) * (r.random(900)[cid] > 0.55)
    h = np.clip(0.75 * grit + 0.5 * peb, 0, 1)
    lum = 0.5 + (grit - grit.mean()) * 0.9 + 0.12 * peb
    save("layer_detail.png", np.concatenate([lum[..., None], normal_rg(h, 4.0)], -1))


def macro(n: int = 256) -> None:
    a = [noise(n, 1.6, s, lo=1, hi=40) for s in (41, 42, 43, 44)]
    a = [(x - x.mean()) / x.std() * 0.22 + 0.5 for x in a]     # centred on 0.5, the same spread in each
    save("layer_macro.png", np.stack(a, -1))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        # stony soil for the gravel layer, dried cracked mud for the mud layer
        photo_layer(sys.argv[1], "Ground105", "gravel", (0.28, 0.25, 0.19), 0.84)
        photo_layer(sys.argv[1], "Ground031", "mud", (0.19, 0.14, 0.10), 0.82)
    detail()
    macro()
