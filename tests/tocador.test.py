#!/usr/bin/env python3
import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


PROJECT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("radio_tocador", str(PROJECT / "radio-tocador"))
spec = importlib.util.spec_from_loader("radio_tocador", loader)
radio_tocador = importlib.util.module_from_spec(spec)
loader.exec_module(radio_tocador)


class Response:
    headers = {"Content-Type": "image/jpeg"}

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self, _limit):
        return b"jpeg cover"


class TocadorCoverTest(unittest.TestCase):
    def test_cover_is_downloaded_with_cdn_headers_and_reused(self):
        with tempfile.TemporaryDirectory() as temporary:
            original_cache = radio_tocador.CACHE
            radio_tocador.CACHE = temporary
            album = {"path": "1969 - Artist - Album", "has_cover": True}
            try:
                with mock.patch.object(radio_tocador.urllib.request, "urlopen", return_value=Response()) as opened:
                    uri = radio_tocador.cached_cover("uqt", album)
                    request = opened.call_args.args[0]
                    self.assertIn("Mozilla", request.get_header("User-agent"))
                    self.assertEqual(request.get_header("Referer"), "https://tocador.cc/")
                self.assertTrue(uri.startswith("file://"))
                self.assertEqual(Path(uri.removeprefix("file://")).read_bytes(), b"jpeg cover")
                with mock.patch.object(radio_tocador.urllib.request, "urlopen") as opened:
                    self.assertEqual(radio_tocador.cached_cover("uqt", album), uri)
                    opened.assert_not_called()
            finally:
                radio_tocador.CACHE = original_cache


if __name__ == "__main__":
    unittest.main()
