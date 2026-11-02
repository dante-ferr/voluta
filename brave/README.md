# Brave colors

User setup for the optional browser feature, Prismwing, and Gallery lives in
[Brave with Prismwing and Gallery](../docs/voluta/integrations/brave.md). This
note covers theme publication behavior next to the code.

In `brave://settings/appearance`, choose **GTK** for the browser theme once per
profile on each host. Installed browser themes take precedence over GTK.
Vertical tabs can stay enabled. In the built-in **Theme and colors** panel,
disable **Ultra dark theme** (called **Darker theme** in some releases). That
mode replaces palette lightness with a fixed value and can make a very dark
custom background brighter. Keep the normal Dark or Device scheme and GTK.

Waypaper calls `combined_wallust.sh`. Wallust renders `colors-gtk.css`, then
`paint_brave_theme.py` publishes a GTK theme and changes the theme name to
notify running browsers. Each stylesheet gets a content-derived theme name so
GTK cannot reuse an older named CSS provider when a palette changes.
GTK 3 and GTK 4, including dark variants, are generated. Native Wayland uses
GSettings/the settings portal; XWayland uses xsettingsd.

The toolbar and vertical sidebar use the same shared background RGB as Dolphin.
Voluta's `appearance.background` setting selects the palette token and darkening;
the default retains Dolphin's 35% darkening. Both generators use one resolver.
See [Shared background](../docs/voluta/integrations/theme.md) for overrides.
Inputs use subtly raised surfaces. Brave stays opaque. Text,
borders, hover and selection colors follow the same Wallust palette. Brave
retains some styling for active vertical tabs and its native group accents.
Websites and the New Tab wallpaper keep their own appearance.

The themes import the previous GTK theme and scope color overrides to
Chromium's `.chromium` widgets. Other GTK applications retain their base theme.
A missing base theme falls back to GTK's bundled Adwaita/Default. GTK settings
are merged, with originals backed up beside `settings.ini` using the suffix
`.pre-imperium-brave`. Existing xsettingsd configuration is also backed up.
Original theme names are recorded in `~/.local/state/imperium/brave-theme.json`.

To reapply the wallpaper palette from the Voluta checkout:

```sh
make theme
```

The shared dependency list includes `gsettings-desktop-schemas` and
`xsettingsd`. No GPU variables, browser profile databases, or browser launch
flags are changed. Run `python3 tools/check-brave-theme.py` for isolated checks;
CSS validation uses system Python with PyGObject and GTK 3/4 installed.

## Website icons: Prismwing

Prismwing is maintained as a separate project at `~/Code/projects/prismwing`.
Its extension, native palette bridge, settings and tests live there.

This repository only supplies its palette:

- `wallust/templates/colors-prismwing.json` renders the 16 Wallust colors as
  generic JSON to `~/.config/prismwing/palette.json`.
- Applying the browser theme registers Prismwing's native host when the project
  is available. Set `PRISMWING_PROJECT_DIR` to use another checkout location.
- Prismwing can also use another JSON palette provider or its manual palette
  settings without any dotfiles dependency. See its own README for setup.

Load the unpacked extension and finish the remaining Brave steps through the
[user setup guide](../docs/voluta/integrations/brave.md). Selecting the project
root instead of `extension/` produces a missing-manifest error.

## Architectural New Tab: Voluta Gallery

The optional Gallery extension adds a framed wallpaper, clock, chamfered search
panel and editable shortcuts. It reuses the shared palette and corner ornaments.
Load the published copy under `~/.local/share/voluta/gallery` through **Load
unpacked** after enabling the browser feature and publishing the palette.
Existing tab groups stay native; choose neutral group colors in Brave.

See [Brave with Prismwing and Gallery](../docs/voluta/integrations/brave.md) for
the manual load steps, and
[Architectural surfaces and Gallery](../docs/voluta/integrations/surfaces.md)
for geometry, storage ownership and verification limits.
