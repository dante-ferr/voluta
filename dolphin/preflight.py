#!/usr/bin/env python3
"""Print Dolphin launch settings and apply tracked config in one process."""

import importlib.util
import os
from pathlib import Path
import socket
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "voluta"))
from cli import resolve  # noqa: E402


def main():
    directory = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "voluta"
    settings, initialized = resolve(directory, socket.gethostname())
    legacy = "--legacy" in sys.argv[1:]
    enabled = settings["features"]["dolphin"] if initialized or not legacy else True
    print("enabled" if enabled else "disabled")
    print("rhi" if enabled and settings.get("dolphin_rhi") else "none")
    if not enabled:
        return
    spec = importlib.util.spec_from_file_location(
        "dolphin_apply_config", Path(__file__).with_name("apply-config.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.main(["--if-unchanged"])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError):
        print("enabled")
        print("none")
