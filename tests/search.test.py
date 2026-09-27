#!/usr/bin/env python3
"""Integration test for connector-wide search and source labelling."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parents[1]


def write_tool(path, rows):
    path.write_text("#!/usr/bin/env python3\nimport json\nprint(json.dumps(" + repr(rows) + "))\n")
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix="tocador-search-") as temporary:
    root = Path(temporary)
    radio = root / "radio"
    library = root / "library"
    archive = root / "archive"
    tv = root / "tv"
    tv.write_text("""#!/usr/bin/env python3
import json, sys
rows = [
 {"uuid":"tv-1","provider":"iptv-org","kind":"tv","name":"Gil TV","url":"https://tv.test/a.m3u8"},
 {"uuid":"yt-1","provider":"youtube","kind":"tv","name":"Gil Live","url":"https://www.youtube.com/channel/UCaaaaaaaaaaaaaaaaaaaaaa/live"}
]
source = sys.argv[3] if len(sys.argv) > 3 else "all"
print(json.dumps([row for row in rows if source == "all" or
 (source == "youtube" and row["provider"] == "youtube") or
 (source == "iptv" and row["provider"] == "iptv-org")]))
""")
    tv.chmod(0o755)
    write_tool(radio, [{"uuid": "radio-1", "name": "Gil Radio", "url": "https://radio.test/live"}])
    write_tool(library, [
        {"uuid": "local-1", "provider": "local", "source": "library", "kind": "track",
         "name": "Gilberto Gil — Refazenda", "title": "Refazenda", "artist": "Gilberto Gil",
         "album": "Refazenda", "url": "file:///music/refazenda.flac"},
        {"uuid": "local-2", "provider": "local", "source": "library", "kind": "track",
         "name": "Unrelated", "title": "Elsewhere", "artist": "Nobody",
         "album": "Other", "url": "file:///music/other.flac"},
    ])
    archive.write_text("""#!/usr/bin/env python3
import json, sys
source = sys.argv[1]
print(json.dumps([{"uuid": source + "-1", "provider": "tocador", "source": source,
 "kind": "track", "name": "Gil Archive", "title": "Gil Song", "artist": "Gil",
 "album": "Archive", "url": "https://cdn.tocador.cc/song.mp3"}]))
""")
    archive.chmod(0o755)
    environment = os.environ.copy()
    environment.update({
        "TOCADOR_FETCH_PATH": str(radio),
        "TOCADOR_LIBRARY_PATH": str(library),
        "TOCADOR_ARCHIVE_PATH": str(archive),
        "TOCADOR_TV_PATH": str(tv),
    })
    process = subprocess.run(
        [str(PROJECT / "radio-search"), "gil"], check=True,
        capture_output=True, text=True, env=environment,
    )
    rows = json.loads(process.stdout)
    assert [row["uuid"] for row in rows] == ["local-1", "homi-1", "uqt-1", "yt-1", "radio-1", "tv-1"], rows
    assert [row["connectorLabel"] for row in rows] == [
        "MY MUSIC", "TOCADOR · HOMINIS", "TOCADOR · UQT", "YOUTUBE", "RADIO", "IPTV"
    ]
    assert next(row for row in rows if row["uuid"] == "yt-1")["source"] == "youtube"
    assert next(row for row in rows if row["uuid"] == "tv-1")["source"] == "iptv"
    assert all(row["kind"] == "tv" for row in rows if row["uuid"] in ("tv-1", "yt-1"))
    assert "local-2" not in [row["uuid"] for row in rows]

print("universal search tests passed")
