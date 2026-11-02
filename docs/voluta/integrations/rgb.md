# Wallust RGB integration

Status: implemented bridge with OpenRGB and an experimental HyperX Mars adapter.
Physical lighting changes are not yet verified on the owner's devices.

Enable RGB for a particular host and list explicit devices in its companion JSON:

```json
{
  "version": 1,
  "features": {"rgb": true},
  "rgb": {
    "accent": "wc_1",
    "devices": [
      {"backend": "openrgb", "usb_id": "04d9:fc30", "name": "Redragon M711 Cobra"},
      {"backend": "hyperx-mars", "usb_id": "0951:16c6", "experimental": true}
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
last successful color/device generation. Reconnects invalidate the cached USB
generation. Unknown backends are rejected; absent devices are skipped. Permission
and dependency failures report unavailable status without blocking desktop startup
or palette generation. The palette watcher retries on wallpaper/settings changes
and periodically for newly connected devices. Disabling stops future updates;
it does not restore an undocumented prior hardware profile or turn lights off.

OpenRGB uses only the selected controller name, static mode and hex accent. Its
package provides device rules; no blanket root execution is used for color writes.
The Mars backend requires `python-hidapi`, interface 0/usage page 1, explicit
experimental selection and exact model matching. Install the narrow rule through
`voluta system-setup rgb`, then reconnect the keyboard. Do not run the desktop or
palette watcher as root.

The Mars sends a complete firmware profile transaction and checks handshake,
header and final acknowledgments. It may save onboard state; identical successful
colors are skipped to avoid gratuitous writes. Static accent is supported here;
per-key effects and universal peripheral support are outside this implementation.

Protocol evidence comes from the [NeoGenesis protocol](https://github.com/lexmarcos/NeoGenesis/blob/972018406ea003415a4a669e959f82e338e97f79/PROTOCOL.md)
and its captured report data. `voluta/mars-keymap.json` contains opaque firmware
report bytes, not SVG/UI paint choices. Tests check report framing, static color,
commit, experimental gating, missing-device behavior and unchanged-color caching.

## Validation on 2026-11-02

Both USB IDs were detected and the actual Wallust accent was resolved in dry-run.
The apply attempt reported OpenRGB and python-hidapi missing. Privileged setup
requires the owner’s sudo authentication; the agent cannot supply it. Therefore
no successful physical color write is claimed. In the owner's normal terminal:

```sh
sudo pacman -S --needed openrgb python-hidapi
voluta system-setup rgb
# Reconnect the keyboard, then:
voluta rgb
```

Permission errors or a rejected Mars acknowledgment remain actionable device
validation results; they must not be described as a successful test.
