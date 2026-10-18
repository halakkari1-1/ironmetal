// Static game data: cars, drivers, specials, maps, difficulty and economy.

export const LORE =
  'Twenty years after the oil ran dry, the old refineries became arenas. ' +
  'Every season the wasteland clans send their machines to the Iron Cup. ' +
  'Win, and you eat. Lose, and the scrappers strip what is left of you.';

// stats are 1..10 and map to real values in carStats()
export const CARS = [
  {
    id: 'rustbucket', name: 'Rustbucket', price: 0,
    driver: 'Sami "Spanner" Haddad',
    story: 'A mechanic who rebuilt his father\'s sedan from three wrecks and a prayer. ' +
      'It rattles, it leaks, and it has never once failed to start.',
    stats: { speed: 6, armor: 5, gun: 5, rocket: 4 },
    special: { id: 'nitro', name: 'Nitro Burst', desc: 'Doubles top speed for 3 seconds.', cooldown: 9 },
  },
  {
    id: 'stinger', name: 'Dune Stinger', price: 900,
    driver: 'Layla Qasim',
    story: 'Raised by smugglers on the salt flats, Layla drives like the ground is on fire. ' +
      'Her buggy weighs nothing and forgives nothing.',
    stats: { speed: 9, armor: 3, gun: 5, rocket: 4 },
    special: { id: 'ram', name: 'Ram Charge', desc: 'Lunges forward. Anything you hit takes heavy damage.', cooldown: 8 },
  },
  {
    id: 'bulldog', name: 'Bulldog', price: 1800,
    driver: 'Old Man Fares',
    story: 'Fares towed wrecks off the highway for forty years. ' +
      'Now he builds them. The crane on his back has lifted heavier things than your car.',
    stats: { speed: 4, armor: 8, gun: 5, rocket: 5 },
    special: { id: 'shockwave', name: 'Shockwave', desc: 'Slams the ground, throwing nearby cars back and hurting them.', cooldown: 11 },
  },
  {
    id: 'hellfire', name: 'Hellfire', price: 3000,
    driver: 'Nadia "Torch" Saleh',
    story: 'She lost her garage to a raider fire and kept the flamethrower that started it. ' +
      'Nobody in the arena wants to be close to her bumper.',
    stats: { speed: 7, armor: 5, gun: 6, rocket: 5 },
    special: { id: 'flame', name: 'Flamethrower', desc: 'Sprays fire ahead for 3 seconds, burning everything in the cone.', cooldown: 12 },
  },
  {
    id: 'maiden', name: 'Iron Maiden', price: 4500,
    driver: 'Brother Yusuf',
    story: 'A former convoy guard who armored an aid van until it stopped looking like one. ' +
      'He prays before every match and reloads during the prayer.',
    stats: { speed: 4, armor: 10, gun: 6, rocket: 5 },
    special: { id: 'shield', name: 'Iron Shield', desc: 'Blocks all damage for 4 seconds.', cooldown: 14 },
  },
  {
    id: 'viper', name: 'Viper', price: 6500,
    driver: 'Karim Zein',
    story: 'An ex-racer banned from every track that still exists. ' +
      'The Viper is fast, low, and carries missiles that find you on their own.',
    stats: { speed: 9, armor: 4, gun: 6, rocket: 8 },
    special: { id: 'homing', name: 'Seeker Missiles', desc: 'Fires three missiles that hunt the nearest enemies.', cooldown: 10 },
  },
  {
    id: 'juggernaut', name: 'Juggernaut', price: 9500,
    driver: 'The Brothers Antar',
    story: 'Two brothers, one rig, no brakes. ' +
      'They haul a trailer full of mines and they are not shy about unloading it.',
    stats: { speed: 5, armor: 9, gun: 7, rocket: 7 },
    special: { id: 'mines', name: 'Mine Layer', desc: 'Drops three proximity mines behind you.', cooldown: 10 },
  },
  {
    id: 'warhorse', name: 'Wasteland Warhorse', price: 16000,
    driver: 'Hussain "The Engineer"',
    story: 'Built in secret from refinery steel and stolen military parts, the Warhorse is the machine every clan whispers about. ' +
      'Its driver designed the arena it fights in.',
    stats: { speed: 7, armor: 8, gun: 9, rocket: 9 },
    special: { id: 'barrage', name: 'Rocket Barrage', desc: 'Unleashes eight rockets in a wide fan.', cooldown: 12 },
    model: 'warhorse',
  },
];

export const UPGRADES = [
  { id: 'gun', name: 'Machine Gun', desc: 'Bullet damage' },
  { id: 'rocket', name: 'Rockets', desc: 'Rocket damage and blast' },
  { id: 'armor', name: 'Armor', desc: 'Maximum health' },
  { id: 'speed', name: 'Engine', desc: 'Top speed and acceleration' },
  { id: 'special', name: 'Special', desc: 'Stronger, faster recharge' },
];
export const MAX_UPGRADE = 5;

export function upgradeCost(car, level) {
  const base = 120 + car.price * 0.05;
  return Math.round((base * (level + 1)) / 10) * 10;
}

// Converts 1..10 ratings plus upgrade levels into the numbers the game uses.
export function carStats(car, up = {}) {
  const s = car.stats;
  const m = (k) => 1 + 0.12 * (up[k] || 0);
  return {
    maxSpeed: (12.5 + s.speed * 1.35) * (1 + 0.06 * (up.speed || 0)), // a little slower than before, easier to aim
    accel: (20 + s.speed * 1.6) * m('speed'), // but quicker off the line
    turn: 2.2 + s.speed * 0.06,
    hp: Math.round((70 + s.armor * 15) * m('armor')),
    gunDmg: (1.1 + s.gun * 0.2) * m('gun'),
    rocketDmg: (22 + s.rocket * 3) * m('rocket'),
    rocketRadius: 6 + s.rocket * 0.2 + (up.rocket || 0) * 0.3,
    specialPower: 1 + 0.15 * (up.special || 0),
    specialCooldown: car.special.cooldown * (1 - 0.08 * (up.special || 0)),
    mass: 0.7 + s.armor * 0.08,
  };
}

export const MAPS = [
  {
    id: 'scrapyard', name: 'Scrapyard', layout: 'scrapyard', tag: 'Junk piles and a watchtower',
    desc: 'Dumpsters, cages and tarp-covered drums around an old watchtower. Plenty of cover, short sight lines.',
    size: 110, ground: 0x4f4032, groundAlt: 0x3b2f25, fog: 0x7d6a58, skyTop: 0x3b3f4a, light: 0xffcf9a, skyLight: 0xffe6c8, concrete: 0,
  },
  {
    id: 'refinery', name: 'Refinery', layout: 'refinery', tag: 'Fuel tanks ready to blow',
    desc: 'Concrete pads, storage tanks, gas carts and rows of fuel barrels. One stray rocket and the whole row goes up.',
    size: 120, ground: 0x55524c, groundAlt: 0x44413c, fog: 0x8b9099, skyTop: 0x41505f, light: 0xe6ecff, skyLight: 0xdfe8ff, concrete: 0.8,
  },
  {
    id: 'dustbowl', name: 'Dust Bowl', layout: 'dustbowl', tag: 'Open ground, rock pillars',
    desc: 'A dried lake bed broken by rock pillars, barrier lines and a lonely outpost. Fast cars rule here.',
    size: 130, ground: 0xb08a5a, groundAlt: 0x9c7a4f, fog: 0xd8b98d, skyTop: 0x8fa3b8, light: 0xffe2b0, skyLight: 0xfff0d8, concrete: 0,
  },
  {
    id: 'shanty', name: 'Shanty Town', layout: 'shanty', tag: 'Three towers, tight streets',
    desc: 'Three scrap towers form a ring around the market square. Every corner is an ambush.',
    size: 115, ground: 0x4a3d33, groundAlt: 0x372d26, fog: 0x5d5560, skyTop: 0x241f2c, light: 0xffb27a, skyLight: 0xd9b8a8, concrete: 0.45,
  },
  {
    id: 'outpost', name: 'The Outpost', layout: 'outpost', tag: 'Fight around the fortress',
    desc: 'A fortified tower inside a ring of concrete barriers with two gates. Circle it, breach it, hold it.',
    size: 120, ground: 0x6b5a45, groundAlt: 0x574837, fog: 0xa38f7a, skyTop: 0x4d5868, light: 0xffd9a8, skyLight: 0xffeedd, concrete: 0.42,
  },
];

export const DIFFICULTY = [
  { id: 'easy', name: 'Rookie', enemies: 3, dmg: 0.5, accuracy: 0.45, aggression: 0.6, focus: 1.15, level: 0, hp: 0.75, maxPrice: 1800, reward: 1, base: 100 },
  { id: 'normal', name: 'Veteran', enemies: 4, dmg: 0.72, accuracy: 0.65, aggression: 0.8, focus: 0.95, level: 1, hp: 0.9, maxPrice: 4500, reward: 1.6, base: 160 },
  { id: 'hard', name: 'Warlord', enemies: 5, dmg: 0.9, accuracy: 0.85, aggression: 1, focus: 0.8, level: 2, hp: 1, maxPrice: 99999, reward: 2.5, base: 250 },
];

export const KILL_REWARD = 18;
export const START_POINTS = 300;

// Daily contracts: three per day, picked from these templates with a seed from the date.
export const CONTRACTS = [
  { id: 'kills', text: 'Wreck {n} cars', goals: [5, 8, 12], reward: 22 },
  { id: 'rocketKills', text: 'Wreck {n} cars with rockets', goals: [2, 3, 5], reward: 55 },
  { id: 'barrels', text: 'Blow up {n} fuel barrels', goals: [4, 6, 10], reward: 30 },
  { id: 'airdrops', text: 'Grab {n} airdrops', goals: [1, 2, 3], reward: 110 },
  { id: 'streak', text: 'Score a Double Wreck', goals: [1], reward: 180 },
  { id: 'bounty', text: 'Claim {n} bounties', goals: [1, 2], reward: 120 },
  { id: 'winMap', text: 'Win a match on {map}', goals: [1], reward: 200 },
  { id: 'winVet', text: 'Win on Veteran or Warlord', goals: [1], reward: 260 },
  { id: 'wave', text: 'Reach wave {n} in Survival', goals: [4, 6, 8], reward: 45 },
];
