// Screenshots the lobby, setup and HUD on phone and tablet viewports, and reports render resolution.
// Usage: node tools/devices.mjs <url> <outDir>
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';

const [url, out] = process.argv.slice(2);
const DEVICES = [
  { name: 'phone', width: 915, height: 412, dpr: 2.625 },          // Pixel 7 landscape
  { name: 'tab11', width: 1280, height: 800, dpr: 2 },              // 11" Android tablet
  { name: 'tab12', width: 1366, height: 1024, dpr: 2 },             // 12.9" tablet
];
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
for (const d of DEVICES) {
  const ctx = await browser.newContext({ viewport: { width: d.width, height: d.height }, deviceScaleFactor: d.dpr, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  const errs = []; page.on('pageerror', (e) => errs.push(e.message));
  await page.goto(url); await page.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 }); await page.waitForTimeout(600);
  await page.screenshot({ path: `${out}/${d.name}-1-lobby.png`, scale: 'css' });
  await page.tap('#btnSettings'); await page.waitForTimeout(300);
  await page.screenshot({ path: `${out}/${d.name}-2-settings.png`, scale: 'css' });
  await page.tap('#setBack'); await page.tap('#btnPlay'); await page.waitForTimeout(400);
  await page.screenshot({ path: `${out}/${d.name}-3-setup.png`, scale: 'css' });
  await page.tap('#sFight'); await page.waitForTimeout(1200);
  await page.evaluate(() => { const g = window.__ironmetal.game; for (let f = 0; f < 150; f++) g.update(1 / 30); });
  await page.waitForTimeout(600);
  await page.screenshot({ path: `${out}/${d.name}-4-hud.png`, scale: 'css' });
  const r = await page.evaluate(() => { const c = document.getElementById('view'); return { css: `${innerWidth}x${innerHeight}`, render: `${c.width}x${c.height}`, mpx: (c.width * c.height / 1e6).toFixed(2) }; });
  console.log(d.name, JSON.stringify(r), errs.length ? errs : 'ok');
  await ctx.close();
}
await browser.close();
