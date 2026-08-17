# WorldMaker — orientation for AI coding sessions

A lightweight, web-exportable first-person 3D sandbox in Godot 4.3
(GDScript, GL Compatibility renderer). Players walk around, place/resize/
rotate/delete primitive shapes with texture or solid-color skins, and
save/load builds as JSON. Deploys automatically to `worldmaker.win` (via
Cloudflare R2) on every push to `main`.

**This file is for editing the codebase.** For player-facing setup,
controls, and deploy instructions, read `README.md` — don't duplicate that
here; this file assumes you've skimmed it and is a map + cookbook for
making changes fast without re-deriving the architecture from scratch.

**No Godot binary exists in this environment.** You cannot run the game
to check your work. Verification is: read the diff carefully (this is a
small, consistently-styled codebase — most bugs are visible on inspection),
commit, push to `main`, confirm the `deploy.yml` GitHub Actions run goes
green, then ask the user to check the specific behavior in-browser at
worldmaker.win. Never claim something "works" without one of those two
confirmations.

## File map

```
scripts/
├── autoload/            # global singletons (Project Settings > Autoload, in this order)
│   ├── InputSetup.gd     # MUST stay first -- registers all input actions in code (see below)
│   ├── GameManager.gd    # world_root reference + get_next_id() id counter, that's it
│   ├── SkinManager.gd    # texture/color cache + skin_key -> material resolution (see below)
│   ├── SaveLoadManager.gd# world JSON export/import
│   └── WebFilePicker.gd  # Web-only: <input type=file> picker via JS polling
├── core/
│   └── Main.gd           # composition root -- see "Composition root" below
├── player/
│   ├── PlayerController.gd # WASD/gravity/jump only, no mouse look (CharacterBody3D)
│   └── PlayerCamera.gd     # mouse look only, no movement (Camera3D child)
├── build/
│   ├── ShapeDefinitions.gd    # data table: shapes + their dimension fields (add a shape here)
│   ├── ShapeFactory.gd        # dimensions -> Mesh + Shape3D, surface_offset(), horizontal_half_extents()
│   ├── PlaceableObject.gd     # metadata + to_dict() on every placed object
│   ├── GhostPreview.gd        # translucent placement preview, visual-only
│   └── BuildModeController.gd # raycast, tool cycling, dimension edit, placement, ALL snapping logic
├── terrain/
│   ├── BiomeDefinitions.gd      # data table: biome colors + noise thresholds + dominant_biome() (add a biome here)
│   ├── TerrainNoise.gd          # single source of truth: world (x,z) -> height/normal/color, river carving
│   ├── TerrainChunk.gd          # (chunk_coord, TerrainNoise) -> Mesh + HeightMapShape3D + water for one chunk
│   ├── TerrainStreamer.gd       # loads/frees chunks around the player, see "Infinite terrain" below
│   ├── VegetationDefinitions.gd # data table: tree archetypes + flower dimensions/colors (add an archetype here)
│   └── VegetationFactory.gd     # (chunk_coord, TerrainNoise) -> scattered tree/flower nodes for one chunk
└── ui/
    ├── UIRoot.gd          # builds PauseMenuUI + BuildHUD + Crosshair, no logic
    ├── PauseMenuUI.gd     # Esc menu -- see "Procedural UI pattern" below
    ├── BuildHUD.gd        # bottom-of-screen status text, signal listener only
    ├── CircleButton.gd    # reusable round button (3 content modes, see below)
    └── Crosshair.gd       # decorative center dot, no logic

scenes/
├── Main.tscn   # Environment, SunLight, Terrain, World (empty container GameManager fills), Player, UI
└── Player.tscn # CharacterBody3D > Camera3D > RayCast3D + BuildController > GhostPreview

project.godot          # autoload order above; run/main_scene=Main.tscn; renderer=gl_compatibility
export_presets.cfg     # single "Web" preset; wires web/local-data-bridge.js via html/head_include
web/local-data-bridge.js  # window.wmPickFile()/window.wmFileResult -- see WebFilePicker.gd's docstring
.github/workflows/deploy.yml  # push to main -> godot --export-release "Web" -> aws s3 sync to R2
```

Every script is single-responsibility and either reaches an autoload
(global by design) or emits a signal without knowing who listens.
`ShapeDefinitions`/`ShapeFactory` are the only place shape-specific data
lives — adding a 6th primitive is one `DEFS` entry plus one `match` branch
per `ShapeFactory` function, nothing else.

## Core systems, explained for extension

### Placement/snapping pipeline (`BuildModeController.gd`)

`_process_place_target()` runs every physics frame and picks **one** of
three cases, checked in this priority order, each writing
`_target_position`/`_target_yaw`/`_target_tilt` for `_place_current()` to
read back verbatim later (so the ghost preview and the actually-placed
object can never drift apart):

1. `_compute_plane_edge_snap(target, hit_point)` — only when placing a
   Plane and the raycast hit an already-placed Plane. Works entirely in
   the target's own local frame (`target.to_local()`/`to_global()`), so it
   honors however the target is currently rotated. **This is the template
   to copy for any new shape-pair-specific snap rule.**
2. `_compute_wall_mount(point, normal)` — only when placing a Plane and
   the hit surface is wall-like (mostly-horizontal normal).
3. `_compute_default_placement(point, normal)` — everything else. Uses
   `ShapeFactory.surface_offset()` (flush distance along whichever axis
   the hit normal is dominant in) and `_snap_flush_position()` (snaps the
   shape's own *edge* to the grid, not its center — see that function's
   docstring; this is a correctness fix, not a toggleable assist, unlike
   the grid/rotation snapping which `snap_enabled` gates).

**Worked example — "make the cone snap to the top of the cylinder":** add
a new case ahead of the default, gated on `current_shape_id ==
ShapeType.CONE and collider is PlaceableObject and collider.shape_id ==
ShapeType.CYLINDER`, in `_process_place_target()`'s `if`/`elif` chain
(same shape as the existing Plane-edge check). Inside it, mirror
`_compute_plane_edge_snap`'s structure: work in the cylinder's local frame
via `to_local(hit_point)`, decide whether the hit landed on the top cap
(compare `local_hit.y` against the cylinder's half-height) vs. the side,
compute the cone's offset from the cylinder's own `height`/`radius`
dimensions (`target.dimensions.get(...)`, exactly like the Plane case
reads `target.dimensions.get("width"/"length")`), and write
`_target_position`/`_target_yaw`/`_target_tilt`. `ShapeFactory.
surface_offset(ShapeType.CONE, current_dimensions, normal)` already gives
you the cone's own vertical half-extent for free.

### Skin/color resolution (`SkinManager.gd`)

`BuildModeController.active_skin_key` (and `PlaceableObject.skin_key`, and
the world JSON's `"skin"` field) is **one opaque string** for both kinds
of skin: `""` (none), an imported texture's filename, or a solid color's
own `"#rrggbb"` hex string. `SkinManager.is_color_key()` distinguishes
them (`begins_with("#")` — image filenames never start with one).
`SkinManager.build_material()` is the **single place** that string
resolves into an actual `StandardMaterial3D` — both the live placement
path (`BuildModeController._place_current()`) and world-load
(`SaveLoadManager._spawn_object()`) call through it. If you're adding a
third kind of "skin" (e.g. a procedural pattern), extend `build_material()`
and `is_color_key()`-style discrimination there, not in either caller.

### Infinite terrain (`TerrainStreamer.gd`, `TerrainNoise.gd`, `TerrainChunk.gd`)

Replaced the old fixed 60x60 `Ground` plane, which had a hard edge you'd
fall through forever past. `TerrainNoise.gd` is the **single source of
truth** for "what does the terrain look like at this world (x, z)" —
`height_at()`/`normal_at()`/`color_at()` are pure functions of world
coordinates only, never chunk-local ones. That's *why* adjacent chunks
never show seams or lighting cracks: two chunks sharing an edge call the
same functions with the same world-space inputs and get bit-identical
results, by construction, not by careful chunk-boundary bookkeeping.
`TerrainChunk.build()` (mirrors `ShapeFactory.create_instance()`) reads
those three functions once per vertex to build both the visual mesh and
the `HeightMapShape3D` collision from the *same* height samples, so the
walkable surface can't drift from the rendered one either.

`TerrainStreamer.gd` (a `Node3D` under `Main`, wired via
`set_player()` from `Main.gd`'s `_ready()` — see "Composition root"
below) tracks the player's current chunk coordinate and keeps a
square ring of chunks loaded within `VIEW_DISTANCE_CHUNKS`, freeing ones
that fall outside `VIEW_DISTANCE_CHUNKS + UNLOAD_HYSTERESIS_CHUNKS` (the
hysteresis margin stops load/unload thrashing right at the boundary).
New chunks are generated a few at a time (`CHUNKS_GENERATED_PER_FRAME`)
from a nearest-first queue rather than all at once, to avoid a hitch
when crossing a chunk boundary; `_ready()` eagerly builds a small block
around world origin synchronously first, since physics can tick before
the first budgeted frame runs otherwise.

Terrain is intentionally **not** part of the save/load system —
`SaveLoadManager` only serializes `GameManager.world_root`'s children,
and terrain chunks live outside it (sibling to `World`, where `Ground`
used to sit), regenerated on demand from a fixed noise seed rather than
persisted. A world JSON like a saved house build still works unmodified,
because `TerrainNoise` hard-flattens height/color to a flat green plain
within `FLATTEN_INNER_RADIUS` of world origin (blending into full hills
by `FLATTEN_OUTER_RADIUS`) — the same assumption the player's spawn
point and any origin-anchored build already relied on.

**Vegetation** (`VegetationDefinitions.gd`, `VegetationFactory.gd`) is
scattered inside `TerrainChunk.build()` itself, not as a separate pass —
that's what gets it covered by `TerrainStreamer`'s existing per-frame
budget for free, and freed automatically (as a descendant of the chunk's
`StaticBody3D`) whenever a chunk unloads, with no lifecycle code of its
own anywhere. `VegetationFactory.scatter()` seeds a
`RandomNumberGenerator` purely from `(chunk_coord, TerrainNoise.
NOISE_SEED)` — the same reproducibility guarantee `TerrainNoise` already
gives height/color, so a chunk's trees/flowers don't reshuffle when it
streams out and back in. Candidates are rejected below
`FLATTEN_SPAWN_THRESHOLD` (keeps decorations out of the spawn/tan-house
zone) and below `TerrainNoise.WATER_LEVEL` (keeps them out of lake/river
beds), then matched to one of three tree archetypes by
`BiomeDefinitions.dominant_biome()` — deliberately real shape variation
(a cactus has no canopy at all; a pine's canopy is a cone, not a sphere),
not just three colors of the same tree. Trees are **not**
`PlaceableObject`: that class exists to make something delete/rotate/
edit-able through `BuildModeController` and serializable through
`SaveLoadManager`, and a decoration that regenerates from the seed on
every reload would make "deleting" one through the build tools
confusing rather than useful.

**Water** (lakes and rivers) shares one rendering mechanism for both.
`TerrainChunk.build()`'s existing per-quad loop (already iterating every
quad once to emit terrain triangle indices) also checks each quad's
already-computed corner heights against `TerrainNoise.WATER_LEVEL` and,
if any corner is submerged, emits a matching flat quad into a second
mesh — so water follows the terrain's actual carved contour instead of
rendering as one hard-edged square per "wet" chunk, at no extra
noise-sampling cost. Lakes are just naturally low noise; rivers are
`TerrainNoise`'s ridged-noise carving (`_river_carve_at()`, a third
`FastNoiseLite` field, subtracted from raw height *before* the
`flatten_factor` multiply so a river can never cut through the flat
spawn zone) lowering terrain enough in a meandering path to dip below
the same `WATER_LEVEL` — no separate river-specific rendering exists.

**Worked example — "add a fourth biome":** add its base `Color` const
(suffixed `_COLOR` — see that constant block's own comment for why) and
extend `_base_biome_color()`'s threshold chain in `BiomeDefinitions.gd`
— that file is the only place biome colors and their noise thresholds
live, exactly like `ShapeDefinitions.DEFS` is the only place shape
dimensions live. Also extend `dominant_biome()`'s branches and give the
new biome a case in `VegetationDefinitions.archetype_for_biome()` (or
let it fall through to `-1`, i.e. no vegetation there) — those two stay
in sync with `_base_biome_color()` by hand, there's no single shared
table driving all three yet.

### Procedural UI pattern (`PauseMenuUI.gd`, `CircleButton.gd`)

No `.tscn` Control trees for UI — everything is built in `_ready()` with
`Node.new()` calls, because HUD/menu content genuinely depends on runtime
data (which shape is selected, how many skins exist) that a static scene
can't express without show/hide bookkeeping anyway.

`PauseMenuUI._ready()` builds, top to bottom: a full-rect dimming
`backdrop` → a `centering` CenterContainer → an `outer_hbox` (its only
child) holding the Colors column (left) and an `outer_vbox` (right:
Skins row / central panel / Tools row, stacked). `CircleButton.gd` is the
reusable round button used throughout (Godot has no built-in one) —
three content modes in priority order (`preview_texture` >
`swatch_color` > `label_text`), a `selected` bool for highlighting, and
its own circular hit-test in `_gui_input()` since a plain rectangular
`Button` would be clickable outside the drawn circle. Dynamic rows
(`_refresh_skins_row()`, `_refresh_colors_row()`) tear down and rebuild
their children from scratch on every call — simpler than diffing, and
cheap since it only runs on open/select, never per-frame. The fixed
Tools row is built once and just toggles `.selected`.

**Worked example — "add a control to the pause menu":** find the right
spot in `_ready()` (the central `vbox` for a simple always-there button
like Resume/Load Skin; a new row/column alongside Skins/Tools/Colors for
something dynamic), construct it the same way the neighboring controls
are (`Button.new()` + `.pressed.connect(...)`, or `CircleButton.new()`
for something matching that visual style), and wire its handler to call
straight into `BuildModeController`/`SkinManager`/`SaveLoadManager` (this
file talks to those directly — no signal indirection needed, it already
holds a `_build_controller` reference via `set_build_controller()`). If
the new control's appearance depends on state that can change from
elsewhere (not just its own click), add a refresh call for it alongside
the existing ones in `_open()` and `set_build_controller()`, the same way
`_refresh_skins_row()`/`_refresh_colors_row()`/`_refresh_tools_row()` are
each called from both places.

### Composition root (`Main.gd`)

The **only** place that knows about both `BuildModeController` (lives
under the player's camera, not global) and the UI (`BuildHUD`,
`PauseMenuUI`). It connects `BuildModeController`'s seven signals to
`BuildHUD`'s `on_*` handlers and hands `PauseMenuUI` a direct
`BuildModeController` reference via `set_build_controller()`. Everything
else either reaches a global autoload directly or has no idea who's
listening to its signals. If a new system needs to talk to both the
player rig and the UI, this is where that wiring goes — not scattered
`@onready` reach-ins in other scripts.

## Working conventions

- **Commit after each logical change**, with a message that explains the
  *root cause* and *reasoning*, not just what changed — `git log` is this
  project's changelog; there's no separate one to maintain, so keep
  writing messages that way rather than starting one.
- **Push to `main` and verify the deploy** after every change:
  `mcp__github__actions_list` (method `list_workflow_runs`, `resource_id:
  "deploy.yml"`, `workflow_runs_filter: {"branch": "main"}`) to find the
  run for your commit SHA. Its output routinely exceeds the tool's token
  limit and gets saved to a file instead — parse it with a `python3 -c
  "..."` one-liner via Bash (`json.load` the file, print
  `id`/`head_sha`/`status`/`conclusion`) rather than reading the raw file.
  Consider scheduling a wakeup (~150–250s) to check back rather than
  polling immediately, since the workflow takes a few minutes.
- **Ask the user to manually verify in-browser** (worldmaker.win) for
  anything visual or interactive — there's no way to confirm that from
  here.
- **Comment style**: WHY, not WHAT. Only comment a hidden constraint, a
  non-obvious invariant, or the reasoning behind a specific choice — never
  restate what a line of code already makes obvious. This is followed
  consistently throughout; match it.
- **`.gitignore`'s `/build/` is anchored to the repo root on purpose** —
  it's the CI export output directory only. It used to be unanchored
  (`build/`), which also matched `scripts/build/` (an unrelated source
  directory sharing the name) and silently required `git add -f` for any
  *new* file placed there. If a `git add` on something under
  `scripts/build/` ever warns about ignored paths again, that pattern has
  regressed — check `.gitignore` before assuming something's wrong with
  the files themselves.
