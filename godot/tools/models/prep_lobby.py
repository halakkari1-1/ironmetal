#!/usr/bin/env python3
"""Prepares the 3D lobby's models (Meshy .glb, one mesh and one material each) for the game:

    assets/lobby/<name>.glb            the mesh alone, every triangle of the original (Godot builds its own
                                       levels of detail on import)
    assets/lobby/<name>_albedo.jpg     colour map, 4096 px (2048 for the small props)
    assets/lobby/<name>_normal.jpg     normal map, 2048 px
    assets/lobby/<name>_orm.jpg        roughness (G) and metal (B), 2048 px
    assets/lobby/lo/<name>_*.jpg       the same three maps at 1024 px, for the medium and low tiers

A file that holds several objects side by side (the four flood lights) is cut into one model per object:
its pieces are grouped by where they stand, and each group keeps the shared maps.

Usage, from the godot/ folder:   python3 tools/models/prep_lobby.py <folder with the Meshy .glb files>
Needs numpy and Pillow.
"""
import glob
import io
import json
import os
import struct
import sys
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

# source file (prefix) -> name in the game, colour map size, how many objects it holds
MODELS = [
    ("Meshy_AI_1_", "platform", 4096, 1),
    ("Meshy_AI_Infernal_Foundry", "foundry", 4096, 1),
    ("Meshy_AI_Industrial_Nightspan", "bridge", 4096, 1),
    ("Meshy_AI_Iron_Outpost_at_Midnight", "outpost", 4096, 1),
    ("Meshy_AI_Industrial_Beacons", "beacon", 2048, 4),
    ("Meshy_AI_Ember_Cliffs", "cliffs", 4096, 1),
]
CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load(path):
    with open(path, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<II", f.read(8))
        doc = json.loads(f.read(n))
        n, _ = struct.unpack("<II", f.read(8))
        blob = f.read(n)

    def acc(i):
        a = doc["accessors"][i]
        v = doc["bufferViews"][a["bufferView"]]
        dt = np.dtype(CT[a["componentType"]])
        c = NC[a["type"]]
        o = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = v.get("byteStride", 0) or dt.itemsize * c
        if stride == dt.itemsize * c:
            return np.frombuffer(blob, dt, a["count"] * c, o).reshape(a["count"], c).copy()
        raw = np.frombuffer(blob, np.uint8, stride * (a["count"] - 1) + dt.itemsize * c, o)
        idx = np.arange(a["count"])[:, None] * stride + np.arange(dt.itemsize * c)[None, :]
        return raw[idx].copy().view(dt).reshape(a["count"], c)

    pr = doc["meshes"][0]["primitives"][0]
    at = pr["attributes"]
    mesh = {"pos": acc(at["POSITION"]).astype(np.float32), "nrm": acc(at["NORMAL"]).astype(np.float32),
            "uv": acc(at["TEXCOORD_0"]).astype(np.float32), "tri": acc(pr["indices"]).reshape(-1, 3).astype(np.uint32)}
    mat = doc["materials"][0]
    pbr = mat.get("pbrMetallicRoughness", {})

    def image(ref):
        img = doc["images"][doc["textures"][ref["index"]]["source"]]
        v = doc["bufferViews"][img["bufferView"]]
        o = v.get("byteOffset", 0)
        return Image.open(io.BytesIO(blob[o:o + v["byteLength"]])).convert("RGB")

    maps = {"albedo": image(pbr["baseColorTexture"]), "normal": image(mat["normalTexture"]),
            "orm": image(pbr["metallicRoughnessTexture"])}
    return mesh, maps


def write_glb(path, pos, nrm, uv, tri):
    parts = [pos.astype(np.float32).tobytes(), nrm.astype(np.float32).tobytes(), uv.astype(np.float32).tobytes(),
             tri.astype(np.uint32).tobytes()]
    blob = bytearray()
    views = []
    for i, p in enumerate(parts):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(p), "target": 34963 if i == 3 else 34962})
        blob += p
    while len(blob) % 4:
        blob.append(0)
    doc = {
        "asset": {"version": "2.0", "generator": "prep_lobby.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": os.path.basename(path)[:-4]}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": "lobby"}],
        "buffers": [{"byteLength": len(blob)}], "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125, "count": tri.size, "type": "SCALAR"},
        ],
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 28 + len(js) + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def pieces(mesh):
    """Connected pieces (vertices welded by position): an id per triangle."""
    key = np.round(mesh["pos"] * 2000).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.ravel()
    parent = np.arange(weld.max() + 1)

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    t = weld[mesh["tri"]]
    for a, b in ((0, 1), (1, 2)):
        for u, v in zip(t[:, a], t[:, b]):
            ru, rv = find(u), find(v)
            if ru != rv:
                parent[ru] = rv
    roots = np.array([find(x) for x in range(len(parent))])
    return roots[t[:, 0]]


def split(mesh, count):
    """Cuts a file holding `count` objects side by side into one triangle set per object, left to right."""
    tri = mesh["tri"]
    cen = mesh["pos"][tri].mean(1)
    pid = pieces(mesh)
    ids, inv = np.unique(pid, return_inverse=True)
    pc = np.zeros((len(ids), 2))
    w = np.bincount(inv).astype(float)
    pc[:, 0] = np.bincount(inv, cen[:, 0]) / w
    pc[:, 1] = np.bincount(inv, cen[:, 2]) / w
    # k-means on the pieces' positions (weighted by size), started from evenly spread x
    lo, hi = pc[:, 0].min(), pc[:, 0].max()
    c = np.stack([np.linspace(lo, hi, count), np.zeros(count)], 1)
    for _ in range(60):
        lab = np.argmin(((pc[:, None, :] - c[None]) ** 2).sum(-1), 1)
        for k in range(count):
            m = lab == k
            if m.any():
                c[k] = (pc[m] * w[m, None]).sum(0) / w[m].sum()
    order = np.argsort(c[:, 0])
    return [lab[inv] == k for k in order]


def subset(mesh, mask):
    tri = mesh["tri"][mask]
    used, remap = np.unique(tri, return_inverse=True)
    return mesh["pos"][used], mesh["nrm"][used], mesh["uv"][used], remap.reshape(-1, 3).astype(np.uint32)


def main(src_dir):
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.normpath(os.path.join(here, "..", "..", "assets", "lobby"))
    os.makedirs(os.path.join(out, "lo"), exist_ok=True)
    for prefix, name, size, count in MODELS:
        files = sorted(glob.glob(os.path.join(src_dir, prefix + "*.glb")))
        if not files:
            print("missing", prefix)
            continue
        mesh, maps = load(files[-1])
        for kind, im in maps.items():
            s = size if kind == "albedo" else min(size, 2048)
            im.resize((s, s), Image.LANCZOS).save(os.path.join(out, "%s_%s.jpg" % (name, kind)), quality=92, optimize=True)
            im.resize((1024, 1024), Image.LANCZOS).save(os.path.join(out, "lo", "%s_%s.jpg" % (name, kind)), quality=90, optimize=True)
        if count == 1:
            write_glb(os.path.join(out, name + ".glb"), mesh["pos"], mesh["nrm"], mesh["uv"], mesh["tri"])
            print(name, len(mesh["tri"]), "triangles")
        else:
            for k, mask in enumerate(split(mesh, count)):
                p, n, uv, t = subset(mesh, mask)
                c = p.mean(0)
                p = p - np.array([c[0], p[:, 1].min(), c[2]], np.float32)   # each object stands on its own origin
                write_glb(os.path.join(out, "%s%d.glb" % (name, k + 1)), p, n, uv, t)
                print("%s%d" % (name, k + 1), len(t), "triangles, size", (p.max(0) - p.min(0)).round(3))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
