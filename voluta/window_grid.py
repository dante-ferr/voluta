"""Outer edges of the Hyprland window grid.

Tiled windows sit inside each monitor's reserved exclusive zone, then inset
by ``general:gaps_out``. That sum is the only edge a framed menu may use.
``gaps_out`` uses CSS order: top, right, bottom, left. Hyprland's monitor
``reserved`` array is left, top, right, bottom.
"""
import json
import subprocess
import sys
from pathlib import Path

SIDES = ('left', 'top', 'right', 'bottom')


def parse_gaps(css):
    """Parse Hyprland's CSS gap string into left, top, right, and bottom."""
    parts = [int(piece) for piece in str(css).split()]
    if len(parts) == 1:
        top = right = bottom = left = parts[0]
    elif len(parts) == 2:
        top = bottom = parts[0]
        right = left = parts[1]
    elif len(parts) == 3:
        top, horizontal, bottom = parts
        right = left = horizontal
    elif len(parts) >= 4:
        top, right, bottom, left = parts[:4]
    else:
        raise ValueError('gaps_out is empty')
    return {'left': left, 'top': top, 'right': right, 'bottom': bottom}


def reserved_edges(monitor):
    """Read one monitor's exclusive zone. Order is left, top, right, bottom."""
    raw = monitor.get('reserved') or [0, 0, 0, 0]
    if not isinstance(raw, list) or len(raw) < 4:
        raise ValueError('monitor reserved area is incomplete')
    left, top, right, bottom = (max(0, int(raw[0])), max(0, int(raw[1])),
                                max(0, int(raw[2])), max(0, int(raw[3])))
    return {'left': left, 'top': top, 'right': right, 'bottom': bottom}


def insets(reserved, gaps):
    """Return the window-grid edges in screen pixels."""
    return {side: reserved[side] + gaps[side] for side in SIDES}


def gaps_from_option(payload):
    data = json.loads(payload)
    if not isinstance(data, dict) or 'css' not in data:
        raise ValueError('gaps_out option is missing')
    return parse_gaps(data['css'])


def grid_for_monitor(monitor, gaps):
    reserved = reserved_edges(monitor)
    return {'monitor': monitor.get('name') or '', 'gaps': gaps, 'reserved': reserved,
            'insets': insets(reserved, gaps)}


def swaync_config_with_grid(config, gaps):
    """Point the top-anchored control center at the grid. Leave its other margins."""
    merged = dict(config)
    merged['control-center-margin-top'] = gaps['top']
    return merged


def _run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=1)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or 'hyprctl failed')
    return result.stdout


def live_grid(monitor_name=''):
    monitors = json.loads(_run(['hyprctl', '-j', 'monitors']))
    gaps = gaps_from_option(_run(['hyprctl', '-j', 'getoption', 'general:gaps_out']))
    if monitor_name:
        monitor = next(item for item in monitors if item.get('name') == monitor_name)
    else:
        monitor = next(item for item in monitors if item.get('focused'))
    return grid_for_monitor(monitor, gaps)


def main(argv):
    if len(argv) >= 4 and argv[1] == '--swaync-config':
        source, destination = Path(argv[2]), Path(argv[3])
        config = json.loads(source.read_text())
        gaps = gaps_from_option(_run(['hyprctl', '-j', 'getoption', 'general:gaps_out']))
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(swaync_config_with_grid(config, gaps), indent=2) + '\n')
        return 0
    name = argv[1] if len(argv) > 1 else ''
    json.dump(live_grid(name), sys.stdout)
    sys.stdout.write('\n')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main(sys.argv))
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, StopIteration, json.JSONDecodeError):
        raise SystemExit(1)
