"""Offline copy of the game's engine model (scripts/core/sfx.gd): renders a run (idle, full throttle up through the
gears, lift off, slow down) for each recorded engine to an MP3 for listening on a phone.

usage: python3 demo.py <loops dir> <out dir>
"""
import math
import os
import subprocess
import sys
import wave

import numpy as np

RATE = 44100
REV = {
    "lfa": {"rpms": [1400, 2600, 3800, 5000, 6300, 7600, 8800], "idle": 780.0, "top": 8600.0, "gears": [0.16, 0.31, 0.47, 0.63, 0.8, 1.0]},
    "f136": {"rpms": [1400, 2600, 3800, 5000, 6300, 7600, 8800], "idle": 1010.0, "top": 8600.0, "gears": [0.16, 0.31, 0.47, 0.63, 0.8, 1.0]},
    "ls": {"rpms": [1000, 1800, 2600, 3500, 4400, 5300, 6300], "idle": 640.0, "top": 6200.0, "gears": [0.17, 0.35, 0.55, 0.77, 1.0]},
    "c454": {"rpms": [1000, 1700, 2400, 3100, 3800, 4500, 5300], "idle": 950.0, "top": 5200.0, "gears": [0.18, 0.38, 0.6, 0.8, 1.0]},
    "m52": {"rpms": [1000, 1800, 2700, 3600, 4600, 5600, 6700], "idle": 900.0, "top": 6600.0, "gears": [0.16, 0.33, 0.52, 0.74, 1.0]},
    "radial": {"rpms": [900, 1250, 1600, 1950, 2300, 2650, 2950], "idle": 820.0, "top": 2900.0, "gears": [0.25, 0.5, 0.75, 1.0]},
}


def load(path):
    out = path[:-4] + ".wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, out], check=True)
    w = wave.open(out)
    a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
    os.remove(out)
    return a


def render(eid, src, tune=1.0):
    c = REV[eid]
    on = [(c["idle"], load(f"{src}/eng_{eid}_idle.ogg"))] + [(r, load(f"{src}/eng_{eid}_{r}_on.ogg")) for r in c["rpms"]]
    off = [(c["idle"], on[0][1])] + [(r, load(f"{src}/eng_{eid}_{r}_off.ogg")) for r in c["rpms"]]
    voices = [on[0]] + on[1:] + off[1:]
    phase = [np.random.rand() * len(v[1]) for v in voices]
    n = len(on)
    gear, rpm_n, load_amt, shift_t, sp = 1, 0.0, 0.0, 0.0, 0.0
    out = []
    ctl = 60
    total = 9.0
    for k in range(int(total * ctl)):
        t = k / ctl
        th = 1.0 if 1.0 < t < 6.0 else 0.0
        sp = min(1.0, max(0.0, sp + (0.22 if th else -0.3) / ctl))
        b = c["gears"]
        while gear < len(b) and sp > b[gear - 1]:
            gear += 1
            shift_t = 0.18
        while gear > 1 and sp < b[gear - 2] * 0.85:
            gear -= 1
        lo = b[gear - 2] if gear > 1 else 0.0
        frac = min(1.1, max(0.0, (sp - lo) / (b[gear - 1] - lo)))
        target = (0.08 + 0.92 * frac) if gear == 1 else (0.45 + 0.55 * frac)
        if sp < 0.03 and th < 0.1:
            target = 0.0
        shift_t -= 1 / ctl
        tht = 0.0 if shift_t > 0 else th
        rate = 3.2 if target < rpm_n else 1.4
        rpm_n += max(-rate / ctl, min(rate / ctl, target - rpm_n))
        load_amt += (tht - load_amt) * min(1.0, 10 / ctl)
        rpm = c["idle"] * (c["top"] / c["idle"]) ** rpm_n
        vol = 0.75 if shift_t > 0 else 1.0
        w = [0.0] * n
        if rpm <= on[0][0]:
            w[0] = 1
        elif rpm >= on[-1][0]:
            w[-1] = 1
        else:
            for i in range(n - 1):
                r0, r1 = on[i][0], on[i + 1][0]
                if r0 <= rpm < r1:
                    x = (math.log(rpm) - math.log(r0)) / (math.log(r1) - math.log(r0))
                    w[i], w[i + 1] = math.cos(x * math.pi / 2), math.sin(x * math.pi / 2)
        gains = [w[0] * vol * 1.7] + [w[i] * math.sqrt(load_amt) * vol for i in range(1, n)] + [w[i] * math.sqrt(1 - load_amt) * vol for i in range(1, n)]
        pitches = [rpm * tune / v[0] for v in voices]
        L = RATE // ctl
        block = np.zeros(L)
        for j, v in enumerate(voices):
            idx = phase[j] + np.arange(L) * pitches[j]
            phase[j] = (phase[j] + L * pitches[j]) % len(v[1])
            if gains[j] < 0.004:
                continue
            data = v[1]
            i0 = np.floor(idx).astype(int) % len(data)
            fr = idx - np.floor(idx)
            block += gains[j] * (data[i0] * (1 - fr) + data[(i0 + 1) % len(data)] * fr)
        out.append(block)
    a = np.concatenate(out)
    a *= 0.9 / max(1e-6, np.abs(a).max())
    return a


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    names = {"m52": "ghost_inline6",
             "lfa": "sports_V10", "f136": "sports_V8", "ls": "police_V8", "c454": "rex_bigblock", "radial": "titan_tank_radial"}
    for eid, nm in names.items():
        a = render(eid, src)
        tmp = f"{dst}/{nm}.wav"
        w = wave.open(tmp, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((a * 32767).astype(np.int16).tobytes()); w.close()
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-b:a", "160k", f"{dst}/{nm}.mp3"], check=True)
        os.remove(tmp)
        print(nm)


if __name__ == "__main__":
    main()
