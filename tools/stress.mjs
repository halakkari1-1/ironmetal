// Runs every car on every map with random input, fast-forwarded, and reports errors and outcomes.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';

const [base, out] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 640 } });
const errors = [];
page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}\n${e.stack}`));
page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_TUNNEL')) errors.push(`[console] ${m.text()}`); });
await page.goto(base); await page.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 });

const results = [];
const cars = ['rustbucket', 'stinger', 'bulldog', 'hellfire', 'maiden', 'viper', 'juggernaut', 'warhorse'];
const maps = ['scrapyard', 'refinery', 'dustbowl'];
for (let i = 0; i < cars.length; i++) {
  const map = maps[i % 3];
  const r = await page.evaluate(async ({ carId, mapId, idx, mode }) => {
    const im = window.__ironmetal;
    const car = im.CARS.find((c) => c.id === carId);
    await im.startMatch({ car, upgrades: { gun: 2, rocket: 2, armor: 2, speed: 2, special: 2 }, map: im.MAPS.find((m) => m.id === mapId), diff: im.DIFFICULTY[2], mode });
    const g = im.game;
    let specials = 0;
    for (let f = 0; f < 1800 && g.running; f++) {
      const t = f / 30;
      g.setInput(Math.sin(t * 0.7) > -0.6 ? 1 : -1, Math.sin(t * 1.3), (f % 60) < 40);
      if (f % 45 === 0) g.playerRocket();
      if (f % 90 === 10 && g.player.specialCd <= 0) { g.playerSpecial(); specials++; }
      g.update(1 / 30);
      if (f === 150) g.dropT = 0;
      if (f === 170) g.eventT = 0;
      if (f === 260) g.player.power = { type: ['railgun', 'napalm', 'nuke'][idx % 3], ammo: 3 };
      if (f === 900) g.eventT = 0;
    }
    return { car: carId, map: mapId, mode, wave: g.stats.wave, bonus: g.stats.bonus.length, t: g.time.toFixed(0), state: g.state, result: g.result || '-', playerHp: Math.max(0, g.player.hp).toFixed(0), kills: g.player.kills, alive: g.cars.filter((c) => c.alive).length, specials, particles: g.fx.fire.n + g.fx.hot.n + g.fx.smoke.n, debris: g.fx.debris.length };
  }, { carId: cars[i], mapId: map, idx: i, mode: i >= 6 ? 'survival' : 'deathmatch' });
  results.push(r);
}
console.table(results);
console.log(errors.length ? errors.slice(0, 8).join('\n') : 'no errors');
await browser.close();
