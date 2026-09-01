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
        self.assertEqual(manifest["name"], "Hurricane + Earthquake Tracker")
        self.assertEqual(manifest["barWidget"]["displayName"], "Hurricane + Earthquake Tracker")
        self.assertEqual(manifest["version"], "0.1.0")
        self.assertEqual(set(manifest["kinds"]), {"service", "overlay", "bar-widget"})
        for entry_point in manifest["entryPoints"].values():
            self.assertFalse(Path(entry_point).is_absolute())
            self.assertNotIn("..", Path(entry_point).parts)
            self.assertTrue((ROOT / entry_point).is_file(), entry_point)
        defaults = manifest["barWidget"]["defaults"]
        self.assertEqual(defaults["earthquakeRefreshMinutes"], 5)
        self.assertEqual(defaults["alertRegion"], "Off")
        self.assertTrue(defaults["onlinePlaceSearch"])
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
        self.assertEqual(entry["Name"], "Hurricane + Earthquake Tracker")
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
        self.assertIn('Quickshell.env("XDG_DATA_HOME")', service)
        self.assertIn("launcherIntentFile.setText", service)
        self.assertIn("blockWrites: true", service)
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

    def test_country_fill_is_clipped_to_the_curved_visible_horizon(self):
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")
        country_paint = storm_map.split("function paintCountryRing", 1)[1].split(
            "function drawCountries", 1
        )[0]

        self.assertIn("Model.clippedPreparedHemisphereRings", country_paint)
        self.assertIn("fragment.boundaryLength", country_paint)
        self.assertIn("if (!fragment.clipped) context.closePath()", country_paint)
        self.assertNotIn("allVisible", country_paint)

    def test_country_geometry_is_prepared_once_instead_of_during_each_paint(self):
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")
        country_paint = storm_map.split("function paintCountryRing", 1)[1].split(
            "function drawCountries", 1
        )[0]
        country_draw = storm_map.split("function drawCountries", 1)[1].split(
            "function drawCountryLabels", 1
        )[0]

        self.assertIn("property var preparedCountryRings", storm_map)
        self.assertIn("function prepareCountryGeometry", storm_map)
        self.assertIn("Model.clippedPreparedHemisphereRings", country_paint)
        self.assertIn("preparedCountryRings", country_draw)

    def test_outlook_connectors_are_drawn_as_directional_links(self):
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")

        self.assertIn("function drawOutlookConnector", storm_map)
        self.assertIn("outlook.connector", storm_map)
        self.assertIn("context.rotate", storm_map)

    def test_deferred_system_fit_cannot_override_place_focus(self):
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")
        self.assertIn("function scheduleFitSelected(force)", storm_map)
        self.assertIn("if (!root.autoFitSelection", storm_map)
        self.assertNotIn("onSelectedKeyChanged: if (autoFitSelection)", storm_map)

    def test_default_location_is_one_time_removable_and_drives_opening_flight(self):
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        bar_widget = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")

        self.assertIn('readonly property string defaultWatchPlaceId: "user-location"', service)
        self.assertIn("property bool defaultLocationInitialized: false", service)
        self.assertIn("property bool settingsReady: false", service)
        apply_settings = service.split("function applySettings(value)", 1)[1].split(
            "function setting(name, fallback)", 1
        )[0]
        self.assertIn("settingsReady = true", apply_settings)
        self.assertIn("root.tracker.applySettings(root.settings)", bar_widget)
        self.assertIn("defaultLocationInitialized: defaultLocationInitialized", service)
        self.assertIn('[backendPath, "default-location"]', service)
        self.assertIn('command.push("--allow-network")', service)
        self.assertIn('["hyprctl", "getoption", "animations:enabled", "-j"]', service)
        apply_default = service.split("function applyDefaultLocation(raw)", 1)[1].split(
            "function requestDefaultLocation()", 1
        )[0]
        self.assertLess(
            apply_default.index("upsertWatchPlace(place, false)"),
            apply_default.index("defaultLocationInitialized = true"),
        )
        self.assertLess(
            apply_default.index("defaultLocationInitialized = true"),
            apply_default.index("persistWatchPlaces()"),
        )
        self.assertIn("function beginOpeningView(payload)", overlay)
        self.assertIn("tracker.defaultWatchPlace", overlay)
        self.assertIn("stormMap.beginOpeningFlight(place", overlay)
        opening_attempt = overlay.split(
            "function tryDefaultLocationArrival()", 1
        )[1].split("function beginOpeningView(payload)", 1)[0]
        self.assertIn("stormMap.width < 40 || stormMap.height < 40", opening_attempt)
        self.assertIn("openingLocationRetry.restart()", opening_attempt)
        self.assertLess(
            opening_attempt.index("stormMap.beginOpeningFlight(place"),
            opening_attempt.index("cancelPendingLocationArrival()"),
        )
        self.assertIn("id: openingLocationRetry", overlay)
        cancel_pending = overlay.split(
            "function cancelPendingLocationArrival()", 1
        )[1].split("function tryDefaultLocationArrival()", 1)[0]
        self.assertIn("openingLocationRetry.stop()", cancel_pending)
        self.assertIn("function beginOpeningFlight(place, animate)", storm_map)
        self.assertIn("function drawOpeningArrival(context)", storm_map)
        self.assertIn('"YOUR LOCATION · "', storm_map)
        self.assertIn("zoom = minimumZoom", storm_map)
        self.assertIn("ParallelAnimation", storm_map)
        self.assertIn("Easing.InOutSine", storm_map)
        self.assertIn("root.cancelOpeningFlight()", storm_map)

    def test_plain_open_starts_with_no_selected_system(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        open_function = overlay.split("function open(payloadJson)", 1)[1].split(
            "function close()", 1
        )[0]

        self.assertIn('cycloneSelection = ""', open_function)
        self.assertIn('earthquakeSelection = ""', open_function)
        self.assertIn('selectedKey = ""', open_function)
        self.assertLess(
            open_function.index('selectedKey = ""'),
            open_function.index("if (payload.stormId)"),
        )
        self.assertLess(
            open_function.index('selectedKey = ""'),
            open_function.index("syncSelection(true)"),
        )

    def test_opening_flight_starts_immediately_with_a_smooth_camera_curve(self):
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")
        opening_flight = storm_map.split("id: openingFlight", 1)[1].split(
            "FileView {", 1
        )[0]

        self.assertNotIn("PauseAnimation", opening_flight)
        self.assertNotIn("Easing.OutQuint", opening_flight)
        self.assertEqual(opening_flight.count("Easing.InOutSine"), 3)

    def test_navigation_shell_keeps_alerts_global_and_trackers_extensible(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        self.assertIn('property bool trackerMenuOpen: false', overlay)
        self.assertIn('readonly property var trackerDefinitions:', overlay)
        self.assertIn('title: "HURRICANE TRACKER"', overlay)
        self.assertIn('title: "EARTHQUAKE TRACKER"', overlay)
        self.assertIn('state: root.earthquakeCount + " IN 7 DAYS"', overlay)
        self.assertIn('available: true', overlay)
        self.assertIn('readonly property var earthquakeRows:', overlay)
        self.assertIn('mode: root.sidebarMode === "alerts" ? "cyclones" : root.activeTrackerId', overlay)
        self.assertIn('section.property: root.earthquakeMode ? "sectionName" : ""', overlay)
        self.assertIn('height: activeSection ? Style.space(44) : 0', overlay)
        self.assertIn('id: alertsButton', overlay)
        self.assertIn('anchors.right: closeButton.left', overlay)
        self.assertIn('id: trackerMenuPanel', overlay)
        self.assertIn('id: dataFooter', overlay)
        self.assertIn('? earthquakeRows : Model.regionalRows(storms, outlooks)', overlay)
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
        self.assertIn('onClicked: root.openBrowser(root.sourceUrl)', overlay)
        self.assertIn('placeholderText: "Home, Beach House, Mom’s Place"', overlay)
        self.assertNotIn("Home, Dad", overlay)

    def test_earthquake_refresh_state_is_independent_from_tropical_alerts(self):
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("property var earthquakePayload:", service)
        self.assertIn("property var earthquakes: []", service)
        self.assertIn("function refreshTropical()", service)
        self.assertIn("function refreshEarthquakes()", service)
        self.assertIn('[backendPath, "fetch-earthquakes"]', service)
        self.assertIn("id: earthquakeFetchProcess", service)
        self.assertIn("id: earthquakeRefreshTimer", service)
        self.assertIn("onTriggered: root.refreshTropical()", service)
        self.assertIn("onTriggered: root.refreshEarthquakes()", service)

    def test_earthquake_list_is_sticky_and_collapsible(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        self.assertIn("ViewSection.CurrentLabelAtStart", overlay)
        self.assertIn("function toggleEarthquakeSection(sectionName)", overlay)
        self.assertIn("id: earthquakeSectionHeader", overlay)
        self.assertIn("function revealIndex(index)", overlay)

    def test_activity_sidebar_routes_wheel_input_across_every_surface(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        header = overlay.split("id: listHeader", 1)[1].split(
            "id: trackerMenuPanel", 1
        )[0]
        activity_list = overlay.split("id: systemList", 1)[1].split(
            "id: watchPlacesPanel", 1
        )[0]
        footer = overlay.split("id: dataFooter", 1)[1].split(
            "id: discussionPanel", 1
        )[0]
        discussion = overlay.split("id: discussionPanel", 1)[1]

        self.assertIn("function routeActivityWheel(event, detailFirst)", overlay)
        self.assertIn("Model.wheelScrollDistance(", overlay)
        self.assertIn("root.routeActivityWheel(event, false)", header)
        self.assertIn("root.routeActivityWheel(event, false)", activity_list)
        self.assertIn("root.routeActivityWheel(event, false)", footer)
        self.assertIn("root.routeActivityWheel(event, true)", discussion)
        self.assertIn("discussionScroll.scrollByPixels(remaining)", overlay)
        self.assertIn("systemList.scrollByPixels(remaining)", overlay)
        self.assertNotIn("event.pixelDelta.y !== 0", activity_list)
        self.assertIn("Style.space(272)", overlay)

    def test_map_renders_only_the_active_hazard_layer(self):
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")
        self.assertIn('property string mode: "cyclones"', storm_map)
        self.assertIn("function drawEarthquakeMarker", storm_map)
        self.assertIn('if (mode === "earthquakes")', storm_map)
        self.assertIn("drawEarthquakeMarker(context, systems[e])", storm_map)

    def test_alerts_button_and_shortcut_share_toggle_navigation(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        toggle_alerts = overlay.split("function toggleAlerts()", 1)[1].split(
            "function toggleTrackerMenu", 1
        )[0]
        alerts_button = overlay.split("id: alertsButton", 1)[1].split(
            "Row {", 1
        )[0]
        alerts_shortcut = overlay.split("event.key === Qt.Key_A", 1)[1].split(
            "event.accepted = true", 1
        )[0]

        self.assertIn('if (sidebarMode === "alerts") showActivity()', toggle_alerts)
        self.assertIn("else showAlerts()", toggle_alerts)
        self.assertIn("onClicked: root.toggleAlerts()", alerts_button)
        self.assertIn("root.toggleAlerts()", alerts_shortcut)
        self.assertIn(
            'root.sidebarMode === "alerts"\n            ? "Back to activity (A)"',
            alerts_button,
        )

    def test_tracker_rows_begin_directly_below_the_introduction_separator(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        tracker_menu_lead = overlay.split('id: trackerMenuPanel', 1)[1].split(
            'Repeater {', 1
        )[0]

        self.assertNotIn('height: Style.space(8)', tracker_menu_lead)

    def test_region_overview_clears_the_selected_system(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        sidebar_mode_change = overlay.split("onSidebarModeChanged:", 1)[1].split(
            "readonly property string pluginId", 1
        )[0]
        sync_selection = overlay.split("function syncSelection", 1)[1].split(
            "function rowIndexForKey", 1
        )[0]
        view_region = overlay.split("function viewRegion(basin)", 1)[1].split(
            "function selectSystem", 1
        )[0]
        select_system = overlay.split("function selectSystem(key)", 1)[1].split(
            "function moveSelection", 1
        )[0]

        self.assertIn('property string regionOverviewBasin: ""', overlay)
        self.assertIn(
            'if (sidebarMode === "alerts") regionOverviewBasin = ""',
            sidebar_mode_change,
        )
        self.assertIn("if (!earthquakeMode && regionOverviewBasin)", sync_selection)
        self.assertIn("fitRegionOverview(regionOverviewBasin)", sync_selection)
        self.assertLess(
            sync_selection.index("if (!earthquakeMode && regionOverviewBasin)"),
            sync_selection.index("Model.selectedKeyAfterRefresh"),
        )
        self.assertIn("regionOverviewBasin = basin", view_region)
        self.assertIn('selectedKey = ""', view_region)
        self.assertLess(
            view_region.index("regionOverviewBasin = basin"),
            view_region.index('selectedKey = ""'),
        )
        self.assertLess(
            view_region.index('selectedKey = ""'),
            view_region.index("fitRegionOverview(basin)"),
        )
        self.assertIn('regionOverviewBasin = ""', select_system)

    def test_watch_place_editor_cannot_leak_into_activity_mode(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        close_function = overlay.split("function close()", 1)[1].split(
            "function showGlobe", 1
        )[0]
        map_wiring = overlay.split("StormMap {", 1)[1].split(
            "BorderSurface {", 1
        )[0]

        self.assertIn("if (editingWatchPlace) cancelWatchPlaceEditor()", close_function)
        self.assertLess(
            close_function.index("cancelWatchPlaceEditor()"),
            close_function.index("opened = false"),
        )
        self.assertIn("onSidebarModeChanged:", overlay)
        self.assertIn(
            'if (sidebarMode !== "alerts" && editingWatchPlace)',
            overlay,
        )
        self.assertIn(
            'placementMode: root.sidebarMode === "alerts" && root.editingWatchPlace',
            map_wiring,
        )
        self.assertIn(
            'visible: root.sidebarMode === "alerts" && root.editingWatchPlace',
            overlay,
        )

    def test_selected_watch_location_reveals_full_alert_copy(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        place_row = overlay.split('id: placeRow', 1)[1].split(
            'QQC.ScrollBar.vertical', 1
        )[0]

        self.assertIn('readonly property bool summaryExpanded: isSelected', place_row)
        self.assertIn('height: summaryExpanded', place_row)
        self.assertIn(
            'wrapMode: placeRow.summaryExpanded ? Text.WordWrap : Text.NoWrap',
            place_row,
        )
        self.assertIn(
            'elide: placeRow.summaryExpanded ? Text.ElideNone',
            place_row,
        )
        self.assertIn('placePrimaryText.truncated', place_row)
        self.assertIn('placeSecondaryText.truncated', place_row)
        self.assertIn('QQC.ToolTip.visible:', place_row)

    def test_overlay_has_readable_minimum_type_and_touch_tokens(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property int typeMicro", overlay)
        self.assertIn("readonly property int typeCaption", overlay)
        self.assertIn("readonly property int minimumTouchTarget", overlay)
        self.assertNotRegex(overlay, r"Math\.max\([678], Style\.font\.caption -")

    def test_units_follow_the_system_locale_without_exposing_a_setting_yet(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        storm_map = (ROOT / "StormMap.qml").read_text(encoding="utf-8")

        self.assertIn(
            "Qt.locale().measurementSystem !== Locale.MetricSystem",
            service,
        )
        self.assertIn("readonly property bool useImperial", overlay)
        self.assertIn("property bool useImperial: false", storm_map)
        self.assertIn("useImperial: root.useImperial", overlay)
        self.assertNotIn("unitSystem", manifest["barWidget"]["defaults"])
        self.assertNotIn(
            "unitSystem",
            {item["key"] for item in manifest["barWidget"]["schema"]},
        )
        self.assertIn("Model.formatWatchRadius", overlay)
        self.assertIn("Model.formatWatchRadius", service)
        self.assertIn("Model.watchRadiusOptions", overlay)
        self.assertIn("Model.defaultWatchRadiusKm", overlay)

    def test_place_editor_supports_search_and_direct_map_placement(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
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

    def test_watch_load_failure_preserves_data_and_keeps_edits_locked(self):
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        failure_handler = service.split("if (!accepted) {", 1)[1].split(
            "root.watchProcessOutput = \"\"", 1
        )[0]

        self.assertNotIn("root.watchPlaces = []", failure_handler)
        self.assertIn("root.watchPlacesLoaded = false", failure_handler)
        self.assertIn("The file was left unchanged", failure_handler)

    def test_combined_alerts_are_coalesced_before_notification(self):
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("events = Model.coalesceAlertEvents(events)", service)

    def test_partial_outlook_data_preserves_alert_baselines(self):
        backend = (ROOT / "bin" / "hurricane-tracker-data").read_text(encoding="utf-8")
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")

        self.assertIn('"incompleteOutlookBasins"', backend)
        self.assertIn("readonly property bool outlookDataComplete", service)
        self.assertNotIn("if (!outlookDataComplete) return", service)
        self.assertIn("Model.stabilizedAlertSnapshots", service)
        self.assertIn("Model.incompleteForecastSystemKeys", service)
        self.assertIn("readonly property var watchPlaceSummaries", service)
        self.assertIn("tracker.watchPlaceSummaries", overlay)
        self.assertIn("tracker.watchPlaceSummaries", (ROOT / "BarWidget.qml").read_text(encoding="utf-8"))
        self.assertIn('"DATA PARTIAL"', overlay)

    def test_place_alert_rearm_waits_for_relevant_partial_data(self):
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        completeness = service.split(
            "function placeAlertSnapshotComplete(snapshot)", 1
        )[1].split("function armAlertsQuietly", 1)[0]
        arm_place_alerts = service.split(
            "function armPlaceAlertsQuietly()", 1
        )[1].split("function evaluateAlerts", 1)[0]
        place_evaluation = service.split("if (placeAlertsEnabled)", 1)[1].split(
            "events = Model.coalesceAlertEvents", 1
        )[0]

        self.assertIn("Model.watchPlaceSummaries", completeness)
        self.assertIn("Model.watchDataLimitedCount", completeness)
        self.assertIn("Model.stabilizedAlertSnapshots", arm_place_alerts)
        self.assertIn(
            "&& placeAlertSnapshotComplete(placeAlertBaseline)",
            arm_place_alerts,
        )
        self.assertIn("Model.stabilizedAlertSnapshots", place_evaluation)
        self.assertIn(
            "placeAlertsArmed = placeAlertSnapshotComplete(placeAlertBaseline)",
            place_evaluation,
        )

    def test_basin_alert_rearm_quiets_only_incomplete_outlooks(self):
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        arm_alerts = service.split("function armAlertsQuietly()", 1)[1].split(
            "function armPlaceAlertsQuietly", 1
        )[0]
        global_evaluation = service.split("if (alertsEnabled)", 1)[1].split(
            "if (placeAlertsEnabled)", 1
        )[0]

        self.assertIn("Model.relevantIncompleteAlertBasins", arm_alerts)
        self.assertNotIn("alertFeedsComplete", arm_alerts)
        self.assertIn("Model.basinAlertTransition", global_evaluation)
        self.assertIn("pendingOutlookBasins", global_evaluation)
        self.assertNotIn("alertsArmed = alertFeedsComplete()", global_evaluation)

    def test_full_outages_preserve_the_last_fresh_alert_baselines(self):
        service = (ROOT / "Service.qml").read_text(encoding="utf-8")
        evaluate = service.split("function evaluateAlerts()", 1)[1].split(
            "var events = []", 1
        )[0]

        self.assertIn("if (!settingsReady || !hasLoaded)", evaluate)
        self.assertIn('if (stale || status !== "fresh") return', evaluate)

    def test_new_watch_place_names_are_suggested_without_placeholder_map_copy(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
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
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")
        bar_widget = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn('shell.serviceFor(pluginId)', overlay)
        self.assertIn('bar.shell.serviceFor(pluginId)', bar_widget)
        self.assertIn('shell toggle " + root.pluginId', bar_widget)
        self.assertIn('visible: root.indicatorCount > 0', bar_widget)
        self.assertIn('text: String(root.indicatorCount)', bar_widget)
        self.assertIn("readonly property int personalAlertCount", bar_widget)
        self.assertNotIn('shell summon " + root.pluginId', bar_widget)
        self.assertNotIn(r'\"alerts\":true', bar_widget)
        self.assertIn(r'\"activity\":true', bar_widget)
        self.assertIn("function openSource()", bar_widget)
        self.assertIn("root.bar.shell.hide(root.pluginId)", bar_widget)
        self.assertIn("All locations quiet", bar_widget)
        self.assertNotIn("left open", bar_widget)

    def test_bar_surfaces_unsupported_watch_coverage(self):
        bar_widget = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")

        self.assertIn("Model.watchUnsupportedCount", bar_widget)
        self.assertIn("readonly property bool limitedCoverage", bar_widget)
        self.assertIn("root.indicatorCount > 0 || root.limitedCoverage", bar_widget)
        self.assertIn("Saved locations outside NHC coverage", bar_widget)
        self.assertIn("location outside NHC coverage", bar_widget)

    def test_bar_surfaces_partial_watch_data(self):
        bar_widget = (ROOT / "BarWidget.qml").read_text(encoding="utf-8")

        self.assertIn("Model.watchDataLimitedCount", bar_widget)
        self.assertIn("readonly property bool partialWatchData", bar_widget)
        self.assertIn("NHC data partial", bar_widget)
        self.assertIn("} else if (partialWatchData) {", bar_widget)

    def test_alerts_header_never_calls_limited_destinations_quiet(self):
        overlay = (ROOT / "HurricaneTracker.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property int alertLimitedDestinationCount", overlay)
        self.assertIn(" LOCATION HAS LIMITED COVERAGE", overlay)
        self.assertIn(" LOCATIONS HAVE LIMITED COVERAGE", overlay)


if __name__ == "__main__":
    unittest.main()
