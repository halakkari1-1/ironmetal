// Effects: textured fire/smoke particles, sparks, flying debris, ground scorch marks and explosion lighting.
import * as THREE from 'three';

// Soft billowy puff texture built from layered noise, so smoke and fire read as volume instead of dots.
function puffTexture() {
  const S = 128, c = document.createElement('canvas'); c.width = c.height = S;
  const g = c.getContext('2d'), img = g.createImageData(S, S);
  const rnd = (x, y) => { const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453; return s - Math.floor(s); };
  const noise = (x, y) => {
    const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi;
    const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    const a = rnd(xi, yi), b = rnd(xi + 1, yi), cc = rnd(xi, yi + 1), d = rnd(xi + 1, yi + 1);
    return a + (b - a) * u + (cc - a) * v + (a - b - cc + d) * u * v;
  };
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const nx = x / S - 0.5, ny = y / S - 0.5, r = Math.sqrt(nx * nx + ny * ny) * 2;
    let n = 0, amp = 0.5, f = 4;
    for (let o = 0; o < 5; o++) { n += noise(x / S * f + 13, y / S * f + 7) * amp; amp *= 0.5; f *= 2; }
    const edge = Math.max(0, 1 - Math.pow(r, 1.6));
    const a = Math.max(0, Math.min(1, edge * (0.35 + n * 1.1) - 0.08));
    const shade = 0.7 + n * 0.45;
    const i = (y * S + x) * 4;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = Math.min(255, shade * 255);
    img.data[i + 3] = a * 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.NoColorSpace;
  return t;
}

function scorchTexture() {
  const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
  const grd = g.createRadialGradient(64, 64, 4, 64, 64, 62);
  grd.addColorStop(0, 'rgba(8,6,4,0.95)'); grd.addColorStop(0.45, 'rgba(15,11,8,0.75)'); grd.addColorStop(1, 'rgba(20,15,10,0)');
  g.fillStyle = grd; g.fillRect(0, 0, 128, 128);
  for (let i = 0; i < 26; i++) { // splash streaks
    const a = Math.random() * Math.PI * 2, l = 30 + Math.random() * 30;
    g.strokeStyle = `rgba(10,8,6,${0.3 + Math.random() * 0.4})`; g.lineWidth = 2 + Math.random() * 4;
    g.beginPath(); g.moveTo(64, 64); g.lineTo(64 + Math.cos(a) * l, 64 + Math.sin(a) * l); g.stroke();
  }
  return new THREE.CanvasTexture(c);
}

const VERT = `
attribute float size; attribute vec4 pcolor; attribute float rot;
varying vec4 vColor; varying float vRot;
uniform float scale;
void main() {
  vColor = pcolor; vRot = rot;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = size * scale / max(0.1, -mv.z);
  gl_Position = projectionMatrix * mv;
}`;
const FRAG = `
uniform sampler2D map; uniform float boost;
varying vec4 vColor; varying float vRot;
void main() {
  vec2 p = gl_PointCoord - 0.5;
  float c = cos(vRot), s = sin(vRot);
  vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y) + 0.5;
  vec4 t = texture2D(map, q);
  float a = t.a * vColor.a;
  if (a < 0.01) discard;
  gl_FragColor = vec4(vColor.rgb * t.rgb * boost, a);
}`;

class System {
  constructor(max, additive, tex, boost) {
    this.max = max; this.n = 0;
    const F = (k) => new Float32Array(max * k);
    this.pos = F(3); this.col = F(4); this.size = F(1); this.rot = F(1);
    this.vel = F(3); this.life = F(1); this.maxLife = F(1); this.delay = F(1); this.spin = F(1);
    this.s0 = F(1); this.s1 = F(1); this.c0 = F(4); this.c1 = F(4); this.grav = F(1); this.drag = F(1);
    const g = new THREE.BufferGeometry();
    const attr = (name, arr, k) => g.setAttribute(name, new THREE.BufferAttribute(arr, k).setUsage(THREE.DynamicDrawUsage));
    attr('position', this.pos, 3); attr('pcolor', this.col, 4); attr('size', this.size, 1); attr('rot', this.rot, 1);
    this.mat = new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG,
      uniforms: { scale: { value: 400 }, map: { value: tex }, boost: { value: boost } },
      transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(g, this.mat); this.points.frustumCulled = false;
    this.geo = g;
  }
  spawn(x, y, z, vx, vy, vz, life, s0, s1, c0, c1, grav = 0, drag = 1, delay = 0) {
    if (this.n >= this.max) return;
    const i = this.n++;
    this.pos[i * 3] = x; this.pos[i * 3 + 1] = y; this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
    this.life[i] = life; this.maxLife[i] = life; this.delay[i] = delay;
    this.s0[i] = s0; this.s1[i] = s1; this.c0.set(c0, i * 4); this.c1.set(c1, i * 4);
    this.grav[i] = grav; this.drag[i] = drag; this.rot[i] = Math.random() * 6.28; this.spin[i] = (Math.random() - 0.5) * 2;
    this.size[i] = 0;
  }
  update(dt) {
    let i = 0;
    while (i < this.n) {
      if (this.delay[i] > 0) { this.delay[i] -= dt; this.size[i] = 0; i++; continue; }
      this.life[i] -= dt;
      if (this.life[i] <= 0) { this.kill(i); continue; }
      const t = 1 - this.life[i] / this.maxLife[i];
      const k = Math.exp(-this.drag[i] * dt), j = i * 3;
      this.vel[j] *= k; this.vel[j + 1] = this.vel[j + 1] * k - this.grav[i] * dt; this.vel[j + 2] *= k;
      this.pos[j] += this.vel[j] * dt; this.pos[j + 1] += this.vel[j + 1] * dt; this.pos[j + 2] += this.vel[j + 2] * dt;
      if (this.pos[j + 1] < 0.05) { this.pos[j + 1] = 0.05; this.vel[j + 1] *= -0.3; }
      const e = 1 - (1 - t) * (1 - t); // ease-out growth
      this.size[i] = this.s0[i] + (this.s1[i] - this.s0[i]) * e;
      this.rot[i] += this.spin[i] * dt;
      for (let c = 0; c < 4; c++) this.col[i * 4 + c] = this.c0[i * 4 + c] + (this.c1[i * 4 + c] - this.c0[i * 4 + c]) * t;
      i++;
    }
    this.geo.setDrawRange(0, this.n);
    for (const a of ['position', 'pcolor', 'size', 'rot']) this.geo.attributes[a].needsUpdate = true;
  }
  kill(i) {
    const j = --this.n;
    if (i === j) return;
    const cp = (arr, w) => { for (let c = 0; c < w; c++) arr[i * w + c] = arr[j * w + c]; };
    cp(this.pos, 3); cp(this.vel, 3); cp(this.col, 4); cp(this.c0, 4); cp(this.c1, 4);
    for (const a of [this.life, this.maxLife, this.s0, this.s1, this.size, this.grav, this.drag, this.delay, this.rot, this.spin]) a[i] = a[j];
  }
  clear() { this.n = 0; this.geo.setDrawRange(0, 0); }
}

const R = (a, b) => a + Math.random() * (b - a);
let PUFF = null, SCORCH = null;

export class FX {
  constructor(scene) {
    if (!PUFF) { PUFF = puffTexture(); SCORCH = scorchTexture(); }
    this.scene = scene;
    this.smoke = new System(1600, false, PUFF, 1);
    this.fire = new System(1400, true, PUFF, 1.5);
    this.hot = new System(900, true, PUFF, 2.4); // sparks and flashes: small, very bright, they bloom
    this.smoke.points.renderOrder = 1; this.fire.points.renderOrder = 2; this.hot.points.renderOrder = 3;
    scene.add(this.smoke.points, this.fire.points, this.hot.points);
    this.lights = [0, 1, 2].map(() => { const l = new THREE.PointLight(0xff9a40, 0, 55, 1.5); scene.add(l); return { l, t: 0 }; });
    this.li = 0;
    this.rings = []; this.debris = []; this.scorches = [];
    this.debrisGeo = [new THREE.BoxGeometry(0.5, 0.18, 0.4), new THREE.BoxGeometry(0.3, 0.3, 0.7), new THREE.TetrahedronGeometry(0.35), new THREE.CylinderGeometry(0.25, 0.25, 0.15, 6)];
    this.debrisMat = [new THREE.MeshStandardMaterial({ color: 0x2a2724, metalness: 0.7, roughness: 0.5, flatShading: true }), new THREE.MeshStandardMaterial({ color: 0x5a3018, metalness: 0.4, roughness: 0.8, flatShading: true })];
    this.scorchGeo = new THREE.PlaneGeometry(1, 1);
  }
  setScale(h) { for (const s of [this.smoke, this.fire, this.hot]) s.mat.uniforms.scale.value = h * 0.9; }

  light(x, y, z, power, color = 0xff9a40) {
    const L = this.lights[this.li++ % this.lights.length];
    L.l.position.set(x, y, z); L.l.color.setHex(color); L.l.intensity = power; L.t = 0.35;
  }

  explosion(x, z, size = 1, opts = {}) {
    const y = 1.0;
    // 1) white-hot core flash
    this.hot.spawn(x, y + 0.8, z, 0, 0, 0, 0.1, 4 * size, 9 * size, [1, 0.75, 0.45, 0.55], [1, 0.35, 0.08, 0]);
    // 2) rolling fireball
    for (let i = 0; i < 16 * size; i++) {
      const a = Math.random() * 6.28, el = R(-0.2, 1.2), s = R(3, 9) * size;
      this.fire.spawn(x + R(-0.5, 0.5), y + R(0, 1), z + R(-0.5, 0.5), Math.cos(a) * s * Math.cos(el), Math.sin(el) * s + 2, Math.sin(a) * s * Math.cos(el),
        R(0.5, 1.0), R(2, 3.5) * size, R(5, 8) * size, [1, R(0.45, 0.6), 0.15, 0.42], [0.45, 0.06, 0.02, 0], -3, 2.6, R(0, 0.08));
    }
    // 3) thick smoke column that takes over as the fire dies
    for (let i = 0; i < 26 * size; i++) {
      const a = Math.random() * 6.28, s = R(1, 4.5) * size, dark = R(0.04, 0.1);
      this.smoke.spawn(x + R(-1.2, 1.2), y + R(0.5, 2.5), z + R(-1.2, 1.2), Math.cos(a) * s, R(2.5, 6), Math.sin(a) * s,
        R(2.2, 4.2), R(3.5, 5) * size, R(10, 15) * size, [dark, dark * 0.95, dark * 0.9, 0.92], [0.18, 0.17, 0.16, 0], -0.8, 0.9, R(0.12, 0.35));
    }
    // 4) sparks and burning bits arcing out
    for (let i = 0; i < 34 * size; i++) {
      const a = Math.random() * 6.28, s = R(12, 32) * size;
      this.hot.spawn(x, y + 0.5, z, Math.cos(a) * s, R(6, 20), Math.sin(a) * s, R(0.5, 1.2), R(0.18, 0.32), 0.08, [1, 0.8, 0.4, 1], [1, 0.3, 0.05, 0], 26, 0.6);
    }
    // 5) dust shock ring along the ground
    for (let i = 0; i < 26 * size; i++) {
      const a = (i / (26 * size)) * 6.28, s = R(14, 22) * size;
      this.smoke.spawn(x + Math.cos(a), 0.4, z + Math.sin(a), Math.cos(a) * s, R(0.3, 1.5), Math.sin(a) * s, R(0.7, 1.3), 1.5 * size, 5 * size, [0.36, 0.3, 0.24, 0.4], [0.36, 0.3, 0.24, 0], 0, 3.5);
    }
    // 6) debris
    const chunks = Math.round((opts.debris ?? 6) * size);
    for (let i = 0; i < chunks; i++) this.chunk(x, y + 0.5, z, size, opts.burning !== false);
    // 7) light + scorch
    this.light(x, 4, z, 85 * size);
    this.scorch(x, z, 4.5 * size);
  }

  chunk(x, y, z, size, burning) {
    if (this.debris.length > 90) { const d = this.debris.shift(); this.scene.remove(d.m); }
    const m = new THREE.Mesh(this.debrisGeo[Math.floor(Math.random() * 4)], this.debrisMat[Math.random() < 0.6 ? 0 : 1]);
    const s = R(0.6, 1.5) * Math.min(1.5, size); m.scale.setScalar(s);
    m.position.set(x, y, z); m.castShadow = true; this.scene.add(m);
    const a = Math.random() * 6.28, sp = R(6, 16) * size;
    this.debris.push({ m, vx: Math.cos(a) * sp, vy: R(8, 18) * size, vz: Math.sin(a) * sp, sx: R(-12, 12), sz: R(-12, 12), life: R(6, 10), burn: burning && Math.random() < 0.5 ? R(0.8, 2.5) : 0, rest: false });
  }

  scorch(x, z, r) {
    const m = new THREE.Mesh(this.scorchGeo, new THREE.MeshBasicMaterial({ map: SCORCH, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 }));
    m.rotation.x = -Math.PI / 2; m.rotation.z = Math.random() * 6.28; m.position.set(x, 0.03, z); m.scale.setScalar(r * 2);
    this.scene.add(m); this.scorches.push({ m, t: 40 });
    if (this.scorches.length > 28) { const s = this.scorches.shift(); this.scene.remove(s.m); s.m.material.dispose(); }
  }

  ring(x, z, radius, color = 0x9fd4ff) {
    const m = new THREE.Mesh(new THREE.TorusGeometry(1, 0.25, 6, 40), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false }));
    m.rotation.x = Math.PI / 2; m.position.set(x, 0.6, z);
    this.scene.add(m); this.rings.push({ m, t: 0, radius });
    for (let i = 0; i < 40; i++) { const a = (i / 40) * 6.28; this.smoke.spawn(x + Math.cos(a) * 2, 0.5, z + Math.sin(a) * 2, Math.cos(a) * 26, R(0.5, 2), Math.sin(a) * 26, 0.9, 2, 6, [0.55, 0.48, 0.4, 0.6], [0.55, 0.48, 0.4, 0], 0, 3); }
  }
  spark(x, y, z, n = 6) {
    for (let i = 0; i < n; i++) this.hot.spawn(x, y, z, R(-7, 7), R(1, 8), R(-7, 7), R(0.15, 0.35), R(0.15, 0.28), 0.06, [1, 0.85, 0.5, 1], [1, 0.4, 0.1, 0], 24, 0.8);
    this.smoke.spawn(x, y, z, R(-1, 1), R(0.5, 1.5), R(-1, 1), 0.5, 0.6, 1.8, [0.5, 0.48, 0.45, 0.5], [0.5, 0.48, 0.45, 0]);
  }
  impact(x, z) { this.smoke.spawn(x, 0.3, z, R(-1, 1), R(1, 3), R(-1, 1), R(0.4, 0.7), 0.6, 2, [0.55, 0.47, 0.38, 0.6], [0.55, 0.47, 0.38, 0], 3); }
  muzzle(x, y, z, dx, dz, isPlayer) {
    this.hot.spawn(x, y, z, dx * 4, 0, dz * 4, 0.05, R(1.6, 2.4), 0.8, [1, 0.85, 0.45, 1], [1, 0.5, 0.1, 0]);
    this.hot.spawn(x + dx * 0.5, y, z + dz * 0.5, dx * 10, 0, dz * 10, 0.04, 1.2, 0.5, [1, 0.8, 0.4, 1], [1, 0.4, 0.1, 0]);
    if (isPlayer && Math.random() < 0.5) this.light(x, y + 0.3, z, 18, 0xffb060);
  }
  trail(x, y, z) {
    this.hot.spawn(x, y, z, R(-0.4, 0.4), R(-0.4, 0.4), R(-0.4, 0.4), 0.09, 1.3, 0.5, [1, 0.8, 0.45, 1], [1, 0.4, 0.1, 0]);
    this.smoke.spawn(x, y, z, R(-0.5, 0.5), R(0.3, 1.2), R(-0.5, 0.5), R(0.9, 1.6), 0.9, 3.6, [0.6, 0.58, 0.55, 0.55], [0.45, 0.44, 0.42, 0]);
  }
  burn(x, y, z) {
    this.smoke.spawn(x + R(-0.6, 0.6), y, z + R(-0.6, 0.6), R(-0.4, 0.4), R(2, 4.5), R(-0.4, 0.4), R(1.8, 3.2), 1.6, 6.5, [0.05, 0.045, 0.04, 0.8], [0.14, 0.13, 0.12, 0], -0.3, 0.5);
  }
  flames(x, y, z, k = 1) {
    this.fire.spawn(x + R(-0.5, 0.5), y, z + R(-0.5, 0.5), R(-0.4, 0.4), R(2, 4), R(-0.4, 0.4), R(0.35, 0.65), R(1.2, 2) * k, 0.5, [1, 0.65, 0.2, 0.95], [0.8, 0.12, 0.02, 0], -2);
  }
  flame(x, y, z, dx, dz) {
    for (let i = 0; i < 4; i++) {
      const sp = R(15, 24), a = R(-0.2, 0.2), c = Math.cos(a), s = Math.sin(a);
      this.fire.spawn(x, y, z, (dx * c - dz * s) * sp, R(0, 2.5), (dx * s + dz * c) * sp, R(0.35, 0.6), 0.7, R(4, 6), [1, 0.85, 0.4, 1], [0.7, 0.12, 0.02, 0], -3, 1.4);
    }
    if (Math.random() < 0.4) this.smoke.spawn(x + dx * 8, y + 1, z + dz * 8, dx * 6, R(2, 4), dz * 6, R(1, 1.6), 2, 6, [0.12, 0.11, 0.1, 0.5], [0.2, 0.2, 0.2, 0]);
  }
  exhaust(x, y, z, dx, dz) { this.hot.spawn(x, y, z, -dx * 9 + R(-1, 1), R(0, 1), -dz * 9 + R(-1, 1), 0.18, 1.5, 0.3, [0.55, 0.75, 1, 1], [1, 0.45, 0.1, 0]); }
  dust(x, z, amt = 1) { this.smoke.spawn(x + R(-0.7, 0.7), 0.4, z + R(-0.7, 0.7), R(-1, 1), R(0.6, 1.8), R(-1, 1), R(0.7, 1.3), 1.2, 4 * amt, [0.58, 0.5, 0.4, 0.3 * amt], [0.58, 0.5, 0.4, 0]); }
  heal(x, z) { for (let i = 0; i < 24; i++) this.hot.spawn(x + R(-1.6, 1.6), R(0.5, 2), z + R(-1.6, 1.6), 0, R(3, 6), 0, R(0.5, 0.9), 0.9, 0.2, [0.35, 1, 0.45, 1], [0.15, 1, 0.35, 0]); }
  beacon(x, z) { this.smoke.spawn(x + R(-0.3, 0.3), 1.2, z + R(-0.3, 0.3), R(-0.6, 0.6), R(5, 8), R(-0.6, 0.6), R(2.5, 3.5), 1.2, 5, [0.25, 0.5, 1, 0.75], [0.5, 0.65, 0.9, 0], -0.5, 0.4); }
  sand(x, z) { this.smoke.spawn(x, R(0.5, 6), z, R(14, 22), R(-0.5, 0.5), R(4, 8), R(1.2, 2), R(4, 7), R(8, 12), [0.75, 0.6, 0.42, 0.35], [0.75, 0.6, 0.42, 0], 0, 0.2); }
  laser(ax, ay, az, bx, by, bz) { // beam drawn as a dense line of hot points
    const n = Math.min(120, Math.ceil(Math.hypot(bx - ax, bz - az) * 1.6));
    for (let i = 0; i < n; i++) { const t = i / n; this.hot.spawn(ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, 0, 0, 0, 0.18, 1.1, 0.2, [0.5, 0.85, 1, 1], [0.2, 0.4, 1, 0]); }
  }

  update(dt) {
    this.smoke.update(dt); this.fire.update(dt); this.hot.update(dt);
    for (const L of this.lights) if (L.t > 0) { L.t -= dt; L.l.intensity *= Math.exp(-dt * 10); if (L.t <= 0) L.l.intensity = 0; }
    this.rings = this.rings.filter((r) => {
      r.t += dt; const k = r.t / 0.45;
      r.m.scale.setScalar(1 + k * r.radius); r.m.material.opacity = 0.9 * (1 - k);
      if (k >= 1) { this.scene.remove(r.m); r.m.geometry.dispose(); r.m.material.dispose(); return false; }
      return true;
    });
    this.debris = this.debris.filter((d) => {
      d.life -= dt;
      if (!d.rest) {
        d.vy -= 30 * dt; d.m.position.x += d.vx * dt; d.m.position.y += d.vy * dt; d.m.position.z += d.vz * dt;
        d.m.rotation.x += d.sx * dt; d.m.rotation.z += d.sz * dt;
        if (d.m.position.y < 0.15) {
          d.m.position.y = 0.15; d.vy *= -0.35; d.vx *= 0.6; d.vz *= 0.6; d.sx *= 0.5; d.sz *= 0.5;
          if (Math.abs(d.vy) < 1.5) d.rest = true;
        }
      }
      if (d.burn > 0) { d.burn -= dt; if (Math.random() < 0.5) this.flames(d.m.position.x, d.m.position.y, d.m.position.z, 0.5); if (Math.random() < 0.3) this.burn(d.m.position.x, d.m.position.y + 0.3, d.m.position.z); }
      if (d.life <= 0) { d.m.scale.multiplyScalar(0.9); if (d.m.scale.x < 0.05) { this.scene.remove(d.m); return false; } }
      return true;
    });
    for (const s of this.scorches) { s.t -= dt; if (s.t < 8) s.m.material.opacity = Math.max(0, s.t / 8); }
  }
  clear() {
    this.smoke.clear(); this.fire.clear(); this.hot.clear();
    for (const r of this.rings) this.scene.remove(r.m);
    for (const d of this.debris) this.scene.remove(d.m);
    for (const s of this.scorches) this.scene.remove(s.m);
    this.rings = []; this.debris = []; this.scorches = [];
    for (const L of this.lights) L.l.intensity = 0;
  }
}
