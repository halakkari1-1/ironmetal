// Usage: node tools/models.mjs <base url> <out.png> id1,id2,...
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [base, out, ids] = process.argv.slice(2);
const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage({ viewport: { width: 1600, height: 900 } }); p.on('pageerror', (e) => console.log(e.message));
await p.goto(`${base}/tools/models.html?ids=${ids}`); await p.waitForFunction(() => document.title === 'done', null, { timeout: 120000 });
await p.screenshot({ path: out }); await b.close();
