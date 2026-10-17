# IronMetal: Wasteland Wars

A mobile 3D vehicular combat game. Armored, scrap-built cars fight in open arenas,
pick up weapons and health, and the last car running wins.

## Team

- **Hussain Al-Akari** — idea, direction, and testing
- **Claude** — design, art pipeline, and programming

## Platform

- Android first (iOS later)
- 3D, built for mid-range phones

## Art pipeline

Car models are generated with Meshy, then prepared for mobile:

1. Generate the car from a reference image
2. Remesh: **Fixed, 30K, Triangle**
3. Texture: **2K, PBR maps on**
4. Download: **GLB, Origin = Bottom, Resize off**
5. Textures are shrunk to 1024 before going into the game

## Roster

| Car | Price | Special |
| --- | ---: | --- |
| Rustbucket | free | Nitro Burst |
| Dune Stinger | 900 | Ram Charge |
| Bulldog | 1,800 | Shockwave |
| Hellfire | 3,000 | Flamethrower |
| Iron Maiden | 4,500 | Iron Shield |
| Viper | 6,500 | Seeker Missiles |
| Juggernaut | 9,500 | Mine Layer |
| Wasteland Warhorse | 16,000 | Rocket Barrage (Meshy model) |

Arenas: Scrapyard, Refinery, Dust Bowl. Difficulty: Rookie, Veteran, Warlord.

## Running it

It's a static web game (three.js r160, vendored). Serve the folder and open `index.html`:

```
python3 -m http.server 8000
```

Controls: on-screen joystick and buttons on touch screens; W A S D, Space (fire), F (rocket), E (special), Esc (pause) on keyboard.

## Code map

- `src/main.js` — renderer, garage showroom, menus, HUD, input, match lifecycle
- `src/game.js` — a match: driving, collisions, weapons, specials, AI, pickups
- `src/cars3d.js` — the seven procedural cars and the Warhorse loader
- `src/arena.js` — arena layouts and obstacles
- `src/fx.js` — particles, explosions, flashes
- `src/audio.js` — synthesized sound (no audio files)
- `src/data.js` — cars, stats, upgrades, maps, difficulty, economy
- `src/save.js` — progress saved on the device
- `tools/` — model optimizers and headless playtest scripts

## Roadmap

- [x] Garage with 8 cars, upgrades, battle history
- [x] Three arenas, AI opponents, specials, pickups, sound
- [x] Bloom lighting, textured fire and smoke, flying debris and wrecks, scorch marks
- [x] Procedural metal soundtrack and fire logo
- [x] Variety: kill streaks, bounty target, airdrops (Railgun, Napalm, Mini Nuke), arena events (artillery, tank rupture, sandstorm), daily contracts, Survival mode
- [ ] Android build (wrap with Capacitor, build the APK in GitHub Actions)
- [ ] Remake the seven procedural cars in Meshy to match the Warhorse
- [ ] Music, more arenas, daily challenges
