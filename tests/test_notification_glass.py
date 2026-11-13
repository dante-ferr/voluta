"""Optional renderer geometry and real subscriber/process lifecycle with fake clients."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import struct
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
        (self.root / 'wallust/assets/generated/notification-aperture.png').write_bytes(
            b'\x89PNG\r\n\x1a\n' + b'\x00\x00\x00\x0dIHDR' + struct.pack('>II', 1056, 736))
        (self.root / 'hypr/wallust/colors-shell.sh').write_text("wc_2='112233'\nwc_4='445566'\nwc_fg='aabbcc'\n")
        (self.root / 'swaync/config.json').write_text('{}')
        self.monitors = [{'name': 'test', 'focused': True, 'width': 1920,
                          'height': 1080, 'scale': 1, 'reserved': [0, 32, 0, 0]}]

    def hypr(self, arguments):
        if 'getoption' in arguments:
            return json.dumps({'css': '8 16 16 16'})
        return json.dumps(self.monitors)

    def test_logical_geometry_and_palette_and_fail_closed(self):
        with patch.object(glass, 'run', side_effect=self.hypr):
            environment = glass.renderer_environment(self.root)
            self.assertEqual(environment['VOLUTA_NOTIFICATION_TOP'], '40')
            self.assertEqual(environment['VOLUTA_NOTIFICATION_MARGIN_TOP'], '8')
            self.assertEqual(environment['VOLUTA_GRID_RIGHT'], '16')
            self.assertEqual(environment['VOLUTA_GRID_BOTTOM'], '16')
            self.assertEqual(environment['VOLUTA_NOTIFICATION_COLORS'], '#112233 #445566 #aabbcc')
            self.monitors[0]['scale'] = 2
            self.assertTrue(glass.renderer_environment(self.root) is None)
            self.monitors[0]['scale'] = 1
            self.monitors[0]['transform'] = 1
            self.assertTrue(glass.renderer_environment(self.root) is not None)
            self.assertEqual(environment['VOLUTA_NOTIFICATION_WIDTH'], '1056')
            self.assertEqual(environment['VOLUTA_NOTIFICATION_HEIGHT'], '736')
            (self.root / 'swaync/config.json').write_text('{"control-center-preferred-output":"absent","control-center-margin-top":14}')
            # SwayNC's own margin is not the grid. The top stays reserved plus gaps_out.
            self.assertEqual(glass.renderer_environment(self.root)['VOLUTA_NOTIFICATION_TOP'], '40')
            self.monitors.append(dict(self.monitors[0], name='preferred', description='External display', focused=False))
            (self.root / 'swaync/config.json').write_text('{"control-center-preferred-output":"External display"}')
            self.assertEqual(glass.renderer_environment(self.root)['VOLUTA_NOTIFICATION_MONITOR'], 'preferred')

    def test_unexpected_monitor_json_falls_back_to_native_center(self):
        for unexpected in ({'error': 'not a list'}, ['invalid entry'], [None], None, [dict(self.monitors[0], name=None)]):
            with self.subTest(monitors=unexpected), patch.object(glass, 'run', return_value=json.dumps(unexpected)):
                self.assertTrue(glass.renderer_environment(self.root) is None)

    def test_dead_renderer_is_replaced_and_shown_when_active(self):
        overlay = glass.Glass()
        overlay.environment = {
            'VOLUTA_NOTIFICATION_MONITOR': 'DP-2',
            'VOLUTA_NOTIFICATION_COLORS': '#111111 #222222 #ffffff',
            'VOLUTA_NOTIFICATION_ASSETS': '/tmp',
            'VOLUTA_NOTIFICATION_RESERVED_TOP': '34',
            'VOLUTA_NOTIFICATION_MARGIN_TOP': '8',
            'VOLUTA_NOTIFICATION_WIDTH': '1056',
            'VOLUTA_NOTIFICATION_HEIGHT': '736',
        }
        overlay.active = True
        overlay.fingerprint = ()
        class Dead:
            pid = 1
            def poll(self):
                return 1
        overlay.process = Dead()
        spawned = []

        class Alive:
            pid = 99
            def poll(self):
                return None

        def popen(*_args, **_kwargs):
            spawned.append(True)
            return Alive()

        with patch.object(glass, 'renderer_pid', return_value=None), \
             patch.object(glass, 'renderer_environment', return_value=overlay.environment), \
             patch.object(glass.subprocess, 'Popen', side_effect=popen), \
             patch.object(overlay, '_send') as send:
            overlay.recover()
        self.assertTrue(spawned)
        self.assertEqual(overlay.process.pid, 99)
        send.assert_called()
        self.assertEqual(send.call_args.args[0], 'showPanel')

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
    if 'getoption' in sys.argv:
        print(json.dumps({'css': '8 16 16 16'}))
    else:
        log('monitors')
        print(os.environ['FAKE_MONITORS'])
elif name == 'quickshell':
    if '--version' in sys.argv: sys.exit(0)
    if 'ipc' in sys.argv:
        method = sys.argv[sys.argv.index('notification') + 1]
        args = sys.argv[sys.argv.index('notification') + 2:]
        if method == 'dismiss': time.sleep(.15)
        if method in ('prepare', 'showPanel', 'recolor'): log('palette=' + args[1])
        state_path = root / 'renderer-state'
        previous = json.loads(state_path.read_text()) if state_path.exists() else {'token': -1, 'active': False}
        if int(args[-1]) >= previous['token']:
            previous['token'] = int(args[-1])
            if method == 'showPanel': previous['active'] = True
            elif method == 'dismiss': previous['active'] = False
            state_path.write_text(json.dumps(previous))
        log('ipc=' + method)
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
        await_count('start', 1)  # Renderer is resident before the first open.
        await_count('ipc=prepare', 1)
        duplicate = subprocess.run(['python3', str(ROOT / 'swaync/watch-glass.py')], env=environment, timeout=2)
        self.assertEqual(duplicate.returncode, 0)
        emit(True)
        await_count('ipc=showPanel', 1)
        time.sleep(.65)
        self.assertEqual(lines().count('monitors'), 2)
        # Publication updates the resident frame in place instead of replaying the entrance.
        (self.root / 'hypr/wallust/colors-shell.sh').write_text("wc_2='223344'\nwc_4='556677'\nwc_fg='bbccdd'\n")
        await_count('ipc=recolor', 1)
        self.assertIn('palette=#223344 #556677 #bbccdd', lines())
        emit(False)
        await_count('ipc=dismiss', 1)
        emit(True)
        await_count('ipc=showPanel', 3)
        # A deliberately slow dismiss cannot keep the event reader waiting or
        # finish after a newer show and leave the resident renderer hidden.
        emit(False)
        time.sleep(.05)
        emit(True)
        await_count('ipc=showPanel', 4)
        self.assertTrue(json.loads((self.root / 'renderer-state').read_text())['active'])
        self.assertEqual(lines().count('start'), 1)
        self.assertEqual(lines().count('stop'), 0)
        with state.open('a') as stream:
            stream.write('disconnect\n')
        await_count('ipc=dismiss', 3)
        self.assertFalse(json.loads((self.root / 'renderer-state').read_text())['active'])
        state.write_text(json.dumps({'visible': True}) + '\n')
        await_count('subscribe', 2)
        await_count('ipc=showPanel', 5)
        watcher.terminate()
        watcher.wait(timeout=2)
        await_count('stop', 1)
        self.assertEqual(lines().count('start'), 1)


if __name__ == '__main__':
    unittest.main()
