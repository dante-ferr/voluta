#!/usr/bin/env python3
"""Exercise package installation and apply failures with fake package managers."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def check(ok, message):
    if not ok:
        raise SystemExit(f"FAIL: {message}")


def executable(path, code):
    path.write_text("#!/bin/bash\n" + code)
    path.chmod(0o755)


def main():
    with tempfile.TemporaryDirectory(prefix="imperium-deps-check-") as temporary:
        base = Path(temporary)
        binaries = base / "bin"
        binaries.mkdir()
        for name in ("bash", "dirname", "readlink", "mktemp", "tee", "rm", "grep", "python3"):
            (binaries / name).symlink_to(shutil.which(name))
        installed, calls = base / "installed", base / "calls"
        installed.write_text("")
        calls.write_text("")
        executable(binaries / "pacman", '''
case "$1" in
    -Q) grep -Fxq "$2" "$FIXTURE_INSTALLED" ;;
    -Si) [[ "$2" != *-git ]] ;;
    -S) printf '%s\\n' "$*" >>"$FIXTURE_CALLS"
        pkg=${@: -1}
        [[ "$pkg" == "${FIXTURE_FAIL:-}" ]] && exit 1
        printf '%s\\n' "$pkg" >>"$FIXTURE_INSTALLED" ;;
    *) exit 2 ;;
esac
''')
        executable(binaries / "paru", 'exec pacman "$@"\n')
        executable(binaries / "sudo", 'exec "$@"\n')
        executable(binaries / "notify-send", 'exit 0\n')
        executable(binaries / "kitty", '''
printf 'kitty\\n' >>"$FIXTURE_CALLS"
while [[ "$1" != -e ]]; do shift; done
shift
exec "$@"
''')
        env = dict(os.environ, PATH=str(binaries), HOME=str(base / "home"),
                   FIXTURE_INSTALLED=str(installed), FIXTURE_CALLS=str(calls),
                   WAYLAND_DISPLAY="", DISPLAY="")
        child = base / "child.txt"
        child.write_text("fixture-font\nfixture-existing-git|fixture-existing\n")
        manifest = base / "packages.txt"
        manifest.write_text("# fixture\n@include child.txt\nfixture-tool\n")
        installed.write_text("fixture-existing\n")

        def run(environment=env, command=None):
            if command is None:
                command = ["bash", "-c", 'set -euo pipefail; source "$1"; ensure_arch_packages "$2" Fixture',
                           "check", str(ROOT / "deps/packages.sh"), str(manifest)]
            result = subprocess.run(command, env=environment, text=True, capture_output=True)
            # Failed runs retain diagnostic logs; clean up these test-owned logs.
            for log in re.findall(r"Log: (/tmp/imperium-deps-[\w.-]+)", result.stderr):
                Path(log).unlink(missing_ok=True)
            return result

        result = run()
        check(result.returncode == 0, f"missing package install failed: {result.stderr}")
        check(installed.read_text().splitlines() == ["fixture-existing", "fixture-font", "fixture-tool"],
              "include, missing font, or installed alternative was mishandled")
        first_calls = calls.read_text()
        check(run().returncode == 0 and calls.read_text() == first_calls,
              "installed dependencies triggered another install")

        installed.write_text("fixture-existing\n")
        result = run(dict(env, FIXTURE_FAIL="fixture-font"))
        check(result.returncode != 0 and "fixture-font" in result.stderr,
              "failed font install was treated as success")

        # Installer exit status is not enough: a sudo timeout after packages
        # land must still let Dolphin apply continue and regenerate icons.
        installed.write_text("fixture-existing\n")
        calls.write_text("")
        executable(binaries / "pacman", '''
case "$1" in
    -Q) grep -Fxq "$2" "$FIXTURE_INSTALLED" ;;
    -Si) [[ "$2" != *-git ]] ;;
    -S) printf '%s\\n' "$*" >>"$FIXTURE_CALLS"
        pkg=${@: -1}
        printf '%s\\n' "$pkg" >>"$FIXTURE_INSTALLED"
        exit 1 ;;
    *) exit 2 ;;
esac
''')
        result = run()
        check(result.returncode == 0, f"installed packages still blocked apply: {result.stderr}")
        check("ignoring installer exit status" in result.stderr,
              "false installer failure was not reported")
        executable(binaries / "pacman", '''
case "$1" in
    -Q) grep -Fxq "$2" "$FIXTURE_INSTALLED" ;;
    -Si) [[ "$2" != *-git ]] ;;
    -S) printf '%s\\n' "$*" >>"$FIXTURE_CALLS"
        pkg=${@: -1}
        [[ "$pkg" == "${FIXTURE_FAIL:-}" ]] && exit 1
        printf '%s\\n' "$pkg" >>"$FIXTURE_INSTALLED" ;;
    *) exit 2 ;;
esac
''')

        # A graphical refresh needs a terminal for sudo/paru authentication.
        installed.write_text("fixture-existing\n")
        calls.write_text("")
        check(run(dict(env, WAYLAND_DISPLAY="fixture-wayland")).returncode == 0,
              "graphical installer failed")
        check("kitty\n" in calls.read_text(), "graphical installer did not open a terminal")

        # All Dolphin dependencies are missing in this fixture. Fail the font
        # install and ensure apply stops before touching configs or opening apps.
        installed.write_text("")
        result = run(dict(env, FIXTURE_FAIL="otf-monaspace"),
                     ["bash", str(ROOT / "dolphin/apply.sh")])
        check(result.returncode != 0 and "otf-monaspace" in result.stderr,
              "Dolphin apply did not propagate its missing font failure")
        check(not (base / "home/.config").exists(), "failed apply wrote appearance files")

        # Official packages still install without an AUR helper; repository
        # alternatives must be selected instead of their -git names.
        (binaries / "paru").unlink()
        installed.write_text("")
        manifest.write_text("fixture-tool-git|fixture-tool\nfixture-font\n")
        calls.write_text("")
        check(run().returncode == 0, "pacman fallback failed without paru")
        check(installed.read_text().splitlines() == ["fixture-tool", "fixture-font"],
              "pacman fallback selected an unavailable AUR alternative")
    print("PASS: missing font installation, alternatives/includes, repeat apply, failure propagation, false installer failure, GUI terminal and pacman fallback")


if __name__ == "__main__":
    main()
