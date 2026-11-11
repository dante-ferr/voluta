#!/usr/bin/env python3
"""Publish Wallust's Chromium GTK colors and notify running browsers."""

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "voluta"))
from theme import preferred_background, read_palette


LEGACY_THEMES = ("Imperium-Wallust-A", "Imperium-Wallust-B")


def managed_theme(name):
    return bool(name and (name in LEGACY_THEMES or re.fullmatch(r"Imperium-Wallust-[a-f0-9]{16}", name)))
HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "imperium/brave-theme.json"


def command(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=5)
    if result.returncode:
        raise RuntimeError(f"{args[0]} {args[1]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def settings(version):
    path = CONFIG / f"gtk-{version}.0/settings.ini"
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    if path.exists():
        parser.read(path)
    if not parser.has_section("Settings"):
        parser.add_section("Settings")
    return path, parser


def base_css(name, version, dark):
    # Import the original theme, so non-Chromium applications retain their style.
    roots = [DATA / "themes", HOME / ".themes"]
    roots += [Path(p) / "themes" for p in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")]
    if name and not managed_theme(name) and "/" not in name:
        for root in roots:
            directory = root / name / f"gtk-{version}.0"
            for filename in (("gtk-dark.css", "gtk.css") if dark else ("gtk.css",)):
                path = directory / filename
                if path.is_file():
                    return path.resolve().as_uri()
    family = "Adwaita" if version == 3 else "Default"
    filename = "gtk-dark.css" if dark else "gtk.css"
    return f"resource:///org/gtk/libgtk/theme/{family}/{filename}"


def dolphin_background(css):
    """Consume the shared Voluta background policy, including host overrides."""
    source = re.search(r"@define-color imperium_source_bg #([0-9a-fA-F]{6});", css)
    if source is None:
        return css
    value = source[1]
    shell = CONFIG / "hypr/wallust/colors-shell.sh"
    palette = read_palette(shell) if shell.exists() else {"bg": tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))}
    color = "#" + "".join(f"{c:02x}" for c in preferred_background(palette, CONFIG / "voluta"))
    return re.sub(r"(@define-color imperium_bg )#[0-9a-fA-F]{6};", rf"\g<1>{color};", css)


def darker_mode_enabled():
    """Brave Ultra/Darker theme remaps GTK lightness away from the shared ink."""
    preferences = CONFIG / "BraveSoftware/Brave-Browser/Default/Preferences"
    if not preferences.is_file():
        return False
    try:
        return bool(json.loads(preferences.read_text()).get("brave", {}).get("darker_mode"))
    except (OSError, json.JSONDecodeError, TypeError):
        return False


def warn_darker_mode():
    message = (
        "Brave Ultra dark / Darker theme is on; turn it off under "
        "brave://settings/appearance so the toolbar matches Dolphin"
    )
    print(f"Brave theme: {message}", file=sys.stderr)
    if shutil.which("notify-send"):
        subprocess.run(
            ["notify-send", "Voluta Brave theme", message],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render-only", action="store_true", help="write themes without changing settings or contacting the session")
    args = parser.parse_args()
    palette = CONFIG / "hypr/wallust/colors-gtk.css"
    if not palette.is_file():
        raise SystemExit("Brave theme: run Wallust first (colors-gtk.css is missing)")
    css = palette.read_text()
    if "{{" in css or not re.search(r"@define-color imperium_bg #[0-9a-fA-F]{6};", css):
        raise SystemExit("Brave theme: refusing an unrendered or invalid palette")
    css = dolphin_background(css)
    if not args.render_only and darker_mode_enabled():
        warn_darker_mode()

    # Use the distro's GSettings alongside the distro's GTK/portal libraries.
    gsettings = "/usr/bin/gsettings" if Path("/usr/bin/gsettings").exists() else shutil.which("gsettings")
    current = None
    if not args.render_only:
        if not gsettings:
            raise SystemExit("Brave theme: gsettings is required")
        current = command(gsettings, "get", "org.gnome.desktop.interface", "gtk-theme").strip("'")
    previous = json.loads(STATE.read_text()) if STATE.exists() else {}
    original = previous.get("original", {})
    if current and not managed_theme(current):
        original["gsettings"] = current
    # GTK keeps named CSS providers in-process. Reusing A/B names can bring
    # back old paints even after their files have changed. A content-derived
    # name makes each palette immutable from the consumer's point of view.
    target = "Imperium-Wallust-" + hashlib.sha256(css.encode()).hexdigest()[:16]

    # Persist originals before changing the session, including on an interrupted
    # first application. Backups also recover earlier partially applied setups.
    for version in (3, 4):
        path, config = settings(version)
        name = config.get("Settings", "gtk-theme-name", fallback="")
        backup = path.with_suffix(".ini.pre-imperium-brave")
        if managed_theme(name) and str(version) not in original and backup.exists():
            saved = configparser.ConfigParser(interpolation=None)
            saved.read(backup)
            name = saved.get("Settings", "gtk-theme-name", fallback="")
        if not managed_theme(name):
            original[str(version)] = name
    if managed_theme(current) and "gsettings" not in original:
        original["gsettings"] = original.get("3", "Adwaita")
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"active": previous.get("active"), "original": original}, indent=2) + "\n")

    for version in (3, 4):
        path, config = settings(version)
        name = config.get("Settings", "gtk-theme-name", fallback="")
        if not managed_theme(name):
            original[str(version)] = name
        directory = DATA / "themes" / target / f"gtk-{version}.0"
        directory.mkdir(parents=True, exist_ok=True)
        for dark, filename in ((False, "gtk.css"), (True, "gtk-dark.css")):
            uri = base_css(original.get(str(version)) or original.get("gsettings"), version, dark)
            contents = f'@import url("{uri}");\n' + css
            temporary = directory / (filename + ".tmp")
            temporary.write_text(contents)
            temporary.replace(directory / filename)
        if not args.render_only:
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists() and not path.with_suffix(".ini.pre-imperium-brave").exists():
                shutil.copy2(path, path.with_suffix(".ini.pre-imperium-brave"))
            config.set("Settings", "gtk-theme-name", target)
            with path.open("w") as handle:
                config.write(handle)

    if not args.render_only:
        command(gsettings, "set", "org.gnome.desktop.interface", "gtk-theme", target)
        # GTK on XWayland consumes XSettings; native Wayland consumes the portal.
        if os.environ.get("DISPLAY") and shutil.which("xsettingsd"):
            path = CONFIG / "xsettingsd/xsettingsd.conf"
            # Older rices can leave a dangling directory symlink. Keep it as a
            # backup rather than writing into the removed rice's directory.
            if path.parent.is_symlink() and not path.parent.exists():
                path.parent.rename(path.parent.with_name("xsettingsd.pre-imperium-brave"))
            path.parent.mkdir(parents=True, exist_ok=True)
            text = path.read_text() if path.exists() else ""
            if path.exists() and not path.with_suffix(".conf.pre-imperium-brave").exists():
                shutil.copy2(path, path.with_suffix(".conf.pre-imperium-brave"))
            line = f'Net/ThemeName "{target}"'
            pattern = r'^\s*Net/ThemeName\s+.*$'
            if re.search(pattern, text, re.M):
                text = re.sub(pattern, line, text, flags=re.M)
            else:
                text = text.rstrip() + "\n" + line + "\n"
            path.write_text(text)
            result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "xsettingsd"], capture_output=True, text=True)
            if result.returncode == 0:
                for pid in result.stdout.split():
                    try:
                        os.kill(int(pid), signal.SIGHUP)
                    except ProcessLookupError:
                        pass
            else:
                subprocess.Popen(["xsettingsd", "--config", str(path)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"active": target, "original": original}, indent=2) + "\n")
    if not args.render_only:
        project = Path(os.environ.get("PRISMWING_PROJECT_DIR", HOME / "Code/projects/prismwing"))
        installer = project / "install.py"
        if installer.is_file():
            subprocess.run([sys.executable, str(installer), "--quiet"], check=True,
                           env={**os.environ, "XDG_CONFIG_HOME": str(CONFIG)})
    print(f"Brave GTK colors: {target}" + (" (render only)" if args.render_only else ""))


if __name__ == "__main__":
    main()
