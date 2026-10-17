#!/usr/bin/env python3
"""Check wallpaper resolution and Wallust selection without touching the desktop."""

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "hypr/UserScripts/combined_wallust.sh").read_text()
FUNCTIONS = SOURCE[SOURCE.index("expand_path() {"):SOURCE.index("# GTK resolves CSS")]
REFRESH = SOURCE[SOURCE.index("do_refresh() {"):SOURCE.index("# Let rapid per-monitor")]


with tempfile.TemporaryDirectory(prefix="check-wallust-") as directory:
    base = Path(directory)
    home = base / "home"
    cargo = home / ".cargo/bin"
    bins = base / "bin"
    cargo.mkdir(parents=True)
    bins.mkdir()

    def executable(path, body):
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    executable(bins / "wallust", 'echo "wallust 3.4.0"\n')
    executable(cargo / "wallust", '''if [[ "$1" == --version ]]; then
    echo "wallust 4.0.0-alpha"
else
    printf '%s\\n' "$@" >"$HOME/wallust-args"
    exit "${WALLUST_TEST_STATUS:-0}"
fi
''')
    executable(bins / "awww", 'printf "eDP-1: currently displaying: image: %s\\n" "$HOME/first image.jpg"\n')
    executable(bins / "swww", 'exit 1\n')
    first = home / "first image.jpg"
    second = home / "second.jpg"
    first.touch()
    second.touch()
    env = dict(os.environ, HOME=str(home), PATH=f"{bins}:/usr/bin:/bin", CARGO_HOME=str(home / ".cargo"))

    def run(body):
        return subprocess.run(["bash", "-c", FUNCTIONS + REFRESH + '''
get_active_monitors() { echo eDP-1; }
write_waybar_angel_css() { touch "$HOME/reloaded"; }
launch_waybar() { :; }
reload_hyprland() { :; }
finish_refresh() { :; }
LOCK_DIR="$HOME"
''' + body], env=env, text=True, capture_output=True, check=True)

    result = run('resolve_wallpapers "$HOME/first image.jpg" "$HOME/second.jpg"')
    assert result.stdout.splitlines() == [str(first), str(second)], result
    result = run('resolve_wallpapers')
    assert result.stdout.splitlines() == [str(first)], result
    run('do_refresh "$HOME/first image.jpg"')
    assert (home / "wallust-args").read_text().splitlines() == ["-q", "run", "-s", str(first)]
    assert (home / "reloaded").exists()
    (home / "reloaded").unlink()
    run('export WALLUST_TEST_STATUS=1; if do_refresh "$HOME/first image.jpg"; then exit 1; fi')
    assert not (home / "reloaded").exists(), "failed generation reloaded stale colors"
    (cargo / "wallust").unlink()
    run('if do_refresh "$HOME/first image.jpg"; then exit 1; fi')
    assert not (home / "reloaded").exists(), "v3 was accepted for a v4 config"

print("Wallust checks passed: queued images, live fallback, GUI PATH, and generation failures")
