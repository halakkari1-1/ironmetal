// Sound effects and the in-match metal riff are synthesized with the Web Audio API.
// The lobby plays a recorded track (assets/music/lobby.mp3) on a plain <audio> element: it decodes on the
// browser's media thread, so a busy frame never makes it stutter.

let ctx = null, master = null, sfxBus = null, musicBus = null, reverb = null, noiseBuf = null;
let sfxOn = true, musicOn = true;
let vol = { master: 0.8, music: 0.6, sfx: 0.9 };
// Optional recorded track for the lobby: drop an MP3 at assets/music/lobby.mp3 and it replaces the synthesized riff there.
const TRACK_URL = new URL('../assets/music/lobby.mp3', import.meta.url).href;
let trackReady = false, trackFade = null;
const track = (() => { try { const a = new Audio(); a.loop = true; a.preload = 'auto'; a.src = TRACK_URL; return a; } catch (e) { return null; } })();
if (track) {
  track.addEventListener('canplaythrough', () => { trackReady = true; if (music.playing && music.where === 'lobby') music.start(music.level, 'lobby'); }, { once: true });
  track.addEventListener('error', () => { trackReady = false; });
}
const trackTarget = () => (musicOn ? Math.min(1, vol.master * vol.music * music.level * 1.9) : 0);
// Fades the element's own volume; pauses it once silent so it costs nothing in matches.
function fadeTrack(to, ms = 600) {
  if (!track) return;
  clearInterval(trackFade);
  if (to > 0 && track.paused) { track.volume = 0; track.play().catch(() => {}); }
  const from = track.volume, t0 = performance.now();
  trackFade = setInterval(() => {
    const k = Math.min(1, (performance.now() - t0) / ms); track.volume = Math.max(0, Math.min(1, from + (to - from) * k));
    if (k >= 1) { clearInterval(trackFade); if (to === 0) track.pause(); }
  }, 40);
}
let engine = null;
// ---------- recorded sound effects ----------
// Real recordings (CC0, from Freesound; see assets/sfx/CREDITS.txt), cut and level-matched into assets/sfx/.
// Each bank holds variations that are picked at random so repeated shots never sound identical.
// Anything not loaded yet falls back to the synthesized version below.
const BANKS = {
  gun: ['gun_1', 'gun_2', 'gun_3', 'gun_4'], gunHeavy: ['gun_heavy_1', 'gun_heavy_2', 'gun_heavy_3'], gunLight: ['gun_light_1', 'gun_light_2', 'gun_light_3'],
  boomSmall: ['boom_small'], boomRocket: ['boom_rocket'], boomBig: ['boom_car'],
  launch: ['launch'], launchHeavy: ['launch_heavy'], incoming: ['incoming'], strike: ['strike'],
};
const buffers = {}; // file name (without .mp3 for banks, full name for per-car files) -> AudioBuffer
const R0 = (a, b) => a + Math.random() * (b - a);
const MAX_VOICES = 28; // recorded one-shots playing at once; beyond this, quiet ones are dropped
let voices = 0;
function loadFile(name) {
  buffers[name] = null;
  const file = name.includes('.') ? name : `${name}.mp3`;
  fetch(new URL(`../assets/sfx/${file}`, import.meta.url).href).then((r) => (r.ok ? r.arrayBuffer() : Promise.reject())).then((ab) => ctx.decodeAudioData(ab)).then((b) => { buffers[name] = b; }).catch(() => { delete buffers[name]; });
}
function loadBanks() { for (const list of Object.values(BANKS)) for (const n of list) if (!(n in buffers)) loadFile(n); }
// Plays a recording. vol 0..1, rate = playback speed (pitch), pan -1..1, offset = seconds into the file.
function playFile(name, vol, { rate = 1, pan = 0, offset = 0 } = {}) {
  const b = buffers[name]; if (!b) return false;
  if (voices >= MAX_VOICES && vol < 0.6) return true; // busy: skip a distant sound rather than pile up
  const s = ctx.createBufferSource(), g = ctx.createGain(); s.buffer = b; s.playbackRate.value = rate; g.gain.value = Math.min(1.2, vol);
  let out = g;
  if (pan && ctx.createStereoPanner) { const p = ctx.createStereoPanner(); p.pan.value = Math.max(-1, Math.min(1, pan)); g.connect(p); out = p; }
  s.connect(g); out.connect(sfxBus);
  voices++; s.onended = () => { voices--; s.disconnect(); out.disconnect(); };
  s.start(0, Math.max(0, Math.min(b.duration - 0.05, offset))); return true;
}
const playBank = (bank, vol, opts) => { const list = BANKS[bank]; return playFile(list[(Math.random() * list.length) | 0], vol, opts); };

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
    fadeTrack(useTrack ? trackTarget() : 0, useTrack ? 900 : 400);
    if (this.playing) return;
    this.playing = true; this.next = ctx.currentTime + 0.1; this.step = 0; this.bar = 0;
    this.timer = setInterval(() => this.schedule(), 50);
  },
  stop(fade = 0.6) {
    if (!ctx || !this.playing) return;
    musicBus.gain.setTargetAtTime(0, ctx.currentTime, fade / 3); fadeTrack(0, fade * 1000);
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
  unlock() { init(); if (ctx && ctx.state !== 'running') ctx.resume().catch(() => {}); if (ctx) loadBanks(); },
  setEnabled(v) { sfxOn = v; if (sfxBus) sfxBus.gain.value = v ? 0.85 * vol.sfx : 0; },
  setMusic(v) { musicOn = v; if (musicBus && music.playing) musicBus.gain.setTargetAtTime(musicTarget(music.level), ctx.currentTime, 0.2); if (music.playing && !music.synth) fadeTrack(trackTarget(), 300); },
  setVolumes(v) {
    vol = { ...vol, ...v };
    if (track && music.playing && !music.synth) { clearInterval(trackFade); track.volume = trackTarget(); }
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
  gun(vol = 1, pitch = 1, pan = 0) { // pitch < 1: heavier calibre (Colossus, Titan); > 1: light rifles (Venom)
    if (!ok()) return; const n = ctx.currentTime; if (n - lastGun < 0.045) return; lastGun = n;
    const bank = pitch < 0.88 ? 'gunHeavy' : pitch > 1.1 ? 'gunLight' : 'gun';
    if (playBank(bank, vol * 0.9, { rate: R0(0.94, 1.06) * (bank === 'gun' ? pitch : 1), pan })) return;
    noise(0.08 / Math.sqrt(pitch), { type: 'bandpass', freq: 1500 * pitch, q: 0.7, gain: 0.4 * vol });
    noise(0.04, { type: 'highpass', freq: 4000 * pitch, gain: 0.15 * vol });
    tone(95 * pitch, 0.07 / pitch, { type: 'square', gain: 0.2 * vol * (pitch < 1 ? 1.3 : 1), to: 45 * pitch });
  },
  // Each vehicle's ability has its own voice. A recorded file (car.sound.files.ability) replaces it when present.
  ability(kind, vol = 1, file = null) {
    if (!ok()) return;
    if (file && playFile(file, vol)) return;
    const v = Math.min(1, vol);
    switch (kind) {
      case 'smoke': noise(1.4, { type: 'lowpass', freq: 2400, gain: 0.4 * v, attack: 0.02, sweepTo: 300 }); tone(160, 0.3, { type: 'triangle', gain: 0.12 * v, to: 60 }); break;
      case 'dash': tone(180, 0.45, { type: 'sawtooth', gain: 0.18 * v, to: 900 }); noise(0.5, { type: 'bandpass', freq: 800, gain: 0.3 * v, sweepTo: 5000 }); break;
      case 'toxic': for (let i = 0; i < 6; i++) tone(R0(300, 700), 0.09, { type: 'sine', gain: 0.12 * v, to: R0(800, 1400), delay: i * 0.06 }); noise(1, { type: 'bandpass', freq: 1800, q: 2, gain: 0.18 * v, attack: 0.1 }); break;
      case 'riptide': noise(1.1, { type: 'lowpass', freq: 300, gain: 0.5 * v, attack: 0.05, sweepTo: 2500 }); tone(70, 0.6, { type: 'sine', gain: 0.3 * v, to: 40 }); break;
      case 'zap': for (let i = 0; i < 8; i++) tone(R0(600, 2400), 0.05, { type: 'square', gain: 0.07 * v, delay: i * 0.035 }); noise(0.4, { type: 'highpass', freq: 3000, gain: 0.25 * v }); tone(120, 0.4, { type: 'sawtooth', gain: 0.12 * v, to: 60 }); break;
      case 'charge': tone(55, 0.8, { type: 'sawtooth', gain: 0.25 * v, to: 140 }); noise(0.8, { type: 'lowpass', freq: 500, gain: 0.35 * v, sweepTo: 1500 }); break;
      case 'roar': tone(110, 0.9, { type: 'sawtooth', gain: 0.22 * v, to: 55 }); tone(165, 0.9, { type: 'square', gain: 0.08 * v, to: 70 }); noise(0.9, { type: 'bandpass', freq: 600, q: 1.5, gain: 0.35 * v, sweepTo: 250 }); break;
      case 'cannon': tone(48, 0.7, { type: 'sine', gain: 0.5 * v, to: 28 }); noise(0.6, { type: 'lowpass', freq: 900, gain: 0.55 * v, sweepTo: 120 }); break;
      case 'shield': tone(200, 0.6, { type: 'sine', gain: 0.25 * v, to: 800 }); tone(400, 0.6, { type: 'triangle', gain: 0.1 * v, to: 1200 }); break;
      default: tone(80, 0.5, { type: 'sawtooth', gain: 0.2 * v, to: 400 }); noise(0.5, { type: 'bandpass', freq: 400, gain: 0.3 * v, sweepTo: 3000 });
    }
  },
  ready() { if (!ok()) return; tone(660, 0.08, { type: 'triangle', gain: 0.1 }); tone(990, 0.12, { type: 'triangle', gain: 0.1, delay: 0.07 }); }, // ability recharged
  abilityEnd() { if (!ok()) return; tone(520, 0.15, { type: 'sine', gain: 0.07, to: 260 }); },
  rocket(vol = 1, heavy = false, pan = 0) {
    if (!ok()) return;
    if (playBank(heavy ? 'launchHeavy' : 'launch', vol * (heavy ? 1 : 0.85), { rate: R0(0.95, 1.05), pan })) return;
    noise(0.7, { type: 'bandpass', freq: 500, q: 1.2, gain: 0.45 * vol, attack: 0.03, sweepTo: 2600 }); tone(70, 0.25, { type: 'sawtooth', gain: 0.18 * vol, to: 38 }); },
  explosion(size = 1, vol = 1, pan = 0) {
    if (!ok() || !boomSlot()) return; const v = Math.min(1, vol);
    const bank = size < 0.65 ? 'boomSmall' : size < 1.3 ? 'boomRocket' : 'boomBig';
    // far explosions are quieter and duller: slowed down a touch, which also lowers their pitch
    if (playBank(bank, v * 1.1, { rate: R0(0.92, 1.04) * (v < 0.4 ? 0.9 : 1), pan })) return;
    noise(1.6 * size, { type: 'lowpass', freq: 1100, gain: 1.0 * v, attack: 0.004, sweepTo: 55 });
    noise(0.3, { type: 'highpass', freq: 2200, gain: 0.4 * v });
    tone(58, 1.0 * size, { type: 'sine', gain: 0.85 * v, to: 22 });
    noise(2.2 * size, { type: 'lowpass', freq: 260, gain: 0.3 * v, attack: 0.25, delay: 0.12 });
    noise(1.2, { type: 'bandpass', freq: 3000, q: 2, gain: 0.06 * v, delay: 0.3, attack: 0.1 }); // falling debris tinkle
  },
  nuke(vol = 1) {
    if (!ok()) return;
    if (playBank('strike', Math.min(1, vol * 1.2), { offset: 0.9 }) && playBank('boomBig', Math.min(1, vol), { rate: 0.8 })) return;
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
  // "wheeeew... boom": the falling whistle, timed so it ends on impact `secs` from now
  incoming(secs, vol = 1, pan = 0) {
    if (!ok()) return;
    const b = buffers.incoming; if (b && playFile('incoming', vol * 0.85, { offset: b.duration - Math.min(b.duration, secs), pan })) return;
    tone(2400, Math.min(1.2, secs), { type: 'sine', gain: 0.12 * vol, to: 700, attack: 0.1 });
  },
  whistle(vol = 1) { this.incoming(0.8, vol); },
  alarm() { if (!ok()) return; [0, 0.28, 0.56].forEach((d) => { tone(740, 0.2, { type: 'square', gain: 0.08, delay: d }); tone(560, 0.2, { type: 'square', gain: 0.08, delay: d + 0.14 }); }); },
  wind() { if (!ok()) return; noise(6, { type: 'bandpass', freq: 400, q: 0.8, gain: 0.25, attack: 1.5, sweepTo: 900 }); },
  streak(n = 2) { if (!ok()) return; const t = ctx.currentTime; guitar(t, E2, 0.5 + n * 0.1, { out: sfxBus, pan: -0.4 }); guitar(t + 0.005, E2 * 1.002, 0.5 + n * 0.1, { out: sfxBus, pan: 0.4 }); crash(t, sfxBus, 0.18); kick(t, sfxBus, 0.8); },
  countdown(final) { if (!ok()) return; if (final) { this.streak(3); } else { tone(440, 0.18, { type: 'square', gain: 0.15 }); kick(ctx.currentTime, sfxBus, 0.6); } },
  win() { if (!ok()) return; const t = ctx.currentTime; [0, 3, 5, 7].forEach((s, i) => guitar(t + i * 0.18, E2 * Math.pow(2, s / 12), i === 3 ? 1.4 : 0.2, { out: sfxBus })); crash(t + 0.54, sfxBus); },
  lose() { if (!ok()) return; const t = ctx.currentTime; [0, -1, -2].forEach((s, i) => guitar(t + i * 0.3, E2 * Math.pow(2, s / 12), i === 2 ? 1.6 : 0.3, { out: sfxBus })); },

  // The player's engine. profile = { base: idle pitch Hz, wave, grit 0..1 } from the car's data: sports cars idle high
  // and sharp, armour idles deep, tracked and battered machines add a rattling, gritty layer. A recorded loop
  // (car.sound.files.engine) replaces the synth when present, pitched by speed.
  engineStart(profile = {}, file = null) {
    if (!ctx || engine) return;
    const p = { base: 45, wave: 'sawtooth', grit: 0.4, ...profile };
    const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 500;
    const g = ctx.createGain(); g.gain.value = 0;
    f.connect(g); g.connect(sfxBus);
    const e = { f, g, p, srcs: [] };
    if (file && buffers[file]) {
      const b = ctx.createBufferSource(); b.buffer = buffers[file]; b.loop = true; b.connect(f); b.start(); e.loop = b; e.srcs.push(b); f.frequency.value = 12000;
    } else {
      const o1 = ctx.createOscillator(), o2 = ctx.createOscillator(); o1.type = p.wave; o2.type = 'square';
      o1.connect(f); o2.connect(f); o1.start(); o2.start(); e.o1 = o1; e.o2 = o2; e.srcs.push(o1, o2);
      // grit: filtered noise whose level wobbles with an LFO (piston knock / track rattle)
      const n = ctx.createBufferSource(); n.buffer = noiseBuf; n.loop = true;
      const nf = ctx.createBiquadFilter(); nf.type = 'bandpass'; nf.frequency.value = 220 + p.base * 3; nf.Q.value = 1.2;
      const ng = ctx.createGain(); ng.gain.value = 0.22 * p.grit;
      const lfo = ctx.createOscillator(), lg = ctx.createGain(); lfo.frequency.value = 8; lg.gain.value = 0.18 * p.grit; lfo.connect(lg); lg.connect(ng.gain);
      n.connect(nf); nf.connect(ng); ng.connect(f); n.start(); lfo.start(); e.lfo = lfo; e.srcs.push(n, lfo);
    }
    engine = e;
  },
  engineSet(throttle, speedFrac) {
    if (!engine) return;
    const t = ctx.currentTime, b = engine.p.base;
    if (engine.loop) { engine.loop.playbackRate.setTargetAtTime(0.7 + speedFrac * 0.9 + throttle * 0.15, t, 0.08); engine.g.gain.setTargetAtTime(0.12 + throttle * 0.1, t, 0.1); return; }
    const base = b + speedFrac * b * 1.55 + throttle * b * 0.33;
    engine.o1.frequency.setTargetAtTime(base, t, 0.08);
    engine.o2.frequency.setTargetAtTime(base * 0.5, t, 0.08);
    engine.lfo.frequency.setTargetAtTime(6 + speedFrac * 22, t, 0.1);
    engine.f.frequency.setTargetAtTime(250 + b * 3 + speedFrac * 900 + throttle * 300, t, 0.1);
    engine.g.gain.setTargetAtTime(0.05 + throttle * 0.05, t, 0.1);
  },
  engineStop() {
    if (!engine) return;
    const e = engine; engine = null;
    e.g.gain.setTargetAtTime(0, ctx.currentTime, 0.1);
    setTimeout(() => { for (const s of e.srcs) { try { s.stop(); } catch (_) { /* already stopped */ } } }, 400);
  },
  // Loads optional recorded sounds (paths relative to assets/sfx/). Missing files are simply skipped.
  preloadFiles(list) { init(); for (const f of list) if (f && !(f in buffers)) loadFile(f); },
};

document.addEventListener('visibilitychange', () => {
  if (document.hidden) { if (track && !track.paused) track.pause(); return; }
  if (ctx && ctx.state !== 'running') ctx.resume().catch(() => {});
  if (track && music.playing && !music.synth) { track.volume = trackTarget(); track.play().catch(() => {}); }
});
