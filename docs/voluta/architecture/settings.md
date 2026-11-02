# Settings, installation and the companion

Status: implemented. Arch Linux is supported; use a regular desktop account.
AUR dependencies require `paru` or `yay`. No remote repository is created.

## Ownership and precedence

| Layer | Location and behavior |
| --- | --- |
| Public defaults and code | Core checkout. Pull changes here, then run `voluta update`. |
| Shared personal preferences | `${XDG_CONFIG_HOME:-~/.config}/voluta/settings.json`. Preserved across updates. |
| Host preferences | `voluta/hosts/<hostname>.json` under the personal settings directory. Override shared values. |
| Optional Lua hooks | Companion `shared.lua`, then `hosts/<hostname>.lua`, then `<hostname>-power.lua`. Trusted personal code. |
| Deployed application config | `${XDG_DATA_HOME:-~/.local/share}/voluta/current/`. Config links point here so app writes cannot dirty the public checkout. |
| Backups and ownership manifest | `${XDG_STATE_HOME:-~/.local/state}/voluta/`. Retained across updates/uninstall. |
| Palettes, sessions and runtime files | Local generated output/state. Never synchronize as shared preferences. |

JSON objects merge recursively; arrays/scalars replace. `false` explicitly
disables a feature or named command. Removing an override restores inheritance.
The `hyprland` object and declarative monitor/workspace rules apply after personal
Lua hooks. Keybinding overrides replace matching default chords; new chords are
additive. Named `startup` commands run once at login; false disables an entry.

The compositor loader validates complete helper output rather than relying on
`pclose()` status: Hyprland may reap that child early and return ECHILD. It keeps
last-known-good preferences on a later helper failure. Tests cover this behavior;
input settings must also be checked in the live compositor after migration.

## Commands

```sh
./bin/voluta init
./bin/voluta install --dry-run
./bin/voluta install
voluta show
voluta feature list
voluta feature enable session_restore
voluta feature disable session_restore
voluta feature enable rgb --scope host
voluta feature reset rgb --scope host
voluta config set input.kb_layout '"us,br"'
voluta config set input.kb_variant '",abnt2"'
voluta config set input.repeat_rate 35 --scope host
voluta config reset input.repeat_rate --scope host
voluta update
voluta doctor
voluta uninstall
```

`config set/reset` edits Hyprland options. Other settings sections are editable
JSON. Global `--host <name>` and `--config-dir <path>` precede the subcommand.
`get <dotted-key>` reads any resolved setting as JSON. Writes are serialized and
atomic, preserve companion symlinks, and reject unsupported schema versions.
Invalid compositor options still need correction; they are not silently migrated.

`init --preserve-session` records the old always-on session-restore preference.
Repeated init preserves existing files. Uninitialized legacy configurations retain
existing Dolphin/session behavior, but a fresh `init` defaults restoration off.

## Schema version 1

| Section | Purpose |
| --- | --- |
| `features` | Boolean selections: dolphin, session_restore, rgb, browser, developer_shell, obs, sddm, rice_switch. |
| `hyprland` | Options passed to `hl.config`. |
| `apps` | terminal, browser and file_manager launch commands. |
| `environment` | Login-time exports; null means unset. Unsafe known GPU backends are rejected. Run update/apply to regenerate the login script. |
| `paths` | wallpapers directory and optional other_rice checkout. |
| `keybindings` | Chord → command or false; matching defaults are replaced. |
| `startup` | Name → command or false; login-only custom actions. |
| `monitors`, `workspaces` | Arrays of Lua API-compatible rule objects, replacing inherited arrays. |
| `waybar_output` | Connector name or null for the normal all-output configuration. |
| `dolphin_rhi` | Host-specific Qt rendering workaround. |
| `rgb` | Palette accent token and explicitly selected USB/backend device records. |
| `appearance` | Shared palette background source and darkening; see [Shared background](../integrations/theme.md). |

Personal shell code lives in `shell/interactive.zsh` and is sourced only for an
interactive shell with developer_shell enabled. The login path only sources the
generated `voluta-login-env.sh`; it never invokes developer tooling. Compositor
client GLX policy stays in the private host Lua hook, after compositor startup.

Host idle files are `idle/<hostname>.conf`; resume hooks are
`resume/<hostname>.sh`. Local nwg-displays outputs remain local; companion
`displays/<hostname>/{monitors,workspaces}.conf` supplies a host-specific fallback.
Declarative JSON rules override both. Never put a desktop layout in a shared
fallback that affects the notebook.

## Companion repository

The local companion created for the owner is `~/voluta-personal`, linked from
`~/.config/voluta`. It includes both host profiles, shell preferences, scoped
idle/resume/display policy and shared app/input choices. It has no remote.
Install/attach this companion on the notebook before updating its old checkout;
copying public defaults alone intentionally does not recreate private hardware policy.

For another user:

```sh
./bin/voluta --config-dir ~/voluta-personal init
./bin/voluta companion attach ~/voluta-personal
```

Attach refuses an existing settings directory or a different symlink. Back up and
merge deliberately first. `examples/companion/` contains an anonymous skeleton.
Version personal preferences separately, without `.env`, credentials, generated
palettes, session snapshots, logs or VM images. No provider or Git remote is needed.

## Installer, updates and rollback

The installer backs up replaced config directories/symlinks, copies maintained
sources into the deployment tree, preserves generated palettes/display state,
and merges only its integration hook into Waypaper's writable preferences.
Explicit wallpaper-path preferences win; GUI changes survive when that path is
not explicitly overridden. Changed managed files receive backups before update.
Core defaults update from the checkout without rewriting companion preferences.

Missing selected dependencies are installed through pacman/paru/yay. Native
Waybar support builds locally. Initial Wallust colors are seeded when missing.
`--skip-deps` deploys configuration only and skips native/privileged setup; it is
intended for provisioning environments and tests, not dependency verification.
The installed CLI delegates updates to the recorded source checkout. Pull that
checkout first; updates never discard uncommitted source changes or auto-pull.

Feature selection is distinct from activation. A dependency/setup failure leaves
the explicit selection saved and reports that activation needs attention. Running
`apply` retries enabled-module setup. Skipped features can be enabled later.
Disabling keeps settings and shared packages; session workers and owned module
links/system drop-ins are stopped/restored where applicable. Dolphin's already
loaded library needs a normal application restart; no file transfers are killed.
Core Qt palette generation continues when advanced Dolphin customization is off.

`uninstall` restores owned links and saved original files only when still managed.
It retains preferences, deployed app state and backups, and does not remove
packages. Switching an external rice only changes symlinks and records their
previous targets; run `rice-switch` again to return before updating Voluta.

SDDM and exact-model HID access require explicit privileged setup. They do not
restart SDDM. The SDDM QML remains root-owned; a dedicated, user-writable color-only
file lets the next greeter use the newest Wallust palette without repeated sudo.
Legacy Imperium filenames/theme identifiers remain compatibility details, while
public branding and the CLI use Voluta.
