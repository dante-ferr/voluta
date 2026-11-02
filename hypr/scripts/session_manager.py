#!/usr/bin/env python3
"""
Hyprland Session Manager
Saves and restores open windows, workspaces, positions, sizes, and terminal CWDs across restarts.
"""

import json
import fcntl
import shlex
import shutil
import signal
from contextlib import contextmanager
import os
import re
import socket
import subprocess
import sys
import time
import tempfile
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))) / "hyprland"
SESSION_FILE = STATE_DIR / "session.json"
SHUTDOWN_FILE = STATE_DIR / "session.shutdown.json"
INSTANCE = re.sub(r"[^a-zA-Z0-9_-]", "_", os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "no-instance"))
LOCK_FILE = STATE_DIR / "snapshot.lock"
DAEMON_LOCK = STATE_DIR / f"daemon-{INSTANCE}.lock"
RESTORE_LOCK = STATE_DIR / f"restore-{INSTANCE}.lock"
FROZEN_FILE = STATE_DIR / f"shutdown-{INSTANCE}"
RESTORED_FILE = STATE_DIR / f"restored-{INSTANCE}"


@contextmanager
def state_lock(path=None, blocking=True):
    path = path or LOCK_FILE
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def frozen():
    # A cancelled shutdown must not disable saving for the rest of the login.
    return FROZEN_FILE.exists() and time.time() - FROZEN_FILE.stat().st_mtime < 120


def lua(value):
    """Encode strings as Lua literals, including quotes, newlines and Unicode."""
    if isinstance(value, str):
        return '"' + ''.join(f"\\{b:03d}" for b in value.encode("utf-8")) + '"'
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, dict):
        return "{" + ",".join(f"{k}={lua(v)}" for k, v in value.items()) + "}"
    return str(value)


def dispatch(method, options):
    result = subprocess.run(
        ["hyprctl", "dispatch", f"hl.dsp.{method}({lua(options)})"],
        capture_output=True, text=True, timeout=5,
    )
    if result.returncode or result.stdout.strip() != "ok":
        raise RuntimeError(f"Hyprland dispatcher {method} failed: {result.stdout.strip()}")


def launch(command, workspace):
    # exec rules are a Lua table in Hyprland 0.55+, not the old [workspace] syntax.
    result = subprocess.run(
        ["hyprctl", "eval", f"hl.exec_cmd({lua(command)}, {{workspace={lua(str(workspace) + ' silent')}}})"],
        capture_output=True, text=True, timeout=5,
    )
    if result.returncode or result.stdout.strip() != "ok":
        raise RuntimeError(f"Hyprland launch failed: {result.stdout.strip()}")

IGNORED_CLASSES = {
    "",
    "rofi",
    "wlogout",
    "swaync",
    "swaync-control-center",
    "swaync-notification-window",
    "imperium-sigil",
    "imperium-telemetry",
    "pixel-art-widget",
    "pixel-widget",
    "pavucontrol",
    "pavucontrol-qt",
    "org.pulseaudio.pavucontrol",
    "com.saivert.pwvucontrol",
    "nm-connection-editor",
    "nm-applet",
    "blueman-manager",
    "hyprland-share-picker",
    "hyprlock",
    "xdg-desktop-portal-hyprland",
    "xdg-desktop-portal-gtk",
    "polkit-gnome-authentication-agent-1",
}


def get_hyprland_socket2_path():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if runtime_dir and his:
        sock = Path(runtime_dir) / "hypr" / his / ".socket2.sock"
        if sock.exists():
            return str(sock)
    try:
        uid = os.getuid()
        base = Path(f"/run/user/{uid}/hypr")
        if base.exists():
            for p in base.glob("*/.socket2.sock"):
                return str(p)
    except Exception:
        pass
    return None


def get_hyprctl_json(command):
    try:
        out = subprocess.check_output(["hyprctl", "-j", command], text=True, timeout=5)
        return json.loads(out)
    except Exception as e:
        print(f"[SessionManager] Error running hyprctl {command}: {e}", file=sys.stderr)
        return None


def get_child_pids(pid):
    try:
        out = subprocess.check_output(["pgrep", "-P", str(pid)], text=True, timeout=2)
        return [int(p) for p in out.strip().split() if p.isdigit()]
    except Exception:
        return []


def get_terminal_cwd(pid):
    """Recursively search child processes of a terminal to find active shell CWD."""
    queue = [pid]
    visited = set()
    candidates = []
    while queue:
        curr = queue.pop(0)
        if curr in visited:
            continue
        visited.add(curr)
        try:
            cwd = os.readlink(f"/proc/{curr}/cwd")
            with open(f"/proc/{curr}/cmdline", "rb") as f:
                cmdline = [a.decode("utf-8", "replace") for a in f.read().split(b"\x00") if a]
            if cmdline:
                exe = os.path.basename(cmdline[0])
                if exe in ("zsh", "bash", "fish", "sh", "tcsh", "tmux", "nu", "elvish"):
                    return cwd
                candidates.append(cwd)
        except Exception:
            pass
        queue.extend(get_child_pids(curr))
    return candidates[0] if candidates else os.path.expanduser("~")


def dolphin_launch(argument=""):
    """Prefer the wrapper that loads the live palette hook."""
    wrapper = os.path.expanduser("~/.local/bin/dolphin")
    binary = wrapper if os.path.isfile(wrapper) and os.access(wrapper, os.X_OK) else "dolphin"
    if argument:
        return f"{binary} {argument}"
    return binary


def resolve_command(client):
    """Determine the accurate launch command and working directory for a window."""
    cls = (client.get("class") or client.get("initialClass") or "").lower()
    pid = client.get("pid")
    home = os.path.expanduser("~")

    # 1. Terminals (Kitty, Alacritty, Foot, Wezterm, Ghostty)
    if "kitty" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"kitty --directory {shlex.quote(cwd)}", cwd
    if "alacritty" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"alacritty --working-directory {shlex.quote(cwd)}", cwd
    if "foot" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"foot -D {shlex.quote(cwd)}", cwd
    if "wezterm" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"wezterm start --cwd {shlex.quote(cwd)}", cwd
    if "ghostty" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"ghostty --working-directory={shlex.quote(cwd)}", cwd

    # 2. Editors & IDEs
    if "cursor" in cls:
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd) and cwd != home:
                return f"cursor --new-window {shlex.quote(cwd)}", cwd
        except Exception:
            pass
        return "cursor --new-window", home

    if cls in ("code", "code-oss", "vscodium", "com.microsoft.vscode"):
        cls = "code" if cls == "com.microsoft.vscode" else cls
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd) and cwd != home:
                return f"{cls} --new-window {shlex.quote(cwd)}", cwd
        except Exception:
            pass
        return f"{cls} --new-window", home

    if "obsidian" in cls:
        return "obsidian", home

    # Browsers restore their tabs/windows; retain profile selection without replaying URLs.
    browsers = (("brave", "brave"), ("chrome", "google-chrome-stable"),
                ("chromium", "chromium"), ("firefox", "firefox"),
                ("zen", "zen-browser"), ("librewolf", "librewolf"))
    for marker, binary in browsers:
        if marker in cls:
            args = [binary]
            try:
                argv = Path(f"/proc/{pid}/cmdline").read_bytes().decode().split("\0")
                for i, arg in enumerate(argv):
                    if arg.startswith(("--profile-directory=", "--user-data-dir=")):
                        args.append(arg)
                    elif arg in ("--profile-directory", "--user-data-dir", "-P", "--profile") and i + 1 < len(argv):
                        args.extend([arg, argv[i + 1]])
            except OSError:
                pass
            if marker in ("brave", "chrome", "chromium"):
                args.append("--restore-last-session")
            return shlex.join(args), home

    # 4. Communication & Media
    if "discord" in cls or "vesktop" in cls or "webcord" in cls:
        return "vesktop" if "vesktop" in cls else "discord", home
    if "spotify" in cls:
        return "spotify", home
    if "steam" in cls:
        return "steam", home
    if "slack" in cls:
        return "slack", home
    if "telegram" in cls or "org.telegram.desktop" in cls:
        return "telegram-desktop", home

    # 5. File Managers
    if any(manager in cls for manager in ("dolphin", "nautilus", "org.gnome.nautilus", "thunar")):
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd):
                return dolphin_launch(shlex.quote(cwd)), cwd
        except Exception:
            pass
        return dolphin_launch(), home

    # 6. Fallback: Parse /proc/<pid>/cmdline if available
    if pid:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = [a.decode("utf-8", "replace") for a in f.read().split(b"\x00") if a]
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if cmdline:
                # Preserve argv boundaries instead of building an injectable nested shell.
                command = shlex.join(cmdline)
                if cwd and os.path.isdir(cwd):
                    command = shlex.join(["sh", "-c", f"cd -- {shlex.quote(cwd)} && exec {command}"])
                return command, cwd
        except Exception:
            pass

    raw_class = client.get("class") or client.get("initialClass") or ""
    return shlex.quote(raw_class), home


def save_session(verbose=False, freeze=False):
    with state_lock():
        if frozen():
            return False
        result = _save_session(verbose)
        if freeze:
            if SESSION_FILE.exists():
                # Also protects the first shutdown while the old daemon is still running.
                temporary = SHUTDOWN_FILE.with_suffix(".tmp")
                shutil.copyfile(SESSION_FILE, temporary)
                os.chmod(temporary, 0o600)
                temporary.replace(SHUTDOWN_FILE)
            FROZEN_FILE.touch(mode=0o600)
        elif result:
            SHUTDOWN_FILE.unlink(missing_ok=True)
        return result


def _save_session(verbose=False):
    """Capture current windows and persist to JSON."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    clients = get_hyprctl_json("clients")
    if clients is None:
        return False
    monitors = {m["id"]: m["name"] for m in (get_hyprctl_json("monitors") or [])}

    saved_windows = []
    seen_addresses = set()

    for c in clients:
        addr = c.get("address")
        if addr in seen_addresses:
            continue
        seen_addresses.add(addr)

        cls = c.get("class") or c.get("initialClass") or ""
        ws_info = c.get("workspace", {})
        ws_id = ws_info.get("id", 0)
        ws_name = ws_info.get("name", "")

        # Named and special workspaces have negative IDs; retain them too.
        if ws_id == 0 or cls.lower() in IGNORED_CLASSES:
            continue

        cmd, cwd = resolve_command(c)
        if not cmd:
            continue

        win_entry = {
            "address": addr,
            "class": cls,
            "initialClass": c.get("initialClass", ""),
            "initialTitle": c.get("initialTitle", ""),
            "title": c.get("title", ""),
            "workspace_id": ws_id,
            "workspace_name": ws_name,
            "monitor": c.get("monitor", 0),
            "monitor_name": monitors.get(c.get("monitor")),
            "floating": bool(c.get("floating", False)),
            "at": c.get("at", [0, 0]),
            "size": c.get("size", [0, 0]),
            "fullscreen": c.get("fullscreen", 0),
            "pinned": bool(c.get("pinned", False)),
            "focus_history_id": c.get("focusHistoryID", 0),
            "cwd": cwd,
            "command": cmd,
        }
        saved_windows.append(win_entry)

    data = {
        "timestamp": time.time(),
        "formatted_time": time.strftime("%Y-%m-%d %H:%M:%S"),
        "window_count": len(saved_windows),
        "windows": saved_windows,
    }

    # Unique temp names also avoid collisions with a daemon from before this update.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=STATE_DIR,
                                     prefix="session-", suffix=".tmp", delete=False) as f:
        temp_file = Path(f.name)
        try:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        except BaseException:
            temp_file.unlink(missing_ok=True)
            raise
    temp_file.replace(SESSION_FILE)

    if verbose:
        print(f"[SessionManager] Saved {len(saved_windows)} windows to {SESSION_FILE}")
    return True


def workspace_selector(win):
    name = win.get("workspace_name", "")
    if name.startswith("special:"):
        return name
    if name and name != str(win.get("workspace_id")):
        return "name:" + name
    return str(win.get("workspace_id", 1))


def window_class(win):
    return (win.get("initialClass") or win.get("class") or "").lower()


def is_browser(win):
    return any(b in window_class(win) for b in
               ("brave", "chrome", "chromium", "firefox", "librewolf", "zen-browser"))


def match_windows(saved, clients):
    """Reserve exact title matches first, then use class/order for changed titles."""
    remaining = list(clients)
    pairs = []
    unmatched = list(saved)
    for exact in (True, False):
        for win in list(unmatched):
            candidates = [c for c in remaining if window_class(c) == window_class(win)]
            if exact:
                candidates = [c for c in candidates if win.get("title") and c.get("title") == win["title"]]
            if candidates:
                client = candidates[0]
                pairs.append((win, client))
                remaining.remove(client)
                unmatched.remove(win)
    return pairs, unmatched


def place_window(win, client, monitors):
    selector = "address:" + client["address"]
    ws = workspace_selector(win)
    dispatch("window.move", {"window": selector, "workspace": ws, "follow": False})
    monitor = win.get("monitor_name")
    if monitor in monitors:
        dispatch("workspace.move", {"workspace": ws, "monitor": monitor})
    dispatch("window.float", {"window": selector, "action": "enable" if win.get("floating") else "disable"})
    if win.get("floating"):
        x, y = win.get("at", [0, 0])
        width, height = win.get("size", [800, 600])
        dispatch("window.resize", {"window": selector, "x": width, "y": height, "relative": False})
        dispatch("window.move", {"window": selector, "x": x, "y": y, "relative": False})
    if win.get("fullscreen"):
        dispatch("window.fullscreen", {"window": selector, "mode": "fullscreen" if win["fullscreen"] == 2 else "maximized", "action": "set"})
    if win.get("pinned") and not client.get("pinned"):
        dispatch("window.pin", {"window": selector})


def restore_session(verbose=False):
    with state_lock(RESTORE_LOCK, blocking=False) as acquired:
        if not acquired or RESTORED_FILE.exists():
            return False
        with state_lock():
            result = _restore_session(verbose)
            RESTORED_FILE.touch(mode=0o600)
            return result


def _restore_session(verbose=False):
    source = SHUTDOWN_FILE if SHUTDOWN_FILE.exists() else SESSION_FILE
    if not source.exists():
        return True
    data = json.loads(source.read_text())
    windows = data.get("windows", [])
    if not windows:
        SHUTDOWN_FILE.unlink(missing_ok=True)
        return True
    # Preserve the pre-login snapshot even if an application cannot be reopened.
    shutil.copyfile(source, STATE_DIR / "session.before-restore.json")
    os.chmod(STATE_DIR / "session.before-restore.json", 0o600)
    clients = get_hyprctl_json("clients")
    if clients is None:
        raise RuntimeError("Hyprland is not ready")
    _, missing = match_windows(windows, clients)
    browser_commands = set()
    for win in missing:
        command = win.get("command")
        if not command:
            continue
        if is_browser(win):
            if any(b in window_class(win) for b in ("brave", "chrome", "chromium")) and "--restore-last-session" not in command:
                command += " --restore-last-session"
            if command in browser_commands:
                continue
            browser_commands.add(command)
        try:
            launch(command, workspace_selector(win))
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            print(f"[SessionManager] Launch failed: {error}", file=sys.stderr)

    # Give app-native session restoration time to reopen multiple windows and titles.
    deadline = time.monotonic() + 30
    fallback_at = time.monotonic() + 15
    settled_at = None
    while time.monotonic() < deadline:
        clients = get_hyprctl_json("clients")
        if clients is None:
            raise RuntimeError("Lost Hyprland during restore")
        pairs, missing = match_windows(windows, clients)
        if not missing:
            if settled_at is None:
                settled_at = time.monotonic()
            if time.monotonic() - settled_at >= 3:
                break
        else:
            settled_at = None
        if time.monotonic() >= fallback_at:
            for win in missing:
                if is_browser(win) and win.get("command"):
                    command = win["command"].replace(" --restore-last-session", "")
                    try:
                        launch(command + " --new-window", workspace_selector(win))
                    except (RuntimeError, subprocess.TimeoutExpired) as error:
                        print(f"[SessionManager] Browser launch failed: {error}", file=sys.stderr)
            fallback_at = float("inf")
        time.sleep(0.5)
    monitors = {m["name"] for m in (get_hyprctl_json("monitors") or [])}
    failures = len(missing)
    for win, client in pairs:
        try:
            place_window(win, client, monitors)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            failures += 1
            print(f"[SessionManager] Placement failed: {error}", file=sys.stderr)
    SHUTDOWN_FILE.unlink(missing_ok=True)
    print(f"[SessionManager] Restored {len(windows) - failures}/{len(windows)} windows.", flush=True)
    return failures == 0


def watch_shutdown():
    """Runs under a logind delay inhibitor, saving before shutdown closes apps."""
    rule = "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForShutdown',path='/org/freedesktop/login1'"
    with subprocess.Popen(["dbus-monitor", "--system", rule], stdout=subprocess.PIPE, text=True) as monitor:
        try:
            for line in monitor.stdout:
                if line.strip() == "boolean true":
                    save_session(freeze=True)
                    return
        finally:
            monitor.terminate()
            monitor.wait(timeout=3)


def run_daemon(restore=False):
    """One owner per compositor; restore finishes before autosave can begin."""
    with state_lock(DAEMON_LOCK, blocking=False) as acquired:
        if not acquired:
            return
        sock_path = get_hyprland_socket2_path()
        if not sock_path:
            raise RuntimeError("Hyprland socket2 not found")
        if restore:
            restore_session(verbose=True)
        watcher = None
        if shutil.which("systemd-inhibit") and shutil.which("dbus-monitor"):
            watcher = subprocess.Popen([
                "systemd-inhibit", "--what=shutdown", "--mode=delay",
                "--who=Hyprland session manager", "--why=Save window workspaces",
                sys.executable, str(Path(__file__).resolve()), "watch-shutdown",
            ], start_new_session=True)
        # Feature disable must unwind the watcher/inhibitor cleanup below.
        previous_term = signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.connect(sock_path)
                sock.settimeout(1)
                last_save = 0
                changed_at = None
                buffer = ""
                while True:
                    try:
                        chunk = sock.recv(65536)
                        if not chunk:
                            return  # Never replace the snapshot after compositor teardown.
                        buffer += chunk.decode("utf-8", errors="replace")
                        while "\n" in buffer:
                            event, buffer = buffer.split("\n", 1)
                            if event.startswith("shutdown>>"):
                                return
                            if event.startswith(("openwindow>>", "closewindow>>", "movewindow>>", "movewindowv2>>", "changefloatingmode>>", "windowtitle>>", "windowtitlev2>>")):
                                changed_at = time.monotonic()
                    except socket.timeout:
                        pass
                    now = time.monotonic()
                    if (changed_at is not None and now - changed_at >= 1) or now - last_save >= 30:
                        save_session()
                        last_save, changed_at = now, None
        finally:
            signal.signal(signal.SIGTERM, previous_term)
            if watcher is not None:
                if watcher.poll() is None:
                    os.killpg(watcher.pid, signal.SIGTERM)
                watcher.wait(timeout=5)


def print_status():
    if not SESSION_FILE.exists():
        print(f"No saved session at {SESSION_FILE}")
        return

    try:
        with open(SESSION_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading session file: {e}")
        return

    print(f"Saved Session from: {data.get('formatted_time')}")
    print(f"Total Windows: {data.get('window_count')}\n")
    print(f"{'WS':<4} {'FLOAT':<6} {'CLASS':<20} {'COMMAND':<40} {'CWD'}")
    print("-" * 95)
    for w in data.get("windows", []):
        ws = w.get("workspace_id")
        flt = "Yes" if w.get("floating") else "No"
        cls = w.get("class", "")[:18]
        cmd = w.get("command", "")[:38]
        cwd = w.get("cwd", "")
        print(f"{ws:<4} {flt:<6} {cls:<20} {cmd:<40} {cwd}")


def main():
    if len(sys.argv) < 2:
        print("Usage: session_manager.py [save|prepare-shutdown|restore|start|daemon|status]")
        sys.exit(1)

    cmd = sys.argv[1].lower()
    if cmd == "save":
        save_session(verbose=True)
    elif cmd == "prepare-shutdown":
        save_session(verbose=True, freeze=True)
    elif cmd == "watch-shutdown":
        watch_shutdown()
    elif cmd == "start":
        run_daemon(restore=True)
    elif cmd == "restore":
        restore_session(verbose=True)
    elif cmd == "daemon":
        run_daemon()
    elif cmd == "status":
        print_status()
    else:
        print(f"Unknown command: {cmd}")
        print("Usage: session_manager.py [save|prepare-shutdown|restore|start|daemon|status]")
        sys.exit(1)


if __name__ == "__main__":
    main()
