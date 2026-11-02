"""Wallust-to-device bridge. No probing writes to unspecified hardware."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from cli import ROOT, atomic_write, resolve


def present(usb_id):
    matches = []
    if not re.fullmatch(r'[0-9a-fA-F]{4}:[0-9a-fA-F]{4}', usb_id):
        raise ValueError('RGB devices require a USB vendor:product ID')
    vendor, product = usb_id.lower().split(':')
    for path in Path('/sys/bus/usb/devices').glob('*'):
        try:
            if (path / 'idVendor').read_text().strip() == vendor and (path / 'idProduct').read_text().strip() == product:
                matches.append(str(path) + ':' + (path / 'devnum').read_text().strip())
        except OSError:
            pass
    return matches


def palette_colors():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    text = (config / 'hypr/wallust/colors-shell.sh').read_text()
    return dict(re.findall(r"^(wc_\w+)=['\"]?([0-9a-fA-F]{6})['\"]?\s*$", text, re.M))


def palette_color(settings):
    key = settings.get('rgb', {}).get('accent', 'wc_1')
    color = palette_colors().get(key)
    if not color:
        raise ValueError('Wallust RGB accent is missing or invalid')
    return color


def mars_custom_reports(palette):
    """Validated E1 profile: 104 keys and 15 bar LEDs, using palette colors only."""
    data = json.loads((ROOT / 'voluta/mars-custom.json').read_text())
    required = [f'wc_{n}' for n in (1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14)]
    if any(key not in palette or not re.fullmatch('[0-9a-fA-F]{6}', palette[key]) for key in required):
        raise ValueError('Per-key RGB requires a complete Wallust palette')

    def color(number):
        return bytes.fromhex(palette[f'wc_{number}'])

    def palette_band(position):
        stops = [color(n) for n in (4, 5, 1, 3, 2, 6)]
        return stops[min(len(stops) - 1, int(max(0, min(1, position)) * len(stops)))]

    frames = [bytearray(row) for row in json.loads((ROOT / 'voluta/mars-keymap.json').read_text())]
    for frame in frames:
        for offset in range(0, 64, 4):
            frame[offset + 1:offset + 4] = b'\x00' * 3
    for key in data['keys']:
        index, label = key['index'], key['label']
        # Physical coordinates matter: firmware rows interleave the navigation block.
        rgb = palette_band(key['x'] / 480 + key['y'] / 178 * .12)
        if index // 18 == 7:
            rgb = palette_band((index % 18 - 3) / 14)
        elif label.startswith('F') and label[1:].isdigit():
            rgb = color((12, 13, 14)[(int(label[1:]) - 1) // 4])
        elif label == 'Esc':
            rgb = color(9)
        elif label in ('Left Win', 'FN', 'App'):
            rgb = color(13)
        elif any(word in label for word in ('Shift', 'Ctrl', 'Alt')):
            rgb = color(12)
        elif label in ('Enter', 'Num Enter', 'Space'):
            rgb = color(11)
        elif label in ('W', 'A', 'S', 'D'):
            rgb = color(10)
        elif label in ('Left', 'Down', 'Up', 'Right'):
            rgb = color(14)
        elif label in ('Insert', 'Home', 'Page up', 'End', 'Page down', 'Print Scr', 'Scroll lock', 'Pause'):
            rgb = color(6)
        elif label in ('Delete', 'Backspace'):
            rgb = color(9)
        elif label.startswith('Num') or label == 'Decimal':
            rgb = palette_band((key['y'] - 49) / 129)
        offset = (index % 16) * 4
        frames[index // 16][offset + 1:offset + 4] = rgb

    query = lambda command: bytes((4, command)) + bytes(62)
    header = bytearray(query(10))
    header[8] = 15
    return [query(0xab), bytes.fromhex(data['E1_SESSION_BLOCK']), query(2), bytes(header),
            *(bytes.fromhex(data[name]) for name in ('E1_EFFECT_01', 'CAPTURED_EFFECT_03',
                'CAPTURED_EFFECT_04', 'CAPTURED_EFFECT_05', 'CAPTURED_EFFECT_08')),
            *map(bytes, frames), bytes.fromhex(data['E1_COMMIT']), query(2)]


def mars_reports(color):
    rgb = bytes.fromhex(color)
    reports = []
    header = bytearray(64)
    header[0:2] = b'\x04\x0a'
    header[8] = 15
    reports.append(bytes(header))
    for code in (1, 3, 4, 5, 8):
        frame = bytearray(64)
        frame[0] = code
        if code in (1, 8):
            frame[1:16] = rgb * 5
            frame[63] = 3
        if code == 4:
            frame[1:4] = rgb
        frame[62] = 5
        reports.append(bytes(frame))
    reports.extend(bytes(row) for row in json.loads((ROOT / 'voluta/mars-keymap.json').read_text()))
    commit = bytearray(64)
    commit[0:2] = b'\x04\x05'
    commit[62:64] = b'\xaa\x55'
    reports.append(bytes(commit))
    return reports


def mars_apply(color, custom_reports=None):
    from rgb_presets import transaction
    reports = custom_reports if custom_reports is not None else transaction(mars_reports(color), ROOT)
    device = mars_open()
    try:
        for index, report in enumerate(reports):
            if index in (0, 2, 3, 19):
                mars_transact(device, report)
            else:
                mars_send(device, report)
                time.sleep(.01)
    finally:
        device.close()


def mars_open():
    try:
        import hid
    except ImportError as error:
        raise ValueError('HyperX Mars requires the Arch python-hidapi package') from error
    devices = [d for d in hid.enumerate(0x0951, 0x16c6) if d.get('interface_number') == 0 and d.get('usage_page') == 1]
    if not devices:
        raise ValueError('HyperX Mars interface 0 / usage page 1 not available')
    device = hid.device()
    device.open_path(devices[0]['path'])
    return device


def mars_send(device, payload):
    result = device.send_feature_report(b'\x00' + bytes(payload))
    if result != 65:
        raise ValueError('HyperX Mars feature write failed or was incomplete')


def mars_transact(device, frame):
    command = frame[1]
    for _ in range(3):
        mars_send(device, frame)
        time.sleep(.04)
        response = bytes(device.get_feature_report(0, 65))
        if bytes((4, command, 0, 1)) in response:
            return
    raise ValueError(f'HyperX Mars did not acknowledge command {command:02x}')


def keepalive(directory, host):
    """Read-only E0 query advances native multicolor breathing; never writes a profile."""
    from rgb_presets import get
    settings, _ = resolve(directory, host)
    if not settings['features']['rgb']:
        return
    selected = [d for d in settings['rgb'].get('devices', [])
                if d.get('backend') == 'hyperx-mars' and d.get('usb_id', '').lower() == '0951:16c6'
                and d.get('experimental') is True and d.get('preset')
                and get(d['preset']).engine == 1 and get(d['preset']).loop]
    if not selected or not present('0951:16c6'):
        return
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'voluta'
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'rgb.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        device = mars_open()
        try:
            mars_transact(device, bytes((4, 0xe0)) + bytes(62))
        finally:
            device.close()


def apply(directory, host, dry_run=False, force=False):
    settings, _ = resolve(directory, host)
    if not settings['features']['rgb']:
        return []
    color = palette_color(settings)
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'voluta'
    state.mkdir(parents=True, exist_ok=True)
    results = []
    with (state / 'rgb.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cache_path = state / f'rgb-{host}.json'
        cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
        for device in settings['rgb'].get('devices', []):
            identity = str(device.get('usb_id', ''))
            backend = device.get('backend')
            attached = present(identity)
            if not attached:
                results.append({'device': identity, 'status': 'absent'})
                continue
            if backend == 'hyperx-mars' and (identity.lower() != '0951:16c6' or device.get('experimental') is not True):
                raise ValueError('Mars adapter requires exact USB ID and experimental=true')
            if backend not in ('openrgb', 'hyperx-mars'):
                raise ValueError('Unsupported RGB backend')
            layout = device.get('layout', 'static')
            if layout not in ('static', 'voluta') or (layout == 'voluta' and backend != 'hyperx-mars'):
                raise ValueError('RGB layout must be static, or voluta for HyperX Mars')
            preset = None
            mouse = None
            if device.get('preset'):
                from rgb_presets import get, reports as preset_reports, mouse_settings
                preset = get(device['preset'])
                palette = palette_colors()
                reports = preset_reports(preset, palette, ROOT) if backend == 'hyperx-mars' else None
                mouse = mouse_settings(preset, palette) if backend == 'openrgb' else None
            else:
                reports = mars_custom_reports(palette_colors()) if layout == 'voluta' else None
            # Hash the actual transaction: every per-key color participates in invalidation.
            fingerprint = hashlib.sha256(json.dumps([device, attached, color if reports is None and mouse is None else None, mouse,
                [p.hex() for p in reports] if reports else None], sort_keys=True).encode()).hexdigest()
            if cache.get(identity) == fingerprint and not force:
                results.append({'device': identity, 'status': 'unchanged'})
                continue
            if dry_run:
                results.append({'device': identity, 'status': 'would-apply', 'color': mouse['color'] if mouse else color,
                                'backend': backend, 'preset': preset.name if preset else layout})
                continue
            try:
                if backend == 'openrgb':
                    name = device.get('name')
                    if not isinstance(name, str) or not name:
                        raise ValueError('OpenRGB requires an exact device name')
                    if not shutil.which('openrgb'):
                        raise ValueError('OpenRGB is not installed')
                    command = ['openrgb', '--device', name, '--mode', mouse['mode'] if mouse else 'Static']
                    selected_color = mouse['color'] if mouse else color
                    if selected_color is not None:
                        command += ['--color', selected_color]
                    subprocess.run(command, check=True, timeout=20, stdout=subprocess.DEVNULL)
                else:
                    mars_apply(color, reports)
                cache[identity] = fingerprint
                results.append({'device': identity, 'status': 'applied'})
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                results.append({'device': identity, 'status': 'unavailable', 'reason': str(error)})
        if not dry_run:
            atomic_write(cache_path, cache)
    print(json.dumps(results), flush=True)
    return results
