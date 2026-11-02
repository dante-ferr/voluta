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

## Update

```sh
make update
make doctor
```

## Documentation

```sh
make docs-serve
```

Overview: [docs/voluta/index.md](docs/voluta/index.md).
Settings, features, companion, and validation live under `docs/voluta/`.
