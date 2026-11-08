#!/usr/bin/env python3
"""Resident music salon: album art, CAVA-like bars, shared framed-menu glass."""
from collections import deque
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import sys

DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from voluta.window_grid import gaps_from_option, grid_for_monitor
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', Path.home() / '.cache/voluta'))
PLAYER_FORMAT = ('{{status}}|{{mpris:artUrl}}|{{artist}}|{{title}}|{{album}}|'
                 '{{position}}|{{mpris:length}}|{{volume}}|{{loop}}|{{shuffle}}|{{playerName}}')
SALON_QML = DIRECTORY / 'salon.qml'


def run(arguments, timeout=1):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def terminate(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=.5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


class AttachedProcess:
    """Attach to a Quickshell instance started by an earlier watcher."""

    def __init__(self, pid):
        self.pid = pid

    def poll(self):
        try:
            os.kill(self.pid, 0)
        except OSError:
            return 1
        return None

    def terminate(self):
        try:
            os.kill(self.pid, signal.SIGTERM)
        except OSError:
            pass

    def kill(self):
        try:
            os.kill(self.pid, signal.SIGKILL)
        except OSError:
            pass

    def wait(self, timeout=None):
        deadline = time.monotonic() + (timeout if timeout is not None else 1e9)
        while self.poll() is None:
            if time.monotonic() >= deadline:
                raise subprocess.TimeoutExpired('quickshell', timeout)
            time.sleep(0.02)


def renderer_pid(path=SALON_QML):
    raw = run(['quickshell', 'list', '-j', '-p', str(path)])
    if not raw:
        return None
    try:
        entries = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(entries, list):
        return None
    for entry in entries:
        pid = entry.get('pid') if isinstance(entry, dict) else None
        if isinstance(pid, int) and pid > 0:
            try:
                os.kill(pid, 0)
            except OSError:
                continue
            return pid
    return None


def snapshot_player():
    line = run(['playerctl', 'metadata', '--format', PLAYER_FORMAT])
    if not line:
        return parse_metadata('')
    return parse_metadata(line.splitlines()[0])


def renderer_environment(config=CONFIG):
    assets = config / 'wallust/assets/generated'
    aperture = assets / 'music-aperture.png'
    if not aperture.is_file() or not (assets / 'music-frame.png').is_file():
        return None
    try:
        with aperture.open('rb') as stream:
            header = stream.read(24)
        if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
            return None
        plate_width, plate_height = struct.unpack('>II', header[16:24])
        if not (0 < plate_width <= 16384 and 0 < plate_height <= 16384):
            return None
        palette_text = (config / 'hypr/wallust/colors-shell.sh').read_text()
        colors = dict(re.findall(r"^(wc_(?:2|4|fg))='([0-9a-fA-F]{6})'$", palette_text, re.M))
        palette = ' '.join('#' + colors[key] for key in ('wc_2', 'wc_4', 'wc_fg'))
        monitors = json.loads(run(['hyprctl', '-j', 'monitors']) or 'null')
        if not isinstance(monitors, list):
            return None
        monitors = [monitor for monitor in monitors if isinstance(monitor, dict)]
        monitor = next(m for m in monitors if m.get('focused'))
        if not isinstance(monitor.get('name'), str) or not monitor['name']:
            return None
        width, height = monitor['width'], monitor['height']
        if monitor.get('transform', 0) % 2:
            width, height = height, width
        scale = monitor['scale']
        grid = grid_for_monitor(monitor, gaps_from_option(
            run(['hyprctl', '-j', 'getoption', 'general:gaps_out']) or ''))
        edges = grid['insets']
        if scale <= 0 or width / scale < plate_width + edges['right'] or height / scale < plate_height:
            return None
        version = '%s:%s' % (aperture.stat().st_mtime_ns, aperture.stat().st_size)
        veil = assets / 'launcher-vignette.svg'
        if veil.is_file():
            version += ':%s:%s' % (veil.stat().st_mtime_ns, veil.stat().st_size)
        environment = dict(os.environ, VOLUTA_MUSIC_ASSETS=str(assets), VOLUTA_MUSIC_COLORS=palette,
                           VOLUTA_MUSIC_MONITOR=monitor['name'], VOLUTA_MUSIC_WIDTH=str(plate_width),
                           VOLUTA_MUSIC_HEIGHT=str(plate_height), VOLUTA_MUSIC_VERSION=version,
                           VOLUTA_GRID_LEFT=str(edges['left']), VOLUTA_GRID_TOP=str(edges['top']),
                           VOLUTA_GRID_RIGHT=str(edges['right']), VOLUTA_GRID_BOTTOM=str(edges['bottom']),
                           VOLUTA_WINDOW_GRID=str(ROOT / 'voluta/window_grid.py'),
                           VOLUTA_PYTHON=sys.executable)
        try:
            content = json.loads((assets / 'music-content.json').read_text())
            environment.update(VOLUTA_MUSIC_INSET_LEFT=str(int(content['left'])),
                               VOLUTA_MUSIC_INSET_TOP=str(int(content['top'])),
                               VOLUTA_MUSIC_INSET_WIDTH=str(int(content['width'])),
                               VOLUTA_MUSIC_INSET_HEIGHT=str(int(content['height'])))
        except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
            pass
        try:
            padding = json.loads((assets / 'music-edges.json').read_text())
            environment.update(VOLUTA_MUSIC_PAD_LEFT=str(int(padding['left'])),
                               VOLUTA_MUSIC_PAD_TOP=str(int(padding['top'])),
                               VOLUTA_MUSIC_PAD_RIGHT=str(int(padding['right'])),
                               VOLUTA_MUSIC_PAD_BOTTOM=str(int(padding['bottom'])))
        except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
            pass
        return environment
    except (OSError, ValueError, KeyError, TypeError, StopIteration, IndexError, ZeroDivisionError):
        return None


def cache_art(url, cache):
    if not url:
        return ''
    cache.mkdir(parents=True, exist_ok=True)
    if url.startswith('file:'):
        path = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path))
        if not path.is_file():
            return ''
        stamp = f'{path}:{path.stat().st_mtime_ns}:{path.stat().st_size}'
        destination = cache / ('art-' + hashlib.sha256(stamp.encode()).hexdigest()[:16] + path.suffix)
        if not destination.is_file() or destination.stat().st_size == 0:
            try:
                shutil.copyfile(path, destination)
            except OSError:
                return str(path)
        return str(destination)
    if not url.startswith(('http://', 'https://')):
        return ''
    destination = cache / ('art-' + hashlib.sha256(url.encode()).hexdigest()[:16])
    if destination.is_file() and destination.stat().st_size > 0:
        return str(destination)
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'VolutaMusic/1'})
        with urllib.request.urlopen(request, timeout=4) as response:
            payload = response.read(8 * 1024 * 1024)
        if len(payload) < 32:
            return ''
        temporary = destination.with_suffix('.part')
        temporary.write_bytes(payload)
        temporary.replace(destination)
        return str(destination)
    except (OSError, ValueError, urllib.error.URLError, TimeoutError):
        return ''


def parse_metadata(line):
    parts = (line or '').rstrip('\n').split('|')
    while len(parts) < 11:
        parts.append('')
    status, art, artist, title, album, position, length, volume, loop, shuffle, player = parts[:11]
    return {'status': status or 'Stopped', 'art': art, 'artist': artist,
            'title': title, 'album': album, 'position': position, 'length': length,
            'volume': volume, 'loop': loop, 'shuffle': shuffle, 'player': player}


class Salon:
    def __init__(self):
        self.process = None
        self.environment = None
        self.active = False
        self.token = 0
        self.closed = False
        self.metadata = parse_metadata('')
        self.cache = RUNTIME / 'voluta-music'
        self.cache.mkdir(parents=True, exist_ok=True)
        self.condition = threading.Condition()
        self.commands = deque()
        self.pending_bars = None
        self.worker = threading.Thread(target=self._work, daemon=True)
        self.worker.start()

    def _work(self):
        while True:
            with self.condition:
                self.condition.wait_for(
                    lambda: self.closed or self.commands or self.pending_bars is not None)
                if self.closed:
                    return
                if self.commands:
                    method, token, command = self.commands.popleft()
                else:
                    method, token, command = self.pending_bars
                    self.pending_bars = None
            deadline = time.monotonic() + (1 if method != 'bars' else 0.25)
            while run(command, timeout=.25) is None:
                with self.condition:
                    if self.closed or time.monotonic() >= deadline:
                        break
                    if method == 'bars' and self.pending_bars is not None:
                        break
                    self.condition.wait(timeout=.015)

    def _send(self, method, *arguments):
        if self.process is None or self.process.poll() is not None:
            return
        with self.condition:
            self.token += 1
            command = ['quickshell', 'ipc', '--pid', str(self.process.pid),
                       'call', 'music', method, *map(str, arguments)]
            item = (method, self.token, command)
            if method == 'bars':
                self.pending_bars = item
            else:
                self.commands.append(item)
            self.condition.notify()

    def bind_renderer(self):
        live = renderer_pid()
        if live:
            if self.process is None or getattr(self.process, 'pid', None) != live:
                self.process = AttachedProcess(live)
            return True
        return self.process is not None and self.process.poll() is None

    def warm(self):
        self.environment = renderer_environment()
        if self.environment is None:
            self._send('dismiss', '')
            return
        if not self.bind_renderer():
            try:
                self.process = subprocess.Popen(
                    ['quickshell', '-n', '-p', str(SALON_QML)],
                    env=self.environment, stdin=subprocess.DEVNULL)
            except OSError:
                self.process = None
                return
            for _ in range(20):
                if self.bind_renderer():
                    break
                time.sleep(0.05)
        self.metadata = snapshot_player()
        self.push_metadata()
        if self.active:
            env = self.environment
            self._send('openSalon', env['VOLUTA_MUSIC_MONITOR'], env['VOLUTA_MUSIC_COLORS'],
                       env['VOLUTA_MUSIC_ASSETS'], str(self.token), env['VOLUTA_MUSIC_VERSION'])

    def push_metadata(self):
        payload = dict(self.metadata)
        payload['art'] = cache_art(self.metadata.get('art', ''), self.cache)
        self._send('playback', json.dumps(payload, ensure_ascii=False))

    def show(self):
        self.active = True
        self.warm()

    def hide(self):
        self.active = False
        self._send('dismiss', '')

    def toggle(self):
        self.hide() if self.active else self.show()

    def renderer_showing(self):
        if self.process is None or self.process.poll() is not None:
            return False
        raw = run(['quickshell', 'ipc', '--pid', str(self.process.pid), 'call', 'music', 'status'])
        if not raw:
            return False
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return False
        return bool(payload.get('showing') or payload.get('active'))

    def reconcile(self):
        self.bind_renderer()
        showing = self.renderer_showing()
        was_active = self.active
        self.active = showing
        if not showing:
            return
        now = time.monotonic()
        if not was_active or now - getattr(self, '_last_snap', 0) >= 1:
            self._last_snap = now
            self.metadata = snapshot_player()
            self.push_metadata()

    def bars(self, values):
        if self.active:
            self._send('bars', values)

    def shutdown(self):
        with self.condition:
            self.closed = True
            self.condition.notify()
        self.worker.join(timeout=.4)
        terminate(self.process)
        self.process = None


def lock_path(runtime):
    session = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') or os.environ.get('WAYLAND_DISPLAY', 'default')
    suffix = hashlib.sha256(session.encode()).hexdigest()[:16]
    return runtime / f'voluta-music-{os.getuid()}-{suffix}.lock'


def follow_player(salon, stopped):
    salon.metadata = snapshot_player()
    salon.push_metadata()
    command = ['playerctl', '--follow', 'metadata', '--format', PLAYER_FORMAT]
    process = None
    while not stopped():
        try:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError:
            time.sleep(1)
            continue
        try:
            for raw in process.stdout:
                if stopped():
                    break
                salon.metadata = parse_metadata(raw.decode('utf-8', 'replace'))
                salon.push_metadata()
        finally:
            terminate(process)
        if not stopped():
            time.sleep(1)


def follow_cava(salon, stopped):
    config = RUNTIME / 'voluta-music-cava.conf'
    config.write_text((DIRECTORY / 'cava.conf').read_text())
    binary = shutil.which('cava')
    phase = 0.0
    while not stopped():
        if binary:
            try:
                process = subprocess.Popen(['cava', '-p', str(config)],
                                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            except OSError:
                binary = None
                continue
            try:
                for raw in process.stdout:
                    if stopped():
                        break
                    text = raw.decode('ascii', 'ignore').strip().replace(';', ' ')
                    if text:
                        salon.bars(text)
            finally:
                terminate(process)
            time.sleep(.4)
            continue
        if salon.metadata.get('status') == 'Playing':
            phase += 0.18
            values = [str(int(36 + 48 * abs(math.sin(phase + index * 0.22)))) for index in range(32)]
        else:
            values = ['0'] * 32
        salon.bars(' '.join(values))
        time.sleep(0.04)


def main():
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp'))
    try:
        lock = lock_path(runtime).open('a')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, BlockingIOError):
        return
    if not all(shutil.which(tool) for tool in ('quickshell', 'hyprctl', 'playerctl')):
        return
    if run(['quickshell', '--version']) is None:
        return
    stopped = False
    requested = threading.Event()

    def stop(_signal, _frame):
        nonlocal stopped
        stopped = True
        requested.set()

    def request_toggle(_signal, _frame):
        requested.set()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGUSR1, request_toggle)
    salon = Salon()
    pidfile = runtime / 'voluta-music.pid'
    pidfile.write_text(str(os.getpid()) + '\n')
    threads = [
        threading.Thread(target=follow_player, args=(salon, lambda: stopped), daemon=True),
        threading.Thread(target=follow_cava, args=(salon, lambda: stopped), daemon=True),
    ]
    for thread in threads:
        thread.start()
    try:
        salon.warm()
        while not stopped:
            fired = requested.wait(timeout=0.2)
            if stopped:
                break
            if fired:
                requested.clear()
                salon.toggle()
            salon.reconcile()
    finally:
        salon.shutdown()
        pidfile.unlink(missing_ok=True)
        lock.close()


if __name__ == '__main__':
    main()
