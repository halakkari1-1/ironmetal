#!/usr/bin/env python3
"""Splits a Meshy .glb (one mesh, one material, textures embedded) into what the game loads for the high tier:

    <out>.glb            the mesh alone, untouched: every vertex and triangle of the original
    <out>_albedo.jpg     base colour, at its original size
    <out>_normal.jpg     normal map, at its original size
    <out>_orm.jpg        roughness in green, metal in blue, at its original size

Nothing is resized or simplified. The colour map arrives as a PNG of 20 MB or more; it is saved as a JPEG at
quality 95, which cannot be told apart from it once the engine has compressed the texture for the graphics chip.
The textures live outside the model so the repository does not carry them twice (Godot would otherwise unpack a
second copy next to the .glb).

Usage:  python3 tools/models/split_glb.py <source.glb> <out path without extension>
Needs Pillow.
"""
import io
import json
import struct
import sys
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


def main(src: str, out: str) -> None:
    with open(src, "rb") as f:
        magic, version, _total = struct.unpack("<4sII", f.read(12))
        if magic != b"glTF" or version != 2:
            sys.exit("not a glTF 2 binary: " + src)
        n, kind = struct.unpack("<II", f.read(8))
        doc = json.loads(f.read(n))
        n, kind = struct.unpack("<II", f.read(8))
        blob = f.read(n)
    views = doc["bufferViews"]

    def image(tex_ref):
        if tex_ref is None:
            return None
        img = doc["images"][doc["textures"][tex_ref["index"]]["source"]]
        v = views[img["bufferView"]]
        o = v.get("byteOffset", 0)
        return Image.open(io.BytesIO(blob[o:o + v["byteLength"]])).convert("RGB")

    mat = doc["materials"][0]
    pbr = mat.get("pbrMetallicRoughness", {})
    maps = {"albedo": image(pbr.get("baseColorTexture")), "normal": image(mat.get("normalTexture")),
            "orm": image(pbr.get("metallicRoughnessTexture"))}
    for name, im in maps.items():
        if im is None:
            sys.exit("%s: no %s map" % (src, name))
        im.save("%s_%s.jpg" % (out, name), quality=95, subsampling=0 if name == "normal" else 2, optimize=True)

    # the mesh alone: drop the images and every buffer view only they used, and close the gaps in the buffer
    image_views = {img["bufferView"] for img in doc.get("images", []) if "bufferView" in img}
    new_blob = bytearray()
    remap = {}
    new_views = []
    for i, v in enumerate(views):
        if i in image_views:
            continue
        o = v.get("byteOffset", 0)
        while len(new_blob) % 4:
            new_blob.append(0)
        nv = dict(v)
        nv["byteOffset"] = len(new_blob)
        new_blob += blob[o:o + v["byteLength"]]
        remap[i] = len(new_views)
        new_views.append(nv)
    while len(new_blob) % 4:
        new_blob.append(0)
    for a in doc["accessors"]:
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
    doc["bufferViews"] = new_views
    doc["buffers"] = [{"byteLength": len(new_blob)}]
    for key in ("images", "textures", "samplers"):
        doc.pop(key, None)
    for m in doc["materials"]:
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(key, None)
        p = m.get("pbrMetallicRoughness", {})
        p.pop("baseColorTexture", None)
        p.pop("metallicRoughnessTexture", None)
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(out + ".glb", "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(new_blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(new_blob), 0x004E4942))
        f.write(new_blob)
    tris = sum(doc["accessors"][p["indices"]]["count"] // 3 for me in doc["meshes"] for p in me["primitives"])
    print("%s: %d triangles, maps %s" % (out, tris, {k: v.size for k, v in maps.items()}))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
