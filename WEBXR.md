# Forest House WebXR

## Run
1. Install Godot 4.7 Web export templates.
2. Export the `WebXR` preset to `build/web/index.html`.
3. Host `build/web` over HTTPS (localhost is also accepted for development).
4. Open the URL in a WebXR headset browser and press **ENTER VR**.

## Controls
- Left stick: locomotion relative to headset direction.
- Right stick: 30-degree snap turn.
- Right trigger: interact using the controller ray.
- A/X: next hotbar slot.
- B/Y: use selected item.
- Menu: inventory.

Desktop mouse/keyboard remains available when no WebXR session is active.
