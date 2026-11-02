# Wallust RGB integration

Status: deferred; compatibility research only, no device writes tested.

The owner wants wallpaper-driven keyboard and mouse lighting after the settings
boundary is decided. Detected desktop devices are HyperX Mars `0951:16c6` and a
wired mouse `04d9:fc30` matching the Redragon M711 family. Detection is not proof
that writing colors works; no installation or device-write test has been done.

- Keyboard candidate: [NeoGenesis](https://github.com/lexmarcos/NeoGenesis),
  including its documented HID protocol. Its documented GUI workflow will need
  evaluation for a headless helper; do not assume a CLI exists.
- Mouse candidate: [OpenRGB](https://openrgb.org/); its source registers that USB
  ID and implements a configurable static color. Verify the installed version,
  detection and device behavior before wiring automatic updates.
- Keep reusable RGB support optional in the core; store device selection and
  enablement in the desktop profile. Require both explicit enablement and matching
  hardware; the notebook and unknown hosts must skip it harmlessly.
- Consume the generated Wallust palette, initially a static accent. Refresh on
  wallpaper changes and desktop startup; serialize writes, skip unchanged colors,
  and let absent devices/tools or permission failures leave desktop startup and
  palette publication working. Evaluate whether commands save to onboard memory
  before choosing refresh frequency. Do not add RGB tools to every host's mandatory
  dependencies or run the whole desktop as root for device access.

## Feasibility and support boundary

RGB control depends on the exact model, firmware, connection mode (USB, wireless
receiver or Bluetooth), and capabilities exposed by the backend. Support for a
brand does not establish support for every device.

The proposed public feature is a Wallust-to-backend bridge for compatible
devices, not universal peripheral support. Prefer an established backend such as
OpenRGB where the exact device is supported. Start with static accents; negotiate
capabilities rather than promising per-key colors or effects on every device.
Unsupported devices must be skipped with a useful status. Do not attempt generic
HID writes to unknown devices.

The Mars helper is a separate, model-specific candidate. Keep it experimental
until its protocol, firmware compatibility and writes are validated on the real
keyboard. Its reusable implementation may live in an optional adapter; the
owner’s selection belongs in the desktop companion profile. Building and
maintaining a broad reverse-engineered device-driver collection is outside the
proposed scope.

These are proposed limits for implementation review. The mouse has a promising
existing backend; keyboard automation still needs a prototype. No compatibility
claim should be upgraded to verified without an actual device test.
