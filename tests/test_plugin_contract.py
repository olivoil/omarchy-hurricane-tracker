from __future__ import annotations

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
        backend = ROOT / "bin" / "omanado-data"
        self.assertTrue(backend.is_file())
        self.assertNotEqual(backend.stat().st_mode & 0o111, 0)

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

    def test_deferred_system_fit_cannot_override_place_focus(self):
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")
        self.assertIn("function scheduleFitSelected(force)", storm_map)
        self.assertIn("if (!root.autoFitSelection", storm_map)
        self.assertNotIn("onSelectedKeyChanged: if (autoFitSelection)", storm_map)

    def test_navigation_shell_keeps_alerts_global_and_trackers_extensible(self):
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        self.assertIn('property bool trackerMenuOpen: false', overlay)
        self.assertIn('readonly property var trackerDefinitions:', overlay)
        self.assertIn('title: "HURRICANE TRACKER"', overlay)
        self.assertIn('title: "EARTHQUAKE TRACKER"', overlay)
        self.assertIn('id: alertsButton', overlay)
        self.assertIn('anchors.right: closeButton.left', overlay)
        self.assertIn('id: trackerMenuPanel', overlay)
        self.assertIn('id: dataFooter', overlay)
        self.assertIn('readonly property var regionalRows: Model.regionalRows(storms, outlooks)', overlay)
        self.assertNotIn('Model.disclosedRegionalRows(', overlay)
        self.assertNotIn('function toggleRegion(', overlay)
        self.assertNotIn('text: "Systems"', overlay)
        self.assertNotIn('text: "Places"', overlay)
        self.assertNotIn('text: "OMANADO"', overlay)
        self.assertIn('stormMap.focusWatchPlace(place)', overlay)
        self.assertIn('visible: root.alertUpdateCount > 0', overlay)
        self.assertIn('text: String(root.alertUpdateCount)', overlay)
        self.assertIn('if (payload.alerts === true) sidebarMode = "alerts"', overlay)
        self.assertIn('"WATCHED LOCATIONS"', overlay)

    def test_overlay_has_readable_minimum_type_and_touch_tokens(self):
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property int typeMicro", overlay)
        self.assertIn("readonly property int typeCaption", overlay)
        self.assertIn("readonly property int minimumTouchTarget", overlay)
        self.assertNotRegex(overlay, r"Math\.max\([678], Style\.font\.caption -")

    def test_plugin_id_is_injected_for_parallel_preview_installs(self):
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        bar_widget = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn('shell.serviceFor(pluginId)', overlay)
        self.assertIn('bar.shell.serviceFor(pluginId)', bar_widget)
        self.assertIn('shell toggle " + root.pluginId', bar_widget)


if __name__ == "__main__":
    unittest.main()
