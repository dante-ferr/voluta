"""Palette publication across core frames and the optional browser gallery."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'voluta'))
import surfaces


class SurfaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'config'
        self.data = self.root / 'data'
        self.settings = self.config / 'voluta/settings.json'
        self.settings.parent.mkdir(parents=True)
        self.shell = self.config / 'hypr/wallust/colors-shell.sh'
        self.shell.parent.mkdir(parents=True)
        self.shell.write_text("wc_bg='102030'\nwc_fg='E0D0C0'\nwc_1='AA5577'\n")
        self.wallpaper = self.root / 'private-name.png'
        self.wallpaper.write_bytes(b'wallpaper-test-fixture')
        self.frames = self.config / 'wallust/assets/generated'
        self.gallery = self.data / 'voluta/gallery'

    def publish(self, enabled=True):
        self.settings.write_text(json.dumps({'version': 1, 'features': {'browser': enabled}}))
        before = self.settings.read_bytes()
        with patch.object(surfaces, 'current_wallpaper', return_value=self.wallpaper) as lookup:
            surfaces.publish(config=self.config, data=self.data, host='test-host')
        self.assertEqual(before, self.settings.read_bytes())
        return lookup

    def test_core_frames_without_browser_activation(self):
        lookup = self.publish(False)
        lookup.assert_not_called()
        self.assertFalse(self.gallery.exists())
        frame = ET.parse(self.frames / 'panel-frame.svg').getroot()
        self.assertEqual((frame.get('width'), frame.get('height')), ('720', '640'))
        angel = ET.parse(self.frames / 'big-angel-box.svg').getroot()
        self.assertEqual((angel.get('width'), angel.get('height')), ('1152', '1024'))
        angel_text = (self.frames / 'big-angel-box.svg').read_text()
        self.assertNotIn('voluta-halo', angel_text)
        self.assertNotIn('#161615', angel_text)
        self.assertIn('#0a151f', angel_text)
        vignette = (self.frames / 'launcher-vignette.svg').read_text()
        self.assertIn('voluta-vignette', vignette)
        self.assertIn('stop-color="#e0d0c0"', vignette)
        self.assertIn('stop-opacity="0.32"', vignette)
        self.assertIn('fill="#0a151f"', vignette)
        for name in self.frames.glob('*.svg'):
            ET.parse(name)
            self.assertNotIn('{{', name.read_text())
        self.assertEqual(ET.parse(self.frames / 'tile-frame-wide.svg').getroot().get('width'), '1086')

    def test_gallery_refresh_preserves_user_data_and_uses_only_local_artwork(self):
        self.publish()
        generated = self.gallery / 'generated'
        self.assertTrue((self.gallery / 'artwork.mjs').is_file())
        packet_path = generated / 'palette.json'
        packet = json.loads(packet_path.read_text())
        self.assertEqual(packet['colors']['bg'], '#172029')
        # Core frames keep the darker chrome background.
        self.assertIn('#0a151f', (self.frames / 'panel-frame.svg').read_text())
        self.assertEqual(packet['colors']['accent'], '#aa5577')
        self.assertNotIn(str(self.root), packet_path.read_text())
        wallpaper = generated / packet['wallpaper']
        self.assertEqual(wallpaper.read_bytes(), self.wallpaper.read_bytes())
        previous = wallpaper.stat().st_mtime_ns
        local = self.gallery / 'user-marker'
        local.write_text('preserve')
        self.publish()
        self.assertEqual(wallpaper.stat().st_mtime_ns, previous)
        self.assertEqual(local.read_text(), 'preserve')
        self.wallpaper.write_bytes(b'new-artwork')
        self.publish()
        self.assertNotEqual(json.loads(packet_path.read_text())['version'], packet['version'])
        self.assertEqual(wallpaper.read_bytes(), b'new-artwork')
        before = packet_path.read_bytes()
        self.publish(False)
        self.assertEqual(packet_path.read_bytes(), before)

    def test_missing_wallpaper_during_switch_does_not_break_core(self):
        self.wallpaper.unlink()
        self.publish()
        self.assertIsNone(json.loads((self.gallery / 'generated/palette.json').read_text())['wallpaper'])
        self.assertTrue((self.frames / 'panel-frame.svg').is_file())


if __name__ == '__main__':
    unittest.main()
