# Integration categories

Status: current behavior. Use this page to classify a new app, theme hook, or
module before adding packages or a `voluta feature` flag. Lifecycle rules for
feature modules live in [Core and optional features](features.md). Shared palette
policy lives in [Shared background](../integrations/theme.md).

Voluta does not ship a third-party plugin API. Public integrations are either
always-on core/theme wiring or an explicit feature module in the companion
settings schema.

## Category overview

| Category | Installs packages? | `features.*` flag? | Harmless if consumer missing? |
| --- | --- | --- | --- |
| Core desktop | Yes (`BASE_PACKAGES`) | No | N/A — required for the rice |
| Core palette consumers | Via core | No | Written into managed config trees |
| External theme-only consumers | No (user installs the app) | No | Yes — Wallust/theme write files only |
| Global GTK user stylesheet | Via core GTK stack | No | Applies to any GTK app that loads it |
| Optional feature modules | Yes, when enabled (`MODULE_PACKAGES`) | Yes | Core stays usable when disabled |
| Soft presence checks | No | No | Code skips tools that are not on `PATH` |
| Personal / host values | No | No | Settings, not shipped modules |

## Core desktop

The maintained baseline for a complete Voluta session. Packages come from
`BASE_PACKAGES` in `voluta/deploy.py`. Examples: Hyprland and UWSM, Waybar,
Kitty, Rofi, SwayNC, wlogout, Wallust, swww, Quickshell, clipboard/screenshot
tools, fonts, and a default terminal plus file-manager experience.

These are not toggled with `voluta feature`. Disabling them is outside the
optional-module contract.

## Core palette consumers

Wallust templates that feed Voluta-owned UI. Targets sit under the deployed
config tree (or paths the rice always manages). Palette refresh and
`voluta/theme.py` keep them aligned with `appearance.background`.

| Consumer | Wallust / publish path |
| --- | --- |
| Hyprland tokens | `~/.config/hypr/wallust/` |
| Waybar | `~/.config/waybar/wallust/` |
| Kitty | `~/.config/kitty/kitty-themes/01-Wallust.conf` |
| Rofi | `~/.config/rofi/wallust/` |
| SwayNC | `~/.config/swaync/wallust/` |
| wlogout | `~/.config/wlogout/wallust/` |
| Quickshell colors | `~/.config/quickshell/qml_color.json` |
| Shell palette | `~/.config/hypr/wallust/colors-shell.sh` |
| GTK bridge used by Brave tooling | `~/.config/hypr/wallust/colors-gtk.css` |
| Cava config | `~/.config/cava/config` |
| Corner SVG assets | `~/.config/wallust/assets/generated/` |

Generated exports under `${XDG_CACHE_HOME:-~/.cache}/voluta/` (`theme.json`,
`theme.css`, `theme.sh`) are disposable outputs for any extra consumer.

## External theme-only consumers

Same pattern as Karere: Voluta ships a template (and may recolor the resolved
background after Wallust). The third-party app or a small companion package
reads the file. Voluta does **not** register a feature flag and does **not**
install the app through `MODULE_PACKAGES`.

| Consumer | Written path | Who consumes it |
| --- | --- | --- |
| Limusic | `~/.config/limusic/matugen.css` | Limusic when its wallpaper-palette / Matugen setting is on |
| Karere | `~/.config/karere/custom.css` | `karere-custom-css` injects into WhatsApp Web; stock Karere ignores the file |

If the app is absent, the files are inert. Prefer this category for public
rice-coded apps whose only Voluta contract is palette files.

`voluta doctor` (and `make doctor`) reports each consumer as `inactive`,
`ready`, `theme_missing`, or `incomplete`. Those notes are advisory: they do
not fail the doctor exit code. Missing selected core/feature packages still do.
Voluta does not install these apps; install them yourself when you want them.

## Global GTK user stylesheet

Wallust writes the same template to `~/.config/gtk-4.0/gtk.css` and
`~/.config/gtk-3.0/gtk.css`. That sheet is shared application chrome (header
bars, menus, preferences), not a single optional app. Karere reloads the GTK4
path while open; other GTK apps load it according to GTK user-CSS rules.

Treat new per-app CSS under the external theme-only category. Do not fold
unrelated apps into this global sheet unless the change is intentionally
desktop-wide.

## Optional feature modules

Boolean keys under `features` in companion settings. Declared in
`voluta/cli.py` (`FEATURES`), defaulted in `voluta/defaults.json`, and mapped to
extra packages in `MODULE_PACKAGES`. Enable or disable with
`voluta feature …`; reconcile installs missing deps and applies module hooks.

| Feature | Default | What enabling does (summary) |
| --- | --- | --- |
| `dolphin` | `true` | Dolphin appearance packages, launch wrapper, advanced customization |
| `session_restore` | `false` | Login restore supervisor and related session tooling |
| `rgb` | `false` | OpenRGB / HID deps; host-scoped device records; privileged Mars setup when selected |
| `browser` | `false` | gsettings/xsettingsd deps; Brave GTK + Prismwing host + Gallery publish on theme refresh |
| `developer_shell` | `false` | Shell helper packages; interactive companion shell hooks |
| `obs` | `false` | `obs-cmd`; OBS-related keybindings when the session is live |
| `sddm` | `false` | SDDM package; privileged theme/palette drop-in setup |
| `rice_switch` | `false` | Permission to run `rice-switch` against another local rice |

Feature-gated theme extras (still not external theme-only):

- **Prismwing** Wallust JSON (`~/.config/prismwing/palette.json`) is always
  rendered. Running Prismwing’s installer and publishing Gallery assets happens
  only when `features.browser` is enabled.
- **SDDM** palette bridging runs when the `sddm` feature is active.
- **Dolphin / Qt / Kvantum** generators remain available for core file-manager
  theming; advanced injection follows the `dolphin` feature.

See [Brave with Prismwing and Gallery](../integrations/brave.md),
[Wallust RGB](../integrations/rgb.md), and [Dolphin](../../../dolphin/README.md).

## Soft presence checks

Runtime code detects optional binaries and continues without a feature flag.

| Tool | Behavior when missing |
| --- | --- |
| `cava` | Music surface skips raw ASCII bars; Wallust still writes `~/.config/cava/config` |
| `quickshell` | Framed selector / music / session UI that needs it fails closed or falls back; install/doctor treat a broken Quickshell as a core dependency problem |
| `prismwing` | Favicon host registration is skipped until the project is present and `browser` is enabled |

Do not invent a feature flag only to mean “skip if not installed.” Use a soft
check unless enabling should install packages or manage privileged hooks.

## Personal / host values

Companion settings that choose behavior without shipping a module:
`apps` (terminal, browser, file_manager commands), `keybindings`, `startup`,
`paths`, `monitors`, `workspaces`, `environment`, `appearance`, and `rgb.devices`.
False disables a named binding or startup entry. These are not listed in
`FEATURES`.

## Choosing a category for a new integration

1. **Only palette files for an external app** → external theme-only (Karere /
   Limusic). Document the required package or in-app toggle.
2. **Desktop-wide GTK chrome** → extend the global GTK user stylesheet carefully.
3. **Voluta should install deps, wrappers, or privileged setup** → optional
   feature module (`FEATURES` + `MODULE_PACKAGES` + enable/disable hooks).
4. **Nice-to-have binary on PATH** → soft presence check.
5. **User-preferred launch command or host path** → personal / host setting.

Public default: keep niche rice-coded apps in the external theme-only category
unless product intent is `voluta feature enable <name>` installing them.
