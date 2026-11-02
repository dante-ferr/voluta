# Settings ownership and updates

The ownership separation and update policy are accepted; exact file layouts and
merge mechanisms still need design. This is not an implemented settings system.
Current `UserConfigs` files are tracked core
files and do not provide update-safe personal overrides merely by their names.

| Layer | Intended contents | Update behavior |
| --- | --- | --- |
| Public core | Theme assets, Wallust templates, reusable scripts, default configuration, generic optional integrations, anonymous examples. | Changes with core updates. |
| Personal preferences | App commands, keyboard layouts, keybindings, paths, idle policy, enabled modules, preferred visual overrides. | Preserved across core updates; optionally versioned in the companion repo/fork. |
| Host profiles | GPU workarounds, connectors/modes/scales, output placement, power differences, device IDs and enabled hardware integrations. | Personal and per-host; desktop settings must not spill into the notebook. |
| Generated output | Rendered palettes/assets and effective application config assembled from defaults and overrides. | Regenerated; never the source of user preferences. |
| Local state/cache | Session snapshots, logs, wallpaper selection, runtime locks, build products and caches. | Per machine; never copied between hosts as user preferences. |

Proposed precedence is core defaults, then personal preferences, then the selected
host's overrides. Specify explicit merge/replacement rules before implementation:
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
