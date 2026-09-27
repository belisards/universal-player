#!/usr/bin/env python3
import importlib.machinery
import pathlib
import unittest
from unittest import mock


PROJECT = pathlib.Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("video_relay", str(PROJECT / "radio-video-relay"))
relay = loader.load_module()


class VideoRelayTest(unittest.TestCase):
    def test_localhost_contract_and_ffmpeg_headers(self):
        command = relay.ffmpeg_command(
            "/plugin/radio-session", "https://example.test/live.m3u8", "Agent/1", "https://ref.test/")
        self.assertEqual(command[:2], ["/plugin/radio-session", "ffmpeg"])
        self.assertIn("-user_agent", command)
        self.assertIn("-referer", command)
        self.assertEqual(command[-3:], ["-f", "mpegts", "pipe:1"])

    def test_url_rejects_credentials_controls_and_non_http(self):
        for value in (
            "file:///etc/passwd",
            "https://user:pass@example.test/live",
            "https://example.test/live#fragment",
            "https://example.test/live\nX-Evil: yes",
        ):
            with self.assertRaises(ValueError):
                relay.validate_url(value)

    def test_headers_reject_injection(self):
        with self.assertRaises(ValueError):
            relay.validate_header("ok\r\nX-Evil: yes", 512, "user-agent")

    def test_parser_requires_executable_session(self):
        with self.assertRaises(SystemExit):
            relay.parse_args(["--url", "https://example.test/live", "--session", "/no/such/session"])

    def test_stream_stop_allows_a_sequential_reconnect(self):
        class FakeProcess:
            def __init__(self, pid):
                self.pid = pid
                self.stdout = object()

            def poll(self):
                return None

            def wait(self, timeout=None):
                return 0

        processes = [FakeProcess(101), FakeProcess(102)]
        with mock.patch.object(relay.subprocess, "Popen", side_effect=processes) as popen:
            state = relay.RelayState("/plugin/radio-session", "https://example.test/live", "", "")
            first = state.start()
            with mock.patch.object(relay.os, "killpg"):
                state.stop_stream()
            second = state.start()

        self.assertIs(first, processes[0])
        self.assertIs(second, processes[1])
        self.assertEqual(popen.call_count, 2)

    def test_global_stop_prevents_reconnect(self):
        process = mock.Mock(pid=103)
        process.poll.return_value = None
        with mock.patch.object(relay.subprocess, "Popen", return_value=process):
            state = relay.RelayState("/plugin/radio-session", "https://example.test/live", "", "")
            state.start()
            with mock.patch.object(relay.os, "killpg"):
                state.stop()
            with self.assertRaises(RuntimeError):
                state.start()


if __name__ == "__main__":
    unittest.main()
