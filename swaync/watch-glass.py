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
import re
import selectors
import shutil
import signal
import subprocess
import time

DIRECTORY = Path(__file__).resolve().parent
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))


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
        palette_text = (config / 'hypr/wallust/colors-shell.sh').read_text()
        colors = dict(re.findall(r"^(wc_(?:2|4|fg))='([0-9a-fA-F]{6})'$", palette_text, re.M))
        palette = ' '.join('#' + colors[key] for key in ('wc_2', 'wc_4', 'wc_fg'))
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
        width, height = monitor['width'], monitor['height']
        if monitor.get('transform', 0) % 2:
            width, height = height, width
        scale = monitor['scale']
        top = int(monitor.get('reserved', [0, 0, 0, 0])[1]) + max(0, int(settings.get('control-center-margin-top', 8)))
        if scale <= 0 or width / scale < 1056 or height / scale < 640 + top:
            return None
        return dict(os.environ, VOLUTA_NOTIFICATION_ASSETS=str(assets),
                    VOLUTA_NOTIFICATION_COLORS=palette,
                    VOLUTA_NOTIFICATION_MONITOR=monitor['name'],
                    VOLUTA_NOTIFICATION_TOP=str(top))
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


def artwork_fingerprint(config=CONFIG):
    paths = ('hypr/wallust/colors-shell.sh', 'wallust/assets/generated/notification-aperture.png',
             'swaync/config.json')
    fingerprints = []
    for relative in paths:
        try:
            stat = (config / relative).stat()
            fingerprints.append((stat.st_ino, stat.st_mtime_ns, stat.st_size))
        except OSError:
            fingerprints.append(None)
    return tuple(fingerprints)


class Glass:
    def __init__(self):
        self.process = None
        self.fingerprint = None
        self.next_check = 0

    def refresh(self):
        # Only called while the native center is visible. IPC is queried only
        # after an asset, palette, or geometry preference actually changes.
        now = time.monotonic()
        if now < self.next_check:
            return
        self.next_check = now + .5
        if artwork_fingerprint() != self.fingerprint:
            self.hide(animate=False)
            self.show()

    def show(self):
        self.fingerprint = artwork_fingerprint()
        self.next_check = time.monotonic() + .5
        if self.process and self.process.poll() is None:
            return
        environment = renderer_environment()
        if environment is not None:
            try:
                self.process = subprocess.Popen(
                    ['quickshell', '-p', str(DIRECTORY / 'glass.qml')],
                    env=environment, stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                self.process = None

    def hide(self, animate=True):
        process, self.process = self.process, None
        if process is None or process.poll() is not None:
            return
        if animate:
            run(['quickshell', 'ipc', '--pid', str(process.pid), 'call',
                 'notification', 'dismiss'], timeout=.4)
            try:
                process.wait(timeout=.5)
            except subprocess.TimeoutExpired:
                pass
        terminate(process)


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
    try:
        while not stopped:
            subscriber = subprocess.Popen(['swaync-client', '-s', '-sw'],
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            visible = False
            started = time.monotonic()
            with selectors.DefaultSelector() as events:
                events.register(subscriber.stdout, selectors.EVENT_READ)
                pending = b''
                while not stopped:
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
            glass.hide(animate=False)
            terminate(subscriber)
            subscriber.stdout.close()
            subscriber = None
            delay = .5 if time.monotonic() - started > 10 else min(delay * 2, 5)
            deadline = time.monotonic() + delay
            while not stopped and time.monotonic() < deadline:
                time.sleep(.1)
    finally:
        glass.hide(animate=False)
        terminate(subscriber)
        lock.close()


if __name__ == '__main__':
    main()
