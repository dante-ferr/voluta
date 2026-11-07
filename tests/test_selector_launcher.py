"""A broken optional renderer must not remove the selector's static artwork."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SelectorLauncherTests(unittest.TestCase):
    def test_qt_loader_failure_preserves_rofi_frame_and_arguments(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binaries = root / 'bin'
            binaries.mkdir()
            assets = root / 'config/wallust/assets/generated'
            assets.mkdir(parents=True)
            for name in ('selector-aperture.png', 'big-angel-box.png', 'launcher-vignette.svg'):
                (assets / name).touch()
            scripts = {
                'quickshell': 'echo "symbol lookup error: Qt_6_PRIVATE_API" >&2\nexit 127\n',
                'jq': 'exit 99\n',
                'hyprctl': 'echo "should not query the compositor" >&2\nexit 99\n',
                'rofi': 'printf "%s\\n" "$@"\nexit 23\n',
            }
            for name, body in scripts.items():
                executable = binaries / name
                executable.write_text('#!/bin/sh\n' + body)
                executable.chmod(0o755)
            arguments = ['-show', 'drun', '-theme', '/theme with spaces/dashboard.rasi']
            result = subprocess.run(
                ['/bin/sh', str(ROOT / 'rofi/run-selector.sh'), *arguments],
                env={**os.environ, 'PATH': f'{binaries}:/usr/bin:/bin',
                     'XDG_CONFIG_HOME': str(root / 'config')},
                capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(result.returncode, 23)
            self.assertEqual(result.stdout.splitlines(), arguments)
            self.assertIn('using the static selector frame', result.stderr)
            self.assertNotIn('should not query', result.stderr)
