#!/usr/bin/env python3
"""
Hyprland Session Manager
Saves and restores open windows, workspaces, positions, sizes, and terminal CWDs across restarts.
"""

import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

STATE_DIR = Path.home() / ".local" / "state" / "hyprland"
SESSION_FILE = STATE_DIR / "session.json"
LOCK_FILE = STATE_DIR / "restore.lock"

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
        out = subprocess.check_output(["hyprctl", command, "-j"], text=True)
        return json.loads(out)
    except Exception as e:
        print(f"[SessionManager] Error running hyprctl {command}: {e}", file=sys.stderr)
        return []


def get_child_pids(pid):
    try:
        out = subprocess.check_output(["pgrep", "-P", str(pid)], text=True)
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


def resolve_command(client):
    """Determine the accurate launch command and working directory for a window."""
    cls = (client.get("class") or client.get("initialClass") or "").lower()
    pid = client.get("pid")
    home = os.path.expanduser("~")

    # 1. Terminals (Kitty, Alacritty, Foot, Wezterm, Ghostty)
    if "kitty" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"kitty --directory '{cwd}'", cwd
    if "alacritty" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"alacritty --working-directory '{cwd}'", cwd
    if "foot" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"foot -D '{cwd}'", cwd
    if "wezterm" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"wezterm start --cwd '{cwd}'", cwd
    if "ghostty" in cls:
        cwd = get_terminal_cwd(pid) if pid else home
        return f"ghostty --working-directory='{cwd}'", cwd

    # 2. Editors & IDEs
    if "cursor" in cls:
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd) and cwd != home:
                return f"cursor '{cwd}'", cwd
        except Exception:
            pass
        return "cursor", home

    if cls in ("code", "code-oss", "vscodium"):
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd) and cwd != home:
                return f"{cls} '{cwd}'", cwd
        except Exception:
            pass
        return cls, home

    if "obsidian" in cls:
        return "obsidian", home

    # 3. Browsers
    if "brave" in cls:
        return "brave", home
    if "chrome" in cls:
        return "google-chrome-stable", home
    if "chromium" in cls:
        return "chromium", home
    if "firefox" in cls or "zen" in cls or "librewolf" in cls:
        return cls.split("-")[0], home

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
    if "dolphin" in cls:
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd):
                return f"dolphin '{cwd}'", cwd
        except Exception:
            pass
        return "dolphin", home
    if "nautilus" in cls or "org.gnome.nautilus" in cls:
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd):
                return f"nautilus '{cwd}'", cwd
        except Exception:
            pass
        return "nautilus", home
    if "thunar" in cls:
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if os.path.isdir(cwd):
                return f"thunar '{cwd}'", cwd
        except Exception:
            pass
        return "thunar", home

    # 6. Fallback: Parse /proc/<pid>/cmdline if available
    if pid:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = [a.decode("utf-8", "replace") for a in f.read().split(b"\x00") if a]
            cwd = os.readlink(f"/proc/{pid}/cwd")
            if cmdline:
                exe = cmdline[0]
                if exe.startswith("/usr/lib/electron") and len(cmdline) > 1:
                    exe = cmdline[1]
                cmd_str = " ".join([f"'{arg}'" if (" " in arg or "$" in arg) else arg for arg in cmdline])
                if cwd and cwd != home and os.path.isdir(cwd):
                    return f"sh -c 'cd \"{cwd}\" && {cmd_str}'", cwd
                return cmd_str, cwd
        except Exception:
            pass

    raw_class = client.get("class") or client.get("initialClass") or ""
    return raw_class, home


def save_session(verbose=False):
    """Capture current windows and persist to JSON."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    clients = get_hyprctl_json("clients")
    if not clients:
        if verbose:
            print("[SessionManager] No active clients found to save.")
        return False

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

        # Skip negative/special scratchpad workspaces or ignored utility windows
        if ws_id <= 0 or ws_name.startswith("special:") or cls in IGNORED_CLASSES:
            continue

        cmd, cwd = resolve_command(c)
        if not cmd:
            continue

        win_entry = {
            "address": addr,
            "class": cls,
            "initialClass": c.get("initialClass", ""),
            "title": c.get("title", ""),
            "workspace_id": ws_id,
            "workspace_name": ws_name,
            "monitor": c.get("monitor", 0),
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

    temp_file = SESSION_FILE.with_suffix(".tmp")
    with open(temp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    temp_file.replace(SESSION_FILE)

    if verbose:
        print(f"[SessionManager] Saved {len(saved_windows)} windows to {SESSION_FILE}")
    return True


def restore_session(verbose=False):
    """Read saved session and relaunch applications in designated workspaces."""
    if not SESSION_FILE.exists():
        if verbose:
            print(f"[SessionManager] No session file found at {SESSION_FILE}")
        return False

    try:
        with open(SESSION_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[SessionManager] Error reading {SESSION_FILE}: {e}", file=sys.stderr)
        return False

    windows = data.get("windows", [])
    if not windows:
        if verbose:
            print("[SessionManager] Saved session contains 0 windows.")
        return False

    # Sort windows by workspace_id, then by focus_history_id (descending so last focused is opened last)
    windows.sort(key=lambda w: (w.get("workspace_id", 1), -w.get("focus_history_id", 0)))

    if verbose:
        print(f"[SessionManager] Restoring {len(windows)} windows...")

    if LOCK_FILE.exists():
        try:
            lock_age = time.time() - LOCK_FILE.stat().st_mtime
            if lock_age < 15:
                print("[SessionManager] Restore already in progress (lock active), skipping.")
                return False
        except Exception:
            pass

    try:
        LOCK_FILE.touch()
        for idx, win in enumerate(windows):
            ws_id = win.get("workspace_id", 1)
            cmd = win.get("command")
            is_floating = win.get("floating", False)

            if not cmd:
                continue

            exec_arg = f"[workspace {ws_id} silent] {cmd}"
            subprocess.run(["hyprctl", "dispatch", "exec", exec_arg], check=False)
            time.sleep(0.18)

        if verbose:
            print(f"[SessionManager] Successfully dispatched {len(windows)} applications.")
    finally:
        try:
            if LOCK_FILE.exists():
                LOCK_FILE.unlink()
        except Exception:
            pass

    return True


def run_daemon():
    """Background listener that debounces window events and keeps session.json up to date."""
    print("[SessionManager] Starting event daemon...")
    sock_path = get_hyprland_socket2_path()
    if not sock_path:
        print("[SessionManager] Hyprland socket2 not found, daemon exiting.", file=sys.stderr)
        sys.exit(1)

    save_session()
    debounce_delay = 5.0
    last_event_time = 0
    pending_save = False

    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(sock_path)
                s.settimeout(1.0)
                print(f"[SessionManager] Connected to Hyprland socket2: {sock_path}")

                while True:
                    try:
                        data = s.recv(4096)
                        if not data:
                            print("[SessionManager] Socket connection closed, reconnecting...")
                            break

                        events = data.decode("utf-8", errors="ignore").splitlines()
                        for ev in events:
                            if any(ev.startswith(k) for k in ("openwindow>>", "closewindow>>", "movewindow>>", "changefloatingmode>>")):
                                last_event_time = time.time()
                                pending_save = True

                    except socket.timeout:
                        if pending_save and (time.time() - last_event_time >= debounce_delay):
                            save_session()
                            pending_save = False

        except Exception as e:
            time.sleep(3)


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
        print("Usage: session_manager.py [save|restore|daemon|status]")
        sys.exit(1)

    cmd = sys.argv[1].lower()
    if cmd == "save":
        save_session(verbose=True)
    elif cmd == "restore":
        restore_session(verbose=True)
    elif cmd == "daemon":
        run_daemon()
    elif cmd == "status":
        print_status()
    else:
        print(f"Unknown command: {cmd}")
        print("Usage: session_manager.py [save|restore|daemon|status]")
        sys.exit(1)


if __name__ == "__main__":
    main()
