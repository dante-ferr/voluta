#!/usr/bin/env python3
"""Notify once when a real Dolphin process is using an outdated/missing hook."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile


def stale_processes(proc, library, uid):
    try:
        current = library.stat()
    except FileNotFoundError:
        return []
    stale = []
    for process in proc.iterdir():
        if not process.name.isdecimal():
            continue
        try:
            if process.stat().st_uid != uid:
                continue
            # A bash script invoked through ~/.local/bin/dolphin also has the
            # comm name "dolphin". Only inspect the actual application binary.
            executable = os.readlink(process / "exe").removesuffix(" (deleted)")
            if executable != "/usr/bin/dolphin":
                continue
            mappings = (process / "maps").read_text().splitlines()
            if not mappings:  # Already exiting; no application to restart.
                continue
            loaded = False
            for line in mappings:
                fields = line.split(maxsplit=5)
                if len(fields) != 6 or fields[5] != str(library):
                    continue
                major, minor = (int(part, 16) for part in fields[3].split(":"))
                if os.makedev(major, minor) == current.st_dev and int(fields[4]) == current.st_ino:
                    loaded = True
                    break
            if not loaded:
                # PID plus kernel start time distinguishes reused process IDs.
                start = (process / "stat").read_text().rsplit(")", 1)[1].split()[19]
                stale.append(f"{process.name}:{start}:{current.st_dev}:{current.st_ino}")
        except (OSError, ValueError, IndexError):
            # Processes can exit or exec between reads. Unknown is not stale.
            continue
    return stale


def notify_once(stale, state, notify):
    if not stale:
        return
    state.mkdir(parents=True, exist_ok=True)
    with (state / "dolphin-restart.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        marker = state / "dolphin-restart.json"
        try:
            previous = set(json.loads(marker.read_text()))
        except (OSError, ValueError, TypeError):
            previous = set()
        if set(stale) <= previous:
            return
        if not notify():
            return
        # Only retain currently stale processes; the file stays bounded.
        with tempfile.NamedTemporaryFile(mode="w", dir=state, delete=False) as handle:
            json.dump(stale, handle)
        os.replace(handle.name, marker)


def main():
    home = Path.home()
    library = home / ".local/lib/imperium/libdolphin-live.so"

    def notify():
        try:
            return subprocess.run([
                "notify-send", "Dolphin restart needed",
                "Fully quit Dolphin, then reopen it to load the current Imperium customization.",
            ], check=False).returncode == 0
        except OSError:
            return False

    notify_once(stale_processes(Path("/proc"), library, os.getuid()),
                home / ".local/state/imperium", notify)


if __name__ == "__main__":
    main()
