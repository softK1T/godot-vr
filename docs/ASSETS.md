# Free assets for the forest-house scene (all CC0 / free commercial)

| Pack | Link | Format | Use |
|---|---|---|---|
| KayKit Forest Nature Pack (free tier, 100+ models) | https://kaylousberg.itch.io/kaykit-forest | GLTF/GLB | trees, bushes, rocks, grass |
| Quaternius Ultimate Nature Pack (150 models) | https://quaternius.com/packs/ultimatenature.html | FBX/OBJ/Blend | trees, foliage |
| Quaternius Stylized Nature MegaKit (110+) | https://quaternius.com/packs/stylizednaturemegakit.html | GLTF/FBX/OBJ | ghibli-style forest |
| Kenney Nature Kit | https://kenney.nl/assets/nature-kit | GLTF/OBJ | modular trees + house parts |
| Kenney Survival Kit | https://kenney.nl/assets/survival-kit | GLTF/OBJ | wooden cabin, crates, campfire |
| Free Forest Nature Pack (60 glb) | https://hooray4brains.itch.io/free-forest-nature-pack | GLB | drop-in low poly trees |
| ambientCG (ground/bark/wood PBR) | https://ambientcg.com | PNG/JPG | textures for ground + house |
| Poly Pizza (CC0 model search) | https://poly.pizza | GLB/FBX | single props |

## How to plug them in
1. Unzip into `assets/external/<packname>/` (GLB preferred — Godot imports it directly).
2. Open `scenes/main.tscn`, select the `Forest` node.
3. Drag a tree `.glb` (or a .tscn made from it) into the `Tree Scene` export slot.
4. Tick `Regenerate` in the inspector — the scatter rebuilds using that model instead of the procedural placeholder.
5. For the house: replace `scenes/house.tscn` content with a cabin GLB, keep the `Body/Collision` node.
