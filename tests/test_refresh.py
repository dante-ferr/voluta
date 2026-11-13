"""Fast-path checks for session refresh and Waybar decoration stamps."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load_decorations():
    path = ROOT / 'waybar/scripts/render-decorations.py'
    spec = importlib.util.spec_from_file_location('render_decorations', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DecorationStampTests(unittest.TestCase):
    def test_fingerprint_changes_with_mtime_and_stamp_requires_outputs(self):
        module = load_decorations()
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'glow.json'
            source.write_text('{}\n')
            first = module.stat_fingerprint([source])
            source.write_text('{}\n\n')
            second = module.stat_fingerprint([source])
            self.assertNotEqual(first, second)
            stamp = Path(directory) / '.inputs.stamp'
            output = Path(directory) / 'angel-paths.css'
            self.assertFalse(module.stamp_matches(stamp, second, [output]))
            stamp.write_text(second + '\n')
            self.assertFalse(module.stamp_matches(stamp, second, [output]))
            output.write_text('ok\n')
            self.assertTrue(module.stamp_matches(stamp, second, [output]))
            self.assertFalse(module.stamp_matches(stamp, first, [output]))


if __name__ == '__main__':
    unittest.main()
