// Automated playtest: menu -> garage -> upgrades -> setup -> match with simulated input.
// Usage: node tools/playtest.mjs <baseUrl> <outDir> [map] [diff]
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';

const [base, out, map = 'scrapyard', diff = 'normal'] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 640 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(`[console] ${m.text()}`); });
page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}\n${e.stack}`));
const shot = async (name) => page.screenshot({ path: `${out}/${name}.png` });

await page.goto(base, { waitUntil: 'load' });
await page.waitForTimeout(4000);
await shot('1-menu');
await page.click('#btnGarage'); await page.waitForTimeout(700);
await page.click('#gNext'); await page.waitForTimeout(900);
await shot('2-garage');
for (let i = 0; i < 6; i++) await page.click('#gNext');
await page.waitForTimeout(900); await shot('3-garage-warhorse');
await page.click('#gBack'); await page.evaluate(() => { window.__ironmetal.save.get().points = 5000; });
await page.click('#btnUpgrade'); await page.waitForTimeout(500);
await page.click('[data-up="gun"]'); await page.waitForTimeout(600);
await shot('4-upgrades');
await page.click('#uBack');
await page.click('#btnPlay'); await page.waitForTimeout(400);
await page.click(`[data-map="${map}"]`); await page.click(`[data-diff="${diff}"]`);
await shot('5-setup');
await page.click('#sFight');
await page.waitForTimeout(2500);
await shot('6-countdown');
await page.waitForTimeout(2000);
await page.keyboard.down('KeyW');
await page.waitForTimeout(1200);
await page.keyboard.down('Space'); await page.keyboard.down('KeyA');
await page.waitForTimeout(900);
await page.keyboard.press('KeyF'); await page.keyboard.press('KeyE');
await page.waitForTimeout(500);
await shot('7-fight');
await page.keyboard.up('KeyA');
await page.waitForTimeout(3000);
await shot('8-fight-later');
const st = await page.evaluate(() => { const g = window.__ironmetal.game; return g ? { t: g.time.toFixed(1), state: g.state, hp: g.player.hp.toFixed(0), alive: g.cars.filter((c) => c.alive).length, cars: g.cars.map((c) => `${c.data.id}:${c.hp.toFixed(0)}@${c.x.toFixed(0)},${c.z.toFixed(0)} spd ${c.speed.toFixed(1)}`) } : null; });
console.log(JSON.stringify(st, null, 1));
// fast-forward: let the AI fight it out
await page.evaluate(() => { const g = window.__ironmetal.game; for (let i = 0; i < 2400 && g.running; i++) g.update(1 / 30); });
await page.waitForTimeout(300);
const st2 = await page.evaluate(() => { const g = window.__ironmetal.game; return { t: g.time.toFixed(1), state: g.state, result: g.result, alive: g.cars.filter((c) => c.alive).map((c) => c.data.id), kills: g.cars.map((c) => `${c.data.id}:${c.kills}`) }; });
console.log(JSON.stringify(st2));
await page.waitForTimeout(500);
await shot('9-end');
console.log(errors.length ? errors.join('\n') : 'no errors');
await browser.close();
