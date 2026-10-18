// Builds an arena from the environment kit: ground, sky, concrete barrier walls, the landmark building,
// scattered props with collision shapes, explosive barrels, storage tanks, and lighting.
import * as THREE from 'three';
import { quality } from './quality.js';
import { KIT, propInstances, propSize, building, buildingFootprint, barrelGeometry, containerGeometry, mapToRegion, panelCylinder, blockGeometry, ATLAS } from './kit.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const PS = 1.5;    // prop scale: kit props are true-to-life, game cars are a bit oversized
const BS = 1.7;    // building scale
const WS = 1.6;    // wall (jersey barrier) scale

function rng(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }

function dirtTexture(map, R) {
  const c = document.createElement('canvas'); c.width = c.height = 512;
  const g = c.getContext('2d');
  const base = new THREE.Color(map.ground), alt = new THREE.Color(map.groundAlt);
  g.fillStyle = `#${base.getHexString()}`; g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 220; i++) {
    const x = R() * 512, y = R() * 512, r = 8 + R() * 46;
    const grd = g.createRadialGradient(x, y, 0, x, y, r);
    grd.addColorStop(0, `#${alt.getHexString()}aa`); grd.addColorStop(1, `#${alt.getHexString()}00`);
    g.fillStyle = grd; g.fillRect(x - r, y - r, r * 2, r * 2);
  }
  for (let i = 0; i < 14000; i++) { const v = R() < 0.5 ? 0 : 255; g.fillStyle = `rgba(${v},${v},${v},${R() * 0.08})`; g.fillRect(R() * 512, R() * 512, 1 + R() * 2, 1 + R() * 2); }
  for (let i = 0; i < 260; i++) { g.fillStyle = `rgba(30,24,18,${0.2 + R() * 0.3})`; g.beginPath(); g.arc(R() * 512, R() * 512, 0.6 + R() * 2.2, 0, 7); g.fill(); } // pebbles
  for (let i = 0; i < 16; i++) { g.fillStyle = 'rgba(10,8,6,0.16)'; g.beginPath(); g.ellipse(R() * 512, R() * 512, 8 + R() * 30, 5 + R() * 18, R() * 3, 0, 7); g.fill(); }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}
function skyTexture(top, horizon) {
  const c = document.createElement('canvas'); c.width = 2; c.height = 256;
  const g = c.getContext('2d'), grd = g.createLinearGradient(0, 0, 0, 256);
  grd.addColorStop(0, `#${new THREE.Color(top).getHexString()}`); grd.addColorStop(0.62, `#${new THREE.Color(horizon).getHexString()}`); grd.addColorStop(1, `#${new THREE.Color(horizon).getHexString()}`);
  g.fillStyle = grd; g.fillRect(0, 0, 2, 256);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

// Big storage tank whose side samples the riveted steel panel of the atlas.
function tankGeometry(r, h) {
  const g = new THREE.CylinderGeometry(r, r, h, 24, 1, false);
  const uv = g.attributes.uv, u0 = 2 / 1024, u1 = 250 / 1024, v0 = 1 - 508 / 1024, v1 = 1 - 262 / 1024;
  const wraps = Math.max(1, Math.round((2 * Math.PI * r) / 6)), rows = Math.max(1, Math.round(h / 5));
  for (let i = 0; i < uv.count; i++) {
    const u = (uv.getX(i) * wraps) % 1, v = (uv.getY(i) * rows) % 1;
    uv.setXY(i, u0 + (uv.getX(i) === 1 ? 1 : u) * (u1 - u0), v0 + (uv.getY(i) === 1 ? 1 : v) * (v1 - v0));
  }
  g.translate(0, h / 2, 0);
  return g;
}

export function buildArena(scene, map) {
  const R = rng(map.id.length * 7919 + map.size * 13);
  const half = map.size / 2;
  const obstacles = []; // { kind:'box'|'circle', x, z, hw, hd | r, h, mesh, barrel?, hp? }
  const grp = new THREE.Group(); scene.add(grp);

  scene.background = skyTexture(map.skyTop, map.fog);
  scene.fog = new THREE.Fog(map.fog, map.size * 0.4, map.size * 1.45);

  const hemi = new THREE.HemisphereLight(map.skyLight || 0xfff2e0, map.ground, 1.35); grp.add(hemi);
  const sun = new THREE.DirectionalLight(map.light, 2.8);
  sun.position.set(45, 75, 30); sun.castShadow = true;
  const sc = sun.shadow.camera; sc.left = -half - 12; sc.right = half + 12; sc.top = half + 12; sc.bottom = -half - 12; sc.far = 220;
  sun.shadow.mapSize.set(quality.tier.shadow, quality.tier.shadow); sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.5;
  grp.add(sun, sun.target);

  // ground: dirt everywhere, concrete slabs where the map asks for it
  const dirt = dirtTexture(map, R); dirt.repeat.set(map.size * 3 / 22, map.size * 3 / 22);
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(map.size * 3, map.size * 3), new THREE.MeshStandardMaterial({ map: dirt, roughness: 1, metalness: 0 }));
  ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; grp.add(ground);
  if (map.concrete) {
    const tex = new THREE.TextureLoader().load(new URL('../assets/kit/ground_concrete.jpg', import.meta.url).href);
    tex.colorSpace = THREE.SRGBColorSpace; tex.wrapS = tex.wrapT = THREE.MirroredRepeatWrapping; tex.anisotropy = 4;
    const size = map.size * map.concrete;
    tex.repeat.set(size / 15, size / 15);
    const slab = new THREE.Mesh(new THREE.PlaneGeometry(size, size), new THREE.MeshStandardMaterial({ map: tex, color: 0xb8b2a8, roughness: 0.95, metalness: 0, polygonOffset: true, polygonOffsetFactor: -1 }));
    slab.rotation.x = -Math.PI / 2; slab.position.y = 0.01; slab.receiveShadow = true; grp.add(slab);
  }

  // ---------- helpers ----------
  const instances = {}; // prop name -> [{x,z,ry,s}]
  const lowTier = quality.tier.particles < 0.6;
  const addProp = (name, x, z, ry = 0, s = 1, collide = true) => {
    if (!collide && lowTier) return; // low quality: skip pure decoration
    (instances[name] = instances[name] || []).push({ x, z, ry, s });
    if (!collide) return;
    const sz = propSize(name, PS * s), hw = sz.x / 2 * 0.94, hd = sz.z / 2 * 0.94;
    if (Math.abs(hw - hd) < 0.3 * Math.max(hw, hd)) obstacles.push({ kind: 'circle', x, z, r: (hw + hd) / 2, h: sz.y });
    else obstacles.push({ kind: 'box', x, z, hw, hd, rot: ry, h: sz.y });
  };
  const bGeo = barrelGeometry();
  const barrels = []; // all barrels draw as one instanced mesh; a destroyed barrel collapses its instance to zero size
  const barrel = (x, z) => {
    const o = { kind: 'circle', x, z, r: 0.85, h: 1.8, barrel: true, hp: 15, index: barrels.length };
    barrels.push({ x, z, ry: R() * 6.28 }); obstacles.push(o);
  };
  const barrelMat = KIT.material.clone(); barrelMat.side = THREE.FrontSide; barrelMat.color = new THREE.Color(1.15, 0.9, 0.85);
  const tankMat = KIT.material.clone(); tankMat.side = THREE.FrontSide; tankMat.alphaMap = null; tankMat.alphaTest = 0;
  const tank = (x, z, r, h) => {
    const m = new THREE.Mesh(panelCylinder(r, h, ATLAS.plate, 6, 5), tankMat); m.position.set(x, 0, z); m.castShadow = true; m.receiveShadow = true; grp.add(m);
    const lid = new THREE.Mesh(new THREE.ConeGeometry(r * 1.02, r * 0.35, 24), tankMat); lid.position.set(x, h + r * 0.175, z); lid.castShadow = true; grp.add(lid);
    const stripe = new THREE.Mesh(new THREE.CylinderGeometry(r + 0.04, r + 0.04, 0.6, 24, 1, true), new THREE.MeshStandardMaterial({ color: 0xc9951f, roughness: 0.7 }));
    stripe.position.set(x, h * 0.72, z); grp.add(stripe);
    obstacles.push({ kind: 'circle', x, z, r, h: h + r * 0.35, mesh: m });
  };
  const contMat = KIT.material.clone(); contMat.side = THREE.FrontSide; contMat.alphaMap = null; contMat.alphaTest = 0;
  const tints = [0xffffff, 0xc8d8e8, 0xf0c8b8, 0xd8e0c0, 0xe8d8b0];
  // shipping container, optionally a second one stacked on top
  const container = (x, z, ry, stack = false) => {
    const variant = R() < 0.5 ? 1 : 0, geo = containerGeometry(7.8, 3.3, 3.1, variant);
    const mk = (y, ryy) => { const mm = contMat.clone(); mm.color = new THREE.Color(tints[Math.floor(R() * tints.length)]); const m = new THREE.Mesh(geo, mm); m.position.set(x, y, z); m.rotation.y = ryy; m.castShadow = true; m.receiveShadow = true; grp.add(m); return m; };
    mk(0, ry); if (stack) mk(3.3, ry + (R() - 0.5) * 0.25);
    obstacles.push({ kind: 'box', x, z, hw: 3.9, hd: 1.55, rot: ry, h: stack ? 6.6 : 3.3 });
  };
  const landmark = (x, z, ry) => {
    const b = building(BS); b.position.set(x, 0, z); b.rotation.y = ry; grp.add(b);
    const f = buildingFootprint(BS);
    const c = Math.cos(ry), s = Math.sin(ry), cx = (f.minX + f.maxX) / 2, cz = (f.minZ + f.maxZ) / 2;
    const wx = cx * c + cz * s, wz = -cx * s + cz * c;
    obstacles.push({ kind: 'box', x: x + wx, z: z + wz, hw: (f.maxX - f.minX) / 2, hd: (f.maxZ - f.minZ) / 2, rot: ry, h: f.h, building: true });
    return b;
  };

  // ---------- boundary: concrete jersey barriers on all four sides ----------
  const bs = propSize('barrier', WS), wall = [];
  const n = Math.ceil(map.size / (bs.x * 0.98));
  for (let i = 0; i < n; i++) {
    const p = -half + (i + 0.5) * (map.size / n);
    for (const [x, z, ry] of [[p, -half, 0], [p, half, Math.PI], [-half, p, Math.PI / 2], [half, p, -Math.PI / 2]]) wall.push({ x, z, ry: ry + (R() - 0.5) * 0.06, s: 1 });
  }
  grp.add(propInstances('barrier', wall, WS));
  // outer skyline: a few far buildings in the haze (low detail)
  for (let i = 0; i < (lowTier ? 0 : quality.tier.particles < 0.9 ? 2 : 4); i++) {
    const a = (i / 4) * Math.PI * 2 + 0.6 + R() * 0.5, d = half + 58 + R() * 14;
    const b = building(BS * 1.2); b.position.set(Math.cos(a) * d, 0, Math.sin(a) * d); b.rotation.y = R() * 6.28; b.levels[0].distance = 1e6; b.levels.reverse();
    b.levels[0].distance = 0; grp.add(b);
  }

  // ---------- industrial district beyond the walls ----------
  // Warehouses, chimneys, tank farms and container stacks fill the horizon so the arena never sits in an empty field.
  // Everything is merged into one mesh per material: two draw calls for the whole district.
  const stacks = [];
  {
    const ring = [], full = !lowTier, place2 = (geo, x, z, ry, y = 0) => { const g = geo.clone(); g.rotateY(ry); g.translate(x, y, z); ring.push(g); };
    const cone = (r, h) => { const g = new THREE.ConeGeometry(r, h, 16, 1, true).toNonIndexed(); mapToRegion(g, ATLAS.greyPlate, 3, 1); g.deleteAttribute('normal'); g.computeVertexNormals(); return g; };
    const taken = [];
    const free = (x, z, r) => taken.every((t) => Math.hypot(t[0] - x, t[1] - z) > t[2] + r + 2);
    const warehouse = (x, z, ry) => {
      const w = 16 + R() * 12, d = 11 + R() * 6, h = 7 + R() * 5;
      place2(blockGeometry(w, h, d, R() < 0.5 ? ATLAS.corrugated : ATLAS.corrugated2, ATLAS.greyPlate, ATLAS.shutter, 4.2), x, z, ry);
      place2(blockGeometry(w * 0.96, 1.2, d * 0.55, ATLAS.greyPlate, ATLAS.plate, null, 4), x, z, ry, h); // roof monitor
      if (full && R() < 0.65) { // brick-red chimney beside it
        const cr = 1.1 + R() * 0.5, ch = 18 + R() * 12, ox = (R() < 0.5 ? -1 : 1) * (w / 2 + cr + 0.6);
        const cx = x + Math.cos(ry) * ox, cz = z - Math.sin(ry) * ox;
        place2(panelCylinder(cr, ch, ATLAS.concrete, 3, 4, 2), cx, cz, 0);
        place2(panelCylinder(cr * 1.15, 1, ATLAS.rustPanel, 3, 1, 2), cx, cz, 0, ch - 1.4);
        stacks.push({ x: cx, y: ch, z: cz });
      }
      return Math.hypot(w, d) / 2;
    };
    const tankFarm = (x, z) => {
      const k = 2 + Math.floor(R() * 2);
      for (let i = 0; i < k; i++) {
        const r = 3 + R() * 2.2, h = 7 + R() * 6, a = (i / k) * 6.28 + R(), dd = k > 1 ? r + 1.5 : 0;
        const tx = x + Math.cos(a) * dd, tz = z + Math.sin(a) * dd;
        place2(panelCylinder(r, h, ATLAS.plate, 6, 5, 2), tx, tz, 0); place2(cone(r * 1.02, r * 0.35), tx, tz, 0, h + r * 0.175);
      }
      return 9;
    };
    const stack = (x, z, ry) => {
      const k = 2 + Math.floor(R() * 3);
      for (let i = 0; i < k; i++) { const lv = i < 2 ? 0 : 1, off = (i % 2) * 3.2 - 1.6; place2(containerGeometry(7.8, 3.3, 3.1, (i + lv) % 2), x + Math.sin(ry) * off, z + Math.cos(ry) * off, ry, lv * 3.3); }
      return 6;
    };
    const near = half + 10, far = half + (full ? 44 : 26), step = full ? 15 : 22;
    for (let side = 0; side < 4; side++) {
      for (let along = -far; along <= far; along += step) {
        for (let depth = near + 7; depth < far; depth += step) {
          const a = along + (R() - 0.5) * 6, dep = depth + (R() - 0.5) * 5;
          const [x, z] = side === 0 ? [a, -dep] : side === 1 ? [a, dep] : side === 2 ? [-dep, a] : [dep, a];
          if (R() < 0.18) continue;
          const face = Math.atan2(-x, -z), pick = R();
          const r = pick < 0.55 ? 12 : pick < 0.78 ? 9 : 6;
          if (!free(x, z, r)) continue;
          const used = pick < 0.55 ? warehouse(x, z, face + (R() < 0.5 ? 0 : Math.PI / 2)) : pick < 0.78 ? tankFarm(x, z) : stack(x, z, face + Math.PI / 2);
          taken.push([x, z, used]);
        }
      }
    }
    if (ring.length) {
      const mat = KIT.material.clone(); mat.side = THREE.DoubleSide; mat.alphaMap = null; mat.alphaTest = 0; mat.color = new THREE.Color(1.3, 1.22, 1.12);
      const district = new THREE.Mesh(mergeGeometries(ring, false), mat);
      district.castShadow = false; district.receiveShadow = false; district.matrixAutoUpdate = false; grp.add(district);
      ring.forEach((g) => g.dispose());
    }
  }

  // ---------- placement ----------
  const spawnR = half * 0.72;
  const clear = (x, z, r) => {
    if (Math.abs(x) > half - r - 3 || Math.abs(z) > half - r - 3) return false;
    for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2 + Math.PI / 2; if (Math.hypot(x - Math.cos(a) * spawnR, z - Math.sin(a) * spawnR) < r + 7) return false; }
    if (Math.hypot(x, z) < r + 5) return false;
    return obstacles.every((o) => Math.hypot(o.x - x, o.z - z) > r + (o.r || Math.hypot(o.hw, o.hd)) + 4.5);
  };
  const place = (count, r, fn) => { let k = 0, tries = 0; while (k < count && tries++ < 500) { const x = (R() * 2 - 1) * half, z = (R() * 2 - 1) * half; if (clear(x, z, r)) { fn(x, z); k++; } } };
  const quarter = () => Math.floor(R() * 4) * (Math.PI / 2) + (R() - 0.5) * 0.25;
  // a small cluster: one main prop with clutter around it
  const cluster = (x, z, main, extras) => {
    const ry = quarter(); addProp(main, x, z, ry);
    const ms = propSize(main, PS);
    for (const e of extras) { const a = R() * 6.28, d = Math.max(ms.x, ms.z) / 2 + 1.1 + R() * 0.8; addProp(e, x + Math.cos(a) * d, z + Math.sin(a) * d, quarter(), 1, false); }
  };

  const L = map.layout;
  if (L === 'scrapyard') {
    landmark(-half * 0.42, -half * 0.05, Math.PI / 2);
    place(7, 5, (x, z) => container(x, z, quarter(), R() < 0.4));
    place(5, 3, (x, z) => cluster(x, z, 'dumpster', ['boxes', 'jugCrate']));
    place(4, 3, (x, z) => cluster(x, z, 'tarpDrums', ['crates']));
    place(3, 3, (x, z) => cluster(x, z, 'cage', ['boxes']));
    place(4, 2.5, (x, z) => cluster(x, z, 'cart', ['jugCrate']));
    place(3, 2.5, (x, z) => addProp('shelf', x, z, quarter()));
    place(4, 2, (x, z) => addProp('drums', x, z, quarter()));
    place(6, 1.5, (x, z) => { barrel(x, z); if (R() < 0.6) barrel(x + 1.8, z + 0.5); });
    place(3, 1, (x, z) => addProp('pole', x, z, R() * 6.28));
  } else if (L === 'refinery') {
    landmark(half * 0.45, -half * 0.42, 0);
    place(4, 7, (x, z) => tank(x, z, 4 + R() * 2.2, 8 + R() * 5));
    place(4, 5, (x, z) => container(x, z, quarter(), R() < 0.3));
    place(4, 3, (x, z) => cluster(x, z, 'waterTank', ['cylinder', 'cylinder']));
    place(3, 3, (x, z) => cluster(x, z, 'tankStand', ['compressor']));
    place(4, 2.5, (x, z) => cluster(x, z, 'gasCart', ['cylinders']));
    place(3, 2, (x, z) => addProp('cylCart', x, z, quarter()));
    place(9, 2.5, (x, z) => { barrel(x, z); barrel(x + 1.75, z); barrel(x + 0.88, z + 1.5); });
    place(3, 1, (x, z) => addProp('pole', x, z, R() * 6.28));
  } else if (L === 'dustbowl') {
    const rockMat = tankMat.clone(); rockMat.color = new THREE.Color(1.35, 1.08, 0.78);
    place(11, 4, (x, z) => {
      const r = 2 + R() * 2.4, h = 5 + R() * 9;
      const geo = new THREE.CylinderGeometry(r * 0.62, r, h, 7, 3); const pos = geo.attributes.position;
      for (let i = 0; i < pos.count; i++) { const k = 1 + (R() - 0.5) * 0.25; pos.setX(i, pos.getX(i) * k); pos.setZ(i, pos.getZ(i) * k); }
      mapToRegion(geo, ATLAS.concrete, 1, 1); geo.computeVertexNormals(); geo.translate(0, h / 2, 0);
      const m = new THREE.Mesh(geo, rockMat); m.position.set(x, 0, z); m.rotation.y = R() * 6; m.castShadow = true; m.receiveShadow = true; grp.add(m);
      obstacles.push({ kind: 'circle', x, z, r, h, mesh: m });
    });
    landmark(half * 0.5, half * 0.48, -Math.PI * 0.75);
    place(5, 5, (x, z) => { const along = R() < 0.5, k = 3 + Math.floor(R() * 3), s = propSize('barrier', WS).x;
      for (let i = 0; i < k; i++) { const bx = x + (along ? (i - k / 2) * s : 0), bz = z + (along ? 0 : (i - k / 2) * s); addProp('barrier', bx, bz, (along ? 0 : Math.PI / 2) + (R() - 0.5) * 0.15, WS / PS); } });
    place(3, 2.5, (x, z) => cluster(x, z, 'tarpDrums', ['drums']));
    place(5, 1.5, (x, z) => { barrel(x, z); barrel(x + 1.8, z + 0.4); });
    place(3, 5, (x, z) => container(x, z, quarter() + 0.3, false));
  } else if (L === 'shanty') {
    landmark(0, -half * 0.36, 0); landmark(-half * 0.38, half * 0.3, Math.PI * 0.66); landmark(half * 0.4, half * 0.28, -Math.PI * 0.66);
    place(6, 5, (x, z) => container(x, z, quarter(), R() < 0.5));
    place(5, 3, (x, z) => cluster(x, z, 'dumpster', ['crates', 'boxes']));
    place(4, 3, (x, z) => cluster(x, z, 'cage', ['jugCrate']));
    place(4, 2.5, (x, z) => cluster(x, z, 'tarpDrums', ['boxes']));
    place(3, 2, (x, z) => addProp('shelf', x, z, quarter()));
    place(4, 1, (x, z) => addProp('pole', x, z, R() * 6.28));
    place(6, 1.5, (x, z) => { barrel(x, z); if (R() < 0.5) barrel(x + 1.8, z); });
  } else { // outpost: a fortified building in the middle, ring of barriers with gaps
    landmark(0, 0, R() * 6.28);
    const ringR = 20, s = propSize('barrier', WS).x;
    const count = Math.floor((2 * Math.PI * ringR) / s);
    for (let i = 0; i < count; i++) {
      if (i % 7 === 0 || i % 7 === 1) continue; // gates
      const a = (i / count) * Math.PI * 2;
      addProp('barrier', Math.cos(a) * ringR, Math.sin(a) * ringR, -a + Math.PI / 2, WS / PS);
    }
    const inner = (a, d, name) => addProp(name, Math.cos(a) * d, Math.sin(a) * d, a);
    inner(0.4, 13, 'tankStand'); inner(2.2, 13.5, 'gasCart'); inner(3.6, 13, 'waterTank'); inner(5.1, 13.5, 'cage');
    place(5, 5, (x, z) => container(x, z, quarter(), R() < 0.35));
    place(4, 3, (x, z) => cluster(x, z, 'dumpster', ['boxes']));
    place(3, 2.5, (x, z) => cluster(x, z, 'cart', ['cylinders']));
    place(7, 1.5, (x, z) => { barrel(x, z); if (R() < 0.6) barrel(x + 1.8, z + 0.4); });
    place(4, 1, (x, z) => addProp('pole', x, z, R() * 6.28));
  }

  const small = quality.tier.particles < 0.9; // medium/low: small props skip the shadow pass
  for (const [name, list] of Object.entries(instances)) { const im = propInstances(name, list, PS); if (small && name !== 'barrier') im.castShadow = false; grp.add(im); }
  if (barrels.length) {
    const im = new THREE.InstancedMesh(bGeo, barrelMat, barrels.length), m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0), one = new THREE.Vector3(1, 1, 1);
    barrels.forEach((b, i) => { q.setFromAxisAngle(up, b.ry); m4.compose(new THREE.Vector3(b.x, 0, b.z), q, one); im.setMatrixAt(i, m4); });
    im.castShadow = !small; im.receiveShadow = true; im.computeBoundingSphere(); grp.add(im);
    const zero = new THREE.Matrix4().makeScale(0, 0, 0);
    for (const o of obstacles) if (o.barrel) o.hide = () => { im.setMatrixAt(o.index, zero); im.instanceMatrix.needsUpdate = true; };
  }

  const spawns = [];
  for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2 + Math.PI / 2; spawns.push({ x: Math.cos(a) * spawnR, z: Math.sin(a) * spawnR, heading: Math.atan2(-Math.cos(a), -Math.sin(a)) }); }

  const pickupSpots = [];
  for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2 + 0.4, d = half * (i % 2 ? 0.42 : 0.25); pickupSpots.push({ x: Math.cos(a) * d, z: Math.sin(a) * d, type: i % 2 ? 'ammo' : 'health' }); }

  return { group: grp, obstacles, spawns, pickupSpots, half, sun, stacks };
}
