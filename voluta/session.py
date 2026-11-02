#!/usr/bin/env python3
"""Supervise optional session saving; notice feature changes without a new login."""
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cli import ROOT, config_home, hostname, resolve


def enabled():
    settings, initialized = resolve(config_home(), hostname())
    return settings["features"]["session_restore"] if initialized else True


def main():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise RuntimeError("XDG_RUNTIME_DIR is required for the session supervisor")
    instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not instance or "/" in instance or instance in (".", ".."):
        raise RuntimeError("a valid compositor instance is required")
    lock_path = Path(runtime) / f"voluta-session-{instance}.lock"
    with lock_path.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        worker = None
        first = True
        previous_error = None
        def stop(*_):
            raise SystemExit(0)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        try:
            while True:
                if not (Path(runtime) / "hypr" / instance / ".socket2.sock").exists():
                    return
                try:
                    active = enabled()
                    previous_error = None
                except (OSError, ValueError, TypeError) as error:
                    message = str(error)
                    if message != previous_error:
                        print(f"Voluta session settings: {message}", file=sys.stderr, flush=True)
                    previous_error = message
                    active = False
                if worker is not None and worker.poll() is not None:
                    # Compositor teardown or a worker failure must not trigger
                    # repeated restores/restarts and overwrite a good snapshot.
                    return
                if active and worker is None:
                    command = "start" if first else "daemon"
                    worker = subprocess.Popen([
                        sys.executable, str(ROOT / "hypr/scripts/session_manager.py"), command,
                    ], start_new_session=True)
                elif not active and worker is not None:
                    worker.terminate()
                    worker.wait(timeout=10)
                    worker = None
                first = False
                time.sleep(1)
        finally:
            if worker is not None and worker.poll() is None:
                worker.terminate()
                try:
                    worker.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    worker.kill()
                    worker.wait()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(f"Voluta session supervisor: {error}", file=sys.stderr)
        raise SystemExit(1)
