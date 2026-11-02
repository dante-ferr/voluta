# Architectural surfaces and Gallery

Status: implemented. The visual direction emphasizes geometry: stepped double
surrounds, chamfered cards, recessed input panels, fine rules, and asymmetrical
ornament. Rofi uses the medium corner scrolls in the crown and foot; Gallery uses
the large corner scrolls on the artwork frame. Labels stay plain; tab-group names
do not receive symbols.

## Desktop surfaces

`rofi/frame.rasi` supplies the shared surround, crown, input relief, tile outlines,
and footer. The main launcher, dashboard, picker, and RGB selector import it;
two-column and wide selectors use frames sized to their own rows. Rofi preserves
SVG aspect ratios when scaling background images and can tile the result, so
update the generated canvas sizes along with any window or tile geometry change.
Test an actual menu, not only `-dump-theme`.

The power menu uses the same stepped surrounds and inset focus relief. Its action
layout, keybindings and power commands are unchanged. Validate styling with a
separate layout whose actions are all `true`; never invoke power actions as a
visual test.

SVG sources live in `wallust/assets/`. `voluta/surfaces.py` renders them into
`~/.config/wallust/assets/generated/` after the shared background publisher runs.
Colors derive exclusively from Wallust tokens and the persistent background
policy. Generated files are ignored and must not be committed.

## Optional Brave New Tab

Voluta Gallery is an unpacked Manifest V3 extension, shipped under `brave/gallery/`.
It provides a large framed wallpaper, clock, search panel, and up to twelve named
shortcuts. It does not change the native tab strip or tab-group geometry: those
controls are drawn by Brave. Choose neutral native group colors separately.
Prismwing remains responsible for website favicons.

Gallery's background mixes the shared browser background 6% toward the palette
foreground, giving the page a lighter surface while the native sidebar stays
dark. Its raised panels and rules derive from that lighter surface.

On opening a tab, the typography enters in a short stagger and the artwork frame
draws into place. A palette-colored glint travels around the stepped surround,
and the wallpaper drifts slowly inside its clipped mat. Motion pauses in hidden
tabs. All of these effects, including hover movement, are disabled when the
browser reports `prefers-reduced-motion: reduce`; static framing remains intact.

With the browser feature enabled, palette publication prepares the extension at
`${XDG_DATA_HOME:-$HOME/.local/share}/voluta/gallery`. To prepare it immediately:

```bash
voluta feature enable browser
bash ~/.config/hypr/UserScripts/combined_wallust.sh
```

In `brave://extensions`, enable Developer mode, choose **Load unpacked**, and
select that `gallery` directory. Brave may ask you to confirm the New Tab change.
Only one extension can own New Tab; choose Gallery or your previous New Tab
provider. Disable Gallery to return control to Brave/the other provider.

This loading step is deliberately manual. The publisher does not edit browser
profile databases, silently install extensions, or change existing groups.
Keep the published directory at the same path across updates: unpacked extension
identity and browser-stored shortcuts depend on that location. After extension
code updates, use **Reload** in the extensions page and reopen New Tab. Palette
and wallpaper changes refresh automatically in open, visible Gallery tabs within
four seconds, and immediately when a tab becomes visible.

Choose **Artwork** under the image to select **Current wallpaper** or **Specific
image**, then **Use artwork**. A specific image is copied into this browser
profile's IndexedDB, so moving/deleting the original file or updating the
dotfiles does not remove it. PNG, JPEG, WebP, AVIF and GIF files up to 64 MiB are
supported. No file-access permission or upload is needed. Switching to the
wallpaper keeps the last image available for reuse. Open Gallery tabs share the
selection; each browser profile has its own choice. The palette continues to
follow Wallust even when the artwork is fixed.

Gallery requests only `storage` and `search`. It stores shortcut names and URLs
in browser-local extension storage, uses the configured search engine, and makes
no external requests before a user searches or follows a shortcut. Its local
wallpaper copy is restricted to supported image files up to 64 MiB; unavailable
artwork leaves a palette-colored mat. The generated descriptor contains an opaque
version and relative image name, not the wallpaper's filesystem path. The private
wallpaper copy belongs in the user's data directory, never the repository.

Disabling the browser feature stops Gallery publication and preserves its data.
Disable/remove the extension in Brave as well if you no longer want its New Tab
page. Re-enabling the feature republishes the assets; shortcut storage survives
ordinary dotfiles updates. Uninstalling the extension itself can erase that
browser-managed storage.
The same applies to the saved image and source selection: they are browser-local
preferences, not companion files or generated extension assets. Clearing the
extension's site data or removing its profile can erase them.

## Verification

`tests/test_surfaces.py` checks core publication with browser disabled, wallpaper
refresh, background policy, missing-artwork tolerance, and preference preservation.
`tests/gallery.test.mjs` checks address validation and bounded shortcut storage.
It also checks custom-image formats and size limits. The local artwork workflow
was exercised with a fixture PNG through the real file-input/save handlers:
missing-image validation, decoding, reload persistence, fixed artwork during
wallpaper refresh, and switching back to the retained image all passed.
Run them alongside the existing theme and installer acceptance suites.

The local browser preview verifies layout, shortcut add/remove persistence, and
narrow-screen overflow. Live Rofi and wlogout previews verify their actual
renderers. Manual extension loading and the browser's default-search API still
need verification in the selected Brave profile; a local HTTP preview exercises
the fallback UI, not Chromium's extension installation.

Recorded validation on 2026-11-02: 46 Voluta tests and 12 session tests passed
locally and in the offline QEMU/TCG Arch guest using configuration-only installs.
The Gallery logic checks passed in Node. All four Rofi themes parsed and opened
successfully; actual screenshots caught and resolved image tiling across icon
and text rows. Wlogout loaded its stylesheet without warnings using a no-op
layout. The HTTP Gallery preview passed shortcut persistence, console-error and
horizontal-overflow checks. No Brave extension was installed automatically.
