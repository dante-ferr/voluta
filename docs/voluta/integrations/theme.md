# Shared appearance

Status: implemented. `appearance` in Voluta's resolved settings is the source of
truth for the rice's base background and shared design tokens (typography,
density, shape, glass). Defaults live in `voluta/defaults.json`; persistent
shared and host overrides use personal TOML (`settings.toml` /
`hosts/<hostname>.toml`) with the normal merge precedence. Core updates preserve
those overlays.

```toml
[appearance.background]
source = "background"
darken = 0.35

[appearance.typography.ui]
family = "Oxanium"
size_pt = 11
fallback = ["sans-serif"]

[appearance.typography.mono]
family = "Monaspace Argon"
size_pt = 10
fallback = ["JetBrainsMono Nerd Font", "monospace"]

[appearance.typography.display]
family = "Cinzel"
size_pt = 11.5
weight = 700
letter_spacing_px = 0.8
fallback = [
  "JetBrainsMono Nerd Font",
  "FiraCode Nerd Font",
  "serif",
  "monospace",
]

[appearance.typography.icon]
family = "JetBrainsMono Nerd Font"

[appearance.density]
space_xs_px = 3
space_sm_px = 6
space_md_px = 12
space_lg_px = 18

[appearance.shape]
radius_sharp_px = 0
radius_sm_px = 5
radius_md_px = 6
radius_lg_px = 8
radius_xl_px = 13

[appearance.glass]
body_alpha = 102
chrome_alpha = 191
stripe_alpha = 40
```

## Background

`source` selects Wallust's `background` or `color0` through `color15`. `darken`
is a number from 0 to 1. The default preserves Dolphin's previous base RGB.
One Python resolver performs the RGB rounding for every consumer.

## Design tokens

Values are centralized; each consumer still uses its own stylesheet or conf
format. `voluta/theme.py` publishes the resolved tokens after Wallust renders
and before consumers reload:

| Role | Typical consumers |
| --- | --- |
| `typography.ui` | Dolphin/Qt, global GTK user CSS, gsimplecal |
| `typography.mono` | Kitty, SwayNC, Rofi, Dolphin terminal pane |
| `typography.display` | Exported for shared use; Waybar keeps a hardcoded Cinzel stack |
| `typography.icon` | Nerd Font symbol maps and icon fallbacks |
| `density.*` | Dolphin QSS padding/spacing |
| `shape.radius_*` | Dolphin soft corners; sharp roots (Waybar plate radii stay in `style.css`) |
| `glass.*` | Dolphin body/chrome/stripe alphas (QSS + live hook) |

Edit a token, then refresh the palette (or run `make theme`):

```sh
voluta theme set typography.ui.family '"Oxanium"'
voluta theme set glass.chrome_alpha 191
voluta theme set shape.radius_md_px 6
voluta theme reset glass.body_alpha
voluta get appearance.typography
make theme
```

Wallpaper changes apply preferences automatically through the same refresh
pipeline. `wc_source_bg` retains the extracted input; `wc_bg` is the resolved
base. Repeated refreshes therefore never darken it twice. Standalone Dolphin
and Brave generators also call this resolver, including when using an older
generated shell palette without `wc_source_bg`.

## Consumers

Background consumers are Dolphin/Qt/Kvantum and its embedded terminal, Brave's
GTK toolbar and sidebar, Kitty and its tabs, Waybar, SwayNC, Rofi, wlogout, the
generated Hyprland background token, Quickshell's window background, Limusic,
and Karere. SDDM's existing optional palette bridge reads the resolved `wc_bg`.
Foregrounds and accents retain their palette values; raised surfaces are
derived from the shared base. Hyprland window outlines use dedicated
`active_border` / `inactive_border` tokens (`color1` and `color0` lifted like
Kitty and Waybar accents) so dark wallpapers cannot leave borders near-black.

Design-token consumers rewrite marked blocks or conf keys on publish:

| Consumer | How tokens apply |
| --- | --- |
| Waybar `style.css` | Not rewritten; typography and plate radii stay hardcoded. Wallust still supplies colors |
| SwayNC `style.css` | `@@voluta-tokens` root (mono) |
| gsimplecal `gtk.css` | `@@voluta-font` (ui family) |
| Kitty `kitty.conf` | `font_family` / `font_size` from mono |
| Rofi `*.rasi` | `font:` family from mono |
| GTK 3/4 `gtk.css` | Appended `@@voluta-design` ui font block |
| Dolphin paint + live hook | QSS, qt6ct fonts, glass alphas from tokens / `theme.json` |

Limusic is an [external theme-only consumer](../architecture/integration_categories.md).
Karere’s CSS is always written the same way, but WhatsApp Web injection needs the
optional `karere` feature. `voluta doctor` reports each app relative to its theme
file.

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

Karere needs `karere-custom-css` to read `~/.config/karere/custom.css` and inject
it into WhatsApp Web. `make karere` enables that feature. If stock `karere` is
already installed, the installer removes that conflicting package first and
keeps files in your home directory. Wallust writes the file
from `wallust/templates/colors-karere.css` on every palette refresh. The package
reloads the file while Karere is open. The chat list, conversation canvas,
bubbles, composer, headers, menus, icons, and text use opaque palette colors.
The sheet does not set a fractional `opacity` on those nodes. Upstream Karere
does not load this file (it avoids WhatsApp Web injection).

Wallust also writes `wallust/templates/colors-karere-gtk.css` to
`~/.config/gtk-4.0/gtk.css` and `~/.config/gtk-3.0/gtk.css`. That sheet is the
global GTK user stylesheet: flat header bars, menus, preferences, and controls
use the shared background, ink, and accent. GTK loads it for every app on top
of the active theme. The publisher then stamps the shared UI font. Karere
reloads the GTK4 path while it is open. Text and controls stay opaque. Brave's
published Imperium GTK theme stays separate for Chromium chrome.
Brave's **Ultra dark theme / Darker theme** override must be off for the GTK
background lightness to match; ordinary Dark mode can remain enabled.
Existing transparency settings remain application-specific, so wallpaper behind
translucent windows can still change their apparent color.

For additional consumers, generated exports are available at
`${XDG_CACHE_HOME:-~/.cache}/voluta/theme.json`, `theme.css` and `theme.sh`.
The JSON provides `background`, `background_rgb`, `source_background`, and the
full design-token tree; the stylesheet defines `voluta_background` plus CSS
custom properties (`--voluta-font-ui`, `--voluta-radius-md`, and related);
the shell file defines `voluta_bg`, `voluta_bg_rgb`, and matching
`voluta_font_*` / `voluta_radius_*` / `voluta_glass_*` variables. These are
disposable outputs, not preference files.

Checks: `python3 -m unittest discover -s tests -p 'test_theme.py'`,
`python3 tools/check-brave-theme.py`, `python3 tools/check-dolphin-theme.py`, and
`python3 tools/check-wallust.py`. These cover shared RGB, design tokens, host
precedence, idempotence, preserved accents/alpha, invalid overrides and existing
generators.
