"""Panel toggling must bypass the slower client open path when D-Bus is available."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NotificationToggleTests(unittest.TestCase):
    def test_direct_toggle_and_missing_bus_tool_fallback(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            log = directory / 'calls'
            for tool in ('gdbus', 'swaync-client'):
                path = directory / tool
                path.write_text('#!/bin/sh\nprintf "%s\\n" "$0" "$@" >> "$TOGGLE_LOG"\n')
                path.chmod(0o755)
            env = {**os.environ, 'PATH': str(directory), 'TOGGLE_LOG': str(log)}
            command = ['/bin/sh', str(ROOT / 'swaync/toggle-panel.sh')]
            subprocess.run(command, env=env, check=True)
            calls = log.read_text()
            self.assertIn('ToggleVisibility', calls)
            self.assertNotIn('swaync-client', calls)
            log.unlink()
            (directory / 'gdbus').unlink()
            subprocess.run(command, env=env, check=True)
            self.assertEqual(log.read_text().splitlines()[1:], ['-t', '-sw'])
