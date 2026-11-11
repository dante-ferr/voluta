# Decorations and top glow

Wallpaper-facing decorations (angels, ornaments, and the Voluta logo in
`../wallust/assets/patera.svg`) always use the dark Wallust ink: half-brightness
`color0`, shared with the box backgrounds. The window title and music icons sit
inside opaque boxes and use the muted bright ink. `#custom-patera` shows the logo
between the status plate and the power plate. Battery and power share
`group/powerplate` so they stay one medallion-facing box when the battery
module is present, and the group keeps the left radius when it is hidden. The
plate ends that face the medallion use the same 13px outer rounding as the
ornament-facing plate ends.
`#custom-mpris` only appears while `playerctl` reports Playing or Paused; the
built-in mpris module leaves a plate up for stopped browser endpoints. When no
window is focused, `hyprland/window` keeps its plate and shows a home icon with
the machine and user names (`voluta/runtime.py` fills the empty-title rewrite).

`scripts/render-decorations.py` rasterizes these into
`../wallust/assets/generated/waybar/` and writes `wallust/angel-paths.css`.
Wallpaper changes run it through the existing Waypaper/Wallust refresh hook.

## Chrome outlines

Edit `chrome.json` (then refresh decorations) to tune plate and SVG outlines:

- `outline.width_px`: border thickness for plates and SVG side contours.
- `outline.color1_mix`: how far `@color1` mixes toward `@background` for
  `@bar-outline` (0 = full accent, 1 = background).
- `outline.plates.{top,right,bottom,left}`: rectangular plate sides.
- `outline.svgs.{top,right,bottom,left}`: shape-following contours on
  wallpaper-facing artwork (angels, ornaments, patera).

`render-decorations.py` writes plate borders into the `@@chrome-outline`
block in `style.css` (it must sit after `* { border: none }`) and paints SVG
side contours into the generated PNGs.

## Top glow

`glow.qml` is a Quickshell surface on the Bottom layer of every display. It sits
above the wallpaper and below all windows and Waybar. Light falls from the top edge
like sun through chapel windows: a soft wash plus leaning beams in the Wallust
palette, fading smoothly well below the bar. The Waybar GTK helper measures the
left, center, and right module boxes and writes `wallust/glow-clusters.json` when
those rects change; the glow mask eases toward them with a wide soft feather so
empty gaps stay quieter and ornament artwork stays covered. It lifts the backdrop
so the dark artwork keeps its contrast.

The beams are painted once per palette. Animation slides and slowly brightens that
texture at `fps` frames per second, so the cost is small. It pauses on battery by
default. Cluster writes are change-detected on the helper's existing 200 ms tick,
so a static-on-battery glow does not keep rewriting. `scripts/render-decorations.py`
writes `wallust/glow-state.json` from the `heaven` section of `glow.json`, and the
QML reloads both state files on change:

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
