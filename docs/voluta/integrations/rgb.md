# Wallust RGB integration

Status: implemented bridge with OpenRGB and an experimental HyperX Mars adapter.
The owner confirmed static lighting works; desktop writes of the per-key profile
have also completed with firmware acknowledgments.

Enable RGB for a particular host and list explicit devices in its companion JSON:

```json
{
  "version": 1,
  "features": {"rgb": true},
  "rgb": {
    "accent": "wc_1",
    "devices": [
      {"backend": "openrgb", "usb_id": "04d9:fc30", "name": "Redragon M711 Cobra"},
      {"backend": "hyperx-mars", "usb_id": "0951:16c6", "experimental": true, "layout": "voluta"}
    ]
  }
}
```

The owner’s desktop profile selects these devices; the notebook disables RGB.
Other users must supply their own supported device/model selection. Brand names
alone do not establish compatibility: firmware and wired/wireless mode matter.

```sh
voluta feature enable rgb --scope host
voluta rgb --dry-run
voluta rgb
```

The backend parses the generated Wallust hex token without sourcing shell code,
checks for the exact connected USB ID, serializes device writes, and caches the
last successful color/device generation (the complete transaction for per-key
layouts, so changes beyond the accent are detected). Reconnects invalidate the cached USB
generation. Unknown backends are rejected; absent devices are skipped. Permission
and dependency failures report unavailable status without blocking desktop startup
or palette generation. The palette watcher starts on login and configuration reload, with a per-session
lock preventing duplicates. It notices wallpaper/settings changes within roughly
one second and periodically retries newly connected devices. Runtime messages go
to `${XDG_STATE_HOME:-$HOME/.local/state}/voluta-palette.log`. Disabling stops future updates;
it does not restore an undocumented prior hardware profile or turn lights off.

OpenRGB uses only the selected controller name, static mode and hex accent. Its
package provides device rules; no blanket root execution is used for color writes.
The Mars backend requires `python-hidapi`, interface 0/usage page 1, explicit
experimental selection and exact model matching. Install the narrow rule through
`voluta system-setup rgb`, then reconnect the keyboard. Do not run the desktop or
palette watcher as root.

The Mars sends a complete firmware profile transaction and checks handshake,
header and final acknowledgments. It may save onboard state; identical successful
colors are skipped to avoid gratuitous writes. The Mars supports `"layout": "static"` (the default) or `"layout": "voluta"`.
The latter writes all 104 keys and 15 light-bar LEDs using the validated E1 custom
transaction, including its session block and custom-mode commit:

- Typing keys flow through a gradient of Wallust colors 4, 5, 1, 3, 2 and 6.
- WASD uses color 10; Super/Fn/Menu use 13, and Ctrl/Alt/Shift use 12.
- Enter and Space use 11; Escape/Delete/Backspace use 9.
- Arrows use 14, navigation uses 6, and function keys form three groups (12–14).
- The numpad has a vertical gradient; the light bar sweeps the full gradient.

All displayed colors come from the active palette or interpolation between its
colors. The captured effect bytes are firmware protocol scaffolding. Per-key
layout selection belongs in the desktop companion profile, never shared settings.
The notebook's `features.rgb=false` returns before palette reads or device access.
Universal peripheral support remains outside this integration.

Protocol evidence comes from the [NeoGenesis protocol](https://github.com/lexmarcos/NeoGenesis/blob/972018406ea003415a4a669e959f82e338e97f79/PROTOCOL.md)
and its captured report data. `voluta/mars-keymap.json` contains opaque firmware
report bytes, not SVG/UI paint choices. `voluta/mars-custom.json` records the
validated E1 payloads and physical key coordinates from that same upstream commit.
Tests check framing, all 119 mapped LEDs, preservation of opaque prefixes,
non-accent cache invalidation, experimental gating, disabled-host isolation, and
watcher reactions to palette changes.

## Presets and selector

**Super+Ctrl+G** opens the Rofi selector when RGB is enabled. Pick both devices,
keyboard, or mouse, then a preset. Type to filter; Escape cancels without changes.
The current selection is marked. The menu inherits the active Wallust Rofi theme.
The shortcut is absent on the notebook, and can be replaced or disabled through
`keybindings["SUPER + CTRL + G"]` in companion settings.

```sh
voluta rgb list                         # IDs and descriptions as JSON
voluta rgb menu                         # target picker, then preset gallery
voluta rgb menu --target keyboard
voluta rgb select wasd                   # both configured peripherals
voluta rgb select aurora --target keyboard
voluta rgb select velvet --target mouse
voluta rgb select voluta                 # original Wallust composition
voluta rgb select off                    # darken both devices
voluta rgb                              # apply saved selections
voluta rgb --dry-run                     # inspect without hardware writes
```

`select` persists each device's `preset` in `hosts/<hostname>.json`, preserving
other host settings and leaving shared/notebook settings untouched. The existing
`layout` setting remains a fallback when a device has no explicit preset.
Selections survive restart, reconnect and updates; palette-derived presets adapt
to wallpaper changes. The public RGB default remains disabled with no devices.
`--dry-run` and `--force` belong to `apply`, and are rejected for selection so a
mistaken dry-run cannot change settings.

There are 26 paired presets. The keyboard has 104 keys plus 15 bar segments; the
mouse exposes one lighting zone, so its companion effect is simpler.

| ID | Keyboard composition | Mouse pairing |
| --- | --- | --- |
| `voluta` | Original functional gradient and palette bar | Static palette color 4 |
| `wasd` | WASD, arrows, Shift and Space highlighted | Static color 10 |
| `navigation` | Navigation island and arrows | Static color 14 |
| `vim` | HJKL, Escape and command punctuation | Static color 12 |
| `shortcuts` | Modifiers and desktop launcher keys | Static color 13 |
| `constellation` | Deterministic stars across a dim field | Static color 5 |
| `checkerboard` | Alternating colors 1 and 4 | Static color 1 |
| `ribbons` | A palette ribbon per row | Static color 5 |
| `numpad` | An illuminated numpad island | Static color 11 |
| `split` | Complementary halves and blended bar | Static color 1 |
| `accent` | A single palette accent | Static color 1 |
| `off` | All mapped lights dark | Static black |
| `velvet` | Slow violet breathing | Breathing color 5, dimmed |
| `moonlight` | Dim, slow cool breathing | Breathing color 4, dimmed |
| `heartbeat` | Five-color breathing loop | Breathing color 1 |
| `aurora` | Cool/violet breathing loop | Breathing color 4 |
| `rose` | Warm/violet breathing loop | Breathing color 1 |
| `embers` | Dim warm breathing loop | Breathing color 1, dimmed |
| `tide` | Slow cool breathing loop | Breathing color 6, dimmed |
| `fountain` | Palette stack moving up | Breathing color 4 |
| `rainfall` | Palette stack moving down | Breathing color 6 |
| `procession` | Palette stack moving right | Breathing color 4 |
| `reflux` | Faster palette stack moving left | Breathing color 6 |
| `prism` | Native rainbow wave right | Native Wave |
| `prism-rain` | Native rainbow wave down | Native Wave |
| `orbit` | Native spectrum cycle | Native Rainbow |

The names describe compositions, not independent firmware engines. The keyboard
uses breathing, stacking, wave and spectrum engines with different palette,
speed, brightness and direction settings. Wave and spectrum use firmware rainbow
colors; the menu identifies these exceptions. The M711's OpenRGB controller
exposes Static/Wave/Breathing/Rainbow/Flashing, one LED and no speed/brightness
controls. We use its native modes and scale palette colors for dim presets.
Different mouse pairings can look similar; spatial keyboard patterns cannot be
reproduced on its single exposed zone. No timing synchronization between the two
firmwares is claimed.

## Animation lifecycle and write limits

A preset change writes one complete profile; the keyboard firmware then animates
it. Multicolor breathing requires the documented `04 E0` read-only keepalive,
sent approximately every two seconds by the palette watcher. Keepalives acquire
the same nonblocking device lock as profile writes, so they cannot interleave
with a transaction. Static profiles and other engines need no polling.
Disabling RGB stops keepalives and further updates; `off` explicitly darkens LEDs.
Quitting the graphical session stops the watcher. Native effects may continue in
hardware afterward; multicolor breathing can freeze without its keepalive.

The upstream protocol investigation found no volatile lighting path in the
observed manufacturer software. We therefore never stream custom animation
frames or audio levels through onboard profile writes. Cava-style audio-reactive
animation remains unsupported for these adapters. New engines must use a proven
RAM/direct mode before implementing frame streaming. The mouse controller also
marks its modes as automatically saved in
[upstream OpenRGB](https://github.com/CalcProgrammer1/OpenRGB/blob/master/Controllers/RedragonController/RGBController_RedragonMouse.cpp).

## Validation on 2026-11-02

Both desktop devices accepted representative WASD, multicolor breathing, stack,
wave and spectrum selections. The keyboard also acknowledged two E0 keepalives;
the original companion-selected layout was restored after the checks. Firmware
acknowledgments verify accepted transactions; the owner must assess appearance
and continuous animation visually. The live watcher is active and Hyprland
reload reports no configuration errors; US/BR and Alt+Shift remain configured.

The isolated RGB source snapshot passed 36 Voluta tests plus 12 session tests
both locally and in a disposable Arch QEMU/TCG guest (48 in each environment).
The Rofi theme parsed successfully and the live gallery opened and was cancelled
without selecting a preset. Super+Ctrl+G was verified in the running compositor.

Automated checks cover all 26 preset transactions, opaque-prefix preservation,
valid LED indices, native-engine settings, per-key palette updates, host/target
isolation, menu selection/cancellation, and keepalive serialization without
profile writes. The normal CLI remains compatible with `voluta rgb --dry-run`.
The launcher and palette watcher use `/usr/bin/python3` because Homebrew/Conda
Python earlier in PATH cannot import Arch's `python-hidapi` package.

For a new installation:

```sh
sudo pacman -S --needed openrgb python-hidapi
voluta system-setup rgb
# Reconnect the keyboard, then:
voluta rgb
```

Permission errors or a rejected Mars acknowledgment remain actionable device
validation results; they must not be described as a successful test.
