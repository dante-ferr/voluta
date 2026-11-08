#!/usr/bin/env python3
"""One JSON line describing night light, the default sink, and monitors."""
import json
import subprocess
from pathlib import Path


def run(arguments):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=1)
    except (OSError, subprocess.TimeoutExpired):
        return ''
    return result.stdout if result.returncode == 0 else ''


def uptime_label():
    try:
        seconds = int(float(Path('/proc/uptime').read_text().split()[0]))
    except (OSError, ValueError, IndexError):
        return ''
    days, remainder = divmod(seconds, 86400)
    hours, remainder = divmod(remainder, 3600)
    minutes = remainder // 60
    if days:
        return f'{days}d {hours}h'
    if hours:
        return f'{hours}h {minutes}m'
    return f'{minutes}m'


def battery_status():
    root = Path('/sys/class/power_supply')
    if not root.is_dir():
        return None
    for supply in root.iterdir():
        try:
            kind = (supply / 'type').read_text().strip()
        except OSError:
            continue
        if kind != 'Battery':
            continue
        try:
            percent = int((supply / 'capacity').read_text().strip())
        except (OSError, ValueError):
            continue
        charging = ''
        try:
            charging = (supply / 'status').read_text().strip()
        except OSError:
            pass
        return {'percent': percent, 'status': charging}
    return None


def snapshot():
    volume_text = run(['wpctl', 'get-volume', '@DEFAULT_AUDIO_SINK@'])
    volume = 0.0
    muted = False
    for token in volume_text.split():
        try:
            volume = float(token)
        except ValueError:
            if token == '[MUTED]':
                muted = True
    sink = ''
    for line in run(['wpctl', 'inspect', '@DEFAULT_AUDIO_SINK@']).splitlines():
        if 'node.description' in line and '=' in line:
            sink = line.split('=', 1)[1].strip().strip('"')
            break
    monitors = []
    try:
        raw = json.loads(run(['hyprctl', '-j', 'monitors']) or 'null')
    except json.JSONDecodeError:
        raw = None
    if isinstance(raw, list):
        for monitor in raw:
            if isinstance(monitor, dict) and isinstance(monitor.get('name'), str):
                monitors.append({'name': monitor['name'], 'focused': bool(monitor.get('focused'))})
    night = subprocess.run(['pgrep', '-x', 'hyprsunset'], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL).returncode == 0
    return {'night': night, 'volume': max(0.0, min(1.5, volume)), 'muted': muted,
            'sink': sink, 'uptime': uptime_label(), 'battery': battery_status(),
            'monitors': monitors}


if __name__ == '__main__':
    json.dump(snapshot(), __import__('sys').stdout)
    __import__('sys').stdout.write('\n')
