# Runtime and hardware constraints

These describe the current personal setup, not portable public defaults. Preserve
these behaviors until an explicitly authorized migration replaces them.

This repository is the shared Hyprland configuration for two machines.
`hyprland.lua` loads companion `shared.lua`, then
`~/.config/voluta/hosts/<hostname>.lua`, then `<hostname>-power.lua`.

## Hosts

| Hostname | Hyprland GPU | Do not do |
| --- | --- | --- |
| `frank` | NVIDIA. `__GLX_VENDOR_LIBRARY_NAME=nvidia` is set in `~/.config/voluta/hosts/frank.lua`. | Do not set `LIBVA_DRIVER_NAME=nvidia`, `NVD_BACKEND=direct`, or `GBM_BACKEND`. |
| `frank-notebook` | Intel iGPU only. Mesa GLX and `LIBVA_DRIVER_NAME=iHD` in `~/.config/voluta/hosts/frank-notebook-power.lua`. | Do not load `hosts/frank.lua`. Do not set `CUDA_VISIBLE_DEVICES` empty. ML jobs must still be able to open the discrete GPU. |

`hosts/frank.lua` is desktop-only. A hostname check is the gate. Do not copy those variables into `UserSettings.lua`, `zshrc`, or `~/.config/uwsm/env`.

## SDDM login loop

Symptom: the password is accepted, the screen waits one or two seconds, then the password field clears and the greeter asks again. Hyprland never stays up.

SDDM runs `zsh --login`, which sources `zprofile` and its generated
`voluta-login-env.sh`, then execs `uwsm`. If that shell exits, or Hyprland exits while opening the GPU, SDDM restarts the greeter. That is the loop.

Rules:

- `zprofile` stays on the login path. No `exit`, no `set -e`, no command that can fail the shell, and do not source `zshrc` from it.
- `zshrc` returns immediately when the shell is not interactive, so oh-my-zsh, conda, and starship cannot run during login.
- Do not export `GBM_BACKEND`. `nvidia-drm` makes Hyprland fail the DRM open and return to the password field.
- Do not export `LIBVA_DRIVER_NAME=nvidia` or `NVD_BACKEND=direct` anywhere. On `frank` that path SIGILL-crashes Brave, exhausts the GPU BAR1 window, and Hyprland aborts on the GL reset. The restarted session is the built-in Hyprland theme.
- Client GLX for `frank` is set from `hosts/frank.lua` after the compositor is up, not from the login shell.
- A fatal error in `hyprland.lua` at startup has the same effect as a GPU open failure. `hyprctl reload` on a running session does not. Check `hyprctl configerrors` before logging out.

Each graphical login appends one line to `~/.local/state/graphical-login.log`.


## Migrated settings and reload validation

Personal host Lua, login environment, desktop Waybar connector, Qt RHI policy,
idle profiles and renderer-resume hooks live in `~/voluta-personal`. Public
`UserSettings.lua` has portable input/cursor defaults. The compositor resolver
must load the private values before relying on those defaults for the owner's
session. Check both `input:kb_layout` and `input:kb_options`, plus the resolved
browser preference, after a migration reload. A successful configerrors query
alone does not prove that the intended preferences were applied.

## Notebook wake recovery (2026-11-03)

Read `/etc/hostname` when selecting host resume policy, consistently with
`StartHypridle.sh`. Arch does not guarantee the optional `hostname` executable;
its absence silently bypassed the companion recovery hook on this notebook.
Keep compositor IPC bounded and retain errors. Resume may restore a missing
locker only when the compositor reports that the session is already locked.
Never clear a session lock or kill the locker as an automatic recovery action.

The notebook hook now restores display/output presentation without a fixed
pre-recovery delay. Lifecycle/error logs live under
`~/.local/state/voluta/lock/`; do not enable raw keyboard/password tracing.
Concurrent lock requests use the shared `LockScreen.sh` launcher.

Validated with isolated routing/concurrency/timeout checks and live wake-hook
execution: display wake and renderer recovery succeeded, configerrors was empty,
and the idle daemon held its sleep delay inhibitor. A physical suspend/resume
with password entry remains to be checked; live hook execution alone does not
prove an intermittent freeze is eliminated.
