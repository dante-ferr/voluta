# Agent notes

This repository is the shared Hyprland configuration for two machines.
`hyprland.lua` loads `hypr/hosts/<hostname>.lua`, then
`hypr/hosts/<hostname>-power.lua`.

## Hosts

| Hostname | Hyprland GPU | Do not do |
| --- | --- | --- |
| `frank` | NVIDIA. `__GLX_VENDOR_LIBRARY_NAME=nvidia` is set in `hypr/hosts/frank.lua`. | Do not set `LIBVA_DRIVER_NAME=nvidia`, `NVD_BACKEND=direct`, or `GBM_BACKEND`. |
| `frank-notebook` | Intel iGPU only. Mesa GLX and `LIBVA_DRIVER_NAME=iHD` in `hypr/hosts/frank-notebook-power.lua`. | Do not load `hosts/frank.lua`. Do not set `CUDA_VISIBLE_DEVICES` empty. ML jobs must still be able to open the discrete GPU. |

`hosts/frank.lua` is desktop-only. A hostname check is the gate. Do not copy those variables into `UserSettings.lua`, `zshrc`, or `~/.config/uwsm/env`.

## SDDM login loop

Symptom: the password is accepted, the screen waits one or two seconds, then the password field clears and the greeter asks again. Hyprland never stays up.

SDDM runs `zsh --login`, which sources `zprofile`, then execs `uwsm`. If that shell exits, or Hyprland exits while opening the GPU, SDDM restarts the greeter. That is the loop.

Rules:

- `zprofile` stays on the login path. No `exit`, no `set -e`, no command that can fail the shell, and do not source `zshrc` from it.
- `zshrc` returns immediately when the shell is not interactive, so oh-my-zsh, conda, and starship cannot run during login.
- Do not export `GBM_BACKEND`. `nvidia-drm` makes Hyprland fail the DRM open and return to the password field.
- Do not export `LIBVA_DRIVER_NAME=nvidia` or `NVD_BACKEND=direct` anywhere. On `frank` that path SIGILL-crashes Brave, exhausts the GPU BAR1 window, and Hyprland aborts on the GL reset. The restarted session is the built-in Hyprland theme.
- Client GLX for `frank` is set from `hosts/frank.lua` after the compositor is up, not from the login shell.
- A fatal error in `hyprland.lua` at startup has the same effect as a GPU open failure. `hyprctl reload` on a running session does not. Check `hyprctl configerrors` before logging out.

Each graphical login appends one line to `~/.local/state/graphical-login.log`.

## Wallust colors for SVGs and text

- SVG artwork and UI text must use the active Wallust palette. Do not introduce fixed SVG paint colors or fixed text colors.
- Use Wallust color tokens in stylesheets and Wallust templates for SVG fills and strokes. Derive muted, hover, and contrast colors from those tokens rather than hard-coded colors.
- Regenerate palette-dependent assets and reload their consumers when the wallpaper changes, so artwork and text follow the current palette on both hosts.

- Keep reusable SVG source assets in `wallust/assets/` and palette-rendered SVGs in `wallust/assets/generated/`; consumers should share these assets instead of keeping private copies.
