# Missile Attack Arcade — Development Plan

## Feature Backlog

---

### 1. Crosshair Always Visible / Reactive Heat-Seeker Cursor
**Status:** Planned

- Show crosshair cursor at all times during gameplay (not just when heat-seeking launcher is selected)
- Default crosshair: subtle, neutral color (e.g. dim white/gray)
- When heat-seeking launcher is selected: crosshair becomes the current reactive red/locked variant
- When an enemy is within lock range: crosshair snaps to red + locked state with the target ring drawn on screen
- No cursor shown on start screen or game over screen

**Files:** `main.gd` (cursor management, `_on_launcher_selected`, `_process`)

---

### 2. Launcher Legend / HUD Overhaul
**Status:** Planned

- Replace the current launcher HUD panels with a clear, readable sidebar on the left
- Each launcher entry should show:
  - Large vehicle icon / type label (SAM, TRUCK, SEEKER)
  - Color-coded health indicator or "destroyed" state
  - Keyboard shortcut hint (1, 2, 3, 4)
  - Clear SELECTED state — bright highlight border, larger
- Make it obvious which launcher is active at a glance

**Files:** `main.gd` (`build_launcher_hud`, `update_launcher_hud`), `main.tscn` (LauncherHUD node layout)

---

### 3. Enemy Missile & Heat-Seeker Tuning
**Status:** Planned

- Enemy missiles: reduce speed (spawn `launch_time` range from `3.5–5.5s` → `5.0–7.5s`)
- Heat-seeking missiles: increase tracking speed (`tracking_speed` from `3.0` → `5.5`) and increase base velocity slightly
- Heat-seeker gravity: reduce from `50` → `30` so it stays on target better at angles
- Goal: make intercepting with heat-seekers feel rewarding, while giving player more reaction time against enemy missiles

**Files:** `heat_seeking_missile.gd`, `main.gd` (`spawn_enemy_missile`)

---

### 4. Enemy Drones
**Status:** Planned — design phase

- Slow-moving aerial units that fly horizontally across the screen
- Different threat profile from missiles: constant direction, lower altitude, harder to intercept with SAM
- Visual: small angular drone silhouette (polygon art)
- Behavior: fly in from left or right edge, bomb launchers if they pass over them
- Can be intercepted by any launcher type
- Score: lower than missile (simpler threat)

**New files:** `drone.gd`, `drone.tscn`
**Modified files:** `main.gd` (spawn logic, wave system)

---

### 5. Enemy Nukes
**Status:** Planned — design phase

- Rare, devastating weapon — requires multiple hits or a direct heat-seeker lock to intercept
- Visual: large warhead with distinctive shape (wider body, different color scheme)
- Impact: much larger blast radius than super missile, destroys all nearby launchers
- Behavior: slow descent, ballistic — gives player time to respond but demands priority
- Audio: distinct warning sound on spawn
- May require a dedicated "nuke incoming" UI alert

**New files:** `nuke.gd`, `nuke.tscn`
**Modified files:** `main.gd` (spawn logic, wave system), `explosion.gd` or new `nuke_explosion.tscn`

---

## Already Done

- [x] Missiles launching and moving
- [x] Enemy missiles
- [x] Collision / interception
- [x] Defensive structures (SAM, Truck, Heat-Seeker)
- [x] Wave system (timer-based spawning)
- [x] Start screen + play/restart flow
- [x] Super missiles with parachutes
- [x] Procedural explosion sounds
- [x] Deformable terrain
- [x] Screen shake
- [x] Launcher selection HUD (basic)
