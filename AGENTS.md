# Agent guide

Voluta is the selected public name for this cyber baroque Hyprland desktop.
Personal preferences and host policy live in the separate companion repository;
keep the public defaults portable.

## Documentation and scope

- Start at [docs/voluta/index.md](docs/voluta/index.md); the complete navigation is
  [SUMMARY.md](docs/voluta/SUMMARY.md). Keep detailed specifications in docs and
  keep this file limited to essential instructions and links.
- The accepted direction is a public core plus a private companion repo, with
  persistent settings under `${XDG_CONFIG_HOME:-$HOME/.config}/voluta/`. Core
  updates must preserve explicit user overrides.
- Read [decisions and scope](docs/voluta/architecture/decisions.md) before migration
  work. Implementation is authorized; use the documented local and Arch VM checks.
  Track behavior and validation limits in the docs. Remote
  repository creation/publication still requires a concrete destination.
- Inspect `git status` and preserve unrelated changes. Do not invoke
  legacy host-copy behavior (the script is now retired) or run the rice switcher
  as a documentation check. See the [audit](docs/voluta/engineering/configuration_audit.md).

## Runtime guardrails

- Read [runtime constraints](docs/voluta/engineering/runtime_constraints.md) before
  changing GPU, login, locking, or suspend behavior. Keep host overrides scoped:
  `frank` uses NVIDIA; `frank-notebook` runs the desktop on Intel. Never load the
  desktop profile on the notebook or mask its CUDA GPU.
- Never export `GBM_BACKEND`, `LIBVA_DRIVER_NAME=nvidia`, or `NVD_BACKEND=direct`.
  Keep desktop client GLX in its host profile after compositor startup.
- Keep `zprofile` non-fatal: no `exit`, `set -e`, or sourcing `zshrc`. `zshrc`
  must return immediately for noninteractive shells. Check `hyprctl configerrors`
  before logout after changing compositor configuration.

## Palette and assets

- SVG paints and UI text must follow the active Wallust palette. Derive muted,
  hover and contrast colors from palette tokens; do not introduce fixed colors.
- Share SVG sources in `wallust/assets/` and rendered assets in
  `wallust/assets/generated/`. Regenerate and reload consumers on wallpaper changes.

## Secrets and commits

- Never display `.env` contents or secret values, and never commit `.env`. When
  changing `.env.example` keys, sync `.env` in the same change using a key-only
  script: append missing keys with empty values, preserve existing values and
  extra keys, and never copy sample values. Report key names only; use
  `nonempty=true/false` if necessary.
- Use Conventional Commits: `<type>[optional scope][!]: <description>`. Use `feat`
  for features and `fix` for bug fixes; mark breaking changes with `!` or a
  `BREAKING CHANGE:` footer. Separate optional body/footers with blank lines.
