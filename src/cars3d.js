// Car models: the nine Meshy-made vehicles (loaded from assets/models), plus the original procedural builders,
// kept as a stand-in if a model file fails to load. Every car faces +Z and sits on y = 0.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { CARS } from './data.js';

// ---------- shared textures ----------
function makeGrime() {
  const c = document.createElement('canvas'); c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#d8d8d8'; g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 2600; i++) {
    const v = 170 + Math.random() * 85;
    g.fillStyle = `rgba(${v},${v},${v},${Math.random() * 0.35})`;
    g.fillRect(Math.random() * 256, Math.random() * 256, 1 + Math.random() * 3, 1 + Math.random() * 3);
  }
  for (let i = 0; i < 18; i++) { // rust blooms
    const x = Math.random() * 256, y = Math.random() * 256, r = 3 + Math.random() * 9;
    const grd = g.createRadialGradient(x, y, 0, x, y, r);
    grd.addColorStop(0, 'rgba(120,60,25,0.4)'); grd.addColorStop(1, 'rgba(120,60,25,0)');
    g.fillStyle = grd; g.beginPath(); g.arc(x, y, r, 0, 7); g.fill();
  }
  for (let i = 0; i < 60; i++) { // drips
    const x = Math.random() * 256; g.fillStyle = `rgba(60,45,35,${0.15 + Math.random() * 0.2})`;
    g.fillRect(x, Math.random() * 200, 1 + Math.random() * 2, 20 + Math.random() * 60);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
function makeStripes() {
  const c = document.createElement('canvas'); c.width = c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = '#e8b21e'; g.fillRect(0, 0, 64, 64);
  g.fillStyle = '#151515';
  for (let i = -64; i < 128; i += 32) { g.beginPath(); g.moveTo(i, 0); g.lineTo(i + 16, 0); g.lineTo(i - 48, 64); g.lineTo(i - 64, 64); g.fill(); }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
let GRIME = null, STRIPES = null;
function tex() { if (!GRIME) { GRIME = makeGrime(); STRIPES = makeStripes(); } }

// ---------- material + geometry helpers ----------
function mats(paint) {
  tex();
  const m = (color, o = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.75, metalness: 0.35, map: GRIME, flatShading: true, ...o });
  return {
    paint: m(paint, { roughness: 0.6, metalness: 0.45 }),
    dark: m(0x1d1d1f, { roughness: 0.85 }),
    steel: m(0x6f6c68, { metalness: 0.7, roughness: 0.45 }),
    chrome: new THREE.MeshStandardMaterial({ color: 0xb9b4ad, metalness: 0.95, roughness: 0.25, flatShading: true }),
    rust: m(0x7c3f1c, { roughness: 0.95, metalness: 0.2 }),
    tire: new THREE.MeshStandardMaterial({ color: 0x161616, roughness: 0.95, flatShading: true }),
    glass: new THREE.MeshStandardMaterial({ color: 0x0f1418, roughness: 0.15, metalness: 0.6 }),
    light: new THREE.MeshStandardMaterial({ color: 0xffe2a0, emissive: 0xffc860, emissiveIntensity: 1.6 }),
    tail: new THREE.MeshStandardMaterial({ color: 0x8a1010, emissive: 0xff2010, emissiveIntensity: 1.2 }),
    hazard: new THREE.MeshStandardMaterial({ map: STRIPES, roughness: 0.8, flatShading: true }),
    olive: m(0x4d5634),
  };
}

function add(group, geo, mat, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0) {
  const o = new THREE.Mesh(geo, mat);
  o.position.set(x, y, z); o.rotation.set(rx, ry, rz);
  o.castShadow = true; o.receiveShadow = true;
  group.add(o); return o;
}
const B = (w, h, l) => new THREE.BoxGeometry(w, h, l);
const C = (rt, rb, h, s = 10) => new THREE.CylinderGeometry(rt, rb, h, s);

// Side profile (pts as [z, y]) extruded across the car's width, with a small bevel.
function profile(pts, width, bevel = 0.06) {
  const s = new THREE.Shape();
  pts.forEach(([z, y], i) => (i ? s.lineTo(z, y) : s.moveTo(z, y)));
  s.closePath();
  const g = new THREE.ExtrudeGeometry(s, { depth: width - bevel * 2, bevelEnabled: true, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 1 });
  g.translate(0, 0, -(width - bevel * 2) / 2);
  g.rotateY(-Math.PI / 2);
  g.computeVertexNormals();
  return g;
}

function wheel(group, m, x, z, r, w, list, chained = false) {
  const wg = new THREE.Group(); wg.position.set(x, r, z);
  const tire = new THREE.Mesh(C(r, r, w, 14), m.tire); tire.rotation.z = Math.PI / 2; tire.castShadow = true;
  const rim = new THREE.Mesh(C(r * 0.55, r * 0.55, w + 0.02, 8), m.steel); rim.rotation.z = Math.PI / 2;
  const hub = new THREE.Mesh(C(r * 0.18, r * 0.18, w + 0.08, 6), m.chrome); hub.rotation.z = Math.PI / 2;
  wg.add(tire, rim, hub);
  for (let i = 0; i < 7; i++) { // tread blocks
    const a = (i / 7) * Math.PI * 2;
    const t = new THREE.Mesh(B(w * 1.04, r * 0.16, r * 0.3), m.tire);
    t.position.set(0, Math.cos(a) * r, Math.sin(a) * r); t.rotation.x = -a; wg.add(t);
  }
  if (chained) { const ch = new THREE.Mesh(new THREE.TorusGeometry(r * 1.0, 0.035, 4, 12), m.steel); ch.rotation.y = Math.PI / 2; ch.position.x = Math.sign(x) * w * 0.3; wg.add(ch); }
  group.add(wg); list.push(wg);
  return wg;
}

function spikes(group, m, x, y, z, n, dx, dz, len = 0.4, dir = [0, 0, 1]) {
  for (let i = 0; i < n; i++) {
    const s = add(group, new THREE.ConeGeometry(0.07, len, 5), m.steel, x + dx * i, y, z + dz * i);
    if (dir[2]) s.rotation.x = Math.PI / 2 * dir[2];
    if (dir[0]) s.rotation.z = -Math.PI / 2 * dir[0];
  }
}

function machineGun(group, m, x, y, z, scale = 1) {
  const g = new THREE.Group(); g.position.set(x, y, z); g.scale.setScalar(scale);
  add(g, B(0.3, 0.25, 0.6), m.dark);
  add(g, C(0.05, 0.05, 1.0, 6), m.dark, 0, 0.04, 0.75, Math.PI / 2);
  add(g, B(0.12, 0.2, 0.22), m.olive, 0.22, -0.04, 0);
  add(g, C(0.12, 0.16, 0.3, 8), m.steel, 0, -0.25, 0);
  group.add(g); return g;
}
function minigun(group, m, x, y, z, scale = 1) {
  const g = new THREE.Group(); g.position.set(x, y, z); g.scale.setScalar(scale);
  add(g, B(0.4, 0.32, 0.5), m.dark);
  for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2; add(g, C(0.035, 0.035, 1.1, 5), m.dark, Math.cos(a) * 0.09, Math.sin(a) * 0.09, 0.75, Math.PI / 2); }
  add(g, C(0.13, 0.13, 0.08, 8), m.steel, 0, 0, 1.1, Math.PI / 2);
  group.add(g); return g;
}
function rocketPod(group, m, x, y, z, cols = 3, rows = 2, mat = null) {
  const g = new THREE.Group(); g.position.set(x, y, z);
  add(g, B(cols * 0.24 + 0.1, rows * 0.24 + 0.1, 0.8), mat || m.olive);
  for (let c = 0; c < cols; c++) for (let r = 0; r < rows; r++)
    add(g, C(0.08, 0.08, 0.05, 8), m.tail, (c - (cols - 1) / 2) * 0.24, (r - (rows - 1) / 2) * 0.24, 0.41, Math.PI / 2);
  group.add(g); return g;
}

// Bakes every static part into one mesh per material (and each wheel into one mesh per material),
// turning ~60 draw calls per car into ~10. Positions are baked relative to the parent being merged into.
function mergeInto(parent, skip) {
  parent.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(parent.matrixWorld).invert(), byMat = new Map(), victims = [];
  parent.traverse((o) => {
    if (!o.isMesh || o === parent) return;
    for (let p = o.parent; p && p !== parent; p = p.parent) if (skip.has(p)) return;
    if (skip.has(o)) return;
    let g = o.geometry.index ? o.geometry.toNonIndexed() : o.geometry.clone();
    for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
    if (!g.attributes.uv) g.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
    g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld));
    if (!byMat.has(o.material)) byMat.set(o.material, []);
    byMat.get(o.material).push(g); victims.push(o);
  });
  for (const o of victims) o.parent.remove(o);
  for (const [mat, list] of byMat) {
    const m = new THREE.Mesh(mergeGeometries(list), mat); m.castShadow = true; m.receiveShadow = true; parent.add(m);
  }
}
function optimize(group, wheels) {
  const skip = new Set(wheels);
  mergeInto(group, skip);
  for (const w of wheels) mergeInto(w, new Set());
  // drop now-empty helper groups
  const empties = []; group.traverse((o) => { if (o.type === 'Group' && o !== group && !skip.has(o) && o.children.length === 0) empties.push(o); });
  for (const e of empties) e.parent.remove(e);
}
function finish(group, wheels, extra = {}) {
  if (!extra.keep) optimize(group, wheels); // model cars share their geometry; only procedural parts get merged
  group.userData = { wheels, muzzles: extra.muzzles || [new THREE.Vector3(0, 1.8, 2.4)], rocketMuzzle: extra.rocketMuzzle || new THREE.Vector3(0, 1.9, 1.8), flame: extra.flame || new THREE.Vector3(0, 0.8, 2.6), dims: extra.dims || null };
  return group;
}

// ---------- the seven designs ----------
const BUILDERS = {
  rustbucket() {
    const g = new THREE.Group(), m = mats(0x4f6e6a), w = [];
    add(g, profile([[-2.2, 0.45], [2.25, 0.45], [2.3, 0.95], [1.0, 1.1], [-2.15, 1.12]], 1.9), m.paint);
    add(g, profile([[-1.5, 1.1], [0.75, 1.1], [0.15, 1.65], [-1.2, 1.65]], 1.66, 0.03), m.glass);
    add(g, B(1.62, 0.07, 1.4), m.paint, 0, 1.68, -0.52);
    add(g, B(0.9, 0.5, 1.2), m.rust, 0.55, 0.85, -1.4).scale.set(1, 1, 1);
    add(g, B(1.96, 0.5, 0.6), m.rust, 0, 0.75, -1.95);
    add(g, B(1.5, 0.32, 0.06), m.dark, 0, 0.8, 2.3);
    add(g, B(0.3, 0.16, 0.05), m.light, 0.65, 0.82, 2.33); add(g, B(0.3, 0.16, 0.05), m.light, -0.65, 0.82, 2.33);
    add(g, B(0.3, 0.14, 0.05), m.tail, 0.7, 0.85, -2.23); add(g, B(0.3, 0.14, 0.05), m.tail, -0.7, 0.85, -2.23);
    add(g, B(2.1, 0.18, 0.2), m.steel, 0, 0.5, 2.42); add(g, B(2.0, 0.16, 0.2), m.steel, 0, 0.5, -2.32);
    for (let i = -1; i <= 1; i++) add(g, B(0.12, 0.6, 0.12), m.steel, i * 0.6, 0.75, 2.5);
    add(g, B(1.0, 0.05, 0.4), m.dark, 0, 1.13, 1.6);
    machineGun(g, m, 0, 1.95, -0.3);
    add(g, C(0.07, 0.07, 0.9, 6), m.chrome, 0.75, 0.55, -2.4, Math.PI / 2.4);
    [[0.95, 1.45], [-0.95, 1.45], [0.95, -1.4], [-0.95, -1.4]].forEach(([x, z]) => wheel(g, m, x, z, 0.47, 0.34, w));
    return finish(g, w, { muzzles: [new THREE.Vector3(0, 1.98, 1.0)], rocketMuzzle: new THREE.Vector3(0, 1.4, 1.6) });
  },

  stinger() {
    const g = new THREE.Group(), m = mats(0xc27a35), w = [];
    add(g, profile([[-1.9, 0.45], [2.1, 0.45], [2.2, 0.7], [0.9, 0.85], [-1.9, 0.85]], 1.5), m.paint);
    add(g, profile([[2.1, 0.55], [2.6, 0.5], [2.5, 0.75], [2.1, 0.8]], 1.3), m.dark);
    const tube = (x1, y1, z1, x2, y2, z2) => {
      const a = new THREE.Vector3(x1, y1, z1), b = new THREE.Vector3(x2, y2, z2), d = b.clone().sub(a);
      const o = add(g, C(0.05, 0.05, d.length(), 6), m.dark); o.position.copy(a).add(b).multiplyScalar(0.5);
      o.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize());
    };
    for (const s of [-1, 1]) {
      tube(s * 0.7, 0.85, 0.8, s * 0.6, 1.75, 0.1); tube(s * 0.6, 1.75, 0.1, s * 0.6, 1.75, -0.9);
      tube(s * 0.6, 1.75, -0.9, s * 0.7, 0.85, -1.5); tube(s * 0.7, 0.85, 0.8, s * 0.7, 0.85, -1.5);
    }
    tube(-0.6, 1.75, 0.1, 0.6, 1.75, 0.1); tube(-0.6, 1.75, -0.9, 0.6, 1.75, -0.9);
    add(g, B(0.5, 0.5, 0.5), m.dark, 0, 1.05, -0.3); // seat
    add(g, B(1.1, 0.55, 0.8), m.steel, 0, 1.05, -1.5); // engine
    for (const s of [-1, 1]) add(g, C(0.08, 0.1, 0.7, 6), m.chrome, s * 0.35, 1.3, -1.95, -0.6);
    // scorpion tail: armored segments arching from the engine over the cockpit
    const tailPts = [[0, 1.3, -1.9], [0, 2.1, -2.25], [0, 2.75, -1.85], [0, 3.0, -1.1], [0, 2.95, -0.35], [0, 2.7, 0.2]];
    for (let i = 0; i < tailPts.length - 1; i++) {
      const a = new THREE.Vector3(...tailPts[i]), b = new THREE.Vector3(...tailPts[i + 1]), d = b.clone().sub(a);
      const seg = add(g, B(0.34 - i * 0.03, 0.26 - i * 0.02, d.length() + 0.12), i % 2 ? m.dark : m.paint);
      seg.position.copy(a).add(b).multiplyScalar(0.5);
      seg.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), d.normalize());
      const sp = add(g, new THREE.ConeGeometry(0.05, 0.22, 4), m.steel); sp.position.copy(seg.position).add(new THREE.Vector3(0, 0.18, 0));
    }
    minigun(g, m, 0, 2.6, 0.4, 0.8);
    add(g, new THREE.ConeGeometry(0.12, 0.5, 5), m.steel, 0, 2.3, 0.7, Math.PI * 0.85);
    add(g, B(0.25, 0.12, 0.05), m.light, 0.45, 0.75, 2.2); add(g, B(0.25, 0.12, 0.05), m.light, -0.45, 0.75, 2.2);
    spikes(g, m, -0.5, 0.6, 2.55, 3, 0.5, 0, 0.35);
    [[0.9, 1.35, 0.45], [-0.9, 1.35, 0.45], [1.0, -1.4, 0.62], [-1.0, -1.4, 0.62]].forEach(([x, z, r]) => wheel(g, m, x, z, r, r > 0.5 ? 0.5 : 0.34, w));
    return finish(g, w, { muzzles: [new THREE.Vector3(0, 2.6, 1.4)], rocketMuzzle: new THREE.Vector3(0, 1.2, 2.0) });
  },

  bulldog() {
    const g = new THREE.Group(), m = mats(0xc99318), w = [];
    add(g, profile([[0.3, 0.55], [2.5, 0.55], [2.55, 1.25], [1.7, 1.35], [1.5, 2.25], [0.3, 2.25]], 2.1), m.paint);
    add(g, profile([[0.55, 1.4], [1.45, 1.4], [1.45, 2.1], [0.55, 2.1]], 2.14, 0.02), m.glass);
    add(g, B(2.1, 0.5, 2.9), m.steel, 0, 0.8, -1.2);
    add(g, B(2.1, 0.12, 2.9), m.hazard, 0, 1.08, -1.2);
    add(g, B(0.5, 0.5, 0.5), m.dark, 0, 1.35, -0.8);
    add(g, B(0.3, 0.3, 2.6), m.paint, 0, 1.75, -1.7, 0.55);
    add(g, C(0.03, 0.03, 0.6, 4), m.dark, 0, 2.1, -2.85);
    add(g, new THREE.TorusGeometry(0.18, 0.05, 5, 8, Math.PI * 1.4), m.steel, 0, 1.75, -2.85, 0, Math.PI / 2, 0);
    add(g, B(2.3, 0.6, 0.25), m.steel, 0, 0.75, 2.65);
    for (let i = -2; i <= 2; i++) add(g, B(0.1, 0.9, 0.1), m.dark, i * 0.45, 0.95, 2.78);
    add(g, B(0.3, 0.18, 0.05), m.light, 0.75, 1.1, 2.56); add(g, B(0.3, 0.18, 0.05), m.light, -0.75, 1.1, 2.56);
    add(g, B(1.4, 0.12, 0.2), m.light, 0, 2.32, 1.0); // roof light bar
    add(g, C(0.09, 0.09, 1.2, 6), m.chrome, 1.1, 2.0, 0.4);
    machineGun(g, m, 0, 2.55, 0.9);
    rocketPod(g, m, 0, 1.6, -0.2, 2, 2, m.dark);
    [[1.0, 1.7], [-1.0, 1.7], [1.0, -0.6], [-1.0, -0.6], [1.0, -1.9], [-1.0, -1.9]].forEach(([x, z]) => wheel(g, m, x, z, 0.55, 0.4, w));
    return finish(g, w, { muzzles: [new THREE.Vector3(0, 2.6, 1.7)], rocketMuzzle: new THREE.Vector3(0, 1.6, 0.3) });
  },

  hellfire() {
    const g = new THREE.Group(), m = mats(0x1b1a1c), w = [];
    const red = new THREE.MeshStandardMaterial({ color: 0xb3221a, roughness: 0.5, metalness: 0.4, map: GRIME, flatShading: true });
    add(g, profile([[-2.3, 0.4], [2.4, 0.4], [2.45, 0.85], [0.2, 1.0], [-2.3, 1.0]], 2.0), m.paint);
    add(g, profile([[-1.6, 0.98], [0.15, 0.98], [-0.35, 1.48], [-1.35, 1.48]], 1.7, 0.03), m.glass);
    add(g, B(1.66, 0.07, 1.0), m.paint, 0, 1.5, -0.85);
    add(g, B(0.3, 0.02, 4.6), red, 0.3, 1.01, 0); add(g, B(0.3, 0.02, 4.6), red, -0.3, 1.01, 0);
    add(g, B(0.7, 0.4, 0.9), m.chrome, 0, 1.15, 1.2); add(g, B(0.6, 0.15, 0.3), m.dark, 0, 1.4, 1.35);
    add(g, B(2.0, 0.08, 0.5), m.dark, 0, 1.25, -2.15); add(g, B(0.1, 0.35, 0.1), m.dark, 0.8, 1.1, -2.15); add(g, B(0.1, 0.35, 0.1), m.dark, -0.8, 1.1, -2.15);
    for (const s of [-1, 1]) {
      add(g, C(0.12, 0.16, 0.9, 8), m.steel, s * 0.6, 0.6, 2.55, Math.PI / 2);
      add(g, C(0.13, 0.13, 0.1, 8), red, s * 0.6, 0.6, 3.0, Math.PI / 2);
      add(g, C(0.06, 0.06, 1.6, 6), m.chrome, s * 1.05, 0.45, 0.0, Math.PI / 2);
    }
    add(g, B(0.4, 0.13, 0.05), m.light, 0.65, 0.75, 2.43); add(g, B(0.4, 0.13, 0.05), m.light, -0.65, 0.75, 2.43);
    add(g, B(1.8, 0.1, 0.05), m.tail, 0, 0.8, -2.32);
    add(g, C(0.35, 0.35, 0.9, 10), m.steel, 0, 1.2, -1.75, 0, 0, Math.PI / 2); // fuel tank
    machineGun(g, m, 0, 1.8, -0.9, 0.9);
    [[0.98, 1.5, 0.48], [-0.98, 1.5, 0.48], [1.0, -1.5, 0.55], [-1.0, -1.5, 0.55]].forEach(([x, z, r]) => wheel(g, m, x, z, r, 0.42, w));
    return finish(g, w, { muzzles: [new THREE.Vector3(0, 1.84, 0.1)], rocketMuzzle: new THREE.Vector3(0, 1.3, 1.6), flame: new THREE.Vector3(0, 0.6, 3.1) });
  },

  maiden() {
    const g = new THREE.Group(), m = mats(0x4d5634), w = [];
    add(g, profile([[-2.4, 0.5], [2.4, 0.5], [2.45, 1.2], [1.6, 2.2], [-2.4, 2.3]], 2.2), m.paint);
    for (let i = 0; i < 4; i++) add(g, B(1.9, 0.06, 0.06), m.dark, 0, 1.45 + i * 0.16, 2.05 - i * 0.12, -0.75);
    for (const s of [-1, 1]) {
      for (let i = 0; i < 3; i++) add(g, B(0.08, 0.9, 1.2), m.steel, s * 1.13, 1.25, 1.2 - i * 1.3);
      for (let i = 0; i < 4; i++) add(g, B(0.06, 0.05, 0.6), m.dark, s * 1.12, 1.85, -1.6 + i * 0.7);
    }
    add(g, B(2.4, 0.7, 0.3), m.steel, 0, 0.85, 2.55);
    spikes(g, m, -0.9, 0.9, 2.85, 4, 0.6, 0, 0.45);
    add(g, C(0.45, 0.45, 0.28, 12), m.tire, 0, 1.4, -2.55, Math.PI / 2);
    add(g, B(0.35, 0.14, 0.05), m.light, 0.75, 1.0, 2.46); add(g, B(0.35, 0.14, 0.05), m.light, -0.75, 1.0, 2.46);
    const tur = new THREE.Group(); tur.position.set(0, 2.35, -0.2); g.add(tur);
    add(tur, C(0.55, 0.65, 0.3, 10), m.steel);
    add(tur, B(1.1, 0.55, 0.08), m.paint, 0, 0.35, 0.55); add(tur, B(0.08, 0.55, 0.6), m.paint, 0.55, 0.35, 0.25); add(tur, B(0.08, 0.55, 0.6), m.paint, -0.55, 0.35, 0.25);
    minigun(tur, m, 0, 0.3, 0.2, 0.85);
    rocketPod(g, m, 0.85, 2.5, -1.6, 2, 2);
    [[1.05, 1.6], [-1.05, 1.6], [1.05, -1.6], [-1.05, -1.6]].forEach(([x, z]) => wheel(g, m, x, z, 0.55, 0.42, w));
    return finish(g, w, { muzzles: [new THREE.Vector3(0, 2.65, 1.0)], rocketMuzzle: new THREE.Vector3(0.85, 2.5, -1.1) });
  },

  viper() {
    const g = new THREE.Group(), m = mats(0x2c4b66), w = [];
    const cyan = new THREE.MeshStandardMaterial({ color: 0x0b2a30, emissive: 0x24d4e0, emissiveIntensity: 1.4 });
    add(g, profile([[-2.3, 0.35], [2.45, 0.35], [2.5, 0.55], [0.6, 0.9], [-2.3, 0.95]], 2.05), m.paint);
    add(g, profile([[-1.2, 0.88], [0.55, 0.88], [-0.25, 1.28], [-1.0, 1.28]], 1.4, 0.03), m.glass);
    add(g, B(1.8, 0.04, 0.06), cyan, 0, 0.5, 2.48);
    add(g, B(1.9, 0.05, 0.06), cyan, 0, 0.75, -2.32);
    add(g, B(2.1, 0.06, 0.55), m.dark, 0, 1.35, -2.0); add(g, B(0.08, 0.45, 0.3), m.dark, 0.85, 1.12, -2.0); add(g, B(0.08, 0.45, 0.3), m.dark, -0.85, 1.12, -2.0);
    for (const s of [-1, 1]) {
      add(g, B(0.12, 0.08, 2.0), m.steel, s * 1.12, 0.95, 0.0);
      for (let i = 0; i < 2; i++) {
        add(g, C(0.09, 0.09, 1.2, 8), m.steel, s * 1.12, 1.07 + i * 0.2, 0.1, Math.PI / 2);
        add(g, new THREE.ConeGeometry(0.09, 0.3, 8), m.tail, s * 1.12, 1.07 + i * 0.2, 0.85, Math.PI / 2);
      }
    }
    add(g, B(1.4, 0.15, 0.6), m.dark, 0, 0.62, 1.7);
    machineGun(g, m, 0, 1.45, -0.6, 0.75);
    [[1.0, 1.55, 0.44], [-1.0, 1.55, 0.44], [1.02, -1.5, 0.5], [-1.02, -1.5, 0.5]].forEach(([x, z, r]) => wheel(g, m, x, z, r, 0.45, w));
    return finish(g, w, { muzzles: [new THREE.Vector3(0, 1.48, 0.2)], rocketMuzzle: new THREE.Vector3(1.12, 1.1, 1.0) });
  },

  juggernaut() {
    const g = new THREE.Group(), m = mats(0x6e1a14), w = [];
    add(g, profile([[0.6, 0.6], [2.6, 0.6], [2.65, 2.3], [2.3, 2.6], [0.6, 2.6]], 2.3), m.paint);
    add(g, profile([[1.9, 1.75], [2.55, 1.75], [2.4, 2.4], [1.9, 2.4]], 2.34, 0.02), m.glass);
    add(g, B(2.0, 1.0, 0.1), m.chrome, 0, 1.2, 2.68);
    for (let i = 0; i < 6; i++) add(g, B(0.05, 0.9, 0.08), m.dark, -0.85 + i * 0.34, 1.2, 2.74);
    add(g, B(2.6, 0.5, 0.35), m.steel, 0, 0.7, 2.9);
    spikes(g, m, -1.1, 0.75, 3.15, 5, 0.55, 0, 0.6);
    for (const s of [-1, 1]) {
      add(g, C(0.1, 0.1, 2.2, 8), m.chrome, s * 1.25, 2.6, 0.75);
      add(g, B(0.3, 0.16, 0.05), m.light, s * 0.85, 1.95, 2.66);
    }
    add(g, B(2.3, 1.6, 2.8), m.dark, 0, 1.6, -1.25);
    add(g, B(2.32, 0.25, 2.82), m.hazard, 0, 2.1, -1.25);
    add(g, B(0.8, 0.5, 0.15), m.steel, 0, 0.9, -2.7);
    add(g, B(2.3, 0.08, 0.06), m.tail, 0, 1.0, -2.67);
    add(g, B(1.6, 0.1, 0.18), m.light, 0, 2.66, 2.3);
    minigun(g, m, 0.6, 2.75, 1.3, 0.9); minigun(g, m, -0.6, 2.75, 1.3, 0.9);
    rocketPod(g, m, 0, 2.6, -1.0, 3, 2, m.paint);
    [[1.1, 1.9], [-1.1, 1.9], [1.1, -0.6], [-1.1, -0.6], [1.1, -1.9], [-1.1, -1.9]].forEach(([x, z]) => wheel(g, m, x, z, 0.6, 0.45, w));
    return finish(g, w, { muzzles: [new THREE.Vector3(0.6, 2.78, 2.4), new THREE.Vector3(-0.6, 2.78, 2.4)], rocketMuzzle: new THREE.Vector3(0, 2.6, -0.5) });
  },
};

// ---------- Meshy car models (GLB) ----------
// Each car's model ships as assets/models/<id>.js, a script that stores the base64 GLB in window.__GLB[id]
// (scripts load from file:// in the app and from any static host). Models load on demand and are cached.
const MODELS = {}; // id -> { scene, promise }
export function preloadModel(id) {
  const m = MODELS[id] || (MODELS[id] = {});
  if (m.scene) return Promise.resolve(m.scene);
  if (m.promise) return m.promise;
  m.promise = new Promise((resolve, reject) => {
    const parse = () => {
      try {
        const b = atob(window.__GLB[id]); const u = new Uint8Array(b.length);
        for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
        delete window.__GLB[id]; // free the base64 copy
        new GLTFLoader().parse(u.buffer, '', (gl) => {
          gl.scene.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
          m.scene = gl.scene; resolve(m.scene);
        }, reject);
      } catch (e) { reject(e); }
    };
    if (window.__GLB && window.__GLB[id]) return parse();
    const s = document.createElement('script');
    s.src = new URL(`../assets/models/${id}.js`, import.meta.url).href;
    s.onload = parse; s.onerror = () => { m.promise = null; reject(new Error(`model ${id} missing`)); }; document.head.appendChild(s);
  });
  return m.promise;
}
export function preloadModels(ids) { return Promise.all([...new Set(ids)].map((id) => preloadModel(id).catch(() => null))); }
export const modelReady = (id) => !!(MODELS[id] && MODELS[id].scene);
// kept for older call sites
export const preloadWarhorse = () => preloadModel('ghost');

// Scales the model to its real length, turns it to face +Z, sets it on the ground, and places the gun muzzles
// from the car's data (fractions of its box) so bullets leave from its own guns.
function buildModelCar(car) {
  const src = MODELS[car.id].scene, spec = car.model || {};
  const box = new THREE.Box3().setFromObject(src), size = box.getSize(new THREE.Vector3());
  const s = (spec.length || 5) / size.x;
  const model = src.clone(true);
  model.rotation.y = Math.PI / 2; // Meshy exports face -X
  model.scale.setScalar(s);
  model.position.set(-(box.min.z + box.max.z) / 2 * s, -box.min.y * s, -(box.min.x + box.max.x) / 2 * s); // centre it
  const g = new THREE.Group(); g.add(model);
  const W = size.z * s, H = size.y * s, L = size.x * s;
  const pt = ([x, y, z]) => new THREE.Vector3(x * W / 2, y * H, z * L / 2);
  return finish(g, [], {
    muzzles: (spec.muzzles || [[0, 0.95, 0.3]]).map(pt), rocketMuzzle: pt(spec.rocket || [0, 0.95, 0]),
    flame: new THREE.Vector3(0, H * 0.4, L / 2 + 0.3), dims: { W, H, L }, keep: true,
  });
}

export function buildCar(id) {
  const car = CARS.find((c) => c.id === id);
  if (car && modelReady(id)) return buildModelCar(car);
  return BUILDERS.rustbucket(); // procedural stand-in only if a model failed to load
}

// Blacken and dent a destroyed car.
export function wreck(group) {
  group.traverse((o) => {
    if (!o.isMesh) return;
    const ms = Array.isArray(o.material) ? o.material : [o.material];
    o.material = ms.map((mt) => {
      const c = mt.clone();
      if (c.color) c.color.multiplyScalar(0.18);
      if (c.emissive) c.emissive.setRGB(0, 0, 0);
      return c;
    });
    if (o.material.length === 1) o.material = o.material[0];
  });
  group.rotation.z = (Math.random() - 0.5) * 0.25;
}
