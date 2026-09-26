#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parent.parent


class LibraryConnectorTest(unittest.TestCase):
    def test_configured_folder_becomes_album_tracks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            music = root / "cloud" / "Artist" / "Album"
            music.mkdir(parents=True)
            (music / "01 First.mp3").write_bytes(b"")
            (music / "02 Second.mp3").write_bytes(b"")
            (music / "Folder.jpg").write_bytes(b"cover")
            config = root / "config" / "radio-atlas"
            config.mkdir(parents=True)
            (config / "connectors.json").write_text(json.dumps({
                "connectors": [{
                    "id": "cloud", "type": "folder", "name": "Cloud",
                    "path": str(root / "cloud"), "enabled": True,
                }]
            }))
            tools = root / "bin"
            tools.mkdir()
            ffprobe = tools / "ffprobe"
            ffprobe.write_text("#!/bin/sh\nprintf '%s\\n' '{\"format\":{\"duration\":\"123\",\"tags\":{\"artist\":\"Artist\",\"album_artist\":\"Artist\",\"album\":\"Album\",\"title\":\"First\",\"date\":\"2024\",\"track\":\"1\"}}}'\n")
            ffprobe.chmod(0o755)
            environment = {
                **os.environ,
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_CACHE_HOME": str(root / "cache"),
                "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            }
            result = subprocess.run(
                [str(PROJECT / "radio-library"), "refresh"],
                env=environment, check=True, text=True, capture_output=True,
            )
            rows = json.loads(result.stdout)
            self.assertEqual(len(rows), 2)
            self.assertEqual([row["title"] for row in rows], ["First", "Second"])
            self.assertEqual({row["albumKey"] for row in rows}, {rows[0]["albumKey"]})
            self.assertEqual(rows[0]["provider"], "local")
            self.assertTrue(rows[0]["url"].startswith("file://"))
            self.assertTrue(rows[0]["cover"].endswith("Folder.jpg"))


if __name__ == "__main__":
    unittest.main()
