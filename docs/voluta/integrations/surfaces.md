# Architectural surfaces and Gallery

Status: implemented. The visual direction emphasizes geometry: stepped surrounds,
chamfered cards, recessed input panels, fine rules, and asymmetrical ornament.
The shared Rofi theme uses a `big-angel-box` SVG silhouette in the Wallust
palette. A framed menu blurs the whole desktop evenly and does not vignette
it: wallpaper colors stay consistent from edge to edge. The dark frosted glass
remains inside the frame. Rofi starts accepting
input without waiting for Quickshell. The uniform veil is established before the
frame rises in 135ms. The entrance waits for the artwork and veil, while
the animated projection paints during the rise to keep the frame close behind
the menu. Two palette-colored light trails travel around the inner rim during
the entrance on every framed menu. Their aperture-derived routes live in
`RimIgnition.qml`, cached by the resident renderer, and each opening restarts
the 450ms trace without the old 180ms post-load delay.
The trace clears at completion and its timer stops while idle. A resident renderer is
prewarmed at compositor startup/reload and reused on subsequent openings. A
session-scoped live-PID cache lets the warm launcher start Rofi before Qt
checks, compositor IPC, palette reads, and artwork timestamp checks. Rofi chooses
the focused monitor itself; decoration preparation follows after it is started.
The Super+D toggle reads Rofi’s PID file and verifies its process name instead
of scanning all processes with `pkill`.
The animated Rofi path unconditionally suppresses its own background artwork;
conditional media rules must not restore a second frame during the entrance.
On a warm switch to an output smaller than the animated plate, the menu remains
usable without decorative artwork. Missing or dead cached renderers still receive the
loader check and static fallback. It
waits 20ms after the menu request before starting the rise. The transparent,
input-free decoration surfaces remain mapped while idle; projection timers stop
when closed. Each request carries an ID so a late dismissal cannot close a newer
menu. Startup is serialized with `flock` and consolidates any surviving
one-shot renderer instances into one. Open/dismiss IPC addresses that exact PID,
so old instances cannot receive requests through ambiguous config selection. Generated-artwork timestamps trigger reloads after wallpaper changes. On dismissal, the boxes leave
first and the frame follows 90ms later. The fullscreen veil stays in
place and fades independently on closing. It is one palette tint at 6% opacity
across the whole screen, which is what gives Hyprland pixels to blur. There is
no feathered center, so the wallpaper is not darker in the middle. Each frame
keeps a dark frosted glass plate clipped to its opening, using the palette
background at 50% opacity, rather than a foreground-colored glow. This is more
transparent than Kitty’s 75% background.
Gallery still uses the large corner scrolls on the artwork frame. Labels stay
plain; tab-group names do not receive symbols.

## Desktop surfaces

`rofi/frame.rasi` supplies the shared angel surround, input relief, and tile
outlines. The shared plate is 1152×1024, with padding that matches the frame
hollow so ornaments sit outside the content. The app selector and Wi-Fi menu
import `rofi/selector-frame.rasi`. The static theme loads `selector-plate.png`;
the animated popup still loads `big-angel-box.png`. The publisher uses the original artwork's hue range to
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
edge of the ornament. The boxes remain above the effects on the Top layer.
A non-grabbing, input-transparent Quickshell popup holds the frame above Rofi, including its closing snapshot.
Hyprland draws closing Overlay snapshots after live Overlay surfaces, so a
second Overlay layer with a lower `order` only fixes the open-menu stacking.
Both decorative surfaces accept no input. The frame and stained-glass
projection share the same entrance and dismissal motion. Only the lower glass
surface receives backdrop blur, across the whole screen; the frame does not
blur the buttons beneath it. The wallpaper outside the opening is blurred
evenly and is not vignetted.
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

## Window grid anchors

Framed menus that sit on an edge use one inset source:
`voluta/window_grid.py`. It reads the focused monitor's reserved exclusive
zone and Hyprland's live `general:gaps_out`. The window grid's outer edge is
the sum of those two, on every side:

> **inset = reserved + gaps_out**

`gaps_out` follows CSS order: top, right, bottom, left. A single value applies
to every side; two values are vertical then horizontal; three values are top,
horizontal, then bottom. Hyprland reports each monitor's reserved area as
left, top, right, bottom. Waybar's exclusive zone is the top entry on this
desktop, so a 34px bar and an 8px top gap put the grid's top edge at 42px.

| Anchor | Screen position |
| --- | --- |
| Left | `inset.left` |
| Top | `inset.top` |
| Right | `screen width − inset.right` |
| Bottom | `screen height − inset.bottom` |

The music salon is right-anchored. Its opaque right pixel, not the transparent
canvas margin, sits on that right edge. `music-edges.json` records the frame's
transparent padding when the plate is published. The salon is centered between
the top and bottom insets when the plate fits; on a 1080p output it stays on
screen even if the plate is taller than the inner grid. Changing focus re-reads
the insets, because another monitor can reserve a different edge.

The session column is left-anchored. Its straight rail faces the screen edge, and
its opaque left pixel sits on `inset.left`. The ornate side and the cherub face
the desktop. The music salon is the mirror on the right.

The notification panel is top-anchored. Its glass starts at `inset.top`: the
layer accounts for the reserved bar, and the projection adds only `gaps_out.top`.
`swaync/launch.sh` copies `control-center-margin-top` from that same top gap
into a runtime config. The value in `swaync/config.json` is the fallback used
when Hyprland cannot be queried. Horizontal SwayNC margins stay at zero because
that panel is centered, not side-anchored. A future menu anchored to the left
or the bottom reads `VOLUTA_GRID_LEFT` or `VOLUTA_GRID_BOTTOM` from the same
object. The session column is the left reader. Do not copy `gaps_out` into
another menu, stylesheet, or margin key.

## Notification salon

SwayNC opens a wide, top-centered framed panel below Waybar. Its top edge is
the window-grid inset from [Window grid anchors](#window-grid-anchors), not a
separate margin. The flat upper edge has no projecting pediment. Two serious-faced
adult angels fly beside the frame, pressing their palms beneath its lower
corners. One bears the weight with an articulated robotic arm; the other has
a visible robotic leg. Spread wings and trailing drapery stay outside the
archive. Lock, power, and the other session actions live in the left column,
not in this panel.
`Super+N` toggles the panel; `Super+Shift+N` toggles the existing night-light
filter. Waybar's notification button also toggles the panel. Both invoke
`swaync/toggle-panel.sh`, which calls the native D-Bus toggle directly when
`gdbus` is available, avoiding extra client-side setup on the toggle path.
The client remains the fallback when the D-Bus command-line tool is absent.

The owner-supplied source is `wallust/assets/notification-angels-frame.png`.
Its near-transparent top margin was cropped by 84px; no artwork was regenerated.
Both it and `big-angel-box.png` use `frame_tints` and `render_palette_frame` in
`voluta/surfaces.py`: the same hue mapping, relief, shadow color, and alpha
preservation apply to both. Only their canvas dimensions and backing layers
differ. The notification canvas is 1056×736; GTK adds the frame's padding to
SwayNC's configured content width, so those dimensions must be changed together.
The publisher derives `notification-glass.png`, `selector-glass.png`, and
`music-glass.png` from each enclosed transparent opening and the resolved
background at 50% opacity. The selector's static fallback composites that glass
under the angel as `selector-plate.png`; the animated path draws
`selector-glass.png` on the lower surface and suppresses the plate. `notification-aperture.png` masks the animation to the same opening.
Both leave the outer silhouette clear.
Malformed/open cutouts produce no glass rather than painting outside the frame.

Wallpaper publication regenerates both frames before reloading consumers.
`Super+Alt+R` also syncs and filters both source PNGs from the recorded checkout,
and re-renders shared SVG templates such as the clear `launcher-vignette.svg`;
the old `--refresh-selector` publisher option remains an alias for
`--refresh-frames`. GTK surfaces, hover colors, text, and shadows derive from
Wallust. Hyprland owns SwayNC's top-slide animation and backdrop blur, using the
existing light compositor blur settings. The artwork itself stays sharp.

Both menus use `wallust/effects/MenuGlass.qml` for the clear veil, masked glass,
preloading, readiness, inner-rim ignition, and entrance/dismissal lifecycle.
The component uses `StainedGlass.qml` for drifting palette bands and facets at
25fps, and `RimIgnition.qml` for the 450ms palette trails that travel the inner
opening. Selector, notification, and music salons do not keep private copies of
those effects. Each consumer has a local `effects` link because Quickshell
restricts imports to its entrypoint root; the installer links the same canonical
source. Native SwayNC keeps its compositor-owned slide and input handling. The
selector and music salon keep only their frame popups and content (Rofi buttons,
album poster, CAVA bars) around that shared lifecycle.

The notification backdrop stays mapped but fully transparent when closed,
matching the selector's warm surface. The shared module preloads its veil at
screen dimensions and prepaints the projection on the resident surface. It
reveals the veil immediately when ready; it does not map a cold blur window
on each open. The same projection canvas joins the native-sized sliding
surface when the panel opens. On dismissal, the veil clears immediately and
the bounded projection follows the native compositor exit. The canvas pauses
while hidden. Neither menu maintains a separate copy of the blur or animation
implementation.

`swaync/watch-glass.py` is the native visibility/IPC adapter. It prewarms one
resident renderer, reattaches or respawns it if that process dies while the
watcher is still running, and numbered requests prevent stale closes.
`Super+N` starts the watcher when it is missing. The optional
`status` IPC reports readiness and open/paint timestamps for real effect
latency checks; native D-Bus acknowledgement alone is insufficient.
A per-compositor lock prevents duplicate watchers after reloads.
The helper detects changed palette, aperture, or panel configuration while
visible, and refreshes the projection. It drops the effect on daemon disconnect
and reconnects with bounded backoff. A missing or broken renderer leaves the
permanent dark GTK glass usable. The managed SwayNC user-service drop-in starts
`swaync/launch.sh`: it defaults only this application's `GSK_RENDERER` to
`cairo`, while preserving an explicitly configured renderer. This avoids the
measured cold GTK graphics initialization delay. D-Bus activation and session
startup both use that service. Compositor blur and Quickshell rendering remain
unchanged, as do host GPU selection and global environment policy.

After a geometry/widget change, test a fresh SwayNC process: reloading the
running daemon can retain old widget allocations. Palette-only changes use the
normal CSS refresh. A change to `gaps_out` reaches the native panel the next
time `swaync/launch.sh` starts it. The glass reads the same gap on the next open.

## Music salon

`Super+M` toggles a portrait framed overlay for the current MPRIS player. The
owner artwork is `wallust/assets/music-frame.png`, published to a 624×1040 plate
so it fills 1080p under Waybar. Its opaque right edge meets the window grid's
right inset, and it slides in from that side and leaves the same way. The enclosed opening holds album art, title,
artist, album, a seek bar, previous/play/next, volume, loop, shuffle, and
CAVA-like bars. The overlay opens on the Hyprland focused monitor, and moves there if focus
changes while it is open. It reads MPRIS itself on open and every second while
visible, so a stale watcher cannot leave **Nothing playing** on screen.
A decoded cover stays up until the next one is ready. A cached copy is not
replaced by Brave's temporary thumbnail, which is often only 150×83.
Previous, next, play/pause, volume, loop, and shuffle call `playerctl`.
Escape, Space, arrow keys, a click on the veiled desktop, or `Super+M`
again close or control it. `playerctl` also still follows from `music/watch.py`. Local `file://` artwork, including browser temp files, is copied under
`$XDG_RUNTIME_DIR` so Chromium can delete the original. HTTP artwork uses the
same cache. If `cava` is installed, `music/watch.py` reads its raw ASCII bars;
otherwise it synthesizes a gentle playing waveform and holds still while paused.
Opening the salon starts the watcher if it is not already running. Media keys
keep controlling playback.

Selector, notification, music, and session menus are mutually exclusive:
`hypr/scripts/exclusive-framed.sh` closes the other three before one of them
opens. Opening music does not toggle the notification panel.

The salon reuses `MenuGlass.qml`, `StainedGlass.qml`, and `RimIgnition.qml`.
`MenuGlass` slides the selector on `y` and the music salon on `x`.
`music/salon.qml` owns only the cherub frame popup, poster, bars, and labels.
`music/watch.py` prewarms one renderer at compositor start/reload, with a
per-session lock matching the notification watcher. A missing Quickshell, CAVA,
or player leaves the rest of the desktop unchanged.

## Session column

`Super+O` toggles a portrait framed column on the left edge of the window grid.
The source is `wallust/assets/session-frame.png`. Its left rail is straight and
spare; the acanthus and a cherub with a key face inward, the reverse of the
music frame. The plate is the same 624×1040 size, so it fits 1080p, and it
slides in from the left.

The opening keeps the clock and date at the top, with uptime and battery
charge when a battery exists. The default audio sink, its volume, and one chip
per monitor sit at the bottom. Night light is a full-width row: the moon stays
the moon, and the row reads **On** or **Off**. A gap separates that row from
the session icons, which span the width of the opening: lock, sleep, log out,
reboot, and power off. Sleep, log out, reboot, and power off ask for a second
click before they run; that click shows a check. Lock uses
`hypr/scripts/LockScreen.sh`. Log out, reboot, and power off use the same
`session_manager.py prepare-shutdown` sequence as the power menu. The column
closes the other framed menus when it opens, and they close it in return.
The column fills its output, like the other framed menus, so the shared veil,
aperture glass, and blur cover the desktop instead of a tiny default window.
`MenuGlass` loads `*-glass.png` beside the aperture when the menu does not
pass its own plate. The notification panel sets `suppressPlate` because GTK
already paints that glass.
`session-menu/watch.py` prewarms one renderer. The directory is `session-menu`,
not `session`, because `~/.config/session` already stores desktop-session files.
A missing Quickshell or frame leaves the rest of the desktop unchanged.

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

Shared-lifecycle validation on 2026-11-07 used the actual QML readiness and
paint timestamps, rather than native-toggle acknowledgements. After 10–12
seconds idle, the notification veil was ready 134–148ms after the toggle;
projection painting was observed within 231ms. The shared veil and projection
were ready while idle, remained decoded across close/open cycles, and cleared
after dismissal. These are observed QML dispatch/paint timings on this host,
not guaranteed presentation latency. Twenty focused installer, surface, notification-watcher, and
selector-launcher checks passed. The real selector opened and dismissed with
its shared effects ready throughout. Both consumers instantiate
`MenuGlass.qml`; neither contains its own backdrop/projection animation copy.

The full-desktop notification veil was also verified live on 2026-11-07:
`voluta-notification-backdrop` covered 1920×1080 beneath the sharp menu and
projection. The resident backdrop now stays mapped with transparent pixels
after dismissal, while the sliding projection unmaps.
The 21 focused checks passed again after this addition.

Owner-art refit on 2026-11-07: 21 focused palette, geometry, renderer lifecycle,
deployment, and toggle checks passed. The content rectangle has a tested 16px
clearance from solid frame pixels; the archive scrollbar uses a 2px rail.
Live checks found matching native/glass surfaces at (0,34), 1920×1046, and
captured the menu and projection moving upward together on dismissal.
The renderer PID survived the idle/open/close test. The default GTK renderer took 2419ms in an isolated first-open comparison;
Cairo took 17ms. The final installed service/toggle measured 18ms on first
opening, 19ms after 8 seconds idle, and 22ms on repeat. These are D-Bus
acknowledgement timings on this session, not a general first-frame benchmark. Hyprland reported no configuration errors.

On 2026-11-07, the resident selector renderer loaded without warnings and
completed three open/dismiss cycles in one process. Measured warm request-to-rise
latency was 133–167ms including IPC on the active notebook session; the 20ms
stagger is an animation timer, not a guarantee of total launch latency. Renderer
initialization measured about 200ms separately and is now paid during prewarming.
The launcher tests cover preserved dmenu input/exit status, hidden prewarming,
reuse without spawning another renderer, and matching dismissal request IDs.
An entrance follow-up removed conditional Rofi background artwork after a
rapid-reopen capture exposed overlapping frames despite a single renderer.
The regression now verifies the animated path cannot restore background images
through media rules. Process counts alone do not establish visual uniqueness.
A duplicate-renderer follow-up consolidated seven live selector instances into
one. Three overlapping prewarms retained one renderer, and a live dummy menu
exposed exactly one `rofi` and one `voluta-selector-glass` surface. The startup
regression also checks duplicate metadata and legacy renderer consolidation.
A follow-up launcher check starts the native input owner before even a blocked
compositor query. Toggle tests cover Rofi’s newline-free PID file and reject a
PID reused by another process. The desktop-entry cache did not produce a
repeatable startup improvement, so app discovery remains uncached.
Hyprland reload reported no configuration errors. A fresh graphical login and
physical multi-monitor switching have not been exercised for this change.

On 2026-11-07, 32 notification, shared-theme, deployment, configuration, and
selector checks passed. Frame checks cover palette changes, preserved alpha,
consumer dimensions, matching backing/projection masks, and rejecting an
aperture that leaks to the exterior. Installer checks resolve both local QML
imports to the same managed source. Watcher checks exercise duplicate
suppression, per-compositor locks, visibility, live palette changes without
continuous monitor IPC, daemon reconnect, missing/invalid dependencies and
monitor data, and process cleanup.

Fresh and live SwayNC previews verified the angel frame, heading, DND switch,
action grid, sliders, and projection below the native controls. The bounded
glass layer measured 1056×640 at (432,42) on the 1080p notebook: Waybar's 34px
exclusive zone plus the 8px window-grid gap. It disappears after panel closure.
The two N shortcuts loaded with separate Super and Super+Shift modifiers;
Hyprland reported no configuration errors. Night light was not toggled during
validation. The inherited system GTK theme still emits its `gtk.css` warnings;
the notification stylesheet loaded without parser errors. Physical GPU behavior
remains subject to the runtime constraints.

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
