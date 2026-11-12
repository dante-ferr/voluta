# Shared background

Status: implemented. `appearance.background` in Voluta's resolved settings is
the source of truth for the rice's base background. Defaults live in
`voluta/defaults.json`; persistent shared and host overrides use the normal
settings precedence. Core updates preserve those overrides.

```json
"appearance": {
  "background": {"source": "background", "darken": 0.35}
}
```

`source` selects Wallust's `background` or `color0` through `color15`. `darken`
is a number from 0 to 1. The default preserves Dolphin's previous base RGB.
One Python resolver performs the RGB rounding for every consumer.

For example, change the darkening, or restore its inherited default:

```sh
voluta theme set background.darken 0.45
voluta theme reset background.darken
voluta theme set background.source '"color0"' --scope host
voluta get appearance.background
make theme
```

Wallpaper changes apply the preference automatically through the same refresh
pipeline. `voluta/theme.py` publishes the resolved background after Wallust
renders and before consumers reload. `wc_source_bg` retains the extracted input;
`wc_bg` is the resolved base. Repeated refreshes therefore never darken it twice.
Standalone Dolphin and Brave generators also call this resolver, including when
using an older generated shell palette without `wc_source_bg`.

Consumers are Dolphin/Qt/Kvantum and its embedded terminal, Brave's GTK toolbar
and sidebar, Kitty and its tabs, Waybar, SwayNC, Rofi, wlogout, the generated
Hyprland background token, Quickshell's window background, Limusic, and Karere.
SDDM's existing optional palette bridge reads the resolved `wc_bg`. Foregrounds
and accents retain their palette values; raised surfaces are derived from the
shared base. Hyprland window outlines use dedicated `active_border` /
`inactive_border` tokens (`color1` and `color0` lifted like Kitty and Waybar
accents) so dark wallpapers cannot leave borders near-black.

Limusic reads `~/.config/limusic/matugen.css` while **Matugen** (named **Wallpaper
palette** in newer builds) is on under Settings, Appearance. Wallust writes that
file from `wallust/templates/colors-limusic.css` on every palette refresh, and
Limusic applies the new file without a restart. The publisher then replaces the
extracted background in that file with the resolved base. The window and sidebar
use that base at 65% opacity, so the wallpaper shows through. Now playing covers
the current page. The palette hides that page and leaves the song layer clear,
so the wallpaper shows through the song. Theater mode keeps the fill and hides
the window under it. A music video still punches a hole through both. Cards and
text on buttons stay opaque. The accent and foreground stay on the Wallust
palette, lifted the same way as Waybar and Kitty.

Karere, installed as the `karere-custom-css` package, reads
`~/.config/karere/custom.css` and injects it into WhatsApp Web. Wallust writes
that file from `wallust/templates/colors-karere.css` on every palette refresh.
The package reloads the file while Karere is open. The chat list and the
conversation canvas use the shared background at 65% opacity. Message bubbles,
the composer, headers, menus, icons, and text stay opaque: the sheet sets their
colors without a fractional `opacity`. Stock Karere does not load this file;
the downstream package is what watches it. A window-wide fade is not used,
because that would also fade the type. Chromium paints the page into Karere's
surface, so the canvas alpha shows the wallpaper only when that surface is
itself transparent.

Wallust also writes `wallust/templates/colors-karere-gtk.css` to
`~/.config/gtk-4.0/gtk.css` and `~/.config/gtk-3.0/gtk.css`. That sheet is the
global GTK user stylesheet: flat header bars, menus, preferences, and controls
use the shared background, ink, and accent. GTK loads it for every app on top
of the active theme. Karere reloads the GTK4 path while it is open. Text and
controls stay opaque. Brave's published Imperium GTK theme stays separate for
Chromium chrome.
Brave's **Ultra dark theme / Darker theme** override must be off for the GTK
background lightness to match; ordinary Dark mode can remain enabled.
Existing transparency settings remain application-specific, so wallpaper behind
translucent windows can still change their apparent color.

For additional consumers, generated exports are available at
`${XDG_CACHE_HOME:-~/.cache}/voluta/theme.json`, `theme.css` and `theme.sh`.
The JSON provides `background`, `background_rgb` and `source_background`;
the stylesheet defines `voluta_background`; the shell file defines `voluta_bg`
and `voluta_bg_rgb`. These are disposable outputs, not preference files.

Checks: `python3 -m unittest discover -s tests -p 'test_theme.py'`,
`python3 tools/check-brave-theme.py`, `python3 tools/check-dolphin-theme.py`, and
`python3 tools/check-wallust.py`. These cover shared RGB, host precedence,
idempotence, preserved accents/alpha, invalid overrides and existing generators.
