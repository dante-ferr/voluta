#!/usr/bin/env python3
"""Check update-only restart reminders without sending desktop notifications."""

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = runpy.run_path(str(ROOT / "dolphin/notify-restart.py"))


def check(ok, message):
    if not ok:
        raise SystemExit(f"FAIL: {message}")


def verify_detection(base):
    proc = base / "proc"
    proc.mkdir()
    library = base / "old-hook.so"
    library.write_bytes(b"old hook")
    old = library.stat()
    device = f"{os.major(old.st_dev):02x}:{os.minor(old.st_dev):02x}"

    def process(pid, executable, inode, suffix=""):
        path = proc / str(pid)
        path.mkdir(exist_ok=True)
        exe = path / "exe"
        exe.unlink(missing_ok=True)
        exe.symlink_to(executable)
        (path / "maps").write_text(f"1000-2000 r-xp 00000000 {device} {inode} {library}{suffix}\n")
        return path

    detect = lambda: FUNCTIONS["processes_using"](proc, old.st_dev, old.st_ino, os.getuid())
    process(10, "/usr/bin/bash", old.st_ino)
    check(not detect(), "shell launcher was treated as Dolphin")
    process(20, "/usr/bin/dolphin", old.st_ino + 1)
    check(not detect(), "Dolphin with another/current library was marked for restart")
    process(30, "/usr/bin/dolphin", 0)
    check(not detect(), "unwrapped Dolphin without a hook was marked for restart")
    real = process(20, "/usr/bin/dolphin", old.st_ino, " (deleted)")
    check(detect() == ["20"], "process mapping the replaced library was missed")

    notices = []
    notify = lambda: notices.append(True) or True
    state = base / "state"
    FUNCTIONS["notify_once"]("update-A", state, notify)
    FUNCTIONS["notify_once"]("update-A", state, notify)
    check(len(notices) == 1, "unchanged update produced repeated reminders")
    (real / "exe").unlink()
    process(21, "/usr/bin/dolphin", old.st_ino, " (deleted)")
    check(detect() == ["21"], "fixture failed to change the active process ID")
    FUNCTIONS["notify_once"]("update-A", state, notify)
    check(len(notices) == 1, "a new process ID repeated the same update reminder")
    FUNCTIONS["notify_once"]("update-B", state, notify)
    check(len(notices) == 2, "a genuinely new update could not notify")
    FUNCTIONS["notify_once"]("update-A", state, notify)
    check(len(notices) == 2, "returning to a known revision repeated its reminder")
    FUNCTIONS["notify_once"]("failed-notification", state, lambda: False)
    check("failed-notification" not in json.loads((state / "dolphin-restart.json").read_text())["revisions"],
          "failed desktop notification was recorded as delivered")
    (proc / "21/maps").write_text("")
    check(not detect(), "exiting process triggered a reminder")


def verify_build_triggers(base):
    code = base / "build-fixture"
    code.mkdir()
    for name in ("build.sh", "live.cpp"):
        shutil.copy2(ROOT / "dolphin" / name, code / name)
    # Record notification attempts without touching the notification service.
    (code / "notify-restart.py").write_text(
        "import json, os, sys\n"
        "with open(os.environ['NOTICE_LOG'], 'a') as handle:\n"
        "    handle.write(json.dumps(sys.argv[1:]) + '\\n')\n"
    )
    log = base / "notice-calls"
    env = dict(os.environ, HOME=str(base / "home"), NOTICE_LOG=str(log))
    command = ["bash", str(code / "build.sh")]
    subprocess.run(command, env=env, check=True)
    check(not log.exists(), "first build emitted a restart reminder")
    subprocess.run(command, env=env, check=True)
    check(not log.exists(), "unchanged build emitted a restart reminder")
    lib = base / "home/.local/lib/imperium/libdolphin-live.so"
    old = lib.stat()
    with (code / "live.cpp").open("a") as source:
        source.write("\n// regression fixture: a genuine source update\n")
    subprocess.run(command, env=env, check=True)
    calls = log.read_text().splitlines()
    check(len(calls) == 1, "successful replacement did not check exactly once")
    args = json.loads(calls[0])
    check(args[args.index("--previous-library") + 1] == f"{old.st_dev}:{old.st_ino}",
          "build did not identify the replaced library")
    stamp = lib.with_name(lib.name + ".sha256").read_text().strip()
    check(args[args.index("--revision") + 1] == stamp, "notification did not use the build fingerprint")
    subprocess.run(command, env=env, check=True)
    check(log.read_text().splitlines() == calls, "unchanged repeated launch attempted another notification")
    with (code / "live.cpp").open("a") as source:
        source.write("\n#error deliberate isolated failure\n")
    result = subprocess.run(command, env=env, capture_output=True)
    check(result.returncode != 0, "fixture did not reproduce a failed build")
    check(log.read_text().splitlines() == calls, "failed build emitted a restart reminder")


def main():
    with tempfile.TemporaryDirectory(prefix="dolphin-restart-check-") as temporary:
        base = Path(temporary)
        verify_detection(base)
        verify_build_triggers(base)
    print("PASS: reminders only after successful replacement, never for fresh/unchanged launches or new PIDs")


if __name__ == "__main__":
    main()
