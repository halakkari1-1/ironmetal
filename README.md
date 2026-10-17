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

| Car | Status |
| --- | --- |
| Wasteland Warhorse | Model ready (29K triangles) |

## Roadmap

- [ ] Prototype: drive one car in one arena with touch controls
- [ ] Shooting and pickups
- [ ] Enemy AI
- [ ] More cars and arenas
