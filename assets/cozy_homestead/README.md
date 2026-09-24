# Cozy Scandinavian Homestead GLB kit

All meshes use meters, Y-up and face +Z. Every GLB embeds the shared 2048 atlas textures and has no cameras/lights. Fence roots begin at first post x=0; gate root is centered between posts; bed roots are centered. In Godot, make Gate_Leaf_Left and Gate_Leaf_Right Node3D pivots at their hinge axes before attaching animation; the delivered names identify leaf geometry. Plants are separate named meshes under Plants.

Assets: straight/broken fence variants, standalone posts, gate, and four farm-bed growth states. `preview_diorama.glb` is intentionally omitted because it would duplicate geometry; assemble the supplied modules in Godot for a lit preview.

## Pedestrian wicket

`gate_wicket_1_4m.glb`: 1.4 m overall width, 1.28 m post height, single leaf. Rotate the `InteractiveGate/Wicket_Leaf` node about local Y (hinge axis x=-0.605 m). Uses the same embedded 2048 atlas textures as the kit. Generator: `tools/build_wicket.py`.
