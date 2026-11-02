# Voluta

A cyber baroque Hyprland desktop with wallpaper-driven Wallust colors. Arch Linux
is the supported platform. The checkout retains several Imperium identifiers for
compatibility with existing themes and integrations.

## Install

Run as your regular desktop user on Arch Linux. Python is required to bootstrap.
Have an AUR helper (`paru` or `yay`) available for dependencies not in the official
repositories, including the appropriate Wallust/Waypaper packages.

```sh
./bin/voluta init
./bin/voluta install --dry-run
./bin/voluta install
```

The installer backs up existing files and links before deploying configuration to
`~/.local/share/voluta/current`. Your preferences live separately under
`~/.config/voluta/`. Start a Hyprland session through your existing session manager;
Voluta does not change your login shell or enable a display-manager service.

Dolphin customization is on by default. Session restoration and browser, RGB,
OBS, developer-shell, SDDM and alternate-rice integrations are optional. Existing
users should attach their companion before updating personal host configurations.

## Configure and update

```sh
voluta feature list
voluta feature enable session_restore
voluta feature disable session_restore
voluta feature enable rgb --scope host
voluta config set input.kb_layout '"us,br"'
voluta update
voluta doctor
```

Features skipped during installation can be enabled later. Enabling installs
missing dependencies; disabling preserves preferences and shared packages.
`voluta update` deploys the current source checkout; pull source changes first.
Use the checkout's `bin/voluta update` after pulling when updating the deployed CLI.
`--skip-deps` deploys configuration only and skips privileged system integration,
for provisioning/testing environments where dependencies are managed separately.
`voluta uninstall` restores replaced config links and keeps personal settings and
backups. Never edit generated palettes as a source of preferences.

## Companion repository

Your private repository contains `settings.json`, `hosts/<hostname>.json`,
optional shared/host Lua hooks and personal shell/display/idle inputs. Attach an
existing checkout with `voluta companion attach /path/to/companion`. Attachment
refuses to overwrite an existing settings directory. No remote is created by the
installer. An anonymous skeleton is available in `examples/companion/`.

## Documentation

Start at [the documentation overview](docs/voluta/index.md) or
[the complete summary](docs/voluta/SUMMARY.md). See
[settings and installation](docs/voluta/architecture/settings.md),
[RGB compatibility](docs/voluta/integrations/rgb.md), and
[validation coverage](docs/voluta/engineering/installation_testing.md).
