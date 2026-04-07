# Missile Attack Arcade

## Tech
- **Engine:** Godot 4.6, GDScript, Forward+ renderer
- **Viewport:** 2560×1440, fullscreen maximized (`window/size/mode=2`), `canvas_items` stretch, `keep` aspect
- **Audio:** Procedural via `AudioStreamWAV` (no external audio files)
- **Cursor:** Procedural crosshair via `Image.create()` + `ImageTexture` (red, bold when locked)
- **Git:** `https://github.com/UriZ/missile-attack-aracde.git` (HTTPS, `http.postBuffer=524288000`). `.gitignore` excludes `.godot/`

## Architecture

### Scenes & Scripts
| File | Purpose |
|------|---------|
| `main.gd` / `main.tscn` | Game controller. Camera2D, UI CanvasLayer (Score, Info, LauncherHUD, GameOver, StartScreen with cover image). Spawns enemies, launchers, terrain. Manages selection, crosshair, screen shake. |
| `launcher.gd` | Base script for all launchers. Turret node tracks mouse (±80° clamp, smooth lerp). `get_launch_position()` fires from turret tip. Selection via `SelectionGlow` + `SelectionLight`. |
| `sam_launcher.tscn` | Hexagonal base + Turret with 3 missile pods |
| `truck_launcher.tscn` | Truck chassis/cab/wheels + Turret with 3 missiles |
| `heat_seeking_launcher.tscn` | Base/platform + Turret with radar + 4 missile tubes |
| `missile.gd` / `.tscn` | Player interceptor. `gravity_force=200`, terrain damage `40/25` |
| `heat_seeking_missile.gd` / `.tscn` | Player heat-seeker. `gravity_force=50`, `tracking_speed=3.0`, nosecone color lerps red on lock |
| `enemy_missile.gd` / `.tscn` | Enemy. `gravity_force=200`, travel time `3.5–5.5s`, terrain damage `75/55`, launcher damage `110/80` |
| `super_missile.gd` / `.tscn` | Parachute bomb. No engine fire, `parachute_speed=35`, `gravity=15` when deployed. Triple explosions, extreme damage (180/130 terrain, 220/150 launcher), crater scale 5–7 |
| `terrain.gd` / `.tscn` | Deformable terrain. Height map with `TERRAIN_WIDTH=2560`, `RESOLUTION=8`. `damage(pos, radius, depth)` carves craters with quadratic falloff |
| `explosion.gd` / `.tscn` | Procedural sound: 3 sine layers (sub-bass/bass/mid), filtered noise, crackle, tanh clipping, pitch drop |
| `mega_explosion.tscn` | Bigger particles, shockwave ring |
| `crater.tscn` | Visual crater mark (OuterRim, MiddleRim, InnerCrater, Scorch, Debris polygons) |

### Key Game Flow
- **Start screen:** Animated title, cover image (`coverimage.png`), emoji rain bg, pulsing PLAY button
- **Gameplay:** 4 launchers at y=1220 (SAM@400, HeatSeeker@900, Truck@1400, SAM@1900). Click to fire. Enemies spawn every 3s, super missiles every 12s.
- **Game over:** All launchers destroyed → overlay with score + PLAY AGAIN

### Selection System
- Launchers have `SelectionGlow` (blue light underneath) + `SelectionLight` (white ground light) instead of old green ring
- LauncherHUD in top-left shows all launchers with selected state
- Heat-seeker selection swaps to red crosshair cursor with lock circle overlay

## See Also
- [DEVPLAN.md](DEVPLAN.md) — Feature backlog (drones, nukes, vulkan cannon, HUD overhaul, tuning)
