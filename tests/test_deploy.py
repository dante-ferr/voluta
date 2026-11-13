"""Installer acceptance tests in disposable homes, also run inside the Arch guest."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

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

    def test_cursor_defaults_and_companion_override(self):
        self.run_cli('init')
        self.assertEqual(json.loads(self.run_cli('get', 'environment.XCURSOR_THEME').stdout),
                         'capitaine-cursors')
        gtk = self.home / '.config/gtk-3.0/settings.ini'
        gtk.parent.mkdir(parents=True)
        gtk.write_text('[Settings]\ngtk-font-name=Serif 11\n')
        settings_path = self.home / '.config/voluta/settings.json'
        settings = json.loads(settings_path.read_text())
        settings['environment'] = {'XCURSOR_THEME': 'Adwaita', 'XCURSOR_SIZE': '32'}
        settings_path.write_text(json.dumps(settings))
        before = settings_path.read_bytes()
        self.run_cli('install', '--skip-deps')
        import configparser
        for version in ('gtk-3.0', 'gtk-4.0'):
            parser = configparser.ConfigParser()
            parser.read(self.home / '.config' / version / 'settings.ini')
            self.assertEqual(parser['Settings']['gtk-cursor-theme-name'], 'Adwaita')
            self.assertEqual(parser['Settings']['gtk-cursor-theme-size'], '32')
            if version == 'gtk-3.0':
                self.assertEqual(parser['Settings']['gtk-font-name'], 'Serif 11')
        login = (self.home / '.config/voluta-login-env.sh').read_text()
        self.assertIn('export XCURSOR_THEME=Adwaita', login)
        self.assertIn('export XCURSOR_SIZE=32', login)
        self.run_cli('update', '--skip-deps')
        self.assertEqual(settings_path.read_bytes(), before)

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
        service = self.home / '.config/systemd/user/swaync.service.d/10-voluta.conf'
        self.assertIn('ExecStart=\nExecStart=/bin/sh ', service.read_text())
        self.assertIn('/swaync/launch.sh', service.read_text())
        for consumer in ('rofi', 'swaync', 'music', 'session-menu'):
            for module in ('MenuGlass.qml', 'StainedGlass.qml', 'RimIgnition.qml'):
                effect = self.home / '.config' / consumer / 'effects' / module
                self.assertTrue(effect.is_file(), f'{consumer} can resolve {module}')
                self.assertEqual(effect.resolve(), self.home / '.local/share/voluta/current/wallust/effects' / module)
        self.assertFalse((self.home / '.local/bin/dolphin').exists())
        for name in ('music', 'session-menu'):
            deployed = self.home / '.config' / name
            self.assertTrue(deployed.is_symlink(), name)
            self.assertTrue((deployed / 'toggle.sh').is_file(), name)
        self.assertIn('SUPER + ALT + R', (original / 'UserConfigs/UserKeybinds.lua').read_text())
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

    def test_installed_command_follows_the_recorded_checkout(self):
        self.run_cli('init')
        self.run_cli('install', '--skip-deps')
        fake = self.home / 'fake-checkout'
        (fake / 'voluta').mkdir(parents=True)
        (fake / 'voluta/cli.py').write_text('print("from-checkout")\n')
        manifest_path = self.home / '.local/state/voluta/install.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['source'] = str(fake)
        manifest_path.write_text(json.dumps(manifest))
        installed = self.home / '.local/share/voluta/current/voluta/cli.py'
        for command in ([str(self.home / '.local/bin/voluta')],
                        ['/usr/bin/python3', str(installed)]):
            result = subprocess.run(command, env=self.env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'from-checkout')
            self.assertNotIn('stale', result.stdout)

    def test_dependency_failure_still_deploys_configuration(self):
        self.run_cli('init')
        sys.path.insert(0, str(ROOT / 'voluta'))
        import deploy
        env = {**self.env, 'HYPRLAND_INSTANCE_SIGNATURE': ''}
        with patch.dict(os.environ, env):
            with patch.object(deploy, 'dependencies', side_effect=ValueError('package failed')):
                with self.assertRaises(ValueError) as caught:
                    deploy.install(self.home / '.config/voluta', 'public-test-host')
        self.assertIn('package failed', str(caught.exception))
        keybinds = self.home / '.config/hypr/UserConfigs/UserKeybinds.lua'
        self.assertIn('SUPER + ALT + R', keybinds.read_text())
        self.assertTrue((self.home / '.config/music/salon.qml').is_file())
        self.assertTrue((self.home / '.config/session-menu/panel.qml').is_file())

    def test_refresh_deploys_without_reloading_twice(self):
        script = (ROOT / 'hypr/scripts/Refresh.sh').read_text()
        self.assertIn('VOLUTA_REFRESH_SKIP_SYNC', script)
        self.assertIn('update --skip-deps --no-session-refresh', script)
        self.assertLess(script.index('palette_before'), script.index('update --skip-deps --no-session-refresh'))
        self.assertLess(script.index('update --skip-deps --no-session-refresh'), script.index('hyprctl reload'))
        self.assertIn('paint_dolphin_theme.sh', script)
        self.assertIn('dolphin/apply.sh', script)
        self.assertIn('--refresh-frames', script)
        self.assertIn('StartTopGlow.sh', script)
        self.run_cli('init')
        help_text = self.run_cli('update', '-h').stdout
        self.assertIn('--no-session-refresh', help_text)

    def test_update_skips_unchanged_checkout_and_restores_missing_files(self):
        self.run_cli('init')
        self.run_cli('install', '--skip-deps')
        manifest_path = self.home / '.local/state/voluta/install.json'
        manifest = json.loads(manifest_path.read_text())
        self.assertTrue(manifest.get('source_stamp'))
        target = self.home / '.local/share/voluta/current/hypr/hyprland.lua'
        mtime = target.stat().st_mtime_ns
        self.run_cli('update', '--skip-deps')
        self.assertEqual(target.stat().st_mtime_ns, mtime)
        target.unlink()
        self.run_cli('update', '--skip-deps')
        self.assertTrue(target.is_file())
        self.assertGreater(target.stat().st_size, 0)

    def test_unchanged_palette_inputs_skip_theme_republish(self):
        self.run_cli('init')
        self.run_cli('install', '--skip-deps')
        palette = self.home / '.config/hypr/wallust/colors-shell.sh'
        palette.parent.mkdir(parents=True, exist_ok=True)
        palette.write_text("wc_bg='102030'\nwc_fg='E0D0C0'\nwc_15='E0D0C0'\nwc_1='AA5577'\n")
        sys.path.insert(0, str(ROOT / 'voluta'))
        import deploy
        import theme
        config = self.home / '.config'
        directory = config / 'voluta'
        with patch.dict(os.environ, {**self.env, 'HYPRLAND_INSTANCE_SIGNATURE': ''}):
            settings, _ = deploy.resolve(directory, 'public-test-host')
            stamp = deploy.publish_stamp(config, ROOT, settings['appearance']['background'])
            manifest_path = self.home / '.local/state/voluta/install.json'
            manifest = json.loads(manifest_path.read_text())
            manifest['publish_stamp'] = stamp
            manifest_path.write_text(json.dumps(manifest))
            with patch.object(theme, 'publish') as publish:
                deploy.install(directory, 'public-test-host', skip_deps=True, no_session_refresh=True)
            publish.assert_not_called()
            manifest['publish_stamp'] = 'stale'
            manifest_path.write_text(json.dumps(manifest))
            with patch.object(theme, 'publish') as publish:
                deploy.install(directory, 'public-test-host', skip_deps=True, no_session_refresh=True)
            publish.assert_called_once()

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
        palette.write_text("wc_bg='102030'\nwc_fg='E0D0C0'\nwc_15='E0D0C0'\nwc_1='AA5577'\n")
        self.run_cli('feature', 'enable', 'browser')
        gallery = self.home / '.local/share/voluta/gallery'
        self.assertTrue((gallery / 'manifest.json').exists())
        self.assertTrue((gallery / 'generated/palette.json').exists())
        # Wallpaper refreshes invoke the deployed publisher, so its runtime
        # sources must be available independently of the original checkout.
        current = self.home / '.local/share/voluta/current'
        result = subprocess.run(['python3', str(current / 'voluta/theme.py')],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        marker = gallery / 'user-marker'
        marker.write_text('preserve')
        self.run_cli('feature', 'disable', 'browser')
        self.run_cli('update', '--skip-deps')
        self.run_cli('feature', 'enable', 'browser')
        self.assertEqual(marker.read_text(), 'preserve')


if __name__ == '__main__':
    unittest.main()
