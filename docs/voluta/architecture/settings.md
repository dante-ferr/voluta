# Settings ownership and updates

The first settings and companion foundation is implemented. Legacy `UserConfigs`
files are still tracked core files; the new JSON layer provides persistent
preferences without editing those files. Full extraction of existing personal
values and replacement of the old installer are not complete.

| Layer | Intended contents | Update behavior |
| --- | --- | --- |
| Public core | Theme assets, Wallust templates, reusable scripts, default configuration, generic optional integrations, anonymous examples. | Changes with core updates. |
| Personal preferences | App commands, keyboard layouts, keybindings, paths, idle policy, enabled modules, preferred visual overrides. | Preserved across core updates; optionally versioned in the companion repo/fork. |
| Host profiles | GPU workarounds, connectors/modes/scales, output placement, power differences, device IDs and enabled hardware integrations. | Personal and per-host; desktop settings must not spill into the notebook. |
| Generated output | Rendered palettes/assets and effective application config assembled from defaults and overrides. | Regenerated; never the source of user preferences. |
| Local state/cache | Session snapshots, logs, wallpaper selection, runtime locks, build products and caches. | Per machine; never copied between hosts as user preferences. |

JSON precedence is `voluta/defaults.json`, then
`~/.config/voluta/settings.json`, then `~/.config/voluta/hosts/<hostname>.json`.
`XDG_CONFIG_HOME` is respected. Objects merge recursively; arrays/scalars replace,
and `false` is an explicit override. The resolved `hyprland` object is applied
last after legacy host/power profiles on compositor start/reload. Specify explicit merge/replacement rules before implementation:
keybindings, lists, autostart actions and environment variables cannot all be
handled as simple last-write-wins values. Separate login-time environment from
compositor-time configuration; the latter cannot fix an earlier GPU-open failure.

Use XDG config/state/cache/runtime locations according to file ownership, with
documented exceptions for applications that require generated colors beside their
config. Missing personal settings and unknown hosts should use portable defaults.
Settings examples must be optional and must never replace existing user files.
Future update/install work must back up and migrate existing configs and symlinks
before replacement, retain explicit overrides, and report obsolete keys without
silently discarding them. Keep core checkout files free from application writes.


## Implemented CLI

Run `./bin/voluta` from the checkout; it uses only Python's standard library.
No global command, remote repo, or personal settings are installed automatically.
For a fresh configuration:

```sh
./bin/voluta init
./bin/voluta show
./bin/voluta feature list
./bin/voluta feature enable session_restore
./bin/voluta feature disable session_restore
./bin/voluta feature disable dolphin
./bin/voluta feature enable dolphin
./bin/voluta config set input.kb_layout '"us,br"'
./bin/voluta config set input.kb_variant '",abnt2"'
./bin/voluta config set input.repeat_rate 35 --scope host
./bin/voluta config reset input.repeat_rate --scope host
```

On the owner's existing setup, use `init --preserve-session` instead of `init`
to preserve the current session-restoration preference. Without initialized
settings, existing Dolphin/session behavior is deliberately retained. Changing
preferences requires initialization first so choosing one module cannot silently
change another legacy behavior. Re-running init preserves the existing file.

`feature reset <name>` removes an override so the inherited value applies again.
Use `--scope host` for a machine-only selection; shared is the default write scope.
`--host <name>` and `--config-dir <path>` are global options before the subcommand,
useful for managing a second host and testing isolated settings. Writes are
serialized and atomic. Invalid version/sections/features fail with a diagnostic
without replacing the source file. State locks live outside the companion repo.
Hyprland values are passed through to `hl.config`; they must be valid for the
installed compositor. This version does not customize keybindings, monitor rules,
autostart lists, or login environment through JSON.

### Feature activation

Only `dolphin` and `session_restore` currently have working feature controls.
Other optional integrations remain planned; the CLI does not claim to activate
them. Dependency installation is not implemented yet; enabling Dolphin requires
the existing Dolphin toolchain/dependencies to be present.

Dolphin changes apply on its next launch. Disabling bypasses the compiled hook
and skips the Qt/Dolphin palette publisher; it does not uninstall Dolphin,
restore old global Qt settings, or unload libraries from already open windows.
Restart Dolphin to remove the existing hook. Full managed-settings cleanup is
part of the installer/module migration still to come.

The new session supervisor starts at the next graphical login (a Hyprland reload
does not run startup hooks). Thereafter it notices settings changes within about
a second. Enabling mid-session starts autosave without reopening windows;
enabling before login restores once then saves. Disabling stops its worker and
shutdown watcher, preserving snapshots. The old power-menu save command remains
in place for now. The supervisor exits when its compositor socket disappears.
No current desktop processes were restarted during implementation.

### Companion checkout

The companion is an ordinary local directory/repository with `settings.json` and
optional `hosts/<hostname>.json` files. No Git provider or special sync tool is
required. Create a separate checkout and initialize its settings, for example:

```sh
./bin/voluta --config-dir ~/voluta-personal init --preserve-session
./bin/voluta companion attach ~/voluta-personal
```

Attach creates a directory symlink at the personal settings location. It refuses
to overwrite an existing directory, file, or different symlink; back up and merge
existing settings deliberately first. Reattaching the same companion is safe.
`examples/companion/` contains an anonymous skeleton; rename the example host
file to the real hostname before expecting it to apply. Companion changes are
committed/synchronized separately; do not commit runtime state or secrets there.

### Remaining work

- Extract all actual host/personal values into a private companion, preserving
  login-time GPU policy and verifying both machines before removing legacy files.
- Build an Arch installer/updater with backups, owned-file tracking, dependency
  selection, module activation/cleanup, and safe application-generated state.
- Migrate remaining app commands, keybindings, display/idle policy and shell setup.
- Complete Voluta branding without breaking compatibility paths.
- Prototype device RGB and validate on physical hardware.
- Run fresh-install/update acceptance checks in a VM when available.

The current integration relies on the existing symlinked `~/.config/hypr`
checkout layout. It is a migration foundation, not yet a standalone public
installer. Verify it with `python3 -m unittest discover -s tests -v` and the
existing session-manager tests; VM and real login validation remain outstanding.
