"""Palette publication across core frames and the optional browser gallery."""
import json
import os
import re
import shutil
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFilter

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
        self.shell.write_text("wc_bg='102030'\nwc_fg='E0D0C0'\nwc_15='E0D0C0'\nwc_1='AA5577'\n")
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
        self.assertIn('width="1024"', vignette)
        self.assertIn('height="784"', vignette)
        self.assertIn('fill-opacity="0.50"', vignette)
        self.assertNotIn('fill="#e0d0c0"', vignette)
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

    def test_notification_glass_is_enclosed_and_tracks_palette(self):
        self.publish(False)
        source = ROOT / surfaces.NOTIFICATION_FRAME
        first = (self.frames / source.name).read_bytes()
        center = tuple(dimension // 2 for dimension in surfaces.NOTIFICATION_SIZE)
        with Image.open(self.frames / source.name) as frame, Image.open(self.frames / 'notification-glass.png') as glass:
            self.assertEqual(frame.size, surfaces.NOTIFICATION_SIZE)
            self.assertEqual(glass.size, frame.size)
            self.assertEqual(glass.getpixel(center), (10, 21, 31, 128))
            self.assertEqual(glass.getpixel((0, 0))[3], 0)
            alpha = frame.getchannel('A')
            self.assertGreater(alpha.getextrema()[1], 0)
            self.assertEqual(alpha.getpixel(center), 0)
            with Image.open(self.frames / 'notification-aperture.png') as mask:
                self.assertEqual(mask.size, frame.size)
                self.assertEqual(mask.getpixel(center)[3], 255)
                self.assertEqual(mask.getpixel((0, 0))[3], 0)
                self.assertEqual(mask.getchannel('A'), surfaces.frame_aperture(frame))
        self.shell.write_text("wc_bg='304050'\nwc_fg='FFEEDD'\nwc_15='FFEEDD'\nwc_1='55BB99'\n")
        self.publish(False)
        self.assertNotEqual(first, (self.frames / source.name).read_bytes())
        with Image.open(self.frames / 'notification-glass.png') as glass:
            self.assertEqual(glass.getpixel(center), (31, 42, 52, 128))

    def test_open_frame_never_paints_glass_outside_the_sculpture(self):
        frame = Image.new('RGBA', (40, 40))
        draw = ImageDraw.Draw(frame)
        draw.rectangle((5, 5, 34, 34), outline=(255, 255, 255, 255), width=2)
        self.assertIsNotNone(surfaces.frame_aperture(frame).getbbox())
        draw.rectangle((18, 0, 22, 10), fill=(0, 0, 0, 0))
        self.assertIsNone(surfaces.frame_aperture(frame).getbbox())

    def test_notification_controls_clear_artwork_by_sixteen_pixels(self):
        self.publish(False)
        config = json.loads((ROOT / 'swaync/config.json').read_text())
        css = (ROOT / 'swaync/style.css').read_text()
        panel = re.search(r'\.control-center\s*\{([^}]+)', css)[1]
        top, right, bottom, left = map(int, re.search(
            r'padding: (\d+)px (\d+)px (\d+)px (\d+)px;', panel).groups())
        width, height = surfaces.NOTIFICATION_SIZE
        self.assertEqual(config['control-center-width'] + left + right, width)
        self.assertEqual(config['control-center-height'], height)
        with Image.open(self.frames / 'notification-aperture.png') as mask:
            safe = mask.getchannel('A').point(lambda value: 255 if value >= 248 else 0)
            safe = safe.filter(ImageFilter.MinFilter(33))
            self.assertEqual(safe.crop((left, top, width-right, height-bottom)).getextrema(), (255, 255))

    def test_refresh_frames_republishes_dark_glass_vignette(self):
        self.publish(False)
        vignette = self.frames / 'launcher-vignette.svg'
        vignette.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>')
        # Copy the angel PNGs so refresh_frames can filter them under a temp ROOT.
        asset_root = self.root / 'checkout'
        for relative in (surfaces.SELECTOR_FRAME, surfaces.NOTIFICATION_FRAME, surfaces.MUSIC_FRAME):
            destination = asset_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        for name in surfaces.ASSETS:
            destination = asset_root / 'wallust/assets' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'wallust/assets' / name, destination)
        data_home = self.root / 'xdg-data'
        state_home = self.root / 'xdg-state'
        (state_home / 'voluta').mkdir(parents=True)
        (state_home / 'voluta/install.json').write_text(
            json.dumps({'files': {}, 'links': {}, 'version': 1}))
        with patch.dict(os.environ, {
            'XDG_CONFIG_HOME': str(self.config),
            'XDG_DATA_HOME': str(data_home),
            'XDG_STATE_HOME': str(state_home),
        }), patch.object(surfaces, 'ROOT', asset_root):
            surfaces.refresh_frames()
        text = vignette.read_text()
        self.assertIn('fill-opacity="0.50"', text)
        self.assertIn('fill="#0a151f"', text)

    def test_music_frame_is_enclosed_and_scaled_for_1080p(self):
        self.publish(False)
        with Image.open(self.frames / surfaces.MUSIC_FRAME.name) as frame, \
             Image.open(self.frames / 'music-aperture.png') as mask, \
             Image.open(self.frames / 'music-glass.png') as glass:
            self.assertEqual(frame.size, surfaces.MUSIC_SIZE)
            self.assertEqual(mask.size, frame.size)
            self.assertEqual(glass.size, frame.size)
            self.assertEqual(glass.getpixel((0, 0))[3], 0)
            opening = surfaces.frame_aperture(frame)
            self.assertIsNotNone(opening.getbbox())
            center = ((opening.getbbox()[0] + opening.getbbox()[2]) // 2,
                      (opening.getbbox()[1] + opening.getbbox()[3]) // 2)
            self.assertEqual(glass.getpixel(center)[3], 128)
            content = json.loads((self.frames / 'music-content.json').read_text())
            box = opening.getbbox()
            self.assertGreaterEqual(content['left'], box[0])
            self.assertGreaterEqual(content['top'], box[1])
            self.assertLessEqual(content['left'] + content['width'], box[2])
            self.assertLessEqual(content['top'] + content['height'], box[3])


if __name__ == '__main__':
    unittest.main()
