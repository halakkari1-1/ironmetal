// All game audio is synthesized with the Web Audio API: sound effects and a procedural metal soundtrack.
// The game ships with no audio files.

let ctx = null, master = null, sfxBus = null, musicBus = null, reverb = null, noiseBuf = null;
let sfxOn = true, musicOn = true;
let vol = { master: 0.8, music: 0.6, sfx: 0.9 };
// Optional recorded track for the lobby: drop an MP3 at assets/music/lobby.mp3 and it replaces the synthesized riff there.
const TRACK_URL = new URL('../assets/music/lobby.mp3', import.meta.url).href;
let track = null, trackGain = null, trackReady = false;
let engine = null;

function makeCurve(k) {
  const n = 2048, c = new Float32Array(n), deg = Math.PI / 180;
  for (let i = 0; i < n; i++) { const x = (i * 2) / n - 1; c[i] = ((3 + k) * x * 20 * deg) / (Math.PI + k * Math.abs(x)); }
  return c;
}
let CURVE = null;

function init() {
  if (ctx) return;
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  ctx = new AC();
  master = ctx.createGain(); master.gain.value = vol.master;
  const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -12; comp.ratio.value = 5; comp.attack.value = 0.004; comp.release.value = 0.2;
  master.connect(comp); comp.connect(ctx.destination);
  sfxBus = ctx.createGain(); sfxBus.gain.value = sfxOn ? 0.85 * vol.sfx : 0; sfxBus.connect(master);
  musicBus = ctx.createGain(); musicBus.gain.value = 0; musicBus.connect(master);
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  // short room reverb from decaying noise
  const len = ctx.sampleRate * 1.4, ir = ctx.createBuffer(2, len, ctx.sampleRate);
  for (let ch = 0; ch < 2; ch++) { const b = ir.getChannelData(ch); for (let i = 0; i < len; i++) b[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 3); }
  reverb = ctx.createConvolver(); reverb.buffer = ir;
  const wet = ctx.createGain(); wet.gain.value = 0.22; reverb.connect(wet); wet.connect(master);
  CURVE = makeCurve(420);
  try {
    track = new Audio(); track.loop = true; track.preload = 'auto'; track.src = TRACK_URL;
    track.addEventListener('canplaythrough', () => { trackReady = true; if (music.playing && music.where === 'lobby') music.start(music.level, 'lobby'); }, { once: true });
    track.addEventListener('error', () => { trackReady = false; });
    trackGain = ctx.createGain(); trackGain.gain.value = 0;
    ctx.createMediaElementSource(track).connect(trackGain); trackGain.connect(musicBus);
  } catch (e) { track = null; }
}
const musicTarget = (level) => (musicOn ? level * vol.music * 1.4 : 0);

function noise(dur, { type = 'lowpass', freq = 1000, q = 1, gain = 0.5, attack = 0.002, sweepTo = null, delay = 0, out = null, rate = null } = {}) {
  const t = ctx.currentTime + delay;
  const src = ctx.createBufferSource(); src.buffer = noiseBuf;
  src.playbackRate.value = rate || 0.8 + Math.random() * 0.4;
  const f = ctx.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
  if (sweepTo) f.frequency.exponentialRampToValueAtTime(sweepTo, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(gain, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f); f.connect(g); g.connect(out || sfxBus);
  src.start(t, Math.random()); src.stop(t + dur + 0.05);
  return g;
}

function tone(freq, dur, { type = 'sine', gain = 0.3, to = null, delay = 0, out = null, attack = 0.01 } = {}) {
  const t = ctx.currentTime + delay;
  const o = ctx.createOscillator(); o.type = type; o.frequency.setValueAtTime(freq, t);
  if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(gain, t + attack);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g); g.connect(out || sfxBus); o.start(t); o.stop(t + dur + 0.05);
  return g;
}

// Distorted guitar. Each output/pan pair gets ONE shared amp chain (fuzz + speaker-cabinet filter);
// a note only adds three oscillators and an envelope, which keeps the CPU cost low on phones.
const amps = new Map();
function amp(out, pan) {
  const key = `${pan}|${out === musicBus ? 'm' : 's'}`;
  if (amps.has(key)) return amps.get(key);
  const input = ctx.createGain(); input.gain.value = 3.2;
  const shaper = ctx.createWaveShaper(); shaper.curve = CURVE; shaper.oversample = 'none';
  const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 100;
  const scoop = ctx.createBiquadFilter(); scoop.type = 'peaking'; scoop.frequency.value = 650; scoop.Q.value = 0.9; scoop.gain.value = -7;
  const cab = ctx.createBiquadFilter(); cab.type = 'lowpass'; cab.frequency.value = 3400; cab.Q.value = 0.8;
  const level = ctx.createGain(); level.gain.value = 0.16;
  input.connect(shaper); shaper.connect(hp); hp.connect(scoop); scoop.connect(cab); cab.connect(level);
  if (ctx.createStereoPanner) { const p = ctx.createStereoPanner(); p.pan.value = pan; level.connect(p); p.connect(out); } else level.connect(out);
  if (reverb) { const send = ctx.createGain(); send.gain.value = 0.18; level.connect(send); send.connect(reverb); }
  amps.set(key, input);
  return input;
}
function guitar(t, freq, dur, { muted = false, pan = 0, gain = 1, out = musicBus } = {}) {
  const env = ctx.createGain();
  const peak = (muted ? 0.55 : 0.8) * gain;
  env.gain.setValueAtTime(0.0001, t); env.gain.exponentialRampToValueAtTime(peak, t + 0.005);
  env.gain.setValueAtTime(peak, t + dur * 0.75); env.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  let last = env;
  if (muted) { const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 700; env.connect(lp); last = lp; }
  last.connect(amp(out, pan));
  for (const [m, det] of [[1, -6], [1.5, 0], [2, 5]]) {
    const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = freq * m; o.detune.value = det;
    o.connect(env); o.start(t); o.stop(t + dur + 0.02);
  }
}

function kick(t, out, g = 0.9) {
  const o = ctx.createOscillator(); o.type = 'sine';
  o.frequency.setValueAtTime(160, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.11);
  const e = ctx.createGain(); e.gain.setValueAtTime(g, t); e.gain.exponentialRampToValueAtTime(0.0001, t + 0.2);
  o.connect(e); e.connect(out); o.start(t); o.stop(t + 0.22);
  const c = ctx.createBufferSource(); c.buffer = noiseBuf; const f = ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = 3500;
  const ce = ctx.createGain(); ce.gain.setValueAtTime(g * 0.35, t); ce.gain.exponentialRampToValueAtTime(0.0001, t + 0.015);
  c.connect(f); f.connect(ce); ce.connect(out); c.start(t); c.stop(t + 0.03);
}
function snare(t, out, g = 0.55) {
  const src = ctx.createBufferSource(); src.buffer = noiseBuf;
  const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = 2200; f.Q.value = 0.7;
  const e = ctx.createGain(); e.gain.setValueAtTime(g, t); e.gain.exponentialRampToValueAtTime(0.0001, t + 0.18);
  src.connect(f); f.connect(e); e.connect(out); if (reverb) { const s = ctx.createGain(); s.gain.value = 0.5; e.connect(s); s.connect(reverb); }
  src.start(t, Math.random()); src.stop(t + 0.2);
  const o = ctx.createOscillator(); o.type = 'triangle'; o.frequency.setValueAtTime(220, t); o.frequency.exponentialRampToValueAtTime(160, t + 0.08);
  const oe = ctx.createGain(); oe.gain.setValueAtTime(g * 0.6, t); oe.gain.exponentialRampToValueAtTime(0.0001, t + 0.1);
  o.connect(oe); oe.connect(out); o.start(t); o.stop(t + 0.12);
}
function hat(t, out, g = 0.08, open = false) {
  const src = ctx.createBufferSource(); src.buffer = noiseBuf;
  const f = ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = 8000;
  const e = ctx.createGain(); e.gain.setValueAtTime(g, t); e.gain.exponentialRampToValueAtTime(0.0001, t + (open ? 0.25 : 0.035));
  src.connect(f); f.connect(e); e.connect(out); src.start(t, Math.random()); src.stop(t + 0.3);
}
function crash(t, out, g = 0.22) {
  const src = ctx.createBufferSource(); src.buffer = noiseBuf; src.playbackRate.value = 0.7;
  const f = ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = 4500;
  const e = ctx.createGain(); e.gain.setValueAtTime(g, t); e.gain.exponentialRampToValueAtTime(0.0001, t + 1.6);
  src.connect(f); f.connect(e); e.connect(out); if (reverb) e.connect(reverb); src.start(t, Math.random()); src.stop(t + 1.7);
}
function bass(t, freq, dur, out) {
  const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = freq / 2;
  const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 420;
  const sh = ctx.createWaveShaper(); sh.curve = makeCurve(30);
  const e = ctx.createGain(); e.gain.setValueAtTime(0.0001, t); e.gain.exponentialRampToValueAtTime(0.28, t + 0.01); e.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(sh); sh.connect(f); f.connect(e); e.connect(out); o.start(t); o.stop(t + dur + 0.02);
}

// ---------- the riff book ----------
// Each bar is 16 sixteenth-notes. A number is semitones above low E (82.4 Hz); 'm' suffix = palm mute; '-' holds; '.' rests.
const BARS = {
  A1: ['0m', '0m', '0m', '0m', '0m', '0m', '3', '-', '0m', '0m', '0m', '0m', '0m', '0m', '2', '-'],
  A2: ['0m', '0m', '0m', '0m', '0m', '0m', '5', '-', '0m', '0m', '6', '-', '5', '-', '3', '-'],
  B1: ['0', '-', '-', '-', '.', '0m', '0m', '.', '0m', '.', '0m', '0m', '1', '-', '-', '-'],
  B2: ['0', '-', '-', '-', '.', '0m', '0m', '.', '0m', '.', '6', '-', '5', '-', '3', '-'],
  C1: ['7', '-', '7m', '7m', '5', '-', '5m', '5m', '3', '-', '3m', '3m', '2', '-', '0m', '0m'],
};
const SONG = [['A1', 'gallop'], ['A2', 'gallop'], ['A1', 'gallop'], ['A2', 'gallop'], ['B1', 'half'], ['B2', 'half'], ['B1', 'half'], ['B2', 'half'], ['C1', 'blast'], ['C1', 'blast'], ['A1', 'gallop'], ['A2', 'gallop']];
const BPM = 168, STEP = 60 / BPM / 4, E2 = 82.41;

const music = {
  playing: false, timer: null, next: 0, step: 0, bar: 0, level: 0.55, where: 'lobby', synth: true,
  start(level = 0.55, where = 'lobby') {
    init(); if (!ctx) return;
    this.level = level; this.where = where;
    musicBus.gain.cancelScheduledValues(ctx.currentTime);
    musicBus.gain.setTargetAtTime(musicTarget(level), ctx.currentTime, 0.4);
    const useTrack = where === 'lobby' && trackReady && track;
    this.synth = !useTrack;
    if (track) {
      if (useTrack) { trackGain.gain.setTargetAtTime(1, ctx.currentTime, 0.5); if (track.paused) track.play().catch(() => {}); }
      else { trackGain.gain.setTargetAtTime(0, ctx.currentTime, 0.3); setTimeout(() => { if (!this.playing || this.synth) track.pause(); }, 1200); }
    }
    if (this.playing) return;
    this.playing = true; this.next = ctx.currentTime + 0.1; this.step = 0; this.bar = 0;
    this.timer = setInterval(() => this.schedule(), 50);
  },
  stop(fade = 0.6) {
    if (!ctx || !this.playing) return;
    musicBus.gain.setTargetAtTime(0, ctx.currentTime, fade / 3);
    setTimeout(() => { if (musicBus.gain.value < 0.02) { clearInterval(this.timer); this.playing = false; } }, fade * 1000 + 200);
  },
  schedule() {
    if (ctx.state !== 'running' || !this.synth) { if (!this.synth) this.next = ctx.currentTime + 0.1; return; }
    if (this.next < ctx.currentTime - 0.2) this.next = ctx.currentTime + 0.05; // skip ahead after a long stall instead of bursting
    while (this.next < ctx.currentTime + 0.35) { this.play(this.next); this.next += STEP; this.step++; if (this.step === 16) { this.step = 0; this.bar = (this.bar + 1) % SONG.length; } }
  },
  play(t) {
    const [barId, feel] = SONG[this.bar], bar = BARS[barId], s = this.step, n = bar[s];
    if (n !== '-' && n !== '.') {
      const muted = n.endsWith('m'), semi = parseInt(n, 10), f = E2 * Math.pow(2, semi / 12);
      let len = 1; while (len < 8 && bar[s + len] === '-') len++;
      const dur = muted ? STEP * 0.85 : STEP * len * 0.98;
      guitar(t, f, dur, { muted, pan: -0.65 });
      guitar(t + 0.006, f * 1.0015, dur, { muted, pan: 0.65 });
      bass(t, f, dur, musicBus);
    }
    const out = musicBus;
    if (feel === 'gallop') { // double kick, backbeat snare
      kick(t, out, s % 2 ? 0.55 : 0.8);
      if (s === 4 || s === 12) snare(t, out);
      if (s % 2 === 0) hat(t, out, 0.07);
      if (s === 0 && this.bar % 4 === 0) crash(t, out);
    } else if (feel === 'half') { // breakdown: kicks follow the chugs, half-time snare
      if (n && n !== '-' && n !== '.') kick(t, out, 0.95);
      if (s === 8) snare(t, out, 0.7);
      if (s % 4 === 0) hat(t, out, 0.1, s === 0);
      if (s === 0) crash(t, out, 0.18);
    } else { // blast beat
      kick(t, out, 0.7);
      if (s % 2 === 1) snare(t, out, 0.45);
      hat(t, out, 0.05);
      if (s === 0) crash(t, out, 0.2);
    }
  },
};

const ok = () => ctx && sfxOn && ctx.state === 'running';
let lastGun = 0, boomTimes = [];
function boomSlot() { const n = ctx.currentTime; boomTimes = boomTimes.filter((t) => n - t < 0.35); if (boomTimes.length >= 3) return false; boomTimes.push(n); return true; }

export const sfx = {
  unlock() { init(); if (ctx && ctx.state !== 'running') ctx.resume().catch(() => {}); },
  setEnabled(v) { sfxOn = v; if (sfxBus) sfxBus.gain.value = v ? 0.85 * vol.sfx : 0; },
  setMusic(v) { musicOn = v; if (musicBus && music.playing) musicBus.gain.setTargetAtTime(musicTarget(music.level), ctx.currentTime, 0.2); },
  setVolumes(v) {
    vol = { ...vol, ...v };
    if (!ctx) return;
    master.gain.setTargetAtTime(vol.master, ctx.currentTime, 0.05);
    sfxBus.gain.setTargetAtTime(sfxOn ? 0.85 * vol.sfx : 0, ctx.currentTime, 0.05);
    if (music.playing) musicBus.gain.setTargetAtTime(musicTarget(music.level), ctx.currentTime, 0.05);
  },
  music,
  click() { if (!ok()) return; tone(220, 0.06, { type: 'square', gain: 0.1, to: 110 }); noise(0.05, { type: 'highpass', freq: 3000, gain: 0.12 }); },
  confirm() { if (!ok()) return; tone(110, 0.15, { type: 'sawtooth', gain: 0.18, to: 220 }); noise(0.2, { type: 'bandpass', freq: 1500, gain: 0.15 }); },
  denied() { if (!ok()) return; tone(140, 0.18, { type: 'square', gain: 0.15, to: 90 }); },
  purchase() { if (!ok()) return; [0, 0.07, 0.14].forEach((d, i) => tone(300 + i * 150, 0.15, { type: 'square', gain: 0.1, delay: d })); noise(0.4, { type: 'highpass', freq: 5000, gain: 0.08, delay: 0.1 }); },
  gun(vol = 1) {
    if (!ok()) return; const n = ctx.currentTime; if (n - lastGun < 0.045) return; lastGun = n;
    noise(0.08, { type: 'bandpass', freq: 1500, q: 0.7, gain: 0.4 * vol });
    noise(0.04, { type: 'highpass', freq: 4000, gain: 0.15 * vol });
    tone(95, 0.07, { type: 'square', gain: 0.2 * vol, to: 45 });
  },
  rocket(vol = 1) { if (!ok()) return; noise(0.7, { type: 'bandpass', freq: 500, q: 1.2, gain: 0.45 * vol, attack: 0.03, sweepTo: 2600 }); tone(70, 0.25, { type: 'sawtooth', gain: 0.18 * vol, to: 38 }); },
  explosion(size = 1, vol = 1) {
    if (!ok() || !boomSlot()) return; const v = Math.min(1, vol);
    noise(1.6 * size, { type: 'lowpass', freq: 1100, gain: 1.0 * v, attack: 0.004, sweepTo: 55 });
    noise(0.3, { type: 'highpass', freq: 2200, gain: 0.4 * v });
    tone(58, 1.0 * size, { type: 'sine', gain: 0.85 * v, to: 22 });
    noise(2.2 * size, { type: 'lowpass', freq: 260, gain: 0.3 * v, attack: 0.25, delay: 0.12 });
    noise(1.2, { type: 'bandpass', freq: 3000, q: 2, gain: 0.06 * v, delay: 0.3, attack: 0.1 }); // falling debris tinkle
  },
  nuke(vol = 1) {
    if (!ok()) return;
    noise(4, { type: 'lowpass', freq: 1400, gain: 1.0 * vol, attack: 0.01, sweepTo: 40 });
    tone(45, 3.5, { type: 'sine', gain: 1.0 * vol, to: 18 });
    noise(5, { type: 'lowpass', freq: 200, gain: 0.5 * vol, attack: 0.6, delay: 0.2 });
  },
  crunch() { if (!ok()) return; noise(0.18, { type: 'bandpass', freq: 380, q: 1.5, gain: 0.5 }); tone(70, 0.15, { type: 'square', gain: 0.18, to: 40 }); noise(0.12, { type: 'highpass', freq: 3500, gain: 0.12, delay: 0.03 }); },
  hit() { if (!ok()) return; noise(0.05, { type: 'highpass', freq: 4000, gain: 0.25 }); tone(1400, 0.04, { type: 'square', gain: 0.05, to: 700 }); },
  hurt() { if (!ok()) return; noise(0.15, { type: 'lowpass', freq: 500, gain: 0.4 }); tone(120, 0.12, { type: 'square', gain: 0.12, to: 70 }); },
  pickup() { if (!ok()) return; [0, 0.06, 0.12].forEach((d, i) => tone(520 * (1 + i * 0.26), 0.14, { type: 'triangle', gain: 0.18, delay: d })); },
  powerup() { if (!ok()) return; [0, 0.05, 0.1, 0.15, 0.2].forEach((d, i) => tone(220 * Math.pow(1.26, i), 0.2, { type: 'square', gain: 0.1, delay: d })); guitar(ctx.currentTime + 0.25, E2 * 2, 0.6, { gain: 0.8, out: sfxBus }); },
  special() { if (!ok()) return; tone(80, 0.5, { type: 'sawtooth', gain: 0.2, to: 400 }); noise(0.5, { type: 'bandpass', freq: 400, gain: 0.3, sweepTo: 3000 }); },
  shield() { if (!ok()) return; tone(200, 0.6, { type: 'sine', gain: 0.25, to: 800 }); tone(400, 0.6, { type: 'triangle', gain: 0.1, to: 1200 }); },
  flame() { if (!ok()) return; noise(0.25, { type: 'bandpass', freq: 700, q: 0.6, gain: 0.25 }); },
  railgun(vol = 1) { if (!ok()) return; tone(3000, 0.12, { type: 'sawtooth', gain: 0.15 * vol, to: 6000 }); tone(1800, 0.35, { type: 'sawtooth', gain: 0.3 * vol, to: 120, delay: 0.1 }); noise(0.3, { type: 'highpass', freq: 2000, gain: 0.35 * vol, delay: 0.1 }); },
  whistle(vol = 1) { if (!ok()) return; tone(2400, 0.8, { type: 'sine', gain: 0.12 * vol, to: 700, attack: 0.2 }); },
  alarm() { if (!ok()) return; [0, 0.28, 0.56].forEach((d) => { tone(740, 0.2, { type: 'square', gain: 0.08, delay: d }); tone(560, 0.2, { type: 'square', gain: 0.08, delay: d + 0.14 }); }); },
  wind() { if (!ok()) return; noise(6, { type: 'bandpass', freq: 400, q: 0.8, gain: 0.25, attack: 1.5, sweepTo: 900 }); },
  streak(n = 2) { if (!ok()) return; const t = ctx.currentTime; guitar(t, E2, 0.5 + n * 0.1, { out: sfxBus, pan: -0.4 }); guitar(t + 0.005, E2 * 1.002, 0.5 + n * 0.1, { out: sfxBus, pan: 0.4 }); crash(t, sfxBus, 0.18); kick(t, sfxBus, 0.8); },
  countdown(final) { if (!ok()) return; if (final) { this.streak(3); } else { tone(440, 0.18, { type: 'square', gain: 0.15 }); kick(ctx.currentTime, sfxBus, 0.6); } },
  win() { if (!ok()) return; const t = ctx.currentTime; [0, 3, 5, 7].forEach((s, i) => guitar(t + i * 0.18, E2 * Math.pow(2, s / 12), i === 3 ? 1.4 : 0.2, { out: sfxBus })); crash(t + 0.54, sfxBus); },
  lose() { if (!ok()) return; const t = ctx.currentTime; [0, -1, -2].forEach((s, i) => guitar(t + i * 0.3, E2 * Math.pow(2, s / 12), i === 2 ? 1.6 : 0.3, { out: sfxBus })); },

  engineStart() {
    if (!ctx || engine) return;
    const o1 = ctx.createOscillator(), o2 = ctx.createOscillator();
    o1.type = 'sawtooth'; o2.type = 'square';
    const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 500;
    const g = ctx.createGain(); g.gain.value = 0;
    o1.connect(f); o2.connect(f); f.connect(g); g.connect(sfxBus);
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
    engine.g.gain.setTargetAtTime(0.05 + throttle * 0.05, t, 0.1);
  },
  engineStop() {
    if (!engine) return;
    const e = engine; engine = null;
    e.g.gain.setTargetAtTime(0, ctx.currentTime, 0.1);
    setTimeout(() => { try { e.o1.stop(); e.o2.stop(); } catch (_) { /* already stopped */ } }, 400);
  },
};

document.addEventListener('visibilitychange', () => {
  if (!ctx) return;
  if (document.hidden) { if (track && !track.paused) track.pause(); }
  else { if (ctx.state !== 'running') ctx.resume().catch(() => {}); if (track && music.playing && !music.synth) track.play().catch(() => {}); }
});
