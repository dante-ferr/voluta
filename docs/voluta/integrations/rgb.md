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

## Validation on 2026-11-02

Both desktop devices reported successful hardware writes using Arch's system
Python; the Mars acknowledged the E1 profile transaction. Physical appearance of
the new per-key layout still needs the owner's visual assessment. The live watcher
is active and Hyprland reload reports no configuration errors; US/BR and
Alt+Shift remain configured. Seven RGB tests cover packet construction, palette
changes, cache behavior, and notebook isolation; the full local suite also passes.

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
