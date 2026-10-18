// Survival balance: player on autopilot, reports waves reached.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [base, carId = 'rustbucket', lvl = '0', runs = '5'] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const errors = []; page.on('pageerror', (e) => errors.push(e.message));
await page.goto(base); await page.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 });
const r = await page.evaluate(async ({ carId, lvl, runs }) => {
  const im = window.__ironmetal, waves = [];
  for (let i = 0; i < runs; i++) {
    const L = +lvl; await im.startMatch({ car: im.CARS.find((c) => c.id === carId), upgrades: { gun: L, rocket: L, armor: L, speed: L, special: L }, map: im.MAPS[i % im.MAPS.length], diff: im.DIFFICULTY[0], mode: 'survival' });
    const g = im.game, p = g.player;
    p.ai = { target: null, retarget: 0, stuck: 0, reverseT: 0, rocketT: 2, strafe: 1, specialT: 3, goal: null };
    for (let f = 0; f < 30 * 600 && g.running; f++) { if (g.state === 'fight' && p.alive) g.think(p, 1 / 30); g.update(1 / 30); }
    waves.push(g.stats.wave);
  }
  return waves;
}, { carId, lvl, runs: +runs });
console.log(carId, 'lvl', lvl, 'waves reached:', r.join(', '), errors.length ? errors : '');
await browser.close();
