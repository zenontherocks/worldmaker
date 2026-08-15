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
└── ui/
    ├── UIRoot.gd          # builds PauseMenuUI + BuildHUD + Crosshair, no logic
    ├── PauseMenuUI.gd     # Esc menu -- see "Procedural UI pattern" below
    ├── BuildHUD.gd        # bottom-of-screen status text, signal listener only
    ├── CircleButton.gd    # reusable round button (3 content modes, see below)
    └── Crosshair.gd       # decorative center dot, no logic

scenes/
├── Main.tscn   # Environment, SunLight, Ground, World (empty container GameManager fills), Player, UI
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
