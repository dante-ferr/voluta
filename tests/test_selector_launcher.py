"""A broken optional renderer must not remove the selector's static artwork."""
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SelectorLauncherTests(unittest.TestCase):
    def test_toggle_uses_rofi_pid_and_ignores_a_reused_pid(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / 'config/rofi'
            config.mkdir(parents=True)
            runtime = root / 'runtime'
            runtime.mkdir()
            (config / 'run-selector.sh').write_text('printf "launched\\n"\n')
            environment = {**os.environ, 'XDG_CONFIG_HOME': str(root / 'config'),
                           'XDG_RUNTIME_DIR': str(runtime)}
            command = ['/bin/sh', str(ROOT / 'rofi/launch-dashboard.sh')]
            # A real executable named rofi lets /proc expose the same comm field.
            fake_rofi = root / 'rofi'
            shutil.copyfile(shutil.which('sleep'), fake_rofi)
            fake_rofi.chmod(0o755)
            for executable, should_close in ((fake_rofi, True), (Path(shutil.which('sleep')), False)):
                process = subprocess.Popen([str(executable), '30'])
                try:
                    (runtime / 'rofi.pid').write_text(str(process.pid))
                    result = subprocess.run(command, env=environment, capture_output=True,
                                            text=True, timeout=3)
                    self.assertEqual(result.returncode, 0)
                    if should_close:
                        process.wait(timeout=3)
                        self.assertEqual(result.stdout, '')
                    else:
                        self.assertIsNone(process.poll())
                        self.assertEqual(result.stdout, 'launched\n')
                finally:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=3)

    def test_resident_renderer_preserves_input_status_and_matching_dismissal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binaries = root / 'bin'
            binaries.mkdir()
            assets = root / 'config/wallust/assets/generated'
            assets.mkdir(parents=True)
            for name in ('selector-aperture.png', 'big-angel-box.png', 'launcher-vignette.svg'):
                (assets / name).touch()
            colors = root / 'config/hypr/wallust/colors-shell.sh'
            colors.parent.mkdir(parents=True)
            colors.write_text("wc_2='112233'\nwc_4='445566'\nwc_fg='aabbcc'\n")
            log = root / 'calls'
            scripts = {
                'quickshell': 'printf "%s\\n" "$*" >> "$SELECTOR_TEST_LOG"\n',
                'hyprctl': 'if [ "${SELECTOR_TEST_REQUIRE_EARLY:-}" = 1 ]; then\n'
                           '  count=0\n'
                           '  while [ ! -e "$SELECTOR_TEST_STARTED" ] && [ "$count" -lt 100 ]; do\n'
                           '    sleep .01; count=$((count + 1))\n'
                           '  done\n'
                           '  [ -e "$SELECTOR_TEST_STARTED" ] || exit 99\n'
                           'fi\necho "[]"\n',
                'jq': 'cat >/dev/null\n'
                      'if [ "$2" = ".[].pid" ]; then\n'
                      '  printf "%s\\n" "$SELECTOR_TEST_RENDERER_PID"\n'
                      'else echo TEST-1; fi\n',
                'rofi': 'printf "rofi-start\\n" >> "$SELECTOR_TEST_LOG"\n'
                        'touch "$SELECTOR_TEST_STARTED"\ncat\nexit 23\n',
            }
            for name, body in scripts.items():
                executable = binaries / name
                executable.write_text('#!/bin/sh\n' + body)
                executable.chmod(0o755)
            environment = {**os.environ, 'PATH': f'{binaries}:/usr/bin:/bin',
                           'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_RUNTIME_DIR': str(root / 'runtime'),
                           'SELECTOR_TEST_LOG': str(log), 'SELECTOR_TEST_STARTED': str(root / 'started'),
                           'SELECTOR_TEST_RENDERER_PID': str(os.getpid())}
            command = ['/bin/sh', str(ROOT / 'rofi/run-selector.sh')]
            warm = subprocess.run(command + ['--prewarm'], env=environment,
                                  capture_output=True, text=True, timeout=5)
            self.assertEqual(warm.returncode, 0)
            self.assertEqual(warm.stdout, '')
            self.assertNotIn('call selector openSelector', log.read_text())
            runtime = root / 'runtime'
            runtime.mkdir(exist_ok=True)
            session = f"{environment.get('HYPRLAND_INSTANCE_SIGNATURE', '')}:{environment.get('WAYLAND_DISPLAY', '')}"
            (runtime / 'voluta-selector.pid').write_text(f'{os.getpid()} {session}\n')
            environment['SELECTOR_TEST_REQUIRE_EARLY'] = '1'
            result = subprocess.run(command + ['-dmenu'], input='First\nSecond\n',
                                    env=environment, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 23)
            self.assertEqual(result.stdout, 'First\nSecond\n')
            # The EXIT handler dispatches dismissal asynchronously.
            for _ in range(100):
                calls = log.read_text().splitlines()
                if any('call selector dismiss' in call for call in calls):
                    break
                time.sleep(.01)
            show = next(call for call in calls if 'call selector openSelector' in call)
            dismiss = next(call for call in calls if 'call selector dismiss' in call)
            self.assertIn('TEST-1 #112233 #445566 #aabbcc', show)
            self.assertIn(f'--pid {os.getpid()} call selector', show)
            self.assertIn(f'--pid {os.getpid()} call selector', dismiss)
            request = dismiss.rsplit(' ', 1)[1]
            self.assertIn(f' {request} ', show)
            self.assertEqual(sum(call.startswith('-n -d -p ') for call in calls), 1)
            # Prewarming checks the loader once; a live renderer must not run
            # another Qt process before the keyboard-owning menu starts.
            self.assertEqual(calls.count('--version'), 1)
            self.assertEqual(calls.count('rofi-start'), 1)
            self.assertTrue((root / 'started').exists())

    def test_prewarm_consolidates_legacy_renderer_instances(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binaries = root / 'bin'
            binaries.mkdir()
            config = root / 'config'
            assets = config / 'wallust/assets/generated'
            assets.mkdir(parents=True)
            for name in ('selector-aperture.png', 'big-angel-box.png', 'launcher-vignette.svg'):
                (assets / name).touch()
            colors = config / 'hypr/wallust/colors-shell.sh'
            colors.parent.mkdir(parents=True)
            colors.write_text("wc_2='112233'\nwc_4='445566'\nwc_fg='aabbcc'\n")
            extra = subprocess.Popen(['sleep', '30'])
            try:
                scripts = {
                    'quickshell': 'printf "%s\\n" "$*" >> "$SELECTOR_TEST_LOG"\n',
                    'hyprctl': 'echo "[]"\n',
                    'jq': 'cat >/dev/null\n'
                          'if [ "$2" = ".[].pid" ]; then\n'
                          ' printf "%s\\n" "$SELECTOR_TEST_PIDS"\n'
                          'else echo TEST-1; fi\n',
                }
                for name, body in scripts.items():
                    executable = binaries / name
                    executable.write_text('#!/bin/sh\n' + body)
                    executable.chmod(0o755)
                log = root / 'calls'
                env = {**os.environ, 'PATH': f'{binaries}:/usr/bin:/bin',
                       'XDG_CONFIG_HOME': str(config), 'XDG_RUNTIME_DIR': str(root / 'runtime'),
                       'SELECTOR_TEST_LOG': str(log),
                       'SELECTOR_TEST_PIDS': f'{extra.pid}\n{os.getpid()}\n{os.getpid()}'}
                result = subprocess.run(['/bin/sh', str(ROOT / 'rofi/run-selector.sh'), '--prewarm'],
                                        env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = log.read_text().splitlines()
                self.assertEqual([call for call in calls if call.startswith('kill ')],
                                 [f'kill --pid {extra.pid}'])
                cached = (root / 'runtime/voluta-selector.pid').read_text()
                self.assertEqual(cached.split()[0], str(os.getpid()))
            finally:
                extra.terminate()
                extra.wait(timeout=3)

    def test_qt_loader_failure_preserves_rofi_frame_and_arguments(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binaries = root / 'bin'
            binaries.mkdir()
            assets = root / 'config/wallust/assets/generated'
            assets.mkdir(parents=True)
            for name in ('selector-aperture.png', 'big-angel-box.png', 'launcher-vignette.svg'):
                (assets / name).touch()
            scripts = {
                'quickshell': 'echo "symbol lookup error: Qt_6_PRIVATE_API" >&2\nexit 127\n',
                'jq': 'exit 99\n',
                'hyprctl': 'echo "should not query the compositor" >&2\nexit 99\n',
                'rofi': 'printf "%s\\n" "$@"\nexit 23\n',
            }
            for name, body in scripts.items():
                executable = binaries / name
                executable.write_text('#!/bin/sh\n' + body)
                executable.chmod(0o755)
            arguments = ['-show', 'drun', '-theme', '/theme with spaces/dashboard.rasi']
            result = subprocess.run(
                ['/bin/sh', str(ROOT / 'rofi/run-selector.sh'), *arguments],
                env={**os.environ, 'PATH': f'{binaries}:/usr/bin:/bin',
                     'XDG_CONFIG_HOME': str(root / 'config')},
                capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(result.returncode, 23)
            self.assertEqual(result.stdout.splitlines(), arguments)
            self.assertIn('using the static selector frame', result.stderr)
            self.assertNotIn('should not query', result.stderr)
