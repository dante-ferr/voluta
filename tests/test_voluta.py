"""Isolated settings and lifecycle checks: no desktop processes or real config writes."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("voluta_cli", ROOT / "voluta/cli.py")
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)
spec = importlib.util.spec_from_file_location("voluta_session", ROOT / "voluta/session.py")
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="voluta-check-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / "config/voluta"
        self.env = {**os.environ, "HOME": str(self.root),
                    "XDG_CONFIG_HOME": str(self.root / "config"),
                    "XDG_STATE_HOME": str(self.root / "state")}

    def run_cli(self, *args, code=0):
        result = subprocess.run([str(ROOT / "bin/voluta"), "--host", "test-desktop", *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def write(self, relative, data):
        path = self.directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"version": 1, **data}))

    def test_init_preserves_existing_preferences(self):
        self.run_cli("init", "--preserve-session")
        path = self.directory / "settings.json"
        before = path.read_bytes()
        self.run_cli("init")
        self.assertEqual(path.read_bytes(), before)
        self.assertTrue(json.loads(self.run_cli("show").stdout)["features"]["session_restore"])

    def test_defaults_and_host_precedence_across_core_updates(self):
        self.write("settings.json", {"features": {"session_restore": True},
                                      "hyprland": {"input": {"kb_layout": "br"}}})
        self.write("hosts/test-desktop.json", {"features": {"session_restore": False},
                                               "hyprland": {"input": {"kb_layout": "us", "repeat_rate": 42}}})
        resolved, initialized = cli.resolve(self.directory, "test-desktop")
        self.assertTrue(initialized)
        self.assertFalse(resolved["features"]["session_restore"])
        self.assertEqual(resolved["hyprland"]["input"], {"kb_layout": "us", "repeat_rate": 42})
        notebook, _ = cli.resolve(self.directory, "test-notebook")
        self.assertTrue(notebook["features"]["session_restore"])
        self.assertEqual(notebook["hyprland"]["input"]["kb_layout"], "br")
        core = self.root / "new-core/voluta"
        core.mkdir(parents=True)
        defaults = cli.read(ROOT / "voluta/defaults.json")
        defaults["features"]["dolphin"] = False
        (core / "defaults.json").write_text(json.dumps(defaults))
        with patch.object(cli, "ROOT", core.parent):
            updated, _ = cli.resolve(self.directory, "test-desktop")
        self.assertFalse(updated["features"]["dolphin"])
        self.assertFalse(updated["features"]["session_restore"])

    def test_feature_changes_require_explicit_initialization(self):
        self.run_cli("feature", "disable", "dolphin", code=2)
        self.assertFalse(self.directory.exists())
        self.run_cli("enabled", "session_restore", "--legacy")
        self.run_cli("enabled", "session_restore", code=1)

    def test_disabled_dolphin_prepare_has_no_application_side_effects(self):
        self.run_cli("init")
        self.run_cli("feature", "disable", "dolphin")
        result = subprocess.run(["bash", str(ROOT / "dolphin/launch.sh"), "--prepare"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / ".local/lib").exists())
        self.assertFalse((self.root / ".config/dolphinrc").exists())

    def test_optional_lifecycle_and_host_disable(self):
        self.run_cli("init")
        self.run_cli("enabled", "session_restore", code=1)
        self.run_cli("feature", "enable", "session_restore")
        self.run_cli("enabled", "session_restore")
        self.run_cli("feature", "disable", "session_restore", "--scope", "host")
        self.run_cli("enabled", "session_restore", code=1)
        self.run_cli("feature", "reset", "session_restore", "--scope", "host")
        self.run_cli("enabled", "session_restore")
        self.run_cli("feature", "disable", "session_restore")
        self.run_cli("feature", "enable", "session_restore")
        self.run_cli("enabled", "session_restore")
        self.run_cli("feature", "disable", "dolphin")
        self.run_cli("enabled", "dolphin", code=1)

    def test_config_nested_update_and_reset(self):
        self.run_cli("init")
        self.run_cli("config", "set", "input.kb_layout", '"br"')
        self.run_cli("config", "set", "input.repeat_rate", "45")
        self.run_cli("config", "reset", "input.kb_layout")
        data = json.loads(self.run_cli("show").stdout)
        self.assertEqual(data["hyprland"]["input"], {"repeat_rate": 45})
        self.run_cli("config", "set", "input.repeat_rate", "NaN", code=2)

    def test_invalid_config_never_overwritten(self):
        self.directory.mkdir(parents=True)
        path = self.directory / "settings.json"
        for data in ('not JSON', '{"version":2}', '{"version":1,"features":{"dolphin":"false"}}'):
            path.write_text(data)
            self.run_cli("feature", "enable", "dolphin", code=2)
            self.assertEqual(path.read_text(), data)
        self.run_cli("--host", "../escape", "show", code=2)

    def test_companion_attach_preserves_source_and_refuses_overwrite(self):
        companion = self.root / "personal"
        companion.mkdir()
        source = companion / "settings.json"
        source.write_text('{"version":1,"features":{"dolphin":false}}')
        self.run_cli("companion", "attach", str(companion))
        self.assertTrue(self.directory.is_symlink())
        self.run_cli("companion", "attach", str(companion))
        self.run_cli("feature", "enable", "dolphin")
        self.assertTrue(json.loads(source.read_text())["features"]["dolphin"])
        other = self.root / "other"
        other.mkdir()
        (other / "settings.json").write_text('{"version":1}')
        self.run_cli("companion", "attach", str(other), code=2)
        self.assertEqual(self.directory.resolve(), companion)

    def test_lua_roundtrip_and_no_injection(self):
        payload = 'br"; error("injected") --\nç\\'
        self.write("settings.json", {"hyprland": {"input": {"kb_layout": payload}}})
        rendered = self.run_cli("render-lua").stdout
        script = self.root / "settings.lua"
        script.write_text(rendered)
        result = subprocess.run(["lua", "-e", f'local x=dofile({cli.lua(str(script))}); io.write(x.hyprland.input.kb_layout)'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, payload)

    def test_lua_reader_refreshes_and_legacy_behavior(self):
        self.directory.parent.mkdir(parents=True)
        (self.directory.parent / "hypr").symlink_to(ROOT / "hypr", target_is_directory=True)
        code = f'''local x=dofile({cli.lua(str(ROOT / "hypr/configs/Voluta.lua"))});
                   assert(x.enabled("session_restore") == EXPECTED)'''
        for expected in ("true", "false"):
            if expected == "false":
                self.run_cli("init")
            result = subprocess.run(["lua", "-e", code.replace("EXPECTED", expected)],
                                    env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


class SupervisorTests(unittest.TestCase):
    def test_late_enable_uses_no_restore_and_disable_stops_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "hypr/test/.socket2.sock"
            socket_path.parent.mkdir(parents=True)
            socket_path.touch()
            worker = Mock()
            worker.poll.return_value = None
            states = iter((False, True, False, True))
            calls = 0
            def tick(_):
                nonlocal calls
                calls += 1
                if calls == 4:
                    raise SystemExit(0)
            with patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory, "HYPRLAND_INSTANCE_SIGNATURE": "test"}), \
                 patch.object(session, "enabled", side_effect=lambda: next(states)), \
                 patch.object(session.subprocess, "Popen", return_value=worker) as popen, \
                 patch.object(session.signal, "signal"), patch.object(session.time, "sleep", side_effect=tick):
                with self.assertRaises(SystemExit):
                    session.main()
            self.assertEqual(popen.call_count, 2)
            self.assertTrue(all(call.args[0][-1] == "daemon" for call in popen.call_args_list))
            self.assertEqual(worker.terminate.call_count, 2)


if __name__ == "__main__":
    unittest.main()
