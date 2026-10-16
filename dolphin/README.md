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
and the embedded terminal profile. The generator also applies managed settings
on wallpaper changes. Switching to Imperium installs dependencies and prepares
the hook before restoring the desktop.

`apply-config.py` converts the old `dolphinrc` symlink to a local merged file so
Dolphin cannot write its session state into the tracked baseline. Keys present
in the tracked baselines are reapplied on refresh, theme generation, and every
launch, including on existing installations. Other settings, bookmarks, paths,
window geometry and sessions remain local. Originals are backed up once beside
the local files with the suffix `.pre-imperium`.

The sidebar starts at the width defined in `live.cpp` on each new window.
Changing the width in a running window is still supported. Opaque Qt dock/window
state is not copied between displays with different sizes or scaling.

The launcher waits for a changed hook to compile and reports build failures
instead of quietly loading an older version. Its cache fingerprints source,
the compiler, Qt and KDE headers, rather than trusting file modification dates.
Unchanged launches reuse the compiled library. Logs are at
`~/.local/lib/imperium/dolphin-live-build.log`.

Already-running Dolphin processes retain their loaded code and view settings.
After an update, fully quit Dolphin and reopen it when the notification asks.
Refresh never kills an active Dolphin process or interrupts file transfers.

Fonts and system Qt/KDE assets must also be installed on both hosts; the shared
dependency list includes `otf-monaspace`, Kvantum, Breeze, qt6ct and the build
dependencies. For a newly added dependency, run `rice-switch.sh imperium` once.
Colors still follow each machine's wallpaper; screen scaling and differing
system package versions can cause remaining differences.
