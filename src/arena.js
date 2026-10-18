// Builds an arena: ground, boundary walls, obstacles (with collision shapes), barrels, backdrop and lighting.
import * as THREE from 'three';
import { quality } from './quality.js';

function rng(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }

function groundTexture(map) {
  const c = document.createElement('canvas'); c.width = c.height = 512;
  const g = c.getContext('2d');
  const base = new THREE.Color(map.ground), alt = new THREE.Color(map.groundAlt);
  g.fillStyle = `#${base.getHexString()}`; g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 180; i++) {
    const x = Math.random() * 512, y = Math.random() * 512, r = 10 + Math.random() * 50;
    const grd = g.createRadialGradient(x, y, 0, x, y, r);
    grd.addColorStop(0, `#${alt.getHexString()}aa`); grd.addColorStop(1, `#${alt.getHexString()}00`);
    g.fillStyle = grd; g.fillRect(x - r, y - r, r * 2, r * 2);
  }
  for (let i = 0; i < 9000; i++) {
    const v = Math.random() < 0.5 ? 0 : 255;
    g.fillStyle = `rgba(${v},${v},${v},${Math.random() * 0.07})`;
    g.fillRect(Math.random() * 512, Math.random() * 512, 2, 2);
  }
  if (map.id === 'refinery') { // concrete slab seams
    g.strokeStyle = 'rgba(20,20,20,0.35)'; g.lineWidth = 2;
    for (let i = 0; i <= 512; i += 128) { g.beginPath(); g.moveTo(i, 0); g.lineTo(i, 512); g.moveTo(0, i); g.lineTo(512, i); g.stroke(); }
  }
  for (let i = 0; i < 14; i++) { // oil stains and tire marks
    g.fillStyle = 'rgba(10,8,6,0.18)'; g.beginPath();
    g.ellipse(Math.random() * 512, Math.random() * 512, 8 + Math.random() * 30, 5 + Math.random() * 18, Math.random() * 3, 0, 7); g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(map.size / 24, map.size / 24);
  t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}

export function buildArena(scene, map) {
  const R = rng(map.id.length * 7919 + map.size);
  const half = map.size / 2;
  const obstacles = []; // { kind:'box'|'circle', x, z, hw, hd | r, h, mesh, barrel?, hp? }
  const grp = new THREE.Group(); scene.add(grp);

  scene.background = new THREE.Color(map.sky);
  scene.fog = new THREE.Fog(map.fog, map.size * 0.45, map.size * 1.5);

  const hemi = new THREE.HemisphereLight(0xfff2e0, map.ground, 1.5); grp.add(hemi);
  const sun = new THREE.DirectionalLight(map.light, 2.6);
  sun.position.set(40, 70, 25); sun.castShadow = true;
  const sc = sun.shadow.camera; sc.left = -half - 10; sc.right = half + 10; sc.top = half + 10; sc.bottom = -half - 10; sc.far = 200;
  sun.shadow.mapSize.set(quality.tier.shadow, quality.tier.shadow); sun.shadow.bias = -0.0008; sun.shadow.normalBias = 0.6;
  grp.add(sun, sun.target);

  const ground = new THREE.Mesh(new THREE.PlaneGeometry(map.size * 3, map.size * 3), new THREE.MeshStandardMaterial({ map: groundTexture(map), roughness: 1, metalness: 0 }));
  ground.material.map.repeat.set(map.size * 3 / 24, map.size * 3 / 24);
  ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; grp.add(ground);

  const mat = (color, o = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.85, metalness: 0.2, flatShading: true, ...o });
  const M = {
    concrete: mat(0x8a877f), darkConcrete: mat(0x5d5a54), rust: mat(0x6e3a1e, { metalness: 0.4 }), steel: mat(0x5c6066, { metalness: 0.6, roughness: 0.5 }),
    rock: mat(map.id === 'dustbowl' ? 0x9a7650 : 0x6b625a), tire: mat(0x1a1a1a), hazard: mat(0xd9a521),
    barrel: mat(0xb8321e, { metalness: 0.5, roughness: 0.5 }), barrelBand: mat(0xe0b42a),
    containers: [mat(0x2f5b6e), mat(0x7a2e22), mat(0x4f6b34), mat(0x8a6a2a)],
  };
  const mesh = (geo, m, x, y, z, ry = 0) => { const o = new THREE.Mesh(geo, m); o.position.set(x, y, z); o.rotation.y = ry; o.castShadow = true; o.receiveShadow = true; grp.add(o); return o; };
  const box = (w, h, d, m, x, z, y0 = 0) => { const o = mesh(new THREE.BoxGeometry(w, h, d), m, x, y0 + h / 2, z); obstacles.push({ kind: 'box', x, z, hw: w / 2, hd: d / 2, h, mesh: o }); return o; };
  const cyl = (r, h, m, x, z, seg = 14) => { const o = mesh(new THREE.CylinderGeometry(r, r, h, seg), m, x, h / 2, z); obstacles.push({ kind: 'circle', x, z, r, h, mesh: o }); return o; };
  const barrel = (x, z) => {
    const g = new THREE.Group(); g.position.set(x, 0, z); grp.add(g);
    const b = new THREE.Mesh(new THREE.CylinderGeometry(0.75, 0.75, 1.8, 10), M.barrel); b.position.y = 0.9; b.castShadow = true;
    const band = new THREE.Mesh(new THREE.CylinderGeometry(0.77, 0.77, 0.25, 10), M.barrelBand); band.position.y = 1.2;
    g.add(b, band);
    obstacles.push({ kind: 'circle', x, z, r: 0.9, h: 1.8, mesh: g, barrel: true, hp: 15 });
  };

  // boundary: jersey barriers with a hazard stripe, plus a tall outer fence
  const wallH = 2.4, segs = Math.ceil(map.size / 6);
  for (let i = 0; i < segs; i++) {
    const p = -half + (i + 0.5) * (map.size / segs);
    for (const [x, z, ry] of [[p, -half, 0], [p, half, 0], [-half, p, Math.PI / 2], [half, p, Math.PI / 2]]) {
      const w = mesh(new THREE.BoxGeometry(map.size / segs - 0.2, wallH, 1.4), i % 2 ? M.concrete : M.darkConcrete, x, wallH / 2, z, ry);
      if (i % 3 === 0) mesh(new THREE.BoxGeometry(map.size / segs - 0.2, 0.3, 1.45), M.hazard, x, wallH - 0.4, z, ry);
      w.receiveShadow = true;
    }
  }
  // backdrop silhouettes beyond the walls
  for (let i = 0; i < 40; i++) {
    const a = (i / 40) * Math.PI * 2, d = half + 15 + R() * 40;
    const h = map.id === 'dustbowl' ? 4 + R() * 14 : 6 + R() * 22;
    const o = new THREE.Mesh(map.id === 'dustbowl' ? new THREE.DodecahedronGeometry(h * 0.7, 0) : new THREE.BoxGeometry(6 + R() * 10, h, 6 + R() * 10), M.darkConcrete);
    o.position.set(Math.cos(a) * d, h / 2 - 1, Math.sin(a) * d); o.rotation.y = R() * 3; grp.add(o);
  }

  const spawnR = half * 0.72;
  const clear = (x, z, r) => {
    if (Math.abs(x) > half - r - 3 || Math.abs(z) > half - r - 3) return false;
    for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2; if (Math.hypot(x - Math.cos(a) * spawnR, z - Math.sin(a) * spawnR) < r + 7) return false; }
    if (Math.hypot(x, z) < r + 6) return false;
    return obstacles.every((o) => Math.hypot(o.x - x, o.z - z) > r + (o.r || Math.max(o.hw, o.hd)) + 5);
  };
  const place = (count, r, fn) => { let n = 0, tries = 0; while (n < count && tries++ < 400) { const x = (R() * 2 - 1) * half, z = (R() * 2 - 1) * half; if (clear(x, z, r)) { fn(x, z); n++; } } };

  if (map.id === 'scrapyard') {
    place(9, 4, (x, z) => { // wreck piles
      const n = 2 + Math.floor(R() * 3), ry = R() * 3;
      box(4.6, 0.9 * n, 2.2, M.rust, x, z);
      for (let i = 0; i < n; i++) { const o = mesh(new THREE.BoxGeometry(4.2, 0.85, 2.0), M.containers[(i + Math.floor(x)) & 3], x + (R() - 0.5) * 0.6, 0.45 + i * 0.9, z + (R() - 0.5) * 0.4, ry * 0 + (R() - 0.5) * 0.3); o.material = i % 2 ? M.rust : o.material; }
    });
    place(4, 7, (x, z) => { const vertical = R() < 0.5; const o = box(vertical ? 2.6 : 12, 2.8, vertical ? 12 : 2.6, M.containers[Math.floor(R() * 4)], x, z); return o; });
    place(6, 2, (x, z) => { const o = cyl(1.3, 2.4, M.tire, x, z, 10); for (let i = 0; i < 4; i++) mesh(new THREE.TorusGeometry(1.1, 0.35, 6, 12), M.tire, x, 0.35 + i * 0.6, z).rotation.x = Math.PI / 2; o.visible = false; });
    // dead crane in the middle of one side
    const cx = -half * 0.35, cz = half * 0.05;
    box(3, 18, 3, M.hazard, cx, cz);
    mesh(new THREE.BoxGeometry(1.2, 1.2, 22), M.hazard, cx, 17.5, cz + 7);
    place(5, 1.5, (x, z) => { barrel(x, z); barrel(x + 1.8, z + 0.4); });
  } else if (map.id === 'refinery') {
    place(5, 7, (x, z) => { const r = 4 + R() * 3; const t = cyl(r, 8 + R() * 6, M.concrete, x, z, 20); mesh(new THREE.CylinderGeometry(r + 0.1, r + 0.1, 0.5, 20), M.hazard, x, t.geometry.parameters.height - 0.3, z); });
    place(5, 6, (x, z) => { const along = R() < 0.5; box(along ? 14 : 1.6, 3.4, along ? 1.6 : 14, M.steel, x, z); });
    place(8, 2.5, (x, z) => { barrel(x, z); barrel(x + 1.7, z); barrel(x + 0.85, z + 1.5); });
    place(6, 2, (x, z) => box(4, 1.2, 1.2, M.concrete, x, z));
  } else {
    place(12, 4, (x, z) => { const r = 2 + R() * 2.5; const o = cyl(r, 5 + R() * 9, M.rock, x, z, 7); o.geometry = new THREE.CylinderGeometry(r * 0.7, r, o.geometry.parameters.height, 7); o.rotation.y = R() * 3; });
    place(6, 6, (x, z) => { const along = R() < 0.5, len = 7 + R() * 7; box(along ? len : 1.4, 2.5 + R() * 2, along ? 1.4 : len, M.concrete, x, z); });
    place(4, 1.5, (x, z) => { barrel(x, z); barrel(x + 1.8, z + 0.4); });
  }

  const spawns = [];
  for (let i = 0; i < 8; i++) { const a = (i / 8) * Math.PI * 2 + Math.PI / 2; spawns.push({ x: Math.cos(a) * spawnR, z: Math.sin(a) * spawnR, heading: Math.atan2(-Math.cos(a), -Math.sin(a)) }); }

  const pickupSpots = [];
  for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2 + 0.4, d = half * (i % 2 ? 0.42 : 0.25); pickupSpots.push({ x: Math.cos(a) * d, z: Math.sin(a) * d, type: i % 2 ? 'ammo' : 'health' }); }

  return { group: grp, obstacles, spawns, pickupSpots, half, sun };
}
