// Vehicle check: every car in the garage (screenshot), then in a match: drives, fires guns and rockets,
// uses its ability on a nearby enemy, and reports what the ability actually did.
// Usage: node tools/vehicles.mjs <url> <outDir>
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, out] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 640 } });
const errs = []; page.on('pageerror', (e) => errs.push(e.message + '\n' + e.stack)); page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_TUNNEL')) errs.push(m.text()); });
await page.goto(url); await page.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 });
await page.evaluate(() => { const s = window.__ironmetal.save.get(); s.points = 50000; });
await page.click('#btnGarage'); await page.waitForTimeout(400);
const ids = await page.evaluate(() => window.__ironmetal.CARS.map((c) => c.id));
for (let i = 0; i < ids.length; i++) {
  await page.waitForFunction((id) => window.__ironmetal.room && window.__ironmetal.room.carId === id, ids[i], { timeout: 60000 });
  await page.waitForTimeout(700);
  await page.screenshot({ path: `${out}/garage-${i + 1}-${ids[i]}.png` });
  await page.click('#gNext'); await page.waitForTimeout(200);
}
const rows = [];
for (const id of ids) {
  const r = await page.evaluate(async (id) => {
    const im = window.__ironmetal, car = im.CARS.find((c) => c.id === id);
    await im.startMatch({ car, upgrades: { gun: 0, rocket: 0, armor: 0, speed: 0, special: 0 }, map: im.MAPS[0], diff: im.DIFFICULTY[1], mode: 'deathmatch' });
    const g = im.game, p = g.player;
    for (let f = 0; f < 120; f++) g.update(1 / 30); // countdown
    const dims = p.mesh.userData.dims, model = !!dims;
    // drive forward 2 s
    const x0 = p.x, z0 = p.z; g.setInput(1, 0, true); for (let f = 0; f < 60; f++) g.update(1 / 30);
    const moved = Math.hypot(p.x - x0, p.z - z0), bullets = g.bullets.length;
    g.playerRocket(); const rockets = g.rockets.length;
    // put one enemy right in front, others away, and use the ability
    const e = g.cars.find((c) => !c.isPlayer); const fx = Math.sin(p.heading), fz = Math.cos(p.heading);
    e.x = p.x + fx * 7; e.z = p.z + fz * 7; e.heading = p.heading + Math.PI; e.speed = 0; e.invuln = 0;
    for (const o of g.cars) if (!o.isPlayer && o !== e) { o.x = -p.x * 0.5 + 30; o.z = -p.z * 0.5; }
    if (e.ai) e.ai.target = p;
    p.specialCd = 0; const hp0 = e.hp;
    const used = g.useSpecial(p);
    const fx0 = { slow: e.slowT, jam: e.jamT, skid: e.skidT, playerHidden: p.hideT, specialOn: p.specialOn, zones: g.zones.length, rocketsAfter: g.rockets.length };
    for (let f = 0; f < 45; f++) { g.setInput(0, 0, false); g.update(1 / 30); }
    // shield/dash damage cut
    let cut = '-';
    if (car.special.id === 'shield' || car.special.id === 'dash') { p.specialCd = 0; p.specialOn = null; g.useSpecial(p); const h = p.hp; g.damage(p, 20, e); cut = `${(h - p.hp).toFixed(0)}/20`; }
    const shot = g.player.specialCd > 0;
    return { id, model, len: dims ? dims.L.toFixed(1) : '-', h: dims ? dims.H.toFixed(1) : '-', hitR: p.hitR.toFixed(1), hp: p.maxHp, vmax: p.stats.maxSpeed.toFixed(1), moved: moved.toFixed(1), bullets, rockets, used, enemyDmg: (hp0 - e.hp).toFixed(0), ...fx0, cut, cooldown: shot };
  }, id);
  rows.push(r);
  await page.waitForTimeout(250);
  await page.screenshot({ path: `${out}/match-${id}.png` });
}
console.table(rows);
console.log(errs.length ? errs.slice(0, 6).join('\n') : 'no errors');
await browser.close();
