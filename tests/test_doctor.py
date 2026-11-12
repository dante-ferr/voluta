"""Doctor reports theme-only consumers without treating them as hard failures."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'voluta'))
import deploy


class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.config = self.root / 'config'
        self.config.mkdir()

    def test_inactive_with_theme_file_is_advisory(self):
        theme = self.config / 'karere/custom.css'
        theme.parent.mkdir(parents=True)
        theme.write_text('--voluta-canvas: #000;\n')
        with patch.object(deploy, 'package_installed', return_value=False), \
             patch.object(deploy, 'any_binary_present', return_value=False):
            report = deploy.theme_only_consumer_status(deploy.THEME_ONLY_CONSUMERS[1], self.config)
        self.assertEqual(report['status'], 'inactive')
        self.assertTrue(report['theme_present'])
        self.assertFalse(report['app_installed'])
        self.assertIn('karere-custom-css', report['note'])
        self.assertFalse(report['injector_installed'])

    def test_limusic_ready_when_installed_and_themed(self):
        theme = self.config / 'limusic/matugen.css'
        theme.parent.mkdir(parents=True)
        theme.write_text('--background: #000;\n')
        with patch.object(deploy, 'package_installed', side_effect=lambda name: name == 'limusic-bin'), \
             patch.object(deploy, 'any_binary_present', return_value=False):
            report = deploy.theme_only_consumer_status(deploy.THEME_ONLY_CONSUMERS[0], self.config)
        self.assertEqual(report['status'], 'ready')
        self.assertTrue(report['app_installed'])

    def test_karere_without_injector_is_incomplete(self):
        theme = self.config / 'karere/custom.css'
        theme.parent.mkdir(parents=True)
        theme.write_text('--voluta-canvas: #000;\n')
        with patch.object(deploy, 'package_installed', side_effect=lambda name: name == 'karere'), \
             patch.object(deploy, 'any_binary_present', return_value=False):
            report = deploy.theme_only_consumer_status(deploy.THEME_ONLY_CONSUMERS[1], self.config)
        self.assertEqual(report['status'], 'incomplete')
        self.assertTrue(report['app_installed'])
        self.assertFalse(report['injector_installed'])
        self.assertIn('karere-custom-css', report['note'])

    def test_theme_missing_when_app_present(self):
        with patch.object(deploy, 'package_installed', side_effect=lambda name: name == 'limusic-bin'), \
             patch.object(deploy, 'any_binary_present', return_value=False):
            report = deploy.theme_only_consumer_status(deploy.THEME_ONLY_CONSUMERS[0], self.config)
        self.assertEqual(report['status'], 'theme_missing')
        self.assertIn('make theme', report['note'])

    def test_doctor_report_keeps_theme_only_notes_advisory(self):
        with patch.object(deploy, 'missing_packages', return_value=[]), \
             patch.object(deploy, 'quickshell_works', return_value=True), \
             patch.object(deploy, 'wallust_binary', return_value='/usr/bin/wallust'), \
             patch.object(deploy.shutil, 'which', return_value='/usr/bin/pacman'), \
             patch.object(deploy, 'THEME_ONLY_CONSUMERS', (
                 {
                     'name': 'limusic',
                     'theme': 'limusic/matugen.css',
                     'packages': ('limusic-bin',),
                     'binaries': ('limusic-app',),
                     'inactive_note': 'install Limusic yourself',
                     'theme_missing_note': 'missing theme',
                     'ready_note': 'ready',
                 },
             )), \
             patch.object(deploy, 'package_installed', return_value=False), \
             patch.object(deploy, 'any_binary_present', return_value=False):
            (self.config / 'limusic').mkdir()
            (self.config / 'limusic/matugen.css').write_text('x\n')
            report = deploy.doctor_report({'features': {}}, 'frank', config=self.config)
        self.assertEqual(report['missing_packages'], [])
        self.assertEqual(report['theme_only_consumers'][0]['status'], 'inactive')
        self.assertIn('install Limusic yourself', report['notes'])
        self.assertTrue(report['quickshell_ok'])
        self.assertTrue(report['wallust_v4'])

    def test_doctor_reports_missing_selected_packages(self):
        with patch.object(deploy, 'missing_packages', return_value=['waybar']), \
             patch.object(deploy, 'quickshell_works', return_value=True), \
             patch.object(deploy, 'wallust_binary', return_value='/usr/bin/wallust'), \
             patch.object(deploy.shutil, 'which', return_value='/usr/bin/pacman'), \
             patch.object(deploy, 'THEME_ONLY_CONSUMERS', ()):
            report = deploy.doctor_report({'features': {}}, 'frank', config=self.config)
        self.assertEqual(report['missing_packages'], ['waybar'])
        self.assertTrue(any('waybar' in note for note in report['notes']))

    def test_format_doctor_report_is_readable_text(self):
        text = deploy.format_doctor_report({
            'host': 'frank',
            'settings_valid': True,
            'missing_packages': ['gsimplecal'],
            'wallust_v4': True,
            'quickshell_ok': True,
            'kvm': False,
            'theme_only_consumers': [
                {
                    'name': 'limusic',
                    'theme': '/home/dante/.config/limusic/matugen.css',
                    'theme_present': True,
                    'app_installed': True,
                    'status': 'ready',
                    'note': 'ready note',
                },
                {
                    'name': 'karere',
                    'theme': '/home/dante/.config/karere/custom.css',
                    'theme_present': True,
                    'app_installed': False,
                    'status': 'inactive',
                    'note': 'install karere-custom-css yourself',
                    'injector_installed': False,
                    'injector_packages': ['karere-custom-css'],
                },
            ],
            'notes': [
                'Missing selected packages: gsimplecal',
                'install karere-custom-css yourself',
            ],
        })
        self.assertIn('Voluta doctor — host frank', text)
        self.assertIn('packages          FAIL (1 missing)', text)
        self.assertIn('- gsimplecal', text)
        self.assertIn('limusic          ready', text)
        self.assertIn('karere           inactive (optional)', text)
        self.assertIn('note            install karere-custom-css yourself', text)
        self.assertNotIn('{', text)
        self.assertIn('Result: needs attention', text)


if __name__ == '__main__':
    unittest.main()
