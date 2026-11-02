# Core and optional features

Status: implemented preset. Dolphin customization is enabled by default; all
other integrations below are opt-in and can be changed after installation.

Core means the maintained baseline for a complete Voluta desktop, not an
unconfigurable choice of every application. Optional integrations must be
independently enabled, install dependencies only when selected, and leave the
core usable when disabled or unavailable. The companion stores selections and
personal values; reusable integration implementations belong in the public core.

| Classification | Features |
| --- | --- |
| Core desktop | Hyprland session, window/workspace controls and base keybindings; Waybar, launcher, notifications/OSD; wallpaper and Wallust palette pipeline; shared artwork, typography and application styling; lock/idle controls, screenshots, clipboard, audio/media/brightness controls; a default terminal and file-manager experience. |
| Optional integrations | SDDM theme installation; browser-specific theming/extensions (Brave/Floorp); developer shell tooling (conda, Android SDK, Linuxbrew, etc.); OBS controls; RGB device support; session save/restore; switching to a second rice; advanced Dolphin injection/build tooling. |
| Personal/host values | Preferred apps, keyboard layouts, bindings, paths, idle timings, module enablement, monitor profiles, device IDs, Bluetooth targets, and machine-specific GPU/power workarounds. These are settings rather than separately shipped features. |

Accepted default preset: enable Dolphin, including the advanced customization
integration, by default. Keep it independently disableable. Session restoration
is optional and disabled unless selected. Existing personal session-restore
behavior must be preserved when migrating the owner’s setup; the public default
must not silently disable that preference. Generic hardware detection
and safe portable fallback behavior are core responsibilities; known machine
workarounds must remain scoped to personal host profiles.

## Optional feature lifecycle

Accepted requirement: declining a feature during installation is not permanent.
Users must be able to enable it later without reinstalling Voluta, and disable
and re-enable it independently. This also applies to default-enabled optional
integrations such as Dolphin customization.

The feature lifecycle contract is:

- Persist explicit enable/disable selections in personal settings, with host
  overrides where appropriate; updates must preserve an installation-time decline.
- Offer the same feature discovery and selection after installation. CLI/UI
  selections use `voluta feature`; see [settings](settings.md).
- On enable, check capabilities and dependencies, install only the selected
  module’s missing dependencies through the normal setup flow, and configure and
  start/reload its consumers. Separate requested state from activation success;
  explain missing hardware, permissions, or failed setup without breaking core.
- On disable, stop module-owned background work and remove only its managed hooks
  and overrides. Preserve personal settings so re-enabling restores preferences.
  Do not automatically uninstall packages shared with other modules/applications.
- Make repeated enable/disable operations safe and avoid duplicate daemons,
  keybindings or startup actions.

Validate skipped-at-install → enabled-later → disabled → re-enabled, plus core
updates while a feature is explicitly disabled. See [settings](settings.md) for implemented activation, privilege and restart
semantics. External dependencies and physical hardware still require validation.
