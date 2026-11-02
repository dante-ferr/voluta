# Remember the last Hyprland session

`configs/Startup_Apps.lua` starts the Voluta session supervisor on graphical
login. With session restoration enabled, it runs `session_manager.py start` to
restore the saved session before starting autosave. New initialized Voluta
settings default restoration off; existing uninitialized setups retain it.
Use `bin/voluta init --preserve-session` to migrate that preference explicitly.
After the first login with the supervisor, `bin/voluta feature enable
session_restore` starts autosave during the current session without reopening
windows; disabling it stops the worker and shutdown watcher. A lock
prevents duplicate managers or a second restore in the same compositor instance.
There are no permanent app-to-workspace assignments.

The snapshot records each window's workspace, monitor name, title, floating
geometry, fullscreen state, launch command, and terminal working directory.
Windows are matched by class and title after apps reopen, then moved individually.
Browser launches retain profile arguments and Chromium browsers request their
native session restoration. Enable previous-session restoration in Firefox-based
browsers to recover their tabs and multiple windows.

Autosave follows window events and also runs every 30 seconds for geometry and
terminal-directory changes. The power menu saves a protected shutdown snapshot
before logout, reboot, or poweroff. A logind delay inhibitor also saves on normal
system shutdown/reboot outside that menu. `dbus-monitor` and `systemd-inhibit`
provide that hook; neither requires a new service or system configuration.

For the first shutdown after this update, use the configured power menu: the old
manager is still running until the next login. The new manager starts automatically
on that login. Reloading Hyprland alone does not run startup hooks again.

State lives in `${XDG_STATE_HOME:-~/.local/state}/hyprland/`. `session.json` is
the current snapshot; `session.before-restore.json` keeps the pre-login snapshot
for troubleshooting an app that fails to reopen. Logs are appended to
`${XDG_STATE_HOME:-~/.local/state}/hyprland-session.log`.

The manager recreates windows rather than preserving running processes. App-native
restoration supplies tabs/documents; terminals reopen their directory, not their
previous processes. Identical windows whose titles change may be matched in a
different order. Workspace placement and floating geometry are restored; exact
tiled split trees are not recorded. Forced power loss can only recover the last
autosave.

Regression checks:

```sh
python3 -m unittest discover -s hypr/scripts/tests -v
```
