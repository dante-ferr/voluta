"""Installer acceptance tests in disposable homes, also run inside the Arch guest."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='voluta-install-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = {**os.environ, 'HOME': str(self.home),
                    'XDG_CONFIG_HOME': str(self.home / '.config'),
                    'XDG_DATA_HOME': str(self.home / '.local/share'),
                    'XDG_CACHE_HOME': str(self.home / '.cache'),
                    'XDG_STATE_HOME': str(self.home / '.local/state')}

    def run_cli(self, *args, code=0):
        self.env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        result = subprocess.run([str(ROOT / 'bin/voluta'), '--host', 'public-test-host', *args], env=self.env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def test_install_update_features_preserve_preferences_and_restore_originals(self):
        original = self.home / '.config/hypr'
        original.mkdir(parents=True)
        (original / 'owner.txt').write_text('existing user config')
        self.run_cli('init')
        self.run_cli('feature', 'disable', 'dolphin')
        self.run_cli('config', 'set', 'input.kb_layout', '"br"')
        settings_path = self.home / '.config/voluta/settings.json'
        before = settings_path.read_bytes()
        self.run_cli('install', '--skip-deps')
        self.assertTrue(original.is_symlink())
        self.assertTrue((original / 'hyprland.lua').is_file())
        self.assertFalse((self.home / '.local/bin/dolphin').exists())
        self.run_cli('update', '--skip-deps')
        self.assertEqual(settings_path.read_bytes(), before)
        self.run_cli('feature', 'enable', 'dolphin')
        self.assertTrue((self.home / '.local/bin/dolphin').is_symlink())
        self.run_cli('feature', 'disable', 'dolphin')
        self.assertFalse((self.home / '.local/bin/dolphin').exists())
        self.run_cli('feature', 'enable', 'session_restore')
        self.run_cli('feature', 'disable', 'session_restore')
        self.run_cli('uninstall')
        self.assertFalse(original.is_symlink())
        self.assertEqual((original / 'owner.txt').read_text(), 'existing user config')
        self.assertTrue(settings_path.exists())

    def test_application_edits_backed_up_and_waypaper_preferences_survive(self):
        self.run_cli('init')
        self.run_cli('install', '--skip-deps')
        config = self.home / '.config'
        waypaper = config / 'waypaper/config.ini'
        waypaper.write_text(waypaper.read_text().replace('~/Pictures/Wallpapers', '~/custom-pictures'))
        managed = config / 'hypr/UserConfigs/UserSettings.lua'
        managed.write_text('-- local application edit\n')
        self.run_cli('update', '--skip-deps')
        self.assertIn('~/custom-pictures', waypaper.read_text())
        self.assertNotEqual(managed.read_text(), '-- local application edit\n')
        backups = self.home / '.local/state/voluta/backups'
        self.assertTrue(any(p.is_file() and not p.is_symlink() and p.read_bytes() == b'-- local application edit\n' for p in backups.iterdir()))

    def test_installed_cli_updates_the_recorded_checkout(self):
        self.run_cli('init')
        self.run_cli('install', '--skip-deps')
        result = subprocess.run([str(self.home / '.local/bin/voluta'), '--host', 'public-test-host',
                                 'update', '--skip-deps'], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.home / '.local/state/voluta/install.json').read_text())
        self.assertEqual(Path(manifest['source']), ROOT)

    def test_dry_run_changes_nothing(self):
        self.run_cli('init')
        output = json.loads(self.run_cli('install', '--dry-run').stdout)
        self.assertNotIn('openrgb', output['packages'])
        self.assertNotIn('obs-cmd', output['packages'])
        self.assertFalse((self.home / '.local/share/voluta').exists())

    def test_browser_enabled_later_publishes_gallery_without_replacing_user_data(self):
        self.run_cli('init')
        self.run_cli('install', '--skip-deps')
        palette = self.home / '.config/hypr/wallust/colors-shell.sh'
        palette.parent.mkdir(parents=True, exist_ok=True)
        palette.write_text("wc_bg='102030'\nwc_fg='E0D0C0'\nwc_1='AA5577'\n")
        self.run_cli('feature', 'enable', 'browser')
        gallery = self.home / '.local/share/voluta/gallery'
        self.assertTrue((gallery / 'manifest.json').exists())
        self.assertTrue((gallery / 'generated/palette.json').exists())
        marker = gallery / 'user-marker'
        marker.write_text('preserve')
        self.run_cli('feature', 'disable', 'browser')
        self.run_cli('update', '--skip-deps')
        self.run_cli('feature', 'enable', 'browser')
        self.assertEqual(marker.read_text(), 'preserve')


if __name__ == '__main__':
    unittest.main()
