"""Rofi selector and host-scoped persistence for RGB compositions."""
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from cli import atomic_write, host_write_path, hostname, read, resolve
from rgb_presets import PRESETS, get


def device_target(device):
    identity = device.get('usb_id', '').lower()
    if device.get('backend') == 'hyperx-mars' and identity == '0951:16c6':
        return 'keyboard'
    if device.get('backend') == 'openrgb' and identity == '04d9:fc30':
        return 'mouse'
    return None


def selected_devices(settings, target):
    if not settings['features']['rgb']:
        raise ValueError('RGB is disabled on this host. Enable it with: voluta feature enable rgb --scope host')
    if target not in ('all', 'keyboard', 'mouse'):
        raise ValueError('RGB target must be all, keyboard or mouse')
    devices = [d for d in settings['rgb'].get('devices', [])
               if device_target(d) and (target == 'all' or device_target(d) == target)]
    if not devices:
        raise ValueError('No selected RGB devices for this target; configure this host first')
    return devices


def selection(settings, target):
    names = {d.get('preset', 'voluta' if d.get('layout') == 'voluta' else 'accent')
             for d in selected_devices(settings, target)}
    return next(iter(names)) if len(names) == 1 else None


def select(directory, host, name, target='all'):
    get(name)
    hostname(host)
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'voluta'
    state.mkdir(parents=True, exist_ok=True)
    lock_name = hashlib.sha256(str(directory.resolve()).encode()).hexdigest() + '.lock'
    with (state / lock_name).open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        settings, _ = resolve(directory, host)
        devices = selected_devices(settings, target)
        updated = copy.deepcopy(settings['rgb']['devices'])
        for device in updated:
            if device in devices:
                device['preset'] = name
        path = host_write_path(directory, host)
        data = read(path) or {'version': 1}
        data.setdefault('rgb', {})['devices'] = updated
        atomic_write(path, data)
    # Apply right away rather than depending on the next watcher tick.
    from rgb import apply
    results = apply(directory, host)
    return int(any(item['status'] == 'unavailable' for item in results))


def choose(rows, prompt, message='', selected=0):
    command = ['rofi', '-dmenu', '-i', '-no-custom', '-format', 'i',
               '-p', prompt, '-mesg', message, '-selected-row', str(selected)]
    theme = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'rofi/rgb.rasi'
    if theme.is_file():
        command += ['-theme', str(theme)]
    result = subprocess.run(command,
                            input='\n'.join(rows) + '\n', text=True, capture_output=True)
    if result.returncode != 0:
        return None
    try:
        index = int(result.stdout.strip())
        return index if 0 <= index < len(rows) else None
    except ValueError:
        return None


def menu(directory, host, target=None):
    if not shutil.which('rofi'):
        raise ValueError('The RGB menu requires rofi')
    settings, _ = resolve(directory, host)
    selected_devices(settings, target or 'all')
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')))
    runtime.mkdir(parents=True, exist_ok=True)
    with (runtime / 'voluta-rgb-menu.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        if target is None:
            available = [('all', 'Both devices'), ('keyboard', 'Keyboard'), ('mouse', 'Mouse')]
            available = [(key, label) for key, label in available
                         if key == 'all' or any(device_target(d) == key for d in settings['rgb']['devices'])]
            index = choose([label for _, label in available], 'RGB · target', 'Choose which peripherals to change')
            if index is None:
                return 0
            target = available[index][0]
        current = selection(settings, target)
        rows = [f'{"●" if p.name == current else "○"}  {"Animation" if p.engine else "Static"} · {p.title} — '
                + (p.mouse_mode + (' · firmware colors' if p.mouse_mode == 'Rainbow' else ' · paired palette accent')
                   if target == 'mouse' else p.description)
                for p in PRESETS]
        index = choose(rows, 'RGB · ' + ('both' if target == 'all' else target),
                       'Wallust colors · saved for this host · Esc leaves settings unchanged',
                       next((i for i, p in enumerate(PRESETS) if p.name == current), 0))
        if index is None:
            return 0
        try:
            result = select(directory, host, PRESETS[index].name, target)
        except (OSError, ValueError) as error:
            subprocess.run(['rofi', '-e', str(error)], check=False)
            raise
        if result:
            subprocess.run(['rofi', '-e', 'Preset saved, but a device could not be updated. Run voluta rgb for details.'], check=False)
        elif shutil.which('notify-send'):
            subprocess.run(['notify-send', 'Voluta RGB', PRESETS[index].title + ' · ' + target], check=False)
        return result


def dispatch(args, directory, host):
    if args.action != 'apply' and (args.dry_run or args.force):
        raise ValueError('--dry-run and --force apply only to rgb apply')
    if args.action != 'select' and args.preset is not None:
        raise ValueError('A preset ID requires rgb select')
    if args.action == 'list' and args.target is not None:
        raise ValueError('--target requires rgb select or rgb menu')
    if args.action == 'list':
        print(json.dumps([{'id': p.name, 'name': p.title, 'type': 'animation' if p.engine else 'static',
                           'description': p.description, 'mouse_mode': p.mouse_mode} for p in PRESETS], indent=2))
        return 0
    if args.action == 'menu':
        return menu(directory, host, args.target)
    if args.action == 'select':
        if args.preset is None:
            raise ValueError('Select requires a preset ID; see voluta rgb list')
        return select(directory, host, args.preset, args.target or 'all')
    if args.preset is not None or args.target is not None:
        raise ValueError('Preset and target require rgb select or rgb menu')
    from rgb import apply
    results = apply(directory, host, args.dry_run, args.force)
    return int(any(item['status'] == 'unavailable' for item in results))
