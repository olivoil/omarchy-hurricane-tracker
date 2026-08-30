from __future__ import annotations

import importlib.machinery
import importlib.util
import http.server
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from unittest import mock
import zipfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
BACKEND = ROOT / "bin" / "omanado-data"

loader = importlib.machinery.SourceFileLoader("omanado_data", str(BACKEND))
spec = importlib.util.spec_from_loader(loader.name, loader)
omanado = importlib.util.module_from_spec(spec)
loader.exec_module(omanado)


def fixture(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()


def kmz(document: bytes, name: str = "document.kml") -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(name, document)
    return output.getvalue()


class FakeResponse:
    def __init__(self, body: bytes, *, url: str = "https://example.test/data",
                 status: int = 200, headers: dict[str, str] | None = None):
        self.body = body
        self.url = url
        self.status = status
        self.headers = headers or {}
        self.read_size = 0

    def __enter__(self):
        return self

    def __exit__(self, exception_type, exception, traceback):
        return False

    def getcode(self):
        return self.status

    def geturl(self):
        return self.url

    def read(self, size: int = -1):
        self.read_size = size
        return self.body if size < 0 else self.body[:size]


class FakeOpener:
    def __init__(self, response: FakeResponse):
        self.response = response
        self.request = None
        self.timeout = None

    def open(self, request, timeout=None):
        self.request = request
        self.timeout = timeout
        return self.response


class BackendTests(unittest.TestCase):
    def test_hurricane_categories_follow_saffir_simpson_thresholds(self):
        self.assertEqual([omanado.category_for_wind(value) for value in (63, 64, 82, 83, 95, 96, 112, 113, 136, 137)],
                         [0, 1, 1, 2, 2, 3, 3, 4, 4, 5])
        self.assertEqual(omanado.official_mph(40), 45)
        self.assertEqual(omanado.official_mph(55), 65)

    def test_forecast_track_extracts_hours_wind_and_coordinates(self):
        points = omanado.parse_forecast_track(kmz(fixture("forecast-track.kml")))
        self.assertEqual([point["forecastHour"] for point in points], [0, 24, 48])
        self.assertEqual(points[1]["category"], 3)
        self.assertEqual(points[1]["windMph"], 115)
        self.assertEqual(points[2]["longitude"], -77.2)
        self.assertIn("August 30", points[2]["validTimeLabel"])

    def test_cone_is_closed_and_bounded(self):
        rings = omanado.parse_cone(kmz(fixture("cone.kml")))
        self.assertEqual(len(rings), 1)
        self.assertEqual(rings[0][0], rings[0][-1])
        self.assertLessEqual(len(rings[0]), omanado.MAX_CONE_POINTS + 1)

    def test_best_track_is_chronological(self):
        points = omanado.parse_best_track(kmz(fixture("best-track.kml")))
        self.assertEqual(len(points), 2)
        self.assertEqual(points[0]["classification"], "TS")
        self.assertEqual(points[1]["category"], 1)
        self.assertEqual(points[1]["time"], "2026-08-28T00:00:00Z")

    def test_outlook_combines_area_point_probability_and_remnant_name(self):
        outlooks = omanado.parse_outlooks(kmz(fixture("outlook.kml")), "al")
        self.assertEqual(len(outlooks), 1)
        outlook = outlooks[0]
        self.assertEqual(outlook["name"], "Dolly")
        self.assertEqual(outlook["classificationLabel"], "Remnant")
        self.assertEqual(outlook["basinLabel"], "Atlantic")
        self.assertEqual(outlook["sevenDayChance"], 10)
        self.assertEqual(len(outlook["area"]), 1)
        self.assertEqual(outlook["updatedAt"], "2026-08-28T23:39:08Z")

    def test_forecast_discussion_extracts_narrative_and_forecaster(self):
        discussion = omanado.parse_forecast_discussion(fixture("discussion.html"))
        self.assertEqual(discussion["title"], "Hurricane Ada Discussion Number 14")
        self.assertIn("Ada has strengthened", discussion["excerpt"])
        self.assertIn("guidance envelope", discussion["excerpt"])
        self.assertNotIn("FORECAST POSITIONS", discussion["excerpt"])
        self.assertEqual(discussion["forecaster"], "Rivera")

    def test_discussion_excerpt_ends_at_a_readable_boundary(self):
        source = "forecast guidance " * 5 + "stays uncertain. " + "Later details " * 100
        excerpt = omanado.readable_excerpt(source, 120)
        self.assertLessEqual(len(excerpt), 120)
        self.assertTrue(excerpt.endswith(". …"))
        self.assertIn("stays uncertain", excerpt)

    def test_only_nhc_https_urls_are_accepted(self):
        self.assertTrue(omanado.is_safe_url("https://www.nhc.noaa.gov/CurrentStorms.json"))
        self.assertFalse(omanado.is_safe_url("http://www.nhc.noaa.gov/CurrentStorms.json"))
        self.assertFalse(omanado.is_safe_url("https://nhc.noaa.gov.attacker.example/file"))
        self.assertFalse(omanado.is_safe_url("https://user@www.nhc.noaa.gov/file"))

    def test_api_response_reader_enforces_status_type_and_streaming_size_limit(self):
        oversized = FakeResponse(
            b"x" * 500,
            status=200,
            headers={"Content-Type": "application/json", "Content-Length": "8"},
        )
        with self.assertRaisesRegex(omanado.DataError, "size limit"):
            omanado.read_bounded_response(
                oversized, 64, "Open-Meteo", require_json=True
            )
        self.assertEqual(oversized.read_size, 65)

        with self.assertRaisesRegex(omanado.DataError, "non-success"):
            omanado.read_bounded_response(FakeResponse(b"{}", status=503), 64, "API")
        with self.assertRaisesRegex(omanado.DataError, "not JSON"):
            omanado.read_bounded_response(
                FakeResponse(b"{}", headers={"Content-Type": "text/html"}),
                64,
                "API",
                require_json=True,
            )

    def test_api_response_reader_rejects_declared_oversize_before_reading(self):
        response = FakeResponse(
            b"{}",
            headers={"Content-Type": "application/json", "Content-Length": "65"},
        )
        with self.assertRaisesRegex(omanado.DataError, "size limit"):
            omanado.read_bounded_response(response, 64, "API", require_json=True)
        self.assertEqual(response.read_size, 0)

    def test_open_meteo_request_is_fixed_encoded_and_refuses_redirects(self):
        url = omanado.open_meteo_geocoding_url("  Sarasota, FL  ")
        self.assertTrue(omanado.is_open_meteo_geocoding_url(url))
        self.assertIn("name=Sarasota%2C+FL", url)
        self.assertIn("count=8", url)
        self.assertFalse(
            omanado.is_open_meteo_geocoding_url(
                "https://geocoding-api.open-meteo.com.attacker.test/v1/search?name=x"
            )
        )

        redirected = FakeResponse(
            b"{}",
            url="https://attacker.test/private",
            headers={"Content-Type": "application/json"},
        )
        with self.assertRaisesRegex(omanado.DataError, "redirect"):
            omanado.fetch_direct_bytes(
                url,
                64,
                omanado.is_open_meteo_geocoding_url,
                "Open-Meteo",
                "application/json",
                5,
                require_json=True,
                opener=FakeOpener(redirected),
            )
        self.assertIsNone(
            omanado.NoRedirectHandler().redirect_request(None, None, 302, "", {}, url)
        )

    def test_direct_opener_does_not_follow_an_http_redirect(self):
        requested_paths = []

        class RedirectHandler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format_string, *args):
                return

            def do_GET(self):
                requested_paths.append(self.path)
                if self.path == "/redirect":
                    self.send_response(302)
                    self.send_header("Location", "/target")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                body = b'{"unexpected":true}'
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RedirectHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            opener = omanado.urllib.request.build_opener(
                omanado.urllib.request.ProxyHandler({}), omanado.NoRedirectHandler()
            )
            with self.assertRaisesRegex(omanado.DataError, "redirect"):
                omanado.fetch_direct_bytes(
                    base_url + "/redirect",
                    64,
                    lambda candidate: candidate.startswith(base_url + "/"),
                    "Fixture",
                    "application/json",
                    1,
                    require_json=True,
                    opener=opener,
                )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertEqual(requested_paths, ["/redirect"])

    def test_place_search_normalizes_safe_results_and_keeps_personal_data_out(self):
        payload = omanado.search_places(
            "Sarasota, FL",
            lambda query: {
                "results": [
                    {
                        "id": 4172131,
                        "name": "Sarasota",
                        "latitude": 27.33643,
                        "longitude": -82.53065,
                        "feature_code": "PPLA2",
                        "admin1": "Florida",
                        "country": "United States",
                    }
                ]
            },
        )
        self.assertEqual(payload["schemaVersion"], 1)
        self.assertEqual(payload["provider"], "open-meteo-geonames")
        self.assertEqual(payload["query"], "Sarasota, FL")
        self.assertEqual(payload["results"][0], {
            "id": "open-meteo:4172131",
            "name": "Sarasota",
            "context": "Florida, United States",
            "kind": "City",
            "latitude": 27.33643,
            "longitude": -82.53065,
        })
        self.assertNotIn("Home", json.dumps(payload))

    def test_place_search_rejects_unsafe_remote_text_and_invalid_coordinates(self):
        safe = {
            "id": 1,
            "name": "São Tomé & Príncipe",
            "latitude": 0.3365,
            "longitude": 6.7273,
            "feature_code": "PPLC",
            "admin1": "Água Grande",
            "country": "São Tomé and Príncipe",
        }
        unsafe_rows = [
            {**safe, "id": 2, "name": "<img src='probe'>"},
            {**safe, "id": 3, "admin1": "Île\0de-France"},
            {**safe, "id": 4, "country": "France > Europe"},
            {**safe, "id": 5, "name": "x" * 257},
            {**safe, "id": 6, "latitude": 120},
            {**safe, "id": 7, "latitude": "0.3365"},
            {**safe, "id": 8, "longitude": True},
        ]
        payload = omanado.normalize_place_search_payload(
            "Sao Tome", {"results": [safe] + unsafe_rows}
        )
        self.assertEqual(len(payload["results"]), 1)
        self.assertEqual(payload["results"][0]["name"], "São Tomé & Príncipe")

    def test_place_search_query_and_result_counts_are_bounded(self):
        with self.assertRaises(omanado.DataError):
            omanado.normalize_place_query("x")
        with self.assertRaises(omanado.DataError):
            omanado.normalize_place_query("Paris\nFrance")
        with self.assertRaises(omanado.DataError):
            omanado.normalize_place_query("x" * 121)

        rows = [
            {
                "id": index,
                "name": f"Place {index}",
                "latitude": 10,
                "longitude": 20,
                "feature_code": "PPL",
                "country": "Somewhere",
            }
            for index in range(100)
        ]
        payload = omanado.normalize_place_search_payload("Place", {"results": rows})
        self.assertEqual(len(payload["results"]), omanado.MAX_PLACE_SEARCH_RESULTS)

    def test_reverse_geocoding_request_is_fixed_bounded_and_refuses_redirects(self):
        url = omanado.nominatim_reverse_url(24.1426, -110.3128)
        self.assertTrue(omanado.is_nominatim_reverse_url(url))
        self.assertIn("lat=24.14260", url)
        self.assertIn("lon=-110.31280", url)
        self.assertFalse(
            omanado.is_nominatim_reverse_url(
                "https://nominatim.openstreetmap.org.attacker.test/reverse?lat=1&lon=2"
            )
        )
        self.assertFalse(omanado.is_nominatim_reverse_url(url + "&lat=1"))
        redirected = FakeResponse(
            b"{}",
            url="https://attacker.test/private",
            headers={"Content-Type": "application/json"},
        )
        with self.assertRaisesRegex(omanado.DataError, "redirect"):
            omanado.fetch_reverse_geocode_json(
                24.1426, -110.3128, opener=FakeOpener(redirected)
            )

    def test_reverse_geocoding_normalizes_only_safe_place_names(self):
        payload = omanado.reverse_geocode_place(
            24.1426,
            -110.3128,
            lambda latitude, longitude: {
                "name": "La Paz",
                "display_name": "La Paz, Baja California Sur, Mexico",
                "address": {
                    "city": "La Paz",
                    "state": "Baja California Sur",
                    "country": "Mexico",
                },
            },
        )
        self.assertEqual(payload, {
            "schemaVersion": 1,
            "provider": "nominatim-openstreetmap",
            "latitude": 24.1426,
            "longitude": -110.3128,
            "name": "La Paz",
            "context": "Baja California Sur, Mexico",
        })
        with self.assertRaises(omanado.DataError):
            omanado.normalize_reverse_geocode_payload(
                24.1426,
                -110.3128,
                {
                    "name": "<script>",
                    "address": {"city": "La Paz", "country": "Mexico"},
                },
            )

    def test_live_payload_combines_summary_track_cone_and_history(self):
        resources = {
            omanado.CURRENT_STORMS_URL: fixture("current-storms.json"),
            "ADA_TRACK.kmz": kmz(fixture("forecast-track.kml")),
            "ADA_CONE.kmz": kmz(fixture("cone.kml")),
            "ada_best_track.kmz": kmz(fixture("best-track.kml")),
            "MIATCDAT1.shtml": fixture("discussion.html"),
            omanado.OUTLOOK_URLS["al"]: kmz(fixture("outlook.kml")),
            omanado.OUTLOOK_URLS["ep"]: kmz(fixture("empty-outlook.kml")),
            omanado.OUTLOOK_URLS["cp"]: kmz(fixture("empty-outlook.kml")),
        }

        def fetcher(url: str, maximum: int) -> bytes:
            for suffix, content in resources.items():
                if url == suffix or url.endswith(suffix):
                    self.assertLessEqual(len(content), maximum)
                    return content
            raise AssertionError(f"unexpected URL {url}")

        payload = omanado.build_live_payload(fetcher)
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
        self.assertEqual(payload["incompleteOutlookBasins"], [])

    def test_empty_live_feed_is_a_fresh_quiet_state(self):
        def fetcher(url: str, maximum: int) -> bytes:
            if url == omanado.CURRENT_STORMS_URL:
                return json.dumps({"activeStorms": []}).encode("utf-8")
            return kmz(fixture("empty-outlook.kml"))

        payload = omanado.build_live_payload(fetcher)
        self.assertEqual(payload["status"], "fresh")
        self.assertEqual(payload["storms"], [])
        self.assertEqual(payload["outlooks"], [])
        self.assertEqual(payload["incompleteOutlookBasins"], [])

    def test_partial_outlook_failure_is_declared_in_the_payload(self):
        def fetcher(url: str, maximum: int) -> bytes:
            if url == omanado.CURRENT_STORMS_URL:
                return json.dumps({"activeStorms": []}).encode("utf-8")
            if url == omanado.OUTLOOK_URLS["al"]:
                raise omanado.DataError("Atlantic outlook unavailable")
            return kmz(fixture("empty-outlook.kml"))

        payload = omanado.build_live_payload(fetcher)

        self.assertEqual(payload["status"], "fresh")
        self.assertEqual(payload["incompleteOutlookBasins"], ["al"])
        self.assertTrue(omanado.valid_payload(payload))
        self.assertFalse(omanado.valid_payload({
            **payload, "incompleteOutlookBasins": ["al", "al"]
        }))
        self.assertFalse(omanado.valid_payload({
            **payload, "incompleteOutlookBasins": ["unknown"]
        }))
        self.assertFalse(omanado.valid_payload({
            **payload, "incompleteOutlookBasins": [{}]
        }))
        legacy_payload = dict(payload)
        legacy_payload.pop("incompleteOutlookBasins")
        self.assertTrue(omanado.valid_payload(legacy_payload))

    def test_detail_failure_keeps_the_current_storm_visible(self):
        def fetcher(url: str, maximum: int) -> bytes:
            if url == omanado.CURRENT_STORMS_URL:
                return fixture("current-storms.json")
            raise omanado.DataError("detail unavailable")

        payload = omanado.build_live_payload(fetcher)
        self.assertEqual(len(payload["storms"]), 1)
        storm = payload["storms"][0]
        self.assertEqual(storm["name"], "Ada")
        self.assertEqual(storm["track"], [])
        self.assertEqual(set(storm["dataWarnings"]), {
            "track unavailable", "cone unavailable", "pastTrack unavailable",
            "discussion unavailable"
        })

    def test_missing_forecast_urls_mark_geometry_incomplete(self):
        current = json.loads(fixture("current-storms.json"))
        current["activeStorms"][0].pop("forecastTrack")
        current["activeStorms"][0].pop("trackCone")

        def fetcher(url: str, maximum: int) -> bytes:
            if url == omanado.CURRENT_STORMS_URL:
                return json.dumps(current).encode("utf-8")
            if url.endswith("ada_best_track.kmz"):
                return kmz(fixture("best-track.kml"))
            if url.endswith("MIATCDAT1.shtml"):
                return fixture("discussion.html")
            if url in omanado.OUTLOOK_URLS.values():
                return kmz(fixture("empty-outlook.kml"))
            raise AssertionError(f"unexpected URL {url}")

        payload = omanado.build_live_payload(fetcher)

        self.assertEqual(set(payload["storms"][0]["dataWarnings"]), {
            "track unavailable", "cone unavailable"
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
                "source": omanado.source_metadata(),
                "error": "",
                "storms": [],
                "outlooks": [],
                "regions": [],
            }
            omanado.write_cache(cached, path)

            def failure(url: str, maximum: int) -> bytes:
                raise omanado.DataError("offline")

            payload = omanado.fetch_with_fallback(failure, path)
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
                "source": omanado.source_metadata(),
                "error": "",
                "storms": [],
                "outlooks": [],
                "regions": [],
            }
            omanado.write_cache(payload, path)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(omanado.read_cache(path), payload)

    def test_watch_places_are_sanitized_private_and_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config" / "watch-places.json"
            requested = {
                "schemaVersion": 99,
                "places": [
                    {
                        "id": "home!",
                        "name": "  Home\nbase  ",
                        "latitude": 21.1619,
                        "longitude": -86.8515,
                        "radiusKm": 9000,
                    },
                    {
                        "id": "home",
                        "name": "Duplicate",
                        "latitude": 20,
                        "longitude": -80,
                        "radiusKm": 100,
                    },
                    {
                        "id": "invalid",
                        "name": "Invalid",
                        "latitude": 120,
                        "longitude": 0,
                    },
                ]
                + [
                    {
                        "id": f"place-{index}",
                        "name": f"Place {index}",
                        "latitude": 10 + index,
                        "longitude": -70,
                        "radiusKm": 250,
                    }
                    for index in range(20)
                ],
            }
            saved = omanado.write_watch_config(requested, path)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(saved["schemaVersion"], 1)
            self.assertEqual(len(saved["places"]), omanado.MAX_WATCH_PLACES)
            self.assertEqual(saved["places"][0]["id"], "home")
            self.assertEqual(saved["places"][0]["name"], "Home base")
            self.assertEqual(saved["places"][0]["radiusKm"], 2000)
            self.assertEqual(omanado.read_watch_config(path), saved)

    def test_corrupt_watch_file_is_reported_without_being_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "omanado" / "watch-places.json"
            path.parent.mkdir(parents=True)
            path.write_text("{not valid json", encoding="utf-8")

            environment = os.environ.copy()
            environment["XDG_CONFIG_HOME"] = directory
            result = subprocess.run(
                [str(BACKEND), "watch-load"],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("watch-place settings", result.stderr)
            self.assertEqual(path.read_text(encoding="utf-8"), "{not valid json")

    def test_invalid_persisted_watch_records_are_rejected_without_sanitizing(self):
        valid = {
            "id": "home",
            "name": "Home",
            "latitude": 21.1619,
            "longitude": -86.8515,
            "radiusKm": 1000,
        }
        invalid_configs = [
            {"schemaVersion": 1, "places": [{**valid, "name": ""}]},
            {"schemaVersion": 1, "places": [{**valid, "latitude": 120}]},
            {"schemaVersion": 1, "places": [valid, {**valid, "name": "Duplicate"}]},
            {"schemaVersion": 1, "places": [{**valid, "radiusKm": 9000}]},
            {
                "schemaVersion": 1,
                "places": [
                    {**valid, "id": f"place-{index}", "name": f"Place {index}"}
                    for index in range(omanado.MAX_WATCH_PLACES + 1)
                ],
            },
        ]

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "watch-places.json"
            for config in invalid_configs:
                with self.subTest(config=config):
                    original = json.dumps(config)
                    path.write_text(original, encoding="utf-8")
                    with self.assertRaises(omanado.DataError):
                        omanado.read_watch_config(path)
                    self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_empty_or_relative_xdg_config_home_uses_home_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            expected = Path(directory) / ".config" / "omanado" / "watch-places.json"
            for configured in ("", "relative/config"):
                with self.subTest(configured=configured), mock.patch.dict(
                    os.environ,
                    {"HOME": directory, "XDG_CONFIG_HOME": configured},
                    clear=False,
                ):
                    self.assertEqual(omanado.watch_config_path(), expected)

    def test_watch_place_radius_defaults_to_forecast_awareness_range(self):
        place = omanado.normalized_watch_place(
            {
                "id": "cancun",
                "name": "Cancún",
                "latitude": 21.1619,
                "longitude": -86.8515,
            }
        )
        self.assertEqual(place["radiusKm"], 1000)


if __name__ == "__main__":
    unittest.main()
