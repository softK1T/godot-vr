# Godot VR Survival

A calm low-poly survival game for desktop and WebXR, built with Godot 4 (Compatibility renderer).
Chop trees, mine stone, forage, farm, build fences, gates and bridges, fish in the lake and keep warm by the stove
while days, rain and seasons pass.

## Running

- **Desktop:** open the folder in Godot 4 and press F5 (main scene `scenes/main.tscn`).
- **WebXR:** export with the Web preset in `export_presets.cfg` and serve over HTTPS. See [WEBXR.md](WEBXR.md) for setup and headset controls.

## Desktop controls

Input map actions from `project.godot`:

| Action | Keys |
|---|---|
| `move_forward` | W, Up |
| `move_backward` | S, Down |
| `move_left` | A, Left |
| `move_right` | D, Right |
| `interact` | E |
| `eat_food` | F |

Extra keys handled directly in scripts:

| Key | Action |
|---|---|
| E | Interact (doors, light switch, stove fuel, harvesting prompts) |
| C | Cook at a lit stove (fries a raw fish if you have one, otherwise 2 vegetables into a stew) |
| G (hold / release / press) | Fishing: hold to preview the cast on water, release to cast, press when a fish bites |
| B (hold / release) | Bridge building: hold to preview a 2 m section, release to build |
| Shift + F8 (hold 2 s) | Start a new game |

The hotbar and crafting hints are shown in the HUD; follow the on-screen prompts.

## WebXR controls

Movement, grabbing and interaction are described in [WEBXR.md](WEBXR.md).
Fishing uses the **B / Y** button on a controller (hold to aim, release to cast, press on a bite).
Bridge building is currently desktop-only.

## Survival loop

- Vitals: health, hunger, warmth and stamina. Rain soaks you outside; dry off indoors or next to the stove.
- Gather berries and mushrooms, chop trees (axe) and mine stone (pickaxe). Plant saplings.
- Build farm beds, plant seeds and harvest vegetables; protect them with fences and gates (hammer).
- Keep the stove fuelled with wood for heat; cook stew or fry fish for the best food.

## Crafting

| Item | Ingredients |
|---|---|
| Building hammer | 3 wood, 2 sticks |
| Stone axe | 5 wood, 3 stone |
| Stone pickaxe | 4 wood, 6 stone |
| Farm bed | 6 wood, 2 stone |
| Wooden gate | 8 wood, 2 stone |
| Fishing rod | 2 wood, 3 sticks |

## Fishing

1. Craft a fishing rod and walk to the river or lake (the Quiet Bay is a good spot).
2. Hold **G**: a ring shows where the bobber will land. Release to cast.
3. Wait 4-10 s (bites come a little faster in the rain). When the bobber dips and the prompt appears, press **G** within about 1.3 s.
4. Fry raw fish on a lit stove with **C**. Fried fish restores hunger and some warmth.

## Building bridges

Have a hammer and 4 wood per section. Hold **B** facing the water: the preview is green when valid and red otherwise.
Sections can only be placed over water, snap to the end of an existing bridge and have solid deck and rail collision.

## Saves

- The main save (`save_system.gd`) is written atomically (temp file + rename) with a `.bak` backup; if the JSON is
  corrupted the backup is loaded. Procedural objects are tracked by generation index, built objects by unique IDs.
- Bridges are stored in `user://bridges.json`, player trails in `user://trails.json` (both written atomically).
- Hold Shift + F8 for 2 seconds to start a new game (this also clears bridges and trails).

## Landmarks

An old boulder, a fallen tree, the Old Lookout on the highest hill and the Quiet Bay on the lake shore are generated
deterministically, so they are always in the same places.

## Performance

The terrain mesh and collision are generated at runtime and are not stored in `main.tscn`.
Grass, shoreline plants, trail wear and edge stones use MultiMesh. `WorldOptimizer` adds visibility ranges and
disables shadows on small decor after the world is generated.

## Known limitations

- The hotbar has 12 fixed slots, so the fishing rod and fish are not shown there (fishing works when the rod is in the inventory; fried fish is eaten with the eat key).
- Bridge sections cannot be removed and cannot be built in WebXR yet.
- Trails never regrow.
- Forest decor is not merged into MultiMesh yet (the optimizer finds no batchable instances in the imported models); trees rely on visibility ranges instead of mesh LOD.
- Fishing, bridges, trails and landmarks were verified only by headless runs, not by a full playtest in VR.
