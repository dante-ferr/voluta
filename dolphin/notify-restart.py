#!/usr/bin/env python3
"""Notify once per successful hook update when Dolphin still maps the old file."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile


def processes_using(proc, device, inode, uid):
    users = []
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
            for line in mappings:
                fields = line.split(maxsplit=5)
                if len(fields) != 6:
                    continue
                major, minor = (int(part, 16) for part in fields[3].split(":"))
                if os.makedev(major, minor) == device and int(fields[4]) == inode:
                    # Paths can change or acquire " (deleted)" on replacement.
                    # Only the actual file identity proves this app uses it.
                    users.append(process.name)
                    break
        except (OSError, ValueError, IndexError):
            # Processes can exit or exec between reads. Unknown is not stale.
            continue
    return users


def notify_once(revision, state, notify):
    state.mkdir(parents=True, exist_ok=True)
    with (state / "dolphin-restart.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        marker = state / "dolphin-restart.json"
        try:
            previous = json.loads(marker.read_text())["revisions"]
            if not isinstance(previous, list) or not all(isinstance(item, str) for item in previous):
                previous = []
        except (OSError, ValueError, TypeError, KeyError):
            # Older versions stored PID/inode tokens in a JSON list.
            previous = []
        if revision in previous:
            return
        if not notify():
            return
        # Deduplicate by code update, not PID. Restarting an unwrapped Dolphin
        # or changing its process ID cannot create another reminder.
        with tempfile.NamedTemporaryFile(mode="w", dir=state, delete=False) as handle:
            json.dump({"revisions": previous[-63:] + [revision]}, handle)
        os.replace(handle.name, marker)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous-library", required=True, help="device:inode of the replaced hook")
    parser.add_argument("--revision", required=True, help="successful build fingerprint")
    args = parser.parse_args()
    device, inode = map(int, args.previous_library.split(":"))
    home = Path.home()
    if not processes_using(Path("/proc"), device, inode, os.getuid()):
        return

    def notify():
        try:
            return subprocess.run([
                "notify-send", "Dolphin restart needed",
                "Fully quit Dolphin, then reopen it to load the current Imperium customization.",
            ], check=False).returncode == 0
        except OSError:
            return False

    notify_once(args.revision, home / ".local/state/imperium", notify)


if __name__ == "__main__":
    main()
