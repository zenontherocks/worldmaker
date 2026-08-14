# WorldMaker

A lightweight, web-exportable (WebGL/HTML5) first-person 3D sandbox built in
Godot 4. Players walk around a small world, drop into **Build Mode**, and
place primitive shapes (box, plane, cylinder, cone, sphere) with adjustable
dimensions, rotation, and user-imported PNG/JPG texture skins. Builds export
to a JSON file and can be re-imported later.

Built for the "GL Compatibility" renderer so it stays usable on low-end
Linux laptops and in a browser tab.

## 1. Project structure

```
worldmaker/
├── project.godot
├── scenes/
│   ├── Main.tscn              # level: ground, sky, light, World container, Player, UI
│   └── Player.tscn            # CharacterBody3D rig: camera, raycast, build controller, ghost
├── web/
│   └── local-data-bridge.js    # universal <input type=file> shim for the exported page
├── scripts/
│   ├── autoload/               # global singletons (Project Settings > Autoload)
│   │   ├── InputSetup.gd       # registers all input actions in code
│   │   ├── GameManager.gd      # shared world-root reference + id counter
│   │   ├── SkinManager.gd      # loads PNG/JPG -> Texture2D at runtime
│   │   ├── SaveLoadManager.gd  # world JSON export/import
│   │   └── WebFilePicker.gd    # Web: one-off <input type=file> picker, every browser
│   ├── core/
│   │   └── Main.gd             # composition root: wires BuildModeController <-> UI
│   ├── player/
│   │   ├── PlayerController.gd # WASD movement, gravity, jump, collision
│   │   └── PlayerCamera.gd     # mouse look (pitch on camera, yaw on body)
│   ├── build/
│   │   ├── ShapeDefinitions.gd # data table: shapes + their dimension fields
│   │   ├── ShapeFactory.gd     # dimensions -> Mesh + Shape3D
│   │   ├── PlaceableObject.gd  # metadata + to_dict() for placed objects
│   │   ├── GhostPreview.gd     # translucent placement preview
│   │   └── BuildModeController.gd # raycast, cycling, dimension edit, placement
│   └── ui/
│       ├── UIRoot.gd           # builds the two UI pieces
│       ├── PauseMenuUI.gd      # Esc pause menu: import/export, pauses the tree
│       └── BuildHUD.gd         # bottom-of-screen build status readout
```

No script exceeds a single responsibility: movement, look, raycasting,
mesh/collision generation, skin loading, save/load, and each UI surface are
all separate files that talk to each other through signals or through the
small autoload services.

## 2. Editor setup

1. Install **Godot 4.3+** (Standard build — .NET/Mono build is not needed,
   the project is pure GDScript).
2. Open Godot, choose **Import**, select this project's `project.godot`.
3. The project already targets the **GL Compatibility** renderer
   (`Project > Project Settings > Rendering > Renderer > Rendering Method`).
   Leave it as-is — it's what makes the WebGL export and low-end laptops
   viable (Forward+ will not export to Web at all, and Mobile is heavier
   than needed here).
4. Input actions are registered at runtime by `scripts/autoload/InputSetup.gd`
   (the first entry in **Project > Project Settings > Autoload**), not by
   hand-edited entries in the Input Map tab. This avoids the Input Map going
   stale after edits and keeps the whole binding table in one data file. If
   you'd like to see/re-map them visually anyway, open
   **Project > Project Settings > Input Map**, type an action name from the
   table below, click **Add**, and record your own key — your binding will
   simply add to (not replace) the one InputSetup registers.

   | Action | Key | Purpose |
   |---|---|---|
   | `move_forward` / `move_back` / `move_left` / `move_right` | W / S / A / D | Walk |
   | `jump` | Space | Jump |
   | `toggle_pause_menu` | Esc | Open/close the pause menu (pauses the game, releases the mouse) |
   | `build_cycle_shape` | E | Cycle Box → Plane → Cylinder → Cone → Sphere → Delete → Rotate → Edit |
   | `build_cycle_dimension` | Q | Select which dimension the scroll wheel edits (Place, or Edit once locked on) |
   | `build_dimension_increase` / `build_dimension_decrease` | Mouse wheel up/down | Adjust the active dimension |
   | `build_rotate_cw` / `build_rotate_ccw` | R / Shift+R | Rotate 15° around Y (horizontal facing) -- tips a pending Plane vertical instead |
   | `build_tilt_cw` / `build_tilt_ccw` | T / Shift+T | Tilt 15° around X (Rotate tool only) |
   | `build_place` | Left click | Place the current shape |
   | `build_toggle_snap` | G | Toggle grid-snap + wall/edge surface-snapping together |

5. `Main.tscn` is already set as the main scene
   (`Project > Project Settings > Application > Run > Main Scene`).

## 3. Running locally

Press **F5** (or the Play button) in the editor. You should spawn standing
on a green ground plane. There's no separate "enter Build Mode" step —
building is the whole game, so you're always in it. Walk with WASD, look
with the mouse, **E** to pick a tool, scroll to resize, **R**/**Shift+R** to
rotate, left-click to place. New placements face the same direction you're
currently facing (nudge further with **R**/**Shift+R** before placing), and
by default (**G** toggles this) placement is smart about surfaces: any
shape sits flush against whichever face it's touching (not just resting on
top of flat ground), a pending Plane automatically stands up flush against
a wall it's aimed at instead of lying flat, and a pending Plane aimed at an
*already-placed* Plane snaps flush against its nearest edge instead of
stacking on top of it.

A pending Plane's default orientation (before **R**/**Shift+R**) always
comes from where the camera is currently pointed, not a fixed rule: aimed
roughly level (within `level_look_threshold_degrees`, 45° by default) it
defaults to standing vertical -- "I'm looking at wall height, I want a
wall" -- and aimed distinctly up or down instead it defaults to lying flat
-- "I'm looking at floor/ceiling height." Aiming at an *already-placed*
Plane's edge keeps that same rule, just relative to the target's own
orientation instead of absolute: looking level always produces a
*vertical* result (hinging a wall up from a floor tile's edge, or tiling
another panel sideways to extend an already-vertical wall into a longer
one -- both "give me a wall"), and looking distinctly up/down always
produces a *horizontal* result (tiling a floor flat, or capping a wall's
edge with a horizontal piece -- both "give me a floor/ceiling"). **R**/
**Shift+R** always nudges further on top of whichever default this picks.
This is how actual buildings (a floor, walls rising from its edges, walls
extended into longer walls) get built out of Planes.

Away from a Plane-specific surface, both position and facing snap to a
grid so shapes actually line up with each other instead of just sitting
at grid-aligned positions while facing whatever arbitrary direction the
player happened to be looking: horizontal position snaps to a 1-unit grid
(`BuildModeController.grid_size`) and yaw snaps to 90°
(`rotation_snap_degrees`). Turning snapping off with **G** falls back to
plain facing-based placement with no grid/wall/edge assistance (still
never clipping or floating, just no smart alignment). A small dot at the
center of the screen always shows exactly where the camera is pointing.

For a Plane specifically (when not snapped to a wall or another Plane),
**R**/**Shift+R** tips it further instead of spinning it -- spinning a
flat square around its own vertical axis doesn't look any different, so R
does the one rotation that actually matters for it; horizontal facing
already comes from wherever you're standing, and its base tilt already
comes from wherever you're looking (see above).

**E** also cycles past the five shapes into three more tools, each of
which highlights whatever placed block the crosshair is over: **Delete**
(left-click removes it), **Rotate** (**R**/**Shift+R** spins it
horizontally, **T**/**Shift+T** tilts it vertically), and **Edit**
(left-click locks onto it, then **Q**/wheel resize it live the same way
Place mode sizes a pending placement -- left-click again to let go of it).

Press **Esc** to open the pause menu, which is also where you can pick any
of the eight tools directly with the cursor (a Tools row mirroring the
**E** cycle) instead of cycling through them, pick which imported skin is
active from a Skins row (not just whichever was imported most recently),
import a new skin, or export/import the whole world as JSON.

In the editor (and any desktop export) the pause menu always uses ordinary
native file dialogs — real OS file pickers reading/writing the actual
filesystem, no special setup needed. The Web export picks a file a
different way (see below), since browsers don't allow that kind of direct
filesystem access by default.

## 4. Exporting for WebGL / HTML5

1. In Godot, open **Editor > Manage Export Templates** and download the
   templates matching your Godot version (one-time setup).
2. **Project > Export... > Add... > Web**.
3. On the Web preset, leave **Threads** disabled unless you know your
   hosting supports the cross-origin isolation headers it needs — disabled
   is safer for the widest range of static hosts (itch.io, GitHub Pages).
4. Click **Export Project**, choose an output folder, and export.
5. Serve the exported folder over HTTP (Godot's export writes an `index.html`
   plus `.wasm`/`.pck` files — opening `index.html` directly via `file://`
   will not work due to browser CORS restrictions on WASM). For a quick local
   check: `python3 -m http.server` from the export folder, then open
   `http://localhost:8000`.
6. On Web, texture-skin import and world JSON import both go through
   `WebFilePicker.gd`/`web/local-data-bridge.js` instead of Godot's
   `FileDialog` (see the architecture notes below for why). World
   **export** on Web triggers a normal browser download.

## 5. Deploying to your domain (Cloudflare R2, automated)

`.github/workflows/deploy.yml` rebuilds the Web export and deploys it on
every push to `main` (and on manual trigger). It has two stages:

1. **Export** — [`chickensoft-games/setup-godot`](https://github.com/chickensoft-games/setup-godot)
   installs a headless Godot `4.3.0` plus export templates (it resolves the
   correct download itself instead of us hand-pinning a release asset URL),
   then a plain `godot --headless --export-release "Web" build/index.html`
   runs the `Web` preset defined in `export_presets.cfg`.
2. **Deploy** — the AWS CLI (pre-installed on GitHub's runners; R2 speaks
   the S3 API) runs `aws s3 sync` against an R2 bucket named `worldmaker`,
   mirroring the `build/` folder exactly (`--delete` removes anything from
   a previous build that's no longer produced).

We deploy to **R2**, not Cloudflare Pages or a Worker, because Godot's
compiled WebAssembly engine (`index.wasm`) is ~34MB and both Pages and
Workers cap individual static assets at 25MB — R2 has no such per-file
limit, and is Cloudflare's own recommended fix for this exact situation.

### One-time setup (you need to do this — I can't do it from here)

1. **Create an R2 bucket** named `worldmaker`: Cloudflare dashboard >
   **R2 Object Storage > Create bucket**.
2. **Enable public access and attach your domain.** In the bucket's
   **Settings > Public access > Custom Domains > Connect Domain**, enter
   `worldmaker.win`. (If your domain was previously attached to the
   `worldmaker` Worker from an earlier setup attempt, remove it there
   first — **Workers & Pages > worldmaker > Settings > Domains & Routes**
   — a hostname can only be attached to one thing at a time.)
3. **Create R2 API credentials**: dashboard > **R2 Object Storage > Manage
   R2 API Tokens > Create API Token**. Give it **Object Read & Write**,
   scoped to the `worldmaker` bucket if you're offered the choice. This
   issues an **Access Key ID** and **Secret Access Key** — copy both now,
   the secret is only shown once.
4. **Add repo secrets** in **GitHub > this repo > Settings > Secrets and
   variables > Actions**:
   - `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` — from step 3.
   - `CLOUDFLARE_ACCOUNT_ID` — found on the right sidebar of any page in
     the Cloudflare dashboard. The workflow uses this to build the R2
     endpoint URL (`https://<account-id>.r2.cloudflarestorage.com`), so it
     must be the account the `worldmaker` bucket actually lives in.
   - (If you added a `CLOUDFLARE_API_TOKEN` secret during an earlier setup
     attempt, it's no longer used by this workflow — fine to leave it or
     delete it.)
5. Push to `main` (or run the workflow manually from the **Actions** tab)
   and watch the run. Once it's green, `worldmaker.win` serves the game.

### Notes / things to double-check on the first run

- Multithreading is disabled in the Web export preset
  (`variant/thread_support=false`) on purpose — enabling it requires the
  host to send `Cross-Origin-Opener-Policy`/`Cross-Origin-Embedder-Policy`
  headers, which R2's public-bucket serving doesn't let you configure as
  easily as a Worker could. Leaving it off keeps deployment simple, at the
  cost of not using multiple CPU threads — a fine trade for a lightweight
  sandbox game.
- Prefer a different host (plain FTP/SSH, GitHub Pages, Netlify)? The
  **Export** stage doesn't know or care where the result ends up — only
  the last step does. Swap the final `Sync build to Cloudflare R2` step
  for whatever your host needs, pointed at the `build/` folder, and the
  rest of the pipeline is unchanged.

## 6. Key architectural decisions

- **Data-driven shapes.** `ShapeDefinitions.gd` is the single table of which
  five shapes exist and which dimension fields each one has. `ShapeFactory.gd`
  is the only place that turns those fields into a `Mesh` + `Shape3D` pair.
  Adding a sixth primitive later means one new entry in `DEFS` plus one new
  `match` branch in `ShapeFactory` — the UI, build controller, and save
  format never need to change.

- **Decoupled player rig.** Movement/gravity (`PlayerController.gd`) and
  mouse look (`PlayerCamera.gd`) are separate scripts on separate nodes
  (body vs. camera). Yaw rotates the body, pitch rotates the camera. This is
  the standard Godot FPS split and means either half can be swapped (e.g. a
  vehicle controller, or a third-person camera) without touching the other.

- **Build mode is a service, not a mode flag on the player.**
  `BuildModeController.gd` lives under the camera (so its raycast always
  matches where the player is looking) but only depends on `ShapeFactory`,
  `ShapeDefinitions`, `SkinManager`, and `GameManager` — never on
  `PlayerController` or the UI directly. There's no "enter/exit build mode"
  toggle -- it's the whole game, so it's always running (the pause menu
  stops it for free via `SceneTree.paused`, same as everything else with
  the default `PROCESS_MODE_PAUSABLE`). It communicates outward via seven
  signals for the HUD (`shape_changed`, `dimensions_changed`,
  `active_field_changed`, `tool_mode_changed`, `edit_target_changed`,
  `edit_target_cleared`, `snap_toggled`) plus two public methods,
  `select_slot()`/`select_skin()`, that the pause menu's Tools/Skins rows
  call directly; `Main.gd` hands the pause menu its `BuildModeController`
  reference (via `set_build_controller()`) since that one isn't global,
  the same way it connects the HUD's signals.

- **`GhostPreview` is visual-only.** It knows how to show a translucent
  shape and flip valid/invalid tinting, and nothing about raycasting or
  input. That keeps it reusable for a future feature (e.g. a "select/move"
  tool) without editing `BuildModeController`.

- **Placement caches one full result, not just a position.**
  `_process_place_target()` picks between three cases each physics frame
  (plain flush placement, Plane-against-a-wall, Plane-against-an-existing-
  Plane's-edge) and always writes `_target_position`/`_target_yaw`/
  `_target_tilt` regardless of which one ran, with manual R/Shift+R/T/
  Shift+T offsets already folded in. `_place_current()` only ever reads
  those three cached values back -- it never recomputes anything itself --
  so the ghost preview and the object actually placed can't drift apart no
  matter which of the three cases produced them. `snap_enabled` ([G])
  gates the wall/edge cases and grid-snapping together as one on/off
  assist; the underlying flush `ShapeFactory.surface_offset()` (correct
  per-axis distance from whichever face was hit, not just "up") is a
  correctness fix rather than an assist, so it always applies regardless.

- **Procedural UI instead of hand-authored `.tscn` Control trees.** The
  pause menu and HUD are built in code (`PauseMenuUI.gd`,
  `BuildHUD.gd`) rather than as static scenes. The HUD's dimension rows
  genuinely depend on which shape is selected (a Sphere has one field, a Box
  has three) — a fixed scene tree can't express that without runtime
  show/hide bookkeeping anyway, so generating it directly from
  `ShapeDefinitions` is simpler and keeps the layout in sync with the data
  table automatically.

- **Runtime input map (`InputSetup.gd`).** Registering actions via
  `InputMap.add_action`/`action_add_event` in code, instead of only the
  editor's Input Map tab, means the bindings can never silently go missing
  after a merge or a fresh clone, and the whole table is reviewable in one
  file. It's still layered under the normal `Input`/`InputMap` APIs, so
  everything else in the project (`Input.is_action_pressed`, etc.) works
  exactly like it would with editor-configured actions.

- **Single mouse-capture authority.** Rather than each system tracking its
  own "is the mouse captured" boolean, every script (camera look, the
  pause menu's open/close and file-dialog flow) reads and writes the same
  global `Input.mouse_mode`. That removes an entire class of desync bug
  where the camera thinks it should still be spinning while a menu or file
  dialog is open.

- **Real `FileDialog` on desktop; a single universal fallback on Web,
  never Godot's own "native" Web dialog.** Desktop exports (and the
  editor) always use ordinary native `FileDialog`s reading/writing the
  real filesystem — no special handling needed, since desktop Godot has
  unrestricted file access. On Web, `FileDialog`'s `use_native_dialog`
  turns out to silently do nothing in *any* browser: Godot's
  `DisplayServer` never reports `FEATURE_NATIVE_DIALOG_FILE` for the Web
  platform at all, so it always renders its own in-engine dialog browsing
  an empty virtual filesystem instead of a real OS picker, regardless of
  which browser is running it. `WebFilePicker.gd` replaces it on Web with
  a plain HTML `<input type="file">` element, triggered via
  `web/local-data-bridge.js` (a plain JS file injected into the exported
  page via `export_presets.cfg`'s `html/head_include`, kept as a real
  `.js` file rather than an inline string so it stays readable/editable,
  and copied into `build/` by the CI workflow since Godot's exporter only
  ships its own engine output). This is a much older, universally-
  supported browser mechanism — the same one behind "attach a file" on
  any ordinary website — so it behaves identically across Chromium,
  Firefox (and its forks, e.g. Zen Browser), and Safari. Two things worth
  knowing about it:
  - **No `<input accept>` filter.** An earlier version filtered by file
    type, which made browsers grey out non-matching files in the OS
    dialog — standard, correct behavior, but a real target file appearing
    unselectable for any reason (an unexpected extension, a cloud-sync
    placeholder file, a filter-string quirk) was a recurring source of
    confusion. Nothing is filtered now, so nothing can ever be greyed
    out; `PauseMenuUI.gd` checks the picked filename's extension itself
    afterward and shows a clear in-menu error if it's the wrong type.
  - **Polling, not a JS→GDScript callback.** The result comes back via a
    plain global object (`window.wmFileResult`) that `WebFilePicker.gd`
    polls for in `_process()`, rather than `JavaScriptBridge.
    create_callback()`. Every callback-based JS-to-Godot return path tried
    earlier in this project (including an abandoned File System Access
    API folder-picker flow) failed to fire with no error on either side at
    some point, while `JavaScriptBridge.eval()` was reliable in both
    directions throughout — polling avoids the whole suspect code path.
  There's no folder concept anymore: every import is a fresh one-off
  picker, and world export uses `JavaScriptBridge.download_buffer()` (a
  normal browser download) exactly as before.

- **Pause menu instead of an always-visible panel.** `PauseMenuUI.gd` is
  hidden until **Esc**, at which point it sets `get_tree().paused = true`
  and shows itself — everything else in the scene (player, camera, build
  mode) uses Godot's default `PROCESS_MODE_PAUSABLE`, so it freezes for
  free with no per-script gating needed. The menu itself (and its
  `FileDialog`s) opts in to `PROCESS_MODE_ALWAYS` so its buttons and
  `WebFilePicker`'s poll keep working while paused. Its Tools row is built
  once from `ShapeDefinitions.ORDER` plus Delete/Rotate/Edit and just
  toggles which button is `disabled` to show the current selection; its
  Skins row
  is rebuilt from `SkinManager.skin_keys()` on every open and every fresh
  import instead, since that list actually grows over a session.

- **Skins are embedded in the world file, keyed by name.** A placed object
  stores its skin's file name (`skin_key`) in `"objects"`, and
  `SaveLoadManager` separately writes each unique skin actually in use into
  a top-level `"skins": {name: base64}` dict (see its docstring for the
  full schema) — `SkinManager` keeps the original bytes cached alongside
  the decoded texture for exactly this. There's deliberately no server
  anywhere in this project to re-fetch images from later, so a name-only
  reference would only resolve for as long as a session's in-memory skin
  cache happened to still hold that image; embedding is what makes a saved
  world's skins actually survive a reload. Older (version 1) world files
  without a `"skins"` key still load fine, just unskinned, same as before
  this was added.

- **UI buttons opt out of keyboard focus.** Every procedurally-built
  `Button` sets `focus_mode = Control.FOCUS_NONE`. Godot's built-in
  `ui_accept` action (Space *and* Enter) re-presses whatever Control last
  held keyboard focus, and Space is also this game's jump key — without
  opting out, clicking any panel button would make Space silently jump
  *and* re-trigger that button from then on. `PlayerController.gd` has the
  same class of fix for the same reason: jump/movement read raw `Input`
  state every physics frame rather than routed events, so they're never
  automatically blocked by GUI focus the way `_unhandled_input` is — they
  explicitly check `Input.mouse_mode == MOUSE_MODE_CAPTURED` (the same
  "is the player actively playing vs. using a menu" signal used
  throughout the UI) instead.

- **`Main.gd` is the only composition root.** Every other script either
  reaches an autoload (global by design) or emits a signal without knowing
  who's listening. `Main.gd` is the one place allowed to know about both
  the player's `BuildModeController` and the UI's `BuildHUD`, which keeps
  that cross-cutting wiring visible in one small file instead of scattered
  through `@onready` reach-ins across the codebase.

## 7. Extending it

- **New shape:** add an entry to `ShapeDefinitions.DEFS`, add a `match`
  branch in `ShapeFactory.build_mesh` / `build_collision_shape` /
  `surface_offset`.
- **Deleting/rotating/resizing placed objects:** implemented as three extra
  tools in `BuildModeController`'s `[E]` cycle (`ToolMode.DELETE`/
  `ToolMode.ROTATE`/`ToolMode.EDIT`, in `_slots` alongside the five
  placeable shapes) rather than new input actions -- all three target
  whatever `PlaceableObject` the existing raycast is over and highlight it
  via a temporary `material_override` swap. Edit additionally locks onto
  its target on click (`_edit_locked`, so the highlight stops following
  the crosshair) and reuses the same Q/wheel dimension-editing code path
  as a pending placement, just writing into `PlaceableObject.
  rebuild_geometry()` instead of the ghost.
- **Multiple skins per object (per-face):** would mean giving
  `PlaceableObject` an array of skin keys instead of one, and teaching
  `ShapeFactory` to build a `MeshInstance3D` with per-surface materials.
