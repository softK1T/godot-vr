# Low-poly modular fence pack

Procedurally generated rustic wooden fence set for Godot 4.

## Included pieces

- `fence_straight_3m.obj` — full 3 m segment
- `fence_straight_1_5m.obj` — half segment
- `fence_corner_3m.obj` — L corner with two 3 m arms
- `fence_gate_3m.obj` — closed gate with iron hinges and latch
- `fence_broken_3m.obj` — damaged variant
- `fence_post.obj` — standalone snap/end post
- `scenes/*.tscn` — ready-to-instance Godot scenes with simple static collisions
- `scenes/fence_pack_preview.tscn` — all elements laid out for inspection

## Scale and snapping

- Units are metres; Y is up.
- Straight modules run from X=0 to X=3 (or X=1.5 for the half piece).
- The corner extends toward +X and +Z.
- Pivots sit at ground level on the left/corner post, so modular placement is easy on a 1.5 m grid.
- Materials are embedded through `fence_materials.mtl`; no textures are required.

## Regenerate

Run `python3 tools/generate_fence_pack.py` from the project root.
