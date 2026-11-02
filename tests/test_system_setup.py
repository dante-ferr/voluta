import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SystemSetupTests(unittest.TestCase):
    def test_sddm_staging_palette_and_disable_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            palette = prefix / 'palette.sh'
            palette.write_text("wc_bg='123456'\nwc_fg='abcdef'\nwc_1='778899'\n")
            target = prefix / 'etc/sddm.conf.d/zz-voluta.conf'
            target.parent.mkdir(parents=True)
            target.write_text('[Theme]\nCurrent=old\n')
            command = ['python3', str(ROOT / 'voluta/system_setup.py'), 'sddm', '--root', str(prefix), '--palette', str(palette)]
            subprocess.run(command, check=True, capture_output=True)
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(target.read_text(), '[Theme]\nCurrent=voluta\n')
            config = prefix / 'usr/share/sddm/themes/voluta/theme.conf'
            self.assertTrue(config.is_symlink())
            self.assertIn('bgColor=#123456', config.read_text())
            subprocess.run(command + ['--disable'], check=True, capture_output=True)
            self.assertEqual(target.read_text(), '[Theme]\nCurrent=old\n')

    def test_rgb_rule_has_exact_id_and_removes_cleanly(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix=Path(directory)
            command=['python3', str(ROOT/'voluta/system_setup.py'),'rgb','--root',directory]
            subprocess.run(command,check=True,capture_output=True)
            rule=prefix/'etc/udev/rules.d/70-voluta-hyperx-mars.rules'
            self.assertIn('0951',rule.read_text())
            self.assertIn('16c6',rule.read_text())
            subprocess.run(command+['--disable'],check=True,capture_output=True)
            self.assertFalse(rule.exists())

if __name__ == '__main__':unittest.main()
