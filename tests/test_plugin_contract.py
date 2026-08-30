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
        self.assertTrue(defaults["onlinePlaceSearch"])
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
        self.assertIn('function openBrowser(url)', overlay)
        self.assertIn('Quickshell.execDetached(["omarchy-launch-browser", safeUrl])', overlay)
        open_browser = overlay.split("function openBrowser(url)", 1)[1].split(
            "function openOfficial", 1
        )[0]
        self.assertIn("dismiss()", open_browser)
        self.assertIn('onClicked: root.openBrowser("https://www.nhc.noaa.gov/")', overlay)
        self.assertIn('placeholderText: "Home, Beach House, Mom’s Place"', overlay)
        self.assertNotIn("Home, Dad", overlay)

    def test_overlay_has_readable_minimum_type_and_touch_tokens(self):
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property int typeMicro", overlay)
        self.assertIn("readonly property int typeCaption", overlay)
        self.assertIn("readonly property int minimumTouchTarget", overlay)
        self.assertNotRegex(overlay, r"Math\.max\([678], Style\.font\.caption -")

    def test_units_follow_the_system_locale_without_exposing_a_setting_yet(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")

        self.assertIn(
            "Qt.locale().measurementSystem !== Locale.MetricSystem",
            service,
        )
        self.assertIn("readonly property bool useImperial", overlay)
        self.assertIn("property bool useImperial: false", storm_map)
        self.assertIn("useImperial: root.useImperial", overlay)
        self.assertIn("Model.formatDistanceKm", service)
        self.assertNotIn("unitSystem", manifest["barWidget"]["defaults"])
        self.assertNotIn(
            "unitSystem",
            {item["key"] for item in manifest["barWidget"]["schema"]},
        )

    def test_place_editor_supports_search_and_direct_map_placement(self):
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")
        self.assertIn('text: "NAME"', overlay)
        self.assertIn('text: "LOCATION"', overlay)
        self.assertIn('text: "ALERTS"', overlay)
        editor_form = overlay.split('id: editorForm', 1)[1].split(
            'id: editorActions', 1
        )[0]
        self.assertLess(
            editor_form.index('id: placeLocationSection'),
            editor_form.index('id: placeNameSection'),
        )
        self.assertLess(
            editor_form.index('id: placeNameSection'),
            editor_form.index('text: "ALERTS"'),
        )
        self.assertNotIn('text: "FIND ON MAP"', overlay)
        self.assertNotIn('text: "MAP POSITION"', overlay)
        self.assertNotIn('text: "PROACTIVE ALERT RULES"', overlay)
        self.assertIn('id: placeSearchField', overlay)
        self.assertIn('id: locationPicker', overlay)
        self.assertIn('"Search a place or click the map"', overlay)
        self.assertIn('placeholderText: "Home, Beach House, Mom’s Place"', overlay)
        self.assertIn('z: 50', overlay)
        self.assertIn('visible: root.placeSearchMenuOpen', overlay)
        self.assertIn('if (draftLocationPending)', overlay)
        search_surface = overlay.split('id: placeSearchResultsSurface', 1)[1].split(
            'Column {', 1
        )[0]
        self.assertIn('parent: watchPlaceEditor', search_surface)
        self.assertNotIn('placeSearchField.mapToItem(', search_surface)
        self.assertIn('editorForm.x + placeLocationSection.x', search_surface)
        self.assertIn('editorForm.y + placeLocationSection.y', search_surface)
        self.assertIn('locationPicker.height', search_surface)
        self.assertIn('editorScroll.contentY', search_surface)
        self.assertIn('Place search: Open-Meteo · GeoNames', overlay)
        self.assertNotIn(
            'Place names: Open-Meteo · GeoNames · © OpenStreetMap contributors',
            overlay,
        )
        self.assertIn('© OpenStreetMap contributors', overlay)
        self.assertIn('function selectPlaceSearchResult(result)', overlay)
        self.assertIn('stormMap.fitWatchPlace(root.draftWatchPlace)', overlay)
        self.assertIn('function setDraftWatchCoordinate(latitude, longitude, fromSearch)', overlay)
        self.assertIn('signal placePicked(real latitude, real longitude)', storm_map)
        self.assertIn('root.placePicked(coordinate.latitude, coordinate.longitude)', storm_map)
        self.assertIn('id: placeSearchProcess', service)
        self.assertIn('readonly property bool onlinePlaceSearchEnabled', service)
        self.assertIn('if (!onlinePlaceSearchEnabled)', service)
        self.assertIn('[backendPath, "place-search", normalized]', service)
        self.assertIn('completedQuery === root.requestedPlaceSearchQuery', service)
        self.assertIn('id: reverseGeocodeProcess', service)
        self.assertIn('"place-reverse"', service)
        self.assertNotIn('geocoding-api.open-meteo.com', overlay)
        self.assertNotIn('geocoding-api.open-meteo.com', service)

    def test_new_watch_place_names_are_suggested_without_placeholder_map_copy(self):
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        self.assertIn('property bool draftPlaceNameManuallyEdited: false', overlay)
        self.assertIn('function suggestDraftPlaceName(value)', overlay)
        self.assertIn('root.suggestDraftPlaceName(result.name)', overlay)
        self.assertIn('root.tracker.reverseGeocode(latitude, longitude)', overlay)
        suggestion = overlay.split('function suggestDraftPlaceName(value)', 1)[1].split(
            'function queuePlaceSearch', 1
        )[0]
        self.assertIn('draftPlaceName = suggestion', suggestion)
        self.assertIn('onDraftPlaceNameChanged:', overlay)
        name_sync = overlay.split('onDraftPlaceNameChanged:', 1)[1].split(
            'readonly property string pluginId', 1
        )[0]
        self.assertIn('placeNameField.text = root.draftPlaceName', name_sync)
        self.assertIn('function applyReverseGeocodeSuggestion(result)', overlay)
        reverse_connection = overlay.split(
            'function onReverseGeocodeResultChanged()', 1
        )[1].split('function onOnlinePlaceSearchEnabledChanged()', 1)[0]
        self.assertIn('Qt.callLater', reverse_connection)
        self.assertIn(
            'root.applyReverseGeocodeSuggestion(root.tracker.reverseGeocodeResult)',
            reverse_connection,
        )
        self.assertNotIn('name: draftPlaceName.trim() || "New watch place"', overlay)

    def test_plugin_id_is_injected_for_parallel_preview_installs(self):
        overlay = (ROOT / "Omanado.qml").read_text(encoding="utf-8")
        bar_widget = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn('shell.serviceFor(pluginId)', overlay)
        self.assertIn('bar.shell.serviceFor(pluginId)', bar_widget)
        self.assertIn('shell toggle " + root.pluginId', bar_widget)
        self.assertIn('visible: root.indicatorCount > 0', bar_widget)
        self.assertIn('text: String(root.indicatorCount)', bar_widget)
        self.assertIn("root.personalAlertCount > 0", bar_widget)
        self.assertIn('shell summon " + root.pluginId', bar_widget)
        self.assertIn(r'\"alerts\":true', bar_widget)
        self.assertIn("function openSource()", bar_widget)
        self.assertIn("root.bar.shell.hide(root.pluginId)", bar_widget)
        self.assertIn("All locations quiet", bar_widget)
        self.assertNotIn("left open", bar_widget)


if __name__ == "__main__":
    unittest.main()
