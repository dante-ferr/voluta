"""Framed menus close every other open framed menu before opening."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ExclusiveFramedTests(unittest.TestCase):
    def test_keep_argument_closes_only_the_other_open_menus(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            runtime = directory / 'runtime'
            runtime.mkdir()
            (runtime / 'voluta-notification.open').write_text('1\n')
            (runtime / 'voluta-selector.open').write_text('1\n')
            log = directory / 'calls'
            for tool, body in {
                'gdbus': 'printf "%s\\n" "$*" >> "$TOGGLE_LOG"\n',
                'swaync-client': 'printf "swaync %s\\n" "$*" >> "$TOGGLE_LOG"\n',
                'pkill': 'printf "pkill %s\\n" "$*" >> "$TOGGLE_LOG"\n',
                'quickshell': 'printf "quickshell %s\\n" "$*" >> "$TOGGLE_LOG"\n'
                              'if printf "%s" "$*" | grep -q "list"; then echo "[]"; fi\n',
                'jq': 'exit 0\n',
                'timeout': 'shift; exec "$@"\n',
            }.items():
                path = directory / tool
                path.write_text('#!/bin/sh\n' + body)
                path.chmod(0o755)
            env = {**os.environ, 'PATH': f'{directory}:/usr/bin:/bin', 'TOGGLE_LOG': str(log),
                   'XDG_CONFIG_HOME': str(directory / 'config'),
                   'XDG_RUNTIME_DIR': str(runtime)}
            (directory / 'config/music').mkdir(parents=True)
            (directory / 'config/music/salon.qml').write_text('// salon\n')
            script = ['/bin/sh', str(ROOT / 'hypr/scripts/exclusive-framed.sh')]
            subprocess.run(script + ['music'], env=env, check=True)
            calls = log.read_text()
            self.assertIn('SetVisibility false', calls)
            self.assertIn('pkill -x rofi', calls)
            self.assertNotIn('call music dismiss', calls)
            log.unlink()
            subprocess.run(script + ['notification'], env=env, check=True)
            calls = log.read_text()
            self.assertNotIn('SetVisibility', calls)
            self.assertNotIn('swaync', calls)
            self.assertIn('pkill -x rofi', calls)
            log.unlink()
            subprocess.run(script + ['selector'], env=env, check=True)
            calls = log.read_text()
            self.assertIn('SetVisibility false', calls)
            self.assertNotIn('pkill', calls)
            script_text = (ROOT / 'hypr/scripts/exclusive-framed.sh').read_text()
            self.assertIn('call session dismiss', script_text)
            self.assertIn('[ "$keep" = session ]', script_text)

    def test_closed_menus_are_not_queried(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            runtime = directory / 'runtime'
            runtime.mkdir()
            log = directory / 'calls'
            for tool, body in {
                'gdbus': 'printf "%s\\n" "$*" >> "$TOGGLE_LOG"\n',
                'pkill': 'printf "pkill %s\\n" "$*" >> "$TOGGLE_LOG"\n',
                'quickshell': 'printf "quickshell %s\\n" "$*" >> "$TOGGLE_LOG"\n',
            }.items():
                path = directory / tool
                path.write_text('#!/bin/sh\n' + body)
                path.chmod(0o755)
            env = {**os.environ, 'PATH': f'{directory}:/usr/bin:/bin', 'TOGGLE_LOG': str(log),
                   'XDG_RUNTIME_DIR': str(runtime),
                   'XDG_CONFIG_HOME': str(directory / 'config')}
            subprocess.run(['/bin/sh', str(ROOT / 'hypr/scripts/exclusive-framed.sh'), 'music'],
                           env=env, check=True)
            self.assertFalse(log.exists())
