// Headless screenshot helper: node tools/shot.mjs <url> <out.png> [width] [height] [waitMs] [script]
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';

const [url, out, w = '1600', h = '800', wait = '1500', script = ''] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: +w, height: +h }, hasTouch: false });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errors.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}`));
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(+wait);
if (script) { await page.evaluate(script); await page.waitForTimeout(+wait); }
await page.screenshot({ path: out });
console.log(errors.length ? errors.join('\n') : 'no console errors');
await browser.close();
