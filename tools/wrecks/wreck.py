"""Low-poly wreck meshes from the game's cars: vertex clustering on a grid (merge every vertex in a cell, drop
the triangles that collapse), normals recomputed, written as OBJ for Godot. Burnt wrecks need no texture."""
import sys
import numpy as np
from load import load

SRC = "/tmp/claude-0/-home-claude/b2803c76-41b3-5f4f-a18f-3b6c823f2c66/scratchpad/mesh"


def simplify(V, T, cell):
    q = np.floor(V / cell).astype(np.int64)
    key = (q[:, 0] + 100000) * 10**10 + (q[:, 1] + 100000) * 10**5 + (q[:, 2] + 100000)
    uniq, inv = np.unique(key, return_inverse=True)
    NV = np.zeros((len(uniq), 3)); cnt = np.zeros(len(uniq))
    np.add.at(NV, inv, V); np.add.at(cnt, inv, 1)
    NV /= cnt[:, None]
    NT = inv[T]
    ok = (NT[:, 0] != NT[:, 1]) & (NT[:, 1] != NT[:, 2]) & (NT[:, 0] != NT[:, 2])
    NT = NT[ok]
    # drop duplicate triangles
    s = np.sort(NT, axis=1)
    _, idx = np.unique(s, axis=0, return_index=True)
    return NV, NT[np.sort(idx)]


def write_obj(path, V, T):
    # smooth normals (area weighted)
    fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    N = np.zeros_like(V)
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    # the dumped triangles are in Godot's winding (clockwise = front); OBJ wants counter-clockwise
    N = -N
    T = T[:, [0, 2, 1]]
    with open(path, "w") as f:
        for v in V:
            f.write("v %.4f %.4f %.4f\n" % tuple(v))
        for n in N:
            f.write("vn %.4f %.4f %.4f\n" % tuple(n))
        for t in T:
            a, b, c = t + 1
            f.write("f %d//%d %d//%d %d//%d\n" % (a, a, b, b, c, c))


for id_ in sys.argv[2:]:
    V, T = load(f"{SRC}/{id_}.bin")
    target = int(sys.argv[1])
    lo, hi = 0.005, 0.2
    for _ in range(18):
        mid = (lo + hi) / 2
        NV, NT = simplify(V, T, mid)
        if len(NT) > target:
            lo = mid
        else:
            hi = mid
    NV, NT = simplify(V, T, hi)
    write_obj(f"/home/claude/ironmetal/godot/assets/wrecks/wreck_{id_}.obj", NV, NT)
    print(id_, len(T), "->", len(NT), "cell %.3f" % hi)
