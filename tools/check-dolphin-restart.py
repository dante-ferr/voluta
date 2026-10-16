#!/usr/bin/env python3
"""Check restart detection without opening apps or sending notifications."""

import os
from pathlib import Path
import runpy
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = runpy.run_path(str(ROOT / "dolphin/notify-restart.py"))


def check(ok, message):
    if not ok:
        raise SystemExit(f"FAIL: {message}")


def main():
    with tempfile.TemporaryDirectory(prefix="dolphin-restart-check-") as temporary:
        base = Path(temporary)
        proc = base / "proc"
        proc.mkdir()
        library = base / "libdolphin-live.so"
        library.write_bytes(b"fixture hook")
        current = library.stat()
        device = f"{os.major(current.st_dev):02x}:{os.minor(current.st_dev):02x}"

        def process(pid, executable, mapping, start="100"):
            path = proc / str(pid)
            path.mkdir(exist_ok=True)
            exe = path / "exe"
            exe.unlink(missing_ok=True)
            exe.symlink_to(executable)
            (path / "maps").write_text(mapping)
            (path / "stat").write_text(f"{pid} (dolphin) " + " ".join(["S"] + ["0"] * 18 + [start]))
            return path

        def mapping(inode=current.st_ino, suffix="", path=library):
            return f"1000-2000 r-xp 00000000 {device} {inode} {path}{suffix}\n"

        # This is the regression: the launcher's comm can be dolphin, but its
        # executable is bash and it must never be diagnosed as uncustomized.
        process(10, "/usr/bin/bash", mapping(path=Path("/usr/bin/bash")))
        detect = lambda: FUNCTIONS["stale_processes"](proc, library, os.getuid())
        check(not detect(), "shell launcher caused a false restart warning")
        process(20, "/usr/bin/dolphin", mapping())
        check(not detect(), "current hook caused a restart warning")

        real = process(20, "/usr/bin/dolphin", mapping(current.st_ino + 1, " (deleted)"))
        stale = detect()
        check(len(stale) == 1, "deleted old hook was not detected")
        notices = []
        notify = lambda: notices.append(True) or True
        state = base / "state"
        FUNCTIONS["notify_once"](stale, state, notify)
        FUNCTIONS["notify_once"](stale, state, notify)
        check(len(notices) == 1, "unchanged stale process produced repeated warnings")
        process(20, "/usr/bin/dolphin", mapping(current.st_ino + 1), start="200")
        FUNCTIONS["notify_once"](detect(), state, notify)
        check(len(notices) == 2, "reused PID was mistaken for an already-notified process")

        # Same path text with another inode is still stale; grep cannot tell.
        check(detect(), "same path with an old inode was treated as current")
        (real / "maps").write_text(mapping(path=Path("/usr/bin/dolphin")))
        check(detect(), "real Dolphin without the hook was not detected")
        (real / "maps").write_text(mapping())
        check(not detect(), "restarted Dolphin with the current hook was still stale")
        (real / "maps").write_text("")
        check(not detect(), "exiting Dolphin triggered a restart notice")
        (real / "exe").unlink()
        check(not detect(), "vanished process triggered a restart notice")
    print("PASS: shell wrapper ignored, current/stale hooks distinguished, notices deduplicated and exiting processes ignored")


if __name__ == "__main__":
    main()
