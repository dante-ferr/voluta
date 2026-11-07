"""Check runtime Wallust compatibility independently of package ownership."""
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'voluta'))
import deploy


class WallustDependencyTests(unittest.TestCase):
    def test_cargo_v4_preferred_over_system_v3(self):
        def version(command, **kwargs):
            value = 'wallust 4.0.0-alpha' if command[0] != '/usr/bin/wallust' else 'wallust 3.4.0'
            return subprocess.CompletedProcess(command, 0, value, '')
        with patch.dict(deploy.os.environ, {'CARGO_HOME': '/custom/cargo'}), \
             patch.object(deploy.shutil, 'which', return_value='/usr/bin/wallust'), \
             patch.object(deploy.os, 'access', return_value=True), \
             patch.object(deploy.subprocess, 'run', side_effect=version):
            self.assertEqual(deploy.wallust_binary(), '/custom/cargo/bin/wallust')

    def test_v3_does_not_satisfy_runtime_requirement(self):
        with patch.object(deploy.os, 'access', return_value=True), \
             patch.object(deploy.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'wallust 3.5.2', '')):
            self.assertIsNone(deploy.wallust_binary())

    def test_v4_avoids_conflicting_package_install(self):
        with patch.object(deploy, 'package_list', return_value=['wallust-git', 'obs-cmd']), \
             patch.object(deploy, 'wallust_binary', return_value='/custom/cargo/bin/wallust'), \
             patch.object(deploy.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertEqual(deploy.missing_packages({}), [])
            self.assertEqual(run.call_args.args[0], ['pacman', '-T', 'obs-cmd'])

    def test_package_name_alone_does_not_satisfy_v4(self):
        with patch.object(deploy, 'package_list', return_value=['wallust-git']), \
             patch.object(deploy, 'wallust_binary', return_value=None):
            self.assertEqual(deploy.missing_packages({}), ['wallust-git'])
