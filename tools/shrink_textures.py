"""Re-encode every texture in a GLB at a smaller size, leaving geometry untouched.

Usage: python3 -I shrink_textures.py in.glb out.glb TEXSIZE
"""
import io, json, struct, sys
from PIL import Image

src, dst, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
raw = open(src, 'rb').read()
jl = struct.unpack('<I', raw[12:16])[0]
j = json.loads(raw[20:20 + jl])
binc = raw[20 + jl + 8:]

img_views = {im['bufferView']: i for i, im in enumerate(j.get('images', []))}
new_bin, new_views = b'', []
for vi, bv in enumerate(j['bufferViews']):
    off = bv.get('byteOffset', 0)
    data = binc[off:off + bv['byteLength']]
    if vi in img_views:
        im = Image.open(io.BytesIO(data)).convert('RGB')
        im = im.resize((size, size), Image.LANCZOS)
        out = io.BytesIO(); im.save(out, 'JPEG', quality=88)
        data = out.getvalue()
        j['images'][img_views[vi]]['mimeType'] = 'image/jpeg'
    nbv = dict(bv); nbv['byteOffset'] = len(new_bin); nbv['byteLength'] = len(data)
    new_views.append(nbv)
    new_bin += data + b'\0' * ((-len(data)) % 4)
j['bufferViews'] = new_views
j['buffers'] = [{'byteLength': len(new_bin)}]
js = json.dumps(j).encode(); js += b' ' * ((-len(js)) % 4)
total = 28 + len(js) + len(new_bin)
with open(dst, 'wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, total))
    f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
    f.write(struct.pack('<II', len(new_bin), 0x004E4942)); f.write(new_bin)
print(f'{len(raw) / 1e6:.2f} MB -> {total / 1e6:.2f} MB')
