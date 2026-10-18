// Free-for-all balance check: eight of the nine vehicles per match (the arena has 8 spawns), equal upgrades, all AI-driven, 3 lives each.
// Reports per vehicle: kills and deaths per match, average finishing place, damage dealt.
// Usage: node tools/matchups.mjs <url> [rounds=2] [level=0]
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, rounds = '2', level = '0'] = process.argv.slice(2);
const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage({ viewport: { width: 480, height: 270 } }); const errs = []; p.on('pageerror', (e) => errs.push(e.message));
await p.goto(url); await p.waitForFunction(() => document.getElementById('loader').hidden, null, { timeout: 120000 });
const res = await p.evaluate(async ({ rounds, level }) => {
  const im = window.__ironmetal, stats = {};
  const diff = { id: 'sim', name: 'Sim', enemies: 7, dmg: 1, accuracy: 0.75, aggression: 0.9, focus: 1, level, hp: 1, maxPrice: 99999, reward: 1, base: 0 };
  for (let r = 0; r < rounds; r++) for (const car of im.CARS) {
    const L = level;
    await im.startMatch({ car, upgrades: { gun: L, rocket: L, armor: L, speed: L, special: L }, map: im.MAPS[(r * 3 + im.CARS.indexOf(car)) % im.MAPS.length], diff, mode: 'deathmatch' });
    const g = im.game; g.player.dmgMul = 1;
    const p = g.player; p.ai = { target: null, retarget: 0, stuck: 0, reverseT: 0, rocketT: 2, strafe: 1, specialT: 3 };
    const dealt = new Map(), order = [];
    const dmg0 = g.damage.bind(g); g.damage = (c, amt, by, q, cause) => { const before = c.hp; dmg0(c, amt, by, q, cause); if (by && by !== c) dealt.set(by, (dealt.get(by) || 0) + Math.max(0, before - Math.max(0, c.hp))); };
    for (let f = 0; f < 30 * 330 && g.running && g.state !== 'ending'; f++) {
      for (const c of g.cars) if (c.lives === 0 && !c.alive && !order.includes(c)) order.push(c);
      if (g.state === 'fight' && p.alive) g.think(p, 1 / 30);
      g.update(1 / 30);
    }
    const alive = g.cars.filter((c) => !order.includes(c)).sort((a, b) => b.kills - a.kills || b.lives - a.lives);
    const ranking = [...alive, ...order.reverse()];
    for (const c of g.cars) {
      const s = stats[c.data.id] || (stats[c.data.id] = { n: 0, kills: 0, deaths: 0, place: 0, dmg: 0 });
      s.n++; s.kills += c.kills; s.deaths += 3 - c.lives; s.place += ranking.indexOf(c) + 1; s.dmg += dealt.get(c) || 0;
    }
  }
  return Object.entries(stats).map(([id, s]) => ({ id, matches: s.n, kills: (s.kills / s.n).toFixed(2), deaths: (s.deaths / s.n).toFixed(2), place: (s.place / s.n).toFixed(2), dmg: Math.round(s.dmg / s.n) }));
}, { rounds: +rounds, level: +level });
console.table(res.sort((a, b) => a.place - b.place));
console.log(errs.length ? errs.slice(0, 5).join('\n') : 'no errors');
await b.close();
