"""Music salon environment, toggle, and shared effect wiring."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import struct
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('music_watch', ROOT / 'music/watch.py')
watch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watch)


class MusicSalonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ('wallust/assets/generated', 'hypr/wallust', 'music'):
            (self.root / directory).mkdir(parents=True)
        (self.root / 'wallust/assets/generated/music-aperture.png').write_bytes(
            b'\x89PNG\r\n\x1a\n' + b'\x00\x00\x00\x0dIHDR' + struct.pack('>II', 624, 1040))
        (self.root / 'wallust/assets/generated/music-content.json').write_text(
            '{"left": 170, "top": 280, "width": 358, "height": 620}\n')
        (self.root / 'wallust/assets/generated/music-frame.png').write_bytes(b'frame')
        (self.root / 'hypr/wallust/colors-shell.sh').write_text(
            "wc_2='112233'\nwc_4='445566'\nwc_fg='aabbcc'\n")
        self.monitors = [{'name': 'DP-2', 'focused': True, 'width': 1920,
                          'height': 1080, 'scale': 1, 'reserved': [0, 34, 0, 0]}]

    def hypr(self, arguments):
        if 'getoption' in arguments:
            return json.dumps({'css': '8 16 16 16'})
        return json.dumps(self.monitors)

    def test_logical_geometry_and_fail_closed(self):
        (self.root / 'wallust/assets/generated/music-edges.json').write_text(
            '{"left": 22, "top": 0, "right": 25, "bottom": 23}\n')
        with patch.object(watch, 'run', side_effect=self.hypr):
            environment = watch.renderer_environment(self.root)
            self.assertEqual(environment['VOLUTA_MUSIC_MONITOR'], 'DP-2')
            self.assertEqual(environment['VOLUTA_MUSIC_COLORS'], '#112233 #445566 #aabbcc')
            self.assertEqual(environment['VOLUTA_MUSIC_WIDTH'], '624')
            self.assertEqual(environment['VOLUTA_MUSIC_HEIGHT'], '1040')
            self.assertEqual(environment['VOLUTA_GRID_TOP'], '42')
            self.assertEqual(environment['VOLUTA_GRID_RIGHT'], '16')
            self.assertEqual(environment['VOLUTA_GRID_BOTTOM'], '16')
            self.assertEqual(environment['VOLUTA_GRID_LEFT'], '16')
            self.assertEqual(environment['VOLUTA_MUSIC_PAD_RIGHT'], '25')
            self.assertEqual(environment['VOLUTA_MUSIC_INSET_WIDTH'], '358')
            self.monitors[0]['scale'] = 2
            self.assertIsNone(watch.renderer_environment(self.root))

    def test_lock_is_scoped_to_compositor_session(self):
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': 'first'}):
            first = watch.lock_path(self.root)
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': 'second'}):
            self.assertNotEqual(first, watch.lock_path(self.root))

    def test_menu_glass_owns_rim_ignition_for_every_consumer(self):
        shared = (ROOT / 'wallust/effects/MenuGlass.qml').read_text()
        self.assertIn('RimIgnition', shared)
        self.assertIn('opacity = 0', (ROOT / 'wallust/effects/RimIgnition.qml').read_text())
        self.assertNotIn('id: ignition', (ROOT / 'rofi/stained-glass.qml').read_text())
        self.assertIn('RimIgnition', (ROOT / 'swaync/glass.qml').read_text() + shared)
        salon = (ROOT / 'music/salon.qml').read_text()
        self.assertIn('Glass.MenuGlass', salon)
        self.assertIn('Glass.CavaBars', salon)
        self.assertIn('voluta-music-glass', salon)
        self.assertIn('itemAxis: "x"', salon)
        self.assertIn('music-glass.png', salon)
        self.assertIn('plateGlass', shared)
        self.assertIn('property int exitTravel: 230', shared)
        self.assertNotIn('PauseAnimation', shared)
        self.assertIn('glass.surfaceMapped', (ROOT / 'swaync/glass.qml').read_text())
        self.assertIn('notification-angels-frame.png', (ROOT / 'swaync/glass.qml').read_text())
        self.assertIn('no_anim = true', (ROOT / 'hypr/UserConfigs/UserAnimations.lua').read_text())
        self.assertNotIn('inertialLift', (ROOT / 'hypr/UserConfigs/UserAnimations.lua').read_text())
        self.assertIn('WlrKeyboardFocus.Exclusive', salon)
        self.assertIn('sequence: "Escape"', salon)
        self.assertIn('Nothing playing', salon)
        self.assertIn('play-pause', salon)
        self.assertIn('function playback', salon)
        self.assertIn('Quickshell.execDetached', salon)
        self.assertIn('Hyprland.focusedMonitor', salon)
        self.assertIn('shownPoster', salon)
        self.assertIn('Image.PreserveAspectFit', salon)

    def test_parse_metadata_pads_short_lines(self):
        parsed = watch.parse_metadata('Playing|file:///tmp/a.jpg|Artist')
        self.assertEqual(parsed['status'], 'Playing')
        self.assertEqual(parsed['artist'], 'Artist')
        self.assertEqual(parsed['title'], '')
        full = watch.parse_metadata(
            'Playing|file:///tmp/a.jpg|Artist|Title|Album|1000000|2000000|0.4|Track|On|brave')
        self.assertEqual(full['title'], 'Title')
        self.assertEqual(full['volume'], '0.4')
        self.assertEqual(full['player'], 'brave')

    def test_snapshot_player_reads_current_mpris_line(self):
        line = 'Playing|file:///tmp/cover.jpg|Brilliant Classics|Mozart: The Vienna Piano Sonatas|\n'
        with patch.object(watch, 'run', return_value=line):
            parsed = watch.snapshot_player()
        self.assertEqual(parsed['title'], 'Mozart: The Vienna Piano Sonatas')
        self.assertEqual(parsed['artist'], 'Brilliant Classics')
        self.assertEqual(parsed['status'], 'Playing')

    def test_cache_art_copies_browser_temp_files(self):
        source = self.root / 'chromium-art'
        source.write_bytes(b'not-a-real-image-but-long-enough-to-keep')
        cached = watch.cache_art('file://' + str(source), self.root / 'cache')
        self.assertTrue(Path(cached).is_file())
        self.assertNotEqual(Path(cached), source)
        self.assertEqual(Path(cached).read_bytes(), source.read_bytes())

    def test_renderer_pid_adopts_a_live_instance(self):
        payload = json.dumps([{'pid': os.getpid(), 'config_path': '/tmp/salon.qml'}])
        with patch.object(watch, 'run', return_value=payload):
            self.assertEqual(watch.renderer_pid(), os.getpid())

    def test_toggle_script_reads_pidfile_without_newline(self):
        script = (ROOT / 'music/toggle.sh').read_text()
        self.assertIn("tr -dc '0-9'", script)
        self.assertIn('readlink -f', script)
        self.assertIn('call music toggle', script)
        self.assertIn('exclusive-framed.sh', script)
        self.assertIn('voluta_menu_open music', script)
        self.assertNotIn('call music status', script)
        self.assertIn('ensure_watcher', script)
        self.assertIn('setsid', script)
        self.assertIn("'--follow', 'metadata'", (ROOT / 'music/watch.py').read_text())
        self.assertNotIn("'-d'", (ROOT / 'music/watch.py').read_text())
        self.assertIn('playback', (ROOT / 'music/watch.py').read_text())
        self.assertIn('function toggle(colors: string, assets: string, version: string)',
                      (ROOT / 'music/salon.qml').read_text())
        self.assertIn('itemAxis', (ROOT / 'wallust/effects/MenuGlass.qml').read_text())

    def test_reconcile_reads_the_open_marker_without_ipc(self):
        with patch.object(watch, 'RUNTIME', self.root):
            salon = watch.Salon()
            self.addCleanup(salon.shutdown)
            salon.process = type('Alive', (), {
                'pid': 7, 'poll': lambda self: None, 'terminate': lambda self: None,
                'kill': lambda self: None, 'wait': lambda self, timeout=None: None})()
            with patch.object(watch, 'run', side_effect=AssertionError('quickshell')):
                salon.reconcile()
            self.assertFalse(salon.active)
            (self.root / 'voluta-music.open').write_text('1\n')
            with patch.object(watch, 'run', side_effect=AssertionError('quickshell')), \
                    patch.object(watch, 'snapshot_player', return_value={'status': 'Stopped'}), \
                    patch.object(salon, 'push_metadata'):
                salon.reconcile()
            self.assertTrue(salon.active)

    def test_publication_follows_recolored_frame_and_palette(self):
        with patch.object(watch, 'CONFIG', self.root), patch.object(watch, 'run', side_effect=self.hypr):
            first = watch.renderer_environment()
            frame = self.root / 'wallust/assets/generated/music-frame.png'
            frame.write_bytes(b'recolored-frame')
            second = watch.renderer_environment()
            self.assertNotEqual(first['VOLUTA_MUSIC_VERSION'], second['VOLUTA_MUSIC_VERSION'])
            (self.root / 'hypr/wallust/colors-shell.sh').write_text(
                "wc_2='aabbcc'\nwc_4='ddeeff'\nwc_fg='001122'\n")
            third = watch.renderer_environment()
        self.assertEqual(third['VOLUTA_MUSIC_COLORS'], '#aabbcc #ddeeff #001122')
        self.assertNotEqual(second['VOLUTA_MUSIC_VERSION'], third['VOLUTA_MUSIC_VERSION'])
        salon = (ROOT / 'music/salon.qml').read_text()
        self.assertIn('function applyPublication', salon)
        self.assertIn('function recolor', salon)
        toggle = salon.split('function toggle', 1)[1].split('function recolor', 1)[0]
        self.assertIn('applyPublication', toggle)
        self.assertLess(toggle.index('applyPublication'), toggle.index('glass.open'))
        script = (ROOT / 'music/toggle.sh').read_text()
        self.assertIn('voluta/menus.py', script)
        self.assertIn('call music toggle', script)

    def test_sync_publication_recolors_without_reopening(self):
        with patch.object(watch, 'RUNTIME', self.root):
            salon = watch.Salon()
        self.addCleanup(salon.shutdown)
        with patch.object(watch, 'CONFIG', self.root), patch.object(watch, 'run', side_effect=self.hypr):
            salon.theme_stamp = watch.renderer_environment()['VOLUTA_MUSIC_VERSION']
            salon.process = type('Alive', (), {
                'pid': 7, 'poll': lambda self: None, 'terminate': lambda self: None,
                'kill': lambda self: None, 'wait': lambda self, timeout=None: None})()
            with patch.object(watch, 'renderer_environment', side_effect=AssertionError('palette reread')):
                salon.sync_publication()
            (self.root / 'wallust/assets/generated/music-frame.png').write_bytes(b'recolored-frame')
            with patch.object(salon, '_send') as send:
                salon.sync_publication()
        self.assertEqual(send.call_args.args[0], 'recolor')
        self.assertEqual(send.call_args.args[1], '#112233 #445566 #aabbcc')

    def test_empty_wayland_display_uses_the_live_socket(self):
        runtime = self.root / 'runtime'
        runtime.mkdir()
        sock = socket.socket(socket.AF_UNIX)
        self.addCleanup(sock.close)
        sock.bind(str(runtime / 'wayland-1'))
        (runtime / 'wayland-1-helper.sock').write_bytes(b'')
        repaired = watch.compositor_environment({
            'WAYLAND_DISPLAY': '', 'XDG_RUNTIME_DIR': str(runtime), 'HOME': str(self.root)})
        self.assertEqual(repaired['WAYLAND_DISPLAY'], 'wayland-1')
        with patch.dict(os.environ, repaired, clear=False), patch.object(watch, 'run', side_effect=self.hypr), \
             patch.object(watch, 'CONFIG', self.root):
            environment = watch.renderer_environment()
        self.assertEqual(environment['WAYLAND_DISPLAY'], 'wayland-1')
