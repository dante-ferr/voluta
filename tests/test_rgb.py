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


if __name__ == '__main__':
    unittest.main()
