// A single match: cars, physics, weapons, specials, AI, pickups and win/lose.
import * as THREE from 'three';
import { CARS, carStats } from './data.js';
import { buildCar, wreck } from './cars3d.js';
import { buildArena } from './arena.js';
import { FX } from './fx.js';
import { sfx } from './audio.js';

const CAR_R = 2.1;
const TAU = Math.PI * 2;
const wrap = (a) => { while (a > Math.PI) a -= TAU; while (a < -Math.PI) a += TAU; return a; };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const R = (a, b) => a + Math.random() * (b - a);
const v3 = new THREE.Vector3();

export class Game {
  constructor(renderer, hud) {
    this.renderer = renderer;
    this.hud = hud;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(62, 1, 0.5, 600);
    this.running = false;
  }

  start({ car, upgrades, map, diff }) {
    this.map = map; this.diff = diff;
    this.arena = buildArena(this.scene, map);
    this.fx = new FX(this.scene);
    this.cars = []; this.bullets = []; this.rockets = []; this.mines = []; this.pickups = [];
    this.time = 0; this.state = 'countdown'; this.countdown = 3.5; this.shake = 0; this.over = false;
    this.bulletGeo = new THREE.BoxGeometry(0.12, 0.12, 1.6);
    this.bulletMat = new THREE.MeshBasicMaterial({ color: 0xffd36a });
    this.enemyBulletMat = new THREE.MeshBasicMaterial({ color: 0xff7a4a });

    const spawns = [...this.arena.spawns].sort(() => Math.random() - 0.5);
    this.player = this.addCar(car, upgrades, spawns[0], true);
    const pool = CARS.filter((c) => c.price <= diff.maxPrice && (c.id !== car.id || c.price === 0));
    for (let i = 0; i < diff.enemies; i++) {
      const c = pool[Math.floor(Math.random() * pool.length)];
      const lvl = diff.level;
      this.addCar(c, { gun: lvl, rocket: lvl, armor: lvl, speed: lvl, special: lvl }, spawns[i + 1], false);
    }
    this.buildPickups();
    this.camPos = new THREE.Vector3(); this.camLook = new THREE.Vector3();
    this.snapCamera();
    sfx.engineStart();
    this.running = true;
    this.hud.onStart(this);
  }

  addCar(data, upgrades, spawn, isPlayer) {
    const stats = carStats(data, upgrades);
    if (!isPlayer) stats.hp = Math.round(stats.hp * this.diff.hp);
    const mesh = buildCar(data.id);
    this.scene.add(mesh);
    const c = {
      data, stats, mesh, isPlayer,
      x: spawn.x, z: spawn.z, heading: spawn.heading, speed: 0, kx: 0, kz: 0,
      hp: stats.hp, maxHp: stats.hp, alive: true,
      throttle: 0, steer: 0, firing: false,
      gunCd: 0, rocketCd: 0, rockets: 6, specialCd: 2, specialT: 0, specialOn: null,
      kills: 0, lastHit: 0, lastAttacker: null, muzzleI: 0, deathT: 0, rammed: new Set(),
      dmgMul: isPlayer ? 1 : this.diff.dmg,
      ai: isPlayer ? null : { target: null, retarget: 0, stuck: 0, reverseT: 0, rocketT: R(2, 4), strafe: Math.random() < 0.5 ? 1 : -1, specialT: R(3, 6) },
    };
    if (data.special.id === 'shield') {
      c.bubble = new THREE.Mesh(new THREE.SphereGeometry(3.4, 16, 12), new THREE.MeshBasicMaterial({ color: 0x7fd8ff, transparent: true, opacity: 0.22, depthWrite: false, blending: THREE.AdditiveBlending }));
      c.bubble.visible = false; mesh.add(c.bubble); c.bubble.position.y = 1.2;
    }
    this.cars.push(c);
    return c;
  }

  buildPickups() {
    const geoH = new THREE.BoxGeometry(1.4, 1.4, 1.4), geoA = new THREE.BoxGeometry(1.8, 1.0, 1.2);
    const matH = new THREE.MeshStandardMaterial({ color: 0x2b8a3e, emissive: 0x1d6b2c, emissiveIntensity: 0.8 });
    const matA = new THREE.MeshStandardMaterial({ color: 0x9c6b1f, emissive: 0x7a4a10, emissiveIntensity: 0.7 });
    const cross = new THREE.MeshBasicMaterial({ color: 0xffffff });
    for (const s of this.arena.pickupSpots) {
      for (const o of this.arena.obstacles) { // nudge out of obstacles
        const d = Math.hypot(s.x - o.x, s.z - o.z), r = (o.r || Math.max(o.hw, o.hd)) + 3;
        if (d < r) { const k = r / Math.max(d, 0.1); s.x = o.x + (s.x - o.x) * k; s.z = o.z + (s.z - o.z) * k; }
      }
      const g = new THREE.Group(); g.position.set(s.x, 1.4, s.z);
      if (s.type === 'health') {
        g.add(new THREE.Mesh(geoH, matH));
        const a = new THREE.Mesh(new THREE.BoxGeometry(1.0, 0.3, 1.45), cross), b = new THREE.Mesh(new THREE.BoxGeometry(0.3, 1.0, 1.45), cross);
        g.add(a, b);
      } else {
        g.add(new THREE.Mesh(geoA, matA));
        for (let i = -1; i <= 1; i++) { const r = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.5, 6), new THREE.MeshStandardMaterial({ color: 0xd8d0c0 })); r.position.set(i * 0.45, 0.7, 0); g.add(r); }
      }
      const ring = new THREE.Mesh(new THREE.TorusGeometry(1.6, 0.08, 6, 24), new THREE.MeshBasicMaterial({ color: s.type === 'health' ? 0x5dff7a : 0xffb347 }));
      ring.rotation.x = Math.PI / 2; ring.position.y = -1.2; g.add(ring);
      this.scene.add(g);
      this.pickups.push({ ...s, mesh: g, respawn: 0 });
    }
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
      if (now !== before && now >= 0) { this.hud.countdown(now > 0 ? String(now) : 'FIGHT'); sfx.countdown(now === 0); }
      if (this.countdown <= 0) this.state = 'fight';
    }
    const active = this.state === 'fight' || this.state === 'ending';
    for (const c of this.cars) {
      if (!c.alive) { this.updateWreck(c, dt); continue; }
      if (active && !c.isPlayer) this.think(c, dt);
      if (!active) { c.throttle = 0; c.steer = 0; c.firing = false; }
      this.drive(c, dt);
      this.weapons(c, dt);
    }
    this.collideCars();
    this.updateBullets(dt); this.updateRockets(dt); this.updateMines(dt); this.updatePickups(dt);
    this.fx.update(dt);
    this.updateCamera(dt);
    const p = this.player;
    sfx.engineSet(Math.abs(p.throttle), clamp(Math.abs(p.speed) / p.stats.maxSpeed, 0, 1));
    if (this.state === 'fight') this.checkEnd();
    if (this.state === 'ending') { this.endT -= dt; if (this.endT <= 0) this.finish(); }
    this.hud.update(this, dt);
  }

  render() { this.renderer.render(this.scene, this.camera); }
  resize(w, h) { this.camera.aspect = w / h; this.camera.fov = w < h ? 78 : 62; this.camera.updateProjectionMatrix(); if (this.fx) this.fx.setScale(h); }

  // ---------- driving ----------
  drive(c, dt) {
    const s = c.stats;
    const nitro = c.specialOn === 'nitro', ram = c.specialOn === 'ram';
    const maxS = s.maxSpeed * (nitro ? 1.75 : 1) * (ram ? 2.1 : 1);
    const acc = s.accel * (nitro ? 2 : 1);
    if (ram) c.speed = Math.min(maxS, c.speed + acc * 4 * dt);
    else if (c.throttle > 0.05) c.speed += acc * c.throttle * dt * (c.speed < 0 ? 2 : 1);
    else if (c.throttle < -0.05) c.speed += acc * c.throttle * dt * (c.speed > 0 ? 1.8 : 0.7);
    else c.speed -= c.speed * Math.min(1, 1.4 * dt);
    c.speed = clamp(c.speed, -s.maxSpeed * 0.45, maxS);
    if (!ram && c.speed > s.maxSpeed * (nitro ? 1.75 : 1)) c.speed -= (c.speed - s.maxSpeed) * 2 * dt;
    const turnScale = clamp(c.speed / 7, -1, 1) * (1 - 0.35 * clamp(Math.abs(c.speed) / maxS, 0, 1));
    c.heading = wrap(c.heading + c.steer * s.turn * turnScale * dt);
    const fx = Math.sin(c.heading), fz = Math.cos(c.heading);
    c.x += (fx * c.speed + c.kx) * dt; c.z += (fz * c.speed + c.kz) * dt;
    const kd = Math.exp(-4 * dt); c.kx *= kd; c.kz *= kd;
    this.collideWorld(c);
    c.mesh.position.set(c.x, 0, c.z);
    c.mesh.rotation.y = c.heading;
    c.mesh.rotation.x = THREE.MathUtils.lerp(c.mesh.rotation.x, -clamp(c.throttle * 0.04 - (c.speed < 0 ? 0.02 : 0), -0.05, 0.05), 0.1);
    c.mesh.rotation.z = THREE.MathUtils.lerp(c.mesh.rotation.z, c.steer * clamp(c.speed / 30, -1, 1) * 0.06, 0.1);
    for (const w of c.mesh.userData.wheels) w.children[0].parent.rotation.x += c.speed * dt / 0.5;
    if (Math.abs(c.speed) > 12 && Math.random() < 0.5) this.fx.dust(c.x - fx * 2, c.z - fz * 2, this.map.id === 'dustbowl' ? 1.6 : 0.8);
    if (nitro || ram) this.fx.exhaust(c.x - fx * 2.4, 0.9, c.z - fz * 2.4, fx, fz);
    if (c.hp < c.maxHp * 0.35 && Math.random() < 0.3) this.fx.burn(c.x, 1.6, c.z);
    if (c.hp < c.maxHp * 0.18 && Math.random() < 0.4) this.fx.fire(c.x + fx, 1.2, c.z + fz);
  }

  collideWorld(c) {
    const h = this.arena.half - 1.2 - CAR_R;
    if (Math.abs(c.x) > h) { c.x = Math.sign(c.x) * h; c.speed *= 0.4; c.kx *= -0.5; this.bump(c); }
    if (Math.abs(c.z) > h) { c.z = Math.sign(c.z) * h; c.speed *= 0.4; c.kz *= -0.5; this.bump(c); }
    for (const o of this.arena.obstacles) {
      if (o.dead) continue;
      let dx, dz, d;
      if (o.kind === 'circle') { dx = c.x - o.x; dz = c.z - o.z; d = Math.hypot(dx, dz); if (d >= o.r + CAR_R) continue; const p = (o.r + CAR_R - d) / Math.max(d, 0.01); c.x += dx * p; c.z += dz * p; }
      else {
        const px = clamp(c.x, o.x - o.hw, o.x + o.hw), pz = clamp(c.z, o.z - o.hd, o.z + o.hd);
        dx = c.x - px; dz = c.z - pz; d = Math.hypot(dx, dz);
        if (d >= CAR_R) continue;
        if (d < 0.001) { // center inside the box: push out along the shallow axis
          const ox = o.hw + CAR_R - Math.abs(c.x - o.x), oz = o.hd + CAR_R - Math.abs(c.z - o.z);
          if (ox < oz) c.x += Math.sign(c.x - o.x || 1) * ox; else c.z += Math.sign(c.z - o.z || 1) * oz;
        } else { const p = (CAR_R - d) / d; c.x += dx * p; c.z += dz * p; }
      }
      const impact = Math.abs(c.speed);
      c.speed *= 0.55;
      if (impact > 14) { this.bump(c); if (o.barrel) this.damageObstacle(o, impact, c); }
    }
  }
  bump(c) { if (c.isPlayer && Math.abs(c.speed) > 6) this.shake = Math.max(this.shake, 0.25); }

  collideCars() {
    const cs = this.cars;
    for (let i = 0; i < cs.length; i++) for (let j = i + 1; j < cs.length; j++) {
      const a = cs[i], b = cs[j];
      if (!a.alive && !b.alive) continue;
      const dx = b.x - a.x, dz = b.z - a.z, d = Math.hypot(dx, dz), min = CAR_R * 2;
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
          this.damage(q, 48 * p.stats.specialPower * p.dmgMul, p);
          q.kx += nx * s * 30; q.kz += nz * s * 30;
          this.fx.explosion((a.x + b.x) / 2, (a.z + b.z) / 2, 0.45); sfx.explosion(0.5, this.vol(q));
          this.shake = Math.max(this.shake, 0.5);
        }
      }
      if (rel > 22) { if (a.alive) this.damage(a, rel * 0.08, b); if (b.alive) this.damage(b, rel * 0.08, a); }
      a.speed *= 0.7; b.speed *= 0.7;
    }
  }

  // ---------- weapons ----------
  weapons(c, dt) {
    c.gunCd -= dt; c.rocketCd -= dt; c.specialCd -= dt;
    if (c.specialOn) {
      c.specialT -= dt;
      if (c.specialOn === 'flame') this.flameTick(c, dt);
      if (c.specialT <= 0) { if (c.bubble) c.bubble.visible = false; c.specialOn = null; c.rammed.clear(); }
    }
    if (c.firing && c.gunCd <= 0 && (this.state === 'fight')) { this.fireGun(c); c.gunCd = 0.09; }
  }

  worldPoint(c, local) { return v3.copy(local).applyAxisAngle(THREE.Object3D.DEFAULT_UP, c.heading).add(new THREE.Vector3(c.x, 0, c.z)).clone(); }

  aimAt(c, range, cone) {
    let best = null, bestScore = Infinity;
    for (const o of this.cars) {
      if (o === c || !o.alive) continue;
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
    let dir = Math.atan2(Math.sin(c.heading), Math.cos(c.heading));
    const t = c.isPlayer ? this.aimAt(c, 55, 0.32) : c.ai.target;
    if (t && t.alive) {
      const dist = Math.hypot(t.x - c.x, t.z - c.z), lead = dist / 110;
      const tx = t.x + Math.sin(t.heading) * t.speed * lead, tz = t.z + Math.cos(t.heading) * t.speed * lead;
      const want = Math.atan2(tx - m.x, tz - m.z);
      if (Math.abs(wrap(want - c.heading)) < 0.45) dir = want;
    }
    const spread = c.isPlayer ? 0.03 : 0.03 + (1 - this.diff.accuracy) * 0.16;
    dir += R(-spread, spread);
    const b = new THREE.Mesh(this.bulletGeo, c.isPlayer ? this.bulletMat : this.enemyBulletMat);
    b.position.copy(m); b.rotation.y = dir;
    this.scene.add(b);
    this.bullets.push({ mesh: b, x: m.x, y: m.y, z: m.z, dx: Math.sin(dir), dz: Math.cos(dir), life: 0.5, owner: c, dmg: c.stats.gunDmg * c.dmgMul });
    this.fx.muzzle(m.x + Math.sin(dir) * 0.6, m.y, m.z + Math.cos(dir) * 0.6);
    sfx.gun(this.vol(c) * (c.isPlayer ? 1 : 0.6));
  }

  fireRocket(c, opts = {}) {
    if (!opts.free) { if (c.rocketCd > 0 || c.rockets <= 0) { if (c.isPlayer && c.rockets <= 0) sfx.denied(); return; } c.rockets--; c.rocketCd = 0.55; }
    const m = this.worldPoint(c, c.mesh.userData.rocketMuzzle);
    let dir = c.heading + (opts.offset || 0);
    if (!opts.offset) {
      const t = c.isPlayer ? this.aimAt(c, 70, 0.4) : c.ai.target;
      if (t && t.alive) { const want = Math.atan2(t.x - m.x, t.z - m.z); if (Math.abs(wrap(want - c.heading)) < 0.5) dir = want; }
      if (!c.isPlayer) dir += R(-1, 1) * (1 - this.diff.accuracy) * 0.2;
    }
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 1.1, 6), new THREE.MeshStandardMaterial({ color: 0xd9d2c4, metalness: 0.5 }));
    body.rotation.x = Math.PI / 2;
    const tip = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.4, 6), new THREE.MeshBasicMaterial({ color: 0xff3d1f }));
    tip.rotation.x = Math.PI / 2; tip.position.z = 0.7;
    g.add(body, tip); g.position.copy(m); g.rotation.y = dir;
    this.scene.add(g);
    this.rockets.push({
      mesh: g, x: m.x, y: Math.max(1.2, m.y), z: m.z, dir, speed: opts.speed || 52, life: 2.4, owner: c,
      dmg: c.stats.rocketDmg * c.dmgMul * (opts.dmgMul || 1), radius: c.stats.rocketRadius, homing: opts.homing || null,
    });
    sfx.rocket(this.vol(c) * (c.isPlayer ? 1 : 0.6));
  }

  useSpecial(c) {
    if (c.specialCd > 0 || c.specialOn) { if (c.isPlayer) sfx.denied(); return false; }
    const sp = c.data.special.id, pw = c.stats.specialPower;
    c.specialCd = c.stats.specialCooldown;
    const fx = Math.sin(c.heading), fz = Math.cos(c.heading);
    switch (sp) {
      case 'nitro': c.specialOn = 'nitro'; c.specialT = 3 * Math.min(1.5, pw); sfx.special(); break;
      case 'ram': c.specialOn = 'ram'; c.specialT = 1.3; c.rammed.clear(); c.speed = Math.max(c.speed, c.stats.maxSpeed); sfx.special(); break;
      case 'shield': c.specialOn = 'shield'; c.specialT = 4 * Math.min(1.5, pw); if (c.bubble) c.bubble.visible = true; sfx.shield(); break;
      case 'flame': c.specialOn = 'flame'; c.specialT = 3; break;
      case 'shockwave': {
        this.fx.ring(c.x, c.z, 13, 0xffc070); this.fx.explosion(c.x, c.z, 0.4); sfx.explosion(0.8, this.vol(c));
        for (const o of this.cars) {
          if (o === c || !o.alive) continue;
          const dx = o.x - c.x, dz = o.z - c.z, d = Math.hypot(dx, dz);
          if (d > 14) continue;
          const k = 1 - d / 14;
          this.damage(o, 34 * pw * c.dmgMul * (0.4 + 0.6 * k), c);
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
    for (const o of this.cars) {
      if (o === c || !o.alive) continue;
      const dx = o.x - c.x, dz = o.z - c.z, d = Math.hypot(dx, dz);
      if (d > 13) continue;
      if (Math.abs(wrap(Math.atan2(dx, dz) - c.heading)) > 0.42) continue;
      this.damage(o, 32 * c.stats.specialPower * c.dmgMul * dt, c, true);
      if (Math.random() < 0.3) this.fx.fire(o.x, 1.5, o.z);
    }
    for (const o of this.arena.obstacles) if (o.barrel && !o.dead && Math.hypot(o.x - c.x, o.z - c.z) < 11 && Math.abs(wrap(Math.atan2(o.x - c.x, o.z - c.z) - c.heading)) < 0.42) this.damageObstacle(o, 20 * dt, c);
  }

  // ---------- projectiles ----------
  hitObstacle(x, y, z) {
    for (const o of this.arena.obstacles) {
      if (o.dead || y > o.h + 0.3) continue;
      if (o.kind === 'circle') { if (Math.hypot(x - o.x, z - o.z) < o.r) return o; }
      else if (Math.abs(x - o.x) < o.hw && Math.abs(z - o.z) < o.hd) return o;
    }
    return null;
  }

  updateBullets(dt) {
    const SPEED = 110, steps = 3;
    this.bullets = this.bullets.filter((b) => {
      b.life -= dt;
      let hit = false;
      for (let s = 0; s < steps && !hit; s++) {
        b.x += b.dx * SPEED * dt / steps; b.z += b.dz * SPEED * dt / steps;
        for (const c of this.cars) {
          if (c === b.owner || !c.alive) continue;
          if (Math.hypot(c.x - b.x, c.z - b.z) < CAR_R) { this.damage(c, b.dmg, b.owner); this.fx.spark(b.x, b.y, b.z); if (b.owner.isPlayer) sfx.hit(); hit = true; break; }
        }
        if (!hit) { const o = this.hitObstacle(b.x, b.y, b.z); if (o) { this.fx.spark(b.x, b.y, b.z); if (o.barrel) this.damageObstacle(o, b.dmg, b.owner); hit = true; } }
        if (Math.abs(b.x) > this.arena.half || Math.abs(b.z) > this.arena.half) hit = true;
      }
      if (hit || b.life <= 0) { this.scene.remove(b.mesh); return false; }
      b.mesh.position.set(b.x, b.y, b.z);
      return true;
    });
  }

  updateRockets(dt) {
    this.rockets = this.rockets.filter((r) => {
      r.life -= dt;
      if (r.homing && r.homing.alive && r.life < 2.2) {
        const want = Math.atan2(r.homing.x - r.x, r.homing.z - r.z);
        r.dir += clamp(wrap(want - r.dir), -3 * dt, 3 * dt);
      }
      const step = r.speed * dt;
      r.x += Math.sin(r.dir) * step; r.z += Math.cos(r.dir) * step;
      r.y = Math.max(1.0, r.y - dt * 0.4);
      r.mesh.position.set(r.x, r.y, r.z); r.mesh.rotation.y = r.dir;
      this.fx.trail(r.x - Math.sin(r.dir) * 0.7, r.y, r.z - Math.cos(r.dir) * 0.7);
      let boom = r.life <= 0 || Math.abs(r.x) > this.arena.half - 0.8 || Math.abs(r.z) > this.arena.half - 0.8;
      if (!boom) for (const c of this.cars) if (c !== r.owner && c.alive && Math.hypot(c.x - r.x, c.z - r.z) < CAR_R + 0.4) { boom = true; break; }
      if (!boom && this.hitObstacle(r.x, r.y, r.z)) boom = true;
      if (boom) { this.scene.remove(r.mesh); this.explode(r.x, r.z, r.radius, r.dmg, r.owner, 0.8); return false; }
      return true;
    });
  }

  updateMines(dt) {
    this.mines = this.mines.filter((m) => {
      m.arm -= dt; m.life -= dt;
      m.led.visible = Math.sin(this.time * (m.arm > 0 ? 6 : 14)) > 0;
      let trig = m.life <= 0;
      if (m.arm <= 0) for (const c of this.cars) if (c.alive && c !== m.owner && Math.hypot(c.x - m.x, c.z - m.z) < 3.6) { trig = true; break; }
      if (trig) { this.scene.remove(m.mesh); this.explode(m.x, m.z, 7.5, m.dmg, m.owner, 1); return false; }
      return true;
    });
  }

  explode(x, z, radius, dmg, owner, size = 1) {
    this.fx.explosion(x, z, size);
    sfx.explosion(size, this.volAt(x, z));
    const pd = Math.hypot(this.player.x - x, this.player.z - z);
    this.shake = Math.max(this.shake, clamp(1 - pd / 45, 0, 1) * 0.7 * size);
    for (const c of this.cars) {
      if (!c.alive) continue;
      const d = Math.hypot(c.x - x, c.z - z);
      if (d > radius + CAR_R) continue;
      const k = clamp(1 - Math.max(0, d - CAR_R) / radius, 0.3, 1);
      this.damage(c, dmg * k * (c === owner ? 0.25 : 1), owner);
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
    o.mesh.visible = false;
    this.explode(o.x, o.z, 9, 55, by, 1.25);
  }

  // ---------- damage / death ----------
  damage(c, amt, by, quiet = false) {
    if (!c.alive || amt <= 0 || this.state === 'countdown') return;
    if (c.specialOn === 'shield') { if (!quiet && Math.random() < 0.3) this.fx.spark(c.x, 1.5, c.z); return; }
    c.hp -= amt; c.lastHit = this.time;
    if (by && by !== c) c.lastAttacker = by;
    if (c.isPlayer) { this.hud.hurt(amt); if (!quiet) sfx.hurt(); }
    if (c.ai && by && by !== c && Math.random() < 0.5) c.ai.target = by;
    if (c.hp <= 0) this.kill(c);
  }

  kill(c) {
    c.alive = false; c.hp = 0; c.deathT = 0;
    c.specialOn = null; if (c.bubble) c.bubble.visible = false;
    this.fx.explosion(c.x, c.z, 1.7); setTimeout(() => this.running && this.fx.explosion(c.x + R(-1, 1), c.z + R(-1, 1), 0.9), 180);
    sfx.explosion(1.5, this.volAt(c.x, c.z));
    wreck(c.mesh);
    c.mesh.position.y = 0.0;
    const killer = c.lastAttacker;
    if (killer && killer !== c) killer.kills++;
    this.hud.feed(killer && killer !== c ? killer : null, c);
    if (c.isPlayer) this.shake = 1; else if (Math.hypot(c.x - this.player.x, c.z - this.player.z) < 40) this.shake = Math.max(this.shake, 0.6);
  }

  updateWreck(c, dt) {
    c.deathT += dt;
    if (c.deathT < 7 && Math.random() < 0.5) this.fx.burn(c.x, 1.4, c.z);
    if (c.deathT < 3 && Math.random() < 0.6) this.fx.fire(c.x + R(-1, 1), 1, c.z + R(-1, 1));
    c.speed *= Math.exp(-3 * dt);
    c.x += (Math.sin(c.heading) * c.speed + c.kx) * dt; c.z += (Math.cos(c.heading) * c.speed + c.kz) * dt;
    c.kx *= Math.exp(-4 * dt); c.kz *= Math.exp(-4 * dt);
    this.collideWorld(c);
    c.mesh.position.set(c.x, 0, c.z);
  }

  updatePickups(dt) {
    for (const p of this.pickups) {
      if (p.respawn > 0) { p.respawn -= dt; p.mesh.visible = p.respawn <= 0; continue; }
      p.mesh.rotation.y += dt * 1.6; p.mesh.position.y = 1.4 + Math.sin(this.time * 3 + p.x) * 0.25;
      for (const c of this.cars) {
        if (!c.alive || Math.hypot(c.x - p.x, c.z - p.z) > 3) continue;
        if (p.type === 'health') { if (c.hp >= c.maxHp) continue; c.hp = Math.min(c.maxHp, c.hp + c.maxHp * 0.4); this.fx.heal(c.x, c.z); }
        else { if (c.rockets >= 12) continue; c.rockets = Math.min(12, c.rockets + 4); }
        if (c.isPlayer) { sfx.pickup(); this.hud.toast(p.type === 'health' ? '+ ARMOR REPAIRED' : '+4 ROCKETS'); }
        p.respawn = 16; p.mesh.visible = false; break;
      }
    }
  }

  // ---------- AI ----------
  think(c, dt) {
    const ai = c.ai, diff = this.diff;
    ai.retarget -= dt;
    if (!ai.target || !ai.target.alive || ai.retarget <= 0) {
      ai.retarget = R(2, 4);
      let best = null, bs = Infinity;
      for (const o of this.cars) {
        if (o === c || !o.alive) continue;
        const s = Math.hypot(o.x - c.x, o.z - c.z) * (o.isPlayer ? this.diff.focus : 1) * (o.hp / o.maxHp < 0.3 ? 0.7 : 1);
        if (s < bs) { bs = s; best = o; }
      }
      ai.target = best;
    }
    const t = ai.target;
    if (!t) { c.throttle = 0.3; c.steer = 0; c.firing = false; return; }
    const dx = t.x - c.x, dz = t.z - c.z, dist = Math.hypot(dx, dz);
    const toT = Math.atan2(dx, dz);
    let want = toT;
    if (dist < 14) want = toT + ai.strafe * 1.1;
    else if (c.hp < c.maxHp * 0.3) { // look for repairs when hurt
      const hp = this.pickups.filter((p) => p.type === 'health' && p.respawn <= 0).sort((a, b) => Math.hypot(a.x - c.x, a.z - c.z) - Math.hypot(b.x - c.x, b.z - c.z))[0];
      if (hp && Math.hypot(hp.x - c.x, hp.z - c.z) < 50) want = Math.atan2(hp.x - c.x, hp.z - c.z);
    }
    // obstacle probes
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
    c.throttle = throttle * (0.75 + 0.25 * diff.aggression); c.steer = steer;

    const aim = Math.abs(wrap(toT - c.heading));
    c.firing = dist < 48 && aim < 0.3;
    ai.rocketT -= dt;
    if (ai.rocketT <= 0 && dist < 55 && aim < 0.2) { this.fireRocket(c); ai.rocketT = R(2.5, 5) / diff.aggression; }
    ai.specialT -= dt;
    if (ai.specialT <= 0 && c.specialCd <= 0) {
      const sp = c.data.special.id;
      const go = (sp === 'nitro' && dist > 35) || (sp === 'ram' && dist < 22 && aim < 0.25) || (sp === 'shockwave' && dist < 11)
        || (sp === 'flame' && dist < 11 && aim < 0.4) || (sp === 'shield' && c.hp < c.maxHp * 0.55 && this.time - c.lastHit < 1)
        || ((sp === 'homing' || sp === 'barrage') && dist < 45 && aim < 0.4) || (sp === 'mines' && dist < 20 && aim > 2.2);
      if (go && Math.random() < diff.aggression) this.useSpecial(c);
      ai.specialT = R(0.8, 2);
    }
  }

  // ---------- camera ----------
  snapCamera() { this.updateCamera(1, true); }
  updateCamera(dt, snap = false) {
    const p = this.player, fx = Math.sin(p.heading), fz = Math.cos(p.heading);
    const back = this.camera.aspect < 1 ? 17 : 13, up = this.camera.aspect < 1 ? 11 : 7.5;
    const want = new THREE.Vector3(p.x - fx * back, up, p.z - fz * back);
    const look = new THREE.Vector3(p.x + fx * 6, 1.5, p.z + fz * 6);
    const k = snap ? 1 : 1 - Math.exp(-dt * 4.5);
    this.camPos.lerp(want, k); this.camLook.lerp(look, snap ? 1 : 1 - Math.exp(-dt * 7));
    this.camera.position.copy(this.camPos);
    if (this.shake > 0) {
      const s = this.shake * this.shake * 1.2;
      this.camera.position.x += R(-s, s); this.camera.position.y += R(-s, s); this.camera.position.z += R(-s, s);
      this.shake = Math.max(0, this.shake - dt * 1.8);
    }
    this.camera.lookAt(this.camLook);
  }

  vol(c) { return c.isPlayer ? 1 : this.volAt(c.x, c.z); }
  volAt(x, z) { return clamp(1.15 - Math.hypot(x - this.player.x, z - this.player.z) / 80, 0.08, 1); }

  // ---------- end ----------
  checkEnd() {
    const alive = this.cars.filter((c) => c.alive);
    if (!this.player.alive) { this.result = 'loss'; this.state = 'ending'; this.endT = 2.6; sfx.lose(); this.hud.banner('WRECKED'); }
    else if (alive.length === 1) { this.result = 'win'; this.state = 'ending'; this.endT = 2.6; sfx.win(); this.hud.banner('VICTORY'); }
  }
  finish() {
    if (this.over) return;
    this.over = true; this.running = false; sfx.engineStop();
    this.hud.onEnd({ result: this.result, kills: this.player.kills, time: this.time, enemies: this.diff.enemies });
  }
  quit() { this.running = false; this.over = true; sfx.engineStop(); }

  dispose() {
    this.running = false;
    sfx.engineStop();
    this.scene.traverse((o) => { if (o.geometry) o.geometry.dispose(); });
    while (this.scene.children.length) this.scene.remove(this.scene.children[0]);
    this.cars = []; this.bullets = []; this.rockets = []; this.mines = [];
  }
}
