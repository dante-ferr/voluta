import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'voluta'))
import rgb
import rgb_menu
import rgb_presets as presets
from cli import resolve


def palette():
    return {f'wc_{i}': f'{i * 11 + 10:02x}{240 - i * 9:02x}{i * 7 + 10:02x}' for i in range(16)}


def devices():
    return [{'backend': 'openrgb', 'usb_id': '04d9:fc30', 'name': 'Redragon M711 Cobra'},
            {'backend': 'hyperx-mars', 'usb_id': '0951:16c6', 'experimental': True, 'layout': 'voluta'}]


class PresetTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('lua'), 'Lua is not installed')
    def test_shortcut_is_optional_and_respects_explicit_override(self):
        for enabled, override, expected in ((True, False, True), (False, False, False), (True, True, False)):
            script = '''
local dsp = {}
setmetatable(dsp, {__index=function() return dsp end, __call=function() return {} end})
local bindings = {}
hl = {dsp=dsp, bind=function(chord) bindings[chord]=true end, window_rule=function() end}
package.loaded['configs.Voluta'] = {
    apps={}, keybindings=OVERRIDE,
    enabled=function(name) return name == 'rgb' and ENABLED end
}
dofile(SOURCE)
assert((bindings['SUPER + CTRL + G'] == true) == EXPECTED)
'''.replace('OVERRIDE', '{["SUPER + CTRL + G"]=false}' if override else '{}')
            script = script.replace('ENABLED', str(enabled).lower()).replace('EXPECTED', str(expected).lower())
            script = script.replace('SOURCE', json.dumps(str(ROOT / 'hypr/UserConfigs/UserKeybinds.lua')))
            result = subprocess.run(['lua', '-e', script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_all_presets_have_complete_validated_transactions(self):
        self.assertEqual(len(presets.PRESETS), len(presets.CATALOG))
        data = json.loads((ROOT / 'voluta/mars-custom.json').read_text())
        template = json.loads((ROOT / 'voluta/mars-keymap.json').read_text())
        valid = {k['index'] for k in data['keys']}
        for preset in presets.PRESETS:
            with self.subTest(preset=preset.name):
                packets = presets.reports(preset, palette(), ROOT)
                self.assertEqual(len(packets), 20)
                self.assertTrue(all(len(p) == 64 for p in packets))
                self.assertEqual(packets[1], bytes.fromhex(data['E1_SESSION_BLOCK']))
                self.assertEqual([packets[i][:2] for i in (0, 2, 3, 19)],
                                 [bytes.fromhex(h) for h in ('04ab', '0402', '040a', '0402')])
                self.assertEqual(packets[18][0], preset.engine or 0x80)
                self.assertEqual(packets[18][-2:], bytes.fromhex('aa55'))
                for index in range(144):
                    offset = index % 16 * 4
                    frame = packets[9 + index // 16]
                    self.assertEqual(frame[offset], template[index // 16][offset])
                    if index not in valid:
                        self.assertEqual(frame[offset + 1:offset + 4], bytes(3))
                mouse = presets.mouse_settings(preset, palette())
                self.assertIn(mouse['mode'], ('Static', 'Breathing', 'Wave', 'Rainbow'))
                if mouse['mode'] == 'Rainbow':
                    self.assertIsNone(mouse['color'])
                else:
                    self.assertEqual(len(bytes.fromhex(mouse['color'])), 3)

    def test_native_engine_fields_and_off(self):
        pulse = presets.reports(presets.get('heartbeat'), palette(), ROOT)
        self.assertEqual(pulse[4][60:64], bytes((1, 0, 5, 3)))
        self.assertEqual(pulse[4][1:16], b''.join(presets.token(palette(), i) for i in (1, 5, 4, 6, 3)))
        stack = presets.reports(presets.get('rainfall'), palette(), ROOT)
        self.assertEqual(stack[8][60:64], bytes((3, 1, 5, 2)))
        wave = presets.reports(presets.get('prism'), palette(), ROOT)
        self.assertEqual(wave[7][61:64], bytes((2, 5, 2)))
        off = presets.reports(presets.get('off'), palette(), ROOT)
        self.assertTrue(all(not any(p[o + 1:o + 4]) for p in off[9:18] for o in range(0, 64, 4)))
        self.assertEqual(presets.mouse_settings(presets.get('off'), palette())['color'], '000000')

    def test_wasd_highlight_and_palette_updates(self):
        keys = json.loads((ROOT / 'voluta/mars-custom.json').read_text())['keys']
        colors = presets.static_colors(presets.get('wasd'), palette(), keys)
        for index in (39, 56, 57, 58):
            self.assertEqual(colors[index], presets.token(palette(), 10))
        self.assertNotEqual(colors[38], colors[39])
        updated = palette()
        updated['wc_10'] = 'aabbcc'
        self.assertNotEqual(presets.reports(presets.get('wasd'), palette(), ROOT),
                            presets.reports(presets.get('wasd'), updated, ROOT))
        with self.assertRaises(ValueError):
            presets.custom_frames({0: bytes(3)}, ROOT)
        with self.assertRaises(ValueError):
            presets.get('$(touch /tmp/unsafe)')

    def test_palette_independent_native_effects_do_not_rewrite_profiles(self):
        selected = devices()
        for device in selected:
            device['preset'] = 'orbit'
        settings = {'features': {'rgb': True}, 'rgb': {'devices': selected}}
        colors = palette()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'XDG_STATE_HOME': directory}), \
             patch.object(rgb, 'resolve', return_value=(settings, True)), \
             patch.object(rgb, 'palette_colors', return_value=colors), \
             patch.object(rgb, 'present', return_value=['present']), patch.object(rgb, 'mars_apply') as keyboard, \
             patch.object(rgb.shutil, 'which', return_value='/usr/bin/openrgb'), patch.object(rgb.subprocess, 'run') as mouse:
            rgb.apply(Path(directory), 'desktop')
            colors['wc_1'] = 'aabbcc'
            colors['wc_4'] = 'ccbbaa'
            self.assertTrue(all(d['status'] == 'unchanged' for d in rgb.apply(Path(directory), 'desktop')))
            keyboard.assert_called_once()
            mouse.assert_called_once()
            self.assertNotIn('--color', mouse.call_args.args[0])

    def test_transport_and_keepalive_only_send_expected_reports(self):
        frames = presets.reports(presets.get('heartbeat'), palette(), ROOT)
        device = MagicMock()
        device.send_feature_report.return_value = 65
        device.get_feature_report.side_effect = [bytes((0, 4, c, 0, 1)) for c in (0xab, 2, 10, 2)]
        with patch.object(rgb, 'mars_open', return_value=device), patch.object(rgb.time, 'sleep'):
            rgb.mars_apply('123456', frames)
        self.assertEqual([call.args[0] for call in device.send_feature_report.call_args_list],
                         [b'\0' + p for p in frames])
        device.close.assert_called_once()
        selected = devices()
        selected[1]['preset'] = 'heartbeat'
        settings = {'features': {'rgb': True}, 'rgb': {'devices': selected}}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'XDG_STATE_HOME': directory}), \
             patch.object(rgb, 'resolve', return_value=(settings, True)), patch.object(rgb, 'present', return_value=['present']), \
             patch.object(rgb, 'mars_open', return_value=device), patch.object(rgb, 'mars_transact') as query:
            rgb.keepalive(Path(directory), 'desktop')
            query.assert_called_once_with(device, bytes((4, 0xe0)) + bytes(62))
            query.reset_mock()
            lock_path = Path(directory) / 'voluta/rgb.lock'
            with lock_path.open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                rgb.keepalive(Path(directory), 'desktop')
            query.assert_not_called()
            settings['features']['rgb'] = False
            rgb.keepalive(Path(directory), 'desktop')
            query.assert_not_called()


class MenuTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / 'companion'
        self.directory.mkdir()
        self.env = patch.dict(os.environ, {'XDG_STATE_HOME': self.temp.name, 'XDG_RUNTIME_DIR': self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        (self.directory / 'settings.json').write_text(json.dumps({
            'version': 1, 'features': {'rgb': True}, 'rgb': {'devices': devices()}}))
        (self.directory / 'hosts').mkdir()
        (self.directory / 'hosts/desktop.json').write_text(json.dumps({
            'version': 1, 'hyprland': {'input': {'kb_layout': 'us,br'}}}))
        (self.directory / 'hosts/notebook.json').write_text(json.dumps({
            'version': 1, 'features': {'rgb': False}}))

    def test_selection_is_host_and_target_scoped(self):
        shared = (self.directory / 'settings.json').read_bytes()
        notebook = (self.directory / 'hosts/notebook.json').read_bytes()
        with patch.object(rgb, 'apply', return_value=[]) as apply:
            self.assertEqual(rgb_menu.select(self.directory, 'desktop', 'wasd', 'keyboard'), 0)
            apply.assert_called_once()
        selected, _ = resolve(self.directory, 'desktop')
        self.assertEqual(selected['rgb']['devices'][1]['preset'], 'wasd')
        self.assertNotIn('preset', selected['rgb']['devices'][0])
        self.assertEqual(selected['hyprland']['input']['kb_layout'], 'us,br')
        self.assertEqual((self.directory / 'settings.json').read_bytes(), shared)
        self.assertEqual((self.directory / 'hosts/notebook.json').read_bytes(), notebook)
        with self.assertRaises(ValueError), patch.object(rgb, 'apply') as apply:
            rgb_menu.select(self.directory, 'notebook', 'heartbeat')
        apply.assert_not_called()

    def test_cancel_and_invalid_rofi_output_leave_settings_unchanged(self):
        original = (self.directory / 'hosts/desktop.json').read_bytes()
        with patch.object(rgb_menu.shutil, 'which', return_value='/usr/bin/rofi'), \
             patch.object(rgb_menu, 'choose', return_value=None), patch.object(rgb_menu, 'select') as select:
            self.assertEqual(rgb_menu.menu(self.directory, 'desktop'), 0)
            select.assert_not_called()
        self.assertEqual((self.directory / 'hosts/desktop.json').read_bytes(), original)
        for output in ('999', '-1', 'not an index'):
            with patch.object(rgb_menu.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, output, '')):
                self.assertIsNone(rgb_menu.choose(['one', 'two'], 'RGB'))

    def test_menu_applies_only_the_chosen_preset_and_target(self):
        index = next(i for i, p in enumerate(presets.PRESETS) if p.name == 'aurora')
        with patch.object(rgb_menu.shutil, 'which', return_value='/usr/bin/rofi'), \
             patch.object(rgb_menu, 'choose', side_effect=[1, index]), \
             patch.object(rgb_menu, 'select', return_value=0) as select, patch.object(rgb_menu.subprocess, 'run'):
            self.assertEqual(rgb_menu.menu(self.directory, 'desktop'), 0)
        select.assert_called_once_with(self.directory, 'desktop', 'aurora', 'keyboard')

    def test_cli_list_and_no_dry_run_mutation(self):
        command = [sys.executable, str(ROOT / 'voluta/cli.py'), '--config-dir', str(self.directory), '--host', 'desktop', 'rgb']
        result = subprocess.run(command + ['list'], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)), 26)
        original = (self.directory / 'hosts/desktop.json').read_bytes()
        result = subprocess.run(command + ['select', 'wasd', '--dry-run'], text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.directory / 'hosts/desktop.json').read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
