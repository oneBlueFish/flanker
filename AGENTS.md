# Flankers — AGENTS.md

## Project
Godot 4 hybrid FPS/RTS game. Single-player and multiplayer (up to 10 players via ENet). No editor GUI workflow — all scene/resource edits are done by hand in `.tscn`/`.tres` files or via GDScript runtime generation.

## Commands
```bash
make           # stop + relaunch + show logs (default)
make run       # launch + wait 8s + show logs
make stop      # kill running instance
make logs      # print /tmp/flankers.log
```
Game binary: `/usr/bin/godot` (system install, 4.6.2). No `./godot` or `bin/godot` symlink in repo.

## Architecture

### Autoload
- `LaneData` — global singleton, all lane path data. Use `LaneData.get_lane_points(i)` / `get_lane_waypoints(i, team)`
- `TeamData` — global singleton, team points/currency tracking. Use `TeamData.get_points(team)` / `TeamData.add_points(team, amount)` / `TeamData.spend_points(team, amount)`
- `NetworkManager` — ENet multiplayer peer management. `start_host(port)` / `join_game(address, port)` / `close_connection()`. Emits `peer_connected`, `peer_disconnected`, `connected_to_server`, `connection_failed`, `server_disconnected`
- `LobbyManager` — lobby state, player registry, role claims, game start orchestration. Handles bullet/minion/tower spawn sync RPCs and player transform broadcast. `start_game(path)` broadcasts seed via `notify_game_seed.rpc` then loads scene on all peers
- `GameSync` — in-game state: player healths, teams, spawn positions, respawn countdowns. `damage_player(peer_id, amount, source_team)` handles death + escalating respawn timer

### Runtime-generated nodes
Most geometry is built at runtime in `_ready()` — no pre-baked meshes:
- `TerrainGenerator.gd` — procedural 200×200 mesh + `HeightMapShape3D` collision, new seed each launch
- `LaneVisualizer.gd` — dirt ribbon meshes along lane curves
- `LampPlacer.gd` — street lamp nodes placed along lane sample points. Each lamp is a `StaticBody3D` with a `SphereShape3D` hitbox on the bulb only. Exposes `lamp_scripts: Array` for darkness queries
- `ShootableLamp.gd` — script node attached to each lamp. Holds refs to `OmniLight3D`, bulb `MeshInstance3D`, bulb `StandardMaterial3D`. `shoot_out()` triggers flicker-then-dark; auto-restores after 15s via `_process`
- `FencePlacer.gd` — fence panels placed along both edges of each lane at regular spacing. Random gaps (20% chance). Each panel is a `StaticBody3D` on collision layer 2. Randomly spawns torches (15% chance, min 12 units apart) with `OmniLight3D` + `GPUParticles3D` flame effect
- `WallPlacer.gd` — scatter walls and crates in 20 random off-lane clearings. Avoids lane edges, secret paths, and base zones. Uses kenney_fantasy-town-kit walls + kenney_blaster-kit crates. Emits `done` signal when finished (awaited by loading screen)
- `TreePlacer.gd` — procedural trees along lane edges (11275 trees per run). Supports `menu_density` override for lighter start-menu background
- `Tower.gd` — towers have no prebaked meshes, setup() generates at runtime
- `FogOverlay.gd` — full-map `MeshInstance3D` at y=25 driven by `FogOfWar.gdshader`. `update_sources(player_pos, player_radius, minion_positions, minion_radius, tower_positions, tower_radius)` pushes up to 64 visibility sources as `vec4` array to the shader

### Scene tree (Main.tscn)
```
Main (Node, Main.gd)
  World (Node3D)
    Terrain (StaticBody3D, TerrainGenerator.gd)
    LaneVisualizer (Node3D, LaneVisualizer.gd)
    LampPlacer (Node3D, LampPlacer.gd)
    FencePlacer (Node3D, FencePlacer.gd)
    WallPlacer (Node3D, WallPlacer.gd)
    TreePlacer (Node3D, TreePlacer.gd)
    FogOverlay (MeshInstance3D, FogOverlay.gd)
    SunLight (DirectionalLight3D)
    WorldEnvironment → assets/{day,dusk,night}_environment.tres
    BlueBase / RedBase (Node3D → Base.tscn + OmniLight3D)
  FPSPlayer_<peer_id> (CharacterBody3D, FPSController.gd)  ← spawned at runtime
  RTSCamera (Camera3D, RTSController.gd)
  MinionSpawner (Node, MinionSpawner.gd)
  BuildSystem (Node, BuildSystem.gd)
  RemotePlayerManager (Node, RemotePlayerManager.gd)  ← multiplayer only
  HUD (CanvasLayer)
    Crosshair (Control) ← hidden in RTS mode / Supporter role
      ReloadBar (ProgressBar)
    PointsLabel (Label) ← team points display
    HealthBar (ProgressBar)
    StaminaBar (ProgressBar)
    AmmoLabel (Label)
    ReloadPrompt (Label)
    WeaponLabel (Label)
    RespawnLabel (Label)
    ModeLabel (Label)
    WaveInfoLabel (Label)
    WaveAnnounceLabel (Label)
    GameOverLabel (Label)
    HUDOverlay (Control)
      EntityHUD (Node, EntityHUD.gd)
    Minimap (Control, Minimap.gd)
    PauseMenu (Control, PauseMenu.gd)  ← hidden until Esc
  AudioModeSwitch (AudioStreamPlayer)
  AudioWave (AudioStreamPlayer)
  AudioRespawn (AudioStreamPlayer)
```

Additional scenes not in Main.tscn:
- `StartMenu.tscn` — host/join/local-play UI with cinematic orbiting camera (`MenuCamera.gd`) and a live menu-world terrain background. Shown before game loads.
- `Lobby.tscn` — pre-game lobby listing players by team with ready/start controls (`Lobby.gd`)
- `LoadingScreen.tscn` — progress bar overlay shown during scene setup (`LoadingScreen.gd`). Reports steps via `LoadingState.report()`
- `RoleSelectDialog.tscn` — in-game role picker (Fighter / Supporter). One Supporter slot per team; server validates and rejects duplicates (`RoleSelectDialog.gd`)
- `RemotePlayer.tscn` — ghost representation of a remote peer. Lerps to server-broadcast position/rotation, drives walk/idle animation from movement speed (`RemotePlayerGhost.gd`)
- `Cannonball.tscn` — ballistic tower projectile with splash damage and impact particles (`Cannonball.gd`)
- `PauseMenu.tscn` — Resume / Leave game buttons (`PauseMenu.gd`)

### Key data flows
- `Main.gd._ready()` detects `NetworkManager._peer != null` → chooses single-player or multiplayer path
- `Main.gd._on_start_game()` awaits `$World/TreePlacer.done` and `$World/WallPlacer.done` before proceeding, driving the loading screen progress bar
- Multiplayer game start: `LobbyManager.start_game(path)` → broadcasts `notify_game_seed.rpc` (sets `GameSync.game_seed` + calls `LaneData.regenerate_for_new_game()` on all peers) → `load_game_scene.rpc` → all peers change scene
- `Main.gd._setup_hud_for_player()` passes `$HUD/Crosshair/ReloadBar`, `$HUD/HealthBar`, `$HUD/StaminaBar`, `weapon_label`, `ammo_label`, `reload_prompt` to `fps_player`
- Bullets spawned into `get_tree().root.get_child(0)` (scene root) — not parented to shooter
- Multiplayer shot path: `FPSController` → `LobbyManager.validate_shot.rpc_id(1, ...)` with `hit_info` dict → server applies damage, calls `apply_player_damage.rpc` on target, calls `spawn_bullet_visuals.rpc` on all clients
- Minions added via `add_child` — set `minion.set("team", team)` **before** `add_child` so `_ready()` sees the correct value
- `MinionAI._ready()` calls `add_to_group("minions")` and defers visuals via `call_deferred("_init_visuals")`
- Remote player positions: `FPSController` → `LobbyManager.report_player_transform.rpc_id(1, ...)` → server calls `broadcast_player_transform.rpc` → `GameSync.remote_player_updated` signal → `RemotePlayerManager` creates/updates `RemotePlayerGhost` nodes
- Avatar chars: `Main._pick_minion_characters()` → `LobbyManager.report_avatar_char.rpc_id(1, char)` → server updates `players` dict and `sync_lobby_state.rpc` → `RemotePlayerGhost._try_load_avatar()` reads on `lobby_updated`
- RPC sender ID: `get_remote_sender_id()` returns 0 when the server calls an RPC on itself. Always use `_sender_id()` helper in `LobbyManager` which maps 0 → 1 (server peer id)

## GDScript gotchas
- **Always use explicit types** when RHS could be Variant: array reads, ternary, `min()`/`clamp()` return values. `:=` on these causes parse errors.
  ```gdscript
  var x: float = some_array[i]   # correct
  var x := some_array[i]         # breaks if array is untyped Array
  ```
- `var outer: float = 1.0 + expr` — not `var outer := 1.0 + expr` when expr involves division of floats
- Loop variables go out of scope immediately after the loop — capture needed values before exiting
- `is_node_ready()` does not protect `@onready` vars from null — use explicit null checks
- `@onready` on dynamically spawned nodes (e.g. minions via `add_child`) must be accessed via `call_deferred`
- Autoload scripts must `extends Node`
- **RPC sender ID on server**: `multiplayer.get_remote_sender_id()` returns 0 when the server invokes an RPC locally. Use the `_sender_id()` pattern:
  ```gdscript
  func _sender_id() -> int:
      var id := multiplayer.get_remote_sender_id()
      return id if id != 0 else 1
  ```
- **Role slots**: only one Supporter per team. Server validates `set_role_ingame` and rejects with `_notify_role_rejected.rpc_id(id, ...)` if slot is taken
- **Seed guard**: `LobbyManager.start_game` never sends seed=0 (TerrainGenerator falls back to random seed, causing client/server divergence)

## Terrain
- `HeightMapShape3D` collision scale must be `col_shape.scale = Vector3(step, 1.0, step)` where `step = GRID_SIZE / GRID_STEPS`
- Triangle winding for upward normals (y-up right-handed): `tl→tr→bl` and `tr→br→bl`
- Height application order per vertex: lane flatten → secret path flatten → base zone flatten → plateau lift → peak lift → color

## Bullets
- Physics done manually in `_process` (not `_physics_process`) — no `RigidBody`, no `CollisionShape`
- Collision via `PhysicsRayQueryParameters3D` raycast between prev and current position each frame — avoids tunnelling
- Friendly fire disabled in `Bullet.gd._should_damage()` — single source of truth, not in individual `take_damage()` methods
- Player `shooter_team = -1`, minions pass their `team` int

## Cannonball
- Fired by towers (`TowerAI.gd`). Ballistic arc computed in `_ready()`: x/z constant velocity, y overcomes gravity over `FLIGHT_TIME = 2.5s`
- Splash radius 3 units, splash damage = 50% of direct hit damage
- Friendly fire disabled via same `_should_damage()` pattern as `Bullet.gd`
- Impact spawns `GPUParticles3D` burst then frees itself

## Map layout
- Map: 200×200 units. Blue base z=+82, Red base z=-82
- Lanes: Left (`x≈-85`), Mid (straight), Right (`x≈+85`) — cubic Bézier, 40 sample points each
- Mountain/off-lane band: `|x|` 15–80
- Biome split (grass vs desert) is seeded: `seed % 2 == 0` → grass left (`x<0`), else flipped
- Peaks reach height 22 (snow line 13) — physically impassable, jump velocity is 6
- Plateaus max height ~7 — reachable, used as sniper nests

## Game Features
- **Dual Mode**: Fighter role switches between FPS shooting and RTS tower placement (Tab). Supporter role is RTS-only; no Tab switching
- **Player Roles**: Fighter (FPS combat + optional RTS) or Supporter (RTS-only tower placement). One Supporter slot per team, server-enforced. Role selected at game start via `RoleSelectDialog`
- **Multiplayer**: ENet-based, up to 10 players. Host/join from `StartMenu`. Lobby screen with team display and ready checks. Seed broadcast ensures identical procedural map on all clients. Server is authoritative for shot damage, minion state, tower placement, and team points
- **Remote Player Ghosts**: Other players shown as `RemotePlayerGhost` nodes with lerped position/rotation (speed 15). Animation driven by actual movement speed (walk/idle). Hitbox is a `StaticBody3D` with `ghost_peer_id` meta for server-side raycast identification
- **Character Avatars**: Kenney blocky-characters GLB models. Three random characters picked per game: blue minions, red minions, local player. Avatar char reported to server and synced to all peers via `LobbyManager`
- **Respawn System**: On death, player switches to RTS camera and waits. Respawn time = `RESPAWN_BASE (5s) + death_count × RESPAWN_INCREMENT (5s)`. In multiplayer, death count tracked in `LobbyManager.player_death_counts`
- **Wave System**: Minion waves spawn every 30 seconds with escalating numbers (max 6 per lane)
- **Procedural Generation**: Each game has unique map layout with peaks, plateaus, secret paths
- **Physics-based Bullets**: Realistic gravity with different speeds for player (280 m/s) vs minions (120 m/s)
- **Cannonball Towers**: Tower projectiles use ballistic arcs with splash damage (radius 3 units)
- **Team Resource System**: Currency based on team points for tower placement. Synced to all clients via `LobbyManager.sync_team_points.rpc`
- **Minion AI**: Pathfinding, strafing, separation steering, and ranged combat
- **Time-of-Day**: `Main.time_seed` (0=sunrise, 1=noon, 2=sunset, 3=night) set once at game start. Lamps off at noon, on otherwise
- **Shootable Street Lamps**: Bulb-only `SphereShape3D` hitbox. `Bullet.gd` checks `is_lamp` meta on hit `StaticBody3D` → calls `ShootableLamp.shoot_out()`. Flicker on shoot-out and on restore (15s timer)
- **Fence + Torch**: Procedural wooden fence panels line both edges of each lane. Random 20% gaps. 15% of panels have a torch (OmniLight3D + GPU particle flame) spaced at least 12 units apart
- **Cover Objects**: `WallPlacer` scatters walls and crates across 20 randomly placed clearings in off-lane areas. Clearings avoid lanes, secret paths, and bases
- **Darkness Mechanics**: `MinionAI._is_in_darkness(pos)` walks `LampPlacer.lamp_scripts` — if no lit lamp within 22 units, pos is dark. Dark targets: detect range 12→5, shot miss chance 60%
- **Fog of War**: `FogOverlay.gd` + `FogOfWar.gdshader` — full-map mesh at y=25. Up to 64 visibility sources (player, allied minions, towers) clear circles in the fog. Updated each frame via `update_sources()`
- **Entity Health Bars**: Visible only when zoomed (`camera.fov < 55`), within 75 units, and with clear line-of-sight (occlusion raycast in `EntityHUD.process_entity_hud`)
- **Loading Screen**: `LoadingScreen.tscn` shown during world setup. Progress driven by `LoadingState.report()` and awaited signals from `TreePlacer.done` / `WallPlacer.done`
- **Pause Menu**: `Esc` toggles pause. Pauses player input, shows Resume/Leave buttons. Leave exits to `StartMenu.tscn` and closes network connection if multiplayer
- **Weapon Pickups**: 3 lane-midpoint pickups + up to 17 random mountain-area pickups. Respawn after 90 seconds at same position (or nearby if occupied)

## Adding new input actions
Register in `project.godot` `[input]` section using the existing Object serialization format. Physical keycodes for common keys:
- Shift = `4194325`, Ctrl = `4194326`, Tab = `4194320`, Space = `32`
- Mouse button 1 = LMB, button 2 = RMB
