// Static game data: vehicles and their abilities, maps, difficulty and economy.

export const LORE =
  'Twenty years after the oil ran dry, the old refineries became arenas. ' +
  'Every season the wasteland clans send their machines to the Iron Cup. ' +
  'Win, and you eat. Lose, and the scrappers strip what is left of you.';

// The nine official vehicles. Everything the game needs about a car lives in its entry, so a new car
// is a new entry plus a model file in assets/models/<id>.js.
// stats are 1..10 and map to real values in carStats(); handling is turning response.
// model: length is the in-game length in metres; muzzles/rocket are points in the model's normalized box
//   (x: -1 left .. 1 right, y: 0 ground .. 1 roof, z: -1 rear .. 1 front).
// special: the ability. duration in seconds, cooldown in seconds, radius in metres where it applies.
// sound: engine timbre (base pitch Hz, waveform, grit 0..1), gun pitch, ability voice; files are optional
//   recordings in assets/sfx/ that replace the synthesized sound when present.
export const CARS = [
  {
    id: 'ghost', name: 'WASTELAND GHOST', price: 0, cls: 'medium',
    desc: 'Ghost of the wasteland. A practical, balanced survival machine that leans on its guns and a short smoke cover to slip out of bad fights.',
    descAr: 'شبح الأراضي المقفرة. مركبة نجاة قتالية عملية ومتوازنة، تعتمد على أسلحتها الأساسية والتمويه المؤقت لتجاوز المواجهات الصعبة.',
    strong: 'Balanced, flexible, easy to drive', weak: 'Not the best at speed, armor or damage',
    stats: { speed: 6, armor: 6, gun: 5, rocket: 6, handling: 6 },
    model: { length: 5.2, muzzles: [[0.05, 0.98, 0.15]], rocket: [0, 0.95, -0.1] },
    special: { id: 'smoke', name: 'Smoke Screen', desc: 'Drops a smoke cloud: enemies lose track of you for 3.5 s and you get a burst of speed.', cooldown: 13, duration: 3.5, radius: 9 },
    sound: { engine: { base: 46, wave: 'sawtooth', grit: 0.75 }, gun: 1, ability: 'smoke', files: { engine: null, ability: null } },
  },
  {
    id: 'venom', name: 'QUEEN VENOM', price: 1500, cls: 'sports',
    desc: 'Queen of speed and evasion. Lives on quick dashes and hit-and-run attacks, but takes less punishment than the heavy machines.',
    descAr: 'ملكة السرعة والمراوغة. تعتمد على الاندفاع السريع والهجمات الخاطفة، لكنها أقل تحملاً للضرر من المركبات الثقيلة.',
    strong: 'Speed and agility', weak: 'Low durability',
    stats: { speed: 10, armor: 5, gun: 6, rocket: 5, handling: 9 },
    model: { length: 4.7, muzzles: [[0.25, 0.95, 0.2], [-0.25, 0.95, 0.2]], rocket: [0, 0.95, -0.2] },
    special: { id: 'dash', name: 'Venom Dash', desc: 'A 1.3 s burst at double speed that also halves incoming damage, to dodge or reposition.', cooldown: 6, duration: 1.3 },
    sound: { engine: { base: 78, wave: 'square', grit: 0.25 }, gun: 1.25, ability: 'dash', files: { engine: null, ability: null } },
  },
  {
    id: 'toxic', name: 'TOXIC VIPER', price: 2000, cls: 'sports',
    desc: 'The poisoned viper. Controls space with short-lived toxic zones that wear down anyone who stays inside.',
    descAr: 'الأفعى السامة. تتحكم بمساحة المعركة عبر مناطق سامة مؤقتة تضعف الخصوم الذين يبقون داخلها.',
    strong: 'Area control, forces enemies to move', weak: 'Damage over time can be escaped',
    stats: { speed: 8, armor: 6, gun: 6, rocket: 5, handling: 8 },
    model: { length: 4.8, muzzles: [[0.3, 0.95, 0.1], [-0.3, 0.95, 0.1]], rocket: [0, 0.95, -0.2] },
    special: { id: 'toxic', name: 'Toxic Cloud', desc: 'Throws a toxic cloud 9 m ahead: 9 m wide, burns 14 HP per second for 6 s.', cooldown: 9, duration: 6, radius: 9 },
    sound: { engine: { base: 70, wave: 'square', grit: 0.4 }, gun: 1.15, ability: 'toxic', files: { engine: null, ability: null } },
  },
  {
    id: 'megalodon', name: 'MEGALODON', price: 2500, cls: 'medium',
    desc: 'The sea predator. Rams and surges to throw enemies off balance, sending them skidding out of control.',
    descAr: 'المفترس البحري. يستخدم هجمات الصدم والاندفاع لإرباك الخصوم ودفعهم إلى الانزلاق وفقدان السيطرة مؤقتاً.',
    strong: 'Surge and disruption', weak: 'Must get close; weak at long range',
    stats: { speed: 7, armor: 6, gun: 6, rocket: 5, handling: 7 },
    model: { length: 5.3, muzzles: [[0.2, 0.92, 0.25], [-0.2, 0.92, 0.25]], rocket: [0, 0.9, -0.2] },
    special: { id: 'riptide', name: 'Riptide', desc: 'A surge forward that blasts a wave ahead (14 m cone): pushes cars away and makes them skid for 1.5 s.', cooldown: 8, duration: 1.5, radius: 14 },
    sound: { engine: { base: 58, wave: 'sawtooth', grit: 0.35 }, gun: 1.05, ability: 'riptide', files: { engine: null, ability: null } },
  },
  {
    id: 'siren', name: 'BLUE SIREN', price: 3000, cls: 'armored',
    desc: 'Field control unit. Electric pulses jam enemy guns and slow them down for a moment.',
    descAr: 'وحدة السيطرة الميدانية. تستخدم النبضات الكهربائية لتعطيل الخصوم وإبطاء حركتهم مؤقتاً.',
    strong: 'Disables enemies, solid armor', weak: 'Slower and less agile than sports cars',
    stats: { speed: 6, armor: 7, gun: 6, rocket: 6, handling: 6 },
    model: { length: 5.4, muzzles: [[0.3, 0.97, 0.1], [-0.3, 0.97, 0.1]], rocket: [0, 0.97, -0.25] },
    special: { id: 'pulse', name: 'Shock Pulse', desc: 'Electric pulse, 16 m around you: enemies are slowed 50% and their guns jam for 2.5 s.', cooldown: 12, duration: 2.5, radius: 16 },
    sound: { engine: { base: 52, wave: 'sawtooth', grit: 0.3 }, gun: 1, ability: 'zap', files: { engine: null, ability: null } },
  },
  {
    id: 'reaper', name: 'YELLOW REAPER', price: 3500, cls: 'tracked',
    desc: 'The yellow reaper. A heavy breaching machine that charges and crashes through enemy defenses.',
    descAr: 'الحصادة الصفراء. مركبة اقتحام ثقيلة تعتمد على الاندفاع والاصطدام لتدمير دفاعات الخصوم.',
    strong: 'Head-on attacks, close fights', weak: 'Slow, poor turning',
    stats: { speed: 4, armor: 8, gun: 6, rocket: 6, handling: 3 },
    model: { length: 6.0, muzzles: [[0.25, 0.98, -0.1], [-0.25, 0.98, -0.1]], rocket: [0, 0.98, -0.3] },
    special: { id: 'ram', name: 'Reaper Charge', desc: 'A 1.4 s charge: anything you hit takes heavy damage and is thrown aside.', cooldown: 9, duration: 1.4 },
    sound: { engine: { base: 34, wave: 'sawtooth', grit: 0.85 }, gun: 0.85, ability: 'charge', files: { engine: null, ability: null } },
  },
  {
    id: 'rex', name: 'REX RAMPAGE', price: 4000, cls: 'monster',
    desc: 'Dinosaur fury. Lives on charges, mechanical strikes and heavy collisions against nearby enemies.',
    descAr: 'غضب الديناصور. يعتمد على الاندفاع والضربات الميكانيكية والاصطدامات القوية لإلحاق الضرر بالخصوم القريبين.',
    strong: 'Close combat, good durability', weak: 'Clumsy turning, must get close',
    stats: { speed: 6, armor: 7, gun: 6, rocket: 5, handling: 5 },
    model: { length: 5.8, muzzles: [[0.2, 0.98, 0.1], [-0.2, 0.98, 0.1]], rocket: [0, 1, -0.1] },
    special: { id: 'whip', name: 'Tail Whip', desc: 'Spins its tail: everything within 10 m takes damage and is knocked back.', cooldown: 10, radius: 10 },
    sound: { engine: { base: 40, wave: 'sawtooth', grit: 0.7 }, gun: 0.95, ability: 'roar', files: { engine: null, ability: null } },
  },
  {
    id: 'titan', name: 'BLOOD TITAN', price: 4500, cls: 'tank',
    desc: 'The red titan. Huge firepower and heavy shots, but its main gun needs good timing and a longer recharge.',
    descAr: 'العملاق الأحمر. يمتلك قوة نارية مرتفعة وضربات ثقيلة، لكن أسلحته الرئيسية تحتاج إلى توقيت جيد وفترات إعادة شحن أطول.',
    strong: 'Damage and explosive attacks', weak: 'Slow, long recharge',
    stats: { speed: 4, armor: 8, gun: 7, rocket: 7, handling: 4 },
    model: { length: 6.4, muzzles: [[0.35, 0.85, 0.3], [-0.35, 0.85, 0.3]], rocket: [0, 0.9, 0.5] },
    special: { id: 'shell', name: 'Titan Shell', desc: 'Main cannon: a slow, huge shell (85 damage, 11 m blast). A red line shows its path, so it can be dodged.', cooldown: 11, radius: 11 },
    sound: { engine: { base: 32, wave: 'square', grit: 0.6 }, gun: 0.8, ability: 'cannon', files: { engine: null, ability: null } },
  },
  {
    id: 'colossus', name: 'IRON COLOSSUS', price: 5000, cls: 'heavy',
    desc: 'The armored giant. Soaks up huge damage and dominates with heavy weapons, at the cost of slow movement and acceleration.',
    descAr: 'العملاق المدرع. يتحمل أضراراً كبيرة ويستخدم تسليحه الثقيل للسيطرة على ساحة المعركة، مقابل بطء الحركة والتسارع.',
    strong: 'High health and armor', weak: 'Slow, hard to turn',
    stats: { speed: 3, armor: 9, gun: 6, rocket: 6, handling: 3 },
    model: { length: 7.0, muzzles: [[0.3, 0.98, 0.25], [-0.3, 0.98, 0.25]], rocket: [0, 0.98, -0.2] },
    special: { id: 'shield', name: 'Bulwark', desc: 'Raises a shield that cuts incoming damage by 70% for 5 s.', cooldown: 16, duration: 5 },
    sound: { engine: { base: 28, wave: 'sawtooth', grit: 0.55 }, gun: 0.75, ability: 'shield', files: { engine: null, ability: null } },
  },
];
// Old roster ids map to the car that replaced them, so saved ownership and upgrades carry over.
export const LEGACY_IDS = { rustbucket: 'ghost', stinger: 'venom', hellfire: 'toxic', bulldog: 'reaper', maiden: 'colossus', viper: 'siren', juggernaut: 'titan', warhorse: 'ghost' };
export const LEGACY_REFUND = { warhorse: 16000 };

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
    maxSpeed: (10.5 + s.speed * 1.1) * (1 + 0.05 * (up.speed || 0)), // tuned down twice after playtests: easier to control and aim
    accel: (17 + s.speed * 1.3) * m('speed'), // still quick off the line
    turn: 1.9 + (s.handling || 6) * 0.11,
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
    size: 132, ground: 0x4f4032, groundAlt: 0x3b2f25, fog: 0x7d6a58, skyTop: 0x3b3f4a, light: 0xffcf9a, skyLight: 0xffe6c8, concrete: 0,
  },
  {
    id: 'refinery', name: 'Refinery', layout: 'refinery', tag: 'Fuel tanks ready to blow',
    desc: 'Concrete pads, storage tanks, gas carts and rows of fuel barrels. One stray rocket and the whole row goes up.',
    size: 142, ground: 0x55524c, groundAlt: 0x44413c, fog: 0x8b9099, skyTop: 0x41505f, light: 0xe6ecff, skyLight: 0xdfe8ff, concrete: 0.8,
  },
  {
    id: 'dustbowl', name: 'Dust Bowl', layout: 'dustbowl', tag: 'Open ground, rock pillars',
    desc: 'A dried lake bed broken by rock pillars, barrier lines and a lonely outpost. Fast cars rule here.',
    size: 150, ground: 0xb08a5a, groundAlt: 0x9c7a4f, fog: 0xd8b98d, skyTop: 0x8fa3b8, light: 0xffe2b0, skyLight: 0xfff0d8, concrete: 0,
  },
  {
    id: 'shanty', name: 'Shanty Town', layout: 'shanty', tag: 'Three towers, tight streets',
    desc: 'Three scrap towers form a ring around the market square. Every corner is an ambush.',
    size: 138, ground: 0x4a3d33, groundAlt: 0x372d26, fog: 0x5d5560, skyTop: 0x241f2c, light: 0xffb27a, skyLight: 0xd9b8a8, concrete: 0.45,
  },
  {
    id: 'outpost', name: 'The Outpost', layout: 'outpost', tag: 'Fight around the fortress',
    desc: 'A fortified tower inside a ring of concrete barriers with two gates. Circle it, breach it, hold it.',
    size: 142, ground: 0x6b5a45, groundAlt: 0x574837, fog: 0xa38f7a, skyTop: 0x4d5868, light: 0xffd9a8, skyLight: 0xffeedd, concrete: 0.42,
  },
];

export const DIFFICULTY = [
  { id: 'easy', name: 'Rookie', enemies: 3, dmg: 0.5, accuracy: 0.45, aggression: 0.6, focus: 1.15, level: 0, hp: 0.75, maxPrice: 2500, reward: 1, base: 100 },
  { id: 'normal', name: 'Veteran', enemies: 4, dmg: 0.72, accuracy: 0.65, aggression: 0.8, focus: 0.95, level: 1, hp: 0.9, maxPrice: 4000, reward: 1.6, base: 160 },
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
