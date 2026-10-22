"""Reads a <id>.bin vertex/triangle dump (from the autotest dumpmesh) into numpy arrays."""
import struct
import numpy as np


def load(path):
    d = open(path, "rb").read()
    o = 0
    V, T = [], []
    base = 0
    while o < len(d):
        nv, ni = struct.unpack_from("<II", d, o); o += 8
        v = np.frombuffer(d, dtype="<f4", count=nv * 3, offset=o).reshape(-1, 3); o += nv * 12
        t = np.frombuffer(d, dtype="<u4", count=ni, offset=o).reshape(-1, 3); o += ni * 4
        V.append(v); T.append(t + base); base += nv
    return np.vstack(V), np.vstack(T)
