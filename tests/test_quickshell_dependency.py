"""Dependency setup repairs Qt loader failures instead of trusting package ownership."""
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'voluta'))
import deploy


class QuickshellDependencyTests(unittest.TestCase):
    def test_selector_renderer_is_a_core_dependency(self):
        self.assertIn('quickshell', deploy.package_list({'features': {}}))

    def test_binary_must_start(self):
        for result, expected in (
            (subprocess.CompletedProcess([], 0), True),
            (subprocess.CompletedProcess([], 127), False),
            (OSError('loader failure'), False),
            (subprocess.TimeoutExpired('quickshell', 5), False),
        ):
            with self.subTest(result=result), \
                 patch.object(deploy.shutil, 'which', return_value='/usr/bin/quickshell'), \
                 patch.object(deploy.subprocess, 'run') as run:
                if isinstance(result, Exception):
                    run.side_effect = result
                else:
                    run.return_value = result
                self.assertEqual(deploy.quickshell_works(), expected)

    def test_broken_provider_is_missing_even_when_package_is_installed(self):
        with patch.object(deploy, 'package_list', return_value=['quickshell']), \
             patch.object(deploy, 'wallust_binary', return_value=None), \
             patch.object(deploy, 'quickshell_works', return_value=False), \
             patch.object(deploy.subprocess, 'run') as run:
            self.assertEqual(deploy.missing_packages({}), ['quickshell'])
            run.assert_not_called()

    def test_working_provider_is_preserved(self):
        with patch.object(deploy, 'package_list', return_value=['quickshell']), \
             patch.object(deploy, 'wallust_binary', return_value=None), \
             patch.object(deploy, 'quickshell_works', return_value=True):
            self.assertEqual(deploy.missing_packages({}), [])

    def test_repair_reinstalls_official_package_and_checks_result(self):
        for repaired in (True, False):
            with self.subTest(repaired=repaired), \
                 patch.object(deploy, 'missing_packages', return_value=['quickshell']), \
                 patch.object(deploy.shutil, 'which', side_effect=lambda name: '/usr/bin/' + name), \
                 patch.object(deploy.os, 'geteuid', return_value=1000), \
                 patch.object(deploy, 'quickshell_works', return_value=repaired) as check, \
                 patch.object(deploy.subprocess, 'run',
                              return_value=subprocess.CompletedProcess([], 0, '', '')), \
                 patch.object(deploy, '_run_visible',
                              return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
                if repaired:
                    deploy.dependencies({})
                else:
                    with self.assertRaisesRegex(ValueError, 'still cannot start'):
                        deploy.dependencies({})
                self.assertEqual(run.call_args.args[0], ['sudo', 'pacman', '-S', '--noconfirm', 'quickshell'])
                check.assert_called_once()

    def test_conflicting_sibling_does_not_block_other_packages(self):
        outcomes = {
            'capitaine-cursors': subprocess.CompletedProcess([], 0, '', ''),
            'nwg-displays': subprocess.CompletedProcess(
                [], 1, '', 'error: failed to commit transaction (conflicting files)\n'
                           'nwg-displays: /usr/bin/nwg-displays exists in filesystem\n'),
        }

        def visible(command):
            package = command[-1]
            if '--overwrite' in command:
                return subprocess.CompletedProcess(command, 0, '', '')
            return outcomes[package]

        with patch.object(deploy, 'missing_packages', return_value=['capitaine-cursors', 'nwg-displays']), \
             patch.object(deploy.shutil, 'which', side_effect=lambda name: '/usr/bin/' + name), \
             patch.object(deploy.os, 'geteuid', return_value=1000), \
             patch.object(deploy.subprocess, 'run',
                          return_value=subprocess.CompletedProcess([], 0, '', '')), \
             patch.object(deploy, '_run_visible', side_effect=visible) as mocked:
            deploy.dependencies({})
        installs = [call.args[0] for call in mocked.call_args_list]
        self.assertEqual(installs[0], ['sudo', 'pacman', '-S', '--noconfirm', '--needed', 'capitaine-cursors'])
        self.assertEqual(installs[1], ['sudo', 'pacman', '-S', '--noconfirm', '--needed', 'nwg-displays'])
        self.assertEqual(installs[2], ['sudo', 'pacman', '-S', '--noconfirm', '--needed', '--overwrite', '*', 'nwg-displays'])
