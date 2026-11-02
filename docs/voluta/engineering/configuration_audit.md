# Configuration separation audit

Historical audit from planning on 2026-11-02. Recheck source files before implementing.
The first foundation has since retired the host-copy script and unified the
alternate startup module. See [current implementation](../architecture/settings.md)
for those changes and the new override/feature controls. Remaining rows describe
the legacy source inventory, not a completed migration.

These are verified source locations, not an exhaustive publication/privacy audit.
Move personal values to the selected personal layer; retain reusable loaders and
capabilities in the public core. Do not move entire files blindly when they mix
theme behavior, preferences, and hardware fixes.

| Location | Finding / migration concern |
| --- | --- |
| `hypr/hyprland.lua`, `hypr/hosts/*.lua` | Hostname-selected desktop/notebook profiles; host then host-power load order. Several Lua files fall back to `/home/dante` and assume `~/.config`. |
| `hypr/UserConfigs/UserSettings.lua` | Shared visual defaults, personal US/BR layout and input preferences, and NVIDIA-related environment cleanup/cursor behavior are mixed. |
| `hypr/configs/SystemSettings.lua` | Another defaults file with overlapping values; it is not loaded by the current master config. Do not treat it as the effective baseline. |
| `hypr/configs/Startup_Apps.lua` | The active startup module; starts session restoration and changes the default file manager as well as desktop services. Preferences and optional modules need explicit ownership. |
| `hypr/UserConfigs/Startup_Apps.lua`, `hypr/UserScripts/auto_host_link.sh` | Alternate startup module is not loaded by the master. It invokes a script that copies a host profile over tracked `UserSettings.lua`. Do not invoke this script or re-enable that startup path; replace this overwrite mechanism during migration. |
| `zprofile`, `zshrc` | Host GPU handling exists outside Hyprland. The shell also contains personal developer tooling, conda auto-activation, Android SDK setup, aliases, and a Bluetooth shortcut with a fixed device address. Do not reproduce the address in public examples. |
| `hypr/scripts/waybar-config.sh` | Desktop-only `frank` branch pins Waybar to `DP-2`; other hosts keep the base config. |
| `dolphin/launch.sh` | Desktop-only Qt RHI workaround; preserve its scope. Generic theme injection can remain a reusable integration. |
| `hypr/UserConfigs/UserDecorations.lua`, `hypr/scripts/after_sleep.sh`, `hypr/hyprlock.conf` | Hardware-motivated rendering, Brave effects and resume/lock behavior also live in shared files. Evaluate which are general fixes versus host policy; preserve login/lock safety during extraction. |
| `hypr/hypridle.conf`, `hypr/hypridle.frank-notebook.conf`, `hypr/scripts/StartHypridle.sh` | Existing hostname-selected idle policies. Notebook omits DPMS; both contain an absolute home path. Timings are user preferences. |
| `hypr/monitors.lua`, `hypr/workspaces.lua`, `.gitignore` | Load ignored `nwg-displays` output and fall back when absent. Notebook power profile additionally specifies its panel mode. Preserve local display state. |
| `hypr/UserConfigs/UserKeybinds.lua` | App choices, named Horizontal/Vertical/Notebook display profiles, screenshot paths, OBS, old illogical-impulse shortcut, and checkout-name assumptions. Bind customization needs replacement/removal semantics to prevent duplicate actions. |
| `rice-switch.sh`, `rice-select.sh` | Personal two-rice workflow, package/bootstrap policy and automatic Floorp installation are mixed with linking. Whole config directories/home files can be removed and replaced with checkout symlinks. Do not run the switcher to audit or test this documentation task. |
| `dolphin/apply-config.py`, `dolphinrc`, `dolphin/view-properties` | Existing partial separation: tracked appearance keys are merged into real local files to preserve unrelated application state. Managed keys still overwrite same-key user choices on launch; this is not yet a general override system. |
| `waypaper/config.ini` | Mixed integration settings, personal wallpaper directory, absolute stylesheet path and writable app preferences. GUI writes can reach tracked files through directory symlinks. |
| `wallust/wallust.toml`, `.gitignore` | Templates versus ignored rendered outputs already have a useful separation; review all targets and tracked outputs for consistency. Generated files beside app configs are not user settings. |
| `hypr/scripts/session_manager.py` | Local session snapshots include window metadata/working directories; keep under local state, outside public config and cross-host sync. |
| `brave/`, `hypr/UserScripts/paint_brave_theme.py` | Browser-specific integration and generated GTK theme publication; make optional if that scope is selected. Preserve work already underway in these files. |
| `sddm/install.sh`, `sddm/theme.conf` | System-wide installation, external base-theme/font assumptions and fixed display dimensions need a separate optional setup policy. |
| `deps/arch.txt`, `deps/dolphin.txt`, `zshrc` | Distinguish desktop requirements, optional app/build dependencies and personal development tools. Public portability is not currently distribution-independent. |
| `waybar/lib/`, `fastfetch/`, `hypr/assets/`, `swaync/` | Before publication, check generated/build artifacts and artwork/font provenance and redistribution rights. Ignore rules do not untrack files already committed. |
