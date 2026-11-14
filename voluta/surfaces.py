"""Publish architectural frames and the optional local New Tab gallery."""
import argparse
from colorsys import hls_to_rgb, rgb_to_hls
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageOps

from cli import ROOT, hostname, resolve
from theme import preferred_background, read_palette, write_changed


ASSETS = ('panel-frame.svg', 'big-angel-box.svg', 'launcher-vignette.svg',
          'tile-frame.svg', 'tile-selected.svg',
          'small-corner-tl.svg', 'small-corner-br.svg',
          'medium-corner-tl.svg', 'medium-corner-br.svg',
          'big-corner-tl.svg', 'big-corner-br.svg')
GALLERY_FILES = ('manifest.json', 'index.html', 'style.css', 'app.js', 'logic.mjs', 'artwork.mjs', 'motion.mjs')
GALLERY_ORNAMENTS = ('big-corner-tl.svg', 'big-corner-br.svg')
SELECTOR_FRAME = Path('wallust/assets/big-angel-box.png')
SELECTOR_SIZE = (1152, 1024)  # Matches the centered slot in rofi/selector-frame.rasi.
NOTIFICATION_FRAME = Path('wallust/assets/notification-angels-frame.png')
NOTIFICATION_SIZE = (1056, 736)  # Matches swaync/config.json and its frame padding.
MUSIC_FRAME = Path('wallust/assets/music-frame.png')
# Portrait plate fills 1080p under Waybar; native art is 971×1620.
MUSIC_SIZE = (624, 1040)
SESSION_FRAME = Path('wallust/assets/session-frame.png')
SESSION_SIZE = MUSIC_SIZE
MUSIC_CONTENT_PAD = 28


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


def write_bytes_changed(path, content):
    if path.exists() and path.read_bytes() == content:
        return False
    destination = path.resolve() if path.is_symlink() else path
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(content)
    try:
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def frame_tints(palette, hue, saturation, luminance, alpha):
    # Ignore transparent, neutral and very dark pixels when finding the source hues.
    mask = ImageChops.multiply(alpha, saturation.point(lambda value: 255 if value >= 24 else 0))
    mask = ImageChops.multiply(mask, luminance.point(lambda value: 255 if value > 24 else 0))
    histogram = hue.histogram(mask)
    center = max(range(256), key=histogram.__getitem__)
    origin = (center - 128) % 256
    histogram = histogram[origin:] + histogram[:origin]
    total = sum(histogram)
    positions = []
    count = 0
    for index, frequency in enumerate(histogram):
        count += frequency
        while len(positions) < 3 and count >= total * (.05, .50, .95)[len(positions)]:
            positions.append(index if total else 128)
    low, middle, high = positions
    low, high = min(low, middle - 1), max(high, middle + 1)

    # Order distinct Wallust hues along the same circular axis as the artwork.
    tones = {}
    for key in ('1', '2', '3', '4', '5', '6', '9', '10', '11', '12', '13', '14'):
        if key not in palette:
            continue
        tint_hue, lightness, chroma = rgb_to_hls(*(channel / 255 for channel in palette[key]))
        if chroma < .08:
            continue
        position = (tint_hue - origin / 256) % 1
        tint = tuple(round(channel * 255) for channel in
                     hls_to_rgb(tint_hue, max(lightness, .68), chroma))
        tones.setdefault(int(position * 24), tint)
    colors = [tones[key] for key in sorted(tones)] or [palette['fg']]
    left, neutral, right = colors[0], colors[len(colors) // 2], colors[-1]
    if len(colors) == 2:
        neutral = tuple(round((a + b) / 2) for a, b in zip(left, right))

    lookup = []
    for value in range(256):
        position = (value - origin) % 256
        if position < middle:
            start, end = left, neutral
            amount = max(0, (position - low) / (middle - low))
        else:
            start, end = neutral, right
            amount = min(1, (position - middle) / (high - middle))
        lookup.append(tuple(round(a + (b - a) * amount) for a, b in zip(start, end)))
    return lookup, neutral


def render_palette_frame(source, palette, size=SELECTOR_SIZE, centering=(.5, .5)):
    with Image.open(source) as original:
        image = original.convert('RGBA')
        alpha = image.getchannel('A')
        hue, saturation, _ = image.convert('HSV').split()
        luminance = ImageOps.grayscale(image)
        lookup, neutral = frame_tints(palette, hue, saturation, luminance, alpha)
        tinted = Image.merge('RGB', tuple(hue.point(channel) for channel in zip(*lookup)))
        # Weakly saturated pixels have unreliable hues. Fade them to the middle tint.
        tinted = Image.composite(tinted, Image.new('RGB', image.size, neutral),
                                 saturation.point(lambda value: min(255, value * 6)))
        # Keep the full tonal range, with the brightest relief closer to the background.
        relief = luminance.point(lambda value: min(224, max(0, round((value - 24) * 224 / 151))))
        frame = Image.composite(tinted, Image.new('RGB', image.size, palette['bg']), relief)
        frame.putalpha(alpha)
        # Use an exact consumer-sized canvas so GTK and Rofi never tile the artwork.
        frame = ImageOps.pad(frame, size, Image.Resampling.LANCZOS,
                             color=(0, 0, 0, 0), centering=centering)
        return frame


def frame_aperture(frame):
    """Find only the enclosed hollow; open/missing cutouts never fill the desktop."""
    alpha = frame.getchannel('A')
    opening = alpha.point(lambda value: 255 if value >= 128 else 0)
    center = (frame.width // 2, frame.height // 2)
    if opening.getpixel(center) == 0:
        ImageDraw.floodfill(opening, center, 128)
    opening = opening.point(lambda value: 255 if value == 128 else 0)
    bounds = opening.getbbox()
    if bounds and bounds[0] > 0 and bounds[1] > 0 and bounds[2] < frame.width and bounds[3] < frame.height:
        # Use the opening's original alpha coverage at the edge of the ornament.
        opening = ImageChops.multiply(opening, ImageOps.invert(alpha))
    else:
        # An open or missing cutout must never project outside the frame.
        opening = Image.new('L', frame.size)
    return opening


def publish_cutout_frame(assets, source, palette, size, frame_name, aperture_name,
                         glass_name=None, centering=(.5, .5)):
    frame = render_palette_frame(source, palette, size, centering)
    opening = frame_aperture(frame)
    mask = Image.new('RGBA', frame.size)
    mask.putalpha(opening)
    outputs = [(frame_name, frame), (aperture_name, mask)]
    if glass_name:
        # Paint glass only inside the sculpture, leaving the outer silhouette clear.
        glass = Image.new('RGBA', frame.size, (*palette['bg'], 0))
        glass.putalpha(opening.point(lambda value: round(value * .50)))
        outputs.append((glass_name, glass))
    for name, image in outputs:
        with BytesIO() as output:
            image.save(output, format='PNG')
            write_bytes_changed(assets / name, output.getvalue())


def publish_selector_frame(assets, source, palette):
    publish_cutout_frame(assets, source, palette, SELECTOR_SIZE,
                         SELECTOR_FRAME.name, 'selector-aperture.png',
                         'selector-glass.png')
    # Static Rofi has one background image, so the fallback plate carries the
    # same opening glass under the angel. The animated path suppresses it and
    # draws selector-glass.png on the lower surface instead.
    with Image.open(assets / 'selector-glass.png') as glass, Image.open(assets / SELECTOR_FRAME.name) as frame:
        plate = Image.alpha_composite(glass.convert('RGBA'), frame.convert('RGBA'))
    with BytesIO() as output:
        plate.save(output, format='PNG')
        write_bytes_changed(assets / 'selector-plate.png', output.getvalue())


def publish_notification_frame(assets, source, palette):
    publish_cutout_frame(assets, source, palette, NOTIFICATION_SIZE,
                         NOTIFICATION_FRAME.name, 'notification-aperture.png',
                         'notification-glass.png', centering=(.5, 0))


def opaque_padding(image, threshold=16):
    """Pixels of transparent margin around a frame. Right and bottom are exclusive."""
    mask = image.getchannel('A').point(lambda value: 255 if value > threshold else 0)
    box = mask.getbbox()
    if not box:
        return {'left': 0, 'top': 0, 'right': 0, 'bottom': 0}
    left, top, right, bottom = box
    width, height = image.size
    return {'left': left, 'top': top, 'right': width - right, 'bottom': height - bottom}


def music_content_rect(opening, padding=MUSIC_CONTENT_PAD):
    box = opening.getbbox()
    if not box:
        return None
    left, top, right, bottom = box[0] + padding, box[1] + padding, box[2] - padding, box[3] - padding
    if right - left < 64 or bottom - top < 64:
        left, top, right, bottom = box
    return {'left': left, 'top': top, 'width': right - left, 'height': bottom - top}


def publish_music_frame(assets, source, palette):
    publish_cutout_frame(assets, source, palette, MUSIC_SIZE,
                         MUSIC_FRAME.name, 'music-aperture.png', 'music-glass.png')
    with Image.open(assets / MUSIC_FRAME.name) as frame:
        content = music_content_rect(frame_aperture(frame))
        edges = opaque_padding(frame)
    if content:
        write_changed(assets / 'music-content.json', json.dumps(content) + '\n')
    write_changed(assets / 'music-edges.json', json.dumps(edges) + '\n')


def publish_session_frame(assets, source, palette):
    publish_cutout_frame(assets, source, palette, SESSION_SIZE,
                         SESSION_FRAME.name, 'session-aperture.png', 'session-glass.png')
    with Image.open(assets / SESSION_FRAME.name) as frame:
        opening = frame_aperture(frame)
        content = music_content_rect(opening)
        edges = opaque_padding(frame)
        if content:
            alpha = frame.getchannel('A')
            hang = content['top']
            limit = content['top'] + content['height'] // 3
            for y in range(content['top'], limit):
                for x in range(content['left'], content['left'] + content['width']):
                    if alpha.getpixel((x, y)) > 40:
                        hang = max(hang, y + 12)
            if hang > content['top']:
                content['height'] = max(64, content['height'] - (hang - content['top']))
                content['top'] = hang
    if content:
        write_changed(assets / 'session-content.json', json.dumps(content) + '\n')
    write_changed(assets / 'session-edges.json', json.dumps(edges) + '\n')


def checkout_root(manifest, data):
    # Installed trees keep a recorded public checkout; live checkouts are ROOT.
    recorded = Path(manifest.get('source', str(ROOT)))
    if ROOT == (data / 'current').resolve() and recorded.is_dir():
        return recorded
    return ROOT


def publish_voluta_mark(assets, root, palette):
    """Rasterize the twin-volute logo for the app selector and other brand slots."""
    source = root / 'wallust/assets/patera.svg'
    if not source.is_file():
        return
    paint = hex_color(palette['fg'])
    svg = source.read_text()
    svg = re.sub(r'\bfill="[^"]*"', f'fill="{paint}"', svg)
    svg = re.sub(r'\bstroke="[^"]*"', f'stroke="{paint}"', svg)
    with tempfile.NamedTemporaryFile(suffix='.svg', delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(svg.encode())
    try:
        # Wide mark with square canvas so Rofi's icon widget does not squash it.
        subprocess.run(
            ['rsvg-convert', '--width', '128', '--height', '128', '--keep-aspect-ratio',
             str(temporary), '-o', str(assets / 'voluta-mark-raw.png')],
            check=True, capture_output=True,
        )
    finally:
        temporary.unlink(missing_ok=True)
    with Image.open(assets / 'voluta-mark-raw.png') as mark:
        mark = mark.convert('RGBA')
        canvas_image = Image.new('RGBA', (128, 128), (0, 0, 0, 0))
        canvas_image.alpha_composite(
            mark, ((128 - mark.width) // 2, (128 - mark.height) // 2))
        output = BytesIO()
        canvas_image.save(output, format='PNG')
        write_bytes_changed(assets / 'voluta-mark.png', output.getvalue())
    (assets / 'voluta-mark-raw.png').unlink(missing_ok=True)


def publish_core_svgs(assets, root, palette):
    rendered = {}
    for name in ASSETS:
        rendered[name] = render((root / 'wallust/assets' / name).read_text(), palette)
        write_changed(assets / name, rendered[name])
    # Match rofi/frame.rasi: 1.6× the 720×640 art so the hollow center stays usable.
    write_changed(assets / 'big-angel-box.svg', canvas(rendered['big-angel-box.svg'], 1152, 1024))
    write_changed(assets / 'panel-frame-wide.svg',
                  rendered['panel-frame.svg'].replace('width="720" height="640"', 'width="1150" height="760"'))
    for variant, width in (('', 324), ('-list', 656), ('-wide', 1086)):
        for name in ('tile-frame', 'tile-selected'):
            # A small clear gutter absorbs icon/text row-height differences.
            write_changed(assets / (name + variant + '.svg'), canvas(rendered[name + '.svg'], width, 45))
    publish_voluta_mark(assets, root, palette)
    return rendered


def refresh_frames():
    from cli import atomic_write
    from deploy import deployment_lock, load_manifest, locations, write_managed

    config, data, state = locations()
    with deployment_lock():
        manifest = load_manifest(state)
        managed_changed = False
        palette = read_palette(config / 'hypr/wallust/colors-shell.sh')
        palette['bg'] = preferred_background(palette, config / 'voluta')
        root = checkout_root(manifest, data)
        assets = config / 'wallust/assets/generated'
        # Pull + Super+Alt+R must republish the clear screen veil and other SVG
        # templates, not only the filtered angel-frame PNGs.
        publish_core_svgs(assets, root, palette)
        for relative, publisher in ((SELECTOR_FRAME, publish_selector_frame),
                                    (NOTIFICATION_FRAME, publish_notification_frame),
                                    (MUSIC_FRAME, publish_music_frame),
                                    (SESSION_FRAME, publish_session_frame)):
            installed = ROOT / relative
            checkout = root / relative
            use_checkout = root != ROOT and checkout.is_file()
            content = (checkout if use_checkout else installed).read_bytes()
            publisher(assets, BytesIO(content), palette)
            if use_checkout and (not installed.is_file() or installed.read_bytes() != content):
                write_managed(installed, content, manifest, state, 0o644)
                managed_changed = True
        if managed_changed:
            atomic_write(state / 'install.json', manifest)


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
    # walltag stores the last pick under the wallpaper root; config may use ~.
    try:
        walltag_cfg = json.loads((config / 'walltag/config.json').read_text())
        root = Path(str(walltag_cfg.get('wallpaper_root', '')).strip()).expanduser()
        state_file = root / '.walltag' / 'state.json'
        if state_file.is_file():
            state = json.loads(state_file.read_text())
            path = Path(str(state.get('last_image', '')).strip()).expanduser()
            if path.is_file():
                return path
    except (OSError, TypeError, ValueError, json.JSONDecodeError):
        pass
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
    rendered = publish_core_svgs(assets, root, palette)
    publish_selector_frame(assets, root / SELECTOR_FRAME, palette)
    publish_notification_frame(assets, root / NOTIFICATION_FRAME, palette)
    publish_music_frame(assets, root / MUSIC_FRAME, palette)
    publish_session_frame(assets, root / SESSION_FRAME, palette)

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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh-frames', '--refresh-selector', dest='refresh_frames', action='store_true',
                        help='sync and filter the selector and notification frames')
    args = parser.parse_args()
    try:
        if args.refresh_frames:
            refresh_frames()
        else:
            publish()
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f'Voluta surfaces: {error}\n')
