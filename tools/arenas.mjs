// Renders every arena from the chase camera and from above, saves map thumbnails, and reports triangle counts.
// Usage: node tools/arenas.mjs <url> <outDir> [thumbDir]
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { writeFileSync } from 'node:fs';

const [url, out, thumbs] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 640 } });
const errs = []; page.on('pageerror', (e) => errs.push(e.message)); page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_TUNNEL')) errs.push(m.text()); });
await page.goto(url); await page.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 });
await page.waitForTimeout(800);
await page.screenshot({ path: `${out}/lobby.png` });
const ids = await page.evaluate(() => window.__ironmetal.MAPS.map((m) => m.id));
for (const id of ids) {
  const info = await page.evaluate(async (id) => {
    const im = window.__ironmetal;
    await im.startMatch({ car: im.CARS[7], upgrades: {}, map: im.MAPS.find((m) => m.id === id), diff: im.DIFFICULTY[1], mode: 'deathmatch' });
    const g = im.game; for (let f = 0; f < 140; f++) g.update(1 / 30);
    g.running = false;
    let tris = 0, draws = 0;
    g.scene.traverse((o) => { if ((o.isMesh || o.isInstancedMesh) && o.visible) { const gg = o.geometry, t = (gg.index ? gg.index.count : gg.attributes.position.count) / 3; tris += t * (o.isInstancedMesh ? o.count : 1); draws++; } });
    return { tris: Math.round(tris), meshes: draws, obstacles: g.arena.obstacles.length };
  }, id);
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${out}/${id}-chase.png` });
  // overhead three-quarter view for the map card thumbnail
  const thumb = await page.evaluate(() => {
    const g = window.__ironmetal.game, cam = g.camera, half = g.arena.half;
    cam.position.set(half * 0.55, half * 0.62, half * 0.95); cam.lookAt(0, 0, -half * 0.12); cam.fov = 55; cam.updateProjectionMatrix();
    window.__ironmetal.renderNow();
    const c = document.getElementById('view');
    const t = document.createElement('canvas'); t.width = 480; t.height = 200; const x = t.getContext('2d');
    const sw = c.width, sh = c.width * 200 / 480; x.drawImage(c, 0, (c.height - sh) / 2, sw, sh, 0, 0, 480, 200);
    return t.toDataURL('image/jpeg', 0.82);
  });
  await page.screenshot({ path: `${out}/${id}-top.png` });
  if (thumbs) writeFileSync(`${thumbs}/${id}.jpg`, Buffer.from(thumb.split(',')[1], 'base64'));
  console.log(id, JSON.stringify(info));
}
console.log(errs.length ? errs.slice(0, 6) : 'no errors');
await browser.close();
