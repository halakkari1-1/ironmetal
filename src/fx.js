// Particle effects: one additive system (fire, sparks, flashes) and one normal system (smoke, dust).
import * as THREE from 'three';

const VERT = `
attribute float size; attribute vec4 pcolor;
varying vec4 vColor;
uniform float scale;
void main() {
  vColor = pcolor;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_PointSize = size * scale / max(0.1, -mv.z);
  gl_Position = projectionMatrix * mv;
}`;
const FRAG = `
varying vec4 vColor;
void main() {
  vec2 p = gl_PointCoord - 0.5;
  float d = length(p);
  if (d > 0.5) discard;
  float a = smoothstep(0.5, 0.0, d);
  gl_FragColor = vec4(vColor.rgb, vColor.a * a);
}`;

class System {
  constructor(max, additive) {
    this.max = max; this.n = 0;
    this.pos = new Float32Array(max * 3); this.col = new Float32Array(max * 4); this.size = new Float32Array(max);
    this.vel = new Float32Array(max * 3); this.life = new Float32Array(max); this.maxLife = new Float32Array(max);
    this.s0 = new Float32Array(max); this.s1 = new Float32Array(max);
    this.c0 = new Float32Array(max * 4); this.c1 = new Float32Array(max * 4);
    this.grav = new Float32Array(max); this.drag = new Float32Array(max);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('pcolor', new THREE.BufferAttribute(this.col, 4).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    this.mat = new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG, uniforms: { scale: { value: 400 } },
      transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(g, this.mat);
    this.points.frustumCulled = false;
    this.geo = g;
  }
  spawn(x, y, z, vx, vy, vz, life, s0, s1, c0, c1, grav = 0, drag = 1) {
    if (this.n >= this.max) return;
    const i = this.n++;
    this.pos.set([x, y, z], i * 3); this.vel.set([vx, vy, vz], i * 3);
    this.life[i] = life; this.maxLife[i] = life; this.s0[i] = s0; this.s1[i] = s1;
    this.c0.set(c0, i * 4); this.c1.set(c1, i * 4); this.grav[i] = grav; this.drag[i] = drag;
  }
  update(dt) {
    let i = 0;
    while (i < this.n) {
      this.life[i] -= dt;
      if (this.life[i] <= 0) { this.kill(i); continue; }
      const t = 1 - this.life[i] / this.maxLife[i];
      const k = Math.exp(-this.drag[i] * dt);
      this.vel[i * 3] *= k; this.vel[i * 3 + 1] = this.vel[i * 3 + 1] * k - this.grav[i] * dt; this.vel[i * 3 + 2] *= k;
      this.pos[i * 3] += this.vel[i * 3] * dt; this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt; this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      if (this.pos[i * 3 + 1] < 0.05) { this.pos[i * 3 + 1] = 0.05; this.vel[i * 3 + 1] *= -0.3; }
      this.size[i] = this.s0[i] + (this.s1[i] - this.s0[i]) * t;
      for (let c = 0; c < 4; c++) this.col[i * 4 + c] = this.c0[i * 4 + c] + (this.c1[i * 4 + c] - this.c0[i * 4 + c]) * t;
      i++;
    }
    this.geo.setDrawRange(0, this.n);
    for (const a of ['position', 'pcolor', 'size']) this.geo.attributes[a].needsUpdate = true;
  }
  kill(i) {
    const j = --this.n;
    if (i === j) return;
    const cp = (arr, w) => { for (let c = 0; c < w; c++) arr[i * w + c] = arr[j * w + c]; };
    cp(this.pos, 3); cp(this.vel, 3); cp(this.col, 4); cp(this.c0, 4); cp(this.c1, 4);
    for (const a of [this.life, this.maxLife, this.s0, this.s1, this.size, this.grav, this.drag]) a[i] = a[j];
  }
  clear() { this.n = 0; this.geo.setDrawRange(0, 0); }
}

const R = (a, b) => a + Math.random() * (b - a);

export class FX {
  constructor(scene) {
    this.glow = new System(1800, true);
    this.smoke = new System(1400, false);
    scene.add(this.smoke.points, this.glow.points);
    this.flash = new THREE.PointLight(0xffa040, 0, 40, 1.6);
    scene.add(this.flash);
    this.flashT = 0;
    this.rings = [];
    this.scene = scene;
  }
  setScale(h) { this.glow.mat.uniforms.scale.value = h * 0.9; this.smoke.mat.uniforms.scale.value = h * 0.9; }

  explosion(x, z, size = 1) {
    const y = 1;
    for (let i = 0; i < 40 * size; i++) {
      const a = Math.random() * Math.PI * 2, s = R(4, 16) * size;
      this.glow.spawn(x, y, z, Math.cos(a) * s, R(2, 12) * size, Math.sin(a) * s, R(0.35, 0.8), R(3, 6) * size, R(0.5, 1.5),
        [1, R(0.6, 0.85), 0.25, 1], [0.8, 0.15, 0.02, 0], 6, 2.5);
    }
    for (let i = 0; i < 26 * size; i++) { // sparks
      const a = Math.random() * Math.PI * 2, s = R(14, 30) * size;
      this.glow.spawn(x, y, z, Math.cos(a) * s, R(6, 18), Math.sin(a) * s, R(0.4, 0.9), 0.5, 0.2, [1, 0.9, 0.5, 1], [1, 0.4, 0.1, 0], 25, 0.8);
    }
    for (let i = 0; i < 22 * size; i++) {
      const a = Math.random() * Math.PI * 2, s = R(1, 5) * size;
      this.smoke.spawn(x + R(-1, 1), y + R(0, 1.5), z + R(-1, 1), Math.cos(a) * s, R(2, 6), Math.sin(a) * s, R(1.5, 3), R(3, 5) * size, R(8, 12) * size,
        [0.18, 0.15, 0.13, 0.85], [0.3, 0.28, 0.26, 0], -0.6, 1.2);
    }
    this.glow.spawn(x, y + 1, z, 0, 0, 0, 0.18, 14 * size, 22 * size, [1, 0.9, 0.6, 1], [1, 0.5, 0.1, 0]);
    this.flash.position.set(x, 3, z); this.flash.intensity = 120 * size; this.flashT = 0.25;
  }
  ring(x, z, radius, color = 0x9fd4ff) {
    const m = new THREE.Mesh(new THREE.TorusGeometry(1, 0.25, 6, 32), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false }));
    m.rotation.x = Math.PI / 2; m.position.set(x, 0.6, z);
    this.scene.add(m); this.rings.push({ m, t: 0, radius });
  }
  spark(x, y, z) {
    for (let i = 0; i < 5; i++) this.glow.spawn(x, y, z, R(-6, 6), R(1, 7), R(-6, 6), R(0.15, 0.3), 0.6, 0.1, [1, 0.85, 0.4, 1], [1, 0.4, 0.1, 0], 20, 1);
  }
  muzzle(x, y, z) { this.glow.spawn(x, y, z, 0, 0, 0, 0.06, 2.2, 0.8, [1, 0.85, 0.4, 1], [1, 0.5, 0.1, 0]); }
  trail(x, y, z) {
    this.glow.spawn(x, y, z, R(-0.5, 0.5), R(-0.5, 0.5), R(-0.5, 0.5), 0.15, 1.6, 0.4, [1, 0.7, 0.3, 1], [1, 0.3, 0.05, 0]);
    this.smoke.spawn(x, y, z, R(-0.6, 0.6), R(0.2, 1.2), R(-0.6, 0.6), R(0.6, 1.1), 1.2, 3.5, [0.55, 0.53, 0.5, 0.6], [0.4, 0.4, 0.4, 0]);
  }
  burn(x, y, z) { // smoke and flame from a damaged or wrecked car
    this.smoke.spawn(x + R(-0.5, 0.5), y, z + R(-0.5, 0.5), R(-0.4, 0.4), R(2, 4), R(-0.4, 0.4), R(1.2, 2.2), 1.5, 5, [0.12, 0.11, 0.1, 0.7], [0.25, 0.24, 0.23, 0], 0, 0.6);
  }
  fire(x, y, z) {
    this.glow.spawn(x + R(-0.4, 0.4), y, z + R(-0.4, 0.4), R(-0.3, 0.3), R(1.5, 3.5), R(-0.3, 0.3), R(0.3, 0.6), 1.6, 0.4, [1, 0.6, 0.15, 0.9], [0.9, 0.15, 0.02, 0]);
  }
  flame(x, y, z, dx, dz) {
    for (let i = 0; i < 3; i++) {
      const sp = R(16, 24), a = R(-0.22, 0.22), c = Math.cos(a), s = Math.sin(a);
      const vx = (dx * c - dz * s) * sp, vz = (dx * s + dz * c) * sp;
      this.glow.spawn(x, y, z, vx, R(0, 2), vz, R(0.35, 0.55), 0.8, 4.5, [1, 0.8, 0.3, 1], [0.9, 0.2, 0.03, 0], -2, 1.2);
    }
  }
  exhaust(x, y, z, dx, dz) { this.glow.spawn(x, y, z, -dx * 8 + R(-1, 1), R(0, 1), -dz * 8 + R(-1, 1), 0.2, 1.4, 0.3, [0.5, 0.7, 1, 1], [1, 0.4, 0.1, 0]); }
  dust(x, z, amt = 1) { this.smoke.spawn(x + R(-0.6, 0.6), 0.3, z + R(-0.6, 0.6), R(-1, 1), R(0.5, 1.5), R(-1, 1), R(0.5, 1.0), 1, 3.2 * amt, [0.55, 0.47, 0.38, 0.35 * amt], [0.55, 0.47, 0.38, 0], 0, 1); }
  heal(x, z) { for (let i = 0; i < 20; i++) this.glow.spawn(x + R(-1.5, 1.5), R(0.5, 2), z + R(-1.5, 1.5), 0, R(3, 6), 0, R(0.5, 0.9), 1.2, 0.3, [0.4, 1, 0.5, 1], [0.2, 1, 0.4, 0]); }

  update(dt) {
    this.glow.update(dt); this.smoke.update(dt);
    if (this.flashT > 0) { this.flashT -= dt; this.flash.intensity *= Math.exp(-dt * 14); if (this.flashT <= 0) this.flash.intensity = 0; }
    this.rings = this.rings.filter((r) => {
      r.t += dt; const k = r.t / 0.45;
      r.m.scale.setScalar(1 + k * r.radius); r.m.material.opacity = 0.9 * (1 - k);
      if (k >= 1) { this.scene.remove(r.m); r.m.geometry.dispose(); r.m.material.dispose(); return false; }
      return true;
    });
  }
  clear() { this.glow.clear(); this.smoke.clear(); this.rings.forEach((r) => this.scene.remove(r.m)); this.rings = []; this.flash.intensity = 0; }
}
