#!/usr/bin/env python3
"""Resident session column: lock, power, night light, sink, and monitors."""
from collections import deque
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import threading
import time

DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from voluta.menus import artwork_version, compositor_environment, menu_colors, menu_paths
from voluta.window_grid import gaps_from_option, grid_for_monitor

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
PANEL_QML = DIRECTORY / 'panel.qml'


def run(arguments, timeout=1):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def renderer_pid():
    payload = run(['quickshell', 'list', '-j', '-p', str(PANEL_QML)])
    if not payload:
        return None
    try:
        entries = json.loads(payload)
    except json.JSONDecodeError:
        return None
    if isinstance(entries, dict):
        entries = [entries]
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


def renderer_environment(config=None):
    if config is None:
        config = CONFIG
    assets = config / 'wallust/assets/generated'
    aperture = assets / 'session-aperture.png'
    if not aperture.is_file() or not (assets / 'session-frame.png').is_file():
        return None
    try:
        with aperture.open('rb') as stream:
            header = stream.read(24)
        if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
            return None
        plate_width, plate_height = struct.unpack('>II', header[16:24])
        palette = menu_colors(config / 'hypr/wallust/colors-shell.sh')
        monitors = json.loads(run(['hyprctl', '-j', 'monitors']) or 'null')
        if not isinstance(monitors, list):
            return None
        monitor = next(item for item in monitors if isinstance(item, dict) and item.get('focused'))
        if not isinstance(monitor.get('name'), str) or not monitor['name']:
            return None
        width, height = monitor['width'], monitor['height']
        if monitor.get('transform', 0) % 2:
            width, height = height, width
        scale = monitor['scale']
        grid = grid_for_monitor(monitor, gaps_from_option(
            run(['hyprctl', '-j', 'getoption', 'general:gaps_out']) or ''))
        edges = grid['insets']
        if scale <= 0 or width / scale < plate_width + edges['left'] or height / scale < plate_height:
            return None
        version = artwork_version(menu_paths(config, 'session'))
        environment = compositor_environment()
        environment.update(VOLUTA_SESSION_ASSETS=str(assets), VOLUTA_SESSION_COLORS=palette,
                           VOLUTA_SESSION_MONITOR=monitor['name'], VOLUTA_SESSION_WIDTH=str(plate_width),
                           VOLUTA_SESSION_HEIGHT=str(plate_height), VOLUTA_SESSION_VERSION=version,
                           VOLUTA_GRID_LEFT=str(edges['left']), VOLUTA_GRID_TOP=str(edges['top']),
                           VOLUTA_GRID_RIGHT=str(edges['right']), VOLUTA_GRID_BOTTOM=str(edges['bottom']),
                           VOLUTA_WINDOW_GRID=str(ROOT / 'voluta/window_grid.py'),
                           VOLUTA_PYTHON=sys.executable, VOLUTA_SESSION_STATUS=str(DIRECTORY / 'status.py'))
        try:
            content = json.loads((assets / 'session-content.json').read_text())
            environment.update(VOLUTA_SESSION_INSET_LEFT=str(int(content['left'])),
                               VOLUTA_SESSION_INSET_TOP=str(int(content['top'])),
                               VOLUTA_SESSION_INSET_WIDTH=str(int(content['width'])),
                               VOLUTA_SESSION_INSET_HEIGHT=str(int(content['height'])))
        except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
            pass
        try:
            padding = json.loads((assets / 'session-edges.json').read_text())
            environment.update(VOLUTA_SESSION_PAD_LEFT=str(int(padding['left'])),
                               VOLUTA_SESSION_PAD_TOP=str(int(padding['top'])),
                               VOLUTA_SESSION_PAD_RIGHT=str(int(padding['right'])),
                               VOLUTA_SESSION_PAD_BOTTOM=str(int(padding['bottom'])))
        except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
            pass
        return environment
    except (OSError, ValueError, KeyError, TypeError, StopIteration, IndexError, ZeroDivisionError):
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


class Session:
    def __init__(self):
        self.process = None
        self.environment = None
        self.active = False
        self.token = 0
        self.commands = deque()
        self.closed = False
        self.condition = threading.Condition()
        self.worker = threading.Thread(target=self._pump, daemon=True)
        self.worker.start()

    def _pump(self):
        while True:
            with self.condition:
                while not self.commands and not self.closed:
                    self.condition.wait()
                if self.closed and not self.commands:
                    return
                _method, _token, command = self.commands.popleft()
            try:
                subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1)
            except (OSError, subprocess.TimeoutExpired):
                pass

    def _send(self, method, *arguments):
        if self.process is None or self.process.poll() is not None:
            return
        with self.condition:
            self.token += 1
            command = ['quickshell', 'ipc', '--pid', str(self.process.pid),
                       'call', 'session', method, *map(str, arguments)]
            self.commands.append((method, self.token, command))
            self.condition.notify()

    def bind_renderer(self):
        live = renderer_pid()
        if live:
            if self.process is None or getattr(self.process, 'pid', None) != live:
                self.process = AttachedProcess(live)
            self._remember(live)
            return True
        if self.process is not None and self.process.poll() is None:
            self._remember(self.process.pid)
            return True
        return False

    def _remember(self, pid):
        runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp'))
        try:
            (runtime / 'voluta-session-renderer.pid').write_text(f'{pid}\n')
        except OSError:
            pass

    def warm(self):
        self.next_spawn = time.monotonic() + 2
        self.environment = renderer_environment()
        if self.environment is None:
            self._send('dismiss', '')
            return
        self.theme_stamp = self.environment['VOLUTA_SESSION_VERSION']
        if not self.bind_renderer():
            try:
                self.process = subprocess.Popen(
                    ['quickshell', '-n', '-p', str(PANEL_QML)],
                    env=self.environment, stdin=subprocess.DEVNULL)
            except OSError:
                self.process = None
                return
            for _ in range(20):
                if self.bind_renderer():
                    break
                time.sleep(0.05)

    def toggle(self):
        self.warm()
        if not self.environment:
            return
        env = self.environment
        self._send('toggle', env['VOLUTA_SESSION_COLORS'], env['VOLUTA_SESSION_ASSETS'],
                   env['VOLUTA_SESSION_VERSION'])

    def maintain(self):
        """Respawn after a startup that ran before the Wayland socket existed."""
        if self.process is not None and self.process.poll() is None:
            return
        now = time.monotonic()
        if now < getattr(self, 'next_spawn', 0):
            return
        if not compositor_environment().get('WAYLAND_DISPLAY'):
            self.next_spawn = now + 1
            return
        self.warm()

    def sync_publication(self):
        """Push a new Wallust publication without replaying the entrance."""
        now = time.monotonic()
        if now < getattr(self, 'next_theme', 0):
            return
        stamp = artwork_version(menu_paths(CONFIG, 'session'))
        if stamp == getattr(self, 'theme_stamp', None):
            return
        self.next_theme = now + 0.5
        environment = renderer_environment()
        if environment is None:
            self.next_theme = now + 2
            return
        self.environment = environment
        self.theme_stamp = environment['VOLUTA_SESSION_VERSION']
        self._send('recolor', environment['VOLUTA_SESSION_COLORS'],
                   environment['VOLUTA_SESSION_ASSETS'], environment['VOLUTA_SESSION_VERSION'])

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
    return runtime / f'voluta-session-{os.getuid()}-{suffix}.lock'


def main():
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp'))
    try:
        lock = lock_path(runtime).open('a')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, BlockingIOError):
        return
    if not all(shutil.which(tool) for tool in ('quickshell', 'hyprctl')):
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
    column = Session()
    pidfile = runtime / 'voluta-session.pid'
    pidfile.write_text(str(os.getpid()) + '\n')
    try:
        column.warm()
        while not stopped:
            if requested.wait(timeout=0.2):
                requested.clear()
                if not stopped:
                    column.toggle()
            column.maintain()
            column.sync_publication()
    finally:
        column.shutdown()
        pidfile.unlink(missing_ok=True)
        lock.close()


if __name__ == '__main__':
    main()
