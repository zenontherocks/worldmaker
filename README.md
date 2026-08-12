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
│   └── local-data-bridge.js    # File System Access API shim, injected into the exported page
├── scripts/
│   ├── autoload/               # global singletons (Project Settings > Autoload)
│   │   ├── InputSetup.gd       # registers all input actions in code
│   │   ├── GameManager.gd      # shared world-root reference + id counter
│   │   ├── SkinManager.gd      # loads PNG/JPG -> Texture2D at runtime
│   │   ├── SaveLoadManager.gd  # world JSON export/import
│   │   └── LocalDataFolder.gd  # Web: reads/writes one folder on the player's disk
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
│       ├── UIRoot.gd           # builds the two UI pieces, F1 toggle
│       ├── SettingsPanelUI.gd  # collapsible corner panel + file dialogs
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
   | `toggle_mouse_capture` | Esc | Release the mouse (click the view to recapture) |
   | `toggle_ui_panel` | F1 | Show/hide the settings panel |
   | `build_mode_toggle` | B | Enter/exit Build Mode |
   | `build_cycle_shape` | E | Cycle Box → Plane → Cylinder → Cone → Sphere |
   | `build_cycle_dimension` | Q | Select which dimension the scroll wheel edits |
   | `build_dimension_increase` / `build_dimension_decrease` | Mouse wheel up/down | Adjust the active dimension |
   | `build_rotate_cw` / `build_rotate_ccw` | R / Shift+R | Rotate the ghost/placement 15° around Y |
   | `build_place` | Left click | Place the current shape |

5. `Main.tscn` is already set as the main scene
   (`Project > Project Settings > Application > Run > Main Scene`).

## 3. Running locally

Press **F5** (or the Play button) in the editor. You should spawn standing
on a green ground plane. Walk with WASD, look with the mouse, press **B** to
enter Build Mode, **E** to pick a shape, scroll to resize, **R**/**Shift+R**
to rotate, left-click to place. Press **F1** to open the corner panel and
import a skin or export/import a world JSON file.

In the editor (and any desktop export) this always uses ordinary native
file dialogs — real OS file pickers reading/writing the actual filesystem,
no special setup needed. The "one folder on your disk" flow described
below only applies to the Web export, where browsers don't allow that kind
of direct filesystem access by default.

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
6. Texture-skin import and world JSON import both use Godot's native
   `FileDialog` (`use_native_dialog = true`), which on Web uses the browser's
   file picker — no extra work needed. World **export** on Web instead
   triggers a normal browser download (see the architecture notes below for
   why).

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
  `PlayerController` or the UI directly. It communicates outward purely via
  four signals (`build_mode_changed`, `shape_changed`, `dimensions_changed`,
  `active_field_changed`); `Main.gd` is the only place those signals get
  connected to the HUD.

- **`GhostPreview` is visual-only.** It knows how to show a translucent
  shape and flip valid/invalid tinting, and nothing about raycasting or
  input. That keeps it reusable for a future feature (e.g. a "select/move"
  tool) without editing `BuildModeController`.

- **Procedural UI instead of hand-authored `.tscn` Control trees.** The
  settings panel and HUD are built in code (`SettingsPanelUI.gd`,
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
  settings panel's file-dialog flow) reads and writes the same global
  `Input.mouse_mode`. That removes an entire class of desync bug where the
  camera thinks it should still be spinning while a file dialog is open.

- **One local data folder on Web, real `FileDialog` everywhere else.**
  Desktop exports (and the editor) always use ordinary native `FileDialog`s
  reading/writing the real filesystem — no special handling needed, since
  desktop Godot has unrestricted file access. Web is different: browsers
  sandbox pages away from the filesystem by default, and testing showed
  Godot's "native" `FileDialog` fallback on Web isn't reliable — it can
  render its own in-engine dialog instead of the browser's real OS picker,
  browsing an empty virtual filesystem rather than anything on the
  player's disk. `LocalDataFolder.gd` (`scripts/autoload/`) sidesteps this
  entirely on Chromium-based browsers (Chrome, Edge, Opera) using the
  browser's [File System Access
  API](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API):
  the player grants access to one real folder on their disk *once*, and
  from then on skins are listed/read and `world.json` is written/read
  directly from that folder — no uploads, no per-file dialogs, no server
  ever sees any of it. The actual browser calls live in
  `web/local-data-bridge.js`, a plain JS file injected into the exported
  page via `export_presets.cfg`'s `html/head_include` (kept as a real
  `.js` file rather than an inline string so it stays readable/editable,
  and copied into `build/` by the CI workflow since Godot's exporter only
  ships its own engine output). Firefox and Safari don't implement this
  API, so `LocalDataFolder.is_supported()` gates it off there and
  `SettingsPanelUI` falls back to the original `FileDialog`/
  `JavaScriptBridge.download_buffer()` flow, same as before.

- **Skins are referenced by name, not embedded.** A placed object stores the
  skin's file name (`skin_key`) in the JSON, not the image itself, keeping
  world files small. The trade-off: reloading a world before that image has
  been read this session (e.g. a fresh page load, before choosing the data
  folder) will place the object with the default material until the
  matching file is available again. This is a deliberate scope boundary for
  a "lightweight, local-first" project — embedding base64 image data in the
  JSON would be the straightforward extension if that's ever a problem.

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
  `vertical_offset`.
- **Deleting placed objects:** not implemented (out of scope for this
  foundation). A natural next step is a `build_delete` action in
  `InputSetup.gd` and a second raycast check in `BuildModeController`
  against `GameManager.world_root`'s children.
- **Multiple skins per object (per-face):** would mean giving
  `PlaceableObject` an array of skin keys instead of one, and teaching
  `ShapeFactory` to build a `MeshInstance3D` with per-surface materials.
