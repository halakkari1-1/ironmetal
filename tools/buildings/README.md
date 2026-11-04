Light versions of the skyline buildings (assets/buildings/lo). The originals are ~100k triangles each with their
texture cut into thousands of tiny pieces, which made them most of what the arena drew every frame.

1. `lowpoly.gd` (run inside Godot) merges vertices, simplifies the shape and gives it a new UV layout:
   `-- 12000` for the light version, `-- 24000 _mid` for the detailed one.
2. `bake.py` paints the new textures from the original model:
   `python3 bake.py godot/assets/buildings tools/buildings godot/assets/buildings/lo 1024` (and `2048 _mid`),
   then convert the PNGs to JPG.
