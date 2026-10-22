"""Generates the arena textures that are drawn rather than photographed (all original, no third-party art):

- container_albedo.png / container_normal.png: corrugated steel container skin (greyscale, tinted in game) with
  the door end, rust streaks and grime along the bottom.
- ground stamps (greyscale masks, white = full effect): crack_*.png, oil_*.png, tyre_*.png, scorch_ground.png,
  puddle_*.png, composited by the game into each arena's detail map.
- ramp_albedo.png / ramp_normal.png: diamond-plate steel with a black/yellow hazard band at the lip.

usage: python3 make_textures.py <out dir>
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

rng = np.random.default_rng(7)
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)


def noise(h, w, scale, octaves=4, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        gh, gw = max(2, int(h / scale) + 2), max(2, int(w / scale) + 2)
        g = r.random((gh, gw))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += np.asarray(img, dtype=np.float64) / 255 * amp
        tot += amp
        amp *= 0.5
        scale /= 2
    return out / tot


def save(a, name, mode="L"):
    a = np.clip(a, 0, 1)
    if mode == "L":   # masks: white, with the mask in the alpha channel (stamps blend straight onto each other)
        la = np.dstack([np.full(a.shape, 255, np.uint8), (a * 255).astype(np.uint8)])
        Image.fromarray(la, "LA").save(os.path.join(OUT, name))
    else:
        Image.fromarray((a * 255).astype(np.uint8), mode).save(os.path.join(OUT, name))


def normal_from_height(hgt, strength):
    gy, gx = np.gradient(hgt)
    n = np.dstack([-gx * strength, -gy * strength, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


# ---------- container ----------
def container():
    W, H = 1024, 512
    side_w = 768                      # u 0..0.75: long side, 0.75..1: door end
    x = np.arange(W)[None, :].repeat(H, 0).astype(float)
    y = np.arange(H)[:, None].repeat(W, 1).astype(float)
    hgt = np.zeros((H, W))
    # trapezoid corrugation ribs across the side, 24 ribs
    ph = (x / side_w * 24) % 1.0
    rib = np.clip(np.minimum(ph, 1 - ph) * 4 - 0.5, 0, 1)
    hgt[:, :side_w] = rib[:, :side_w]
    # door end: two doors with vertical locking bars and horizontal pressings
    dx = x - side_w
    door = np.zeros((H, W))
    door += 0.35 * ((y % 128) < 70)
    for bx in [40, 90, 166, 216]:
        door += 0.9 * (np.abs(dx - bx) < 5)
    door -= 0.6 * (np.abs(dx - 128) < 2)
    hgt[:, side_w:] = door[:, side_w:]
    # frame top and bottom rails
    hgt[(y < 14) | (y > H - 18)] = 0.7
    base = 0.82 + 0.1 * noise(H, W, 64, seed=1)
    grime = np.clip((y / H - 0.55) * 2.0, 0, 1) * (0.5 + 0.5 * noise(H, W, 40, seed=2))
    streak_n = noise(H, W, 16, seed=3)
    streaks = np.clip((noise(1, W, 6, seed=4)[0] - 0.62) * 6, 0, 1)[None, :] * np.clip(1 - y / H * 1.3, 0, 1) * streak_n
    alb = base * (1 - 0.45 * grime) * (1 - 0.35 * streaks)
    alb = alb * (0.88 + 0.12 * hgt)
    rust = np.clip(streaks * 1.2 + grime * 0.6 - 0.35, 0, 1)
    rgb = np.dstack([alb, alb, alb])
    rust_col = np.array([0.45, 0.24, 0.12])
    rgb = rgb * (1 - rust[..., None] * 0.7) + rust_col * rust[..., None] * 0.7 * alb[..., None]
    save(rgb, "container_albedo.png", "RGB")
    save(normal_from_height(hgt * 6.0, 1.0), "container_normal.png", "RGB")


# ---------- ground stamps ----------
def crack(seed, size=512):
    r = np.random.default_rng(seed)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)

    def branch(x, y, ang, length, width, depth):
        pts = [(x, y)]
        for k in range(int(length / 8)):
            ang += r.normal(0, 0.35)
            x += np.cos(ang) * 8
            y += np.sin(ang) * 8
            pts.append((x, y))
            if depth < 3 and r.random() < 0.07:
                branch(x, y, ang + r.choice([-1, 1]) * r.uniform(0.5, 1.2), length * 0.5, max(1, width * 0.6), depth + 1)
        d.line(pts, fill=255, width=int(max(1, width)))

    c = size / 2
    for k in range(r.integers(3, 6)):
        branch(c, c, r.uniform(0, 2 * np.pi), r.uniform(size * 0.25, size * 0.45), r.uniform(3, 6), 0)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(img) / 255.0
    halo = np.asarray(img.filter(ImageFilter.GaussianBlur(10))) / 255.0
    return np.clip(a + halo * 0.6, 0, 1)


def blob(seed, size, rough, base=0.0):
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    rad = np.sqrt(xx ** 2 + yy ** 2)
    ang = np.arctan2(yy, xx)
    wob = 0.3 + 0.035 * np.sin(ang * 2 + r.uniform(0, 6)) + 0.015 * np.sin(ang * 5 + r.uniform(0, 6))
    n = noise(size, size, size / 6, seed=seed)
    m = np.clip((wob - rad) / 0.06 + (n - 0.5) * rough * 2.5, 0, 1)
    return np.clip(m, 0, 1)


def tyre(seed, curved):
    W, H = 1024, 256
    r = np.random.default_rng(seed)
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for track in [-38, 38]:
        pts = []
        for i in range(0, W + 1, 16):
            t = i / W
            off = (np.sin(t * np.pi) * 60 if curved else 0) + track
            pts.append((i, H / 2 + off))
        d.line(pts, fill=255, width=26)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(2))) / 255.0
    tread = 0.75 + 0.25 * ((np.arange(W)[None, :] // 9) % 2)
    fade = np.clip(np.sin(np.linspace(0, np.pi, W)) * 1.6, 0, 1)[None, :]
    n = noise(H, W, 40, seed=seed)
    return a * tread * fade * (0.6 + 0.4 * n)


def stamps():
    for i in range(4):
        save(crack(10 + i), f"crack_{i}.png")
    for i in range(3):
        save(blob(20 + i, 256, 1.6), f"oil_{i}.png")
    for i in range(3):
        save(blob(30 + i, 512, 1.2), f"puddle_{i}.png")
    save(tyre(40, False), "tyre_0.png")
    save(tyre(41, True), "tyre_1.png")
    s = 512
    yy, xx = np.mgrid[0:s, 0:s] / s - 0.5
    rad = np.sqrt(xx ** 2 + yy ** 2)
    n = noise(s, s, 60, seed=50)
    scorch = np.clip(1 - rad / 0.45 + (n - 0.5) * 0.8, 0, 1) ** 1.4
    save(scorch, "scorch_ground.png")


# ---------- ramp ----------
def ramp():
    W, H = 512, 1024
    y, x = np.mgrid[0:H, 0:W].astype(float)
    # diamond plate: raised lozenges in a staggered grid
    u = (x / 26.0 + (np.floor(y / 26.0) % 2) * 0.5) % 1.0 - 0.5
    v = (y / 26.0) % 1.0 - 0.5
    d1 = np.abs(u * 0.9 + v * 0.45)
    d2 = np.abs(u * 0.9 - v * 0.45)
    lozenge = np.clip(0.18 - np.maximum(np.abs(u) * 0.35 + np.abs(v) * 0.05, 0) * 1.0, 0, 1)
    hgt = np.clip((0.12 - np.abs((u + v) * 0.5)) * 8, 0, 1) * np.clip((0.4 - np.abs(u - v)) * 4, 0, 1)
    base = 0.55 + 0.12 * noise(H, W, 80, seed=60)
    wear = noise(H, W, 30, seed=61)
    alb = base * (0.85 + 0.25 * hgt) * (0.8 + 0.2 * wear)
    rgb = np.dstack([alb, alb * 0.98, alb * 0.95])
    # hazard band along the top (the lip) and bottom edge
    for y0, y1 in [(0, 90), (H - 60, H)]:
        band = (y >= y0) & (y < y1)
        stripe = ((x + y) // 46) % 2 == 0
        col_y = np.array([0.95, 0.72, 0.08])
        col_k = np.array([0.06, 0.06, 0.06])
        rgb[band & stripe] = col_y * (0.8 + 0.2 * wear[band & stripe])[:, None]
        rgb[band & ~stripe] = col_k
        hgt[band] = 0.0
    dirt = np.clip(noise(H, W, 50, seed=62) - 0.45, 0, 1) * 1.4
    rgb = rgb * (1 - dirt[..., None] * 0.45) + np.array([0.35, 0.28, 0.2]) * dirt[..., None] * 0.45
    save(rgb, "ramp_albedo.png", "RGB")
    save(normal_from_height(hgt * 3.0, 1.0), "ramp_normal.png", "RGB")


def cloud_noise():
    """Tileable cloud noise (fbm-like spectrum from filtered random phases), two independent channels."""
    N = 512
    out = []
    for seed in (70, 71):
        r = np.random.default_rng(seed)
        f = np.fft.fftfreq(N)
        fx, fy = np.meshgrid(f, f)
        k = np.sqrt(fx ** 2 + fy ** 2)
        k[0, 0] = 1
        spec = (r.normal(size=(N, N)) + 1j * r.normal(size=(N, N))) / k ** 1.7
        spec[0, 0] = 0
        spec[k > 0.25] *= 0.3
        img = np.real(np.fft.ifft2(spec))
        img = (img - img.min()) / (img.max() - img.min())
        out.append(img)
    rgb = np.dstack([out[0], out[1], np.zeros_like(out[0])])
    save(rgb, "cloud_noise.png", "RGB")


container()
stamps()
ramp()
cloud_noise()
print("done", sorted(os.listdir(OUT)))
