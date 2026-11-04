"""Second half of the skyline building baker (first half: godot/tools_lowpoly.gd writes <id>.bin: the simplified
building with a fresh UV layout). Paints the new textures from the original model: every texel of the new layout
is placed on the simplified surface, the nearest point of the original surface facing the same way is found, and
the original texture is sampled there. Gaps round the UV islands are filled outwards so mipmaps don't bleed.
Writes godot/assets/buildings/lo/<id>.obj, <id>_albedo.png and <id>_orm.png (converted to JPG for the game).

usage: python3 bake.py <buildings glb dir> <bin dir> <out dir> [texture size] [suffix]
"""
import io
import json
import struct
import sys

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

IDS = ["skyscraper", "spire", "ascent", "refinery", "foundry"]


def glb(path):
    d = open(path, "rb").read()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    binoff = 20 + n + 8

    def view(i):
        bv = j["bufferViews"][i]
        o = binoff + bv.get("byteOffset", 0)
        return d[o:o + bv["byteLength"]]

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        comp = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
        w = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        off = binoff + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        x = np.frombuffer(d, comp, a["count"] * w, off)
        return x.reshape(a["count"], w) if w > 1 else x

    def tex(info):
        img = j["images"][j["textures"][info["index"]]["source"]]
        return np.asarray(Image.open(io.BytesIO(view(img["bufferView"]))).convert("RGB"), dtype=np.float32) / 255

    p = j["meshes"][0]["primitives"][0]
    m = j["materials"][p.get("material", 0)]
    pbr = m["pbrMetallicRoughness"]
    return (acc(p["attributes"]["POSITION"]).astype(np.float64), acc(p["attributes"]["NORMAL"]).astype(np.float64),
            acc(p["attributes"]["TEXCOORD_0"]).astype(np.float64), acc(p["indices"]).astype(np.int64).reshape(-1, 3),
            tex(pbr["baseColorTexture"]), tex(pbr["metallicRoughnessTexture"]))


def readbin(path):
    d = open(path, "rb").read()
    nv = struct.unpack("<I", d[:4])[0]
    a = np.frombuffer(d, np.float32, nv * 8, 4).reshape(-1, 8).astype(np.float64)
    o = 4 + nv * 32
    nt = struct.unpack("<I", d[o:o + 4])[0]
    T = np.frombuffer(d, np.uint32, nt * 3, o + 4).reshape(-1, 3).astype(np.int64)
    return a[:, :3], a[:, 3:6], a[:, 6:8], T


def bilinear(img, uv):
    h, w, _ = img.shape
    x = (uv[:, 0] % 1.0) * w - 0.5
    y = (uv[:, 1] % 1.0) * h - 0.5
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int)
    fx = (x - x0)[:, None]; fy = (y - y0)[:, None]
    x0 %= w; y0 %= h; x1 = (x0 + 1) % w; y1 = (y0 + 1) % h
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy) + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)


def surface_samples(P, N, UV, F, spacing):
    """Points spread over the original surface about `spacing` apart, with their UV and face normal."""
    A, B, C = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    fn = np.cross(B - A, C - A)
    area = np.linalg.norm(fn, axis=1) / 2
    fn /= (2 * area[:, None] + 1e-18)
    k = np.clip(np.ceil(area / spacing ** 2).astype(int), 1, 64)
    tri = np.repeat(np.arange(len(F)), k)
    rng = np.random.default_rng(1)
    r1 = np.sqrt(rng.random(len(tri))); r2 = rng.random(len(tri))
    w0, w1, w2 = 1 - r1, r1 * (1 - r2), r1 * r2
    # always include the centroid of every face, so thin ones are never missed
    tri = np.concatenate([tri, np.arange(len(F))])
    w0 = np.concatenate([w0, np.full(len(F), 1 / 3)]); w1 = np.concatenate([w1, np.full(len(F), 1 / 3)]); w2 = np.concatenate([w2, np.full(len(F), 1 / 3)])
    f = F[tri]
    pts = P[f[:, 0]] * w0[:, None] + P[f[:, 1]] * w1[:, None] + P[f[:, 2]] * w2[:, None]
    uvs = UV[f[:, 0]] * w0[:, None] + UV[f[:, 1]] * w1[:, None] + UV[f[:, 2]] * w2[:, None]
    return pts, uvs, fn[tri]


def rasterize(V, N, U, T, size):
    """Every texel covered by a triangle of the new layout: its 3D position and the triangle's normal."""
    pos = np.zeros((size, size, 3)); nor = np.zeros((size, size, 3)); hit = np.zeros((size, size), bool)
    px = U * size - 0.5
    fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-18
    for t in range(len(T)):
        a, b, c = px[T[t, 0]], px[T[t, 1]], px[T[t, 2]]
        x0 = max(0, int(np.floor(min(a[0], b[0], c[0]))) - 1); x1 = min(size - 1, int(np.ceil(max(a[0], b[0], c[0]))) + 1)
        y0 = max(0, int(np.floor(min(a[1], b[1], c[1]))) - 1); y1 = min(size - 1, int(np.ceil(max(a[1], b[1], c[1]))) + 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        q = np.stack([gx.ravel(), gy.ravel()], 1).astype(np.float64)
        v0, v1, v2 = b - a, c - a, q - a
        den = v0[0] * v1[1] - v1[0] * v0[1]
        if abs(den) < 1e-12:
            continue
        w1 = (v2[:, 0] * v1[1] - v1[0] * v2[:, 1]) / den
        w2 = (v0[0] * v2[:, 1] - v2[:, 0] * v0[1]) / den
        w0 = 1 - w1 - w2
        # a little outside the edges too (half a texel), so edge texels are filled by their own triangle
        e = 0.7 / max(1.0, np.sqrt(abs(den)))
        ins = (w0 >= -e) & (w1 >= -e) & (w2 >= -e)
        if not ins.any():
            continue
        qi = q[ins].astype(int)
        p3 = V[T[t, 0]] * w0[ins, None] + V[T[t, 1]] * w1[ins, None] + V[T[t, 2]] * w2[ins, None]
        free = ~hit[qi[:, 1], qi[:, 0]] | ((w0[ins] >= 0) & (w1[ins] >= 0) & (w2[ins] >= 0))
        qi, p3 = qi[free], p3[free]
        pos[qi[:, 1], qi[:, 0]] = p3
        nor[qi[:, 1], qi[:, 0]] = fn[t]
        hit[qi[:, 1], qi[:, 0]] = True
    return pos, nor, hit


def dilate(img, hit, steps):
    img = img.copy(); hit = hit.copy()
    for _ in range(steps):
        acc = np.zeros_like(img); cnt = np.zeros(hit.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            h2 = np.roll(np.roll(hit, dy, 0), dx, 1)
            acc += np.roll(np.roll(img, dy, 0), dx, 1) * h2[..., None]
            cnt += h2
        grow = (~hit) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow, None]
        hit |= grow
    return img


def main():
    src, bins, out = sys.argv[1:4]
    size = int(sys.argv[4]) if len(sys.argv) > 4 else 1024
    sfx = sys.argv[5] if len(sys.argv) > 5 else ""
    for id in IDS:
        P, N, UV, F, albedo, mr = glb(f"{src}/{id}.glb")
        V, VN, U, T = readbin(f"{bins}/{id}{sfx}.bin")
        ext = np.linalg.norm(P.max(0) - P.min(0))
        pts, uvs, pn = surface_samples(P, N, UV, F, ext / 900)
        tree = cKDTree(pts)
        pos, nor, hit = rasterize(V, VN, U, T, size)
        q = pos[hit]; qn = nor[hit]
        # godot winding is clockwise: its face normals point the other way from glTF's
        qn = -qn
        _, cand = tree.query(q, k=10)
        dist = np.linalg.norm(pts[cand] - q[:, None, :], axis=2)
        facing = np.abs(np.einsum("ij,ikj->ik", qn, pn[cand]))   # double-sided: either side of a wall counts
        score = dist * (1.0 + 3.0 * (1.0 - facing))
        best = cand[np.arange(len(q)), np.argmin(score, axis=1)]
        col = bilinear(albedo, uvs[best]); orm = bilinear(mr, uvs[best])
        A = np.zeros((size, size, 3)); A[hit] = col
        O = np.zeros((size, size, 3)); O[hit] = orm
        A = dilate(A, hit, 12); O = dilate(O, hit, 12)
        Image.fromarray((np.clip(A, 0, 1) * 255).astype(np.uint8)).save(f"{out}/{id}{sfx}_albedo.png", optimize=True)
        Image.fromarray((np.clip(O, 0, 1) * 255).astype(np.uint8)).save(f"{out}/{id}{sfx}_orm.png", optimize=True)
        with open(f"{out}/{id}{sfx}.obj", "w") as f:
            f.write("# %s.glb simplified to %d triangles with baked textures (tools/buildings)\n" % (id, len(T)))
            for v in V:
                f.write("v %.4f %.4f %.4f\n" % tuple(v))
            for u in U:
                f.write("vt %.6f %.6f\n" % (u[0], 1 - u[1]))
            for n in VN:
                f.write("vn %.4f %.4f %.4f\n" % tuple(n))
            for t in T:
                a, b, c = t + 1
                f.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (a, a, a, c, c, c, b, b, b))
        print(id, len(F), "->", len(T), "texels", int(hit.sum()), flush=True)


if __name__ == "__main__":
    main()
