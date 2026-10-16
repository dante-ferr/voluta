#!/usr/bin/env python3
"""Apply tracked Dolphin appearance keys without sharing machine/session state."""

import argparse
import configparser
import fcntl
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    args = parser.parse_args()
    # --home is also used by the isolated theme checks.
    home = args.home
    state = home / ".local/state/imperium"
    state.mkdir(parents=True, exist_ok=True)
    with (state / "dolphin-config.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        apply(ROOT / "dolphinrc", home / ".config/dolphinrc")
        apply(ROOT / "dolphin/view-properties",
              home / ".local/share/dolphin/view_properties/global/.directory")
        # KXMLGUI reads the user override here, independently of dolphinrc.
        ui = home / ".local/share/kxmlgui5/dolphin/dolphinui.rc"
        ui.parent.mkdir(parents=True, exist_ok=True)
        source = ROOT / "dolphin/dolphinui.rc"
        if ui.is_symlink() and ui.resolve() == source:
            return
        if ui.exists() and not ui.is_symlink():
            backup = ui.with_name(ui.name + ".pre-imperium")
            if not backup.exists():
                backup.write_bytes(ui.read_bytes())
        ui.unlink(missing_ok=True)
        ui.symlink_to(source)


if __name__ == "__main__":
    main()
