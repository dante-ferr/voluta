"""Background policy, shared output publication and preference preservation."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "voluta"))
import cli
import theme


class ThemeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        environment = patch.dict(os.environ, {"XDG_STATE_HOME": str(self.root / "state")})
        environment.start()
        self.addCleanup(environment.stop)
        self.config = self.root / "config"
        self.settings = self.config / "voluta"
        self.cache = self.root / "cache"
        self.shell = self.write("hypr/wallust/colors-shell.sh", "wc_bg='0A1515'\nwc_fg='80BAED'\nwc_15='80BAED'\nwc_0='204060'\nwc_1='54222B'\n")

    def write(self, relative, text):
        path = self.config / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def publish(self):
        return theme.publish(self.config, self.cache, self.settings, "test-host")

    def test_default_outputs_share_rgb_and_preserve_accents_and_alpha(self):
        gtk = self.write("hypr/wallust/colors-gtk.css", "@define-color imperium_source_bg #0A1515;\n@define-color imperium_bg #0A1515;\n")
        css = self.write("waybar/wallust/colors-waybar.css", "@define-color background #0A1515;\n@define-color background-alt rgba(10,21,21,0.25);\n@define-color color0 #0A1515;\n")
        kitty = self.write("kitty/kitty-themes/01-Wallust.conf", "background #0a1515\nactive_tab_background #0a1515\nforeground #80baed\n")
        rofi = self.write("rofi/wallust/colors-rofi.rasi", "normal-background: #0a1515;\nbackground: rgba(10,21,21,0.7);\nselected-normal-background: #54222b;\n")
        limusic = self.write("limusic/matugen.css", "html.matugen-theme {\n --background: #0A1515;\n --card: color-mix(in oklab, #80BAED 6%, #0A1515);\n --primary: #54222B;\n}\n")
        karere = self.write("karere/custom.css", "--voluta-canvas: #0A1515;\n--voluta-ink: #80BAED;\n--voluta-out: color-mix(in oklab, #54222B 28%, #0A1515);\ncolor: #80BAED;\n")
        self.assertTrue(self.publish())
        self.assertEqual(theme.read_palette(self.shell)["bg"], (6, 14, 14))
        self.assertEqual(theme.read_palette(self.shell)["source_bg"], (10, 21, 21))
        self.assertIn("imperium_bg #060e0e;", gtk.read_text())
        self.assertIn("background #060e0e;", css.read_text())
        self.assertIn("rgba(6,14,14,0.25)", css.read_text())
        self.assertIn("color0 #0A1515", css.read_text())
        self.assertIn("active_tab_background #060e0e", kitty.read_text())
        self.assertIn("rgba(6,14,14,0.7)", rofi.read_text())
        self.assertIn("selected-normal-background: #54222b", rofi.read_text())
        self.assertIn("--background: #060e0e;", limusic.read_text())
        self.assertIn("6%, #060e0e)", limusic.read_text())
        self.assertIn("--primary: #54222B;", limusic.read_text())
        self.assertIn("--voluta-canvas: #060e0e;", karere.read_text())
        self.assertIn("28%, #060e0e)", karere.read_text())
        self.assertIn("--voluta-ink: #80BAED;", karere.read_text())
        self.assertIn("color: #80BAED;", karere.read_text())
        exported = json.loads((self.cache / "voluta/theme.json").read_text())
        self.assertEqual(exported["background"], "#060e0e")
        self.assertFalse(self.publish(), "repeated publication must not darken twice or rewrite outputs")

    def test_karere_canvas_is_opaque(self):
        text = (ROOT / "wallust/templates/colors-karere.css").read_text()
        self.assertIn("--WDS-systems-chat-background-wallpaper: var(--voluta-canvas) !important;", text)
        self.assertIn("--voluta-canvas: {{background}};", text)
        self.assertIn("background-color: {{background}} !important;", text)
        self.assertNotIn("{{background}}a6", text)
        self.assertIn("--WDS-content-default: var(--voluta-ink) !important;", text)
        self.assertIn("--WDS-content-default-RGB: {{ink | rgb}} !important;", text)
        self.assertIn("--primary: var(--voluta-ink) !important;", text)
        self.assertIn("color: {{ink}};", text)
        self.assertNotIn("opacity: 0", text)
        self.assertNotIn("{{ink}}a", text)
        self.assertNotIn("{{accent}}a", text)
        gtk = (ROOT / "wallust/templates/colors-karere-gtk.css").read_text()
        self.assertIn("headerbar,", gtk)
        self.assertIn("@define-color voluta_bg {{background}};", gtk)
        self.assertIn("@define-color voluta_fg {{ink}};", gtk)
        self.assertNotIn(".voluta headerbar", gtk)
        self.assertNotIn("window.voluta-canvas", gtk)
        self.assertNotIn("opacity:", gtk)

    def test_limusic_song_layer_does_not_show_the_page_under_it(self):
        text = (ROOT / "wallust/templates/colors-limusic.css").read_text()
        self.assertIn("--background: {{background}}a6;", text)
        self.assertIn("html.matugen-theme:has([data-np-view]) main", text)
        self.assertIn("html.matugen-theme [data-np-view]", text)
        self.assertIn("background-color: transparent;", text)
        self.assertIn("section.fixed.inset-0.z-40.bg-background) div.relative.flex.h-screen.flex-col", text)

    def test_limusic_follows_the_recorded_source_background(self):
        self.publish()
        css = self.write("limusic/matugen.css", "--background: #0A1515e0;\n--sidebar: #0a1515e0;\n--primary-foreground: #0A1515;\n--primary: #54222B;\n")
        self.assertTrue(self.publish())
        text = css.read_text()
        self.assertIn("--background: #060e0ee0;", text)
        self.assertIn("--sidebar: #060e0ee0;", text)
        self.assertIn("--primary-foreground: #060e0e;", text)
        self.assertNotIn("#060e0ee0e", text)
        self.assertIn("--primary: #54222B;", text)
        self.assertFalse(self.publish())

    def test_host_override_uses_palette_token_and_preserves_shared_settings(self):
        shared = self.write("voluta/settings.json", json.dumps({"version": 1, "appearance": {"background": {"darken": 0.5}}}))
        self.write("voluta/hosts/test-host.json", json.dumps({"version": 1, "appearance": {"background": {"source": "color0", "darken": 0.25}}}))
        original = shared.read_bytes()
        self.publish()
        self.assertEqual(theme.read_palette(self.shell)["bg"], (24, 48, 72))
        self.assertEqual(shared.read_bytes(), original)

    def test_invalid_policy_is_rejected_before_publication(self):
        original = self.shell.read_bytes()
        for invalid in ({"darken": 2}, {"darken": True}, {"source": "color16"}, {"source": "#112233"}):
            with self.subTest(invalid=invalid):
                self.write("voluta/settings.json", json.dumps({"version": 1, "appearance": {"background": invalid}}))
                with self.assertRaises(ValueError):
                    self.publish()
                self.assertEqual(self.shell.read_bytes(), original)

    def test_cli_theme_override_does_not_clobber_other_preferences(self):
        path = self.write("voluta/settings.json", json.dumps({"version": 1, "apps": {"terminal": "example"}}))
        cli.main(["--config-dir", str(self.settings), "--host", "test-host", "theme", "set", "background.darken", "0.2"])
        self.assertEqual(json.loads(path.read_text())["apps"], {"terminal": "example"})
        previous = path.read_bytes()
        with self.assertRaises(ValueError):
            cli.main(["--config-dir", str(self.settings), "theme", "set", "background.darken", "2"])
        self.assertEqual(path.read_bytes(), previous)
        cli.main(["--config-dir", str(self.settings), "theme", "reset", "background.darken"])
        self.assertEqual(cli.resolve(self.settings, "test-host")[0]["appearance"]["background"]["darken"], 0.35)


if __name__ == "__main__":
    unittest.main()
