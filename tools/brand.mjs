// Renders the app icon and splash screen PNGs: node tools/brand.mjs <baseUrl> <outDir>
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';

const [base, out] = process.argv.slice(2);
const browser = await chromium.launch();
for (const [mode, size] of [['icon', 1024], ['splash', 2732]]) {
  const page = await browser.newPage({ viewport: { width: size, height: size } });
  await page.goto(`${base}/tools/brand.html?mode=${mode}&size=${size}`);
  await page.waitForFunction(() => window.READY === true);
  await page.waitForTimeout(400);
  await page.screenshot({ path: `${out}/${mode}.png` });
  await page.close();
}
await browser.close();
console.log('rendered');
