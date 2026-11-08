"""Window-grid insets are the only edge source for framed menus."""
import json
from pathlib import Path
import unittest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from voluta.window_grid import grid_for_monitor, parse_gaps, swaync_config_with_grid


class WindowGridTests(unittest.TestCase):
    def test_css_gap_orders(self):
        self.assertEqual(parse_gaps('12'), {'left': 12, 'top': 12, 'right': 12, 'bottom': 12})
        self.assertEqual(parse_gaps('8 16'), {'left': 16, 'top': 8, 'right': 16, 'bottom': 8})
        self.assertEqual(parse_gaps('4 10 6'), {'left': 10, 'top': 4, 'right': 10, 'bottom': 6})
        self.assertEqual(parse_gaps('8 16 16 16'), {'left': 16, 'top': 8, 'right': 16, 'bottom': 16})

    def test_insets_add_reserved_zone_to_every_side(self):
        monitor = {'name': 'DP-2', 'reserved': [4, 34, 0, 9]}
        grid = grid_for_monitor(monitor, parse_gaps('8 16 16 16'))
        self.assertEqual(grid['insets'], {'left': 20, 'top': 42, 'right': 16, 'bottom': 25})
        self.assertEqual(grid['reserved'], {'left': 4, 'top': 34, 'right': 0, 'bottom': 9})

    def test_swaync_tracks_only_the_top_gap(self):
        merged = swaync_config_with_grid({
            'control-center-margin-top': 8,
            'control-center-margin-right': 0,
            'control-center-margin-bottom': 12,
            'control-center-margin-left': 0,
        }, parse_gaps('10 20 30 40'))
        self.assertEqual(merged['control-center-margin-top'], 10)
        self.assertEqual(merged['control-center-margin-right'], 0)
        self.assertEqual(merged['control-center-margin-bottom'], 12)
        self.assertEqual(merged['control-center-margin-left'], 0)
        self.assertIn('window_grid', (Path(__file__).resolve().parents[1] / 'swaync/launch.sh').read_text())
        self.assertIn('VOLUTA_GRID_RIGHT', (Path(__file__).resolve().parents[1] / 'music/salon.qml').read_text())
        self.assertIn('framePadRight', (Path(__file__).resolve().parents[1] / 'music/salon.qml').read_text())


if __name__ == '__main__':
    unittest.main()
