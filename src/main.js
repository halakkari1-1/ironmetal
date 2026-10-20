// App controller: renderer, garage showroom, menus, HUD, input and the match lifecycle.
import * as THREE from 'three';
import { CARS, UPGRADES, MAX_UPGRADE, MAPS, DIFFICULTY, KILL_REWARD, CONTRACTS, carStats, upgradeCost } from './data.js';
import { buildCar, preloadModel, preloadModels, modelReady } from './cars3d.js';
import { loadKit } from './kit.js';
import { Game, POWERS, PROP_MODELS } from './game.js';
import { SKYLINE } from './arena.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { save } from './save.js';
import { sfx } from './audio.js';
import { quality, TIERS } from './quality.js';
import { t, applyLang, initLang, getLang } from './i18n.js';

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

// ---------- garage showroom ----------
// The lobby is a painted night scene (assets/lobby/lobby.jpg) with the real 3D car standing on its glowing ring.
// The image is drawn "cover" style; the camera is solved each resize so the 3D ground lines up with the ring
// in the picture. The car turns on the ring, casts its shadow onto the picture and is lit by the scene's lamps.
const LOBBY = {
  url: new URL('../assets/lobby/lobby.jpg', import.meta.url).href,
  w: 2576, h: 1448,          // source size the numbers below were measured on (any resolution with this aspect works)
  ring: [0.6724, 0.674],     // ring centre as fractions of the image
  ringA: 0.2686,             // ring half-width as a fraction of image width
  ringB: 0.0622,             // ring half-height as a fraction of image height
  focal: 0.898,              // lens focal length in image heights (puts the horizon where the picture has it)
  radius: 5,                 // the ring's radius in world metres
  // animated light spots laid over the picture: [x, y, size (fraction of image height), colour, flicker style]
  glows: [[0.083, 0.42, 0.06, '255,170,80', 'a'], [0.165, 0.465, 0.07, '255,170,80', 'b'], [0.966, 0.5, 0.07, '255,170,80', 'a'],
    [0.022, 0.17, 0.05, '255,140,60', 'c'], [0.03, 0.31, 0.05, '255,140,60', 'b'], [0.613, 0.25, 0.05, '255,80,40', 'c'],
    [0.548, 0.18, 0.06, '255,120,40', 'a'], [0.841, 0.14, 0.11, '210,225,255', 'm'], [0.80, 0.33, 0.08, '255,120,50', 'b'],
    [0.47, 0.37, 0.07, '255,110,40', 'c'], [0.335, 0.47, 0.05, '255,170,80', 'a']],
};
class Showroom {
  constructor() {
    const s = this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(50, 1, 0.1, 200);
    const tex = this.bg = new THREE.TextureLoader().load(LOBBY.url, () => this.layout());
    tex.colorSpace = THREE.SRGBColorSpace; tex.generateMipmaps = false; tex.minFilter = THREE.LinearFilter;
    s.background = tex;
    // light that matches the picture: warm lamps front-left, cold moon behind-right, orange glow from the ring
    s.add(new THREE.HemisphereLight(0x8a90b0, 0x2a1810, 0.45));
    const key = this.key = new THREE.SpotLight(0xffa860, 150, 40, 0.6, 0.7, 1.3); key.position.set(-7, 7, 6); key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024); key.shadow.bias = -0.0005; s.add(key, key.target);
    const moon = new THREE.DirectionalLight(0xaec4ff, 1.4); moon.position.set(8, 9, -10); s.add(moon);
    const ringLight = this.ringLight = new THREE.PointLight(0xff7a30, 30, 12, 1.6); ringLight.position.set(0, 0.4, 0); s.add(ringLight);
    // invisible ground that only shows the car's shadow on top of the picture
    const ground = new THREE.Mesh(new THREE.CircleGeometry(14, 40), new THREE.ShadowMaterial({ opacity: 0.55 }));
    ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; s.add(ground);
    this.platform = new THREE.Group(); s.add(this.platform);
    // a few embers drifting up past the car
    const n = 60, pos = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) pos.set([(Math.random() - 0.5) * 14, Math.random() * 7, (Math.random() - 0.5) * 8], i * 3);
    const dg = new THREE.BufferGeometry(); dg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    this.embers = new THREE.Points(dg, new THREE.PointsMaterial({ color: 0xffa050, size: 0.07, transparent: true, opacity: 0.8, depthWrite: false, blending: THREE.AdditiveBlending }));
    s.add(this.embers);
    this.car = null; this.carId = null; this.spin = 0.35; this.yaw = 0.6; this.drop = 0; this.focus = 'right';
    this.dragging = false; this.t = 0; this.w = 1; this.h = 1;
    this.buildGlows();
  }
  dress() { /* kept for older call sites: the lobby no longer needs the environment kit */ }
  // CSS light spots over the picture (lamps flicker, fires breathe, the moon glows); they cost nothing on the GPU.
  buildGlows() {
    const box = this.glowBox = document.createElement('div'); box.id = 'lobbyGlow';
    for (const [, , , rgb, style] of LOBBY.glows) { const d = document.createElement('i'); d.className = `g-${style}`; d.style.background = `radial-gradient(circle, rgba(${rgb},.55) 0%, rgba(${rgb},.18) 35%, rgba(${rgb},0) 70%)`; box.appendChild(d); }
    const fog = document.createElement('b'); fog.className = 'fog'; box.appendChild(fog);
    document.body.insertBefore(box, document.getElementById('vignette'));
  }
  // Cover-fit the picture and solve the camera so the 3D ring sits on the painted one.
  layout() {
    const W = this.w, H = this.h, s = Math.max(W / LOBBY.w, H / LOBBY.h), iw = LOBBY.w * s, ih = LOBBY.h * s, oy = (H - ih) / 2;
    const ox = Math.min(0, Math.max(W - iw, 0.64 * W - LOBBY.ring[0] * iw)); // on narrower screens crop toward the ring so the car stays in view
    const t = this.bg; t.repeat.set(W / iw, H / ih); t.offset.set(-ox / iw, (1 - t.repeat.y) / 2);
    const f = LOBBY.focal * ih, aPx = LOBBY.ringA * iw, bPx = LOBBY.ringB * ih;
    const d = (f * LOBBY.radius) / aPx, el = Math.asin(Math.min(0.5, bPx / aPx));
    const cam = this.camera; cam.fov = (2 * Math.atan(H / 2 / f) * 180) / Math.PI; cam.aspect = W / H;
    cam.position.set(0, d * Math.sin(el), d * Math.cos(el)); cam.lookAt(0, 0, 0);
    const cx = ox + LOBBY.ring[0] * iw, cy = oy + LOBBY.ring[1] * ih;
    cam.setViewOffset(W, H, W / 2 - cx, H / 2 - cy, W, H); cam.updateProjectionMatrix();
    LOBBY.glows.forEach(([gx, gy, gs], i) => { const el2 = this.glowBox.children[i], sz = gs * ih * 2; Object.assign(el2.style, { left: `${ox + gx * iw - sz / 2}px`, top: `${oy + gy * ih - sz / 2}px`, width: `${sz}px`, height: `${sz}px` }); });
    Object.assign(this.glowBox.lastChild.style, { top: `${oy + 0.47 * ih}px`, height: `${0.16 * ih}px` });
  }
  show(id) {
    this.want = id;
    if (this.carId === id && this.car) return;
    if (!modelReady(id)) { // load first, keep the current car on the ring meanwhile
      preloadModel(id).then(() => { if (this.want === id) this.show(id); }).catch(() => {});
      return;
    }
    if (this.car) this.platform.remove(this.car);
    this.car = buildCar(id); this.carId = id;
    const dm = this.car.userData.dims; this.car.scale.setScalar(dm ? Math.min(1, (LOBBY.radius * 1.75) / dm.L) : 1); // long trucks still fit the ring
    this.platform.add(this.car); this.drop = 1;
  }
  resize(w, h) { this.w = w; this.h = h; this.layout(); }
  setVisible(v) { this.glowBox.hidden = !v; }
  update(dt) {
    this.t += dt;
    if (!this.dragging) this.yaw += dt * this.spin;
    this.platform.rotation.y = this.yaw;
    if (this.drop > 0 && this.car) { this.drop = Math.max(0, this.drop - dt * 3.2); const k = this.drop; this.car.position.y = k * k * 3; if (this.drop === 0) sfx.click(); }
    this.ringLight.intensity = 26 + Math.sin(this.t * 2.2) * 6; // the ring breathes
    this.key.intensity = 150 * (0.94 + Math.random() * 0.06); // sodium lamps buzz
    const p = this.embers.geometry.attributes.position, a = p.array;
    for (let i = 0; i < a.length; i += 3) { a[i + 1] += dt * (0.4 + (i % 7) * 0.08); a[i] += Math.sin(this.t + i) * dt * 0.15; if (a[i + 1] > 7) a[i + 1] = 0; }
    p.needsUpdate = true;
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
function show(id) { for (const s of ['menu', 'setup', 'history', 'contracts', 'settings', 'layoutEdit', 'hud', 'pause', 'results']) $(s).hidden = s !== id && !(id === 'pause' && s === 'hud'); }

function statRows(car, up, compareTo = null) {
  const s = car.stats, rows = [[t('Speed'), 'speed', s.speed], [t('Armor'), 'armor', s.armor], [t('Handling'), 'handling', s.handling], [t('Guns'), 'gun', s.gun], [t('Rockets'), 'rocket', s.rocket]];
  return rows.map(([label, key, v]) => {
    const bonus = (up[key] || 0) * 0.6;
    return `<div class="stat"><span>${label}</span><div class="bar"><i style="width:${v * 10}%"></i>${bonus ? `<i class="up" style="left:${v * 10}%;width:${bonus * 10}%"></i>` : ''}</div><span class="num">${v}${bonus ? '+' : ''}</span></div>`;
  }).join('');
}

const CLASS = { sports: 'Sports car', medium: 'Medium', armored: 'Armored', tracked: 'Tracked', monster: 'Monster', tank: 'Tank', heavy: 'Heavy carrier' };
const carDesc = (car) => (getLang() === 'ar' ? car.descAr : car.desc);
function fillPanel(car, eyebrow) {
  const up = save.owns(car.id) ? save.upgrades(car.id) : {};
  $('cpEyebrow').textContent = t(eyebrow);
  $('cpName').textContent = car.name;
  $('cpDriver').textContent = `${t(CLASS[car.cls] || 'Medium')} · ${car.model.length.toFixed(1)} ${t('m')}`;
  $('cpSW').innerHTML = `<span class="pro">\u25B2 ${t(car.strong)}</span><span class="con">\u25BC ${t(car.weak)}</span>`;
  $('cpStats').innerHTML = statRows(car, up);
  $('cpSpecial').innerHTML = `${abilityIcon(car.special.id)}<span>${t(car.special.name)}</span><em class="num">${t('{n}s recharge', { n: Math.round(carStats(car, up).specialCooldown) })}</em>`;
  $('cpSpecialDesc').textContent = t(car.special.desc);
}
// Simple line icons for the nine abilities (used in the garage and on the ability button).
const ICONS = {
  smoke: '<path d="M6 17h11a4 4 0 0 0 0-8 5 5 0 0 0-9.6-1.4A3.6 3.6 0 0 0 6 17z"/><path d="M4 21h14"/>',
  dash: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  toxic: '<circle cx="12" cy="12" r="2.2"/><path d="M12 9.8V4a6 6 0 0 1 5 2.8M14 13.2l5 2.8a6 6 0 0 1-5.6 3M10 13.2 5 16a6 6 0 0 1-.4-5.8"/>',
  riptide: '<path d="M2 15c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2"/><path d="M4 10c3-5 9-6 13-3"/><path d="M14 4l3 3-3 3"/>',
  pulse: '<path d="M12 2v4M12 18v4M2 12h4M18 12h4"/><circle cx="12" cy="12" r="4"/><path d="m11 10-1 2.5h3l-1 2.5"/>',
  ram: '<path d="m5 6 6 6-6 6M12 6l6 6-6 6"/>',
  whip: '<path d="M4 18c0-6 4-10 9-10a5 5 0 0 1 0 10c-2.5 0-4-1.6-4-3.5S10.5 11 12.5 11"/>',
  shell: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
  shield: '<path d="M12 3 5 6v6c0 4.4 3 7.6 7 9 4-1.4 7-4.6 7-9V6z"/>',
};
function abilityIcon(id) { return `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[id] || ICONS.dash}</svg>`; }

function refreshPoints() { $('points').textContent = fmt(save.get().points); }

function setUI(next) {
  ui = next;
  $('mainActions').hidden = next !== 'main';
  $('garageUI').hidden = next !== 'garage';
  $('upgradeUI').hidden = next !== 'upgrade';
  $('carpanel').hidden = next === 'upgrade'; // the workshop list takes the left side; the car stays on its ring
  $('menu').classList.toggle('sub', next !== 'main');
  $('menu').classList.toggle('garage', next === 'garage');
  $('gStory').hidden = $('gCount').hidden = $('cpSW').hidden = next !== 'garage';
  if (next === 'main') { const car = save.selectedCar(); room.show(car.id); fillPanel(car, 'Your ride'); }
  if (next === 'garage') { browseI = CARS.findIndex((c) => c.id === save.get().selected); renderGarage(); }
  if (next === 'upgrade') renderUpgrades();
  refreshPoints();
}

function renderGarage() {
  const car = CARS[browseI], owned = save.owns(car.id), sel = save.get().selected === car.id;
  room.show(car.id);
  for (const k of [-1, 1]) preloadModel(CARS[(browseI + k + CARS.length) % CARS.length].id).catch(() => {}); // next and previous ready to show
  const afford0 = save.get().points >= car.price;
  fillPanel(car, sel ? 'Selected' : owned ? (car.price === 0 ? 'Free' : 'Owned') : afford0 ? 'Can buy' : 'Locked');
  $('gCount').textContent = `${browseI + 1} / ${CARS.length}`;
  $('gStory').textContent = carDesc(car);
  const price = $('gPrice'), act = $('gAction');
  if (owned) { price.hidden = true; act.textContent = t(sel ? 'Selected' : 'Select'); act.disabled = sel; }
  else {
    price.hidden = false;
    const afford = save.get().points >= car.price;
    price.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="${afford ? '#f0b429' : '#9a9282'}" stroke-width="2.2" class="lock"><rect x="5" y="11" width="14" height="10"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg><span class="num" style="color:${afford ? 'var(--fg)' : 'var(--muted)'}">${fmt(car.price)}</span>`;
    act.textContent = afford ? t('Buy') : t('Need {n}', { n: fmt(car.price - save.get().points) }); act.disabled = !afford;
  }
}

function renderUpgrades() {
  const car = save.selectedCar(), up = save.upgrades(car.id), pts = save.get().points;
  room.show(car.id); fillPanel(car, 'Upgrading');
  const coin = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><circle cx="12" cy="12" r="4"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3"/></svg>';
  $('upList').innerHTML = `<div class="eyebrow">${t('Workshop')}</div>` + UPGRADES.map((u) => {
    const lvl = up[u.id], maxed = lvl >= MAX_UPGRADE, cost = upgradeCost(car, lvl);
    const label = t(u.id === 'special' ? car.special.name : u.name);
    return `<div class="uprow"><b>${label}</b><small>${t(u.desc)}</small><div class="pips">${Array.from({ length: MAX_UPGRADE }, (_, i) => `<i class="${i < lvl ? 'on' : ''}"></i>`).join('')}</div>
      <button class="btn ${!maxed && pts >= cost ? 'primary' : ''}" data-up="${u.id}" ${maxed || pts < cost ? 'disabled' : ''}>${maxed ? t('Max') : coin + fmt(cost)}</button></div>`;
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
  { id: 'deathmatch', name: 'Deathmatch', desc: 'Three lives each. Most kills wears the crown. 5 minutes.' },
  { id: 'survival', name: 'Survival', desc: 'Endless waves that all hunt you. How far can you go?' },
];
function renderSetup() {
  $('modeSeg').innerHTML = MODES.map((m) => `<button data-mode="${m.id}" aria-pressed="${m.id === setupMode}"><b>${t(m.name)}</b><span>${t(m.desc)}</span></button>`).join('');
  const surv = setupMode === 'survival';
  $('diffBox').hidden = surv; $('bestBox').hidden = !surv;
  $('bestWave').textContent = t('Wave {n}', { n: save.get().best.wave });
  $('mapList').innerHTML = MAPS.map((m) => `<button class="mapcard" data-map="${m.id}" aria-pressed="${m === setupMap}">
    <div class="art" style="background:#1a1712 url('assets/maps/${m.id}.jpg') center/cover"></div>
    <b>${t(m.name)}</b><em>${t(m.tag)}</em><span>${t(m.desc)}</span></button>`).join('');
  $('diffSeg').innerHTML = DIFFICULTY.map((d) => `<button data-diff="${d.id}" aria-pressed="${d === setupDiff}">${t(d.name)}<small>${t('{n} enemies', { n: d.enemies })}</small></button>`).join('');
  $('sReward').textContent = surv ? t('{a}/kill + wave bonuses', { a: fmt(KILL_REWARD * 1.2) }) : t('Win: {a} + {b}/kill', { a: fmt(setupDiff.base), b: fmt(KILL_REWARD * setupDiff.reward) });
}
$('modeSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-mode]'); if (!b) return; setupMode = b.dataset.mode; sfx.click(); renderSetup(); });
$('mapList').addEventListener('click', (e) => { const b = e.target.closest('[data-map]'); if (!b) return; setupMap = MAPS.find((m) => m.id === b.dataset.map); sfx.click(); renderSetup(); });
$('diffSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-diff]'); if (!b) return; setupDiff = DIFFICULTY.find((d) => d.id === b.dataset.diff); sfx.click(); renderSetup(); });

const SCHEMES = [['classic', 'Classic', 'Up to drive, down to reverse, left and right to steer'], ['direction', 'Direction', 'Point the stick where you want to go'], ['autogas', 'Auto gas', 'The car drives itself; you only steer']];
function renderSettings() {
  const st = save.get();
  $('steerSeg').innerHTML = SCHEMES.map(([id, l]) => `<button data-steer="${id}" aria-pressed="${(st.scheme || 'classic') === id}">${t(l)}</button>`).join('');
  $('steerNote').textContent = t(SCHEMES.find((x) => x[0] === (st.scheme || 'classic'))[2]);
  $('volMaster').value = Math.round(st.volume.master * 100); $('volMusic').value = Math.round(st.volume.music * 100); $('volSfx').value = Math.round(st.volume.sfx * 100);
  $('gfxSeg').innerHTML = [['auto', 'Auto'], ['high', 'High'], ['medium', 'Medium'], ['low', 'Low']].map(([id, l]) => `<button data-gfx="${id}" aria-pressed="${st.graphics === id}">${t(l)}</button>`).join('');
  $('ctlSeg').innerHTML = [[0.85, 'Small'], [1, 'Normal'], [1.2, 'Large']].map(([v, l]) => `<button data-ctl="${v}" aria-pressed="${+st.controls === v}">${t(l)}</button>`).join('');
  $('gfxNote').textContent = st.graphics === 'auto' ? t('Auto: now {q}, adjusts to keep the game smooth', { q: t(TIERS[quality.tierId].label).toLowerCase() }) : t('Fixed quality');
  $('langSeg').innerHTML = [['en', 'English'], ['ar', 'العربية']].map(([id, l]) => `<button data-lang="${id}" aria-pressed="${getLang() === id}" lang="${id}">${l}</button>`).join('');
}
function applyControls() { const L = save.get().layout || {}; document.documentElement.style.setProperty('--ctl', (save.get().controls || 1) * ((L.stick && L.stick.k) || 1)); placeButtons('b', L); }

// ---------- touch button layout ----------
// Defaults are offsets from the bottom-right corner (px at size 1); a saved layout stores centres as screen fractions.
const BTN = { Gun: { r: 74, b: 72, size: 108, font: 16 }, Rocket: { r: 176, b: 64, size: 76, font: 13 }, Special: { r: 80, b: 174, size: 76, font: 13 } };
function btnCenter(id, L) {
  const g = save.get().controls || 1, d = BTN[id], u = L[id], W = innerWidth, H = innerHeight;
  return u && u.fx != null ? { x: u.fx * W, y: u.fy * H } : { x: W - d.r * g - 12, y: H - d.b * g };
}
function placeButtons(prefix, L) {
  const g = save.get().controls || 1;
  for (const id of Object.keys(BTN)) {
    const el = $(prefix + id); if (!el) continue;
    const k = ((L[id] && L[id].k) || 1) * g, c = btnCenter(id, L), size = BTN[id].size * k;
    Object.assign(el.style, { left: `${c.x}px`, top: `${c.y}px`, width: `${size}px`, height: `${size}px`, fontSize: `${BTN[id].font * Math.min(1.3, k)}px` });
  }
}
const editor = { work: {}, sel: 'Gun', drag: null };
function openEditor() {
  editor.work = JSON.parse(JSON.stringify(save.get().layout || {})); editor.sel = 'Gun';
  show('layoutEdit'); drawEditor();
}
function drawEditor() {
  placeButtons('e', editor.work);
  const st = $('eStick'), k = ((editor.work.stick && editor.work.stick.k) || 1) * (save.get().controls || 1), size = 130 * k;
  Object.assign(st.style, { left: `${innerWidth * 0.2}px`, top: `${innerHeight * 0.68}px`, width: `${size}px`, height: `${size}px` });
  for (const id of Object.keys(BTN)) $('e' + id).classList.toggle('sel', editor.sel === id);
  st.classList.toggle('sel', editor.sel === 'stick');
  $('eSize').value = Math.round(((editor.work[editor.sel] && editor.work[editor.sel].k) || 1) * 100);
}
for (const id of Object.keys(BTN)) {
  const el = $('e' + id);
  el.addEventListener('pointerdown', (e) => { el.setPointerCapture(e.pointerId); editor.sel = id; const c = btnCenter(id, editor.work); editor.drag = { id, ox: e.clientX - c.x, oy: e.clientY - c.y }; drawEditor(); });
  el.addEventListener('pointermove', (e) => {
    if (!editor.drag || editor.drag.id !== id) return;
    const x = Math.max(30, Math.min(innerWidth - 30, e.clientX - editor.drag.ox)), y = Math.max(30, Math.min(innerHeight - 30, e.clientY - editor.drag.oy));
    editor.work[id] = Object.assign(editor.work[id] || {}, { fx: x / innerWidth, fy: y / innerHeight }); drawEditor();
  });
  for (const ev of ['pointerup', 'pointercancel']) el.addEventListener(ev, () => { editor.drag = null; });
}
$('eStick').addEventListener('pointerdown', () => { editor.sel = 'stick'; drawEditor(); });
$('eSize').addEventListener('input', (e) => { editor.work[editor.sel] = Object.assign(editor.work[editor.sel] || {}, { k: +e.target.value / 100 }); drawEditor(); });
$('steerSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-steer]'); if (!b) return; save.get().scheme = b.dataset.steer; save.write(); sfx.click(); renderSettings(); });
for (const [id, key] of [['volMaster', 'master'], ['volMusic', 'music'], ['volSfx', 'sfx']]) $(id).addEventListener('input', (e) => { save.get().volume[key] = +e.target.value / 100; initLang();
sfx.setVolumes(save.get().volume); });
for (const id of ['volMaster', 'volMusic', 'volSfx']) $(id).addEventListener('change', () => { save.write(); sfx.click(); });
$('btnEditLayout').addEventListener('click', () => { sfx.click(); openEditor(); });
$('gfxSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-gfx]'); if (!b) return; save.get().graphics = b.dataset.gfx; save.write(); quality.init(b.dataset.gfx); applyQuality(true); sfx.click(); renderSettings(); });
$('langSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-lang]'); if (!b) return; save.get().lang = b.dataset.lang; save.write(); sfx.click(); relabel(); renderSettings(); });
$('ctlSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-ctl]'); if (!b) return; save.get().controls = +b.dataset.ctl; save.write(); applyControls(); sfx.click(); renderSettings(); });

function contractText(c) { // stored text is English; rebuild it from the template so it follows the language
  const tpl = CONTRACTS.find((x) => x.id === c.id), map = MAPS.find((m) => m.id === c.map);
  return tpl ? t(tpl.text, { n: c.goal, map: map ? t(map.name) : '' }) : c.text;
}
function renderContracts() {
  const list = save.contracts();
  $('cList').innerHTML = list.map((c) => `<div class="contract ${c.done ? 'done' : ''}"><div><b>${contractText(c)}</b><div class="eyebrow num" style="margin-top:3px">${c.done ? t('Complete') : `${c.progress} / ${c.goal}`}</div></div>
    <div class="reward num">${c.done ? '&check;' : '+' + fmt(c.reward)}</div><div class="prog"><i style="width:${(c.progress / c.goal) * 100}%"></i></div></div>`).join('');
  const h = new Date(); const left = 24 - h.getHours();
  $('cDay').textContent = t(left === 1 ? 'New contracts in {n} hour' : 'New contracts in {n} hours', { n: left });
}
function refreshBadge() { const n = save.contracts().filter((c) => !c.done).length; $('cBadge').hidden = !n; $('cBadge').textContent = n; }

function renderHistory() {
  const st = save.get(), h = st.history;
  const rate = st.stats.matches ? Math.round((st.stats.wins / st.stats.matches) * 100) : 0;
  $('hTotals').innerHTML = [['Matches', st.stats.matches], ['Wins', st.stats.wins], ['Win rate', rate + '%'], ['Kills', st.stats.kills]]
    .map(([k, v]) => `<div class="tot"><span class="eyebrow">${t(k)}</span><b class="num">${typeof v === 'number' ? fmt(v) : v}</b></div>`).join('');
  $('hList').innerHTML = h.length ? `<table class="hist"><thead><tr><th>${t('Result')}</th><th>${t('Arena')}</th><th>${t('Car')}</th><th>${t('Kills')}</th><th class="end">${t('Points')}</th></tr></thead><tbody>${h.map((e) =>
    `<tr><td class="${e.result === 'win' ? 'w' : 'l'}">${e.result === 'win' ? t('Victory') : e.result === 'quit' ? t('Left') : e.result === 'survival' ? t('Wave {n}', { n: e.wave }) : t('Wrecked')}</td><td>${t(e.map)} · ${t(e.diff)}</td><td>${e.car}</td><td class="num">${e.kills}</td><td class="num end">+${fmt(e.points)}</td></tr>`).join('')}</tbody></table>`
    : `<div class="empty">${t('No battles yet. Your record starts with the first match.')}</div>`;
}

// ---------- HUD ----------
const hud = {
  onStart(g) {
    show('hud');
    $('hName').textContent = g.player.data.name;
    $('hSpecialIc').innerHTML = abilityIcon(g.player.data.special.id);
    $('hSpecialLbl').textContent = t(g.player.data.special.name);
    $('hLives').hidden = false; $('hTimer').hidden = g.mode !== 'deathmatch';
    $('keys').hidden = isTouch; $('fireBtns').hidden = !isTouch; $('stick').hidden = !isTouch;
    applyControls();
    $('feed').innerHTML = ''; $('big').innerHTML = ''; $('toast').textContent = '';
    $('ehps').innerHTML = ''; $('announce').innerHTML = '';
    this.ensureEnemyBars(g);
  },
  ensureEnemyBars(g) {
    for (const c of g.cars) {
      if (c.isPlayer || c.hpEl) continue;
      const el = document.createElement('div'); el.className = 'ehp'; el.innerHTML = `<b>${c.data.name}</b><i></i><u></u>`;
      $('ehps').appendChild(el); c.hpEl = el; c.hpFill = el.querySelector('i'); c.hpName = el.querySelector('b'); c.hpLives = el.querySelector('u');
    }
    for (const el of [...$('ehps').children]) if (!g.cars.some((c) => c.hpEl === el)) el.remove();
  },
  announce(title, sub = '', tone = '') {
    const a = $('announce');
    a.innerHTML = `<div class="a ${tone}"><b>${title}</b>${sub ? `<span>${sub}</span>` : ''}</div>`;
  },
  feedText(s) { const d = document.createElement('div'); d.textContent = s; $('feed').prepend(d); setTimeout(() => d.remove(), 3600); },
  whiteout() { const w = $('whiteout'); w.classList.remove('go'); void w.offsetWidth; w.classList.add('go'); },
  countdown(s) { $('big').innerHTML = `<span>${s}</span>`; if (s === t('FIGHT')) setTimeout(() => { if ($('big').textContent === s) $('big').innerHTML = ''; }, 800); },
  banner(s, win) { $('announce').innerHTML = ''; $('big').innerHTML = `<span class="${win ? 'win' : 'lose'}">${s}</span>`; },
  hurt(a) { const v = $('vignette'); v.style.boxShadow = `inset 0 0 120px 40px rgba(216,56,44,${Math.min(0.75, 0.2 + a / 30)})`; clearTimeout(this.vt); this.vt = setTimeout(() => (v.style.boxShadow = ''), 160); },
  feed(k, v) {
    const d = document.createElement('div');
    d.innerHTML = k ? t('{k} wrecked {v}', { k: `<b>${k.isPlayer ? t('You') : k.data.name}</b>`, v: v.isPlayer ? t('you') : v.data.name }) : t('{v} crashed out', { v: v.isPlayer ? t('You') : v.data.name });
    $('feed').prepend(d); setTimeout(() => d.remove(), 3600);
  },
  toast(s) { const el = $('toast'); el.textContent = s; clearTimeout(this.tt); this.tt = setTimeout(() => (el.textContent = ''), 1300); },
  flashSpecial() { $('bSpecial').classList.add('on'); setTimeout(() => $('bSpecial').classList.remove('on'), 300); },
  update(g, dt = 1 / 60) {
    const p = g.player, frac = Math.max(0, p.hp / p.maxHp);
    $('hBar').style.width = `${frac * 100}%`; $('hBar').classList.toggle('low', frac < 0.3);
    $('hHp').textContent = Math.ceil(Math.max(0, p.hp));
    $('hKills').textContent = `${p.kills} ${t(p.kills === 1 ? 'KILL' : 'KILLS')}`;
    const lv = `${p.lives}|${p.alive}`;
    if (this.lv !== lv) { this.lv = lv; $('hLives').innerHTML = Array.from({ length: 3 }, (_, i) => `<i class="${i < p.lives ? 'on' : ''}"></i>`).join(''); }
    const tl = g.timeLeft();
    if (tl != null) { const m = Math.floor(tl / 60), s2 = String(Math.floor(tl % 60)).padStart(2, '0'); $('hTimer').textContent = `${m}:${s2}`; $('hTimer').classList.toggle('low', tl < 30); }
    if (g.mode === 'survival') { const left = g.cars.filter((c) => !c.isPlayer && c.alive).length; $('hEnemies').innerHTML = `W${g.wave || 0} · ${left}<small>${t('wave · hostiles')}</small>`; }
    else { // live scoreboard: top kills, crown holder first
      const order = [...g.cars].sort((a, b) => b.kills - a.kills || (b.isPlayer ? 1 : 0) - (a.isPlayer ? 1 : 0));
      const lead = g.cars.find((c) => c.bounty) || order[0], rank = order.indexOf(p) + 1, alive = g.cars.filter((c) => g.inPlay(c)).length;
      const chip = (c) => `<span class="${c.isPlayer ? 'me' : ''}">${c.bounty ? '\u265B ' : ''}${c.isPlayer ? t('You') : c.data.name.split(' ').pop()} <b>${c.kills}</b>${c.isPlayer ? `<bdi class="rk">#${rank}/${alive}</bdi>` : ''}</span>`;
      const html = lead === p ? chip(p) : chip(lead) + chip(p);
      if (this.sb !== html) { this.sb = html; $('hEnemies').innerHTML = `<div class="sb">${html}</div>`; }
    }
    const rb = $('bRocket');
    if (p.power) { rb.classList.add('power'); rb.firstChild.textContent = t(POWERS[p.power.type].short); $('hRockets').textContent = p.power.ammo; }
    else { rb.classList.remove('power'); rb.firstChild.textContent = t('RKT'); $('hRockets').textContent = p.rockets; }
    if (!isTouch) $('keys').textContent = p.power ? t('F fires the {p} ({n})', { p: t(POWERS[p.power.type].name), n: p.power.ammo }) : t('W A S D drive · Space fire · F rocket · E special · C camera · Esc pause');
    // special cooldown ring
    // ability button: blue ring = active (time left), orange = recharging (seconds shown), green = ready, dim = can't use now
    const sp = p.data.special, active = !!p.specialOn, blocked = !p.alive || p.skidT > 0 || g.state !== 'fight';
    const k = active ? Math.max(0, p.specialT) / Math.max(0.01, (sp.duration || 1) * Math.min(1.4, p.stats.specialPower)) : 1 - Math.max(0, p.specialCd) / p.stats.specialCooldown;
    const st = blocked ? 'off' : active ? 'active' : k >= 1 ? 'ready' : 'cool';
    const secs = st === 'cool' ? Math.ceil(Math.max(0, p.specialCd)) : st === 'active' ? Math.ceil(Math.max(0, p.specialT)) : '';
    const key = `${st}|${secs}|${Math.round(k * 60)}`;
    if (this.abKey !== key) {
      this.abKey = key;
      const cd = $('cdRing'), cx = cd.getContext('2d');
      cx.clearRect(0, 0, 160, 160); cx.lineWidth = 8;
      cx.strokeStyle = 'rgba(236,229,214,.15)'; cx.beginPath(); cx.arc(80, 80, 72, 0, 7); cx.stroke();
      cx.strokeStyle = st === 'active' ? '#58a8ff' : st === 'ready' ? '#7cc441' : '#e0682c'; cx.beginPath(); cx.arc(80, 80, 72, -Math.PI / 2, -Math.PI / 2 + Math.min(1, k) * Math.PI * 2); cx.stroke();
      const b = $('bSpecial'); b.dataset.state = st; $('hSpecialCd').textContent = secs;
    }
    // minimap: 12 times a second is plenty; the obstacle layer is drawn once per arena (and when a barrel goes) and reused
    this.mmT = (this.mmT || 0) + dt;
    if (this.mmT < 1 / 12) { this.updateBars(g); return; }
    this.mmT = 0;
    const mm = $('mini'), m = mm.getContext('2d'), W = mm.width, half = g.arena.half, sc = W / (half * 2);
    const live = g.arena.obstacles.reduce((n, o) => n + (o.dead ? 0 : 1), 0);
    if (this.mmArena !== g.arena || this.mmLive !== live) {
      this.mmArena = g.arena; this.mmLive = live;
      const L = this.mmLayer || (this.mmLayer = document.createElement('canvas')); L.width = L.height = W; const lc = L.getContext('2d');
      lc.fillStyle = 'rgba(140,130,110,.35)';
      for (const o of g.arena.obstacles) { if (o.dead) continue; if (o.kind === 'box') { lc.save(); lc.translate((o.x + half) * sc, (o.z + half) * sc); lc.rotate(-(o.rot || 0)); lc.fillRect(-o.hw * sc, -o.hd * sc, o.hw * 2 * sc, o.hd * 2 * sc); lc.restore(); } else { lc.beginPath(); lc.arc((o.x + half) * sc, (o.z + half) * sc, Math.max(2, o.r * sc), 0, 7); lc.fill(); } }
    }
    m.clearRect(0, 0, W, W); m.drawImage(this.mmLayer, 0, 0);
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
    this.updateBars(g);
  },
  // enemy health bars follow the cars every frame
  updateBars(g) {
    const w = window.innerWidth, h = window.innerHeight, v = this.v3 || (this.v3 = new THREE.Vector3());
    for (const c of g.cars) {
      if (!c.hpEl) continue;
      if (!c.alive) { c.hpEl.hidden = true; continue; }
      const dm = c.mesh.userData.dims; v.set(c.x, (dm ? dm.H : 3.6) + 0.9, c.z).project(g.camera); // just above the roof
      const on = v.z < 1 && Math.abs(v.x) < 1.1 && Math.abs(v.y) < 1.1;
      c.hpEl.hidden = !on;
      if (on) { c.hpEl.classList.toggle('far', !c.bounty && Math.hypot(c.x - g.player.x, c.z - g.player.z) > 38); if (c.hpCrown !== !!c.bounty) { c.hpCrown = !!c.bounty; c.hpName.textContent = c.bounty ? `\u265B ${c.data.name}` : c.data.name; c.hpName.style.color = c.bounty ? '#ffd23a' : ''; c.hpFill.style.background = c.bounty ? '#ffc23a' : ''; } c.hpEl.style.left = `${(v.x * 0.5 + 0.5) * w}px`; c.hpEl.style.top = `${(-v.y * 0.5 + 0.5) * h}px`; c.hpFill.style.width = `${Math.max(0, c.hp / c.maxHp) * 100}%`; const lt = g.mode === 'deathmatch' ? '\u2022'.repeat(c.lives) : ''; if (c.hpLives.textContent !== lt) c.hpLives.textContent = lt; }
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
    $('rMap').textContent = `${t(cfg.map.name)} · ${t(surv ? 'Survival' : d.name)} · ${cfg.car.name}`;
    $('rTitle').textContent = surv ? t('Wave {n}', { n: r.stats.wave }) : t(r.result === 'win' ? 'Victory' : 'Wrecked');
    $('rTitle').style.color = r.result === 'win' || (surv && r.stats.wave > prevBest) ? 'var(--hazard)' : 'var(--blood)';
    const mins = Math.floor(r.time / 60), secs = String(Math.floor(r.time % 60)).padStart(2, '0');
    const lines = [[t('Time in arena'), `${mins}:${secs}`], [t('Kills'), `${r.kills} \u00d7 ${fmt(KILL_REWARD * (surv ? 1.2 : d.reward))}`]];
    if (surv && r.stats.wave > prevBest) lines.push([t('New personal best'), t('Wave {n}', { n: r.stats.wave })]);
    if (r.result === 'win') lines.push([t('Victory bonus'), `+${fmt(winPts)}`]); else if (showPts) lines.push([t('Show-up pay'), `+${showPts}`]);
    for (const b of r.stats.bonus) lines.push([t(b.label, { n: b.n }), `+${fmt(b.pts)}`]);
    $('rLines').innerHTML = lines.map(([a, b]) => `<div><span>${a}</span><span class="num">${b}</span></div>`).join('') + `<div class="total"><span>${t('Scrap earned')}</span><span class="num">+${fmt(total)}</span></div>`;
    $('rContracts').innerHTML = doneC.map((c) => `<div class="contract done"><div><b>${t('Contract complete')}</b><div class="eyebrow">${contractText(c)}</div></div><div class="reward num">+${fmt(c.reward)}</div></div>`).join('');
    show('results'); mode = 'results';
    sfx.music.start(0.45, 'game');
  },
};

// ---------- match lifecycle ----------
async function startMatch(cfg) {
  lastConfig = cfg;
  if (game) game.dispose();
  $('loader').hidden = false; $('loader').style.opacity = 1;
  // load the player's car and every car that can show up as an enemy in this match
  const maxP = cfg.mode === 'survival' ? 99999 : cfg.diff.maxPrice;
  await preloadModels([cfg.car.id, ...CARS.filter((c) => c.price <= maxP).map((c) => c.id), ...SKYLINE.map((k) => k.id), ...PROP_MODELS]);
  await loadKit();
  room.setVisible(false);
  game = new Game(renderer, hud);
  game.resize(window.innerWidth, window.innerHeight);
  game.start(cfg);
  game.camMode = save.get().camera || 'near';
  game.snapCamera(); updateCamBtn();
  sfx.music.start(0.16, 'game');
  game.resize(window.innerWidth, window.innerHeight);
  mode = 'game';
  $('loader').hidden = true;
  $('rotate').classList.add('need');
}

function toMenu() {
  if (game) { game.dispose(); game = null; }
  mode = 'menu'; show('menu'); setUI('main'); refreshBadge(); room.setVisible(true);
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
    const scheme = save.get().scheme || 'classic', p = game.player;
    if (this.stickId !== null) {
      const mag = Math.min(1, Math.hypot(this.jx, this.jy));
      if (scheme === 'direction') { // point where you want to go; the car turns there by itself
        if (mag < 0.18) { th = 0; st = 0; } else {
          const ch = game.camHeading(), fx = Math.sin(ch), fz = Math.cos(ch), rx = -Math.cos(ch), rz = Math.sin(ch);
          const dx = fx * -this.jy + rx * this.jx, dz = fz * -this.jy + rz * this.jx;
          let diff = Math.atan2(dx, dz) - p.heading; while (diff > Math.PI) diff -= Math.PI * 2; while (diff < -Math.PI) diff += Math.PI * 2;
          st = Math.max(-1, Math.min(1, diff * 2.6)); th = mag * (1 - 0.4 * Math.min(1, Math.abs(diff) / 1.6));
          if (Math.abs(diff) > 2.6 && Math.abs(p.speed) < 3) { th = -0.8 * mag; st = -st; } // target right behind: back up and swing round
        }
      } else if (scheme === 'autogas') { st = -this.jx; th = this.jy > 0.55 ? -1 : 1; }
      else { th = Math.abs(this.jy) < 0.2 ? 0 : -this.jy; st = -Math.sign(this.jx) * Math.pow(Math.min(1, Math.abs(this.jx) * 1.2), 1.5); } // classic: up drives, down reverses; a soft curve keeps small corrections gentle
    } else if (scheme === 'autogas' && isTouch && game.state === 'fight') { th = 1; st = 0; }
    game.setInput(th, st, this.gun || k.has('Space'));
  },
};
addEventListener('keydown', (e) => {
  if (mode === 'game') {
    if (e.code === 'Escape' || e.code === 'KeyP') { pause(); return; }
    if (!e.repeat && e.code === 'KeyF') game.playerRocket();
    if (!e.repeat && e.code === 'KeyE') game.playerSpecial();
    if (!e.repeat && e.code === 'KeyC') cycleCamera();
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
  let dx = e.clientX - input.sx, dy = e.clientY - input.sy; const L0 = save.get().layout || {}, sk = (save.get().controls || 1) * ((L0.stick && L0.stick.k) || 1), d = Math.hypot(dx, dy), max = 55 * sk;
  if (d > max) { dx *= max / d; dy *= max / d; }
  input.jx = dx / max; input.jy = dy / max;
  if (Math.abs(input.jx) < 0.12) input.jx = 0;
  const k = sk; knob.style.transform = `translate(calc(-50% + ${dx / k}px), calc(-50% + ${dy / k}px))`;
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
  else if (save.buy(car)) { sfx.purchase(); toastMenu(t('{car} is yours', { car: car.name })); } else sfx.denied();
  renderGarage(); refreshPoints();
});
on('eReset', () => { sfx.click(); editor.work = {}; drawEditor(); });
on('eSave', () => { sfx.confirm(); save.get().layout = editor.work; save.write(); applyControls(); renderSettings(); show('settings'); });
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
// camera button: near chase -> far chase -> hood, remembered between matches
const CAMS = ['near', 'far', 'hood'];
function cycleCamera() {
  const st = save.get(), next = CAMS[(CAMS.indexOf(st.camera || 'near') + 1) % CAMS.length];
  st.camera = next; save.write(); if (game) game.setCamMode(next); updateCamBtn(); sfx.click();
  hud.toast(t({ near: 'Camera: near', far: 'Camera: far', hood: 'Camera: hood' }[next]));
}
function updateCamBtn() { const m = save.get().camera || 'near'; $('cambtn').dataset.mode = m; $('camLbl').textContent = t({ near: 'NEAR', far: 'FAR', hood: 'HOOD' }[m]); }
$('cambtn').addEventListener('pointerdown', (e) => { e.stopPropagation(); cycleCamera(); });
function toastMenu(msg) { const el = $('menuToast'); el.textContent = msg; el.classList.remove('go'); void el.offsetWidth; el.classList.add('go'); }
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
  applyControls(); if (!$('layoutEdit').hidden) drawEditor();
}
addEventListener('resize', resize);

let last = performance.now();
// Frame pacing saves battery: matches run at up to 60 fps (even on 90/120 Hz screens), menus at 30,
// and a paused or finished match only redraws a few times a second.
let acc = 0;
function frame(now) {
  requestAnimationFrame(frame);
  const target = mode === 'game' ? 60 : mode === 'menu' ? 30 : 8;
  acc += now - last;
  if (acc < 1000 / target - 2) { last = now; return; }
  const raw = acc / 1000, dt = Math.min(0.05, raw); acc = 0; last = now;
  if (mode === 'game' && raw < 0.5) { const q = quality.sample(raw); if (q) applyQuality(q === 'tier'); }
  if (mode === 'game') { input.apply(); game.update(dt); draw(game.scene, game.camera); }
  else if ((mode === 'paused' || mode === 'results') && game) draw(game.scene, game.camera);
  else { room.update(dt); room.render(); }
}

// Re-renders every piece of text after a language change.
function relabel() {
  applyLang(save.get().lang);
  setUI(ui); refreshBadge();
}

// ---------- boot ----------
initLang();
sfx.setVolumes(save.get().volume); sfx.setEnabled(save.get().sound); sfx.setMusic(save.get().music);
$('mus').style.display = save.get().music ? 'none' : '';
refreshBadge(); applyControls();
$('snd').style.display = save.get().sound ? '' : 'none';
resize();
show('menu'); setUI('main');
requestAnimationFrame(frame);
Promise.all([preloadModel(save.get().selected).catch(() => {})]).finally(() => {
  setUI(ui);
  // the rest of the roster loads in the background, one at a time, so browsing the garage is instant
  CARS.reduce((p, c) => p.then(() => new Promise((r) => setTimeout(r, 120))).then(() => preloadModel(c.id).catch(() => {})), Promise.resolve());
  const l = $('loader'); l.style.opacity = 0; setTimeout(() => (l.hidden = true), 500);
});
window.__ironmetal = { save, room, get game() { return game; }, startMatch, MAPS, DIFFICULTY, CARS, renderNow: () => game && draw(game.scene, game.camera), renderer };
