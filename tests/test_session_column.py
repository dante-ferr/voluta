"""Session column geometry, status snapshot, and left-edge wiring."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('session_watch', ROOT / 'session-menu/watch.py')
watch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watch)
STATUS = importlib.util.spec_from_file_location('session_status', ROOT / 'session-menu/status.py')
status = importlib.util.module_from_spec(STATUS)
STATUS.loader.exec_module(status)


class SessionColumnTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ('wallust/assets/generated', 'hypr/wallust'):
            (self.root / directory).mkdir(parents=True)
        (self.root / 'wallust/assets/generated/session-aperture.png').write_bytes(
            b'\x89PNG\r\n\x1a\n' + b'\x00\x00\x00\x0dIHDR' + struct.pack('>II', 624, 1040))
        (self.root / 'wallust/assets/generated/session-frame.png').write_bytes(b'frame')
        (self.root / 'wallust/assets/generated/session-content.json').write_text(
            '{"left": 108, "top": 380, "width": 360, "height": 560}\n')
        (self.root / 'wallust/assets/generated/session-edges.json').write_text(
            '{"left": 30, "top": 2, "right": 20, "bottom": 28}\n')
        (self.root / 'hypr/wallust/colors-shell.sh').write_text(
            "wc_2='112233'\nwc_4='445566'\nwc_fg='aabbcc'\n")
        self.monitors = [{'name': 'DP-2', 'focused': True, 'width': 2560,
                          'height': 1440, 'scale': 1, 'reserved': [0, 34, 0, 0]}]

    def hypr(self, arguments):
        if 'getoption' in arguments:
            return json.dumps({'css': '8 16 16 16'})
        return json.dumps(self.monitors)

    def test_left_inset_and_frame_padding(self):
        with patch.object(watch, 'run', side_effect=self.hypr):
            environment = watch.renderer_environment(self.root)
        self.assertEqual(environment['VOLUTA_GRID_LEFT'], '16')
        self.assertEqual(environment['VOLUTA_GRID_TOP'], '42')
        self.assertEqual(environment['VOLUTA_SESSION_PAD_LEFT'], '30')
        self.assertEqual(environment['VOLUTA_SESSION_INSET_TOP'], '380')
        panel = (ROOT / 'session-menu/panel.qml').read_text()
        self.assertIn('anchors { top: true; bottom: true; left: true; right: true }', panel)
        self.assertIn('z: 2', panel)
        self.assertIn('resolvedPlate', (ROOT / 'wallust/effects/MenuGlass.qml').read_text())
        self.assertNotIn('suppressPlate', (ROOT / 'swaync/glass.qml').read_text())
        self.assertNotIn('suppressPlate', (ROOT / 'wallust/effects/MenuGlass.qml').read_text())
        self.assertNotIn('projectionOpacity', (ROOT / 'swaync/glass.qml').read_text())
        self.assertNotIn('buttons-grid', (ROOT / 'swaync/config.json').read_text())
        self.assertIn('gridLeft - panel.framePadLeft', panel)
        self.assertIn('itemEnterFrom: -(panel.plateWidth + panel.gridLeft)', panel)
        self.assertIn('voluta-session-glass', panel)
        self.assertIn('prepare-shutdown', panel)
        self.assertIn('JetBrainsMono Nerd Font', panel)
        self.assertIn('\\u{F033E}', panel)
        self.assertIn('height: 18', panel)
        self.assertIn('contentHeight', panel)
        self.assertIn('text: "\\u{F0594}"', panel)
        self.assertIn('spacing: Math.max(8, (width - 220) / 4)', panel)

    def test_publication_follows_recolored_frame_and_palette(self):
        with patch.object(watch, 'CONFIG', self.root), patch.object(watch, 'run', side_effect=self.hypr):
            first = watch.renderer_environment()
            (self.root / 'wallust/assets/generated/session-frame.png').write_bytes(b'recolored-frame')
            second = watch.renderer_environment()
            self.assertNotEqual(first['VOLUTA_SESSION_VERSION'], second['VOLUTA_SESSION_VERSION'])
            (self.root / 'hypr/wallust/colors-shell.sh').write_text(
                "wc_2='aabbcc'\nwc_4='ddeeff'\nwc_fg='001122'\n")
            third = watch.renderer_environment()
        self.assertEqual(third['VOLUTA_SESSION_COLORS'], '#aabbcc #ddeeff #001122')
        self.assertNotEqual(second['VOLUTA_SESSION_VERSION'], third['VOLUTA_SESSION_VERSION'])
        panel = (ROOT / 'session-menu/panel.qml').read_text()
        self.assertIn('function applyPublication', panel)
        self.assertIn('function recolor', panel)
        toggle = panel.split('function toggle', 1)[1].split('function recolor', 1)[0]
        self.assertIn('applyPublication', toggle)
        self.assertLess(toggle.index('applyPublication'), toggle.index('glass.open'))
        script = (ROOT / 'session-menu/toggle.sh').read_text()
        self.assertIn('voluta/menus.py', script)
        self.assertIn('call session toggle', script)

    def test_sync_publication_recolors_without_reopening(self):
        column = watch.Session()
        self.addCleanup(column.shutdown)
        with patch.object(watch, 'CONFIG', self.root), patch.object(watch, 'run', side_effect=self.hypr):
            column.theme_stamp = watch.renderer_environment()['VOLUTA_SESSION_VERSION']
            column.process = type('Alive', (), {
                'pid': 7, 'poll': lambda self: None, 'terminate': lambda self: None,
                'kill': lambda self: None, 'wait': lambda self, timeout=None: None})()
            with patch.object(watch, 'renderer_environment', side_effect=AssertionError('palette reread')):
                column.sync_publication()
            (self.root / 'hypr/wallust/colors-shell.sh').write_text(
                "wc_2='aabbcc'\nwc_4='ddeeff'\nwc_fg='001122'\n")
            with patch.object(column, '_send') as send:
                column.sync_publication()
        self.assertEqual(send.call_args.args[0], 'recolor')
        self.assertEqual(send.call_args.args[1], '#aabbcc #ddeeff #001122')

    def test_status_reads_sink_and_monitors(self):
        def fake(arguments, **_kwargs):
            command = arguments[0]
            class Result:
                returncode = 0
                stdout = ''
            result = Result()
            if command == 'wpctl' and 'get-volume' in arguments:
                result.stdout = 'Volume: 0.40 [MUTED]\n'
            elif command == 'wpctl':
                result.stdout = 'node.description = "Desk speakers"\n'
            elif command == 'hyprctl':
                result.stdout = json.dumps([{'name': 'DP-2', 'focused': True}])
            elif command == 'pgrep':
                result.returncode = 1
            return result

        with patch.object(status.subprocess, 'run', side_effect=fake):
            snapshot = status.snapshot()
        self.assertEqual(snapshot['sink'], 'Desk speakers')
        self.assertTrue(snapshot['muted'])
        self.assertEqual(snapshot['volume'], 0.4)
        self.assertFalse(snapshot['night'])
        self.assertEqual(snapshot['monitors'][0]['name'], 'DP-2')
        self.assertIn('uptime', snapshot)
        self.assertIn('battery', snapshot)


if __name__ == '__main__':
    unittest.main()
