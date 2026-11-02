# Brave with Prismwing and Gallery

Status: implemented. Enable the optional `browser` feature, then finish a few
Brave UI steps that Chromium-based browsers do not allow an installer to perform
for you. Voluta does not edit Brave profile databases, install extensions into a
profile, or change launch flags.

## What Voluta configures

With `features.browser` enabled:

| Step | Result |
| --- | --- |
| Dependency install | `gsettings-desktop-schemas` and `xsettingsd` |
| Wallpaper / Wallust refresh | Shared GTK theme for Brave's toolbar and sidebar |
| Wallust Prismwing template | `~/.config/prismwing/palette.json` |
| Theme publish, when Prismwing is present | Runs Prismwing's `install.py --quiet` to register the Brave native messaging host |
| Theme publish, with Gallery | Publishes the New Tab extension under `~/.local/share/voluta/gallery` |

From the Voluta checkout:

```sh
make browser
```

That enables the feature, reconciles dependencies and Gallery publication, then
runs `make theme` (Wallust consumers, Brave GTK theme, Prismwing palette/host).
You can also select the feature during `voluta install`. Enabling it later is
supported; see [Core and optional features](../architecture/features.md).

## Manual Brave appearance

Do this once per Brave profile on each host:

1. Open `brave://settings/appearance`.
2. Set the browser theme to **GTK**. Installed browser themes override GTK.
3. In **Theme and colors**, leave Dark or Device enabled.
4. Turn off **Ultra dark theme** (labeled **Darker theme** in some releases).
   That mode replaces palette lightness and can brighten a dark custom background.

Vertical tabs can stay enabled. Native tab-group accents remain Brave's; choose
neutral group colors if you want them quieter next to the Wallust chrome.

## Prismwing (website favicons)

Prismwing is a separate project. Voluta only publishes its palette JSON and, when
the project is available, registers its native host. Default checkout path:

```text
~/Code/projects/prismwing
```

Set `PRISMWING_PROJECT_DIR` if the project lives elsewhere. Without that
checkout, Voluta still writes the palette file; favicon recoloring needs the
extension and native host from Prismwing itself.

1. Clone or place Prismwing at the path above (or your override).
2. Open `brave://extensions` and enable **Developer mode**.
3. Choose **Load unpacked** and select the `extension` subdirectory that contains
   `manifest.json`. Selecting the project root fails with a missing-manifest
   error.
4. If theme publish already ran while the project was present, the native host is
   registered. Otherwise run `python3 install.py` from the Prismwing checkout,
   then reopen Brave or reload the extension.
5. Reload existing website tabs once so inactive-tab icons pick up the palette.
6. If **Imperium Wallust Favicons** is still installed, remove it first, load
   Prismwing, then reload website tabs.

Open the extension **Details** page for its settings. Manual palettes work
without the native host on pages that allow generated data images; restrictive
pages need the helper. Prefer **Use native palette** so Wallust updates keep
driving the colors.

Brave can still flash a site-provided favicon before the extension takes control.
Bookmark menus and other browser-owned favicon caches are outside extension
reach. See Prismwing's own README for palette format, limits, and tests.

## Voluta Gallery (New Tab)

Gallery is the optional framed New Tab page. With the browser feature enabled,
publication keeps `~/.local/share/voluta/gallery` ready. Load it once:

1. Open `brave://extensions` and enable **Developer mode**.
2. Choose **Load unpacked**.
3. Select `~/.local/share/voluta/gallery` (the directory that contains
   `manifest.json`).
4. Confirm Brave's New Tab ownership prompt when it appears. Only one extension
   can own New Tab; pick Gallery or keep your previous provider.
5. Keep that published path stable across updates. Unpacked identity and
   browser-stored shortcuts depend on it.
6. After Gallery code updates from a Voluta refresh, use **Reload** on the
   extensions page and open a new tab. Palette and wallpaper changes refresh
   open, visible Gallery tabs automatically.

Choose **Artwork** on the page to use the current wallpaper or a specific image.
Image choice and shortcuts are browser-local storage, not companion settings.
Disable or remove the extension in Brave if you want Brave's default New Tab
again. Disabling the Voluta `browser` feature stops publication but leaves
browser-managed Gallery data until you remove the extension or clear its site
data.

Geometry, motion, permissions, and verification limits live in
[Architectural surfaces and Gallery](surfaces.md).

## Checklist after install

| Done by | Action |
| --- | --- |
| You | `make browser` (or select browser at install) |
| You | Install Brave if it is not already the browser you use |
| You | Place Prismwing at `~/Code/projects/prismwing` when you want favicons |
| Voluta | Publish GTK theme, Prismwing palette, Gallery assets, and Prismwing host when available |
| You | Set Brave theme to **GTK**; disable Ultra/Darker theme |
| You | **Load unpacked** Prismwing `extension/` |
| You | **Load unpacked** `~/.local/share/voluta/gallery` and confirm New Tab |
| You | Reload website tabs once after Prismwing loads |
| Optional | Neutral native tab-group colors; Gallery artwork and shortcuts |

## Why these steps stay manual

Chromium and Brave do not allow a desktop installer to silently load unpacked
extensions into an existing profile, claim New Tab, or flip per-profile
appearance overrides. Voluta therefore prepares files and the native host, then
leaves the Developer-mode **Load unpacked** steps and appearance toggles to you.

Component notes next to the code:
[Brave README](../../../brave/README.md). Shared toolbar background policy:
[Shared background](theme.md).
