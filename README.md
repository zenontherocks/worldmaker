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
├── scripts/
│   ├── autoload/               # global singletons (Project Settings > Autoload)
│   │   ├── InputSetup.gd       # registers all input actions in code
│   │   ├── GameManager.gd      # shared world-root reference + id counter
│   │   ├── SkinManager.gd      # loads PNG/JPG -> Texture2D at runtime
│   │   └── SaveLoadManager.gd  # world JSON export/import
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
   | `toggle_mouse_capture` | Esc | Release/recapture the mouse |
   | `toggle_ui_panel` | F1 | Show/hide the settings panel |
   | `build_mode_toggle` | B | Enter/exit Build Mode |
   | `build_cycle_shape` | Tab | Cycle Box → Plane → Cylinder → Cone → Sphere |
   | `build_cycle_dimension` | Q | Select which dimension the scroll wheel edits |
   | `build_dimension_increase` / `build_dimension_decrease` | Mouse wheel up/down | Adjust the active dimension |
   | `build_rotate_cw` / `build_rotate_ccw` | R / Shift+R | Rotate the ghost/placement 15° around Y |
   | `build_place` | Left click | Place the current shape |

5. `Main.tscn` is already set as the main scene
   (`Project > Project Settings > Application > Run > Main Scene`).

## 3. Running locally

Press **F5** (or the Play button) in the editor. You should spawn standing
on a green ground plane. Walk with WASD, look with the mouse, press **B** to
enter Build Mode, **Tab** to pick a shape, scroll to resize, **R**/**Shift+R**
to rotate, left-click to place. Press **F1** to open the corner panel and
import a skin or export/import a world JSON file.

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

## 5. Key architectural decisions

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

- **Two save paths for one save format.** `SaveLoadManager.gd` always
  builds the same JSON (see the schema comment at the top of that file).
  Desktop exports write it straight to a path chosen via `FileDialog`.
  Web exports can't write to an arbitrary host path — browsers only allow
  downloads — so on Web the same JSON string is handed to
  `JavaScriptBridge.download_buffer()` instead, which triggers a normal
  browser file-save. Skin *import* doesn't need this split because Godot's
  native open dialog already resolves to a browser file picker on Web.

- **Skins are referenced by name, not embedded.** A placed object stores the
  skin's file name (`skin_key`) in the JSON, not the image itself, keeping
  world files small. The trade-off: reloading a world in a browser tab that
  never had that image loaded this session will place the object with the
  default material until the user re-imports that same-named file via the
  panel. This is a deliberate scope boundary for a "lightweight, web-first"
  project — embedding base64 image data in the JSON would be the
  straightforward extension if that's ever a problem.

- **`Main.gd` is the only composition root.** Every other script either
  reaches an autoload (global by design) or emits a signal without knowing
  who's listening. `Main.gd` is the one place allowed to know about both
  the player's `BuildModeController` and the UI's `BuildHUD`, which keeps
  that cross-cutting wiring visible in one small file instead of scattered
  through `@onready` reach-ins across the codebase.

## 6. Extending it

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
