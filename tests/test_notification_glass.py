"""Optional renderer geometry and real subscriber/process lifecycle with fake clients."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('notification_glass', ROOT / 'swaync/watch-glass.py')
glass = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(glass)


class NotificationGlassTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ('wallust/assets/generated', 'hypr/wallust', 'swaync'):
            (self.root / directory).mkdir(parents=True)
        (self.root / 'wallust/assets/generated/notification-aperture.png').touch()
        (self.root / 'hypr/wallust/colors-shell.sh').write_text("wc_2='112233'\nwc_4='445566'\nwc_fg='aabbcc'\n")
        (self.root / 'swaync/config.json').write_text('{}')
        self.monitors = [{'name': 'test', 'focused': True, 'width': 1920,
                          'height': 1080, 'scale': 1, 'reserved': [0, 32, 0, 0]}]

    def test_logical_geometry_and_palette_and_fail_closed(self):
        with patch.object(glass, 'run', side_effect=lambda _: json.dumps(self.monitors)):
            environment = glass.renderer_environment(self.root)
            self.assertEqual(environment['VOLUTA_NOTIFICATION_TOP'], '40')
            self.assertEqual(environment['VOLUTA_NOTIFICATION_COLORS'], '#112233 #445566 #aabbcc')
            self.monitors[0]['scale'] = 2
            self.assertTrue(glass.renderer_environment(self.root) is None)
            self.monitors[0]['scale'] = 1
            self.monitors[0]['transform'] = 1
            self.assertTrue(glass.renderer_environment(self.root) is not None)
            (self.root / 'swaync/config.json').write_text('{"control-center-preferred-output":"absent","control-center-margin-top":14}')
            self.assertEqual(glass.renderer_environment(self.root)['VOLUTA_NOTIFICATION_TOP'], '46')
            self.monitors.append(dict(self.monitors[0], name='preferred', description='External display', focused=False))
            (self.root / 'swaync/config.json').write_text('{"control-center-preferred-output":"External display"}')
            self.assertEqual(glass.renderer_environment(self.root)['VOLUTA_NOTIFICATION_MONITOR'], 'preferred')

    def test_unexpected_monitor_json_falls_back_to_native_center(self):
        for unexpected in ({'error': 'not a list'}, ['invalid entry'], [None], None):
            with self.subTest(monitors=unexpected), patch.object(glass, 'run', return_value=json.dumps(unexpected)):
                self.assertTrue(glass.renderer_environment(self.root) is None)

    def test_lock_is_scoped_to_compositor_session(self):
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': 'first/session'}):
            first = glass.lock_path(self.root)
            self.assertEqual(first.parent, self.root)
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': 'second/session'}):
            self.assertNotEqual(first, glass.lock_path(self.root))

    def test_subscription_visibility_singleton_disconnect_and_cleanup(self):
        tools = self.root / 'bin'
        tools.mkdir()
        runtime = self.root / 'runtime'
        runtime.mkdir()
        state = self.root / 'events'
        state.write_text('')
        log = self.root / 'log'
        script = tools / 'fake'
        script.write_text('''#!/usr/bin/env python3
import json, os, pathlib, signal, sys, time
name = pathlib.Path(sys.argv[0]).name
root = pathlib.Path(os.environ['FAKE_ROOT'])
def log(text):
    with (root / 'log').open('a') as stream: stream.write(text + '\\n')
if name == 'hyprctl':
    log('monitors')
    print(os.environ['FAKE_MONITORS'])
elif name == 'quickshell':
    if '--version' in sys.argv: sys.exit(0)
    if 'ipc' in sys.argv:
        try: os.kill(int(sys.argv[sys.argv.index('--pid') + 1]), signal.SIGTERM)
        except ProcessLookupError: pass
        sys.exit(0)
    log('start')
    log('palette=' + os.environ['VOLUTA_NOTIFICATION_COLORS'])
    def stop(*args):
        log('stop')
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    while True: time.sleep(.02)
else:
    log('subscribe')
    with (root / 'events').open() as stream:
        while True:
            line = stream.readline()
            if line.strip() == 'disconnect': sys.exit(0)
            if line: print(line.strip(), flush=True)
            else: time.sleep(.02)
''')
        script.chmod(0o755)
        for name in ('hyprctl', 'quickshell', 'swaync-client'):
            (tools / name).symlink_to(script)
        environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                           XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(self.root),
                           FAKE_ROOT=str(self.root), FAKE_MONITORS=json.dumps(self.monitors))
        watcher = subprocess.Popen(['python3', str(ROOT / 'swaync/watch-glass.py')], env=environment)
        self.addCleanup(lambda: watcher.poll() is None and watcher.kill())

        def lines():
            return log.read_text().splitlines() if log.exists() else []

        def await_count(event, count):
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline:
                if lines().count(event) >= count:
                    return
                time.sleep(.02)
            self.fail(f'{event} count {count} not reached: {lines()}')

        def emit(value):
            with state.open('a') as stream:
                stream.write(json.dumps({'visible': value}) + '\n')

        await_count('subscribe', 1)
        duplicate = subprocess.run(['python3', str(ROOT / 'swaync/watch-glass.py')], env=environment, timeout=2)
        self.assertEqual(duplicate.returncode, 0)
        emit(True)
        await_count('start', 1)
        time.sleep(.65)
        self.assertEqual(lines().count('monitors'), 1)
        # An open control center picks up a wallpaper palette publication
        # without querying monitor IPC on every timer tick.
        (self.root / 'hypr/wallust/colors-shell.sh').write_text("wc_2='223344'\nwc_4='556677'\nwc_fg='bbccdd'\n")
        await_count('start', 2)
        self.assertIn('palette=#223344 #556677 #bbccdd', lines())
        emit(True)
        emit(False)
        await_count('stop', 2)
        emit(True)
        await_count('start', 3)
        with state.open('a') as stream:
            stream.write('disconnect\n')
        await_count('stop', 3)
        # A fresh daemon subscription will replay the current visible state.
        state.write_text(json.dumps({'visible': True}) + '\n')
        await_count('subscribe', 2)
        await_count('start', 4)
        watcher.terminate()
        watcher.wait(timeout=2)
        await_count('stop', 4)
        self.assertEqual(lines().count('start'), 4)


if __name__ == '__main__':
    unittest.main()
