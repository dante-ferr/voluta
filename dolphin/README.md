# Dolphin appearance

The repo owns the visual keys in `../dolphinrc`, the global view defaults in
`view-properties`, the toolbar/shortcuts in `dolphinui.rc`, and the customization
in `live.cpp`. Both hosts use the same files. The existing desktop-only Qt RHI
workaround remains gated to `frank` in `launch.sh`.

After pulling, press **Super+Alt+R**, or apply just Dolphin:

```bash
bash ~/imperivm-dotfiles/dolphin/apply.sh
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
on wallpaper changes. Switching to Imperium installs dependencies and prepares
the hook before restoring the desktop.

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
dependencies. Both `dolphin/apply.sh` and `rice-switch.sh imperium` install
newly added dependencies automatically.
Colors still follow each machine's wallpaper; screen scaling and differing
system package versions can cause remaining differences.

Shared corner and scroll artwork lives in `../wallust/assets/`. The theme
generator recolors it into `~/.config/wallust/generated/` for the current
palette. The hook frames each window and adds small ornaments to the panel
headings. Decorations never receive clicks or keyboard focus. Existing
windows need one full quit and relaunch to load a changed hook; later palette
changes refresh the artwork in place.

Run `python3 tools/check-dolphin-theme.py` from the checkout to check existing
install migration, generated themes, Qt font parsing, and panel positioning in
an isolated home with Qt's offscreen platform. The checks require the build
dependencies listed in `deps/arch.txt` and do not open a Dolphin window.
