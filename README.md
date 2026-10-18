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

Nine vehicles, all Meshy-made models (about 30K triangles each, textures 1024/512). Data lives in `src/data.js`;
each model is `assets/models/<id>.js` (base64 GLB, loaded on demand).

| Vehicle | Class | Price | Ability (real gameplay effect) | Weakness |
| --- | --- | ---: | --- | --- |
| WASTELAND GHOST | Medium, 5.2 m | free | Smoke Screen: enemies lose you for 3.5 s, speed burst | No specialty |
| QUEEN VENOM | Sports, 4.7 m | 1,500 | Venom Dash: 2x speed, half damage for 1.3 s | Low durability |
| TOXIC VIPER | Sports, 4.8 m | 2,000 | Toxic Cloud: 9 m zone, 14 HP/s for 6 s | Escapable damage over time |
| MEGALODON | Medium, 5.3 m | 2,500 | Riptide: forward wave, pushes and spins out cars 1.5 s | Close range only |
| BLUE SIREN | Armored, 5.4 m | 3,000 | Shock Pulse: 16 m, slows 50% and jams guns 2.5 s | Slower than sports cars |
| YELLOW REAPER | Tracked, 6.0 m | 3,500 | Reaper Charge: ram with heavy impact damage | Slow, poor turning |
| REX RAMPAGE | Monster, 5.8 m | 4,000 | Tail Whip: 10 m spin, damage and knockback | Must get close |
| BLOOD TITAN | Tank, 6.4 m | 4,500 | Titan Shell: slow 85-damage shell, path shown in red | Slow, long recharge |
| IRON COLOSSUS | Heavy carrier, 7.0 m | 5,000 | Bulwark: 70% less damage for 5 s | Slowest, hardest to turn |

Saves from the old eight-car roster are migrated once: ownership and upgrades move to the matching new car,
the Warhorse purchase is refunded (its model is now the free Ghost), and the old save is kept as a backup key.

Optional recorded sounds: set `sound.files.engine` / `sound.files.ability` on a car in `src/data.js` to a file
name in `assets/sfx/` (for example `venom-engine.ogg`, `venom-ability.ogg`). Without them the synthesized
per-car engine, gun and ability sounds play.

Arenas: Scrapyard, Refinery, Dust Bowl, Shanty Town, The Outpost. Difficulty: Rookie, Veteran, Warlord.

Balance tools: `tools/matchups.mjs` (nine-car AI free-for-all), `tools/balance.mjs` (one car vs each difficulty), `tools/vehicles.mjs` (every car: model, driving, guns, ability effect).

## Running it

It's a static web game (three.js r160, vendored). Serve the folder and open `index.html`:

```
python3 -m http.server 8000
```

Music: the lobby track is "THE COST" by Kill Dyll. A commercial release needs the artist's permission or a license.

Controls: on-screen joystick and buttons on touch screens; W A S D, Space (fire), F (rocket), E (special), Esc (pause) on keyboard.

## Environment kit

`assets/kit/` holds the post-apocalypse kitbash sample by Oleg Ushenok (Fab Standard License), converted for mobile:
the 331-part FBX was split into a watchtower (49k triangles near, 15k far) and 18 props (500-3,400 triangles each),
packed as base64 GLBs in `kit_models.js`. All pieces share one 2K/1K texture atlas. The conversion pages live in the
session workspace, not in this repo.

## Android build

Every push to `main` runs `.github/workflows/android.yml` on GitHub's servers and publishes
`IronMetal-<version>.apk` (install directly) and `.aab` (for Google Play) on the Releases page.

App id: `com.alakkari.ironmetal`. Landscape only, full screen, screen kept awake.
Release signing uses four repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Without them the build is signed with a temporary debug key.

Icon and splash sources live in `resources/`; they are rendered from `tools/brand.html` with `tools/brand.mjs`.

## Code map

- `src/main.js` — renderer, garage showroom, menus, HUD, input, match lifecycle
- `src/game.js` — a match: driving, collisions, weapons, specials, AI, pickups
- `src/cars3d.js` — loads and places the vehicle models (the old procedural builders remain as a fallback)
- `src/arena.js` — arena layouts and obstacles
- `src/kit.js` — environment kit loader: building LODs, props, atlas-textured containers, tanks and barrels
- `src/fx.js` — particles, explosions, flashes
- `src/audio.js` — synthesized sound effects and riffs, plus the lobby track in `assets/music/lobby.mp3`
- `src/i18n.js` — English and Arabic text (English strings are the keys)
- `src/data.js` — cars, stats, upgrades, maps, difficulty, economy
- `src/save.js` — progress saved on the device
- `src/quality.js` — graphics tiers and adaptive resolution
- `tools/` — model optimizers and headless playtest scripts

## Roadmap

- [x] Garage with 8 cars, upgrades, battle history
- [x] Three arenas, AI opponents, specials, pickups, sound
- [x] Bloom lighting, textured fire and smoke, flying debris and wrecks, scorch marks
- [x] Procedural metal soundtrack and fire logo
- [x] Variety: kill streaks, bounty target, airdrops (Railgun, Napalm, Mini Nuke), arena events (artillery, tank rupture, sandstorm), daily contracts, Survival mode
- [x] Android build: Capacitor wrapper, built by GitHub Actions on every push (APK + AAB on the Releases page)
- [x] Adaptive resolution for phones and 12" tablets, graphics and control-size settings
- [x] Five arenas and the garage lobby built from the environment kit (watchtower with LODs, 18 props, containers, tanks)
- [x] Three lives per car, the crown follows the kill leader, 5-minute deathmatch clock
- [x] Industrial district outside the walls (warehouses, smoking chimneys, tank farms, container stacks; two draw calls)
- [x] Smoother steering, three control schemes (Direction, Classic, Auto gas), touch button layout editor
- [x] Lobby music track, volume sliders (master, music, effects)
- [x] Light glass UI, Arabic language with the Cairo font and a mirrored right-to-left lobby
- [x] Nine Meshy vehicles with their own abilities, sounds, prices and balance
- [ ] More arenas
