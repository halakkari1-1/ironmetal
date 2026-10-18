// Player progress, kept in this device's browser storage.
import { CARS, MAPS, CONTRACTS, START_POINTS } from './data.js';

const KEY = 'ironmetal_save_v1';

function fresh() {
  return {
    points: START_POINTS,
    owned: ['rustbucket'],
    selected: 'rustbucket',
    upgrades: {},
    history: [],
    stats: { matches: 0, wins: 0, kills: 0 },
    best: { wave: 0 },
    contracts: null,
    sound: true,
    music: true,
    graphics: 'auto',
    controls: 1,
  };
}

let state = fresh();
try {
  const raw = localStorage.getItem(KEY);
  if (raw) { const f = fresh(); state = Object.assign(f, JSON.parse(raw)); state.best = Object.assign(f.best, state.best || {}); }
} catch (e) { /* storage unavailable: play without saving */ }

function today() { const d = new Date(); return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`; }
function seeded(str) { let h = 2166136261; for (const ch of str) h = Math.imul(h ^ ch.charCodeAt(0), 16777619); return () => ((h = Math.imul(h ^ (h >>> 15), 2246822507) ^ Math.imul(h ^ (h >>> 13), 3266489909)) >>> 0) / 4294967296; }

export const save = {
  get: () => state,
  write() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* ignore */ }
  },
  car(id) { return CARS.find((c) => c.id === id); },
  selectedCar() { return this.car(state.selected) || CARS[0]; },
  owns(id) { return state.owned.includes(id); },
  upgrades(id) {
    if (!state.upgrades[id]) state.upgrades[id] = { gun: 0, rocket: 0, armor: 0, speed: 0, special: 0 };
    return state.upgrades[id];
  },
  spend(n) {
    if (state.points < n) return false;
    state.points -= n; this.write(); return true;
  },
  buy(car) {
    if (this.owns(car.id) || !this.spend(car.price)) return false;
    state.owned.push(car.id); state.selected = car.id; this.write(); return true;
  },
  select(id) { if (this.owns(id)) { state.selected = id; this.write(); } },
  record(entry) {
    state.history.unshift(entry);
    state.history = state.history.slice(0, 30);
    state.points += entry.points;
    state.stats.matches++;
    if (entry.result === 'win') state.stats.wins++;
    state.stats.kills += entry.kills;
    if (entry.wave) state.best.wave = Math.max(state.best.wave, entry.wave);
    this.write();
  },

  // ---------- daily contracts ----------
  contracts() {
    const day = today();
    if (!state.contracts || state.contracts.day !== day) {
      const rnd = seeded(day), pool = [...CONTRACTS], list = [];
      while (list.length < 3) {
        const t = pool.splice(Math.floor(rnd() * pool.length), 1)[0];
        const gi = Math.floor(rnd() * t.goals.length), goal = t.goals[gi];
        const map = MAPS[Math.floor(rnd() * MAPS.length)];
        list.push({ id: t.id, goal, progress: 0, done: false, map: map.id, text: t.text.replace('{n}', goal).replace('{map}', map.name), reward: Math.round((t.reward * (t.goals.length > 1 ? goal : 1) + 80) / 10) * 10 });
      }
      state.contracts = { day, list }; this.write();
    }
    return state.contracts.list;
  },
  // Applies a finished match to today's contracts. Returns the contracts completed by it.
  applyContracts(m) {
    const done = [];
    for (const c of this.contracts()) {
      if (c.done) continue;
      const s = m.stats;
      const add = { kills: s.kills, rocketKills: s.rocketKills, barrels: s.barrels, airdrops: s.airdrops, bounty: s.bounty,
        streak: s.streakMax >= 2 ? 1 : 0, winMap: m.result === 'win' && m.map === c.map ? 1 : 0,
        winVet: m.result === 'win' && (m.diff === 'normal' || m.diff === 'hard') ? 1 : 0 }[c.id];
      if (c.id === 'wave') c.progress = Math.max(c.progress, s.wave || 0); else c.progress += add || 0;
      if (c.progress >= c.goal) { c.progress = c.goal; c.done = true; state.points += c.reward; done.push(c); }
    }
    this.write();
    return done;
  },
  reset() { state = fresh(); this.write(); },
};
