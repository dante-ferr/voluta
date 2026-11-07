# Architectural surfaces and Gallery

Status: implemented. The visual direction emphasizes geometry: stepped surrounds,
chamfered cards, recessed input panels, fine rules, and asymmetrical ornament.
The shared Rofi theme uses a `big-angel-box` SVG silhouette in the Wallust
palette. The app and Wi-Fi selectors use a translucent fullscreen vignette so
Hyprland can softly blur the desktop behind the frame. Rofi starts accepting
input without waiting for Quickshell. The frame and glass rise in 190ms and two
reflections trace the inner edge as it settles. On dismissal, the boxes leave
first and the frame follows 90ms later. The fullscreen blur veil stays in
place and fades independently on opening and closing.
Gallery still uses the large corner scrolls on the artwork frame. Labels stay
plain; tab-group names do not receive symbols.

## Desktop surfaces

`rofi/frame.rasi` supplies the shared angel surround, input relief, and tile
outlines. The shared plate is 1152×1024, with padding that matches the frame
hollow so ornaments sit outside the content. The app selector and Wi-Fi menu
import `rofi/selector-frame.rasi`, which loads the same generated
`big-angel-box.png`. The publisher uses the original artwork's hue range to
map different areas to several colors from the active Wallust palette. It
blends between those colors and uses the original luminance to retain detail,
with deep shadows matching the background of the Rofi boxes. It preserves the
original PNG and its transparency.
Rofi reads the filtered copy on the next launch without
processing the image or refreshing a menu that is already open.
After replacing `wallust/assets/big-angel-box.png` in the source checkout,
press Super+Alt+R to deploy just that image and regenerate the filtered copy
with the current palette. Wallpaper changes use the deployed source.
The publisher also scales `big-angel-box.svg` for the shared theme. It centers
the filtered PNG on a transparent 1152×1024 canvas while preserving its aspect
ratio, so Rofi fills the slot without repeating the image.
The fullscreen window centers that plate with padding, using half the
monitor minus half the plate. Super+D, Super+Shift+Enter, and
Super+Ctrl+Enter all run `rofi/launch-dashboard.sh`. Both menus use opposing
rounded corners and a heavier left edge on ordinary rows, with more space
between the boxes and the surrounding ornament. Both lists show up to seven
rows at a time. The selected row has a 2px palette accent outline and a raised
background color, with the same content position as ordinary rows.
When Quickshell is installed and the monitor can fit the frame, the shared
selector launcher projects moving bands of stained glass inside the opening.
The launcher checks that `quickshell --version` succeeds before handing off
the frame. A broken Quickshell binary keeps the static Rofi artwork. If effects
are missing, run that check in a terminal: a Qt symbol lookup error requires
repairing or rebuilding Quickshell against the installed Qt libraries;
Super+Alt+R cannot repair a binary/library mismatch.
The Wallust colors drift diagonally behind Rofi. The publisher derives a mask
from the PNG's enclosed transparent opening, so the effect reaches the inner
edge of the ornament. The boxes remain above the effects on the Top layer. A separate
`voluta-selector-frame` Overlay surface renders after Rofi (`order = -1`), so
the ornament covers the button edges. Both decorative surfaces accept no input
and share the same entrance and dismissal motion. Only the lower glass surface
receives backdrop blur; the frame does not blur the buttons beneath it.
The static fallback retains Rofi’s background frame when Quickshell is unavailable.
The main launcher, dashboard, picker, and RGB selector import the shared frame;
two-column and wide selectors use frames sized to their own rows. Rofi preserves
SVG aspect ratios when scaling background images and can tile the result, so
update the generated canvas sizes along with any window or tile geometry change.
Test an actual menu, not only `-dump-theme`.

The power menu uses the same stepped surrounds and inset focus relief. Its action
layout, keybindings and power commands are unchanged. Validate styling with a
separate layout whose actions are all `true`; never invoke power actions as a
visual test.

Frame sources live in `wallust/assets/`. `voluta/surfaces.py` renders them into
`~/.config/wallust/assets/generated/` after the shared background publisher runs.
Colors derive exclusively from Wallust tokens and the persistent background
policy. Generated files are ignored and must not be committed.

## Optional Brave New Tab

Voluta Gallery is an unpacked Manifest V3 extension, shipped under `brave/gallery/`.
It provides a large framed wallpaper, clock, search panel, and up to twelve named
shortcuts. It does not change the native tab strip or tab-group geometry: those
controls are drawn by Brave. Choose neutral native group colors separately.
Prismwing remains responsible for website favicons. For enablement, GTK
appearance, Prismwing, and the **Load unpacked** steps, follow
[Brave with Prismwing and Gallery](brave.md).

Gallery's background mixes the shared browser background 6% toward the palette
foreground, giving the page a lighter surface while the native sidebar stays
dark. Its raised panels and rules derive from that lighter surface.

On opening a tab, the typography enters in a short stagger and the artwork frame
draws into place. A palette-colored glint travels around the stepped surround,
and the wallpaper drifts slowly inside its clipped mat. Motion pauses in hidden
tabs. All of these effects, including hover movement, are disabled when the
browser reports `prefers-reduced-motion: reduce`; static framing remains intact.

With the browser feature enabled, palette publication prepares the extension at
`${XDG_DATA_HOME:-$HOME/.local/share}/voluta/gallery`. Keep that published path
stable across updates: unpacked extension identity and browser-stored shortcuts
depend on it. After extension code updates, use **Reload** in the extensions
page and reopen New Tab. Palette and wallpaper changes refresh automatically in
open, visible Gallery tabs within four seconds, and immediately when a tab
becomes visible. The publisher does not edit browser profile databases, silently
install extensions, or change existing groups.

Choose **Artwork** under the image to select **Current wallpaper** or **Specific
image**, then **Use artwork**. A specific image is copied into this browser
profile's IndexedDB, so moving/deleting the original file or updating the
dotfiles does not remove it. PNG, JPEG, WebP, AVIF and GIF files up to 64 MiB are
supported. No file-access permission or upload is needed. Switching to the
wallpaper keeps the last image available for reuse. Open Gallery tabs share the
selection; each browser profile has its own choice. The palette continues to
follow Wallust even when the artwork is fixed.

Gallery requests only `storage` and `search`. It stores shortcut names and URLs
in browser-local extension storage, uses the configured search engine, and makes
no external requests before a user searches or follows a shortcut. Its local
wallpaper copy is restricted to supported image files up to 64 MiB; unavailable
artwork leaves a palette-colored mat. The generated descriptor contains an opaque
version and relative image name, not the wallpaper's filesystem path. The private
wallpaper copy belongs in the user's data directory, never the repository.

Disabling the browser feature stops Gallery publication and preserves its data.
Disable/remove the extension in Brave as well if you no longer want its New Tab
page. Re-enabling the feature republishes the assets; shortcut storage survives
ordinary dotfiles updates. Uninstalling the extension itself can erase that
browser-managed storage.
The same applies to the saved image and source selection: they are browser-local
preferences, not companion files or generated extension assets. Clearing the
extension's site data or removing its profile can erase them.

## Verification

On 2026-11-06, the installed pinned Quickshell provider failed at startup with a
Qt private-symbol lookup error. Replacing it with Arch's Quickshell 0.3.2 restored
the renderer. A live dummy selector exposed both `rofi` and
`voluta-selector-glass` layers without stderr output, and a separate renderer
check loaded the QML and completed IPC dismissal successfully. Dependency tests
cover loader failures, timeouts, preserving working providers, reinstalling a
broken package, and rejecting an unsuccessful repair. The launcher regression
test verifies that loader failure preserves the static artwork and arguments.

`tests/test_surfaces.py` checks core publication with browser disabled, wallpaper
refresh, background policy, missing-artwork tolerance, and preference preservation.
`tests/gallery.test.mjs` checks address validation and bounded shortcut storage.
It also checks custom-image formats and size limits. The local artwork workflow
was exercised with a fixture PNG through the real file-input/save handlers:
missing-image validation, decoding, reload persistence, fixed artwork during
wallpaper refresh, and switching back to the retained image all passed.
Run them alongside the existing theme and installer acceptance suites.

The local browser preview verifies layout, shortcut add/remove persistence, and
narrow-screen overflow. Live Rofi and wlogout previews verify their actual
renderers. Manual extension loading and the browser's default-search API still
need verification in the selected Brave profile; a local HTTP preview exercises
the fallback UI, not Chromium's extension installation.

Recorded validation on 2026-11-02: 46 Voluta tests and 12 session tests passed
locally and in the offline QEMU/TCG Arch guest using configuration-only installs.
The Gallery logic checks passed in Node. All four Rofi themes parsed and opened
successfully; actual screenshots caught and resolved image tiling across icon
and text rows. Wlogout loaded its stylesheet without warnings using a no-op
layout. The HTTP Gallery preview passed shortcut persistence, console-error and
horizontal-overflow checks. No Brave extension was installed automatically.
