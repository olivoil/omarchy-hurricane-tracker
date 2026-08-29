from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
BACKEND = ROOT / "bin" / "hurricane-tracker-data"

loader = importlib.machinery.SourceFileLoader("hurricane_tracker_data", str(BACKEND))
spec = importlib.util.spec_from_loader(loader.name, loader)
tracker_data = importlib.util.module_from_spec(spec)
loader.exec_module(tracker_data)


def fixture(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()


def kmz(document: bytes, name: str = "document.kml") -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(name, document)
    return output.getvalue()


class BackendTests(unittest.TestCase):
    def test_hurricane_categories_follow_saffir_simpson_thresholds(self):
        self.assertEqual([tracker_data.category_for_wind(value) for value in (63, 64, 82, 83, 95, 96, 112, 113, 136, 137)],
                         [0, 1, 1, 2, 2, 3, 3, 4, 4, 5])
        self.assertEqual(tracker_data.official_mph(40), 45)
        self.assertEqual(tracker_data.official_mph(55), 65)

    def test_forecast_track_extracts_hours_wind_and_coordinates(self):
        points = tracker_data.parse_forecast_track(kmz(fixture("forecast-track.kml")))
        self.assertEqual([point["forecastHour"] for point in points], [0, 24, 48])
        self.assertEqual(points[1]["category"], 3)
        self.assertEqual(points[1]["windMph"], 115)
        self.assertEqual(points[2]["longitude"], -77.2)
        self.assertIn("August 30", points[2]["validTimeLabel"])

    def test_cone_is_closed_and_bounded(self):
        rings = tracker_data.parse_cone(kmz(fixture("cone.kml")))
        self.assertEqual(len(rings), 1)
        self.assertEqual(rings[0][0], rings[0][-1])
        self.assertLessEqual(len(rings[0]), tracker_data.MAX_CONE_POINTS + 1)

    def test_best_track_is_chronological(self):
        points = tracker_data.parse_best_track(kmz(fixture("best-track.kml")))
        self.assertEqual(len(points), 2)
        self.assertEqual(points[0]["classification"], "TS")
        self.assertEqual(points[1]["category"], 1)
        self.assertEqual(points[1]["time"], "2026-08-28T00:00:00Z")

    def test_outlook_combines_area_point_probability_and_remnant_name(self):
        outlooks = tracker_data.parse_outlooks(kmz(fixture("outlook.kml")), "al")
        self.assertEqual(len(outlooks), 1)
        outlook = outlooks[0]
        self.assertEqual(outlook["name"], "Dolly")
        self.assertEqual(outlook["classificationLabel"], "Remnant")
        self.assertEqual(outlook["basinLabel"], "Atlantic")
        self.assertEqual(outlook["sevenDayChance"], 10)
        self.assertEqual(len(outlook["area"]), 1)
        self.assertEqual(outlook["updatedAt"], "2026-08-28T23:39:08Z")

    def test_forecast_discussion_extracts_narrative_and_forecaster(self):
        discussion = tracker_data.parse_forecast_discussion(fixture("discussion.html"))
        self.assertEqual(discussion["title"], "Hurricane Ada Discussion Number 14")
        self.assertIn("Ada has strengthened", discussion["excerpt"])
        self.assertIn("guidance envelope", discussion["excerpt"])
        self.assertNotIn("FORECAST POSITIONS", discussion["excerpt"])
        self.assertEqual(discussion["forecaster"], "Rivera")

    def test_discussion_excerpt_ends_at_a_readable_boundary(self):
        source = "forecast guidance " * 5 + "stays uncertain. " + "Later details " * 100
        excerpt = tracker_data.readable_excerpt(source, 120)
        self.assertLessEqual(len(excerpt), 120)
        self.assertTrue(excerpt.endswith(". …"))
        self.assertIn("stays uncertain", excerpt)

    def test_only_nhc_https_urls_are_accepted(self):
        self.assertTrue(tracker_data.is_safe_url("https://www.nhc.noaa.gov/CurrentStorms.json"))
        self.assertFalse(tracker_data.is_safe_url("http://www.nhc.noaa.gov/CurrentStorms.json"))
        self.assertFalse(tracker_data.is_safe_url("https://nhc.noaa.gov.attacker.example/file"))
        self.assertFalse(tracker_data.is_safe_url("https://user@www.nhc.noaa.gov/file"))

    def test_live_payload_combines_summary_track_cone_and_history(self):
        resources = {
            tracker_data.CURRENT_STORMS_URL: fixture("current-storms.json"),
            "ADA_TRACK.kmz": kmz(fixture("forecast-track.kml")),
            "ADA_CONE.kmz": kmz(fixture("cone.kml")),
            "ada_best_track.kmz": kmz(fixture("best-track.kml")),
            "MIATCDAT1.shtml": fixture("discussion.html"),
            tracker_data.OUTLOOK_URLS["al"]: kmz(fixture("outlook.kml")),
            tracker_data.OUTLOOK_URLS["ep"]: kmz(fixture("empty-outlook.kml")),
            tracker_data.OUTLOOK_URLS["cp"]: kmz(fixture("empty-outlook.kml")),
        }

        def fetcher(url: str, maximum: int) -> bytes:
            for suffix, content in resources.items():
                if url == suffix or url.endswith(suffix):
                    self.assertLessEqual(len(content), maximum)
                    return content
            raise AssertionError(f"unexpected URL {url}")

        payload = tracker_data.build_live_payload(fetcher)
        self.assertEqual(payload["status"], "fresh")
        self.assertEqual(len(payload["storms"]), 1)
        storm = payload["storms"][0]
        self.assertEqual(storm["name"], "Ada")
        self.assertEqual(storm["category"], 2)
        self.assertEqual(storm["windMph"], 105)
        self.assertEqual(len(storm["track"]), 3)
        self.assertEqual(len(storm["cone"]), 1)
        self.assertEqual(len(storm["pastTrack"]), 2)
        self.assertIn("Ada has strengthened", storm["discussionExcerpt"])
        self.assertEqual(payload["outlooks"][0]["name"], "Dolly")
        self.assertEqual(payload["regions"][0]["outlookCount"], 1)

    def test_empty_live_feed_is_a_fresh_quiet_state(self):
        payload = tracker_data.build_live_payload(
            lambda url, maximum: json.dumps({"activeStorms": []}).encode("utf-8")
        )
        self.assertEqual(payload["status"], "fresh")
        self.assertEqual(payload["storms"], [])
        self.assertEqual(payload["outlooks"], [])

    def test_detail_failure_keeps_the_current_storm_visible(self):
        def fetcher(url: str, maximum: int) -> bytes:
            if url == tracker_data.CURRENT_STORMS_URL:
                return fixture("current-storms.json")
            raise tracker_data.DataError("detail unavailable")

        payload = tracker_data.build_live_payload(fetcher)
        self.assertEqual(len(payload["storms"]), 1)
        storm = payload["storms"][0]
        self.assertEqual(storm["name"], "Ada")
        self.assertEqual(storm["track"], [])
        self.assertEqual(set(storm["dataWarnings"]), {
            "track unavailable", "cone unavailable", "pastTrack unavailable",
            "discussion unavailable"
        })

    def test_network_failure_returns_a_marked_stale_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "storms.json"
            cached = {
                "schemaVersion": 2,
                "status": "fresh",
                "stale": False,
                "fetchedAt": "2026-08-28T12:00:00Z",
                "checkedAt": "2026-08-28T12:00:00Z",
                "source": tracker_data.source_metadata(),
                "error": "",
                "storms": [],
                "outlooks": [],
                "regions": [],
            }
            tracker_data.write_cache(cached, path)

            def failure(url: str, maximum: int) -> bytes:
                raise tracker_data.DataError("offline")

            payload = tracker_data.fetch_with_fallback(failure, path)
            self.assertEqual(payload["status"], "cached")
            self.assertTrue(payload["stale"])
            self.assertEqual(payload["fetchedAt"], "2026-08-28T12:00:00Z")
            self.assertIn("National Hurricane Center", payload["error"])

    def test_cache_file_is_private_and_round_trips(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested" / "storms.json"
            payload = {
                "schemaVersion": 2,
                "status": "fresh",
                "stale": False,
                "fetchedAt": "2026-08-28T12:00:00Z",
                "checkedAt": "2026-08-28T12:00:00Z",
                "source": tracker_data.source_metadata(),
                "error": "",
                "storms": [],
                "outlooks": [],
                "regions": [],
            }
            tracker_data.write_cache(payload, path)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(tracker_data.read_cache(path), payload)


if __name__ == "__main__":
    unittest.main()
