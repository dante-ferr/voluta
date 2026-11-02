# Dolphin appearance

Dolphin's base background comes from Voluta's shared `appearance.background`
preference, also used by Brave and the other palette consumers. The default
preserves its existing 35% darkening. See
[Shared background](../docs/voluta/integrations/theme.md) for overrides and exports.

The repo owns the visual keys in `../dolphinrc`, the global view defaults in
`view-properties`, the toolbar/shortcuts in `dolphinui.rc`, and the customization
in `live.cpp`. Both hosts use the same files. The existing desktop-only Qt RHI
workaround is selected by `dolphin_rhi` in the private host settings.

After pulling, press **Super+Alt+R**, or apply just Dolphin:

```bash
voluta feature enable dolphin
voluta update
```

This installs the launcher and desktop/D-Bus routing, merges the managed visual
settings, builds the current hook, and regenerates Qt/Kvantum styling, icons,
and the embedded terminal profile. It first installs missing packages from
`deps/dolphin.txt`, including `otf-monaspace`, using the same installer as the
full rice switch. It uses `paru`, or `sudo pacman` when paru is unavailable.
A keybind invocation opens Kitty for authentication when needed; a terminal
invocation uses that terminal. Installation failures stop the apply before
appearance files are changed and report the remaining packages and a log path.
The generator also applies managed settings
on wallpaper changes. The Voluta installer selects dependencies from enabled modules; the feature can
be disabled and re-enabled after installation.

`apply-config.py` converts the old `dolphinrc` symlink to a local merged file so
Dolphin cannot write its session state into the tracked baseline. Keys present
in the tracked baselines are reapplied on refresh, theme generation, and every
launch, including on existing installations. Other settings, bookmarks, paths,
window geometry and sessions remain local. Originals are backed up once beside
the local files with the suffix `.pre-imperium`.

Each new window restores a shared logical panel layout after Dolphin reads its
local Qt state: Places above Folders on the left, Information on the right and
Terminal below the files. Visibility choices remain local. The sidebar starts
at the width defined in `live.cpp`. Later changes in that window are supported.
Opaque Qt window geometry is not copied between displays.

The Qt/KDE font strings use Qt 6's explicit Normal weight (400). The live hook
also sets Monaspace Argon Regular at 10 points, and every view mode uses the
system font instead of retaining a local custom font. `fonts.conf` gives this
launcher the desktop's grayscale antialiasing and slight hinting, independently
of machine-local fontconfig rules. It is inherited by the embedded terminal.

The launcher waits for a changed hook to compile and reports build failures
instead of quietly loading an older version. Its cache fingerprints source,
the compiler, Qt and KDE headers, rather than trusting file modification dates.
Unchanged launches reuse the compiled library. Logs are at
`~/.local/lib/imperium/dolphin-live-build.log`.

Already-running Dolphin processes retain their loaded code and view settings.
After an update, fully quit Dolphin and reopen it when the notification asks.
Ordinary launches and unchanged refreshes do not check for or emit restart
reminders. After a successful hook rebuild, the installer checks whether an
actual Dolphin process still maps the replaced library. Only that confirmed
update can produce a reminder, once per build fingerprint across process IDs.
Unwrapped processes and shell launchers are not treated as stale libraries.
Refresh never kills an active Dolphin process or interrupts file transfers.

Fonts and system Qt/KDE assets must also be installed on both hosts; the shared
dependency list includes `otf-monaspace`, Kvantum, Breeze, qt6ct and the build
dependencies. `voluta update` installs newly selected dependencies unless `--skip-deps` is used.
Ark supplies the native Extract context menu for ZIP and other archives.
Colors still follow each machine's wallpaper; screen scaling and differing
system package versions can cause remaining differences.

Shared corner and scroll artwork lives in `../wallust/assets/`. The theme
generator recolors it into `~/.config/wallust/assets/generated/` for the current
palette. Dolphin uses the big corner design; notifications use the small
design. All three sizes have mirrored variants in the shared asset folder.
The hook frames each window and adds small ornaments to the panel
headings. Decorations never receive clicks or keyboard focus. Existing
windows need one full quit and relaunch to load a changed hook; later palette
changes refresh the artwork in place.

Wallpaper updates also reload the file view's separate Kvantum style, so its
selection and hover artwork follow the new palette in open windows. Updating
the palette alone leaves Kvantum's cached SVG colors unchanged. The native Places
delegate uses the application style, which is refreshed alongside the file
scene's separate style so sidebar selections also follow wallpaper changes. This hook change
needs one full quit and relaunch; subsequent wallpaper changes refresh in place.

Run `python3 tools/check-dolphin-theme.py` from the checkout to check existing
install migration, generated themes, Qt font parsing, and panel positioning in
an isolated home with Qt's offscreen platform. The checks require the build
dependencies listed in `deps/arch.txt` and do not open a Dolphin window.
They render selections across two consecutive atomic palette updates in the
same file view and a native KDE Places sidebar. An interactive wallpaper change
remains the final visual check.
The native Places check passed outside the restricted agent sandbox on
2026-11-02; the sandboxed run stalled during native delegate painting.
