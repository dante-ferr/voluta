# Decorations and top glow

Wallpaper-facing decorations (angels, ornaments, patera) always use the dark
Wallust ink: half-brightness `color0`, shared with the box backgrounds. The window
title and music icons sit inside opaque boxes and use the muted bright ink.

`scripts/render-decorations.py` rasterizes these into
`../wallust/assets/generated/waybar/` and writes `wallust/angel-paths.css`.
Wallpaper changes run it through the existing Waypaper/Wallust refresh hook.

## Top glow

`glow.qml` is a Quickshell surface on the Bottom layer of every display. It sits
above the wallpaper and below all windows and Waybar. Light falls from the top edge
like sun through chapel windows: a soft wash plus leaning beams in the Wallust
palette, fading smoothly well below the bar. It lifts the backdrop so the dark
artwork keeps its contrast.

The beams are painted once per palette. Animation slides and slowly brightens that
texture at `fps` frames per second, so the cost is small. It pauses on battery by
default. `scripts/render-decorations.py` writes `wallust/glow-state.json` from the
`heaven` section of `glow.json`, and the QML reloads it on change:

- `opacity` (0 to 1): peak brightness at the top edge.
- `height_px`: how far the light reaches below the top edge.
- `fps`, `drift_px_per_s`: animation rate and beam speed.
- `full_below`, `off_above`: relative luminance (0 to 1) of the wallpaper's top
  band. The glow is full below `full_below`, fades out toward `off_above`, and is
  off above it, so light tops get no glow. `render-decorations.py` measures each
  display's wallpaper on every refresh.
- `animate`, `pause_on_battery`: set `animate` to `false` for a static glow.

`hypr/scripts/StartTopGlow.sh` starts it at login and on Refresh.

Rebuild the native helper with `make -C waybar` from the repository root. The
helper only animates the workspace selection.
