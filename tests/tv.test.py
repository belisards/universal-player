#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("tv_fetch", str(PROJECT / "tv-fetch"))
spec = importlib.util.spec_from_loader("tv_fetch", loader)
tv_fetch = importlib.util.module_from_spec(spec)
loader.exec_module(tv_fetch)


def channel(channel_id, country="BR", **extra):
    return {"id": channel_id, "name": channel_id.split(".")[0], "country": country,
            "categories": ["news"], "is_nsfw": False, "closed": None,
            "website": "https://example.com", "network": None, **extra}


def stream(channel_id, url, **extra):
    return {"channel": channel_id, "feed": None, "url": url, "quality": "720p",
            "labels": [], "user_agent": None, "referrer": None, **extra}


class TvCatalogTest(unittest.TestCase):
    def build(self, channels, streams, blocklist=()):
        return tv_fetch.build_rows(channels, streams, list(blocklist),
                                   [{"code": "BR", "name": "Brazil"}, {"code": "UK", "name": "United Kingdom"}])

    def test_rows_match_the_station_shape(self):
        rows = self.build([channel("Globo.br")], [stream("Globo.br", "https://example.com/a.m3u8")])
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertRegex(row["uuid"], r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
        self.assertEqual(row["uuid"], tv_fetch.station_uuid("Globo.br"))
        self.assertEqual((row["kind"], row["countryCode"], row["country"]), ("tv", "BR", "Brazil"))
        self.assertEqual((row["codec"], row["tags"]), ("720p", "news"))

    def test_unsafe_blocked_and_adult_channels_are_dropped(self):
        rows = self.build(
            [channel("Ok.br"), channel("Adult.br", is_nsfw=True), channel("Gone.br", closed="2020-01-01"),
             channel("Blocked.br"), channel("Rtmp.br")],
            [stream("Ok.br", "https://example.com/ok.m3u8"), stream("Adult.br", "https://example.com/x"),
             stream("Gone.br", "https://example.com/x"), stream("Blocked.br", "https://example.com/x"),
             stream("Rtmp.br", "rtmp://example.com/live"), stream(None, "https://example.com/orphan"),
             stream("Ok.br", "https://example.com/\nbad")],
            blocklist=[{"channel": "Blocked.br"}])
        self.assertEqual([row["name"] for row in rows], ["Ok"])

    def test_best_stream_wins_and_headers_are_kept(self):
        rows = self.build([channel("News.br")], [
            stream("News.br", "https://example.com/geo.m3u8", labels=["Geo-blocked"], quality="1080p"),
            stream("News.br", "http://example.com/plain.m3u8", quality="480p"),
            stream("News.br", "https://example.com/best.m3u8", user_agent="Agent/1", referrer="https://ref/"),
        ])
        self.assertEqual(rows[0]["url"], "http://example.com/plain.m3u8")
        rows = self.build([channel("News.br")], [
            stream("News.br", "https://example.com/best.m3u8", user_agent="Agent/1", referrer="https://ref/"),
        ])
        self.assertEqual((rows[0]["userAgent"], rows[0]["referrer"]), ("Agent/1", "https://ref/"))

    def test_uk_maps_to_the_globe_code(self):
        rows = self.build([channel("Bbc.uk", country="UK")], [stream("Bbc.uk", "https://example.com/b")])
        self.assertEqual((rows[0]["countryCode"], rows[0]["country"]), ("GB", "United Kingdom"))
        self.assertIsNone(rows[0]["latitude"])

    def test_small_places_get_coordinates_near_their_capital(self):
        rows = self.build([channel("Mediacorp.sg", country="SG")], [stream("Mediacorp.sg", "https://example.com/s")])
        latitude, longitude = tv_fetch.FALLBACK_COORDINATES["SG"]
        self.assertAlmostEqual(rows[0]["latitude"], latitude, delta=0.31)
        self.assertAlmostEqual(rows[0]["longitude"], longitude, delta=0.31)

    def test_cli_serves_a_cached_catalog_offline(self):
        rows = self.build([channel("Globo.br"), channel("Bbc.uk", country="UK")],
                          [stream("Globo.br", "https://example.com/g"), stream("Bbc.uk", "https://example.com/b")])
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary) / "omarchy-radio-atlas"
            cache.mkdir()
            (cache / "tv.json").write_text(json.dumps(rows))
            live_id = "UC" + "a" * 22
            youtube_row = tv_fetch.youtube_live_channels(
                {"entry": guide_entry(live_id, "Gil Live", True)})[0]
            (cache / "youtube-live.json").write_text(json.dumps([youtube_row]))
            config = Path(temporary) / "radio-atlas"
            config.mkdir()
            (config / "connectors.json").write_text(json.dumps({"connectors": [{
                "type": "youtube-subscriptions", "auth": "~/unused-auth.json", "enabled": True
            }]}))
            environment = {**os.environ, "XDG_CACHE_HOME": temporary, "PATH": "/nonexistent",
                           "XDG_CONFIG_HOME": temporary}

            def run(*arguments):
                result = subprocess.run(["/usr/bin/python3", str(PROJECT / "tv-fetch"), *arguments],
                                        env=environment, capture_output=True, text=True)
                return result.returncode, json.loads(result.stdout) if result.returncode == 0 else None

            self.assertEqual(len(run("world")[1]), 3)
            self.assertEqual(len(run("world", "", "iptv")[1]), 2)
            self.assertEqual([row["name"] for row in run("world", "", "youtube")[1]], ["Gil Live"])
            self.assertEqual([row["name"] for row in run("country", "uk")[1]], ["Bbc"])
            self.assertEqual(run("country", "uk", "youtube")[1], [])
            self.assertEqual([row["name"] for row in run("search", "glo")[1]], ["Globo"])
            self.assertEqual(run("search", "glo", "youtube")[1], [])
            self.assertEqual([row["name"] for row in run("search", "gil", "youtube")[1]], ["Gil Live"])
            self.assertEqual(run("resolve", tv_fetch.station_uuid("Bbc.uk"))[1][0]["name"], "Bbc")
            self.assertEqual(run("world", "", "unknown")[0], 2)
            self.assertEqual(run("world-more")[1], [])
            self.assertEqual(run("country", "1")[0], 2)
            self.assertEqual(run("resolve", "not-an-id")[0], 2)


def guide_entry(channel_id, title, live):
    return {"guideEntryRenderer": {
        "formattedTitle": {"simpleText": title},
        "navigationEndpoint": {"browseEndpoint": {"browseId": channel_id}},
        "thumbnail": {"thumbnails": [{"url": "//yt3.example/small"}, {"url": "//yt3.example/large"}]},
        "badges": {"liveBroadcasting": live},
    }}


class YoutubeSubscriptionsTest(unittest.TestCase):
    def test_only_live_channels_become_tv_rows(self):
        live_id, idle_id = "UC" + "a" * 22, "UC" + "b" * 22
        guide = {"items": [{"guideSubscriptionsSectionRenderer": {"items": [
            guide_entry(live_id, "News Live", True), guide_entry(idle_id, "Idle", False),
            guide_entry(live_id, "News Live", True), guide_entry("FEwhat_to_watch", "Home", True),
        ]}}]}
        rows = tv_fetch.youtube_live_channels(guide)
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["url"], f"https://www.youtube.com/channel/{live_id}/live")
        self.assertEqual(row["uuid"], tv_fetch.station_uuid(live_id, "youtube"))
        self.assertNotEqual(row["uuid"], tv_fetch.station_uuid(live_id))
        self.assertEqual((row["kind"], row["provider"], row["favicon"]),
                         ("tv", "youtube", "https://yt3.example/large"))

    def test_session_signature_binds_the_account(self):
        header = tv_fetch.youtube_authorization(
            {"SAPISID": "a", "__Secure-3PAPISID": "b"}, "user", "https://www.youtube.com")
        schemes = [part for part in header.split() if part.isupper()]
        self.assertEqual(schemes, ["SAPISIDHASH", "SAPISID3PHASH"])
        self.assertTrue(all(part.endswith("_u") for part in header.split() if not part.isupper()))

    def test_subscriptions_are_opt_in(self):
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "connectors.json"
            original = tv_fetch.connectors_file
            tv_fetch.connectors_file = config
            try:
                self.assertIsNone(tv_fetch.youtube_auth_path())
                self.assertEqual(tv_fetch.youtube_live_rows(), [])
                config.write_text(json.dumps({"connectors": [
                    {"type": "folder", "path": "~/Music"},
                    {"type": "youtube-subscriptions", "auth": "~/auth.json", "enabled": False}]}))
                self.assertIsNone(tv_fetch.youtube_auth_path())
                config.write_text(json.dumps({"connectors": [
                    {"type": "youtube-subscriptions", "auth": "~/auth.json"}]}))
                self.assertEqual(tv_fetch.youtube_auth_path(), Path("~/auth.json").expanduser())
            finally:
                tv_fetch.connectors_file = original


if __name__ == "__main__":
    unittest.main()
