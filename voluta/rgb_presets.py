"""Palette-derived compositions and native effects; no software frame streaming."""
from dataclasses import dataclass
import json


@dataclass(frozen=True)
class Preset:
    name: str
    title: str
    description: str
    engine: int = 0             # 0: per-key; 1: breathing; 5: wave; 8: stack; 3: spectrum
    colors: tuple = (4, 5, 1, 3, 6)
    speed: int = 3
    brightness: int = 5
    direction: int = 2
    loop: bool = True
    mouse_mode: str = 'Static'


PRESETS = (
    Preset('voluta', 'Voluta', 'Flowing keys, functional accents and a palette light bar'),
    Preset('wasd', 'WASD spotlight', 'Bright movement keys over a quiet palette backdrop', colors=(10,)),
    Preset('navigation', 'Navigator', 'Arrows and the navigation island in relief', colors=(14,)),
    Preset('vim', 'Vim sanctuary', 'H J K L, Escape and command punctuation', colors=(12,)),
    Preset('shortcuts', 'Command deck', 'Modifiers and desktop launcher keys illuminated', colors=(13,)),
    Preset('constellation', 'Constellation', 'A quiet field scattered with palette stars', colors=(5,)),
    Preset('checkerboard', 'Harlequin', 'Alternating woven colors across the key field', colors=(1, 4)),
    Preset('ribbons', 'Silken ribbons', 'A different palette ribbon on each row', colors=(5,)),
    Preset('numpad', 'Number atelier', 'The numpad becomes a bright, separate island', colors=(11,)),
    Preset('split', 'Duet', 'Two complementary halves and a blended light bar', colors=(1, 4)),
    Preset('accent', 'Monochrome', 'One wallpaper accent across both peripherals', colors=(1,)),
    Preset('off', 'Lights out', 'Darken the selected device without disabling the integration'),
    Preset('velvet', 'Velvet breath', 'A slow single-color pulse', 1, (5,), 1, 3, loop=False, mouse_mode='Breathing'),
    Preset('moonlight', 'Moonlit hush', 'A dim, unhurried cool pulse', 1, (4,), 1, 2, loop=False, mouse_mode='Breathing'),
    Preset('heartbeat', 'Baroque heartbeat', 'Five colors breathe through the wallpaper palette', 1, (1, 5, 4, 6, 3), 3, mouse_mode='Breathing'),
    Preset('aurora', 'Aurora', 'Cool colors fold into violet and back', 1, (4, 12, 5, 13, 6), 2, mouse_mode='Breathing'),
    Preset('rose', 'Rose window', 'Warm and violet colors glow in succession', 1, (1, 9, 5, 13, 3), 2, mouse_mode='Breathing'),
    Preset('embers', 'Ember chapel', 'A warm, low glow from the active palette', 1, (1, 9, 3, 11, 1), 2, 3, mouse_mode='Breathing'),
    Preset('tide', 'Midnight tide', 'Five cool colors ebb through a slow breathing cycle', 1, (6, 14, 4, 12, 5), 1, 3, mouse_mode='Breathing'),
    Preset('fountain', 'Fountain', 'Palette colors stack upward across the keyboard', 8, direction=0, mouse_mode='Breathing'),
    Preset('rainfall', 'Stained-glass rain', 'Colors descend in repeating layers', 8, (6, 4, 5, 1, 3), 2, direction=3, mouse_mode='Breathing'),
    Preset('procession', 'Procession', 'A steady procession of palette colors toward the right', 8, speed=2, direction=2, mouse_mode='Breathing'),
    Preset('reflux', 'Undertow', 'A faster procession flowing back toward the left', 8, (6, 3, 1, 5, 4), 4, direction=1, mouse_mode='Breathing'),
    Preset('prism', 'Prismatic current', 'Native rainbow wave to the right; firmware colors', 5, speed=2, direction=2, mouse_mode='Wave'),
    Preset('prism-rain', 'Prismatic rain', 'Native rainbow wave downward; firmware colors', 5, speed=3, direction=3, mouse_mode='Wave'),
    Preset('orbit', 'Chromatic orbit', 'Native rainbow cycle; firmware colors', 3, speed=2, mouse_mode='Rainbow'),
)
CATALOG = {preset.name: preset for preset in PRESETS}


def get(name):
    try:
        return CATALOG[name]
    except (KeyError, TypeError):
        raise ValueError(f'Unknown RGB preset: {name}') from None


def token(palette, number):
    try:
        color = bytes.fromhex(palette[f'wc_{number}'])
        if len(color) != 3:
            raise ValueError()
        return color
    except (KeyError, ValueError, TypeError):
        raise ValueError(f'Wallust RGB token wc_{number} is missing or invalid') from None


def blend(first, second, amount):
    amount = max(0, min(1, amount))
    return bytes(round(a + (b - a) * amount) for a, b in zip(first, second))


def static_colors(preset, palette, keys):
    """Return colors for real key indices only; physical coordinates handle islands."""
    base = token(palette, preset.colors[0])
    quiet = blend(bytes(3), base, .13)
    result = {}
    for key in keys:
        index, label = key['index'], key['label']
        row, col = divmod(index, 18)
        bar = row == 7
        color = quiet
        if preset.name == 'off':
            color = bytes(3)
        elif preset.name == 'accent':
            color = base
        elif preset.name == 'wasd':
            if label in ('W', 'A', 'S', 'D'):
                color = token(palette, 10)
            elif label in ('Left', 'Right', 'Up', 'Down'):
                color = token(palette, 14)
            elif label in ('Space', 'Left Shift', 'Esc') or bar:
                color = token(palette, 3)
        elif preset.name == 'navigation':
            if row == 6 or label in ('Left', 'Right', 'Up', 'Down') or bar:
                color = base
        elif preset.name == 'vim':
            if label in ('H', 'J', 'K', 'L'):
                color = token(palette, 14)
            elif label in ('Esc', ':', ';', '/', 'Enter') or bar:
                color = token(palette, 9)
        elif preset.name == 'shortcuts':
            if any(part in label for part in ('Win', 'Ctrl', 'Alt', 'Shift')) or bar:
                color = base
            elif label in ('B', 'E', 'W', 'D', 'T', 'R', 'Q', 'Return', 'Enter', 'Space'):
                color = token(palette, 11)
        elif preset.name == 'constellation':
            if (index * 37 + 11) % 13 < 3 or bar:
                color = token(palette, (9, 11, 12, 13, 14)[index % 5])
        elif preset.name == 'checkerboard':
            color = token(palette, preset.colors[(row + col) % 2])
        elif preset.name == 'ribbons':
            color = token(palette, (4, 5, 1, 3, 2, 6, 13, 14)[row])
        elif preset.name == 'numpad':
            if label.startswith('Num') or label == 'Decimal' or bar:
                color = base
        elif preset.name == 'split':
            if bar:
                color = blend(token(palette, 1), token(palette, 4), (col - 3) / 14)
            else:
                color = token(palette, 1 if key['x'] < 240 else 4)
        result[index] = color
    return result


def custom_frames(colors, root):
    frames = [bytearray(row) for row in json.loads((root / 'voluta/mars-keymap.json').read_text())]
    valid = {key['index'] for key in json.loads((root / 'voluta/mars-custom.json').read_text())['keys']}
    if set(colors) - valid:
        raise ValueError('Unmapped Mars LED index')
    for index in range(144):
        offset = index % 16 * 4
        color = colors.get(index, bytes(3))
        if len(color) != 3:
            raise ValueError('Mars LED colors must contain three channels')
        frames[index // 16][offset + 1:offset + 4] = color
    return list(map(bytes, frames))


def transaction(profile, root):
    data = json.loads((root / 'voluta/mars-custom.json').read_text())
    query = lambda command: bytes((4, command)) + bytes(62)
    return [query(0xab), bytes.fromhex(data['E1_SESSION_BLOCK']), query(2), *profile, query(2)]


def reports(preset, palette, root):
    if preset.name == 'voluta':
        from rgb import mars_custom_reports
        return mars_custom_reports(palette)
    data = json.loads((root / 'voluta/mars-custom.json').read_text())
    header = bytearray(64)
    header[0:2] = b'\x04\x0a'
    header[8] = 15
    effects = [bytearray.fromhex(data[name]) for name in ('E1_EFFECT_01', 'CAPTURED_EFFECT_03',
        'CAPTURED_EFFECT_04', 'CAPTURED_EFFECT_05', 'CAPTURED_EFFECT_08')]
    if preset.engine:
        selected = {1: effects[0], 3: effects[1], 5: effects[3], 8: effects[4]}[preset.engine]
        selected[62:64] = bytes((preset.brightness, preset.speed))
        if preset.engine in (1, 8):
            colors = [token(palette, preset.colors[i % len(preset.colors)]) for i in range(5)]
            selected[1:16] = b''.join(colors)
            selected[59] = 0
            if preset.engine == 1:
                selected[60:62] = bytes((int(preset.loop), 0))
            else:
                selected[60:62] = bytes((preset.direction, int(preset.loop)))
        elif preset.engine == 5:
            selected[61] = preset.direction
        frames = custom_frames({}, root)
        commit = bytearray(64)
        commit[:2] = bytes((preset.engine, 5))
        commit[62:] = b'\xaa\x55'
    else:
        frames = custom_frames(static_colors(preset, palette, data['keys']), root)
        commit = bytes.fromhex(data['E1_COMMIT'])
    return transaction([bytes(header), *map(bytes, effects), *frames, bytes(commit)], root)


def mouse_settings(preset, palette):
    color = bytes(3) if preset.name == 'off' else token(palette, preset.colors[0])
    color = blend(bytes(3), color, preset.brightness / 5)
    # One exposed mouse LED: pair spatial keyboard effects with a native pulse.
    # This controller exposes neither speed nor brightness controls through OpenRGB.
    return {'mode': preset.mouse_mode, 'color': None if preset.mouse_mode == 'Rainbow' else color.hex()}
