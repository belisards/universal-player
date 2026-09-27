#!/usr/bin/env python3
import gzip
import http.server
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parent.parent

loader = importlib.machinery.SourceFileLoader("tv_health", str(PROJECT / "tv-health"))
spec = importlib.util.spec_from_loader("tv_health", loader)
tv_health = importlib.util.module_from_spec(spec)
loader.exec_module(tv_health)

MASTER = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nlive/chunks.m3u8\n"
MEDIA = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nseg1.ts\n"


class Handler(http.server.BaseHTTPRequestHandler):
    routes = {
        "/master.m3u8": (200, "application/vnd.apple.mpegurl", MASTER.encode()),
        "/live/chunks.m3u8": (200, "application/vnd.apple.mpegurl", MEDIA.replace("seg1", "../seg1").encode()),
        "/seg1.ts": (200, "video/mp2t", b"\x47" * 188),
        "/media.m3u8": (200, "application/vnd.apple.mpegurl", MEDIA.encode()),
        "/login.m3u8": (200, "text/html", b"<html>sign in</html>"),
        "/nosegment.m3u8": (200, "application/vnd.apple.mpegurl", MEDIA.replace("seg1.ts", "missing.ts").encode()),
        "/empty.m3u8": (200, "application/vnd.apple.mpegurl", b"#EXTM3U\n#EXT-X-TARGETDURATION:4\n"),
    }

    def do_GET(self):
        status, kind, body = self.routes.get(self.path, (404, "text/plain", b"no"))
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class ProbeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        tv_health.time.sleep = lambda seconds: None

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def result(self, path):
        return tv_health.probe({"url": self.base + path})

    def test_working_master_and_media_playlists_pass(self):
        self.assertEqual(self.result("/master.m3u8"), (True, ""))
        self.assertEqual(self.result("/media.m3u8"), (True, ""))

    def test_dead_streams_report_a_reason(self):
        self.assertEqual(self.result("/gone.m3u8"), (False, "http 404"))
        self.assertEqual(self.result("/login.m3u8"), (False, "not-a-stream"))
        self.assertEqual(self.result("/nosegment.m3u8"), (False, "http 404"))
        self.assertEqual(self.result("/empty.m3u8"), (False, "empty-playlist"))

    def test_unreachable_host_fails(self):
        self.assertFalse(tv_health.probe({"url": "http://127.0.0.1:9/x.m3u8"})[0])

    def test_gzip_playlists_are_read(self):
        self.assertTrue(tv_health.decode_text(gzip.compress(MEDIA.encode())).startswith("#EXTM3U"))


class HiddenChannelTest(unittest.TestCase):
    def load_tv_fetch(self):
        loader = importlib.machinery.SourceFileLoader("tv_fetch", str(PROJECT / "tv-fetch"))
        spec = importlib.util.spec_from_loader("tv_fetch", loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module

    def test_tv_fetch_hides_dead_and_removed_channels(self):
        tv_fetch = self.load_tv_fetch()
        with tempfile.TemporaryDirectory() as directory:
            tv_fetch.health_file = Path(directory) / "health.json"
            tv_fetch.removed_file = Path(directory) / "removed.json"
            self.assertEqual(tv_fetch.hidden_uuids(), set())
            tv_fetch.health_file.write_text(json.dumps({"a" * 32: {"ok": False}, "b" * 32: {"ok": True}}))
            tv_fetch.removed_file.write_text(json.dumps({"c" * 32: {"name": "Gone", "at": 1}}))
            self.assertEqual(tv_fetch.hidden_uuids(), {"a" * 32, "c" * 32})

    def test_remove_restore_and_status_round_trip(self):
        uuid = "d" * 32
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, "XDG_CONFIG_HOME": directory, "XDG_CACHE_HOME": directory}
            run = lambda *args: subprocess.run(
                [str(PROJECT / "tv-health"), *args], env=env, capture_output=True, text=True)
            self.assertEqual(run("remove", uuid, "Some\nChannel").returncode, 0)
            stored = json.loads((Path(directory) / "radio-atlas" / "tv-removed.json").read_text())
            self.assertEqual(stored[uuid]["name"], "Some Channel")
            self.assertIn("1 channel", run("status").stdout)
            self.assertEqual(run("remove", "../bad").returncode, 2)
            self.assertEqual(run("restore", uuid).returncode, 0)
            self.assertEqual(json.loads((Path(directory) / "radio-atlas" / "tv-removed.json").read_text()), {})


if __name__ == "__main__":
    unittest.main()
