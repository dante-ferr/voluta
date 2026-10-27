# Adaptive decorations

Every SVG on a bar uses one shared color decision from the complete wallpaper
strip behind that bar. Gaps between icons and wallpaper underneath opaque
plates also contribute. There are no independent SVG or pixel color changes.

`scripts/render-decorations.py` creates three Wallust-colored variants in
`../wallust/assets/generated/waybar/`: dark (`color0`), light (the selected
workspace accent), and a brighter palette fallback (`foreground` or `color15`).
Both light colors are muted with 20% Wallust dark ink (`color0`).
Light variants have no glow. Dark variants use the faint decoration glow in
`glow.json`; plate shadows retain the separate `boxes` settings.

## Wallpaper placement and sampling

The renderer queries the live awww/swww daemon for each output's current image,
logical dimensions, and scale. Query dimensions already include output rotation;
they must not be swapped again. It reconstructs the complete output at native
pixel resolution, using awww's cached resize method, crop gravity, and filter
when the cache matches the live image and default namespace. Without that cache,
it follows the installed Waypaper awww/swww mapping: fill/stretch use crop,
center/tile use no-resize, and fit uses centered padding. The padding color comes
from Waypaper. The complete canvas avoids the former arbitrary 128-row limit.

For fill/crop, the scale is `max(output_width / image_width, output_height /
image_height)`. Crop gravity determines which excess image area is removed.
The crop applies to the entire output, including Waybar's reserved space.
That reservation moves application windows; it does not shorten or shift awww's
wallpaper surface. awww's raster decoder does not apply EXIF orientation, so the
reconstruction likewise leaves the decoded orientation unchanged.

The GTK helper asynchronously queries `hyprctl -j layers` every two seconds. It
matches the bar by output, namespace and process ID, and finds the wallpaper
surface on the same output. Both rectangles share the compositor's coordinate
system, so subtracting the wallpaper origin handles monitor placement, margins,
other reserved surfaces, and changes to the bar's size without inferred anchors.
The sampled image rectangle is:

```
x = (bar.x - wallpaper.x) * image.width / wallpaper.width
y = (bar.y - wallpaper.y) * image.height / wallpaper.height
w = bar.width * image.width / wallpaper.width
h = bar.height * image.height / wallpaper.height
```

Every native pixel in that rectangle contributes, with fractional edge coverage
weighted by area. Static geometry is not resampled. A single CSS class on the
bar selects the same variant for every decoration. Each monitor's bar uses its
own wallpaper strip.

Dark ink remains the default. `contrast.dark_luminance` (currently 0.02, roughly
sRGB grey 39/255) defines nearly black pixels. `contrast.dark_coverage` in
`glow.json` is the required fraction of the full strip before light ink is used;
the user's current setting is 0.7. Hysteresis prevents threshold flicker. Lower
luminance or higher coverage makes light ink less likely.

Startup keeps dark artwork if exact geometry or wallpaper data is unavailable.
Wallpaper changes should use the existing Waypaper/Wallust refresh hook, which
regenerates the cache and restarts Waybar. Animated images use their first frame.
Pillow and awww use separate decoder/filter implementations, so reconstructed
colors can differ slightly; Mitchell currently uses Pillow's bicubic filter.
The crop and sampled area follow the backend placement.

Rebuild with `make -C waybar` from the repository root. Set
`WAYBAR_CONTRAST_DEBUG=1` at launch to log the shared decision, native image
rectangle, and dark coverage. No changes to SVG dimensions require sampler edits.

## Checks

```sh
python3 tools/check-waybar-contrast.py
cc -Wall -Wextra -o /tmp/check-waybar-contrast tools/check-waybar-contrast.c $(pkg-config --cflags --libs gtk+-3.0 json-glib-1.0) -ldl -lm
/tmp/check-waybar-contrast
```
