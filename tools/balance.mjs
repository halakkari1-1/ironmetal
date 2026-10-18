// Balance sim: the player car is driven by the same AI as the enemies. Reports win rate per difficulty.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';

const [base, carId = 'rustbucket', lvl = '0', runs = '8'] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.goto(base); await page.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 });
for (let d = 0; d < 3; d++) {
  const r = await page.evaluate(async ({ d, carId, lvl, runs }) => {
    const im = window.__ironmetal, out = { wins: 0, kills: 0, time: 0 };
    for (let i = 0; i < runs; i++) {
      const car = im.CARS.find((c) => c.id === carId), L = +lvl;
      await im.startMatch({ car, upgrades: { gun: L, rocket: L, armor: L, speed: L, special: L }, map: im.MAPS[i % im.MAPS.length], diff: im.DIFFICULTY[d] });
      const g = im.game, p = g.player;
      p.ai = { target: null, retarget: 0, stuck: 0, reverseT: 0, rocketT: 2, strafe: 1, specialT: 3 };
      for (let f = 0; f < 30 * 330 && g.running; f++) { if (g.state === 'fight' && p.alive) g.think(p, 1 / 30); g.update(1 / 30); }
      if (g.result === 'win') out.wins++;
      out.kills += p.kills; out.time += g.time;
    }
    return { diff: im.DIFFICULTY[d].name, winRate: Math.round((out.wins / runs) * 100) + '%', avgKills: (out.kills / runs).toFixed(1), avgTime: (out.time / runs).toFixed(0) + 's' };
  }, { d, carId, lvl, runs: +runs });
  console.log(JSON.stringify(r));
}
console.log(errors.length ? errors.join('\n') : 'no errors');
await browser.close();
