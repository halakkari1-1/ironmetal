"""Turns engine-sim recordings into seamless game loops.

For each recording: skip the settling start, cut a whole number of engine cycles (one cycle = two crank turns),
crossfade the tail into the head so it loops without a click, even out loudness (loud stays louder, but the gap
is narrowed so quiet off-load and idle are still audible), and encode as Ogg Vorbis.

usage: python3 make_loops.py <in_dir> <out_dir> <prefix>
"""
import glob
import os
import subprocess
import sys
import wave

import numpy as np

RATE = 44100
LOOP_S = 1.6       # about this long
XFADE_S = 0.12
REF_RMS = 5200.0   # loudness the loops are pulled towards
SQUASH = 0.4       # 0 = all the same loudness, 1 = untouched


def read(path):
    w = wave.open(path)
    return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)


def make(a, rpm):
    a = a[int(0.35 * RATE):]
    cycle = 120.0 / max(rpm, 300) * RATE
    n = max(1, round(LOOP_S * RATE / cycle))
    L = int(round(n * cycle))
    X = int(XFADE_S * RATE)
    if L + X > len(a):
        L = len(a) - X - 1
    seg = a[:L + X].copy()
    # crossfade the extra tail over the head (equal power), then drop the tail
    t = np.linspace(0, 1, X)
    fade_in, fade_out = np.sin(t * np.pi / 2), np.cos(t * np.pi / 2)
    head = seg[:X] * fade_in + seg[L:L + X] * fade_out
    loop = np.concatenate([head, seg[X:L]])
    loop -= loop.mean()
    rms = np.sqrt((loop ** 2).mean()) + 1e-9
    target = REF_RMS * (rms / REF_RMS) ** SQUASH
    loop *= target / rms
    peak = np.abs(loop).max()
    if peak > 30000:
        loop *= 30000 / peak
    return loop.astype(np.int16)


def main():
    src, dst, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(dst, exist_ok=True)
    idle_rpm = float(sys.argv[4]) if len(sys.argv) > 4 else 800
    for f in sorted(glob.glob(os.path.join(src, "*.wav"))):
        name = os.path.basename(f)[:-4]
        rpm = idle_rpm if name == "idle" else int(name.split("_")[0])
        loop = make(read(f), rpm)
        tmp = os.path.join(dst, "_tmp.wav")
        w = wave.open(tmp, "wb")
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(loop.tobytes()); w.close()
        out_name = "eng_%s_%s.ogg" % (prefix, name.lstrip("0") if name != "idle" else "idle")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", os.path.join(dst, out_name)], check=True)
        os.remove(tmp)
        print(out_name, "rms %.0f" % np.sqrt((loop.astype(float) ** 2).mean()), "len %.2fs" % (len(loop) / RATE))


if __name__ == "__main__":
    main()
