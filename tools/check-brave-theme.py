#!/usr/bin/env python3
"""Exercise palette rendering, GTK parsing and live theme publication in isolation."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("brave_theme", ROOT / "hypr/UserScripts/paint_brave_theme.py")
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)

with tempfile.TemporaryDirectory(prefix="check-brave-theme-") as temporary:
    home = Path(temporary)
    theme.HOME = home
    theme.CONFIG = home / ".config"
    theme.DATA = home / ".local/share"
    theme.STATE = home / "state/brave-theme.json"
    palette = theme.CONFIG / "hypr/wallust/colors-gtk.css"
    palette.parent.mkdir(parents=True)
    prismwing_palette = home / "prismwing-palette.json"
    config = home / "wallust.toml"
    config.write_text(f'[templates.gtk]\ntemplate = "colors-gtk.css"\ntarget = "{palette}"\n'
                      f'[templates.prismwing]\ntemplate = "colors-prismwing.json"\ntarget = "{prismwing_palette}"\n')
    subprocess.run(["wallust", "-q", "-s", "--no-hooks", "-C", str(config), "--templates-dir", str(ROOT / "wallust/templates"), "cs", str(ROOT / "wallust/colorschemes/imperium.json")], check=True, env={**os.environ, "HOME": str(home), "XDG_CACHE_HOME": str(home / "cache")})
    rendered = palette.read_text()
    assert "{{" not in rendered
    colors = json.loads(prismwing_palette.read_text())["colors"]
    assert len(colors) == 16 and all(color.startswith("#") and len(color) == 7 for color in colors)
    assert "@define-color imperium_bg #060e0e;" in theme.dolphin_background(
        "@define-color imperium_source_bg #0A1515;\n@define-color imperium_bg #070e0e;"
    ), "browser and Dolphin RGB rounding differ"

    original = theme.CONFIG / "gtk-3.0/settings.ini"
    original.parent.mkdir(parents=True)
    original.write_text("[Settings]\ngtk-theme-name=Existing\ngtk-font-name=Example 11\n")
    base = theme.DATA / "themes/Existing/gtk-3.0/gtk.css"
    base.parent.mkdir(parents=True)
    base.write_text("/* original GTK theme */\n")
    current = "Existing"
    changes = []

    def session_command(*args):
        global current
        if args[1] == "get":
            return repr(current)
        current = args[-1]
        changes.append(current)
        return ""

    theme.command = session_command
    os.environ.pop("DISPLAY", None)
    sys.argv = [str(spec.origin)]
    theme.main()
    first = current
    assert changes == [first] and theme.managed_theme(first)
    css = theme.DATA / f"themes/{current}/gtk-3.0/gtk.css"
    assert base.resolve().as_uri() in css.read_text(), "original theme was not imported"
    assert "gtk-font-name = Example 11" in original.read_text()
    assert original.with_suffix(".ini.pre-imperium-brave").read_text().endswith("gtk-font-name=Example 11\n")

    # Different content must get a fresh name; returning to a named provider
    # can resurrect its cached CSS in a long-running browser.
    palette.write_text(rendered.replace("@define-color imperium_bg ", "/* new palette */\n@define-color imperium_bg "))
    theme.main()
    second = current
    assert second != first and theme.managed_theme(second)
    assert changes == [first, second]
    assert "/* new palette */" in (theme.DATA / f"themes/{current}/gtk-3.0/gtk.css").read_text()
    assert json.loads(theme.STATE.read_text())["original"]["3"] == "Existing"
    theme.main()
    assert changes == [first, second, second], "unchanged content must keep its immutable theme name"

    palette.write_text("{{background}}")
    try:
        theme.main()
        raise AssertionError("unrendered palette was accepted")
    except SystemExit:
        pass
    assert len(changes) == 3, "bad palette changed the session theme"

    # Parse the actual generated CSS with both installed GTK versions. No GUI
    # connection is needed to validate the scoped overrides.
    for version in (3, 4):
        # Avoid importing the base theme here, which needs a display in GTK 4.
        validation = palette.parent / "validation.css"
        validation.write_text(rendered)
        subprocess.run(["/usr/bin/python3", "-c", '''
import gi, sys
gi.require_version("Gtk", sys.argv[1] + ".0")
from gi.repository import Gtk
p = Gtk.CssProvider()
errors = []
p.connect("parsing-error", lambda _p, _section, error: errors.append(str(error)))
p.load_from_data(open(sys.argv[2], "rb").read())
assert not errors, errors
''', str(version), str(validation)], check=True)

print("Brave theme checks passed: Wallust rendering, GTK 3/4 CSS, live publication, preservation and invalid palettes")
