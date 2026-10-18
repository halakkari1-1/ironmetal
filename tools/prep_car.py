"""Prepare a Meshy car GLB for the game: geometry untouched, textures re-encoded per role
(colour 1024, normal and metal/rough 512, JPEG), then wrapped as a base64 script so it loads
from file:// and from hosts that will not serve .glb.

Usage: python3 -I tools/prep_car.py in.glb <car_id>   -> assets/models/<car_id>.glb and .js
"""
import base64, io, json, struct, sys, os
from PIL import Image

src, cid = sys.argv[1], sys.argv[2]
out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'models')
raw = open(src, 'rb').read()
jl = struct.unpack('<I', raw[12:16])[0]
j = json.loads(raw[20:20 + jl])
binc = raw[20 + jl + 8:]

size_for = {}  # image index -> size
for m in j.get('materials', []):
    pbr = m.get('pbrMetallicRoughness', {})
    for key, sz in (('baseColorTexture', 1024), ('metallicRoughnessTexture', 512)):
        if key in pbr: size_for[j['textures'][pbr[key]['index']]['source']] = sz
    if 'normalTexture' in m: size_for[j['textures'][m['normalTexture']['index']]['source']] = 512
img_views = {im['bufferView']: i for i, im in enumerate(j.get('images', []))}
new_bin, views = b'', []
for vi, bv in enumerate(j['bufferViews']):
    data = binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
    if vi in img_views:
        ii = img_views[vi]; sz = size_for.get(ii, 512)
        im = Image.open(io.BytesIO(data)).convert('RGB').resize((sz, sz), Image.LANCZOS)
        o = io.BytesIO(); im.save(o, 'JPEG', quality=86 if sz >= 1024 else 90); data = o.getvalue()
        j['images'][ii]['mimeType'] = 'image/jpeg'
    nbv = dict(bv); nbv['byteOffset'] = len(new_bin); nbv['byteLength'] = len(data); views.append(nbv)
    new_bin += data + b'\0' * ((-len(data)) % 4)
j['bufferViews'] = views; j['buffers'] = [{'byteLength': len(new_bin)}]
js = json.dumps(j, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4)
total = 28 + len(js) + len(new_bin)
glb = struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(new_bin), 0x004E4942) + new_bin
open(os.path.join(out_dir, f'{cid}.glb'), 'wb').write(glb)
open(os.path.join(out_dir, f'{cid}.js'), 'w').write(f"(window.__GLB=window.__GLB||{{}})['{cid}']='{base64.b64encode(glb).decode()}';\n")
print(cid, f'{len(raw)/1e6:.1f} MB -> {total/1e6:.2f} MB')
