"""Regression tests: python3 -m unittest discover -s hypr/scripts/tests -v"""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch, Mock

spec = importlib.util.spec_from_file_location("session_manager", Path(__file__).parents[1] / "session_manager.py")
sm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sm)


def window(address="0x1", title="Work", cls="kitty", ws=7):
    return {"address": address, "class": cls, "initialClass": cls, "title": title,
            "workspace": {"id": ws, "name": str(ws)}, "workspace_id": ws,
            "workspace_name": str(ws), "command": "kitty", "floating": False}


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        for key, value in {
            "STATE_DIR": root, "SESSION_FILE": root / "session.json",
            "SHUTDOWN_FILE": root / "session.shutdown.json",
            "LOCK_FILE": root / "snapshot.lock", "DAEMON_LOCK": root / "daemon.lock",
            "RESTORE_LOCK": root / "restore.lock", "FROZEN_FILE": root / "shutdown",
            "RESTORED_FILE": root / "restored",
        }.items():
            p = patch.object(sm, key, value)
            p.start()
            self.addCleanup(p.stop)

    def snapshot(self, windows):
        sm.SESSION_FILE.write_text(json.dumps({"windows": windows}))

    def test_launch_uses_lua_and_checks_response(self):
        with patch.object(sm.subprocess, "run", return_value=Mock(returncode=0, stdout="ok\n")) as run:
            sm.launch("kitty --directory '/tmp/a b'", "7")
        args = run.call_args.args[0]
        self.assertEqual(args[:2], ["hyprctl", "eval"])
        self.assertIn("hl.exec_cmd(", args[2])
        self.assertIn("workspace=", args[2])
        with patch.object(sm.subprocess, "run", return_value=Mock(returncode=0, stdout="error: invalid")):
            with self.assertRaises(RuntimeError):
                sm.launch("kitty", "7")

    def test_exact_titles_reserved_before_fallback(self):
        saved = [window(title="changed"), window(title="Personal")]
        clients = [window("0x2", "Personal"), window("0x3", "new title")]
        pairs, missing = sm.match_windows(saved, clients)
        self.assertFalse(missing)
        self.assertEqual({s["title"]: c["address"] for s, c in pairs},
                         {"Personal": "0x2", "changed": "0x3"})

    def test_cannot_match_same_client_twice(self):
        pairs, missing = sm.match_windows([window(), window()], [window()])
        self.assertEqual((len(pairs), len(missing)), (1, 1))

    def test_empty_session_is_saved_but_ipc_failure_is_not(self):
        self.snapshot([window()])
        with patch.object(sm, "get_hyprctl_json", return_value=None):
            self.assertFalse(sm.save_session())
        self.assertEqual(len(json.loads(sm.SESSION_FILE.read_text())["windows"]), 1)
        with patch.object(sm, "get_hyprctl_json", return_value=[]):
            self.assertTrue(sm.save_session())
        self.assertEqual(json.loads(sm.SESSION_FILE.read_text())["windows"], [])

    def test_shutdown_snapshot_survives_old_daemon_overwrite(self):
        with patch.object(sm, "get_hyprctl_json", side_effect=lambda cmd: [window()] if cmd == "clients" else []), patch.object(sm, "resolve_command", return_value=("kitty", "/tmp")):
            sm.save_session(freeze=True)
        original = sm.SHUTDOWN_FILE.read_text()
        with patch.object(sm, "_save_session") as save:
            self.assertFalse(sm.save_session())
            save.assert_not_called()
        self.snapshot([])  # An old daemon in memory can still overwrite session.json.
        with patch.object(sm, "get_hyprctl_json", side_effect=lambda cmd: [window()] if cmd == "clients" else []), patch.object(sm, "place_window") as place, patch.object(sm.time, "sleep"):
            self.assertTrue(sm.restore_session())
        place.assert_called_once()
        self.assertEqual((sm.STATE_DIR / "session.before-restore.json").read_text(), original)
        self.assertFalse(sm.SHUTDOWN_FILE.exists())

    def test_special_and_named_workspace_selectors(self):
        self.assertEqual(sm.workspace_selector({"workspace_name": "special:notes", "workspace_id": -99}), "special:notes")
        self.assertEqual(sm.workspace_selector({"workspace_name": "Research", "workspace_id": -5}), "name:Research")
        self.assertEqual(sm.workspace_selector(window()), "7")

    def test_browser_launches_once_then_matches_native_restored_windows(self):
        saved = [window("0x1", "Work", "brave-browser", 1), window("0x2", "Personal", "brave-browser", 8)]
        for w in saved:
            w["command"] = "brave --restore-last-session"
        self.snapshot(saved)
        clients = [window("0xa", "Personal", "brave-browser"), window("0xb", "Work", "brave-browser")]
        calls = 0
        def query(cmd):
            nonlocal calls
            if cmd == "monitors":
                return []
            calls += 1
            return [] if calls == 1 else clients
        with patch.object(sm, "get_hyprctl_json", side_effect=query), patch.object(sm, "launch") as launch, patch.object(sm, "place_window") as place, patch.object(sm.time, "sleep"), patch.object(sm.time, "monotonic", side_effect=range(100)):
            self.assertTrue(sm.restore_session())
        launch.assert_called_once()
        self.assertEqual({args.args[0]["workspace_id"]: args.args[1]["address"] for args in place.call_args_list}, {1: "0xb", 8: "0xa"})

    def test_restore_only_once_per_compositor(self):
        self.snapshot([])
        with patch.object(sm, "_restore_session", return_value=True) as restore:
            sm.restore_session()
            sm.restore_session()
            restore.assert_called_once()

    def test_floating_geometry_and_monitor_use_explicit_window(self):
        saved = window()
        saved.update(floating=True, at=[20, 40], size=[800, 600], monitor_name="DP-1", fullscreen=2)
        with patch.object(sm, "dispatch") as dispatch:
            sm.place_window(saved, window("0xaa"), {"DP-1"})
        calls = dispatch.call_args_list
        self.assertEqual(calls[0].args, ("window.move", {"window": "address:0xaa", "workspace": "7", "follow": False}))
        self.assertEqual(calls[1].args, ("workspace.move", {"workspace": "7", "monitor": "DP-1"}))
        self.assertIn(unittest.mock.call("window.resize", {"window": "address:0xaa", "x": 800, "y": 600, "relative": False}), calls)

    def test_terminal_cwd_shell_quoting(self):
        cwd = "/tmp/it's a $(touch nope) project"
        with patch.object(sm, "get_terminal_cwd", return_value=cwd):
            command, _ = sm.resolve_command({"class": "kitty", "pid": 123})
        import shlex
        self.assertEqual(shlex.split(command), ["kitty", "--directory", cwd])

    def test_daemon_restores_before_listening_and_saving(self):
        order = []
        sock = Mock()
        sock.recv.return_value = b""  # compositor exits: do not save an empty teardown session
        ctx = Mock()
        ctx.__enter__ = Mock(return_value=sock)
        ctx.__exit__ = Mock(return_value=False)
        with patch.object(sm, "get_hyprland_socket2_path", return_value="/tmp/socket"), patch.object(sm, "restore_session", side_effect=lambda **kw: order.append("restore")), patch.object(sm.shutil, "which", return_value=None), patch.object(sm.socket, "socket", return_value=ctx), patch.object(sm, "save_session") as save:
            sock.connect.side_effect = lambda _: order.append("connect")
            sm.run_daemon(restore=True)
        self.assertEqual(order, ["restore", "connect"])
        save.assert_not_called()

    def test_logind_shutdown_saves_and_releases_monitor(self):
        monitor = Mock()
        monitor.stdout = iter(["signal member=PrepareForShutdown\n", "   boolean true\n"])
        ctx = Mock()
        ctx.__enter__ = Mock(return_value=monitor)
        ctx.__exit__ = Mock(return_value=False)
        with patch.object(sm.subprocess, "Popen", return_value=ctx), patch.object(sm, "save_session") as save:
            sm.watch_shutdown()
        save.assert_called_once_with(freeze=True)
        monitor.terminate.assert_called_once()


if __name__ == "__main__":
    unittest.main()
