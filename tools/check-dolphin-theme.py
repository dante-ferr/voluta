#!/usr/bin/env python3
"""Focused, isolated checks for Dolphin wallust theme generation."""

from __future__ import annotations

import ast
import configparser
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "hypr/UserScripts/paint_dolphin_theme.sh"
ICON_SOURCE = "/usr/share/icons/breeze-dark"
TIERS = ("normal", "large", "x-large", "xx-large")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def generator_python() -> str:
    shell = GENERATOR.read_text(encoding="utf-8")
    match = re.search(r"^exec python3 - \"\$root\".*?<<'PY'\n(.*?)^PY$", shell, re.M | re.S)
    check(match is not None, "could not find embedded theme generator")
    return match.group(1).replace(ICON_SOURCE, "__TEST_ICON_SOURCE__")


def verify_worker_selection(base: Path) -> None:
    # Exercise the process selector without sending a signal to any process.
    definition = next(node for node in ast.parse(generator_python()).body
                      if isinstance(node, ast.FunctionDef) and node.name == "session_thumbnail_worker")
    scope = {"os": os}
    exec(compile(ast.Module(body=[definition], type_ignores=[]), str(GENERATOR), "exec"), scope)
    matches = scope["session_thumbnail_worker"]
    base.mkdir()
    (base / "exe").symlink_to("/usr/lib/kf6/kioworker")
    thumbnail = b"/usr/lib/kf6/kioworker\0/usr/lib/qt6/plugins/kf6/kio/thumbnail.so\0"
    (base / "cmdline").write_bytes(thumbnail)
    (base / "environ").write_bytes(b"DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/test-bus,guid=123\0")
    check(matches(str(base), "unix:path=/tmp/test-bus"), "thumbnail worker on this session was not selected")
    check(not matches(str(base), "unix:path=/tmp/another-bus"), "another session's worker was selected")
    (base / "cmdline").write_bytes(thumbnail.replace(b"thumbnail.so", b"file.so"))
    check(not matches(str(base), "unix:path=/tmp/test-bus"), "file-transfer worker was selected")
    (base / "cmdline").write_bytes(thumbnail)
    (base / "exe").unlink()
    (base / "exe").symlink_to("/usr/bin/dolphin")
    check(not matches(str(base), "unix:path=/tmp/test-bus"), "application process was selected")
    check(not matches(str(base / "missing"), "unix:path=/tmp/test-bus"), "vanished process was selected")


def png_with_text(key: str, value: str) -> bytes:
    def chunk(name: bytes, payload: bytes) -> bytes:
        body = name + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"tEXt", key.encode("latin-1") + b"\0" + value.encode("latin-1"))
        + chunk(b"IDAT", b"")
        + chunk(b"IEND", b"")
    )


def add_cached_thumbnail(cache: Path, name: str, uri: str, tier: str = "normal") -> Path:
    path = cache / "thumbnails" / tier / f"{name}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png_with_text("Thumb::URI", uri))
    return path


def write_palette(path: Path, colors: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(f"wc_{key}='{value.lstrip('#')}'\n" for key, value in colors.items()),
        encoding="utf-8",
    )


def run_generator(home: Path, cache: Path, icon_source: Path, palette: Path | None) -> None:
    code = generator_python().replace("__TEST_ICON_SOURCE__", str(icon_source))
    env = os.environ.copy()
    env.update(
        HOME=str(home),
        XDG_CONFIG_HOME=str(home / ".config"),
        XDG_CACHE_HOME=str(cache),
        DBUS_SESSION_BUS_ADDRESS=f"unix:path={home / 'no-session-bus'}",
    )
    colors_path = palette if palette is not None else home / "missing-colors-shell.sh"
    result = subprocess.run(
        [sys.executable, "-c", code, str(ROOT), str(colors_path), str(home)],
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    check(result.returncode == 0, "theme generator failed in isolated home")


def read_ansi(
    path: Path,
) -> tuple[
    tuple[int, int, int],
    tuple[int, int, int],
    dict[tuple[int, str], tuple[int, int, int]],
    dict[str, tuple[int, int, int]],
]:
    section = ""
    background = None
    foreground = None
    ansi: dict[tuple[int, str], tuple[int, int, int]] = {}
    terminal_backgrounds: dict[str, tuple[int, int, int]] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("[") and raw.endswith("]"):
            section = raw[1:-1]
            continue
        key, separator, value = raw.partition("=")
        if not separator or key != "Color":
            continue
        try:
            color = tuple(int(channel) for channel in value.split(","))
        except ValueError:
            continue
        if section == "Background":
            background = color
            terminal_backgrounds[section] = color
        elif section in ("BackgroundIntense", "BackgroundFaint"):
            terminal_backgrounds[section] = color
        elif section == "Foreground":
            foreground = color
        else:
            match = re.fullmatch(r"Color([0-7])(Intense|Faint)?", section)
            if match:
                ansi[(int(match.group(1)), match.group(2) or "normal")] = color
    check(background is not None and foreground is not None, "could not read generated terminal colors")
    return background, foreground, ansi, terminal_backgrounds  # type: ignore[return-value]


def contrast(a: tuple[int, ...], b: tuple[int, ...]) -> float:
    def luminance(color: tuple[int, ...]) -> float:
        def channel(value: int) -> float:
            unit = value / 255
            return unit / 12.92 if unit <= 0.04045 else ((unit + 0.055) / 1.055) ** 2.4

        return sum(weight * channel(value) for weight, value in zip((0.2126, 0.7152, 0.0722), color))

    light, dark = sorted((luminance(a), luminance(b)), reverse=True)
    return (light + 0.05) / (dark + 0.05)


def dolphin_background(value: str) -> str:
    color = tuple(int(value.lstrip("#")[i : i + 2], 16) for i in (0, 2, 4))
    darkened = tuple(round(channel * 0.65) for channel in color)
    return "#" + "".join(f"{channel:02x}" for channel in darkened)


def verify_colors(home: Path, expected_bg: str, label: str) -> None:
    config = home / ".local/share/konsole/Imperium.colorscheme"
    background, foreground, ansi, terminal_backgrounds = read_ansi(config)
    marker = dict(line.split("=", 1) for line in (home / ".config/qt6ct/dolphin-live.conf").read_text().splitlines())
    terminal = marker.get("terminal", "")
    check(bool(re.fullmatch(r"dolphin-terminal-live-\d+", terminal)), f"{label}: missing live terminal profile")
    konsole = home / ".local/share/konsole"
    check((konsole / f"{terminal}.colorscheme").read_bytes() == config.read_bytes(), f"{label}: live terminal colors differ")
    check(f"Name={terminal}\n" in (konsole / f"{terminal}.profile").read_text(), f"{label}: live terminal name differs")
    check(f"ColorScheme={terminal}\n" in (konsole / "Imperium.profile").read_text(), f"{label}: default terminal scheme is stale")
    check(contrast(foreground, background) >= 7.0, f"{label}: foreground contrast below 7")
    check(len(terminal_backgrounds) == 3, f"{label}: missing terminal background variants")
    check(all(color == background for color in terminal_backgrounds.values()), f"{label}: terminal backgrounds differ")
    for index in range(8):
        check((index, "normal") in ansi, f"{label}: missing ANSI normal color")
        check((index, "Intense") in ansi, f"{label}: missing ANSI intense color")
        check((index, "Faint") in ansi, f"{label}: missing ANSI faint color")
        check(contrast(ansi[(index, "normal")], background) >= 4.5, f"{label}: ANSI normal contrast below 4.5")
        check(contrast(ansi[(index, "Faint")], background) >= 4.5, f"{label}: ANSI faint contrast below 4.5")
        check(contrast(ansi[(index, "Intense")], background) >= 7.0, f"{label}: ANSI intense contrast below 7")

    live_files = list((home / ".local/share/color-schemes").glob("dolphin-live-*.colors"))
    check(len(live_files) == 1, f"{label}: expected one live Dolphin color scheme")
    groups: dict[str, dict[str, tuple[int, ...]]] = {}
    group = ""
    for raw in live_files[0].read_text(encoding="utf-8").splitlines():
        if raw.startswith("[") and raw.endswith("]"):
            group = raw[1:-1]
            groups[group] = {}
        elif group in ("Colors:View", "Colors:Window", "Colors:Complementary", "Colors:Selection") and "=" in raw:
            key, value = raw.split("=", 1)
            if key in ("BackgroundNormal", "BackgroundAlternate", "ForegroundNormal"):
                groups[group][key] = tuple(int(c) for c in value.split(","))
    target = tuple(int(expected_bg.lstrip("#")[i : i + 2], 16) for i in (0, 2, 4))
    for group_name in ("Colors:View", "Colors:Window", "Colors:Complementary"):
        for key in ("BackgroundNormal", "BackgroundAlternate"):
            value = groups.get(group_name, {}).get(key)
            check(value is not None, f"{label}: missing {group_name} {key}")
            check(value[:3] == target, f"{label}: {group_name} {key} differs from Dolphin background")
            expected_alpha = 0 if group_name == "Colors:View" else 240
            check(value[3] == expected_alpha, f"{label}: {group_name} {key} opacity is wrong")
    selection = groups.get("Colors:Selection", {})
    check("BackgroundNormal" in selection and "ForegroundNormal" in selection, f"{label}: missing selection colors")
    check(contrast(selection["ForegroundNormal"], selection["BackgroundNormal"]) >= 4.5,
          f"{label}: selected text contrast below 4.5")


def verify_cache_refresh(base: Path, source: Path) -> None:
    home = base / "home"
    cache = base / "cache"
    home.mkdir(parents=True)
    folder_one = base / "folder-one"
    folder_one.mkdir()
    regular_file = base / "file.png"
    regular_file.write_bytes(b"file")

    folder_thumb = add_cached_thumbnail(cache, "folder", folder_one.as_uri())
    regular_thumb = add_cached_thumbnail(cache, "regular", regular_file.as_uri())
    remote_thumb = add_cached_thumbnail(cache, "remote", "sftp://example.invalid/folder")
    malformed_thumb = cache / "thumbnails/normal/malformed.png"
    malformed_thumb.parent.mkdir(parents=True, exist_ok=True)
    malformed_thumb.write_bytes(b"not a PNG")

    palette_path = home / ".config/hypr/wallust/colors-shell.sh"
    initial = {"bg": "#121218", "fg": "#f2f0ed", "1": "#3daee9"}
    initial.update({str(i): f"#{i * 16:02x}{(15 - i) * 12:02x}{(i * 9) % 256:02x}" for i in range(15)})
    initial.update({str(i): f"#{(i * 12) % 256:02x}{(i * 17) % 256:02x}{(i * 23) % 256:02x}" for i in range(8, 16)})
    write_palette(palette_path, initial)

    run_generator(home, cache, source, palette_path)
    check(not folder_thumb.exists(), "accent change did not remove the folder preview")
    check(regular_thumb.exists() and remote_thumb.exists() and malformed_thumb.exists(), "folder refresh removed unrelated cache files")
    icon_theme = home / ".local/share/icons/imperium"
    first_accent = (icon_theme / ".accent").read_text(encoding="utf-8").strip()
    check(bool(re.fullmatch(r"[0-9a-f]{6}", first_accent)), "first accent was not written to the generated icon theme")
    check("#" + first_accent in (icon_theme / "scalable/places/folder.svg").read_text(encoding="utf-8"), "generated icon does not use its recorded accent")

    folder_two = base / "folder-two"
    folder_two.mkdir()
    same_accent_thumb = add_cached_thumbnail(cache, "same-accent", folder_two.as_uri(), "large")
    run_generator(home, cache, source, palette_path)
    check(same_accent_thumb.exists(), "same-accent run removed a folder preview")

    # Existing installations already have .accent but no preview-refresh stamp.
    (icon_theme / ".folder-preview-accent").unlink()
    run_generator(home, cache, source, palette_path)
    check(not same_accent_thumb.exists(), "upgrade did not repair already-stale folder previews")
    same_accent_thumb = add_cached_thumbnail(cache, "same-accent", folder_two.as_uri(), "large")

    changed = dict(initial)
    changed["1"] = "#ff5a22"
    write_palette(palette_path, changed)
    run_generator(home, cache, source, palette_path)
    check(not same_accent_thumb.exists(), "next accent change did not remove the folder preview")
    check(regular_thumb.exists() and remote_thumb.exists() and malformed_thumb.exists(), "next accent refresh removed unrelated cache files")
    next_accent = (icon_theme / ".accent").read_text(encoding="utf-8").strip()
    check(next_accent != first_accent, "changed accent did not refresh the generated icon theme")
    check("#" + next_accent in (icon_theme / "scalable/places/folder.svg").read_text(encoding="utf-8"), "refreshed icon does not use its recorded accent")
    check(len(list((home / ".local/share/konsole").glob("dolphin-terminal-live-*.profile"))) == 2, "obsolete live terminal profiles were not pruned")


def verify_existing_install(base: Path, source: Path) -> None:
    home = base / "home"
    config = home / ".config"
    config.mkdir(parents=True)
    original = base / "old-tracked-dolphinrc"
    original.write_text("[DetailsMode]\nIconSize=48\n[General]\nGlobalViewProps=false\n[LocalSession]\nPath=/tmp/local-folder\n")
    (config / "dolphinrc").symlink_to(original)
    qt = config / "qt6ct/qt6ct.conf"
    qt.parent.mkdir()
    qt.write_text("[Appearance]\nstyle=Fusion\n[Fonts]\ngeneral=Old Font\n[Interface]\nactivate_item_on_single_click=0\n")
    view = home / ".local/share/dolphin/view_properties/global/.directory"
    view.parent.mkdir(parents=True)
    view.write_text("[Dolphin]\nViewMode=0\nPreviewsShown=false\nHiddenFilesShown=true\nLocalProperty=keep\n")

    def read(path):
        result = configparser.ConfigParser(interpolation=None)
        result.optionxform = str
        result.read(path)
        return result

    for _ in range(2):
        run_generator(home, base / "cache", source, None)
        rc = read(config / "dolphinrc")
        check(not (config / "dolphinrc").is_symlink(), "Dolphin can still overwrite the tracked baseline")
        check(rc["DetailsMode"]["IconSize"] == "22", "old visual settings survived migration")
        check(rc["General"]["GlobalViewProps"] == "true", "global view defaults not enforced")
        for mode in ("IconsMode", "CompactMode", "DetailsMode"):
            check(rc[mode]["UseSystemFont"] == "true", f"{mode}: local custom font overrides the shared font")
        check(rc["LocalSession"]["Path"] == "/tmp/local-folder", "migration removed local session state")
        check(read(view)["Dolphin"]["ViewMode"] == "2", "existing view mode was not updated")
        check(read(view)["Dolphin"]["PreviewsShown"] == "true", "existing preview setting was not updated")
        check(read(view)["Dolphin"]["LocalProperty"] == "keep", "unmanaged view state was removed")
        interface = read(qt)["Interface"]
        check(interface["stylesheets"] == str(config / "qt6ct/qss/imperium.qss"), "missing stylesheet key was not installed")
        check(interface["activate_item_on_single_click"] == "0", "unmanaged Qt setting was overwritten")
        check(read(qt)["Appearance"]["color_scheme_path"] == str(config / "qt6ct/colors/Imperium.conf"), "Qt palette path is not absolute")
    check(original.read_text().startswith("[DetailsMode]\nIconSize=48\n"), "migration wrote through the old symlink")
    check((config / "dolphinrc.pre-imperium").read_bytes() == original.read_bytes(), "original config backup was overwritten")
    check((home / ".local/share/kxmlgui5/dolphin/dolphinui.rc").resolve() == ROOT / "dolphin/dolphinui.rc", "toolbar override points at another checkout")


def verify_qt_appearance(home: Path, base: Path) -> None:
    # Exercise Qt's actual font parser and dock layout, rather than assuming
    # identical INI strings imply identical font weights or panel placement.
    flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Widgets", "Qt6Xml"], text=True).split()
    binary = base / "appearance-check"
    libexec = subprocess.check_output(["pkg-config", "--variable=libexecdir", "Qt6Core"], text=True).strip()
    subprocess.run([str(Path(libexec) / "moc"), str(ROOT / "tools/check-dolphin-appearance.cpp"),
                    "-o", str(base / "check-dolphin-appearance.moc")], check=True)
    subprocess.run([
        "g++", "-fPIC", "-std=c++17", "-pthread",
        "-I" + str(base),
        "-I/usr/include/KF6/KIconThemes", "-I/usr/include/KF6/KParts",
        "-I/usr/include/KF6/KIOFileWidgets", "-I/usr/include/KF6/KIO", "-I/usr/include/KF6/KBookmarks", "-I/usr/include/KF6/Solid",
        str(ROOT / "tools/check-dolphin-appearance.cpp"), "-o", str(binary),
        *flags, "-lKF6IconThemes", "-lKF6KIOFileWidgets",
    ], check=True)
    env = dict(os.environ, HOME=str(home), FONTCONFIG_FILE=str(ROOT / "dolphin/fonts.conf"),
               XDG_CONFIG_HOME=str(home / ".config"), XDG_DATA_HOME=str(home / ".local/share"),
               XDG_CACHE_HOME=str(home / ".cache"), DBUS_SESSION_BUS_ADDRESS=f"unix:path={home / 'no-session-bus'}")
    subprocess.run([str(binary), str(home), "-platform", "offscreen"], env=env, check=True)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="dolphin-theme-check-") as temporary:
        base = Path(temporary)
        verify_worker_selection(base / "worker-selector")
        icon_source = base / "breeze-dark"
        (icon_source / "scalable/places").mkdir(parents=True)
        (icon_source / "index.theme").write_text("[Icon Theme]\nName=Breeze Dark\n", encoding="utf-8")
        (icon_source / "scalable/places/folder.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#3DAEE9"/></svg>\n',
            encoding="utf-8",
        )

        verify_cache_refresh(base / "cache-case", icon_source)
        verify_existing_install(base / "existing-install", icon_source)

        custom = base / "custom-case"
        custom_home = custom / "home"
        custom_cache = custom / "cache"
        custom_home.mkdir(parents=True)
        custom_palette_path = custom_home / ".config/hypr/wallust/colors-shell.sh"
        custom_palette = {"bg": "#121218", "fg": "#f2f0ed", "1": "#3daee9"}
        custom_palette.update({str(i): "#5c8fbd" for i in range(15)})
        custom_palette.update({str(i): "#a9d6ff" for i in range(8, 16)})
        write_palette(custom_palette_path, custom_palette)
        run_generator(custom_home, custom_cache, icon_source, custom_palette_path)
        verify_colors(custom_home, dolphin_background(custom_palette["bg"]), "generated palette")
        verify_qt_appearance(custom_home, base)

        fallback = base / "fallback-case"
        fallback_home = fallback / "home"
        fallback_home.mkdir(parents=True)
        run_generator(fallback_home, fallback / "cache", icon_source, None)
        fallback_data = json.loads((ROOT / "wallust/colorschemes/imperium.json").read_text(encoding="utf-8"))
        verify_colors(fallback_home, dolphin_background(fallback_data["background"]), "fallback palette")

    print("PASS: Dolphin theme cache refresh, ANSI contrast, live backgrounds, and existing-install convergence")


if __name__ == "__main__":
    main()
