// Real-world environment kit (post-apocalypse kitbash by Oleg Ushenok, free sample, Fab Standard license).
// All pieces share one texture atlas and one material, so a whole arena draws with very few state changes.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { quality } from './quality.js';

const BASE = new URL('../assets/kit/', import.meta.url).href;
let ready = null;
const geos = {};      // name -> BufferGeometry (meters, origin at ground center)
export const KIT = { meta: null, material: null, barrelMaterial: null, loaded: false };

function loadScript(src) {
  return new Promise((res, rej) => { const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
}
function b64ToBuffer(b64) { const bin = atob(b64); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u.buffer; }

export function loadKit() {
  if (ready) return ready;
  ready = (async () => {
    if (!window.__KIT) await loadScript(BASE + 'kit_models.js');
    const { meta, files } = window.__KIT;
    KIT.meta = meta;
    const loader = new GLTFLoader();
    await Promise.all(Object.entries(files).map(([name, b64]) => new Promise((res, rej) => {
      loader.parse(b64ToBuffer(b64), '', (gl) => {
        let g = null; gl.scene.traverse((o) => { if (o.isMesh && !g) g = o.geometry; });
        geos[name.replace('.glb', '')] = g; res();
      }, rej);
    })));
    delete window.__KIT; // free the base64 strings
    const hi = quality.tier.shadow >= 2048;
    const tl = new THREE.TextureLoader();
    const tex = (f, srgb) => new Promise((res) => tl.load(BASE + f, (t) => { if (srgb) t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; res(t); }, undefined, () => res(null)));
    const [map, normal, orm, alpha] = await Promise.all([
      tex(`kit_color_${hi ? 2048 : 1024}.jpg`, true), tex(`kit_normal_${hi ? 2048 : 1024}.jpg`), tex(`kit_orm_${hi ? 2048 : 1024}.jpg`), tex('kit_opacity_1024.png'),
    ]);
    KIT.material = new THREE.MeshStandardMaterial({
      map, normalMap: normal, roughnessMap: orm, metalnessMap: orm, alphaMap: alpha, alphaTest: 0.5,
      side: THREE.DoubleSide, roughness: 1, metalness: 1, normalScale: new THREE.Vector2(1, 1),
    });
    KIT.barrelMaterial = KIT.material;
    KIT.loaded = true;
  })();
  return ready;
}

// Prop names available: dumpster, barrier, gasCart, cylinders, cylCart, compressor, cylinder, cart, tarpDrums,
// tankStand, cage, pole, crates, drums, boxes, waterTank, jugCrate, shelf
export function propSize(name, scale = 1) { const s = KIT.meta.props[name].size; return { x: s[0] * scale, y: s[1] * scale, z: s[2] * scale }; }
export function propMesh(name, scale = 1) {
  const m = new THREE.Mesh(geos['prop_' + name], KIT.material);
  m.scale.setScalar(scale); m.castShadow = true; m.receiveShadow = true;
  return m;
}
// Instanced copies of one prop: list of {x, z, ry, s}
export function propInstances(name, list, baseScale = 1) {
  const im = new THREE.InstancedMesh(geos['prop_' + name], KIT.material, list.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0);
  list.forEach((p, i) => { q.setFromAxisAngle(up, p.ry || 0); const s = (p.s || 1) * baseScale; m4.compose(new THREE.Vector3(p.x, p.y || 0, p.z), q, new THREE.Vector3(s, s, s)); im.setMatrixAt(i, m4); });
  im.castShadow = true; im.receiveShadow = true;
  im.computeBoundingSphere();
  return im;
}
// The landmark building with two levels of detail.
export function building(scale = 1.6) {
  const lod = new THREE.LOD();
  const near = new THREE.Mesh(geos.building_lod0, KIT.material), far = new THREE.Mesh(geos.building_lod1, KIT.material);
  for (const m of [near, far]) { m.scale.setScalar(scale); m.castShadow = true; m.receiveShadow = true; }
  lod.addLevel(near, 0); lod.addLevel(far, 46);
  return lod;
}
export function buildingFootprint(scale = 1.6) {
  const f = KIT.meta.building.footprint;
  return { minX: f.min[0] * scale, maxX: f.max[0] * scale, minZ: f.min[2] * scale, maxZ: f.max[2] * scale, h: KIT.meta.building.lod0.size[1] * scale };
}

// Explosive fuel barrel: a low-poly cylinder whose side samples the red painted-metal panel of the atlas.
let barrelGeo = null;
export function barrelGeometry() {
  if (barrelGeo) return barrelGeo;
  const seg = 14, r = 0.75, h = 1.8;
  const side = new THREE.CylinderGeometry(r, r, h, seg, 1, true);
  const u0 = 568 / 1024, u1 = 662 / 1024, v0 = 1 - 1018 / 1024, v1 = 1 - 868 / 1024; // red panel (image y down → v up)
  const uv = side.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, u0 + uv.getX(i) * (u1 - u0), v0 + uv.getY(i) * (v1 - v0));
  const cap = new THREE.CircleGeometry(r, seg); cap.rotateX(-Math.PI / 2); cap.translate(0, h / 2, 0);
  const cu = cap.attributes.uv, c0 = 200 / 1024, c1 = 300 / 1024, cv0 = 1 - 1015 / 1024, cv1 = 1 - 915 / 1024; // grey plate
  for (let i = 0; i < cu.count; i++) cu.setXY(i, c0 + cu.getX(i) * (c1 - c0), cv0 + cu.getY(i) * (cv1 - cv0));
  const ring = (y) => { const t = new THREE.TorusGeometry(r + 0.02, 0.05, 4, seg); t.rotateX(Math.PI / 2); t.translate(0, y, 0); const tu = t.attributes.uv; for (let i = 0; i < tu.count; i++) tu.setXY(i, c0 + tu.getX(i) * 0.05, cv0 + tu.getY(i) * 0.05); return t; };
  const parts = [side, cap, ring(-0.45), ring(0.45)].map((g) => g.toNonIndexed());
  for (const g of parts) for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
  const merged = mergeSimple(parts); merged.translate(0, h / 2, 0);
  barrelGeo = merged;
  return barrelGeo;
}
function mergeSimple(list) {
  let n = 0; for (const g of list) n += g.attributes.position.count;
  const out = new THREE.BufferGeometry(), P = new Float32Array(n * 3), N = new Float32Array(n * 3), U = new Float32Array(n * 2);
  let o = 0;
  for (const g of list) { P.set(g.attributes.position.array, o * 3); N.set(g.attributes.normal.array, o * 3); U.set(g.attributes.uv.array, o * 2); o += g.attributes.position.count; }
  out.setAttribute('position', new THREE.BufferAttribute(P, 3)); out.setAttribute('normal', new THREE.BufferAttribute(N, 3)); out.setAttribute('uv', new THREE.BufferAttribute(U, 2));
  return out;
}

// ---------- atlas-textured procedural pieces ----------
// Atlas regions in 1024-px image coordinates (x0, y0, x1, y1); converted to UV with v flipped.
export const ATLAS = {
  corrugated: [252, 2, 498, 246], corrugated2: [504, 2, 752, 246], shutter: [4, 4, 244, 248], doors: [760, 30, 1020, 250],
  plate: [2, 262, 250, 508], concrete: [504, 262, 752, 508], rustPanel: [204, 512, 312, 618], greyPlate: [196, 784, 308, 1020],
};
function regionUV(r) { return [r[0] / 1024, 1 - r[3] / 1024, r[2] / 1024, 1 - r[1] / 1024]; }
// A quad grid on a box face, every panel showing the whole atlas region (so textures tile without stretching).
function facePanels(out, origin, uDir, vDir, normal, w, h, panelW, panelH, region) {
  const [u0, v0, u1, v1] = regionUV(region), nu = Math.max(1, Math.round(w / panelW)), nv = Math.max(1, Math.round(h / panelH));
  const pw = w / nu, ph = h / nv;
  for (let i = 0; i < nu; i++) for (let j = 0; j < nv; j++) {
    const p = (a, b) => [origin[0] + uDir[0] * a + vDir[0] * b, origin[1] + uDir[1] * a + vDir[1] * b, origin[2] + uDir[2] * a + vDir[2] * b];
    const a0 = i * pw, a1 = a0 + pw, b0 = j * ph, b1 = b0 + ph;
    const q = [p(a0, b0), p(a1, b0), p(a1, b1), p(a0, b1)], t = [[u0, v0], [u1, v0], [u1, v1], [u0, v1]];
    for (const k of [0, 1, 2, 0, 2, 3]) { out.pos.push(...q[k]); out.nor.push(...normal); out.uv.push(...t[k]); }
  }
}
function finishGeo(out) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(out.pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(out.nor, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(out.uv, 2));
  return g;
}
// Shipping container, origin at ground center, long axis along X.
const containerCache = {};
export function containerGeometry(len = 7.8, h = 3.3, w = 3.1, variant = 0) {
  const key = `${len}|${h}|${w}|${variant}`;
  if (containerCache[key]) return containerCache[key];
  const side = variant ? ATLAS.corrugated2 : ATLAS.corrugated, out = { pos: [], nor: [], uv: [] };
  const X = len / 2, Z = w / 2, P = 2.6;
  facePanels(out, [-X, 0, Z], [1, 0, 0], [0, 1, 0], [0, 0, 1], len, h, P, h, side);    // front long side
  facePanels(out, [X, 0, -Z], [-1, 0, 0], [0, 1, 0], [0, 0, -1], len, h, P, h, side);  // back long side
  facePanels(out, [X, 0, Z], [0, 0, -1], [0, 1, 0], [1, 0, 0], w, h, w, h, ATLAS.doors); // door end
  facePanels(out, [-X, 0, -Z], [0, 0, 1], [0, 1, 0], [-1, 0, 0], w, h, w, h, side);      // closed end
  facePanels(out, [-X, h, Z], [1, 0, 0], [0, 0, -1], [0, 1, 0], len, w, P, w, ATLAS.plate); // roof
  return (containerCache[key] = finishGeo(out));
}
// Plain building block (no floor) with panelled walls and a roof, origin at ground centre.
// Each side can take its own atlas region; panel sizes keep the texture at a believable scale.
export function blockGeometry(w, h, d, walls = ATLAS.corrugated, roof = ATLAS.greyPlate, front = null, panel = 4) {
  const out = { pos: [], nor: [], uv: [] }, X = w / 2, Z = d / 2;
  facePanels(out, [-X, 0, Z], [1, 0, 0], [0, 1, 0], [0, 0, 1], w, h, panel, panel, front || walls);
  facePanels(out, [X, 0, -Z], [-1, 0, 0], [0, 1, 0], [0, 0, -1], w, h, panel, panel, walls);
  facePanels(out, [X, 0, Z], [0, 0, -1], [0, 1, 0], [1, 0, 0], d, h, panel, panel, walls);
  facePanels(out, [-X, 0, -Z], [0, 0, 1], [0, 1, 0], [-1, 0, 0], d, h, panel, panel, walls);
  facePanels(out, [-X, h, Z], [1, 0, 0], [0, 0, -1], [0, 1, 0], w, d, panel * 1.5, panel * 1.5, roof);
  return finishGeo(out);
}
// Remaps an existing geometry's 0..1 UVs onto one atlas region, repeating `rep` times (by duplicating faces is not needed: we clamp to the region).
export function mapToRegion(geo, region, repU = 1, repV = 1) {
  const [u0, v0, u1, v1] = regionUV(region), uv = geo.attributes.uv;
  for (let i = 0; i < uv.count; i++) {
    let u = (uv.getX(i) * repU) % 1, v = (uv.getY(i) * repV) % 1;
    if (uv.getX(i) * repU >= repU - 1e-6 && repU >= 1) u = 1; if (uv.getY(i) * repV >= repV - 1e-6 && repV >= 1) v = 1;
    uv.setXY(i, u0 + u * (u1 - u0), v0 + v * (v1 - v0));
  }
  return geo;
}

// Cylinder wall made of separate panels, each showing the full atlas region (no smeared seams).
export function panelCylinder(r, h, region, panelW = 6, panelH = 5, segsPerPanel = 4) {
  const [u0, v0, u1, v1] = regionUV(region), out = { pos: [], nor: [], uv: [] };
  const panels = Math.max(3, Math.round((2 * Math.PI * r) / panelW)), rows = Math.max(1, Math.round(h / panelH)), segs = panels * segsPerPanel, rh = h / rows;
  for (let i = 0; i < segs; i++) {
    const a0 = (i / segs) * Math.PI * 2, a1 = ((i + 1) / segs) * Math.PI * 2, k = i % segsPerPanel;
    const ua = u0 + (k / segsPerPanel) * (u1 - u0), ub = u0 + ((k + 1) / segsPerPanel) * (u1 - u0);
    for (let j = 0; j < rows; j++) {
      const y0 = j * rh, y1 = y0 + rh;
      const P = (a, y) => [Math.sin(a) * r, y, Math.cos(a) * r], N = (a) => [Math.sin(a), 0, Math.cos(a)];
      const q = [[P(a0, y0), N(a0), [ua, v0]], [P(a1, y0), N(a1), [ub, v0]], [P(a1, y1), N(a1), [ub, v1]], [P(a0, y1), N(a0), [ua, v1]]];
      for (const idx of [0, 1, 2, 0, 2, 3]) { out.pos.push(...q[idx][0]); out.nor.push(...q[idx][1]); out.uv.push(...q[idx][2]); }
    }
  }
  return finishGeo(out);
}
