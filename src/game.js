// A single match: cars, physics, weapons, specials, AI, pickups, airdrops, map events, and win/lose.
// Modes: 'deathmatch' (last car running) and 'survival' (endless waves that all hunt the player).
import * as THREE from 'three';
import { CARS, carStats, KILL_REWARD } from './data.js';
import { buildCar, wreck, getModel } from './cars3d.js';
import { t as tr } from './i18n.js';
import { buildArena } from './arena.js';
import { FX } from './fx.js';
import { sfx } from './audio.js';

const CAR_R = 2.1; // fallback; each car has its own hit radius (c.hitR) from its model size
const HR = (c) => c.hitR || CAR_R;
const TAU = Math.PI * 2;
const wrap = (a) => { while (a > Math.PI) a -= TAU; while (a < -Math.PI) a += TAU; return a; };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const R = (a, b) => a + Math.random() * (b - a);
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const v3 = new THREE.Vector3();

export const POWERS = {
  railgun: { name: 'Railgun', short: 'RAIL', ammo: 3, desc: 'Instant beam, punches through armor' },
  napalm: { name: 'Napalm', short: 'NAPLM', ammo: 3, desc: 'Rockets leave burning ground' },
  nuke: { name: 'Mini Nuke', short: 'NUKE', ammo: 1, desc: 'One rocket. Huge blast.' },
};
const LIVES = 3;          // every car comes back twice after being wrecked
const TIME_LIMIT = 300;  // deathmatch ends after five minutes; most kills wins
const STREAKS = { 2: ['DOUBLE WRECK', 40], 3: ['TRIPLE WRECK', 80], 4: ['RAMPAGE', 150], 5: ['UNSTOPPABLE', 220] };
const MAP_EVENT = { scrapyard: 'artillery', refinery: 'rupture', dustbowl: 'sandstorm', shanty: 'artillery', outpost: 'artillery' };

// Push vector that moves a circle (x, z, r) out of an obstacle, or null. Boxes may be rotated (o.rot, radians about Y).
function pushOut(o, x, z, r) {
  if (o.kind === 'circle') {
    const dx = x - o.x, dz = z - o.z, d = Math.hypot(dx, dz);
    if (d >= o.r + r) return null;
    const k = (o.r + r - d) / Math.max(d, 0.01);
    return [dx * k, dz * k];
  }
  const cs = Math.cos(o.rot || 0), sn = Math.sin(o.rot || 0), dx = x - o.x, dz = z - o.z;
  const lx = dx * cs - dz * sn, lz = dx * sn + dz * cs; // into box space
  const px = clamp(lx, -o.hw, o.hw), pz = clamp(lz, -o.hd, o.hd);
  let ex = lx - px, ez = lz - pz, d = Math.hypot(ex, ez), mx, mz;
  if (d >= r) return null;
  if (d < 1e-4) { // centre inside the box: leave by the shallowest side
    const ox = o.hw - Math.abs(lx), oz = o.hd - Math.abs(lz);
    if (ox < oz) { mx = Math.sign(lx || 1) * (ox + r); mz = 0; } else { mx = 0; mz = Math.sign(lz || 1) * (oz + r); }
  } else { const k = (r - d) / d; mx = ex * k; mz = ez * k; }
  return [mx * cs + mz * sn, -mx * sn + mz * cs]; // back to world space
}
export function insideObstacle(o, x, z) {
  if (o.kind === 'circle') return Math.hypot(x - o.x, z - o.z) < o.r;
  const cs = Math.cos(o.rot || 0), sn = Math.sin(o.rot || 0), dx = x - o.x, dz = z - o.z;
  return Math.abs(dx * cs - dz * sn) < o.hw && Math.abs(dx * sn + dz * cs) < o.hd;
}

// Prop models (assets/models/<id>.js) used in a match; main.js preloads them with the cars.
export const PROP_MODELS = ['crown', 'medkit', 'ammo', 'dropcrate', 'parachute'];
const propBoxes = new Map();
// A copy of a prop model scaled so its longest side is `size`, centred on its pivot (or standing on it with
// { stand: true }). Copies share the loaded geometry and materials. Null if the model isn't loaded, so callers
// can fall back to the simple procedural version.
function propModel(id, size, { stand = false } = {}) {
  const src = getModel(id); if (!src) return null;
  if (!propBoxes.has(id)) propBoxes.set(id, new THREE.Box3().setFromObject(src));
  const box = propBoxes.get(id), dim = box.getSize(new THREE.Vector3()), k = size / Math.max(dim.x, dim.y, dim.z);
  const m = src.clone(true); m.scale.setScalar(k);
  m.position.set(-(box.min.x + box.max.x) / 2 * k, stand ? -box.min.y * k : -(box.min.y + box.max.y) / 2 * k, -(box.min.z + box.max.z) / 2 * k);
  const g = new THREE.Group(); g.add(m); g.userData.h = dim.y * k;
  return g;
}

export class Game {
  constructor(renderer, hud) {
    this.renderer = renderer;
    this.hud = hud;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(62, 1, 0.5, 600);
    this.running = false;
  }

  start({ car, upgrades, map, diff, mode = 'deathmatch' }) {
    this.map = map; this.mode = mode;
    this.diff = mode === 'survival' ? { ...diff, focus: 0.45, enemies: 0 } : diff;
    this.arena = buildArena(this.scene, map);
    this.fx = new FX(this.scene);
    this.cars = []; this.bullets = []; this.rockets = []; this.mines = []; this.pickups = []; this.drops = []; this.zones = []; this.strikes = []; this.wrecks = [];
    this.time = 0; this.state = 'countdown'; this.countdown = 3.5; this.shake = 0; this.over = false;
    this.stats = { kills: 0, rocketKills: 0, barrels: 0, airdrops: 0, streakMax: 0, bounty: 0, wave: 0, firstBlood: false, bonus: [] };
    this.streak = 0; this.lastKillT = -99;
    this.dropT = R(18, 26); this.eventT = R(22, 30); this.storm = 0;
    this.baseFog = { near: this.scene.fog.near, far: this.scene.fog.far, color: this.scene.fog.color.clone() };
    this.bulletGeo = new THREE.BoxGeometry(0.1, 0.1, 2.2);
    this.bulletMat = new THREE.MeshBasicMaterial({ color: 0xffe08a });
    this.enemyBulletMat = new THREE.MeshBasicMaterial({ color: 0xff8a5a });

    const spawns = [...this.arena.spawns].sort(() => Math.random() - 0.5);
    this.spawns = spawns;
    this.player = this.addCar(car, upgrades, spawns[0], true);
    if (mode === 'deathmatch') {
      const pool = CARS.filter((c) => c.price <= diff.maxPrice && c.id !== car.id).sort(() => Math.random() - 0.5);
      for (let i = 0; i < diff.enemies; i++) this.addCar(pool[i % pool.length], this.lvl(diff.level), spawns[i + 1], false);
    } else { this.wave = 0; this.breakT = 0; }
    this.buildPickups();
    this.camPos = new THREE.Vector3(); this.camLook = new THREE.Vector3();
    this.snapCamera();
    const snd = car.sound || {};
    sfx.preloadFiles(this.cars.flatMap((c) => Object.values((c.data.sound && c.data.sound.files) || {})));
    sfx.engineStart(snd.engine, snd.files && snd.files.engine);
    this.running = true;
    this.hud.onStart(this);
  }
  lvl(l) { return { gun: l, rocket: l, armor: l, speed: l, special: l }; }

  addCar(data, upgrades, spawn, isPlayer, hpMul = 1) {
    const stats = carStats(data, upgrades);
    if (!isPlayer) stats.hp = Math.round(stats.hp * this.diff.hp * hpMul);
    const mesh = buildCar(data.id);
    this.scene.add(mesh);
    const bb = new THREE.Box3().setFromObject(mesh), sz = bb.getSize(new THREE.Vector3());
    const rad = clamp(Math.min(sz.x, sz.z) / 2 * 0.92, 0.85, 1.7), halfLen = Math.max(0.4, Math.max(sz.x, sz.z) / 2 - rad);
    const c = {
      data, stats, mesh, isPlayer,
      x: spawn.x, z: spawn.z, heading: spawn.heading, speed: 0, kx: 0, kz: 0, y: 0, vy: 0, rx: 0, rz: 0, srx: 0, srz: 0,
      hp: stats.hp, maxHp: stats.hp, alive: true, rad, halfLen, hitR: rad + halfLen * 0.6 + 0.35, slowT: 0, jamT: 0, skidT: 0, skidSpin: 0, hideT: 0, spinT: 0, roofY: bb.max.y, lenZ: sz.z, lives: this.mode === 'survival' && !isPlayer ? 1 : LIVES, respawnT: 0, invuln: 0,
      throttle: 0, steer: 0, firing: false,
      gunCd: 0, rocketCd: 0, rockets: 6, specialCd: 2, specialT: 0, specialOn: null, power: null,
      kills: 0, lastHit: 0, lastAttacker: null, lastCause: null, muzzleI: 0, deathT: 0, rammed: new Set(),
      dmgMul: isPlayer ? 1 : this.diff.dmg,
      ai: isPlayer ? null : { target: null, retarget: 0, stuck: 0, reverseT: 0, rocketT: R(2, 4), strafe: Math.random() < 0.5 ? 1 : -1, specialT: R(3, 6), goal: null },
    };
    this.attachBubble(c);
    this.cars.push(c);
    return c;
  }

  attachBubble(c) {
    if (c.data.special.id !== 'shield') return;
    const dm = c.mesh.userData.dims, br = dm ? Math.max(dm.L, dm.W) * 0.62 : 3.4;
    c.bubble = new THREE.Mesh(new THREE.SphereGeometry(br, 18, 12), new THREE.MeshBasicMaterial({ color: 0x7fd8ff, transparent: true, opacity: 0.22, depthWrite: false, blending: THREE.AdditiveBlending }));
    c.bubble.visible = false; c.mesh.add(c.bubble); c.bubble.position.y = dm ? dm.H * 0.45 : 1.2;
  }
  inPlay(c) { return c.alive || c.respawnT > 0; }

  // Brings a wrecked car back at the spawn point farthest from its enemies, briefly invulnerable.
  respawn(c) {
    const old = c.mesh;
    this.wrecks.push({ mesh: old, t: 0 });
    if (c.crown) { old.remove(c.crown); }
    c.mesh = buildCar(c.data.id); this.scene.add(c.mesh);
    this.attachBubble(c);
    c.roofSpot = null; if (c.crown) { const spot = this.roofSpot(c); c.mesh.add(c.crown); c.crown.position.copy(spot); }
    const foes = this.cars.filter((o) => o !== c && o.alive);
    let best = this.spawns[0], bestD = -1;
    for (const sp of this.spawns) { const d = foes.length ? Math.min(...foes.map((o) => Math.hypot(o.x - sp.x, o.z - sp.z))) : 0; if (d > bestD) { bestD = d; best = sp; } }
    Object.assign(c, { x: best.x, z: best.z, heading: best.heading, speed: 0, kx: 0, kz: 0, y: 0, vy: 0, rx: 0, rz: 0, srx: 0, srz: 0,
      hp: c.maxHp, alive: true, rockets: 6, specialCd: 2, specialOn: null, specialT: 0, power: null, lastAttacker: null, lastCause: null, invuln: 2.5, respawnT: 0, steerS: 0, slowT: 0, jamT: 0, skidT: 0, hideT: 0, spinT: 0 });
    c.rammed.clear();
    c.mesh.position.set(c.x, 0, c.z); c.mesh.rotation.set(0, c.heading, 0);
    this.fx.heal(c.x, c.z); this.fx.ring(c.x, c.z, 6, 0x9fd4ff);
    if (c.isPlayer) { this.hud.announce(this.t('BACK IN THE FIGHT'), this.t(c.lives === 1 ? 'Last life' : '{n} lives left', { n: c.lives }), 'green'); this.snapCamera(); }
    if (c.ai) c.ai.target = null;
    this.hud.ensureEnemyBars(this);
  }
  // The crown always sits on the car with the most kills (ties keep the current holder).
  updateLeader() {
    if (this.mode !== 'deathmatch') return;
    const pool = this.cars.filter((o) => this.inPlay(o) && o.kills > 0);
    if (!pool.length) return;
    const top = Math.max(...pool.map((o) => o.kills));
    const holder = this.cars.find((o) => o.bounty);
    if (holder && this.inPlay(holder) && holder.kills === top) return;
    const next = pool.find((o) => o.kills === top);
    if (next && next !== holder) this.setBounty(next, true);
  }
  // Where the crown sits: cast down onto the rear half of the roof so it clears the gun turret.
  roofSpot(c) {
    if (c.roofSpot) return c.roofSpot.clone();
    const m = c.mesh, rot = m.rotation.y, pos = m.position.clone(); m.rotation.y = 0; m.position.set(0, 0, 0); m.updateMatrixWorld(true);
    const rc = new THREE.Raycaster(), hits = [];
    for (const z of [-0.22, -0.12, 0]) { rc.set(new THREE.Vector3(0, c.roofY + 2, z * (c.lenZ || 4)), new THREE.Vector3(0, -1, 0)); const h = rc.intersectObject(m, true).find((x) => x.object.visible && !x.object.isPoints); if (h) hits.push(h.point); }
    m.rotation.y = rot; m.position.copy(pos); m.updateMatrixWorld(true);
    const best = hits.sort((a, b) => a.y - b.y)[Math.floor(hits.length / 2)] || new THREE.Vector3(0, c.roofY, 0);
    c.roofSpot = best.clone(); c.roofSpot.y += 0.02;
    return c.roofSpot.clone();
  }
  setBounty(c, announce = true) {
    for (const o of this.cars) if (o.crown) { o.mesh.remove(o.crown); o.crown = null; o.bounty = false; }
    if (!c || !c.alive) return;
    c.bounty = true;
    const g = propModel('crown', 1.3, { stand: true }) || this.simpleCrown();
    g.position.copy(this.roofSpot(c)); // sits right on the roof
    c.mesh.add(g); c.crown = g;
    if (announce) this.hud.announce(this.t(c.isPlayer ? 'YOU TAKE THE CROWN' : 'NEW LEADER'), c.isPlayer ? this.t('Every car is hunting you now') : this.t('{car} has the most kills', { car: c.data.name }), 'gold');
  }

  simpleCrown() {
    const g = new THREE.Group(); g.scale.setScalar(0.85);
    const gold = new THREE.MeshStandardMaterial({ color: 0xffc23a, emissive: 0x8a5200, emissiveIntensity: 0.55, metalness: 0.85, roughness: 0.3 });
    const band = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.6, 0.35, 10, 1, true), gold); band.position.y = 0.17; g.add(band);
    for (let i = 0; i < 5; i++) { const s = new THREE.Mesh(new THREE.ConeGeometry(0.14, 0.5, 4), gold); const a = (i / 5) * TAU; s.position.set(Math.cos(a) * 0.5, 0.57, Math.sin(a) * 0.5); g.add(s); }
    return g;
  }

  // Health (Neon Medkit Chest) and rocket (Spike Ammo Crate) pickups, floating over a coloured ground ring.
  buildPickups() {
    for (const s of this.arena.pickupSpots) {
      this.nudgeClear(s, 3);
      const g = propModel(s.type === 'health' ? 'medkit' : 'ammo', 2.1) || this.simplePickup(s.type);
      g.position.set(s.x, 1.4, s.z);
      const ring = new THREE.Mesh(new THREE.TorusGeometry(1.6, 0.08, 6, 24), new THREE.MeshBasicMaterial({ color: s.type === 'health' ? 0x5dff7a : 0xffb347 }));
      ring.rotation.x = Math.PI / 2; ring.position.y = -1.2; g.add(ring);
      this.scene.add(g);
      this.pickups.push({ ...s, mesh: g, respawn: 0 });
    }
  }
  simplePickup(type) {
    const g = new THREE.Group();
    if (type === 'health') {
      const cross = new THREE.MeshBasicMaterial({ color: 0xffffff });
      g.add(new THREE.Mesh(new THREE.BoxGeometry(1.4, 1.4, 1.4), new THREE.MeshStandardMaterial({ color: 0x2b8a3e, emissive: 0x1d6b2c, emissiveIntensity: 0.8 })),
        new THREE.Mesh(new THREE.BoxGeometry(1.0, 0.3, 1.45), cross), new THREE.Mesh(new THREE.BoxGeometry(0.3, 1.0, 1.45), cross));
    } else {
      g.add(new THREE.Mesh(new THREE.BoxGeometry(1.8, 1.0, 1.2), new THREE.MeshStandardMaterial({ color: 0x9c6b1f, emissive: 0x7a4a10, emissiveIntensity: 0.7 })));
      const tipMat = new THREE.MeshStandardMaterial({ color: 0xd8d0c0 });
      for (let i = -1; i <= 1; i++) { const r = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.5, 6), tipMat); r.position.set(i * 0.45, 0.7, 0); g.add(r); }
    }
    return g;
  }
  nudgeClear(s, pad) {
    for (const o of this.arena.obstacles) {
      const d = Math.hypot(s.x - o.x, s.z - o.z), r = (o.r || Math.hypot(o.hw, o.hd)) + pad;
      if (d < r) { const k = r / Math.max(d, 0.1); s.x = o.x + (s.x - o.x) * k; s.z = o.z + (s.z - o.z) * k; }
    }
    const h = this.arena.half - 5; s.x = clamp(s.x, -h, h); s.z = clamp(s.z, -h, h);
    return s;
  }

  // ---------- input ----------
  setInput(throttle, steer, firing) { if (!this.player) return; this.player.throttle = throttle; this.player.steer = steer; this.player.firing = firing; }
  playerRocket() { if (this.state === 'fight' && this.player.alive) this.fireRocket(this.player); }
  playerSpecial() { if (this.state === 'fight' && this.player.alive) this.useSpecial(this.player); }

  // ---------- main loop ----------
  update(dt) {
    if (!this.running) return;
    dt = Math.min(dt, 0.05);
    this.time += dt;
    if (this.state === 'countdown') {
      const before = Math.ceil(this.countdown);
      this.countdown -= dt;
      const now = Math.ceil(this.countdown);
      if (now !== before && now >= 0) { this.hud.countdown(now > 0 ? String(now) : tr('FIGHT')); sfx.countdown(now === 0); }
      if (this.countdown <= 0) { this.state = 'fight'; if (this.mode === 'survival') this.nextWave(); }
    }
    const active = this.state === 'fight' || this.state === 'ending';
    for (const c of this.cars) {
      if (!c.alive) {
        this.updateWreck(c, dt);
        if (c.respawnT > 0 && this.state === 'fight') { c.respawnT -= dt; if (c.respawnT <= 0) this.respawn(c); }
        continue;
      }
      if (c.invuln > 0) { c.invuln -= dt; c.mesh.visible = c.invuln <= 0 || Math.floor(c.invuln * 10) % 2 === 0; }
      if (active && !c.isPlayer) this.think(c, dt);
      if (!active) { c.throttle = 0; c.steer = 0; c.firing = false; }
      this.drive(c, dt);
      this.weapons(c, dt);
      if (c.crown) c.crown.rotation.y += dt * 2;
    }
    this.collideCars();
    for (const st of this.arena.stacks || []) if (st.big) { if (Math.random() < dt * 3) this.fx.towerSmoke(st.x, st.y, st.z); } else if (Math.random() < dt * 2.2) // chimney smoke drifting off the district
      this.fx.smoke.spawn(st.x + R(-0.4, 0.4), st.y, st.z + R(-0.4, 0.4), R(1.5, 3), R(2, 3.5), R(-0.5, 0.5), R(5, 7), 3, 11, [0.3, 0.28, 0.26, 0.45], [0.42, 0.4, 0.38, 0], -0.15, 0.3);
    for (const b of this.arena.blazes || []) if (Math.random() < dt * 5) this.fx.flames(b.x, b.y, b.z, 3.2); // fires in the skyscrapers
    this.wrecks = this.wrecks.filter((w) => { // old wrecks smoulder, then sink out of the way
      w.t += dt;
      if (w.t < 5 && Math.random() < 0.3) this.fx.burn(w.mesh.position.x, w.mesh.position.y + 1.2, w.mesh.position.z);
      if (w.t > 7) w.mesh.position.y -= dt * 0.8;
      if (w.t > 10) { this.scene.remove(w.mesh); return false; }
      return true;
    });
    this.updateBullets(dt); this.updateRockets(dt); this.updateMines(dt); this.updatePickups(dt);
    this.updateZones(dt); this.updateStrikes(dt);
    if (this.state === 'fight') { this.updateDrops(dt); this.updateEvents(dt); if (this.mode === 'survival') this.updateWaves(dt); }
    this.fx.update(dt);
    this.updateCamera(dt);
    const p = this.player;
    sfx.engineSet(Math.abs(p.throttle), clamp(Math.abs(p.speed) / p.stats.maxSpeed, 0, 1));
    if (this.state === 'fight') this.checkEnd();
    if (this.state === 'ending') { this.endT -= dt; if (this.endT <= 0) this.finish(); }
    this.hud.update(this, dt);
  }

  resize(w, h) { this.camera.aspect = w / h; this.camera.fov = this.baseFov(); this.camera.updateProjectionMatrix(); if (this.fx) this.fx.setScale(h); }
  // keeps roughly the same horizontal view from 20:9 phones to 4:3 tablets
  baseFov() { const a = this.camera.aspect; return a < 1 ? 78 : 62 + Math.max(0, 1.75 - a) * 20; }

  // ---------- survival waves ----------
  nextWave() {
    this.wave++; this.stats.wave = this.wave;
    const n = Math.min(1 + Math.floor(this.wave * 0.7), 7);
    const tiers = [1500, 2500, 3500, 4500, 99999];
    const pool = CARS.filter((c) => c.price <= tiers[Math.min(tiers.length - 1, Math.floor((this.wave - 1) / 2))]);
    const lvl = Math.min(5, Math.floor((this.wave - 1) / 2));
    this.diff.dmg = Math.min(1.05, 0.38 + this.wave * 0.055);
    const far = [...this.spawns].sort((a, b) => Math.hypot(b.x - this.player.x, b.z - this.player.z) - Math.hypot(a.x - this.player.x, a.z - this.player.z));
    // clear old wrecks so the arena stays readable
    this.cars = this.cars.filter((c) => { if (!c.alive && !c.isPlayer) { this.scene.remove(c.mesh); return false; } return true; });
    for (let i = 0; i < n; i++) {
      const s = far[i % far.length], c = this.addCar(pick(pool), this.lvl(lvl), { x: s.x + R(-3, 3), z: s.z + R(-3, 3), heading: s.heading }, false, 0.68 + this.wave * 0.05);
      c.dmgMul = this.diff.dmg;
    }
    if (this.wave % 3 === 0) this.setBounty(pick(this.cars.filter((c) => c.alive && !c.isPlayer)), false);
    this.hud.ensureEnemyBars(this);
    this.hud.announce(tr('WAVE {n}', { n: this.wave }), tr('{n} hostiles inbound', { n }), 'red');
    sfx.alarm();
  }
  updateWaves(dt) {
    const left = this.cars.filter((c) => !c.isPlayer && this.inPlay(c)).length;
    if (left > 0 || !this.player.alive) return;
    if (this.breakT <= 0) {
      this.breakT = 5;
      const p = this.player; p.hp = Math.min(p.maxHp, p.hp + p.maxHp * 0.35); p.rockets = Math.min(12, p.rockets + 4);
      this.fx.heal(p.x, p.z); sfx.pickup();
      const pts = 40 + this.wave * 15;
      this.stats.bonus.push({ label: 'Wave {n} cleared', n: this.wave, pts });
      this.hud.announce(tr('WAVE {n} CLEARED', { n: this.wave }), tr('+{n} · armor patched', { n: pts }), 'green');
    }
    this.breakT -= dt;
    if (this.breakT <= 0) this.nextWave();
  }

  // ---------- driving ----------
  drive(c, dt) {
    const s = c.stats;
    const nitro = c.specialOn === 'nitro', ram = c.specialOn === 'ram';
    const dash = c.specialOn === 'dash', slow = c.slowT > 0 ? 0.5 : 1;
    const maxS = s.maxSpeed * (nitro ? 1.75 : 1) * (ram ? 2.1 : 1) * (dash ? 2 : 1) * slow;
    const acc = s.accel * (nitro ? 2 : 1) * (dash ? 4 : 1) * slow;
    if (c.skidT > 0) { c.throttle = 0; c.steer = 0; } // spun out: no control until the skid ends
    if (ram) c.speed = Math.min(maxS, c.speed + acc * 4 * dt);
    else if (c.throttle > 0.05) c.speed += acc * c.throttle * dt * (c.speed < 0 ? 2 : 1);
    else if (c.throttle < -0.05) c.speed += acc * c.throttle * dt * (c.speed > 0 ? 1.8 : 0.7);
    else c.speed -= c.speed * Math.min(1, 2.2 * dt); // lets go of the stick: the car settles quickly
    c.speed = clamp(c.speed, -s.maxSpeed * 0.45, maxS);
    if (!ram && !dash && c.speed > s.maxSpeed * (nitro ? 1.75 : 1) * slow) c.speed -= (c.speed - s.maxSpeed * slow) * 2 * dt;
    // steering eases in and out instead of snapping, which keeps the car stable on a touch stick
    c.steerS = (c.steerS || 0) + (c.steer - (c.steerS || 0)) * Math.min(1, dt * (c.isPlayer ? 20 : 12));
    const turnScale = clamp(c.speed / 4, -1, 1) * (1 - 0.3 * clamp(Math.abs(c.speed) / maxS, 0, 1)); // a little less twitchy at top speed
    c.heading = wrap(c.heading + c.steerS * s.turn * 1.15 * turnScale * dt + (c.skidT > 0 ? c.skidSpin * Math.min(1, c.skidT) * dt : 0));
    const fx = Math.sin(c.heading), fz = Math.cos(c.heading);
    c.x += (fx * c.speed + c.kx) * dt; c.z += (fz * c.speed + c.kz) * dt;
    const kd = Math.exp(-4 * dt); c.kx *= kd; c.kz *= kd;
    this.collideWorld(c);
    c.mesh.position.set(c.x, 0, c.z);
    c.mesh.rotation.y = c.heading;
    c.mesh.rotation.x = THREE.MathUtils.lerp(c.mesh.rotation.x, -clamp(c.throttle * 0.04 - (c.speed < 0 ? 0.02 : 0), -0.05, 0.05), 0.1);
    c.mesh.rotation.z = THREE.MathUtils.lerp(c.mesh.rotation.z, c.steerS * clamp(c.speed / 30, -1, 1) * 0.06, 0.1);
    for (const w of c.mesh.userData.wheels) w.rotation.x += c.speed * dt / 0.5;
    if (Math.abs(c.speed) > 12 && Math.random() < 0.5) this.fx.dust(c.x - fx * 2, c.z - fz * 2, this.map.id === 'dustbowl' ? 1.6 : 0.8);
    if (nitro || ram) this.fx.exhaust(c.x - fx * 2.4, 0.9, c.z - fz * 2.4, fx, fz);
    if (c.hp < c.maxHp * 0.4 && Math.random() < 0.35) this.fx.burn(c.x + fx * 1.2, 1.6, c.z + fz * 1.2);
    if (c.hp < c.maxHp * 0.2 && Math.random() < 0.16) this.fx.flames(c.x + fx * 1.4, 1.3, c.z + fz * 1.4);
  }

  // The car body is three circles along its length (sized from its model), so it can get close to things side-on.
  // On contact only the part of the motion that goes into the obstacle is lost: the car slides along walls.
  collideWorld(c) {
    const fx = Math.sin(c.heading), fz = Math.cos(c.heading), r = c.rad, L = c.halfLen;
    let nx = 0, nz = 0, hit = null, any = false;
    const lim = this.arena.half - 1.0;
    for (const off of [L, 0, -L]) {
      const cx = c.x + fx * off, cz = c.z + fz * off;
      if (cx > lim - r) { c.x -= cx - (lim - r); nx -= 1; any = true; } else if (cx < -lim + r) { c.x += -lim + r - cx; nx += 1; any = true; }
      if (cz > lim - r) { c.z -= cz - (lim - r); nz -= 1; any = true; } else if (cz < -lim + r) { c.z += -lim + r - cz; nz += 1; any = true; }
    }
    if (c.y <= 2) { // airborne wrecks fly over obstacles
      for (const o of this.arena.obstacles) {
        if (o.dead) continue;
        const bound = (o.r || Math.hypot(o.hw, o.hd)) + r + L;
        if (Math.abs(c.x - o.x) > bound || Math.abs(c.z - o.z) > bound) continue;
        for (const off of [L, 0, -L]) {
          const push = pushOut(o, c.x + fx * off, c.z + fz * off, r);
          if (!push) continue;
          c.x += push[0]; c.z += push[1]; nx += push[0]; nz += push[1]; any = true; hit = o;
        }
      }
    }
    if (!any) return;
    const nl = Math.hypot(nx, nz) || 1; nx /= nl; nz /= nl;
    const into = -(fx * nx + fz * nz) * Math.sign(c.speed || 1); // 1 = head-on, 0 = scraping along
    const impact = Math.abs(c.speed) * Math.max(0, into);
    if (into > 0) c.speed *= 1 - 0.85 * into;
    const kn = c.kx * nx + c.kz * nz; if (kn < 0) { c.kx -= kn * nx * 1.4; c.kz -= kn * nz * 1.4; }
    if (impact > 12) { this.bump(c); if (c.alive) this.fx.spark(c.x - nx * r, 1, c.z - nz * r, 8); if (hit && hit.barrel) this.damageObstacle(hit, impact, c); }
  }
  bump(c) { if (c.isPlayer && Math.abs(c.speed) > 6) { this.shake = Math.max(this.shake, 0.25); sfx.crunch(); } }

  collideCars() {
    const cs = this.cars;
    for (let i = 0; i < cs.length; i++) for (let j = i + 1; j < cs.length; j++) {
      const a = cs[i], b = cs[j];
      if (!a.alive && !b.alive) continue;
      if (a.y > 2 || b.y > 2) continue;
      const dx = b.x - a.x, dz = b.z - a.z, d = Math.hypot(dx, dz), min = (a.rad + b.rad) * 1.45;
      if (d >= min || d < 0.001) continue;
      const nx = dx / d, nz = dz / d, push = min - d;
      const ma = a.alive ? a.stats.mass : 50, mb = b.alive ? b.stats.mass : 50, tot = ma + mb;
      a.x -= nx * push * (mb / tot); a.z -= nz * push * (mb / tot);
      b.x += nx * push * (ma / tot); b.z += nz * push * (ma / tot);
      const rel = Math.abs(a.speed) + Math.abs(b.speed);
      for (const [p, q, s] of [[a, b, 1], [b, a, -1]]) {
        if (!p.alive || !q.alive) continue;
        if (p.specialOn === 'ram' && !p.rammed.has(q)) {
          p.rammed.add(q);
          this.damage(q, 48 * p.stats.specialPower * p.dmgMul, p, false, 'ram');
          q.kx += nx * s * 30; q.kz += nz * s * 30;
          this.fx.explosion((a.x + b.x) / 2, (a.z + b.z) / 2, 0.45, { debris: 4 }); sfx.explosion(0.5, this.vol(q), this.panAt(q.x, q.z));
          this.shake = Math.max(this.shake, 0.5);
        }
      }
      if (rel > 22) {
        if (a.alive) this.damage(a, rel * 0.08, b, false, 'crash'); if (b.alive) this.damage(b, rel * 0.08, a, false, 'crash');
        this.fx.spark((a.x + b.x) / 2, 1.2, (a.z + b.z) / 2, 12);
        if (a.isPlayer || b.isPlayer) { sfx.crunch(); this.shake = Math.max(this.shake, 0.35); }
      }
      a.speed *= 0.7; b.speed *= 0.7;
    }
  }

  // ---------- weapons ----------
  weapons(c, dt) {
    const wasCooling = c.specialCd > 0;
    c.gunCd -= dt; c.rocketCd -= dt; c.specialCd -= dt;
    if (c.isPlayer && wasCooling && c.specialCd <= 0 && this.state === 'fight') sfx.ready();
    for (const k of ['slowT', 'jamT', 'skidT', 'hideT', 'spinT']) if (c[k] > 0) c[k] = Math.max(0, c[k] - dt);
    if (c.specialOn) {
      c.specialT -= dt;
      if (c.specialOn === 'flame') this.flameTick(c, dt);
      if (c.specialOn === 'smoke' && Math.random() < dt * 12) { const fx = Math.sin(c.heading), fz = Math.cos(c.heading); this.fx.smokeScreen(c.x - fx * 5, c.z - fz * 5, 3); } // trail behind, the driver still sees ahead
      if (c.specialOn === 'dash' && Math.random() < dt * 40) { const fx = Math.sin(c.heading), fz = Math.cos(c.heading); this.fx.trailColor(c.x - fx * 2.5, 0.8, c.z - fz * 2.5, [1, 0.25, 0.7]); }
      if (c.specialOn === 'shield' && c.bubble) c.bubble.material.opacity = 0.18 + 0.08 * Math.sin(this.time * 12);
      if (c.specialT <= 0) { if (c.bubble) c.bubble.visible = false; if (c.isPlayer && c.specialOn !== 'flame') sfx.abilityEnd(); c.specialOn = null; c.rammed.clear(); }
    }
    if (c.jamT > 0 && Math.random() < dt * 6) this.fx.zap(c.x, 2.2, c.z);
    if (c.slowT > 0 && Math.random() < dt * 4) this.fx.spark(c.x, 1.2, c.z, 3);
    const model = c.mesh.userData.dims && c.mesh.children[0];
    if (model) model.rotation.y = Math.PI / 2 + (c.spinT > 0 ? (1 - c.spinT / 0.55) * TAU : 0); // Rex's tail whip spin
    if (c.firing && c.gunCd <= 0 && this.state === 'fight' && c.jamT <= 0) { this.fireGun(c); c.gunCd = 0.09; }
  }

  worldPoint(c, local) { v3.copy(local).applyAxisAngle(THREE.Object3D.DEFAULT_UP, c.heading); v3.x += c.x; v3.z += c.z; return v3.clone(); }

  aimAt(c, range, cone) {
    let best = null, bestScore = Infinity;
    for (const o of this.cars) {
      if (o === c || !o.alive || o.hideT > 0) continue;
      const dx = o.x - c.x, dz = o.z - c.z, d = Math.hypot(dx, dz);
      if (d > range) continue;
      const ang = Math.abs(wrap(Math.atan2(dx, dz) - c.heading));
      if (ang > cone) continue;
      const score = d * (1 + ang * 2);
      if (score < bestScore) { bestScore = score; best = o; }
    }
    return best;
  }

  fireGun(c) {
    const muzzles = c.mesh.userData.muzzles;
    const m = this.worldPoint(c, muzzles[c.muzzleI++ % muzzles.length]);
    let dir = c.heading;
    const t = c.isPlayer ? this.aimAt(c, 55, 0.32) : c.ai.target;
    if (t && t.alive) {
      const dist = Math.hypot(t.x - c.x, t.z - c.z), lead = dist / 120;
      const tx = t.x + Math.sin(t.heading) * t.speed * lead, tz = t.z + Math.cos(t.heading) * t.speed * lead;
      const want = Math.atan2(tx - m.x, tz - m.z);
      if (Math.abs(wrap(want - c.heading)) < 0.45) dir = want;
    }
    const spread = c.isPlayer ? 0.03 : 0.03 + (1 - this.diff.accuracy) * 0.16;
    dir += R(-spread, spread);
    const dx = Math.sin(dir), dz = Math.cos(dir);
    const b = (this.bulletPool || (this.bulletPool = [])).pop() || new THREE.Mesh(this.bulletGeo, this.bulletMat); // tracers are recycled, not re-created
    b.material = c.isPlayer ? this.bulletMat : this.enemyBulletMat;
    b.position.copy(m); b.rotation.y = dir;
    this.scene.add(b);
    this.bullets.push({ mesh: b, x: m.x, y: m.y, z: m.z, dx, dz, life: 0.5, owner: c, dmg: c.stats.gunDmg * c.dmgMul });
    this.fx.muzzle(m.x + dx * 0.6, m.y, m.z + dz * 0.6, dx, dz, c.isPlayer);
    sfx.gun(this.vol(c) * (c.isPlayer ? 1 : 0.6), (c.data.sound && c.data.sound.gun) || 1, this.pan(c));
  }

  fireRocket(c, opts = {}) {
    if (c.power && !opts.free) return this.firePower(c);
    if (!opts.free) { if (c.rocketCd > 0 || c.rockets <= 0) { if (c.isPlayer && c.rockets <= 0) sfx.denied(); return; } c.rockets--; c.rocketCd = 0.55; }
    const m = this.worldPoint(c, c.mesh.userData.rocketMuzzle);
    let dir = c.heading + (opts.offset || 0);
    if (!opts.offset) {
      const t = c.isPlayer ? this.aimAt(c, 70, 0.4) : c.ai.target;
      if (t && t.alive) { const want = Math.atan2(t.x - m.x, t.z - m.z); if (Math.abs(wrap(want - c.heading)) < 0.5) dir = want; }
      if (!c.isPlayer) dir += R(-1, 1) * (1 - this.diff.accuracy) * 0.2;
    }
    const big = opts.kind === 'nuke' || opts.kind === 'shell';
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.CylinderGeometry(big ? 0.4 : 0.16, big ? 0.4 : 0.16, big ? 2.2 : 1.1, 8), new THREE.MeshStandardMaterial({ color: opts.kind === 'shell' ? 0x2a0c0a : big ? 0x3d4a2a : opts.kind === 'napalm' ? 0x8a3a12 : 0xd9d2c4, metalness: 0.5 }));
    body.rotation.x = Math.PI / 2;
    const tip = new THREE.Mesh(new THREE.ConeGeometry(big ? 0.4 : 0.16, big ? 0.8 : 0.4, 8), new THREE.MeshStandardMaterial({ color: opts.kind === 'shell' ? 0xff2a1a : big ? 0xffd23a : 0xff3d1f, emissive: opts.kind === 'shell' ? 0xff1000 : big ? 0xffa000 : 0xff2000, emissiveIntensity: 1.5 }));
    tip.rotation.x = Math.PI / 2; tip.position.z = big ? 1.5 : 0.7;
    g.add(body, tip); g.position.copy(m); g.rotation.y = dir;
    this.scene.add(g);
    this.rockets.push({
      mesh: g, x: m.x, y: Math.max(1.2, m.y), z: m.z, dir, speed: opts.speed || (big ? 34 : 52), life: big ? 3.5 : 2.4, owner: c, kind: opts.kind || 'rocket',
      dmg: opts.dmg || c.stats.rocketDmg * c.dmgMul * (opts.dmgMul || 1), radius: opts.radius || c.stats.rocketRadius, homing: opts.homing || null,
    });
    sfx.rocket(this.vol(c) * (c.isPlayer ? 1 : 0.6), big, this.pan(c));
  }

  firePower(c) {
    if (c.rocketCd > 0) return;
    const p = c.power; c.rocketCd = p.type === 'railgun' ? 0.7 : 0.6;
    if (p.type === 'railgun') this.railgun(c);
    else if (p.type === 'napalm') this.fireRocket(c, { free: true, kind: 'napalm', dmgMul: 0.8 });
    else this.fireRocket(c, { free: true, kind: 'nuke', dmg: 170 * (c.isPlayer ? 1 : c.dmgMul), radius: 18 });
    if (--p.ammo <= 0) { c.power = null; if (c.isPlayer) this.hud.toast(tr('{p} EMPTY', { p: tr(POWERS[p.type].name).toUpperCase() })); }
  }

  railgun(c) {
    const m = this.worldPoint(c, c.mesh.userData.rocketMuzzle);
    const t = c.isPlayer ? this.aimAt(c, 95, 0.35) : c.ai.target;
    let dir = c.heading;
    if (t && t.alive) { const want = Math.atan2(t.x - m.x, t.z - m.z); if (Math.abs(wrap(want - c.heading)) < 0.5) dir = want; }
    const dx = Math.sin(dir), dz = Math.cos(dir);
    let end = 95, hit = null;
    for (let s = 2; s < 95; s += 0.8) { // march the beam
      const x = m.x + dx * s, z = m.z + dz * s;
      if (Math.abs(x) > this.arena.half || Math.abs(z) > this.arena.half) { end = s; break; }
      const o = this.hitObstacle(x, 1.5, z); if (o) { end = s; if (o.barrel) this.damageObstacle(o, 99, c); break; }
      const car = this.cars.find((q) => q !== c && q.alive && Math.hypot(q.x - x, q.z - z) < HR(q));
      if (car) { hit = car; end = s; break; }
    }
    const ex = m.x + dx * end, ez = m.z + dz * end;
    this.fx.laser(m.x, m.y, m.z, ex, 1.5, ez);
    this.fx.light(ex, 2, ez, 120, 0x60b0ff);
    this.fx.spark(ex, 1.5, ez, 16);
    if (hit) { this.damage(hit, 68 * (c.isPlayer ? 1 : c.dmgMul), c, false, 'railgun'); hit.kx += dx * 18; hit.kz += dz * 18; }
    sfx.railgun(this.vol(c));
    if (c.isPlayer) this.shake = Math.max(this.shake, 0.3);
  }

  useSpecial(c) {
    if (c.specialCd > 0 || c.specialOn) { if (c.isPlayer) sfx.denied(); return false; }
    const spec = c.data.special, sp = spec.id, pw = c.stats.specialPower;
    if (c.skidT > 0) { if (c.isPlayer) sfx.denied(); return false; } // can't act while spinning out
    c.specialCd = c.stats.specialCooldown;
    const fx = Math.sin(c.heading), fz = Math.cos(c.heading), dur = spec.duration || 1, rad = spec.radius || 10;
    const near = (r, cone = Math.PI) => this.cars.filter((o) => { if (o === c || !o.alive) return false; const dx = o.x - c.x, dz = o.z - c.z, d = Math.hypot(dx, dz); return d < r + HR(o) && Math.abs(wrap(Math.atan2(dx, dz) - c.heading)) <= cone; });
    sfx.ability(c.data.sound && c.data.sound.ability, this.vol(c), c.data.sound && c.data.sound.files && c.data.sound.files.ability);
    switch (sp) {
      case 'smoke': // Ghost: smoke cover, enemies lose track, short speed burst
        c.specialOn = 'smoke'; c.specialT = dur; c.hideT = dur * Math.min(1.4, pw);
        c.speed = Math.max(c.speed, c.stats.maxSpeed * 1.25);
        for (let i = 0; i < 14; i++) this.fx.smokeScreen(c.x - fx * 3, c.z - fz * 3, rad);
        for (const o of this.cars) if (o.ai && o.ai.target === c) { o.ai.target = null; o.ai.retarget = c.hideT; }
        break;
      case 'dash': // Venom: double speed, half damage taken
        c.specialOn = 'dash'; c.specialT = dur * Math.min(1.4, pw); c.speed = Math.max(c.speed, c.stats.maxSpeed * 1.6);
        break;
      case 'toxic': { // Toxic Viper: a poison cloud lobbed ahead of the car
        const zx = clamp(c.x + fx * 9, -this.arena.half + 2, this.arena.half - 2), zz = clamp(c.z + fz * 9, -this.arena.half + 2, this.arena.half - 2);
        this.zones.push({ x: zx, z: zz, r: rad, t: dur, dps: 14 * pw * c.dmgMul, owner: c, safe: c, kind: 'toxic' });
        for (let i = 0; i < 30; i++) this.fx.toxic(zx + R(-rad, rad) * 0.7, zz + R(-rad, rad) * 0.7);
        this.fx.ring(zx, zz, rad, 0x7cff3a);
        break;
      }
      case 'riptide': { // Megalodon: surge plus a wave that shoves and spins out cars in front
        c.speed = Math.max(c.speed, c.stats.maxSpeed * 1.4);
        this.fx.ring(c.x + fx * 6, c.z + fz * 6, rad * 0.8, 0x5fb8ff); this.fx.wave(c.x, c.z, c.heading, rad);
        for (const o of near(rad, 0.75)) {
          const dx = o.x - c.x, dz = o.z - c.z, d = Math.max(0.5, Math.hypot(dx, dz)), k = 1 - Math.min(1, d / (rad + 2)) * 0.6;
          this.damage(o, 18 * pw * c.dmgMul * k, c, false, 'special');
          o.kx += (dx / d) * 30 * k; o.kz += (dz / d) * 30 * k;
          o.skidT = dur; o.skidSpin = (Math.random() < 0.5 ? -1 : 1) * R(3, 4.5); o.speed *= 0.5;
          if (o.isPlayer) this.hud.toast(tr('SKIDDING'));
        }
        if (c.isPlayer) this.shake = Math.max(this.shake, 0.4);
        break;
      }
      case 'pulse': // Blue Siren: electric pulse, slows and jams guns
        this.fx.ring(c.x, c.z, rad, 0x58a8ff); this.fx.light(c.x, 3, c.z, 180, 0x58a8ff);
        for (const o of near(rad)) {
          o.slowT = dur * Math.min(1.4, pw); o.jamT = dur * Math.min(1.4, pw);
          this.damage(o, 8 * pw * c.dmgMul, c, false, 'special');
          this.fx.laser(c.x, 2.6, c.z, o.x, 1.6, o.z);
          if (o.isPlayer) this.hud.toast(tr('JAMMED'));
        }
        break;
      case 'whip': // Rex: tail spin, damage and knockback all around
        c.spinT = 0.55;
        this.fx.ring(c.x, c.z, rad, 0xff6a3a); this.fx.light(c.x, 2, c.z, 140);
        for (const o of near(rad)) {
          const dx = o.x - c.x, dz = o.z - c.z, d = Math.max(0.5, Math.hypot(dx, dz)), k = 1 - Math.min(1, d / (rad + 2)) * 0.5;
          this.damage(o, 30 * pw * c.dmgMul * k, c, false, 'special');
          o.kx += (dx / d) * 34 * k; o.kz += (dz / d) * 34 * k; o.speed *= 0.4;
          this.fx.spark(o.x, 1.4, o.z, 10);
        }
        if (c.isPlayer) this.shake = Math.max(this.shake, 0.5);
        break;
      case 'shell': { // Blood Titan: slow heavy shell, its path drawn in red so it can be dodged
        let dir = c.heading;
        const t = c.isPlayer ? this.aimAt(c, 80, 0.3) : c.ai.target;
        if (t && t.alive) { const want = Math.atan2(t.x - c.x, t.z - c.z); if (Math.abs(wrap(want - c.heading)) < 0.35) dir = want; }
        this.fireRocket(c, { free: true, kind: 'shell', offset: wrap(dir - c.heading), speed: 30, dmg: 85 * pw * (c.isPlayer ? 1 : c.dmgMul), radius: rad });
        this.fx.aimLine(c.x, c.z, dir, 70, 1.6); this.fx.light(c.x + fx * 3, 2.5, c.z + fz * 3, 160);
        c.kx -= fx * 8; c.kz -= fz * 8; // recoil
        if (c.isPlayer) this.shake = Math.max(this.shake, 0.45);
        break;
      }
      case 'nitro': c.specialOn = 'nitro'; c.specialT = 3 * Math.min(1.5, pw); sfx.special(); break;
      case 'ram': c.specialOn = 'ram'; c.specialT = spec.duration || 1.3; c.rammed.clear(); c.speed = Math.max(c.speed, c.stats.maxSpeed); break;
      case 'shield': c.specialOn = 'shield'; c.specialT = dur * Math.min(1.4, pw); if (c.bubble) c.bubble.visible = true; break;
      case 'flame': c.specialOn = 'flame'; c.specialT = 3; break;
      case 'shockwave': {
        this.fx.ring(c.x, c.z, 13, 0xffc070); this.fx.light(c.x, 2, c.z, 160); sfx.explosion(0.8, this.vol(c), this.pan(c));
        for (const o of this.cars) {
          if (o === c || !o.alive) continue;
          const dx = o.x - c.x, dz = o.z - c.z, d = Math.hypot(dx, dz);
          if (d > 14) continue;
          const k = 1 - d / 14;
          this.damage(o, 34 * pw * c.dmgMul * (0.4 + 0.6 * k), c, false, 'special');
          o.kx += (dx / d) * 34 * k; o.kz += (dz / d) * 34 * k; o.speed *= 0.3;
        }
        if (c.isPlayer) this.shake = 0.6;
        break;
      }
      case 'homing': {
        const targets = this.cars.filter((o) => o !== c && o.alive).sort((a, b) => Math.hypot(a.x - c.x, a.z - c.z) - Math.hypot(b.x - c.x, b.z - c.z));
        for (let i = 0; i < 3; i++) this.fireRocket(c, { free: true, offset: (i - 1) * 0.35, homing: targets[i % Math.max(1, targets.length)] || null, dmgMul: 0.9 * pw, speed: 40 });
        break;
      }
      case 'barrage':
        for (let i = 0; i < 8; i++) setTimeout(() => { if (c.alive && this.running) this.fireRocket(c, { free: true, offset: (i - 3.5) * 0.11, dmgMul: 0.75 * pw }); }, i * 70);
        break;
      case 'mines':
        for (let i = 0; i < 3; i++) {
          const mx = c.x - fx * (3.2 + i * 2.4) + (i - 1) * 1.6 * fz, mz = c.z - fz * (3.2 + i * 2.4) - (i - 1) * 1.6 * fx;
          const g = new THREE.Group();
          const disc = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 0.8, 0.3, 10), new THREE.MeshStandardMaterial({ color: 0x3a3a32, metalness: 0.6 }));
          const led = new THREE.Mesh(new THREE.SphereGeometry(0.16, 6, 5), new THREE.MeshBasicMaterial({ color: 0xff2020 }));
          led.position.y = 0.22; g.add(disc, led); g.position.set(mx, 0.15, mz); this.scene.add(g);
          this.mines.push({ mesh: g, led, x: mx, z: mz, owner: c, arm: 0.9, life: 25, dmg: 52 * pw * c.dmgMul });
        }
        sfx.click();
        break;
    }
    if (c.isPlayer) this.hud.flashSpecial();
    return true;
  }

  flameTick(c, dt) {
    const fx = Math.sin(c.heading), fz = Math.cos(c.heading);
    const n = this.worldPoint(c, c.mesh.userData.flame);
    this.fx.flame(n.x, n.y, n.z, fx, fz);
    if (Math.random() < dt * 8) sfx.flame();
    if (Math.random() < dt * 6) this.fx.light(n.x + fx * 4, 2, n.z + fz * 4, 40);
    for (const o of this.cars) {
      if (o === c || !o.alive) continue;
      const dx = o.x - c.x, dz = o.z - c.z, d = Math.hypot(dx, dz);
      if (d > 13) continue;
      if (Math.abs(wrap(Math.atan2(dx, dz) - c.heading)) > 0.42) continue;
      this.damage(o, 32 * c.stats.specialPower * c.dmgMul * dt, c, true, 'special');
      if (Math.random() < 0.3) this.fx.flames(o.x, 1.5, o.z);
    }
    for (const o of this.arena.obstacles) if (o.barrel && !o.dead && Math.hypot(o.x - c.x, o.z - c.z) < 11 && Math.abs(wrap(Math.atan2(o.x - c.x, o.z - c.z) - c.heading)) < 0.42) this.damageObstacle(o, 20 * dt, c);
  }

  // ---------- projectiles ----------
  hitObstacle(x, y, z) {
    for (const o of this.arena.obstacles) {
      if (o.dead || y > o.h + 0.3) continue;
      if (insideObstacle(o, x, z)) return o;
    }
    return null;
  }

  updateBullets(dt) {
    const SPEED = 120, steps = 3;
    this.bullets = this.bullets.filter((b) => {
      b.life -= dt;
      let hit = false;
      for (let s = 0; s < steps && !hit; s++) {
        b.x += b.dx * SPEED * dt / steps; b.z += b.dz * SPEED * dt / steps;
        for (const c of this.cars) {
          if (c === b.owner || !c.alive) continue;
          if (Math.hypot(c.x - b.x, c.z - b.z) < HR(c)) { this.damage(c, b.dmg, b.owner, false, 'gun'); this.fx.spark(b.x, b.y, b.z); if (b.owner.isPlayer) sfx.hit(); hit = true; break; }
        }
        if (!hit) { const o = this.hitObstacle(b.x, b.y, b.z); if (o) { this.fx.spark(b.x, b.y, b.z, 4); if (o.barrel) this.damageObstacle(o, b.dmg, b.owner); hit = true; } }
        if (Math.abs(b.x) > this.arena.half || Math.abs(b.z) > this.arena.half) hit = true;
      }
      if (!hit && b.life <= 0) this.fx.impact(b.x, b.z);
      if (hit || b.life <= 0) { this.scene.remove(b.mesh); this.bulletPool.push(b.mesh); return false; }
      b.mesh.position.set(b.x, b.y, b.z);
      return true;
    });
  }

  updateRockets(dt) {
    this.rockets = this.rockets.filter((r) => {
      r.life -= dt;
      if (r.homing && r.homing.alive && !(r.homing.hideT > 0) && r.life < 2.2) {
        const want = Math.atan2(r.homing.x - r.x, r.homing.z - r.z);
        r.dir += clamp(wrap(want - r.dir), -3 * dt, 3 * dt);
      }
      const step = r.speed * dt;
      r.x += Math.sin(r.dir) * step; r.z += Math.cos(r.dir) * step;
      r.y = Math.max(1.0, r.y - dt * 0.4);
      r.mesh.position.set(r.x, r.y, r.z); r.mesh.rotation.y = r.dir;
      this.fx.trail(r.x - Math.sin(r.dir) * 0.7, r.y, r.z - Math.cos(r.dir) * 0.7);
      if (r.kind === 'nuke' || r.kind === 'shell') this.fx.trail(r.x - Math.sin(r.dir) * 1.2, r.y + 0.2, r.z - Math.cos(r.dir) * 1.2);
      if (!r.warned) this.warnIncoming(r);
      let boom = r.life <= 0 || Math.abs(r.x) > this.arena.half - 0.8 || Math.abs(r.z) > this.arena.half - 0.8;
      if (!boom) for (const c of this.cars) if (c !== r.owner && c.alive && Math.hypot(c.x - r.x, c.z - r.z) < HR(c) + 0.4) { boom = true; break; }
      if (!boom && this.hitObstacle(r.x, r.y, r.z)) boom = true;
      if (boom) {
        this.scene.remove(r.mesh);
        if (r.kind === 'nuke') this.nukeBlast(r.x, r.z, r.radius, r.dmg, r.owner);
        else {
          this.explode(r.x, r.z, r.radius, r.dmg, r.owner, r.kind === 'shell' ? 1.5 : 0.8, r.homing || r.kind === 'shell' ? 'special' : 'rocket');
          if (r.kind === 'napalm') this.zones.push({ x: r.x, z: r.z, r: 7, t: 6, dps: 20 * r.owner.dmgMul, owner: r.owner });
        }
        return false;
      }
      return true;
    });
  }

  nukeBlast(x, z, radius, dmg, owner) {
    this.fx.explosion(x, z, 2.6, { debris: 10 });
    setTimeout(() => this.running && this.fx.explosion(x + R(-4, 4), z + R(-4, 4), 1.4), 150);
    setTimeout(() => this.running && this.fx.explosion(x + R(-5, 5), z + R(-5, 5), 1.2), 320);
    this.fx.ring(x, z, radius * 1.3, 0xffe0a0);
    this.fx.light(x, 8, z, 900, 0xfff0c0);
    sfx.nuke(this.volAt(x, z));
    this.hud.whiteout();
    this.shake = 1.2;
    this.explode(x, z, radius, dmg, owner, 0, 'rocket');
    this.zones.push({ x, z, r: 10, t: 5, dps: 15, owner });
  }

  updateMines(dt) {
    this.mines = this.mines.filter((m) => {
      m.arm -= dt; m.life -= dt;
      m.led.visible = Math.sin(this.time * (m.arm > 0 ? 6 : 14)) > 0;
      let trig = m.life <= 0;
      if (m.arm <= 0) for (const c of this.cars) if (c.alive && c !== m.owner && Math.hypot(c.x - m.x, c.z - m.z) < 3.6) { trig = true; break; }
      if (trig) { this.scene.remove(m.mesh); this.explode(m.x, m.z, 7.5, m.dmg, m.owner, 1, 'special'); return false; }
      return true;
    });
  }

  explode(x, z, radius, dmg, owner, size = 1, cause = 'rocket') {
    if (size > 0) {
      this.fx.explosion(x, z, size);
      sfx.explosion(size, this.volAt(x, z), this.panAt(x, z));
      const pd = Math.hypot(this.player.x - x, this.player.z - z);
      this.shake = Math.max(this.shake, clamp(1 - pd / 45, 0, 1) * 0.7 * size);
    }
    for (const c of this.cars) {
      if (!c.alive) continue;
      const d = Math.hypot(c.x - x, c.z - z);
      if (d > radius + HR(c)) continue;
      const k = clamp(1 - Math.max(0, d - HR(c)) / radius, 0.3, 1);
      this.damage(c, dmg * k * (c === owner ? 0.25 : 1), owner, false, cause);
      const nx = (c.x - x) / Math.max(d, 0.5), nz = (c.z - z) / Math.max(d, 0.5);
      c.kx += nx * 14 * k; c.kz += nz * 14 * k;
    }
    for (const o of this.arena.obstacles) if (o.barrel && !o.dead && Math.hypot(o.x - x, o.z - z) < radius + 1) setTimeout(() => this.damageObstacle(o, 99, owner), 90 + Math.random() * 120);
  }

  damageObstacle(o, dmg, by) {
    if (o.dead || !this.running) return;
    o.hp -= dmg;
    if (o.hp > 0) return;
    o.dead = true;
    if (o.hide) o.hide(); else if (o.mesh) o.mesh.visible = false;
    if (by && by.isPlayer) this.stats.barrels++;
    this.explode(o.x, o.z, 9, 55, by, 1.25, 'barrel');
    this.zones.push({ x: o.x, z: o.z, r: 3.5, t: 4, dps: 12, owner: by });
  }

  updateZones(dt) {
    this.zones = this.zones.filter((zn) => {
      zn.t -= dt;
      const n = Math.ceil(zn.r * 0.6);
      if (zn.kind === 'toxic') { for (let i = 0; i < n; i++) if (Math.random() < 0.45) { const a = Math.random() * TAU, d = Math.sqrt(Math.random()) * zn.r; this.fx.toxic(zn.x + Math.cos(a) * d, zn.z + Math.sin(a) * d); } }
      else {
      for (let i = 0; i < n; i++) if (Math.random() < 0.14) { const a = Math.random() * TAU, d = Math.sqrt(Math.random()) * zn.r; this.fx.flames(zn.x + Math.cos(a) * d, 0.3, zn.z + Math.sin(a) * d, 1.3); }
      if (Math.random() < 0.3) this.fx.burn(zn.x + R(-zn.r, zn.r) * 0.5, 1, zn.z + R(-zn.r, zn.r) * 0.5);
      }
      for (const c of this.cars) if (c.alive && c !== zn.safe && Math.hypot(c.x - zn.x, c.z - zn.z) < zn.r + HR(c) * 0.5) { this.damage(c, zn.dps * dt, zn.owner, true, zn.kind === 'toxic' ? 'special' : 'fire'); if (zn.kind === 'toxic' && c.isPlayer && !this.poisonMsg) { this.poisonMsg = true; this.hud.toast(tr('POISONED')); setTimeout(() => (this.poisonMsg = false), 2500); } }
      return zn.t > 0;
    });
  }

  // ---------- airdrops ----------
  updateDrops(dt) {
    this.dropT -= dt;
    if (this.dropT <= 0 && this.drops.length < 2) { this.dropT = R(30, 42); this.spawnDrop(); }
    this.drops = this.drops.filter((d) => {
      if (!d.landed) {
        d.y -= dt * 7; d.mesh.position.y = d.y; d.mesh.rotation.y += dt * 0.6;
        d.chute.scale.setScalar(1 + Math.sin(this.time * 5) * 0.03);
        if (d.y <= d.ground) { d.landed = true; d.y = d.mesh.position.y = d.ground; d.mesh.remove(d.chute); this.fx.dust(d.x, d.z, 3); this.fx.dust(d.x + 1, d.z - 1, 3); sfx.crunch(); }
      }
      if (Math.random() < 0.6) this.fx.beacon(d.x, d.z);
      if (d.landed) {
        d.mesh.rotation.y += dt;
        for (const c of this.cars) {
          if (!c.alive || Math.hypot(c.x - d.x, c.z - d.z) > 3.2) continue;
          const type = d.type;
          c.power = { type, ammo: POWERS[type].ammo };
          if (c.isPlayer) { this.stats.airdrops++; sfx.powerup(); this.hud.announce(tr(POWERS[type].name).toUpperCase(), tr('{p} · rocket button', { p: tr(POWERS[type].desc) }), 'blue'); }
          else if (Math.hypot(c.x - this.player.x, c.z - this.player.z) < 70) this.hud.feedText(tr('{car} grabbed the {p}', { car: c.data.name, p: tr(POWERS[type].name) }));
          this.scene.remove(d.mesh);
          return false;
        }
      }
      return true;
    });
  }
  simpleCrate() {
    const g = new THREE.Group(); g.userData.h = 1.4;
    const crate = new THREE.Mesh(new THREE.BoxGeometry(1.8, 1.4, 1.8), new THREE.MeshStandardMaterial({ color: 0x3f5a8a, emissive: 0x15305a, emissiveIntensity: 0.9, metalness: 0.5, roughness: 0.5 }));
    const band = new THREE.Mesh(new THREE.BoxGeometry(1.84, 0.25, 1.84), new THREE.MeshStandardMaterial({ color: 0xf0b429, emissive: 0x8a5a00, emissiveIntensity: 0.6 }));
    crate.castShadow = true; g.add(crate, band); return g;
  }
  simpleChute() {
    const g = new THREE.Group();
    const canopy = new THREE.Mesh(new THREE.SphereGeometry(3.4, 12, 6, 0, TAU, 0, Math.PI / 2.4), new THREE.MeshStandardMaterial({ color: 0xd9cdb4, side: THREE.DoubleSide, roughness: 0.9 }));
    canopy.position.y = 4.3; canopy.castShadow = true; g.add(canopy);
    for (let i = 0; i < 4; i++) { const a = (i / 4) * TAU + 0.78; const l = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 5.4, 3), new THREE.MeshBasicMaterial({ color: 0x222222 })); l.position.set(Math.cos(a) * 1.4, 2.4, Math.sin(a) * 1.4); l.rotation.z = Math.cos(a) * 0.35; l.rotation.x = -Math.sin(a) * 0.35; g.add(l); }
    return g;
  }
  spawnDrop() {
    const s = this.nudgeClear({ x: R(-0.6, 0.6) * this.arena.half, z: R(-0.6, 0.6) * this.arena.half }, 4);
    const g = new THREE.Group(); g.position.set(s.x, 40, s.z);
    const crate = propModel('dropcrate', 2.5) || this.simpleCrate();
    const chute = propModel('parachute', 6.5, { stand: true }) || this.simpleChute();
    chute.position.y = crate.userData.h / 2 + 0.25; // the rigging lines meet on the crate lid
    g.add(crate, chute);
    this.scene.add(g);
    const type = pick(Object.keys(POWERS));
    this.drops.push({ x: s.x, z: s.z, y: 40, ground: crate.userData.h / 2 + 0.05, mesh: g, chute, landed: false, type });
    this.hud.announce(tr('AIRDROP INCOMING'), tr('Follow the blue smoke'), 'blue');
    sfx.alarm();
  }

  // ---------- map events ----------
  updateEvents(dt) {
    if (this.storm > 0) {
      this.storm -= dt;
      const k = this.storm > 12 ? (14 - this.storm) / 2 : this.storm < 2 ? this.storm / 2 : 1;
      this.scene.fog.near = THREE.MathUtils.lerp(this.baseFog.near, 6, k); this.scene.fog.far = THREE.MathUtils.lerp(this.baseFog.far, 48, k);
      for (let i = 0; i < 3; i++) this.fx.sand(this.player.x + R(-25, 25), this.player.z + R(-25, 25));
      if (this.storm <= 0) { this.scene.fog.near = this.baseFog.near; this.scene.fog.far = this.baseFog.far; }
    }
    this.eventT -= dt;
    if (this.eventT > 0) return;
    this.eventT = R(28, 38);
    const ev = MAP_EVENT[this.map.id];
    if (ev === 'artillery') {
      this.hud.announce(tr('ARTILLERY STRIKE'), tr('Get out of the red circles'), 'red'); sfx.alarm();
      const alive = this.cars.filter((c) => c.alive);
      for (let i = 0; i < 7; i++) {
        const c = i < 4 ? pick(alive) : null;
        const x = c ? c.x + R(-6, 6) : R(-0.8, 0.8) * this.arena.half, z = c ? c.z + R(-6, 6) : R(-0.8, 0.8) * this.arena.half;
        this.addStrike(x, z, 6.5, 2.2 + i * 0.25, 48);
      }
    } else if (ev === 'rupture') {
      const tanks = this.arena.obstacles.filter((o) => o.kind === 'circle' && o.r >= 4 && !o.ruptured);
      if (!tanks.length) return;
      const t = tanks.reduce((a, b) => (Math.hypot(a.x - this.player.x, a.z - this.player.z) < Math.hypot(b.x - this.player.x, b.z - this.player.z) ? a : b));
      t.ruptured = true;
      this.hud.announce(tr('TANK RUPTURE'), tr('A fuel tank is about to blow'), 'red'); sfx.alarm();
      this.addStrike(t.x, t.z, t.r + 9, 2.6, 75, () => {
        this.zones.push({ x: t.x, z: t.z, r: t.r + 4, t: 9, dps: 16, owner: null });
        t.mesh.material = t.mesh.material.clone(); t.mesh.material.color.multiplyScalar(0.25);
        this.fx.explosion(t.x + t.r, t.z, 1.4); this.fx.explosion(t.x - t.r, t.z + 1, 1.2);
      }, 2.2);
    } else {
      this.storm = 14;
      this.hud.announce(tr('SANDSTORM'), tr('Visibility dropping'), 'gold'); sfx.wind();
    }
  }
  addStrike(x, z, r, delay, dmg, after = null, size = 1) {
    const ring = new THREE.Mesh(new THREE.RingGeometry(r * 0.92, r, 40), new THREE.MeshBasicMaterial({ color: 0xff2a1a, transparent: true, opacity: 0.7, depthWrite: false, side: THREE.DoubleSide }));
    const fill = new THREE.Mesh(new THREE.CircleGeometry(r, 40), new THREE.MeshBasicMaterial({ color: 0xff2a1a, transparent: true, opacity: 0.12, depthWrite: false }));
    ring.rotation.x = fill.rotation.x = -Math.PI / 2; ring.position.set(x, 0.06, z); fill.position.set(x, 0.05, z);
    this.scene.add(ring, fill);
    this.strikes.push({ x, z, r, t: delay, total: delay, dmg, ring, fill, after, size, whistled: false });
  }
  updateStrikes(dt) {
    this.strikes = this.strikes.filter((s) => {
      s.t -= dt;
      const k = 1 - s.t / s.total;
      s.ring.material.opacity = 0.4 + 0.5 * Math.abs(Math.sin(this.time * (6 + k * 14)));
      s.fill.scale.setScalar(Math.max(0.01, k));
      if (!s.whistled && s.t <= Math.min(s.total, 2.5)) { s.whistled = true; sfx.incoming(s.t, this.volAt(s.x, s.z), this.panAt(s.x, s.z)); }
      if (s.t > 0) return true;
      this.scene.remove(s.ring, s.fill);
      this.explode(s.x, s.z, s.r, s.dmg, null, s.size * 1.1, 'event');
      if (s.after) s.after();
      return false;
    });
  }

  // ---------- damage / death ----------
  damage(c, amt, by, quiet = false, cause = 'gun') {
    if (!c.alive || amt <= 0 || this.state === 'countdown' || c.invuln > 0) return;
    if (c.specialOn === 'shield') { amt *= 0.3; if (!quiet && Math.random() < 0.3) this.fx.spark(c.x, 1.5, c.z); } // Bulwark: 70% less damage
    if (c.specialOn === 'dash') amt *= 0.5;
    c.hp -= amt; c.lastHit = this.time;
    if (by && by !== c) { c.lastAttacker = by; c.lastCause = cause; }
    if (c.isPlayer) { this.hud.hurt(amt); if (!quiet) sfx.hurt(); }
    if (c.ai && by && by !== c && Math.random() < 0.5) c.ai.target = by;
    if (c.hp <= 0) this.kill(c);
  }

  kill(c) {
    c.alive = false; c.hp = 0; c.deathT = 0; c.mesh.visible = true;
    c.lives = Math.max(0, c.lives - 1);
    if (c.lives > 0) c.respawnT = 3.2;
    c.specialOn = null; if (c.bubble) c.bubble.visible = false;
    // the wreck is thrown into the air and tumbles
    c.vy = R(10, 15); c.srx = R(-5, 5); c.srz = R(-7, 7); c.y = 0.01;
    c.kx += R(-6, 6); c.kz += R(-6, 6);
    this.fx.explosion(c.x, c.z, 1.7, { debris: 9 });
    setTimeout(() => this.running && this.fx.explosion(c.x + R(-1, 1), c.z + R(-1, 1), 1.0, { debris: 3 }), 220);
    setTimeout(() => this.running && this.fx.explosion(c.x + R(-1, 1), c.z + R(-1, 1), 0.7, { debris: 2 }), 520);
    sfx.explosion(1.6, this.volAt(c.x, c.z), this.panAt(c.x, c.z));
    wreck(c.mesh);
    const killer = c.lastAttacker && c.lastAttacker !== c ? c.lastAttacker : null;
    if (killer) killer.kills++;
    this.hud.feed(killer, c);
    if (c.isPlayer) this.shake = 1; else if (Math.hypot(c.x - this.player.x, c.z - this.player.z) < 40) this.shake = Math.max(this.shake, 0.6);
    // scoring hooks for the player
    if (killer && killer.isPlayer) {
      this.stats.kills++;
      if (c.lastCause === 'rocket') this.stats.rocketKills++;
      if (!this.stats.firstBlood) { this.stats.firstBlood = true; this.stats.bonus.push({ label: 'First blood', pts: 25 }); }
      this.streak = this.time - this.lastKillT < 7 ? this.streak + 1 : 1;
      this.lastKillT = this.time;
      this.stats.streakMax = Math.max(this.stats.streakMax, this.streak);
      const st = STREAKS[Math.min(5, this.streak)];
      if (this.streak >= 2 && st) { this.stats.bonus.push({ label: st[0].toLowerCase().replace(/^./, (m) => m.toUpperCase()), pts: st[1] }); this.hud.announce(tr(st[0]), tr('+{n} streak bonus', { n: st[1] }), 'gold'); sfx.streak(this.streak); }
      else if (!c.bounty) this.hud.announce(tr('WRECKED'), c.data.name, 'kill');
    } else if (!killer && !c.isPlayer && this.stats.firstBlood === false) { /* environment kill, no first blood */ }
    if (c.bounty) {
      if (killer && killer.isPlayer) {
        const pts = Math.round(100 * (this.diff.reward || 1));
        this.stats.bounty++; this.stats.bonus.push({ label: 'Crown claimed', pts });
        this.hud.announce(this.t('CROWN CLAIMED'), `+${pts}`, 'gold'); sfx.streak(3);
      }
      if (this.mode === 'survival') this.setBounty(null, false);
      else if (c.lives === 0) this.setBounty(null, false);
    }
    if (c.isPlayer && c.lives > 0) this.hud.announce(this.t('WRECKED'), this.t(c.lives === 1 ? 'Last life · back in 3s' : '{n} lives left · back in 3s', { n: c.lives }), 'red');
    this.updateLeader();
  }

  updateWreck(c, dt) {
    c.deathT += dt;
    if (c.deathT < 8 && Math.random() < 0.55) this.fx.burn(c.x, c.y + 1.4, c.z);
    if (c.deathT < 5 && Math.random() < 0.22) this.fx.flames(c.x + R(-1, 1), c.y + 1, c.z + R(-1, 1), 1.3);
    // airborne tumble
    if (c.y > 0 || c.vy > 0) {
      c.vy -= 30 * dt; c.y += c.vy * dt;
      c.rx += c.srx * dt; c.rz += c.srz * dt;
      if (c.y <= 0) {
        c.y = 0;
        if (c.vy < -4) { c.vy *= -0.3; c.srx *= 0.4; c.srz *= 0.4; this.fx.dust(c.x, c.z, 3); this.fx.spark(c.x, 0.5, c.z, 10); if (Math.hypot(c.x - this.player.x, c.z - this.player.z) < 50) sfx.crunch(); }
        else { c.vy = 0; c.srx = c.srz = 0; }
      }
    } else { // settle flat: right side up or on its roof
      const snap = (a) => Math.round(a / Math.PI) * Math.PI;
      c.rx += (snap(c.rx) - c.rx) * Math.min(1, dt * 6); c.rz += (snap(c.rz) - c.rz) * Math.min(1, dt * 6);
    }
    c.speed *= Math.exp(-3 * dt);
    c.x += (Math.sin(c.heading) * c.speed + c.kx) * dt; c.z += (Math.cos(c.heading) * c.speed + c.kz) * dt;
    c.kx *= Math.exp(-2.5 * dt); c.kz *= Math.exp(-2.5 * dt);
    this.collideWorld(c);
    const lift = (1 - Math.cos(c.rx) * Math.cos(c.rz)) * 0.8; // keeps a car on its roof above the ground
    c.mesh.position.set(c.x, c.y + lift, c.z);
    c.mesh.rotation.set(c.rx, c.heading, c.rz, 'YXZ');
  }

  updatePickups(dt) {
    for (const p of this.pickups) {
      if (p.respawn > 0) { p.respawn -= dt; p.mesh.visible = p.respawn <= 0; continue; }
      p.mesh.rotation.y += dt * 1.6; p.mesh.position.y = 1.4 + Math.sin(this.time * 3 + p.x) * 0.25;
      for (const c of this.cars) {
        if (!c.alive || Math.hypot(c.x - p.x, c.z - p.z) > 3) continue;
        if (p.type === 'health') { if (c.hp >= c.maxHp) continue; c.hp = Math.min(c.maxHp, c.hp + c.maxHp * 0.4); this.fx.heal(c.x, c.z); }
        else { if (c.rockets >= 12) continue; c.rockets = Math.min(12, c.rockets + 4); }
        if (c.isPlayer) { sfx.pickup(); this.hud.toast(tr(p.type === 'health' ? '+ ARMOR REPAIRED' : '+4 ROCKETS')); }
        p.respawn = 16; p.mesh.visible = false; break;
      }
    }
  }

  // ---------- AI ----------
  think(c, dt) {
    const ai = c.ai, diff = this.diff;
    ai.retarget -= dt;
    if (ai.target && ai.target.hideT > 0) ai.target = null; // lost in the smoke
    if (!ai.target || !ai.target.alive || ai.retarget <= 0) {
      ai.retarget = R(2, 4);
      let best = null, bs = Infinity;
      for (const o of this.cars) {
        if (o === c || !o.alive || o.hideT > 0) continue;
        if (this.mode === 'survival' && !c.isPlayer && !o.isPlayer && Math.random() < 0.85) continue;
        const s = Math.hypot(o.x - c.x, o.z - c.z) * (o.isPlayer ? diff.focus : 1) * (o.hp / o.maxHp < 0.3 ? 0.7 : 1) * (o.bounty ? 0.75 : 1);
        if (s < bs) { bs = s; best = o; }
      }
      ai.target = best || (c.isPlayer ? null : this.player.alive && !(this.player.hideT > 0) ? this.player : null);
    }
    const t = ai.target;
    if (!t) { c.throttle = 0.3; c.steer = 0; c.firing = false; return; }
    const dx = t.x - c.x, dz = t.z - c.z, dist = Math.hypot(dx, dz);
    const toT = Math.atan2(dx, dz);
    let want = toT;
    if (dist < 14) want = toT + ai.strafe * 1.1;
    // detours: repairs when hurt, airdrops when close, away from strike circles
    const drop = this.drops.find((d) => d.landed && Math.hypot(d.x - c.x, d.z - c.z) < 40);
    if (drop && !c.power && dist > 12) want = Math.atan2(drop.x - c.x, drop.z - c.z);
    else if (c.hp < c.maxHp * 0.3) {
      const hp = this.pickups.filter((p) => p.type === 'health' && p.respawn <= 0).sort((a, b) => Math.hypot(a.x - c.x, a.z - c.z) - Math.hypot(b.x - c.x, b.z - c.z))[0];
      if (hp && Math.hypot(hp.x - c.x, hp.z - c.z) < 50) want = Math.atan2(hp.x - c.x, hp.z - c.z);
    }
    for (const s of this.strikes) { const d = Math.hypot(s.x - c.x, s.z - c.z); if (d < s.r + 3) { want = Math.atan2(c.x - s.x, c.z - s.z); break; } }
    const probe = (ang, d) => { const px = c.x + Math.sin(ang) * d, pz = c.z + Math.cos(ang) * d; return this.hitObstacle(px, 1, pz) || Math.abs(px) > this.arena.half - 4 || Math.abs(pz) > this.arena.half - 4; };
    if (probe(c.heading, 7) || probe(c.heading, 11)) {
      const l = probe(c.heading - 0.6, 9), r = probe(c.heading + 0.6, 9);
      want = c.heading + (l && !r ? 1.2 : r && !l ? -1.2 : (ai.strafe * 1.2));
    }
    let steer = clamp(wrap(want - c.heading) * 2.2, -1, 1);
    let throttle = dist < 9 ? 0.55 : 1;
    if (ai.reverseT > 0) { ai.reverseT -= dt; throttle = -1; steer = -steer || ai.strafe; }
    else if (Math.abs(c.speed) < 2 && this.state === 'fight') { ai.stuck += dt; if (ai.stuck > 0.9) { ai.reverseT = 1.1; ai.stuck = 0; ai.strafe *= -1; } }
    else ai.stuck = 0;
    c.throttle = throttle * (0.75 + 0.25 * (diff.aggression || 1)); c.steer = steer;

    const aim = Math.abs(wrap(toT - c.heading));
    c.firing = dist < 48 && aim < 0.3;
    ai.rocketT -= dt;
    if (ai.rocketT <= 0 && dist < (c.power ? 70 : 55) && aim < 0.2) { this.fireRocket(c); ai.rocketT = R(2.5, 5) / (diff.aggression || 1); }
    ai.specialT -= dt;
    if (ai.specialT <= 0 && c.specialCd <= 0) {
      const sp = c.data.special.id;
      const recent = this.time - c.lastHit < 1.2;
      const go = (sp === 'smoke' && c.hp < c.maxHp * 0.5 && recent) || (sp === 'dash' && (dist > 32 || (c.hp < c.maxHp * 0.4 && recent)))
        || (sp === 'toxic' && dist < 18 && aim < 0.5) || (sp === 'riptide' && dist < 13 && aim < 0.6) || (sp === 'pulse' && dist < 14)
        || (sp === 'whip' && dist < 9) || (sp === 'shell' && dist < 55 && aim < 0.12)
        || (sp === 'nitro' && dist > 35) || (sp === 'ram' && dist < 22 && aim < 0.25) || (sp === 'shockwave' && dist < 11)
        || (sp === 'flame' && dist < 11 && aim < 0.4) || (sp === 'shield' && c.hp < c.maxHp * 0.55 && this.time - c.lastHit < 1)
        || ((sp === 'homing' || sp === 'barrage') && dist < 45 && aim < 0.4) || (sp === 'mines' && dist < 20 && aim > 2.2);
      if (go && Math.random() < (diff.aggression || 1)) this.useSpecial(c);
      ai.specialT = R(0.8, 2);
    }
  }

  t(s, v) { return tr(s, v); }
  camHeading() { return Math.atan2(this.camLook.x - this.camPos.x, this.camLook.z - this.camPos.z); }

  // ---------- camera ----------
  snapCamera() { this.updateCamera(1, true); }
  setCamMode(m) { this.camMode = m; this.camModeT = 0.4; }
  updateCamera(dt, snap = false) {
    const p = this.player, fx = Math.sin(p.heading), fz = Math.cos(p.heading);
    // camera modes: 'near' chase (default), 'far' chase (wide view), 'hood' (on the bonnet, looking ahead)
    const dm = p.mesh.userData.dims || { L: 5.2, H: 2.2 }, size = Math.max(1, dm.L / 5.2), portrait = this.camera.aspect < 1;
    let mode = this.camMode || 'near'; if (mode === 'hood' && !p.alive) mode = 'near';
    const speedPull = clamp(Math.abs(p.speed) / 40, 0, 1) * (mode === 'far' ? 2.5 : 1.5);
    const want = this.camWant || (this.camWant = new THREE.Vector3()), look = this.camAim || (this.camAim = new THREE.Vector3());
    let k;
    if (mode === 'hood') {
      const h = dm.H * 0.95 + 0.3, f = dm.L * 0.02; // just over the roof: the front of the car stays in view
      want.set(p.x + fx * f, h, p.z + fz * f);
      look.set(p.x + fx * 30, h - 2.6, p.z + fz * 30);
      k = snap ? 1 : 1 - Math.exp(-dt * 30); // locked to the car
    } else {
      const back = (mode === 'far' ? (portrait ? 17 : 13) : (portrait ? 12 : 8.5)) * size, up = (mode === 'far' ? (portrait ? 11 : 7.5) : (portrait ? 7.5 : 4.6)) * Math.sqrt(size);
      want.set(p.x - fx * (back + speedPull), up + speedPull * 0.3, p.z - fz * (back + speedPull));
      look.set(p.x + fx * (mode === 'far' ? 6 : 8), mode === 'far' ? 1.5 : 1.8, p.z + fz * (mode === 'far' ? 6 : 8));
      k = snap ? 1 : 1 - Math.exp(-dt * (mode === 'far' ? 4.5 : 6));
    }
    if (mode !== 'hood') { // never let the camera go behind the arena walls or into tall cover: pull it in and lift it
      const lim = this.arena.half + 1.2, dx = want.x - p.x, dz = want.z - p.z; // the low barriers may sit under the camera; the buildings behind them may not
      let t = 1;
      if (Math.abs(want.x) > lim && Math.abs(dx) > 0.01) t = Math.min(t, (Math.sign(dx) * lim - p.x) / dx);
      if (Math.abs(want.z) > lim && Math.abs(dz) > 0.01) t = Math.min(t, (Math.sign(dz) * lim - p.z) / dz);
      for (let i = 1; i <= 10; i++) { // tall obstacles between car and camera
        const u = (i / 10) * t, h = 1.5 + (want.y - 1.5) * u;
        const o = this.hitObstacle(p.x + dx * u, h, p.z + dz * u);
        if (o && o.h > 2.5) { t = Math.max(0.25, u - 0.12); break; }
      }
      if (t < 1) { t = Math.max(0.25, t); want.set(p.x + dx * t, want.y * (0.35 + 0.65 * t) + (1 - t) * 2.5, p.z + dz * t); look.set(look.x - fx * (1 - t) * 3, look.y, look.z - fz * (1 - t) * 3); }
    }
    if (this.camModeT > 0) { this.camModeT -= dt; k = Math.max(k, 0.25); } // quick glide when switching
    this.camPos.lerp(want, k); this.camLook.lerp(look, snap || mode === 'hood' ? Math.max(k, 1 - Math.exp(-dt * 20)) : 1 - Math.exp(-dt * 7));
    this.camera.position.copy(this.camPos);
    if (this.shake > 0) {
      const s = this.shake * this.shake * 1.2;
      this.camera.position.x += R(-s, s); this.camera.position.y += R(-s, s); this.camera.position.z += R(-s, s);
      this.shake = Math.max(0, this.shake - dt * 1.8);
    }
    this.camera.lookAt(this.camLook);
    const fov = this.baseFov() + (p.specialOn === 'nitro' || p.specialOn === 'ram' ? 8 : 0);
    if (Math.abs(this.camera.fov - fov) > 0.1) { this.camera.fov += (fov - this.camera.fov) * Math.min(1, dt * 5); this.camera.updateProjectionMatrix(); }
  }

  vol(c) { return c.isPlayer ? 1 : this.volAt(c.x, c.z); }
  pan(c) { return c.isPlayer ? 0 : this.panAt(c.x, c.z); }
  // stereo position of a world point: -1 left .. 1 right of the camera, softened so nothing is hard-panned
  panAt(x, z) {
    const cam = this.camera, e = cam.matrixWorld.elements; // column 0 = camera right vector
    const dx = x - cam.position.x, dz = z - cam.position.z, d = Math.hypot(dx, dz);
    return d < 2 ? 0 : clamp((dx * e[0] + dz * e[2]) / d, -1, 1) * 0.7;
  }
  // "wheeeew... boom": an enemy rocket on course to hit the player whistles in, timed to land with the impact
  warnIncoming(r) {
    const p = this.player; if (!p.alive || r.owner === p) return;
    const dx = p.x - r.x, dz = p.z - r.z, d = Math.hypot(dx, dz);
    if (d > 38) return;
    const fx = Math.sin(r.dir), fz = Math.cos(r.dir), ahead = dx * fx + dz * fz;
    if (ahead <= 0) { r.warned = true; return; } // already past us
    if (Math.abs(dx * fz - dz * fx) > HR(p) + 3) return; // would miss by a margin
    r.warned = true;
    if (this.time - (this.lastIncoming || -9) < 0.6) return; // one whistle at a time
    this.lastIncoming = this.time;
    sfx.incoming(ahead / r.speed, r.kind === 'rocket' || r.kind === 'napalm' ? 0.75 : 1, this.panAt(r.x, r.z));
  }
  volAt(x, z) { return clamp(1.15 - Math.hypot(x - this.player.x, z - this.player.z) / 80, 0.08, 1); }

  // ---------- end ----------
  checkEnd() {
    const p = this.player;
    if (!p.alive && p.lives === 0) { this.result = this.mode === 'survival' ? 'survival' : 'loss'; this.state = 'ending'; this.endT = 3; sfx.lose(); this.hud.banner(this.mode === 'survival' ? `${this.t('WAVE')} ${this.wave}` : this.t('WRECKED'), false); return; }
    if (this.mode !== 'deathmatch') return;
    const left = this.cars.filter((c) => this.inPlay(c));
    if (left.length === 1 && left[0] === p) { this.result = 'win'; this.state = 'ending'; this.endT = 3; sfx.win(); this.hud.banner(this.t('VICTORY'), true); return; }
    if (this.time - 3.5 >= TIME_LIMIT) { // time up: most kills wins (a tie goes to the player)
      const top = Math.max(...this.cars.map((c) => c.kills));
      const win = p.kills >= top;
      this.result = win ? 'win' : 'loss'; this.state = 'ending'; this.endT = 3;
      if (win) { sfx.win(); this.hud.banner(this.t('VICTORY'), true); } else { sfx.lose(); this.hud.banner(this.t('TIME UP'), false); }
    }
  }
  timeLeft() { return this.mode === 'deathmatch' ? Math.max(0, TIME_LIMIT - Math.max(0, this.time - 3.5)) : null; }
  finish() {
    if (this.over) return;
    this.over = true; this.running = false; sfx.engineStop();
    this.hud.onEnd({ result: this.result, mode: this.mode, kills: this.player.kills, time: this.time, stats: this.stats });
  }
  quit() { this.running = false; this.over = true; sfx.engineStop(); }

  dispose() {
    this.running = false;
    sfx.engineStop();
    this.scene.traverse((o) => { if (o.geometry) o.geometry.dispose(); });
    while (this.scene.children.length) this.scene.remove(this.scene.children[0]);
    this.cars = []; this.bullets = []; this.rockets = []; this.mines = []; this.drops = []; this.zones = []; this.strikes = [];
  }
}
export { KILL_REWARD };
