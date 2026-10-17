// All game sound is synthesized with the Web Audio API, so the game ships with no audio files.

let ctx = null, master = null, noiseBuf = null, enabled = true;
let engine = null;

function init() {
  if (ctx) return;
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  ctx = new AC();
  master = ctx.createGain();
  master.gain.value = enabled ? 0.7 : 0;
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -14; comp.ratio.value = 6;
  master.connect(comp); comp.connect(ctx.destination);
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
}

function noise(dur, { type = 'lowpass', freq = 1000, q = 1, gain = 0.5, attack = 0.002, sweepTo = null, delay = 0 } = {}) {
  const t = ctx.currentTime + delay;
  const src = ctx.createBufferSource(); src.buffer = noiseBuf;
  src.playbackRate.value = 0.8 + Math.random() * 0.4;
  const f = ctx.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
  if (sweepTo) f.frequency.exponentialRampToValueAtTime(sweepTo, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(gain, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f); f.connect(g); g.connect(master);
  src.start(t, Math.random()); src.stop(t + dur + 0.05);
}

function tone(freq, dur, { type = 'sine', gain = 0.3, to = null, delay = 0 } = {}) {
  const t = ctx.currentTime + delay;
  const o = ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(freq, t);
  if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(gain, t + 0.01);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g); g.connect(master); o.start(t); o.stop(t + dur + 0.05);
}

const ok = () => ctx && enabled && ctx.state === 'running';
let lastGun = 0;

export const sfx = {
  unlock() { init(); if (ctx && ctx.state !== 'running') ctx.resume(); },
  setEnabled(v) { enabled = v; if (master) master.gain.value = v ? 0.7 : 0; },
  click() { if (!ok()) return; tone(220, 0.06, { type: 'square', gain: 0.12, to: 110 }); noise(0.05, { type: 'highpass', freq: 3000, gain: 0.15 }); },
  confirm() { if (!ok()) return; tone(160, 0.12, { type: 'sawtooth', gain: 0.15, to: 320 }); tone(320, 0.18, { type: 'square', gain: 0.08, delay: 0.08 }); },
  denied() { if (!ok()) return; tone(140, 0.18, { type: 'square', gain: 0.15, to: 90 }); },
  purchase() { if (!ok()) return; [0, 0.07, 0.14].forEach((d, i) => tone(300 + i * 150, 0.15, { type: 'square', gain: 0.1, delay: d })); noise(0.3, { type: 'highpass', freq: 5000, gain: 0.08, delay: 0.1 }); },
  gun(vol = 1) {
    if (!ok()) return; const n = ctx.currentTime; if (n - lastGun < 0.045) return; lastGun = n;
    noise(0.07, { type: 'bandpass', freq: 1800, q: 0.8, gain: 0.35 * vol });
    tone(90, 0.06, { type: 'square', gain: 0.18 * vol, to: 50 });
  },
  rocket(vol = 1) { if (!ok()) return; noise(0.6, { type: 'bandpass', freq: 600, q: 1.2, gain: 0.4 * vol, attack: 0.03, sweepTo: 2500 }); tone(70, 0.2, { type: 'sawtooth', gain: 0.15 * vol, to: 40 }); },
  explosion(size = 1, vol = 1) {
    if (!ok()) return; const v = Math.min(1, vol);
    noise(1.4 * size, { type: 'lowpass', freq: 900, gain: 0.9 * v, attack: 0.005, sweepTo: 60 });
    noise(0.25, { type: 'highpass', freq: 2500, gain: 0.35 * v });
    tone(60, 0.9 * size, { type: 'sine', gain: 0.7 * v, to: 25 });
    noise(1.8 * size, { type: 'lowpass', freq: 300, gain: 0.25 * v, attack: 0.2, delay: 0.1 });
  },
  hit() { if (!ok()) return; noise(0.05, { type: 'highpass', freq: 4000, gain: 0.25 }); tone(1400, 0.04, { type: 'square', gain: 0.05, to: 700 }); },
  hurt() { if (!ok()) return; noise(0.15, { type: 'lowpass', freq: 500, gain: 0.4 }); tone(120, 0.12, { type: 'square', gain: 0.12, to: 70 }); },
  pickup() { if (!ok()) return; [0, 0.06, 0.12].forEach((d, i) => tone(520 * (1 + i * 0.26), 0.14, { type: 'triangle', gain: 0.18, delay: d })); },
  special() { if (!ok()) return; tone(80, 0.5, { type: 'sawtooth', gain: 0.2, to: 400 }); noise(0.5, { type: 'bandpass', freq: 400, gain: 0.3, sweepTo: 3000 }); },
  shield() { if (!ok()) return; tone(200, 0.6, { type: 'sine', gain: 0.25, to: 800 }); tone(400, 0.6, { type: 'triangle', gain: 0.1, to: 1200 }); },
  flame() { if (!ok()) return; noise(0.25, { type: 'bandpass', freq: 700, q: 0.6, gain: 0.25 }); },
  countdown(final) { if (!ok()) return; tone(final ? 880 : 440, final ? 0.5 : 0.18, { type: 'square', gain: 0.15 }); },
  win() { if (!ok()) return; [0, 0.15, 0.3, 0.5].forEach((d, i) => tone([262, 330, 392, 523][i], 0.4, { type: 'sawtooth', gain: 0.12, delay: d })); },
  lose() { if (!ok()) return; [0, 0.25, 0.5].forEach((d, i) => tone([220, 185, 147][i], 0.5, { type: 'sawtooth', gain: 0.12, delay: d })); },

  engineStart() {
    if (!ctx || engine) return;
    const o1 = ctx.createOscillator(), o2 = ctx.createOscillator();
    o1.type = 'sawtooth'; o2.type = 'square';
    const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 500;
    const g = ctx.createGain(); g.gain.value = 0;
    o1.connect(f); o2.connect(f); f.connect(g); g.connect(master);
    o1.start(); o2.start();
    engine = { o1, o2, f, g };
  },
  engineSet(throttle, speedFrac) {
    if (!engine) return;
    const t = ctx.currentTime;
    const base = 45 + speedFrac * 70 + throttle * 15;
    engine.o1.frequency.setTargetAtTime(base, t, 0.08);
    engine.o2.frequency.setTargetAtTime(base * 0.5, t, 0.08);
    engine.f.frequency.setTargetAtTime(300 + speedFrac * 900 + throttle * 300, t, 0.1);
    engine.g.gain.setTargetAtTime(enabled ? 0.05 + throttle * 0.05 : 0, t, 0.1);
  },
  engineStop() {
    if (!engine) return;
    const e = engine; engine = null;
    e.g.gain.setTargetAtTime(0, ctx.currentTime, 0.1);
    setTimeout(() => { try { e.o1.stop(); e.o2.stop(); } catch (_) { /* already stopped */ } }, 400);
  },
};
