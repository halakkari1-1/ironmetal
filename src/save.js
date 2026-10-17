// Player progress, kept in this device's browser storage.
import { CARS, START_POINTS } from './data.js';

const KEY = 'ironmetal_save_v1';

function fresh() {
  return {
    points: START_POINTS,
    owned: ['rustbucket'],
    selected: 'rustbucket',
    upgrades: {},
    history: [],
    stats: { matches: 0, wins: 0, kills: 0 },
    sound: true,
  };
}

let state = fresh();
try {
  const raw = localStorage.getItem(KEY);
  if (raw) state = Object.assign(fresh(), JSON.parse(raw));
} catch (e) { /* storage unavailable: play without saving */ }

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
    this.write();
  },
  reset() { state = fresh(); this.write(); },
};
