"""Palette and artwork identity shared by every framed menu.

Selector, notification, music, and session read the same Wallust accents and
the same published files. Resident renderers must be told when either changes:
environment captured at process start goes stale after the next palette.
"""
import os
from pathlib import Path
import re
import sys

ACCENTS = ('2', '4', 'fg')
# Files whose bytes change when a menu is republished. The shell palette is
# included so a color write reloads the plate even before the PNG is replaced.
MENU_FILES = {
    'selector': ('big-angel-box.png', 'selector-glass.png', 'selector-aperture.png', 'launcher-vignette.svg'),
    'notification': ('notification-angels-frame.png', 'notification-glass.png',
                     'notification-aperture.png', 'launcher-vignette.svg'),
    'music': ('music-frame.png', 'music-glass.png', 'music-aperture.png', 'launcher-vignette.svg'),
    'session': ('session-frame.png', 'session-glass.png', 'session-aperture.png', 'launcher-vignette.svg'),
}


def compositor_environment(base=None):
    """Copy the process environment and repair an empty Wayland display.

    Hyprland evaluates startup while ``WAYLAND_DISPLAY`` is still empty.
    The first watcher to take the lock keeps that value, and Qt then refuses
    the real socket. A live ``wayland-*`` socket in the runtime directory is
    the display those renderers should use.
    """
    environment = dict(os.environ if base is None else base)
    runtime = Path(environment.get('XDG_RUNTIME_DIR') or f'/run/user/{os.getuid()}')
    display = environment.get('WAYLAND_DISPLAY') or ''
    if display and (runtime / display).is_socket():
        return environment
    found = []
    try:
        for path in runtime.iterdir():
            name = path.name
            if path.is_socket() and name.startswith('wayland-') and '-' not in name[8:]:
                found.append(name)
    except OSError:
        found = []
    if found:
        environment['WAYLAND_DISPLAY'] = sorted(found)[0]
    else:
        environment.pop('WAYLAND_DISPLAY', None)
    return environment


def _hex(color):
    return '#' + ''.join(f'{channel:02x}' for channel in color)


def menu_colors(palette_path):
    """Return the framed-menu accents as ``#wc_2 #wc_4 #wc_fg``.

    Parse the shell palette here. Importing the theme publisher pulls in the
    settings loader, and that startup cost was landing on every keypress.
    """
    text = Path(palette_path).read_text()
    palette = {key: tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))
               for key, value in re.findall(r"^wc_(\w+)='([0-9a-fA-F]{6})'\s*$", text, re.M)}
    missing = [key for key in ACCENTS if key not in palette]
    if missing:
        raise KeyError('framed menu palette missing ' + ', '.join(missing))
    return ' '.join(_hex(palette[key]) for key in ACCENTS)


def menu_paths(config, kind):
    if kind not in MENU_FILES:
        raise ValueError(f'unknown framed menu {kind}')
    config = Path(config)
    assets = config / 'wallust/assets/generated'
    return [config / 'hypr/wallust/colors-shell.sh', *(assets / name for name in MENU_FILES[kind])]


def artwork_version(paths):
    parts = []
    for path in paths:
        try:
            stat = Path(path).stat()
        except OSError:
            parts.append('missing')
            continue
        parts.append(f'{stat.st_mtime_ns}:{stat.st_size}')
    return ':'.join(parts)


def publication(config, kind):
    """Colors, generated asset directory, and artwork stamp for one menu."""
    paths = menu_paths(config, kind)
    return menu_colors(paths[0]), str(paths[1].parent), artwork_version(paths)


def main(argv):
    if len(argv) != 2 or argv[1] not in MENU_FILES:
        print('usage: menus.py selector|notification|music|session', file=sys.stderr)
        return 2
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    try:
        colors, assets, version = publication(config, argv[1])
    except (OSError, KeyError, ValueError) as error:
        print(f'voluta menus: {error}', file=sys.stderr)
        return 1
    print(colors)
    print(assets)
    print(version)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
