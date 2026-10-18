// App controller: renderer, garage showroom, menus, HUD, input and the match lifecycle.
import * as THREE from 'three';
import { CARS, UPGRADES, MAX_UPGRADE, MAPS, DIFFICULTY, KILL_REWARD, carStats, upgradeCost } from './data.js';
import { buildCar, preloadWarhorse } from './cars3d.js';
import { loadKit, KIT, building, propMesh, barrelGeometry } from './kit.js';
import { Game, POWERS } from './game.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { save } from './save.js';
import { sfx } from './audio.js';
import { quality, TIERS } from './quality.js';

const $ = (id) => document.getElementById(id);
const fmt = (n) => Math.round(n).toLocaleString('en-US');
const isTouch = matchMedia('(pointer:coarse)').matches || 'ontouchstart' in window;

// ---------- renderer ----------
const canvas = $('view');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
quality.init(save.get().graphics);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.05;
renderer.shadowMap.enabled = true; renderer.shadowMap.type = quality.tier.soft ? THREE.PCFSoftShadowMap : THREE.PCFShadowMap;

// Bloom makes fire, muzzle flashes and lights glow. One composer is shared by the showroom and the arena.
const composer = new EffectComposer(renderer);
const renderPass = new RenderPass(new THREE.Scene(), new THREE.PerspectiveCamera());
const bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.55, 0.4, 0.86);
composer.addPass(renderPass); composer.addPass(bloom); composer.addPass(new OutputPass());
bloom.enabled = quality.tier.bloom;
function draw(scene, camera) { renderPass.scene = scene; renderPass.camera = camera; composer.render(); }

// Animated fire behind the logo (classic cellular fire, drawn into a small canvas and blurred by CSS).
class FireLogo {
  constructor(canvas) {
    this.c = canvas; this.g = canvas.getContext('2d'); this.w = canvas.width; this.h = canvas.height;
    this.px = new Uint8Array(this.w * this.h); this.img = this.g.createImageData(this.w, this.h);
    this.pal = [];
    for (let i = 0; i < 37; i++) {
      const t = i / 36;
      const r = Math.min(255, t * 3 * 255), gg = Math.min(255, Math.max(0, (t * 3 - 1) * 255)), b = Math.min(255, Math.max(0, (t * 3 - 2) * 255));
      this.pal.push([r, gg * 0.85, b * 0.6, i === 0 ? 0 : Math.min(255, 60 + t * 300)]);
    }
    for (let x = 0; x < this.w; x++) this.px[(this.h - 1) * this.w + x] = 36;
    this.embers = [];
  }
  step() {
    const { w, h, px } = this;
    for (let x = 0; x < w; x++) px[(h - 1) * w + x] = Math.random() < 0.85 ? 36 : 30;
    for (let y = 1; y < h; y++) for (let x = 0; x < w; x++) {
      const src = y * w + x, v = px[src];
      const r = (Math.random() * 3) | 0, dst = src - w - r + 1;
      if (dst >= 0) px[dst] = Math.max(0, v - (r & 1) - (Math.random() < 0.35 ? 1 : 0));
    }
    const d = this.img.data;
    for (let i = 0; i < px.length; i++) { const c = this.pal[px[i]]; d[i * 4] = c[0]; d[i * 4 + 1] = c[1]; d[i * 4 + 2] = c[2]; d[i * 4 + 3] = c[3] * (1 - (Math.floor(i / w) / h) * 0.15); }
    this.g.putImageData(this.img, 0, 0);
    if (Math.random() < 0.35) this.embers.push({ x: Math.random() * w, y: h - 4, vx: (Math.random() - 0.5) * 0.6, vy: -0.6 - Math.random() * 0.9, l: 1 });
    this.embers = this.embers.filter((e) => { e.x += e.vx; e.y += e.vy; e.l -= 0.015; this.g.fillStyle = `rgba(255,${150 + Math.random() * 80},60,${e.l})`; this.g.fillRect(e.x, e.y, 1.5, 1.5); return e.l > 0 && e.y > 0; });
  }
}
const fires = [new FireLogo($('loaderFire'))];
let fireT = 0;

// ---------- garage showroom ----------
class Showroom {
  constructor() {
    const s = this.scene = new THREE.Scene();
    s.background = new THREE.Color(0x0d0c0a); s.fog = new THREE.Fog(0x0d0c0a, 18, 46);
    this.camera = new THREE.PerspectiveCamera(36, 1, 0.1, 200);
    s.add(new THREE.HemisphereLight(0xffeedd, 0x1a1510, 0.55));
    const key = new THREE.SpotLight(0xffd2a0, 260, 40, 0.55, 0.6, 1.4); key.position.set(4, 13, 7); key.castShadow = true; key.shadow.mapSize.set(1024, 1024); key.shadow.bias = -0.0005; s.add(key, key.target);
    const rim = new THREE.SpotLight(0x7fa6ff, 180, 40, 0.7, 0.7, 1.4); rim.position.set(-7, 6, -8); s.add(rim, rim.target);
    const fill = new THREE.PointLight(0xe0682c, 20, 14, 1.6); fill.position.set(0, 0.6, 5); s.add(fill);

    const c = document.createElement('canvas'); c.width = c.height = 512; const g = c.getContext('2d');
    g.fillStyle = '#2a2722'; g.fillRect(0, 0, 512, 512);
    for (let i = 0; i < 7000; i++) { const v = Math.random() < 0.5 ? 0 : 255; g.fillStyle = `rgba(${v},${v},${v},${Math.random() * 0.06})`; g.fillRect(Math.random() * 512, Math.random() * 512, 2, 2); }
    g.strokeStyle = 'rgba(0,0,0,0.45)'; g.lineWidth = 3; for (let i = 0; i <= 512; i += 128) { g.beginPath(); g.moveTo(i, 0); g.lineTo(i, 512); g.moveTo(0, i); g.lineTo(512, i); g.stroke(); }
    for (let i = 0; i < 10; i++) { g.fillStyle = 'rgba(5,4,3,0.25)'; g.beginPath(); g.ellipse(Math.random() * 512, Math.random() * 512, 20 + Math.random() * 40, 10 + Math.random() * 20, Math.random() * 3, 0, 7); g.fill(); }
    const ft = new THREE.CanvasTexture(c); ft.wrapS = ft.wrapT = THREE.RepeatWrapping; ft.repeat.set(8, 8); ft.colorSpace = THREE.SRGBColorSpace;
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(80, 80), new THREE.MeshStandardMaterial({ map: ft, roughness: 0.6, metalness: 0.3 }));
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; s.add(floor); this.floor = floor;

    const steel = new THREE.MeshStandardMaterial({ color: 0x2d2b27, metalness: 0.8, roughness: 0.4, flatShading: true });
    this.platform = new THREE.Group(); s.add(this.platform); this.key = key;
    const base = new THREE.Mesh(new THREE.CylinderGeometry(4.6, 4.9, 0.35, 40), steel); base.position.y = 0.17; base.receiveShadow = true; base.castShadow = true;
    const ring = new THREE.Mesh(new THREE.TorusGeometry(4.65, 0.05, 6, 64), new THREE.MeshBasicMaterial({ color: 0xe0682c })); ring.rotation.x = Math.PI / 2; ring.position.y = 0.36;
    this.platform.add(base, ring);
    for (let i = 0; i < 24; i++) { const a = (i / 24) * Math.PI * 2; const b = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.04, 0.12), new THREE.MeshStandardMaterial({ color: 0x46413a, metalness: 0.7 })); b.position.set(Math.cos(a) * 4.1, 0.36, Math.sin(a) * 4.1); b.rotation.y = -a; this.platform.add(b); }

    const old = this.old = new THREE.Group(); s.add(old);
    const prop = new THREE.MeshStandardMaterial({ color: 0x3a3630, roughness: 0.9, flatShading: true });
    const red = new THREE.MeshStandardMaterial({ color: 0x6e2216, roughness: 0.6, metalness: 0.4, flatShading: true });
    const tire = new THREE.MeshStandardMaterial({ color: 0x141414, roughness: 0.95 });
    [[-7.5, -5], [-6.4, -5.6], [8, -6], [9.1, -5.2]].forEach(([x, z], i) => { const b = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 0.7, 1.7, 10), i % 2 ? prop : red); b.position.set(x, 0.85, z); b.castShadow = true; old.add(b); });
    for (let i = 0; i < 4; i++) { const t = new THREE.Mesh(new THREE.TorusGeometry(0.9, 0.35, 8, 14), tire); t.rotation.x = Math.PI / 2; t.position.set(-9, 0.35 + i * 0.62, -1.5); t.castShadow = true; old.add(t); }
    const wall = new THREE.Mesh(new THREE.BoxGeometry(40, 14, 1), new THREE.MeshStandardMaterial({ color: 0x1c1a16, roughness: 0.9 })); wall.position.set(0, 7, -14); old.add(wall);
    for (let i = -3; i <= 3; i++) { const p = new THREE.Mesh(new THREE.BoxGeometry(0.6, 14, 0.6), steel); p.position.set(i * 6, 7, -13.3); old.add(p); }
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(40, 0.5, 0.1), new THREE.MeshBasicMaterial({ color: 0x8e3a14 })); stripe.position.set(0, 2.2, -13.45); old.add(stripe);
    for (const x of [-6, 0, 6]) { // hanging work lamps
      const lamp = new THREE.Mesh(new THREE.ConeGeometry(0.5, 0.5, 12, 1, true), new THREE.MeshStandardMaterial({ color: 0x222, side: THREE.DoubleSide })); lamp.position.set(x, 9, -4); old.add(lamp);
      const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.18, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffd9a0 })); bulb.position.set(x, 8.75, -4); old.add(bulb);
    }
    // drifting dust in the key light
    const n = 220, pos = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) pos.set([(Math.random() - 0.5) * 16, Math.random() * 9, (Math.random() - 0.5) * 12], i * 3);
    const dg = new THREE.BufferGeometry(); dg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    this.dust = new THREE.Points(dg, new THREE.PointsMaterial({ color: 0xffd8a8, size: 0.05, transparent: true, opacity: 0.5, depthWrite: false }));
    s.add(this.dust);

    this.car = null; this.carId = null; this.spin = 0.5; this.yaw = 0.6; this.drop = 0; this.focus = 'right';
    this.camX = 0;
    this.dragging = false;
  }
  // Replaces the placeholder backdrop with the real environment kit: an open yard at dusk in front of a watchtower.
  dress() {
    if (this.dressed || !KIT.loaded) return;
    this.dressed = true;
    const s = this.scene;
    s.remove(this.old);
    const c = document.createElement('canvas'); c.width = 2; c.height = 256; const g = c.getContext('2d'), grd = g.createLinearGradient(0, 0, 0, 256);
    grd.addColorStop(0, '#15131c'); grd.addColorStop(0.55, '#3b2d2a'); grd.addColorStop(0.75, '#6a4632'); grd.addColorStop(1, '#6a4632');
    g.fillStyle = grd; g.fillRect(0, 0, 2, 256);
    const sky = new THREE.CanvasTexture(c); sky.colorSpace = THREE.SRGBColorSpace; s.background = sky;
    s.fog = new THREE.Fog(0x4a352b, 24, 75);
    const tex = new THREE.TextureLoader().load(new URL('../assets/kit/ground_concrete.jpg', import.meta.url).href);
    tex.colorSpace = THREE.SRGBColorSpace; tex.wrapS = tex.wrapT = THREE.MirroredRepeatWrapping; tex.repeat.set(9, 9); tex.anisotropy = 4;
    this.floor.material = new THREE.MeshStandardMaterial({ map: tex, color: 0x8a8278, roughness: 0.9, metalness: 0.05 });
    const tower = building(1.7); tower.levels[1].distance = 1e6; tower.position.set(3, 0, -19); tower.rotation.y = 0.35; s.add(tower);
    const put = (name, x, z, ry, sc = 1.35) => { const m = propMesh(name, sc); m.position.set(x, 0, z); m.rotation.y = ry; s.add(m); return m; };
    put('dumpster', -9, -6, 0.35); put('tarpDrums', -11.5, -2.2, 1.2); put('boxes', -7.4, -3.6, 0.6); put('jugCrate', -6.8, -4.6, 2);
    put('gasCart', 9, -6.5, -0.5); put('cylinders', 10.8, -3.2, 0.9); put('cylinder', 7.6, -8.4, 0); put('cylinder', 8.1, -8.9, 0);
    put('cage', 13, -11, -0.3); put('pole', -6.5, -13, 0.4); put('shelf', -13, -8, 0.8); put('crates', 11.5, -0.5, 0.2);
    const bm = KIT.material.clone(); bm.side = THREE.FrontSide; bm.color = new THREE.Color(1.15, 0.9, 0.85);
    for (const [x, z] of [[-10.8, 1.2], [-9.2, 1.9], [12.2, 2.6]]) { const b = new THREE.Mesh(barrelGeometry(), bm); b.position.set(x, 0, z); b.rotation.y = x; b.castShadow = true; s.add(b); }
    // sodium work lights on the tower and a warm fill from the left
    const lamp = new THREE.PointLight(0xff9a48, 160, 30, 1.6); lamp.position.set(-1, 6.5, -13); s.add(lamp);
    const lamp2 = new THREE.PointLight(0xffb070, 70, 22, 1.6); lamp2.position.set(-10, 3.5, -4); s.add(lamp2);
    this.lamps = [lamp, lamp2];
    s.traverse((o) => { if (o.isMesh && o !== this.floor) { o.castShadow = true; o.receiveShadow = true; } });
  }
  show(id) {
    if (this.carId === id && this.car) return;
    if (this.car) this.platform.remove(this.car);
    this.car = buildCar(id); this.car.position.y = 0.36; this.carId = id;
    this.platform.add(this.car); this.drop = 1;
  }
  resize(w, h) { this.camera.aspect = w / h; this.camera.updateProjectionMatrix(); }
  update(dt) {
    if (!this.dragging) this.yaw += dt * this.spin;
    this.platform.rotation.y = this.yaw;
    if (this.drop > 0) { this.drop = Math.max(0, this.drop - dt * 3.2); const k = this.drop; this.car.position.y = 0.36 + k * k * 3; if (this.drop === 0) sfx.click(); }
    const portrait = this.camera.aspect < 1;
    const a = this.camera.aspect, squarish = Math.max(0, 1.75 - a); // 0 on 16:9+, ~0.42 on 4:3
    const off = portrait ? 0 : (this.focus === 'right' ? -3.2 : this.focus === 'left' ? 3.4 : 0) * (1 - squarish * 0.55);
    this.camX += (off - this.camX) * Math.min(1, dt * 4);
    const dist = portrait ? 24 : 15 + squarish * 15;
    this.camera.position.set(this.camX + 2.2, 4.6, dist * 0.92);
    this.camera.lookAt(this.camX, 1.3, 0);
    this.dust.rotation.y += dt * 0.02;
    if (this.lamps) { this.lamps[0].intensity = 160 * (0.92 + Math.random() * 0.08); }
  }
  render() { draw(this.scene, this.camera); }
}

const room = new Showroom();
let game = null;
let mode = 'menu';
let ui = 'main'; // main | garage | upgrade
let browseI = 0;
let setupMap = MAPS[0], setupDiff = DIFFICULTY[0], setupMode = 'deathmatch';
let lastConfig = null;

// ---------- screens ----------
function show(id) { for (const s of ['menu', 'setup', 'history', 'contracts', 'settings', 'hud', 'pause', 'results']) $(s).hidden = s !== id && !(id === 'pause' && s === 'hud'); }

function statRows(car, up, compareTo = null) {
  const s = car.stats, rows = [['Speed', 'speed', s.speed], ['Armor', 'armor', s.armor], ['Guns', 'gun', s.gun], ['Rockets', 'rocket', s.rocket]];
  return rows.map(([label, key, v]) => {
    const bonus = (up[key] || 0) * 0.6;
    return `<div class="stat"><span>${label}</span><div class="bar"><i style="width:${v * 10}%"></i>${bonus ? `<i class="up" style="left:${v * 10}%;width:${bonus * 10}%"></i>` : ''}</div><span class="num">${v}${bonus ? '+' : ''}</span></div>`;
  }).join('');
}

function fillPanel(car, eyebrow) {
  const up = save.owns(car.id) ? save.upgrades(car.id) : {};
  $('cpEyebrow').textContent = eyebrow;
  $('cpName').textContent = car.name;
  $('cpDriver').textContent = `Driver: ${car.driver}`;
  $('cpStats').innerHTML = statRows(car, up);
  $('cpSpecial').textContent = `Special: ${car.special.name}`;
  $('cpSpecialDesc').textContent = car.special.desc;
}

function refreshPoints() { $('points').textContent = fmt(save.get().points); }

function setUI(next) {
  ui = next;
  $('mainActions').hidden = next !== 'main';
  $('garageUI').hidden = next !== 'garage';
  $('upgradeUI').hidden = next !== 'upgrade';
  $('carpanel').hidden = false;
  $('menu').classList.toggle('sub', next === 'upgrade');
  room.focus = next === 'upgrade' ? 'left' : next === 'garage' ? 'center' : 'right';
  if (next === 'main') { const car = save.selectedCar(); room.show(car.id); fillPanel(car, 'Your ride'); }
  if (next === 'garage') { browseI = CARS.findIndex((c) => c.id === save.get().selected); renderGarage(); }
  if (next === 'upgrade') renderUpgrades();
  refreshPoints();
}

function renderGarage() {
  const car = CARS[browseI], owned = save.owns(car.id), sel = save.get().selected === car.id;
  room.show(car.id);
  fillPanel(car, owned ? (sel ? 'Selected' : 'Owned') : 'Locked');
  $('gCount').textContent = `${browseI + 1} / ${CARS.length}`;
  $('gStory').textContent = car.story;
  const price = $('gPrice'), act = $('gAction');
  if (owned) { price.hidden = true; act.textContent = sel ? 'Selected' : 'Select'; act.disabled = sel; }
  else {
    price.hidden = false;
    const afford = save.get().points >= car.price;
    price.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="${afford ? '#f0b429' : '#9a9282'}" stroke-width="2.2" class="lock"><rect x="5" y="11" width="14" height="10"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><span class="num" style="color:${afford ? 'var(--fg)' : 'var(--muted)'}">${fmt(car.price)}</span>`;
    act.textContent = afford ? 'Buy' : `Need ${fmt(car.price - save.get().points)}`; act.disabled = !afford;
  }
}

function renderUpgrades() {
  const car = save.selectedCar(), up = save.upgrades(car.id), pts = save.get().points;
  room.show(car.id); fillPanel(car, 'Upgrading');
  const coin = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><circle cx="12" cy="12" r="4"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3"/></svg>';
  $('upList').innerHTML = `<div class="eyebrow">Workshop</div>` + UPGRADES.map((u) => {
    const lvl = up[u.id], maxed = lvl >= MAX_UPGRADE, cost = upgradeCost(car, lvl);
    const label = u.id === 'special' ? car.special.name : u.name;
    return `<div class="uprow"><b>${label}</b><small>${u.desc}</small><div class="pips">${Array.from({ length: MAX_UPGRADE }, (_, i) => `<i class="${i < lvl ? 'on' : ''}"></i>`).join('')}</div>
      <button class="btn ${!maxed && pts >= cost ? 'primary' : ''}" data-up="${u.id}" ${maxed || pts < cost ? 'disabled' : ''}>${maxed ? 'Max' : coin + fmt(cost)}</button></div>`;
  }).join('');
}

$('upList').addEventListener('click', (e) => {
  const b = e.target.closest('[data-up]'); if (!b || b.disabled) return;
  const car = save.selectedCar(), up = save.upgrades(car.id), k = b.dataset.up;
  if (up[k] >= MAX_UPGRADE) return;
  if (save.spend(upgradeCost(car, up[k]))) { up[k]++; save.write(); sfx.purchase(); renderUpgrades(); refreshPoints(); }
  else sfx.denied();
});

// setup sheet
const MODES = [
  { id: 'deathmatch', name: 'Deathmatch', desc: 'Last car running wins. Bounty, airdrops, arena events.' },
  { id: 'survival', name: 'Survival', desc: 'Endless waves that all hunt you. How far can you go?' },
];
function renderSetup() {
  $('modeSeg').innerHTML = MODES.map((m) => `<button data-mode="${m.id}" aria-pressed="${m.id === setupMode}"><b>${m.name}</b><span>${m.desc}</span></button>`).join('');
  const surv = setupMode === 'survival';
  $('diffBox').hidden = surv; $('bestBox').hidden = !surv;
  $('bestWave').textContent = `Wave ${save.get().best.wave}`;
  $('mapList').innerHTML = MAPS.map((m) => `<button class="mapcard" data-map="${m.id}" aria-pressed="${m === setupMap}">
    <div class="art" style="background:#1a1712 url('assets/maps/${m.id}.jpg') center/cover"></div>
    <b>${m.name}</b><em>${m.tag}</em><span>${m.desc}</span></button>`).join('');
  $('diffSeg').innerHTML = DIFFICULTY.map((d) => `<button data-diff="${d.id}" aria-pressed="${d === setupDiff}">${d.name}<small>${d.enemies} enemies</small></button>`).join('');
  $('sReward').textContent = surv ? `${fmt(KILL_REWARD * 1.2)}/kill + wave bonuses` : `Win: ${fmt(setupDiff.base)} + ${fmt(KILL_REWARD * setupDiff.reward)}/kill`;
}
$('modeSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-mode]'); if (!b) return; setupMode = b.dataset.mode; sfx.click(); renderSetup(); });
$('mapList').addEventListener('click', (e) => { const b = e.target.closest('[data-map]'); if (!b) return; setupMap = MAPS.find((m) => m.id === b.dataset.map); sfx.click(); renderSetup(); });
$('diffSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-diff]'); if (!b) return; setupDiff = DIFFICULTY.find((d) => d.id === b.dataset.diff); sfx.click(); renderSetup(); });

function renderSettings() {
  const st = save.get();
  $('gfxSeg').innerHTML = [['auto', 'Auto'], ['high', 'High'], ['medium', 'Medium'], ['low', 'Low']].map(([id, l]) => `<button data-gfx="${id}" aria-pressed="${st.graphics === id}">${l}</button>`).join('');
  $('ctlSeg').innerHTML = [[0.85, 'Small'], [1, 'Normal'], [1.2, 'Large']].map(([v, l]) => `<button data-ctl="${v}" aria-pressed="${+st.controls === v}">${l}</button>`).join('');
  $('gfxNote').textContent = st.graphics === 'auto' ? `Auto: now ${TIERS[quality.tierId].label.toLowerCase()}, adjusts to keep the game smooth` : 'Fixed quality';
}
function applyControls() { document.documentElement.style.setProperty('--ctl', save.get().controls || 1); }
$('gfxSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-gfx]'); if (!b) return; save.get().graphics = b.dataset.gfx; save.write(); quality.init(b.dataset.gfx); applyQuality(true); sfx.click(); renderSettings(); });
$('ctlSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-ctl]'); if (!b) return; save.get().controls = +b.dataset.ctl; save.write(); applyControls(); sfx.click(); renderSettings(); });

function renderContracts() {
  const list = save.contracts();
  $('cList').innerHTML = list.map((c) => `<div class="contract ${c.done ? 'done' : ''}"><div><b>${c.text}</b><div class="eyebrow num" style="margin-top:3px">${c.done ? 'Complete' : `${c.progress} / ${c.goal}`}</div></div>
    <div class="reward num">${c.done ? '&check;' : '+' + fmt(c.reward)}</div><div class="prog"><i style="width:${(c.progress / c.goal) * 100}%"></i></div></div>`).join('');
  const h = new Date(); const left = 24 - h.getHours();
  $('cDay').textContent = `New contracts in ${left} ${left === 1 ? 'hour' : 'hours'}`;
}
function refreshBadge() { const n = save.contracts().filter((c) => !c.done).length; $('cBadge').hidden = !n; $('cBadge').textContent = n; }

function renderHistory() {
  const st = save.get(), h = st.history;
  const rate = st.stats.matches ? Math.round((st.stats.wins / st.stats.matches) * 100) : 0;
  $('hTotals').innerHTML = [['Matches', st.stats.matches], ['Wins', st.stats.wins], ['Win rate', rate + '%'], ['Kills', st.stats.kills]]
    .map(([k, v]) => `<div class="tot"><span class="eyebrow">${k}</span><b class="num">${typeof v === 'number' ? fmt(v) : v}</b></div>`).join('');
  $('hList').innerHTML = h.length ? `<table class="hist"><thead><tr><th>Result</th><th>Arena</th><th>Car</th><th>Kills</th><th style="text-align:right">Points</th></tr></thead><tbody>${h.map((e) =>
    `<tr><td class="${e.result === 'win' ? 'w' : 'l'}">${e.result === 'win' ? 'Victory' : e.result === 'quit' ? 'Left' : e.result === 'survival' ? 'Wave ' + e.wave : 'Wrecked'}</td><td>${e.map} · ${e.diff}</td><td>${e.car}</td><td class="num">${e.kills}</td><td class="num" style="text-align:right">+${fmt(e.points)}</td></tr>`).join('')}</tbody></table>`
    : '<div class="empty">No battles yet. Your record starts with the first match.</div>';
}

// ---------- HUD ----------
const hud = {
  onStart(g) {
    show('hud');
    $('hName').textContent = g.player.data.name;
    $('hSpecialLbl').textContent = g.player.data.special.name.split(' ')[0].toUpperCase().slice(0, 6);
    $('keys').hidden = isTouch; $('fireBtns').hidden = !isTouch; $('stick').hidden = !isTouch;
    $('feed').innerHTML = ''; $('big').innerHTML = ''; $('toast').textContent = '';
    $('ehps').innerHTML = ''; $('announce').innerHTML = '';
    this.ensureEnemyBars(g);
  },
  ensureEnemyBars(g) {
    for (const c of g.cars) {
      if (c.isPlayer || c.hpEl) continue;
      const el = document.createElement('div'); el.className = 'ehp'; el.innerHTML = `<b>${c.data.name}</b><i></i>`;
      $('ehps').appendChild(el); c.hpEl = el; c.hpFill = el.querySelector('i'); c.hpName = el.querySelector('b');
    }
    for (const el of [...$('ehps').children]) if (!g.cars.some((c) => c.hpEl === el)) el.remove();
  },
  announce(title, sub = '', tone = '') {
    const a = $('announce');
    a.innerHTML = `<div class="a ${tone}"><b>${title}</b>${sub ? `<span>${sub}</span>` : ''}</div>`;
  },
  feedText(t) { const d = document.createElement('div'); d.textContent = t; $('feed').prepend(d); setTimeout(() => d.remove(), 3600); },
  whiteout() { const w = $('whiteout'); w.classList.remove('go'); void w.offsetWidth; w.classList.add('go'); },
  countdown(t) { $('big').innerHTML = `<span>${t}</span>`; if (t === 'FIGHT') setTimeout(() => { if ($('big').textContent === 'FIGHT') $('big').innerHTML = ''; }, 800); },
  banner(t, win) { $('announce').innerHTML = ''; $('big').innerHTML = `<span class="${win ? 'win' : 'lose'}">${t}</span>`; },
  hurt(a) { const v = $('vignette'); v.style.boxShadow = `inset 0 0 120px 40px rgba(216,56,44,${Math.min(0.75, 0.2 + a / 30)})`; clearTimeout(this.vt); this.vt = setTimeout(() => (v.style.boxShadow = ''), 160); },
  feed(k, v) {
    const d = document.createElement('div');
    d.innerHTML = k ? `<b>${k.isPlayer ? 'You' : k.data.name}</b> wrecked ${v.isPlayer ? 'you' : v.data.name}` : `${v.isPlayer ? 'You' : v.data.name} crashed out`;
    $('feed').prepend(d); setTimeout(() => d.remove(), 3600);
  },
  toast(t) { const el = $('toast'); el.textContent = t; clearTimeout(this.tt); this.tt = setTimeout(() => (el.textContent = ''), 1300); },
  flashSpecial() { $('bSpecial').classList.add('on'); setTimeout(() => $('bSpecial').classList.remove('on'), 300); },
  update(g) {
    const p = g.player, frac = Math.max(0, p.hp / p.maxHp);
    $('hBar').style.width = `${frac * 100}%`; $('hBar').classList.toggle('low', frac < 0.3);
    $('hHp').textContent = Math.ceil(Math.max(0, p.hp));
    $('hKills').textContent = `${p.kills} ${p.kills === 1 ? 'KILL' : 'KILLS'}`;
    const left = g.cars.filter((c) => !c.isPlayer && c.alive).length;
    $('hEnemies').innerHTML = g.mode === 'survival' ? `W${g.wave || 0} · ${left}<small>wave · hostiles</small>` : `${left}<small>${left === 1 ? 'enemy left' : 'enemies left'}</small>`;
    const rb = $('bRocket');
    if (p.power) { rb.classList.add('power'); rb.firstChild.textContent = POWERS[p.power.type].short; $('hRockets').textContent = p.power.ammo; }
    else { rb.classList.remove('power'); rb.firstChild.textContent = 'RKT'; $('hRockets').textContent = p.rockets; }
    if (!isTouch) $('keys').textContent = p.power ? `F fires the ${POWERS[p.power.type].name} (${p.power.ammo})` : 'W A S D drive · Space fire · F rocket · E special · Esc pause';
    // special cooldown ring
    const cd = $('cdRing'), cx = cd.getContext('2d'), k = p.specialOn ? 1 : 1 - Math.max(0, p.specialCd) / p.stats.specialCooldown;
    cx.clearRect(0, 0, 160, 160); cx.lineWidth = 8;
    cx.strokeStyle = 'rgba(236,229,214,.15)'; cx.beginPath(); cx.arc(80, 80, 72, 0, 7); cx.stroke();
    cx.strokeStyle = k >= 1 ? '#7cc441' : '#e0682c'; cx.beginPath(); cx.arc(80, 80, 72, -Math.PI / 2, -Math.PI / 2 + k * Math.PI * 2); cx.stroke();
    $('bSpecial').style.borderColor = k >= 1 ? '#7cc441' : '';
    // minimap
    const mm = $('mini'), m = mm.getContext('2d'), W = mm.width, half = g.arena.half, sc = W / (half * 2);
    m.clearRect(0, 0, W, W);
    m.fillStyle = 'rgba(140,130,110,.35)';
    for (const o of g.arena.obstacles) { if (o.dead) continue; if (o.kind === 'box') m.fillRect((o.x - o.hw + half) * sc, (o.z - o.hd + half) * sc, o.hw * 2 * sc, o.hd * 2 * sc); else { m.beginPath(); m.arc((o.x + half) * sc, (o.z + half) * sc, Math.max(2, o.r * sc), 0, 7); m.fill(); } }
    for (const s of g.strikes) { m.strokeStyle = 'rgba(255,60,40,.9)'; m.lineWidth = 2; m.beginPath(); m.arc((s.x + half) * sc, (s.z + half) * sc, s.r * sc, 0, 7); m.stroke(); }
    for (const d of g.drops) { m.fillStyle = '#7fc4ff'; m.fillRect((d.x + half) * sc - 5, (d.z + half) * sc - 5, 10, 10); }
    for (const pk of g.pickups) if (pk.respawn <= 0) { m.fillStyle = pk.type === 'health' ? '#5dff7a' : '#ffb347'; m.fillRect((pk.x + half) * sc - 3, (pk.z + half) * sc - 3, 6, 6); }
    for (const c of g.cars) {
      if (!c.alive) continue;
      const x = (c.x + half) * sc, y = (c.z + half) * sc;
      m.save(); m.translate(x, y); m.rotate(-c.heading + Math.PI);
      m.fillStyle = c.isPlayer ? '#f0b429' : c.bounty ? '#ffd23a' : '#d8382c';
      if (c.bounty) { m.strokeStyle = '#ffd23a'; m.lineWidth = 2; m.beginPath(); m.arc(0, 0, 11, 0, 7); m.stroke(); }
      m.beginPath(); m.moveTo(0, -9); m.lineTo(6, 6); m.lineTo(-6, 6); m.closePath(); m.fill(); m.restore();
    }
    // enemy health bars
    const w = window.innerWidth, h = window.innerHeight, v = new THREE.Vector3();
    for (const c of g.cars) {
      if (!c.hpEl) continue;
      if (!c.alive) { c.hpEl.hidden = true; continue; }
      v.set(c.x, 4.4, c.z).project(g.camera);
      const on = v.z < 1 && Math.abs(v.x) < 1.1 && Math.abs(v.y) < 1.1;
      c.hpEl.hidden = !on;
      if (on) { c.hpEl.classList.toggle('far', !c.bounty && Math.hypot(c.x - g.player.x, c.z - g.player.z) > 38); c.hpName.textContent = c.bounty ? `\u2605 ${c.data.name} \u2605` : c.data.name; c.hpName.style.color = c.bounty ? '#ffd23a' : ''; c.hpFill.style.background = c.bounty ? '#ffc23a' : ''; c.hpEl.style.left = `${(v.x * 0.5 + 0.5) * w}px`; c.hpEl.style.top = `${(-v.y * 0.5 + 0.5) * h}px`; c.hpFill.style.width = `${Math.max(0, c.hp / c.maxHp) * 100}%`; }
    }
  },
  onEnd(r) {
    const cfg = lastConfig, d = cfg.diff, surv = r.mode === 'survival';
    const killPts = Math.round(r.kills * KILL_REWARD * (surv ? 1.2 : d.reward));
    const winPts = r.result === 'win' ? d.base : 0;
    const showPts = r.result === 'loss' ? 10 : 0;
    const bonus = r.stats.bonus.reduce((a, b) => a + b.pts, 0);
    const total = winPts + killPts + showPts + bonus;
    const prevBest = save.get().best.wave;
    save.record({ date: new Date().toISOString(), map: cfg.map.name, diff: surv ? 'Survival' : d.name, car: cfg.car.name, result: r.result, kills: r.kills, points: total, wave: surv ? r.stats.wave : 0 });
    const doneC = save.applyContracts({ result: r.result, map: cfg.map.id, diff: surv ? 'survival' : d.id, stats: r.stats });
    $('rMap').textContent = `${cfg.map.name} · ${surv ? 'Survival' : d.name} · ${cfg.car.name}`;
    $('rTitle').textContent = surv ? `Wave ${r.stats.wave}` : r.result === 'win' ? 'Victory' : 'Wrecked';
    $('rTitle').style.color = r.result === 'win' || (surv && r.stats.wave > prevBest) ? 'var(--hazard)' : 'var(--blood)';
    const mins = Math.floor(r.time / 60), secs = String(Math.floor(r.time % 60)).padStart(2, '0');
    const lines = [['Time in arena', `${mins}:${secs}`], ['Kills', `${r.kills} \u00d7 ${fmt(KILL_REWARD * (surv ? 1.2 : d.reward))}`]];
    if (surv && r.stats.wave > prevBest) lines.push(['New personal best', `Wave ${r.stats.wave}`]);
    if (r.result === 'win') lines.push(['Victory bonus', `+${fmt(winPts)}`]); else if (showPts) lines.push(['Show-up pay', `+${showPts}`]);
    for (const b of r.stats.bonus) lines.push([b.label, `+${fmt(b.pts)}`]);
    $('rLines').innerHTML = lines.map(([a, b]) => `<div><span>${a}</span><span class="num">${b}</span></div>`).join('') + `<div class="total"><span>Scrap earned</span><span class="num">+${fmt(total)}</span></div>`;
    $('rContracts').innerHTML = doneC.map((c) => `<div class="contract done"><div><b>Contract complete</b><div class="eyebrow">${c.text}</div></div><div class="reward num">+${fmt(c.reward)}</div></div>`).join('');
    show('results'); mode = 'results';
    sfx.music.start(0.45);
  },
};

// ---------- match lifecycle ----------
async function startMatch(cfg) {
  lastConfig = cfg;
  if (game) game.dispose();
  $('loader').hidden = false; $('loader').style.opacity = 1;
  try { await preloadWarhorse(); } catch (e) { /* the Warhorse falls back to an empty shell */ }
  await loadKit();
  game = new Game(renderer, hud);
  game.resize(window.innerWidth, window.innerHeight);
  game.start(cfg);
  sfx.music.start(save.get().music ? 0.16 : 0);
  game.resize(window.innerWidth, window.innerHeight);
  mode = 'game';
  $('loader').hidden = true;
  $('rotate').classList.add('need');
}

function toMenu() {
  if (game) { game.dispose(); game = null; }
  mode = 'menu'; show('menu'); setUI('main'); refreshBadge();
  sfx.music.start(0.5);
  $('rotate').classList.remove('need');
  input.reset();
}

// ---------- input ----------
const input = {
  keys: new Set(), stickId: null, sx: 0, sy: 0, jx: 0, jy: 0, gun: false,
  reset() { this.keys.clear(); this.stickId = null; this.jx = this.jy = 0; this.gun = false; $('stickbase').style.display = 'none'; $('bGun').classList.remove('on'); },
  apply() {
    if (!game || mode !== 'game') return;
    const k = this.keys;
    let th = (k.has('KeyW') || k.has('ArrowUp') ? 1 : 0) - (k.has('KeyS') || k.has('ArrowDown') ? 1 : 0);
    let st = (k.has('KeyA') || k.has('ArrowLeft') ? 1 : 0) - (k.has('KeyD') || k.has('ArrowRight') ? 1 : 0);
    if (this.stickId !== null) { th = -this.jy; st = -this.jx; }
    game.setInput(th, st, this.gun || k.has('Space'));
  },
};
addEventListener('keydown', (e) => {
  if (mode === 'game') {
    if (e.code === 'Escape' || e.code === 'KeyP') { pause(); return; }
    if (!e.repeat && e.code === 'KeyF') game.playerRocket();
    if (!e.repeat && e.code === 'KeyE') game.playerSpecial();
    input.keys.add(e.code);
    if (e.code === 'Space' || e.code.startsWith('Arrow')) e.preventDefault();
  } else if (mode === 'paused' && (e.code === 'Escape' || e.code === 'KeyP')) resume();
});
addEventListener('keyup', (e) => input.keys.delete(e.code));
addEventListener('blur', () => input.reset());

const stick = $('stick'), base = $('stickbase'), knob = $('stickknob');
stick.addEventListener('pointerdown', (e) => {
  if (input.stickId !== null) return;
  input.stickId = e.pointerId; stick.setPointerCapture(e.pointerId);
  const r = stick.getBoundingClientRect(); input.sx = e.clientX; input.sy = e.clientY;
  base.style.display = 'block'; base.style.left = `${e.clientX - r.left}px`; base.style.top = `${e.clientY - r.top}px`;
  knob.style.transform = 'translate(-50%,-50%)';
});
stick.addEventListener('pointermove', (e) => {
  if (e.pointerId !== input.stickId) return;
  let dx = e.clientX - input.sx, dy = e.clientY - input.sy; const d = Math.hypot(dx, dy), max = 55 * (save.get().controls || 1);
  if (d > max) { dx *= max / d; dy *= max / d; }
  input.jx = dx / max; input.jy = dy / max;
  if (Math.abs(input.jx) < 0.12) input.jx = 0;
  const k = save.get().controls || 1; knob.style.transform = `translate(calc(-50% + ${dx / k}px), calc(-50% + ${dy / k}px))`;
});
const endStick = (e) => { if (e.pointerId !== input.stickId) return; input.stickId = null; input.jx = input.jy = 0; base.style.display = 'none'; };
stick.addEventListener('pointerup', endStick); stick.addEventListener('pointercancel', endStick);

const gunBtn = $('bGun');
gunBtn.addEventListener('pointerdown', (e) => { gunBtn.setPointerCapture(e.pointerId); input.gun = true; gunBtn.classList.add('on'); });
for (const ev of ['pointerup', 'pointercancel']) gunBtn.addEventListener(ev, () => { input.gun = false; gunBtn.classList.remove('on'); });
$('bRocket').addEventListener('pointerdown', () => { game && game.playerRocket(); $('bRocket').classList.add('on'); setTimeout(() => $('bRocket').classList.remove('on'), 120); });
$('bSpecial').addEventListener('pointerdown', () => game && game.playerSpecial());

// garage drag-to-rotate
let dragX = null;
canvas.addEventListener('pointerdown', (e) => { if (mode === 'menu') { dragX = e.clientX; room.dragging = true; } });
addEventListener('pointermove', (e) => { if (dragX !== null) { room.yaw += (e.clientX - dragX) * 0.01; dragX = e.clientX; } });
addEventListener('pointerup', () => { dragX = null; room.dragging = false; });

// ---------- buttons ----------
const on = (id, fn) => $(id).addEventListener('click', (e) => { sfx.unlock(); fn(e); });
document.addEventListener('pointerdown', () => { sfx.unlock(); if (!sfx.music.playing && mode === 'menu' && save.get().music) sfx.music.start(0.5); }, { passive: true });
addEventListener('keydown', () => { sfx.unlock(); if (!sfx.music.playing && mode === 'menu' && save.get().music) sfx.music.start(0.5); });
on('btnPlay', () => { sfx.confirm(); renderSetup(); show('setup'); });
on('btnGarage', () => { sfx.click(); setUI('garage'); });
on('btnUpgrade', () => { sfx.click(); setUI('upgrade'); });
on('gBack', () => { sfx.click(); setUI('main'); });
on('uBack', () => { sfx.click(); setUI('main'); });
on('gPrev', () => { sfx.click(); browseI = (browseI + CARS.length - 1) % CARS.length; renderGarage(); });
on('gNext', () => { sfx.click(); browseI = (browseI + 1) % CARS.length; renderGarage(); });
on('gAction', () => {
  const car = CARS[browseI];
  if (save.owns(car.id)) { save.select(car.id); sfx.confirm(); }
  else if (save.buy(car)) sfx.purchase(); else sfx.denied();
  renderGarage(); refreshPoints();
});
on('btnSettings', () => { sfx.click(); renderSettings(); show('settings'); });
on('setBack', () => { sfx.click(); show('menu'); });
on('btnContracts', () => { sfx.click(); renderContracts(); show('contracts'); });
on('cBack', () => { sfx.click(); show('menu'); refreshBadge(); });
on('btnMusic', () => { const st = save.get(); st.music = !st.music; save.write(); sfx.setMusic(st.music); $('mus').style.display = st.music ? 'none' : ''; if (st.music) sfx.music.start(0.5); sfx.click(); });
on('btnHistory', () => { sfx.click(); renderHistory(); show('history'); });
on('hBack', () => { sfx.click(); show('menu'); });
on('btnSound', () => { const st = save.get(); st.sound = !st.sound; save.write(); sfx.setEnabled(st.sound); $('snd').style.display = st.sound ? '' : 'none'; sfx.click(); });
on('sBack', () => { sfx.click(); show('menu'); });
on('sFight', () => { sfx.confirm(); const car = save.selectedCar(); startMatch({ car, upgrades: save.upgrades(car.id), map: setupMap, diff: setupDiff, mode: setupMode }); });
on('pausebtn', () => pause());
on('pResume', () => resume());
on('pQuit', () => {
  if (game && !game.over) { game.quit(); save.record({ date: new Date().toISOString(), map: lastConfig.map.name, diff: lastConfig.mode === 'survival' ? 'Survival' : lastConfig.diff.name, car: lastConfig.car.name, result: 'quit', kills: game.player.kills, points: 0 }); }
  toMenu();
});
on('rGarage', () => toMenu());
on('rAgain', () => { const car = save.selectedCar(); startMatch({ ...lastConfig, car, upgrades: save.upgrades(car.id) }); });

function pause() { if (mode !== 'game') return; mode = 'paused'; input.reset(); sfx.engineSet(0, 0); show('pause'); }
function resume() { if (mode !== 'paused') return; mode = 'game'; show('hud'); }
document.addEventListener('visibilitychange', () => { if (document.hidden && mode === 'game') pause(); });

// ---------- loop ----------
function applyQuality(tierChanged = false) {
  const w = window.innerWidth, h = window.innerHeight, pr = quality.pixelRatio(w, h);
  renderer.setPixelRatio(pr); renderer.setSize(w, h, false);
  composer.setPixelRatio(pr); composer.setSize(w, h);
  bloom.enabled = quality.tier.bloom;
  if (tierChanged) {
    renderer.shadowMap.type = quality.tier.soft ? THREE.PCFSoftShadowMap : THREE.PCFShadowMap;
    const shadowScene = game ? game.scene : room.scene;
    shadowScene.traverse((o) => { if (o.isLight && o.shadow && o.castShadow) { o.shadow.mapSize.set(quality.tier.shadow, quality.tier.shadow); if (o.shadow.map) { o.shadow.map.dispose(); o.shadow.map = null; } } });
    shadowScene.traverse((o) => { if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => (m.needsUpdate = true)); });
  }
}
function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  applyQuality();
  room.resize(w, h);
  if (game) game.resize(w, h);
}
addEventListener('resize', resize);

let last = performance.now();
function frame(now) {
  const raw = (now - last) / 1000, dt = Math.min(0.05, raw); last = now;
  if (mode === 'game' && raw < 0.5) { const q = quality.sample(raw); if (q) applyQuality(q === 'tier'); }
  if (mode === 'game') { input.apply(); game.update(dt); draw(game.scene, game.camera); }
  else if ((mode === 'paused' || mode === 'results') && game) draw(game.scene, game.camera);
  else { room.update(dt); room.render(); }
  fireT += dt;
  if (fireT > 1 / 30) { fireT = 0; if (!$('loader').hidden) for (const f of fires) f.step(); }
  requestAnimationFrame(frame);
}

// ---------- boot ----------
sfx.setEnabled(save.get().sound); sfx.setMusic(save.get().music);
$('mus').style.display = save.get().music ? 'none' : '';
refreshBadge(); applyControls();
$('snd').style.display = save.get().sound ? '' : 'none';
resize();
show('menu'); setUI('main');
requestAnimationFrame(frame);
Promise.all([preloadWarhorse().catch(() => {}), loadKit().then(() => room.dress()).catch((e) => console.warn('kit failed', e))]).finally(() => {
  if (save.get().selected === 'warhorse') { room.carId = null; setUI(ui); }
  const l = $('loader'); l.style.opacity = 0; setTimeout(() => (l.hidden = true), 500);
});
window.__ironmetal = { save, get game() { return game; }, startMatch, MAPS, DIFFICULTY, CARS, renderNow: () => game && draw(game.scene, game.camera), renderer };
