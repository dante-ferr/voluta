#!/usr/bin/env python3
"""Enable the Voluta theme and window transparency in Vesktop's Vencord settings.

Vesktop has no toggle for window transparency on Linux, so this edits
`~/.config/vesktop/settings/settings.json`. It changes only `enabledThemes` and
`transparent`, keeps every other key, and refuses to run while Vesktop is open
because Vesktop rewrites the file on exit.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

THEME = "voluta.theme.css"


def settings_path():
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config / "vesktop/settings/settings.json"


def vesktop_running():
    return subprocess.run(["pgrep", "-x", "vesktop"], stdout=subprocess.DEVNULL).returncode == 0


def write_flags():
    """Run Electron natively on Wayland; XWayland windows rarely get an alpha channel."""
    flags = settings_path().parents[1] / "vesktop-flags.conf"
    if flags.exists():
        return False
    flags.write_text("--ozone-platform=wayland\n--enable-features=WaylandWindowDecorations\n")
    return True


def apply(settings):
    themes = list(settings.get("enabledThemes", []))
    if THEME not in themes:
        themes.append(THEME)
    updated = dict(settings, enabledThemes=themes, transparent=True)
    return updated, updated != settings


def main():
    path = settings_path()
    if not path.parent.is_dir():
        print("Vesktop has no settings yet. Start Vesktop once, close it, and rerun.", file=sys.stderr)
        return 1
    if vesktop_running():
        print("Vesktop is running. Close it fully (including the tray icon) and rerun.", file=sys.stderr)
        return 1
    settings = json.loads(path.read_text()) if path.is_file() else {}
    updated, changed = apply(settings)
    if write_flags():
        print("Wrote ~/.config/vesktop/vesktop-flags.conf (native Wayland).")
    if not changed:
        print("Vesktop already uses voluta.theme.css with transparency.")
        return 0
    if path.is_file():
        path.with_suffix(".json.voluta-backup").write_text(path.read_text())
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(updated, indent=4) + "\n")
    temporary.replace(path)
    print("Enabled voluta.theme.css and transparent window. Start Vesktop to see the result.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
