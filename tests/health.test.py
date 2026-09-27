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


class HiddenChannelTest(unittest.TestCase):
    def load_tv_fetch(self):
        loader = importlib.machinery.SourceFileLoader("tv_fetch", str(PROJECT / "tv-fetch"))
        spec = importlib.util.spec_from_loader("tv_fetch", loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module

    def test_tv_fetch_hides_removed_but_can_still_resolve_them(self):
        tv_fetch = self.load_tv_fetch()
        with tempfile.TemporaryDirectory() as directory:
            tv_fetch.removed_file = Path(directory) / "removed.json"
            self.assertEqual(tv_fetch.hidden_uuids(), set())
            tv_fetch.removed_file.write_text(json.dumps({"c" * 32: {"name": "Gone", "at": 1}}))
            self.assertEqual(tv_fetch.hidden_uuids(), {"c" * 32})

    def test_remove_restore_and_status_round_trip(self):
        uuid = "d" * 32
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, "XDG_CONFIG_HOME": directory}
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
