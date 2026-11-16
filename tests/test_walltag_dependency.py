"""Walltag pacman repo registration and install mode."""
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'voluta'))
import deploy


class WalltagDependencyTests(unittest.TestCase):
    def test_walltag_is_not_a_base_package(self):
        # Installed by ensure_walltag() from deps/walltag.conf, not BASE_PACKAGES.
        self.assertNotIn('walltag', deploy.package_list({'features': {}}))

    def test_walltag_binary_prefers_pacman_package(self):
        with patch.object(deploy, 'package_installed', side_effect=lambda name: name == 'walltag'), \
             patch.object(deploy.os, 'access', return_value=True), \
             patch('pathlib.Path.is_file', return_value=True):
            self.assertEqual(deploy.walltag_binary(), '/usr/bin/walltag')

    def test_ensure_walltag_pacman_repo_installs_conf(self):
        calls = []

        def visible(command):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, '', '')

        with patch.object(deploy, 'walltag_pacman_repo_ready', side_effect=[False, True]), \
             patch.object(deploy.os, 'geteuid', return_value=1000), \
             patch.object(deploy, '_run_visible', side_effect=visible):
            deploy.ensure_walltag_pacman_repo()
        self.assertEqual(
            calls[0],
            ['sudo', 'install', '-Dm644', str(deploy.ROOT / 'deps/walltag.conf'), '/etc/pacman.d/walltag'],
        )
        self.assertEqual(calls[1][0:2], ['sudo', 'sh'])

    def test_ensure_walltag_pacman_repo_skips_include_when_ready(self):
        calls = []

        def visible(command):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, '', '')

        with patch.object(deploy, 'walltag_pacman_repo_ready', return_value=True), \
             patch.object(deploy.os, 'geteuid', return_value=0), \
             patch.object(deploy, '_run_visible', side_effect=visible):
            deploy.ensure_walltag_pacman_repo()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], 'install')

    def test_ensure_walltag_uses_pacman_by_default(self):
        with patch.object(deploy, 'walltag_install_mode', return_value='pacman'), \
             patch.object(deploy.shutil, 'which', return_value='/usr/bin/pacman'), \
             patch.object(deploy, '_install_walltag_package', return_value='/usr/bin/walltag') as install, \
             patch.object(deploy, '_ensure_walltag_cargo') as cargo:
            self.assertEqual(deploy.ensure_walltag(), '/usr/bin/walltag')
            install.assert_called_once_with()
            cargo.assert_not_called()

    def test_ensure_walltag_src_mode_uses_cargo(self):
        with patch.object(deploy, 'walltag_install_mode', return_value='src'), \
             patch.object(deploy, 'walltag_binary', return_value=None), \
             patch.object(deploy, '_ensure_walltag_cargo', return_value='/home/u/.cargo/bin/walltag') as cargo, \
             patch.object(deploy, '_install_walltag_package') as install:
            self.assertEqual(deploy.ensure_walltag(), '/home/u/.cargo/bin/walltag')
            cargo.assert_called_once_with(force=True)
            install.assert_not_called()


if __name__ == '__main__':
    unittest.main()
