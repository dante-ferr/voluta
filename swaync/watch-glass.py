#!/usr/bin/env python3
"""Optional, input-transparent animation behind the native SwayNC control center.

No daemon configuration or CSS is changed here. A missing renderer, palette,
output, or aperture leaves SwayNC's permanent static backing fully usable.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import struct
import time
import sys
import threading

DIRECTORY = Path(__file__).resolve().parent
ROOT = DIRECTORY.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from voluta.menus import compositor_environment, menu_colors
from voluta.window_grid import gaps_from_option, grid_for_monitor
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
GLASS_QML = DIRECTORY / 'glass.qml'


def run(arguments, timeout=1):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def renderer_environment(config=CONFIG):
    assets = config / 'wallust/assets/generated'
    if not (assets / 'notification-aperture.png').is_file():
        return None
    try:
        with (assets / 'notification-aperture.png').open('rb') as stream:
            header = stream.read(24)
        if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
            return None
        plate_width, plate_height = struct.unpack('>II', header[16:24])
        if not (0 < plate_width <= 16384 and 0 < plate_height <= 16384):
            return None
        palette = menu_colors(config / 'hypr/wallust/colors-shell.sh')
        monitors = json.loads(run(['hyprctl', '-j', 'monitors']) or 'null')
        if not isinstance(monitors, list):
            return None
        monitors = [monitor for monitor in monitors if isinstance(monitor, dict)]
        settings = json.loads((config / 'swaync/config.json').read_text())
        if not isinstance(settings, dict):
            return None
        preferred = settings.get('control-center-preferred-output')
        monitor = next((m for m in monitors if preferred and preferred in (m.get('name'), m.get('description'))), None)
        if monitor is None:
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
        if scale <= 0 or width / scale < plate_width or height / scale < plate_height + edges['top']:
            return None
        environment = compositor_environment()
        environment.update(VOLUTA_NOTIFICATION_ASSETS=str(assets),
                    VOLUTA_NOTIFICATION_COLORS=palette,
                    VOLUTA_NOTIFICATION_MONITOR=monitor['name'],
                    VOLUTA_NOTIFICATION_TOP=str(edges['top']),
                    VOLUTA_NOTIFICATION_WIDTH=str(plate_width),
                    VOLUTA_NOTIFICATION_HEIGHT=str(plate_height),
                    VOLUTA_NOTIFICATION_RESERVED_TOP=str(grid['reserved']['top']),
                    VOLUTA_NOTIFICATION_MARGIN_TOP=str(grid['gaps']['top']),
                    VOLUTA_GRID_LEFT=str(edges['left']), VOLUTA_GRID_TOP=str(edges['top']),
                    VOLUTA_GRID_RIGHT=str(edges['right']), VOLUTA_GRID_BOTTOM=str(edges['bottom']))
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


def renderer_pid(path=GLASS_QML):
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


def artwork_fingerprint(config=CONFIG):
    paths = ('hypr/wallust/colors-shell.sh', 'wallust/assets/generated/notification-aperture.png',
             'swaync/config.json', 'wallust/assets/generated/launcher-vignette.svg')
    fingerprints = []
    for relative in paths:
        try:
            stat = (config / relative).stat()
            fingerprints.append((stat.st_ino, stat.st_mtime_ns, stat.st_size))
        except OSError:
            fingerprints.append(None)
    return tuple(fingerprints)


class Glass:
    """One warmed renderer and an asynchronous, latest-request IPC lane."""
    def __init__(self):
        self.process = None
        self.fingerprint = None
        self.environment = None
        self.next_check = 0
        self.active = False
        self.token = 0
        self.pending = None
        self.closed = False
        self.condition = threading.Condition()
        self.worker = threading.Thread(target=self._work, daemon=True)
        self.worker.start()

    def _work(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.closed or self.pending is not None)
                if self.closed:
                    return
                token, command = self.pending
                self.pending = None
            # Only the initial prewarm normally needs retries while QML loads.
            # A newer state supersedes retries immediately; the event reader is
            # never blocked by renderer startup, close animations, or IPC waits.
            deadline = time.monotonic() + 2
            while run(command, timeout=.4) is None:
                with self.condition:
                    if self.closed or self.token != token or time.monotonic() >= deadline:
                        break
                    self.condition.wait(timeout=.015)

    def _send(self, method, *arguments):
        if self.process is None or self.process.poll() is not None:
            return
        with self.condition:
            self.token += 1
            command = ['quickshell', 'ipc', '--pid', str(self.process.pid),
                       'call', 'notification', method, *map(str, arguments), str(self.token)]
            self.pending = (self.token, command)
            self.condition.notify()

    def _arguments(self):
        environment = self.environment
        version = hashlib.sha256(repr(self.fingerprint).encode()).hexdigest()
        return (environment['VOLUTA_NOTIFICATION_MONITOR'], environment['VOLUTA_NOTIFICATION_COLORS'],
                environment['VOLUTA_NOTIFICATION_ASSETS'], environment['VOLUTA_NOTIFICATION_RESERVED_TOP'],
                environment['VOLUTA_NOTIFICATION_MARGIN_TOP'], environment['VOLUTA_NOTIFICATION_WIDTH'],
                environment['VOLUTA_NOTIFICATION_HEIGHT'], version)

    def respawn(self):
        """Attach to a live renderer or start one. True when a new pid is bound."""
        if self.process is not None and self.process.poll() is None:
            return False
        # A previous pid is gone. Reuse a leftover Quickshell before spawning.
        if self.process is not None:
            live = renderer_pid()
            if live:
                self.process = AttachedProcess(live)
                return True
        if self.environment is None:
            return False
        try:
            # Keep this process as the IPC pid. -n collapses duplicates; do not
            # daemonize, or Popen would point at an exited parent.
            self.process = subprocess.Popen(
                ['quickshell', '-n', '-p', str(GLASS_QML)],
                env=self.environment, stdin=subprocess.DEVNULL)
        except OSError:
            self.process = None
            return False
        return True

    def warm(self):
        self.fingerprint = artwork_fingerprint()
        self.next_check = time.monotonic() + .5
        self.environment = renderer_environment()
        if self.environment is None:
            # Retain the desired native visibility so a later valid palette
            # publication can restore decoration while the center stays open.
            self._send('dismiss')
            return
        self.respawn()
        self._send('showPanel' if self.active else 'prepare', *self._arguments())

    def recover(self):
        if self.process is not None and self.process.poll() is None:
            return
        self.environment = renderer_environment() or self.environment
        if self.respawn() and self.active and self.environment is not None:
            self._send('showPanel', *self._arguments())

    def refresh(self):
        now = time.monotonic()
        if now < self.next_check:
            return
        self.next_check = now + .5
        if artwork_fingerprint() != self.fingerprint:
            # Same URL may contain new bytes. QML explicitly unloads its mask.
            self.warm()

    def show(self):
        self.active = True
        # Focused output or palette can change while the menu is hidden.
        # Refresh placement without restarting the warmed Qt process.
        self.warm()

    def hide(self):
        self.active = False
        self._send('dismiss')

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
    return runtime / f'voluta-notification-glass-{os.getuid()}-{suffix}.lock'


def main():
    # Advisory lock closes on termination; a second autostart cannot duplicate
    # the subscription or leave two input-transparent layers behind.
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp'))
    try:
        lock = lock_path(runtime).open('a')
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, BlockingIOError):
        return
    if not all(shutil.which(tool) for tool in ('quickshell', 'swaync-client', 'hyprctl')):
        return
    if run(['quickshell', '--version']) is None:
        return
    stopped = False

    def stop(_signal, _frame):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    glass = Glass()
    subscriber = None
    delay = .5
    pidfile = runtime / 'voluta-notification-glass.pid'
    pidfile.write_text(str(os.getpid()) + '\n')
    try:
        glass.warm()
        while not stopped:
            subscriber = subprocess.Popen(['swaync-client', '-s', '-sw'],
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            visible = False
            started = time.monotonic()
            with selectors.DefaultSelector() as events:
                events.register(subscriber.stdout, selectors.EVENT_READ)
                pending = b''
                while not stopped:
                    glass.recover()
                    if visible:
                        glass.refresh()
                    if not events.select(timeout=.25):
                        continue
                    chunk = os.read(subscriber.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    pending += chunk
                    # Bound malformed subscriber output without retaining an
                    # unbounded stream when a client version changes format.
                    if len(pending) > 262144:
                        pending = b''
                    while b'\n' in pending:
                        line, pending = pending.split(b'\n', 1)
                        try:
                            state = json.loads(line)
                        except (ValueError, UnicodeDecodeError):
                            continue
                        if not isinstance(state, dict) or not isinstance(state.get('visible'), bool):
                            continue
                        if state['visible'] != visible:
                            visible = state['visible']
                            glass.show() if visible else glass.hide()
            # A disconnected daemon must never leave a stale glass plate.
            glass.hide()
            terminate(subscriber)
            subscriber.stdout.close()
            subscriber = None
            delay = .5 if time.monotonic() - started > 10 else min(delay * 2, 5)
            deadline = time.monotonic() + delay
            while not stopped and time.monotonic() < deadline:
                time.sleep(.1)
    finally:
        glass.shutdown()
        terminate(subscriber)
        pidfile.unlink(missing_ok=True)
        lock.close()


if __name__ == '__main__':
    main()
