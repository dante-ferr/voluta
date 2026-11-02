"""Publish shared architectural SVG frames and the optional local New Tab gallery."""
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from cli import ROOT, hostname, resolve
from theme import preferred_background, read_palette, write_changed


ASSETS = ('panel-frame.svg', 'big-angel-box.svg', 'launcher-vignette.svg',
          'tile-frame.svg', 'tile-selected.svg',
          'small-corner-tl.svg', 'small-corner-br.svg',
          'medium-corner-tl.svg', 'medium-corner-br.svg',
          'big-corner-tl.svg', 'big-corner-br.svg')
GALLERY_FILES = ('manifest.json', 'index.html', 'style.css', 'app.js', 'logic.mjs', 'artwork.mjs', 'motion.mjs')
GALLERY_ORNAMENTS = ('big-corner-tl.svg', 'big-corner-br.svg')


def hex_color(color):
    return '#' + ''.join(f'{channel:02x}' for channel in color)


def render(source, palette):
    def replace(match):
        name, amount = match.groups()
        key = {'background': 'bg', 'foreground': 'fg'}.get(name, name.removeprefix('color'))
        color = palette[key]
        if amount is not None:
            color = tuple(round(c * (1 - float(amount))) for c in color)
        return hex_color(color)
    result = re.sub(r'\{\{\s*(background|foreground|color\d+)(?:\s*\|\s*darken\((0\.\d+)\))?\s*\}\}', replace, source)
    if '{{' in result:
        raise ValueError('Unrendered surface SVG token')
    return result


def canvas(svg, width, height):
    def dimensions(match):
        attributes = re.sub(r'\s(?:width|height)="[^"]*"', '', match[1])
        return f'<svg width="{width}" height="{height}"' + attributes + '>'
    return re.sub(r'<svg\b([^>]*)>', dimensions, svg, count=1)


def current_wallpaper(config):
    try:
        result = subprocess.run(['swww', 'query'], capture_output=True, text=True, timeout=3)
        for line in result.stdout.splitlines():
            if 'image: ' in line:
                path = Path(line.split('image: ', 1)[1].strip()).expanduser()
                if path.is_file():
                    return path
    except (OSError, subprocess.SubprocessError):
        pass
    for filename in (Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'waypaper/state.ini',
                     config / 'waypaper/config.ini'):
        parser = configparser.ConfigParser(interpolation=None)
        try:
            parser.read(filename)
            for section in parser.sections():
                for name in parser.get(section, 'wallpaper', fallback='').splitlines():
                    path = Path(name.strip()).expanduser()
                    if path.is_file():
                        return path
        except (OSError, configparser.Error):
            continue
    return None


def copy_wallpaper(source, generated):
    if source is None:
        return None, ''
    suffix = source.suffix.lower()
    if suffix not in ('.jpg', '.jpeg', '.png', '.webp', '.avif', '.gif') or source.stat().st_size > 64 * 1024 * 1024:
        return None, ''
    fingerprint = hashlib.sha256(f'{source.resolve()}:{source.stat().st_mtime_ns}:{source.stat().st_size}'.encode()).hexdigest()[:16]
    destination = generated / ('wallpaper' + suffix)
    stamp = generated / '.wallpaper-version'
    if not destination.exists() or not stamp.exists() or stamp.read_text() != fingerprint:
        with tempfile.NamedTemporaryFile(dir=generated, delete=False) as temporary:
            name = Path(temporary.name)
        try:
            shutil.copyfile(source, name)
            name.replace(destination)
            write_changed(stamp, fingerprint)
        finally:
            name.unlink(missing_ok=True)
        for old in generated.glob('wallpaper.*'):
            if old != destination:
                old.unlink()
    return destination.name, fingerprint


def publish(config=None, data=None, directory=None, host=None, root=ROOT):
    config = config or Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    data = data or Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    directory = directory or config / 'voluta'
    palette = read_palette(config / 'hypr/wallust/colors-shell.sh')
    palette['bg'] = preferred_background(palette, directory, host)
    assets = config / 'wallust/assets/generated'
    rendered = {}
    for name in ASSETS:
        rendered[name] = render((root / 'wallust/assets' / name).read_text(), palette)
        write_changed(assets / name, rendered[name])
    # Match rofi/frame.rasi: 1.6× the 720×640 art so the hollow center stays usable.
    write_changed(assets / 'big-angel-box.svg', canvas(rendered['big-angel-box.svg'], 1152, 1024))
    write_changed(assets / 'panel-frame-wide.svg', rendered['panel-frame.svg'].replace('width="720" height="640"', 'width="1150" height="760"'))
    for variant, width in (('', 324), ('-list', 656), ('-wide', 1086)):
        for name in ('tile-frame', 'tile-selected'):
            # A small clear gutter absorbs icon/text row-height differences.
            write_changed(assets / (name + variant + '.svg'), canvas(rendered[name + '.svg'], width, 45))

    settings, _ = resolve(directory, hostname(host))
    if not settings['features']['browser']:
        return
    gallery = data / 'voluta/gallery'
    generated = gallery / 'generated'
    generated.mkdir(parents=True, exist_ok=True)
    for name in GALLERY_FILES:
        write_changed(gallery / name, (root / 'brave/gallery' / name).read_text())
    for name in GALLERY_ORNAMENTS:
        write_changed(generated / name, rendered[name])
    try:
        wallpaper, wallpaper_version = copy_wallpaper(current_wallpaper(config), generated)
    except OSError:
        # A wallpaper disappearing during a switch must not interrupt core styling.
        wallpaper, wallpaper_version = None, ''
    fg, bg = palette['fg'], palette['bg']
    # Gallery is a lighter reading surface than the surrounding browser chrome.
    bg = tuple(round(a * .94 + b * .06) for a, b in zip(bg, fg))
    mix = lambda amount: tuple(round(a * (1 - amount) + b * amount) for a, b in zip(bg, fg))
    colors = {'bg': hex_color(bg), 'fg': hex_color(fg), 'accent': hex_color(palette['1']),
              'muted': hex_color(mix(.58)), 'line': hex_color(mix(.23)), 'raised': hex_color(mix(.05))}
    packet = {'colors': colors, 'wallpaper': wallpaper, 'wallpaperVersion': wallpaper_version}
    packet['version'] = hashlib.sha256(json.dumps(packet, sort_keys=True).encode()).hexdigest()[:16]
    write_changed(generated / 'palette.css', ':root {\n' + ''.join(f'  --{key}: {value};\n' for key, value in colors.items()) + '}\n')
    # Publish the descriptor last, after its referenced artwork has been written.
    write_changed(generated / 'palette.json', json.dumps(packet, indent=2) + '\n')


if __name__ == '__main__':
    publish()
