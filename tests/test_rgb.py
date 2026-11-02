import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'voluta'))
import rgb


class RGBTests(unittest.TestCase):
    def test_mars_transaction_has_static_payload_and_commit(self):
        packets = rgb.mars_reports('123456')
        self.assertEqual(len(packets), 16)
        self.assertTrue(all(len(p) == 64 for p in packets))
        self.assertEqual(packets[0][0:2], b'\x04\x0a')
        self.assertEqual(packets[0][8], 15)
        self.assertEqual(packets[3][:4], bytes.fromhex('04123456'))
        self.assertEqual(packets[-1][:2], b'\x04\x05')
        self.assertEqual(packets[-1][-2:], b'\xaa\x55')

    def test_exact_device_gate_cache_and_dry_run(self):
        settings = {'features': {'rgb': True}, 'rgb': {'devices': [{'backend':'openrgb','usb_id':'04d9:fc30','name':'Redragon M711 Cobra'}]}}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'XDG_STATE_HOME':directory}), \
             patch.object(rgb, 'resolve', return_value=(settings, True)), patch.object(rgb, 'palette_color', return_value='123456'), \
             patch.object(rgb, 'present', return_value=['usb-path:1']), patch.object(rgb.shutil, 'which', return_value='/usr/bin/openrgb'), \
             patch.object(rgb.subprocess, 'run') as run:
            self.assertEqual(rgb.apply(Path(directory),'test',True)[0]['status'], 'would-apply')
            run.assert_not_called()
            self.assertEqual(rgb.apply(Path(directory),'test')[0]['status'], 'applied')
            self.assertEqual(rgb.apply(Path(directory),'test')[0]['status'], 'unchanged')
            self.assertEqual(run.call_count, 1)
            with patch.object(rgb, 'present', return_value=[]):
                self.assertEqual(rgb.apply(Path(directory),'test')[0]['status'], 'absent')
            self.assertEqual(run.call_count, 1)

    def test_mars_requires_explicit_experimental_selection(self):
        settings = {'features': {'rgb': True}, 'rgb': {'devices':[{'backend':'hyperx-mars','usb_id':'0951:16c6'}]}}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'XDG_STATE_HOME':directory}), \
             patch.object(rgb, 'resolve', return_value=(settings,True)), patch.object(rgb, 'palette_color', return_value='123456'), \
             patch.object(rgb, 'present', return_value=['usb-path:1']), patch.object(rgb, 'mars_apply') as apply:
            with self.assertRaises(ValueError):
                rgb.apply(Path(directory),'test')
            apply.assert_not_called()


    def test_custom_profile_covers_only_real_keys_and_preserves_prefixes(self):
        palette = {f'wc_{i}': f'{i * 11:02x}{255 - i * 9:02x}{i * 7:02x}' for i in range(16)}
        packets = rgb.mars_custom_reports(palette)
        self.assertEqual(len(packets), 20)
        self.assertTrue(all(len(p) == 64 for p in packets))
        self.assertEqual(packets[1][:4], bytes.fromhex('c759656c'))
        self.assertEqual(packets[3][8], 15)
        self.assertEqual(packets[18][:2], bytes.fromhex('8005'))
        self.assertEqual(packets[18][-2:], bytes.fromhex('aa55'))
        template = json.loads((ROOT / 'voluta/mars-keymap.json').read_text())
        data = json.loads((ROOT / 'voluta/mars-custom.json').read_text())
        keys = {key['index']: key['label'] for key in data['keys']}
        self.assertEqual(len(keys), 119)
        def key_color(index):
            offset = index % 16 * 4
            return packets[9 + index // 16][offset + 1:offset + 4]
        for index in range(144):
            self.assertEqual(packets[9 + index // 16][index % 16 * 4], template[index // 16][index % 16 * 4])
            self.assertEqual(key_color(index) != bytes(3), index in keys)
        self.assertEqual(key_color(39), bytes.fromhex(palette['wc_10']))  # W
        self.assertEqual(key_color(92), bytes.fromhex(palette['wc_13']))  # Super
        self.assertEqual(key_color(101), bytes.fromhex(palette['wc_14']))  # Up
        self.assertNotEqual(key_color(129), key_color(143))
        with self.assertRaises(ValueError):
            rgb.mars_custom_reports({'wc_1': '123456'})

    def test_custom_cache_tracks_colors_beyond_the_accent(self):
        settings = {'features': {'rgb': True}, 'rgb': {'devices': [
            {'backend': 'hyperx-mars', 'usb_id': '0951:16c6', 'experimental': True, 'layout': 'voluta'}]}}
        palette = {f'wc_{i}': f'{i * 13:06x}' for i in range(16)}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'XDG_STATE_HOME': directory}), \
             patch.object(rgb, 'resolve', return_value=(settings, True)), \
             patch.object(rgb, 'palette_color', return_value=palette['wc_1']), \
             patch.object(rgb, 'palette_colors', return_value=palette), \
             patch.object(rgb, 'present', return_value=['usb-path:1']), patch.object(rgb, 'mars_apply') as send:
            self.assertEqual(rgb.apply(Path(directory), 'test')[0]['status'], 'applied')
            self.assertEqual(rgb.apply(Path(directory), 'test')[0]['status'], 'unchanged')
            palette['wc_14'] = 'abcdef'
            self.assertEqual(rgb.apply(Path(directory), 'test')[0]['status'], 'applied')
            self.assertEqual(send.call_count, 2)

    def test_notebook_disabled_never_reads_palette_or_touches_devices(self):
        with patch.object(rgb, 'resolve', return_value=({'features': {'rgb': False}}, True)), \
             patch.object(rgb, 'palette_color') as palette, patch.object(rgb, 'present') as devices:
            self.assertEqual(rgb.apply(Path('/unused'), 'frank-notebook'), [])
            palette.assert_not_called()
            devices.assert_not_called()

    def test_watcher_reacts_to_palette_change_without_login(self):
        import runtime
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            socket = root / 'hypr/test/.socket2.sock'
            socket.parent.mkdir(parents=True)
            socket.touch()
            palette = root / 'hypr/wallust/colors-shell.sh'
            palette.parent.mkdir(parents=True)
            palette.write_text("wc_1='123456'\n")
            seen = []
            def tick(_):
                if len(seen) == 1:
                    palette.write_text("wc_1='abcdef'\n")
                    # Explicit distinct mtime, also on filesystems with coarse clocks.
                    os.utime(palette, ns=(1_000_000, 2_000_000))
                else:
                    socket.unlink()
            settings = {'features': {'sddm': False, 'browser': False}}
            with patch.dict(os.environ, {'XDG_RUNTIME_DIR': directory, 'HYPRLAND_INSTANCE_SIGNATURE': 'test', 'XDG_CONFIG_HOME': directory}), \
                 patch.object(runtime, 'resolve', return_value=(settings, True)), \
                 patch.object(runtime.time, 'sleep', side_effect=tick), \
                 patch.object(rgb, 'apply', side_effect=lambda *args: seen.append(palette.read_text())):
                runtime.watch()
            self.assertEqual(seen, ["wc_1='123456'\n", "wc_1='abcdef'\n"])


if __name__ == '__main__':
    unittest.main()
