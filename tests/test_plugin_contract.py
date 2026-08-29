from __future__ import annotations

import configparser
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PluginContractTests(unittest.TestCase):
    def test_manifest_entry_points_exist_and_stay_inside_repo(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["id"], "io.github.olivoil.hurricane-tracker")
        self.assertEqual(manifest["name"], "Hurricane Tracker")
        self.assertEqual(manifest["barWidget"]["displayName"], "Hurricane Tracker")
        self.assertEqual(manifest["version"], "0.0.1")
        self.assertEqual(set(manifest["kinds"]), {"service", "overlay", "bar-widget"})
        for entry_point in manifest["entryPoints"].values():
            self.assertFalse(Path(entry_point).is_absolute())
            self.assertNotIn("..", Path(entry_point).parts)
            self.assertTrue((ROOT / entry_point).is_file(), entry_point)
        defaults = manifest["barWidget"]["defaults"]
        self.assertEqual(defaults["alertRegion"], "Off")
        self.assertEqual(defaults["formationThreshold"], "Medium (40%)")
        self.assertTrue(defaults["notifyNamedStorms"])
        self.assertTrue((ROOT / "assets" / "hurricane-tracker.svg").is_file())
        self.assertTrue((ROOT / "preview.png").is_file())

    def test_backend_is_executable(self):
        backend = ROOT / "bin" / "hurricane-tracker-data"
        self.assertTrue(backend.is_file())
        self.assertNotEqual(backend.stat().st_mode & 0o111, 0)

    def test_launcher_entry_summons_the_overlay(self):
        desktop_file = ROOT / "hurricane-tracker.desktop"
        parser = configparser.ConfigParser(interpolation=None)
        parser.optionxform = str
        parser.read(desktop_file, encoding="utf-8")

        entry = parser["Desktop Entry"]
        self.assertEqual(entry["Type"], "Application")
        self.assertEqual(entry["Name"], "Hurricane Tracker")
        self.assertEqual(
            entry["Exec"],
            "omarchy-shell shell summon io.github.olivoil.hurricane-tracker {}",
        )
        self.assertEqual(entry["TryExec"], "omarchy-shell")
        self.assertEqual(entry["Icon"], "@ICON@")
        self.assertEqual(entry["X-Hurricane-Tracker-Managed"], "true")

        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("hurricane-tracker.desktop", service)
        self.assertIn("X-Hurricane-Tracker-Managed=true", service)
        self.assertIn("Component.onDestruction", service)

    def test_generated_map_has_bounded_geometry(self):
        collection = json.loads((ROOT / "assets" / "countries.json").read_text(encoding="utf-8"))
        self.assertEqual(collection["type"], "FeatureCollection")
        self.assertGreaterEqual(len(collection["features"]), 170)
        point_count = sum(
            len(polygon[0])
            for feature in collection["features"]
            for polygon in feature["geometry"]["coordinates"]
        )
        self.assertLess(point_count, 12000)


if __name__ == "__main__":
    unittest.main()
