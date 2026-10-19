// Captures the effects frame by frame: an explosion, a big explosion, burning wreck flames and smoke, gunfire.
// Usage: node tools/vfx.mjs <url> <outDir>
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, out] = process.argv.slice(2);
const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage({ viewport: { width: 960, height: 480 } }); const errs = []; p.on('pageerror', (e) => errs.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
await p.goto(url); await p.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 });
await p.evaluate(async () => { const im = window.__ironmetal; await im.startMatch({ car: im.CARS[0], upgrades: {}, map: im.MAPS[2], diff: im.DIFFICULTY[0], mode: 'deathmatch' }); const g = im.game; for (let f = 0; f < 110; f++) g.update(1 / 30); for (const c of g.cars) if (!c.isPlayer) { c.x = 50; c.z = 50; c.ai = { target: null, retarget: 99, stuck: 0, reverseT: 0, rocketT: 99, strafe: 1, specialT: 99 }; } });
await p.waitForTimeout(1500); // textures
const step = async (n) => p.evaluate((n) => { const g = window.__ironmetal.game; g.setInput(0, 0, false); for (let f = 0; f < n; f++) g.update(1 / 30); window.__ironmetal.renderNow(); }, n);
const at = (dist, size) => p.evaluate(({ dist, size }) => { const g = window.__ironmetal.game, pl = g.player; g.fx.explosion(pl.x + Math.sin(pl.heading) * dist, pl.z + Math.cos(pl.heading) * dist, size); }, { dist, size });
await at(16, 1); for (const [i, n] of [[1, 3], [2, 6], [3, 12], [4, 30]]) { await step(n); await p.waitForTimeout(150); await p.screenshot({ path: `${out}/exp-${i}.png` }); }
await step(90); await at(22, 1.6); for (const [i, n] of [[1, 4], [2, 10], [3, 25]]) { await step(n); await p.waitForTimeout(150); await p.screenshot({ path: `${out}/big-${i}.png` }); }
await step(120);
await p.evaluate(() => { const g = window.__ironmetal.game, pl = g.player, x = pl.x + Math.sin(pl.heading) * 12, z = pl.z + Math.cos(pl.heading) * 12; g.zones.push({ x, z, r: 4, t: 8, dps: 0, owner: null }); g.fxT = setInterval(() => { for (let i = 0; i < 3; i++) g.fx.burn(x + 5, 1.5, z); }, 30); });
await step(40); await p.waitForTimeout(150); await p.screenshot({ path: `${out}/fire.png` });
await p.evaluate(() => { const g = window.__ironmetal.game; clearInterval(g.fxT); g.zones = []; });
await step(90); await p.evaluate(() => { const g = window.__ironmetal.game; g.setInput(0, 0, true); for (let f = 0; f < 8; f++) g.update(1 / 30); window.__ironmetal.renderNow(); });
await p.screenshot({ path: `${out}/gun.png` });
console.log(errs.length ? errs : 'no errors');
await b.close();
