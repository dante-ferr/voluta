#!/usr/bin/env python3
"""Apply tracked Dolphin appearance keys without sharing machine/session state."""

import argparse
import configparser
import fcntl
import hashlib
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def read_config(path):
    config = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",))
    config.optionxform = str
    if path.exists():
        config.read(path, encoding="utf-8")
    return config


def apply(source, destination):
    # The deployed tree does not carry these baselines; only a real checkout does.
    if not source.is_file():
        return
    baseline = read_config(source)
    current = read_config(destination)
    for section in baseline.sections():
        if not current.has_section(section):
            current.add_section(section)
        for key, value in baseline.items(section):
            current.set(section, key, value)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Replace old symlinks with real local files: Dolphin must never write its
    # window state back into the tracked baseline. Keep the original once.
    backup = destination.with_name(destination.name + ".pre-imperium")
    if destination.exists() and not backup.exists():
        backup.write_bytes(destination.read_bytes())
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination.parent,
                                         delete=False) as handle:
            temporary = Path(handle.name)
            current.write(handle, space_around_delimiters=False)
        if destination.is_symlink() or not destination.exists() or temporary.read_bytes() != destination.read_bytes():
            os.replace(temporary, destination)
        else:
            temporary.unlink()
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def tracked_inputs():
    sources = (ROOT / "dolphinrc", ROOT / "dolphin/view-properties", ROOT / "dolphin/dolphinui.rc")
    parts = []
    for path in sources:
        if not path.is_file():
            return None
        stat = path.stat()
        parts.append(f"{path}:{stat.st_mtime_ns}:{stat.st_size}")
    return hashlib.sha256(("\n".join(parts) + "\n").encode()).hexdigest()


def is_current(home, stamp_path):
    digest = tracked_inputs()
    if digest is None or not stamp_path.is_file():
        return False
    ui = home / ".local/share/kxmlgui5/dolphin/dolphinui.rc"
    try:
        ui_ok = ui.is_symlink() and ui.resolve() == (ROOT / "dolphin/dolphinui.rc").resolve()
    except OSError:
        ui_ok = False
    return ui_ok and stamp_path.read_text(encoding="utf-8") == digest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--if-unchanged", action="store_true",
                        help="skip work when tracked baselines are already applied")
    args = parser.parse_args(argv)
    # --home is also used by the isolated theme checks.
    home = args.home
    state = home / ".local/state/imperium"
    state.mkdir(parents=True, exist_ok=True)
    stamp_path = state / "dolphin-config.stamp"
    if args.if_unchanged and is_current(home, stamp_path):
        return
    with (state / "dolphin-config.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.if_unchanged and is_current(home, stamp_path):
            return
        apply(ROOT / "dolphinrc", home / ".config/dolphinrc")
        apply(ROOT / "dolphin/view-properties",
              home / ".local/share/dolphin/view_properties/global/.directory")
        # KXMLGUI reads the user override here, independently of dolphinrc.
        ui = home / ".local/share/kxmlgui5/dolphin/dolphinui.rc"
        ui.parent.mkdir(parents=True, exist_ok=True)
        source = ROOT / "dolphin/dolphinui.rc"
        if not (ui.is_symlink() and ui.resolve() == source):
            if ui.exists() and not ui.is_symlink():
                backup = ui.with_name(ui.name + ".pre-imperium")
                if not backup.exists():
                    backup.write_bytes(ui.read_bytes())
            ui.unlink(missing_ok=True)
            ui.symlink_to(source)
        digest = tracked_inputs()
        if digest is not None:
            stamp_path.write_text(digest, encoding="utf-8")


if __name__ == "__main__":
    main()
