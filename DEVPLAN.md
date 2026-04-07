# Missile Attack Arcade — Development Plan

## Feature Backlog

---

### 1. Launcher Legend / HUD Overhaul
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
- acquiring a target with heat seeking should be more dramatic and fun - the cursor shold be more reactvie
- add the voice "pickle is hot" when a heat missile is acquired (when the cursor reacts)


**Files:** `heat_seeking_missile.gd`, `main.gd` (`spawn_enemy_missile`)

---

### 4. Enemy Drones
**Status:** ✅ Done

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


### 6. vulkan cannon
**Status:** ✅ Done
- Multi-barrel rapid-fire cannon (hold to fire, ~14 rounds/sec)
- Overheat system: heat builds per shot, locks out at 100%, recovers at 30%
- Visual: 3 barrels with rotating barrel group, heat glow overlay, ammo boxes
- HUD: heat bar in top-left, overheat warning label
- Tracer bullets: fast (1800px/s), small explosions on hit, no terrain damage

---

### 7 ui fixes launchers and missiles
- add wheels to the truck, and chains (lime in a tank) to the sam launcher
- when blsting the mega missiles, i want to see a mega blast


### 8 terrain improvements
**Status:** ✅ Done
add improvements to the terrain - add bridges, soldiers, civilian buildings , industry buildings . randomly generate them at the beginning 
### 8.1 terrain improvemetns advanced
- add bigger mountains, canions , vallies, revers... more dramamtic landscape
- add weather scenery - ie. snow, or sun and desert

### 9 wave
**Status:** ✅ Done
- have attack waves of the incoming missiles... generate them, repeat etc

### 10 add sound for outgoing missiles
**Status:** ✅ Done
- add sounds for outgoing missiles
- add sound for vulkan 

### 11 mega missile split 
- create a new type of mega missle. when its hit, it splits into multiple smaller fragments than can cause damage 


### startup 
- fix cover image - play button shouldbe nicer and in center
- add music


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
- [x] Crosshair always visible during gameplay; reactive for heat-seeker (default/heat/locked modes)
- [x] Vulkan cannon with overheat mechanic
