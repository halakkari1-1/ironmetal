"""Decimate a single-mesh textured GLB by vertex clustering and shrink its textures.

Usage: python3 -I decimate_glb.py in.glb out.glb GRID TEXSIZE
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

src, dst, grid, texsize = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

raw = open(src, 'rb').read()
jl = struct.unpack('<I', raw[12:16])[0]
j = json.loads(raw[20:20 + jl])
bin_off = 20 + jl + 8
binc = raw[bin_off:]

CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}

def acc(i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    n = NC[a['type']]; dt = CT[a['componentType']]
    arr = np.frombuffer(binc, dt, a['count'] * n, off)
    return arr.reshape(-1, n) if n > 1 else arr

prim = j['meshes'][0]['primitives'][0]
P = acc(prim['attributes']['POSITION']).astype(np.float64)
N = acc(prim['attributes']['NORMAL']).astype(np.float64)
UV = acc(prim['attributes']['TEXCOORD_0']).astype(np.float64)
I = acc(prim['indices']).astype(np.int64).reshape(-1, 3)

lo, hi = P.min(0), P.max(0)
cell = (hi - lo).max() / grid
q = np.floor((P - lo) / cell).astype(np.int64)
uq = np.floor(UV * 48).astype(np.int64)
key = np.concatenate([q, uq], 1)
_, cid = np.unique(key, axis=0, return_inverse=True)
cid = cid.ravel()
nc = cid.max() + 1
cnt = np.bincount(cid, minlength=nc)[:, None]
def avg(A):
    out = np.zeros((nc, A.shape[1]))
    for k in range(A.shape[1]):
        out[:, k] = np.bincount(cid, A[:, k], nc)
    return out / cnt
P2, UV2, N2 = avg(P), avg(UV), avg(N)
N2 /= np.linalg.norm(N2, axis=1, keepdims=True) + 1e-12

T = cid[I]
ok = (T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])
T = T[ok]
s = np.sort(T, 1)
_, first = np.unique(s, axis=0, return_index=True)
T = T[np.sort(first)]
used = np.unique(T)
remap = -np.ones(nc, np.int64); remap[used] = np.arange(len(used))
T = remap[T]; P2, UV2, N2 = P2[used], UV2[used], N2[used]
print(f'triangles {len(I)} -> {len(T)}, vertices {len(P)} -> {len(P2)}')

blobs, views, accs = [], [], []
def add(arr, comp, typ, target=None, minmax=False):
    b = arr.tobytes(); off = sum(len(x) for x in blobs)
    blobs.append(b + b'\0' * ((-len(b)) % 4))
    v = {'buffer': 0, 'byteOffset': off, 'byteLength': len(b)}
    if target: v['target'] = target
    views.append(v)
    if comp is None: return len(views) - 1
    a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': len(arr), 'type': typ}
    if minmax: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
    accs.append(a); return len(accs) - 1

ap = add(P2.astype(np.float32), 5126, 'VEC3', 34962, True)
an = add(N2.astype(np.float32), 5126, 'VEC3', 34962)
au = add(UV2.astype(np.float32), 5126, 'VEC2', 34962)
ai = add(T.astype(np.uint32).ravel(), 5125, 'SCALAR', 34963)

images = []
for im in j.get('images', []):
    bv = j['bufferViews'][im['bufferView']]
    data = binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
    img = Image.open(io.BytesIO(data)).convert('RGB')
    img = img.resize((texsize, texsize), Image.LANCZOS)
    out = io.BytesIO(); img.save(out, 'JPEG', quality=85)
    images.append({'bufferView': add(np.frombuffer(out.getvalue(), np.uint8), None, None), 'mimeType': 'image/jpeg'})

buf = b''.join(blobs)
nj = {
    'asset': {'version': '2.0', 'generator': 'decimate_glb.py'},
    'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0, 'name': 'car_body'}],
    'meshes': [{'name': 'car_body', 'primitives': [{'attributes': {'POSITION': ap, 'NORMAL': an, 'TEXCOORD_0': au}, 'indices': ai, 'material': 0}]}],
    'materials': j['materials'], 'textures': j.get('textures', []), 'samplers': j.get('samplers', []),
    'images': images, 'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(buf)}],
}
js = json.dumps(nj).encode(); js += b' ' * ((-len(js)) % 4)
total = 12 + 8 + len(js) + 8 + len(buf)
with open(dst, 'wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, total))
    f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
    f.write(struct.pack('<II', len(buf), 0x004E4942)); f.write(buf)
print(f'size {total / 1e6:.2f} MB')
