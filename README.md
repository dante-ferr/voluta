# Voluta

A cyber baroque Hyprland desktop with wallpaper-driven Wallust colors. Arch Linux
is the supported platform. Python and an AUR helper (`paru` or `yay`) are
required to bootstrap.

## Install

```sh
make init
make dry-run
make install
```

Start Hyprland through your existing session manager. Preferences live under
`~/.config/voluta/`. Attach a companion before updating personal host settings:
`voluta companion attach /path/to/companion`.

## Brave, Prismwing, and Gallery

```sh
make browser
```

That enables the optional browser feature, installs its dependencies when
needed, publishes the GTK theme inputs, Prismwing palette, and Gallery assets,
and registers Prismwing's native host when
`~/Code/projects/prismwing` (or `PRISMWING_PROJECT_DIR`) is present.

Finish once per Brave profile:

1. Open `brave://settings/appearance`. Choose **GTK**. Disable **Ultra dark
   theme** / **Darker theme**. Keep ordinary Dark or Device.
2. Open `brave://extensions`, enable **Developer mode**, then **Load unpacked**:
   - Prismwing favicons: `~/Code/projects/prismwing/extension`
   - Voluta Gallery New Tab: `~/.local/share/voluta/gallery`
3. Confirm Gallery as the New Tab page if Brave asks. Reload website tabs once
   after loading Prismwing.

Brave does not allow an installer to load unpacked extensions or flip those
appearance toggles for you. Details:
[Brave with Prismwing and Gallery](docs/voluta/integrations/brave.md).

## Optional features and updates

A feature flag is the only switch. `make update` does not turn features on.
It deploys this checkout, then installs packages for features that are already
enabled. Turn a feature on once. Later updates keep it installed.

```sh
make karere     # once: enable Karere theming and install its package
make update     # later: deploy files and install packages for enabled features
make doctor     # report missing packages and optional apps
```

`make install` without flags does the same package step as `make update`.
`voluta install --skip-deps` deploys files only and remembers that choice, so a
later `voluta feature enable` will not install packages until you run
`make deps` or `make update`.

`make doctor` prints core checks and optional-app notes. Missing selected
packages fail the command. A theme file for an app you have not opted into does
not.

## Karere

Voluta writes `~/.config/karere/custom.css` on every palette refresh. Stock
`karere` never loads that file. The AUR package `karere-custom-css` does, and
it reloads the file while the app is open.

`make karere` works whether or not stock Karere is already installed:

1. It sets `features.karere` to true.
2. It builds `packaging/karere` with `makepkg`. That recipe is the
   `karere-custom-css` sources plus a compiler fix. It does not install a
   package file from your home directory, and it does not remove an existing
   Karere install while the build is still running.
3. After the package file exists, it installs it. If stock `karere` is
   installed, pacman replaces that package. Files in your home directory stay.
4. It refreshes the palette. Reopen Karere if it was running.

The unmodified AUR package fails to compile with rustc 1.94 (`glib-build-tools`
rejects the resource-path array). The overlay in this repo applies that fix.

After that, `make update` keeps `karere-custom-css` installed. It does not
enable Karere for someone who left the feature off.

## Documentation

```sh
make docs-serve
```

Overview: [docs/voluta/index.md](docs/voluta/index.md).
Settings, features, companion, and validation live under `docs/voluta/`.
