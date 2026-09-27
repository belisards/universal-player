# Universal Player

> One Omarchy media player for world radio, embedded IPTV, YouTube, independent music archives,
> and your own albums.

Every source shares one window, one search box, one Random button, and one
transport control surface. Audio queues also appear in Omarchy's media controls:

- **Radio**: about 50,000 stations from Radio Browser on a rotatable globe
- **IPTV**: about 10,000 free channels from iptv-org, rendered inside the globe canvas
- **YouTube**: live channels from your subscriptions, kept separate from IPTV (audio playback for now)
- **Tocador**: the [UQT and Hominis Canidae](https://tocador.cc/) archives as one album catalog
- **My Music**: any local or synced music folder, such as a Nextcloud library

Universal Player is an [Omarchy](https://omarchy.org) shell plugin: it builds on Omarchy's
Quickshell UI components, so it needs Omarchy and won't run on a plain Hyprland setup.

![Universal Player showing live TV channels across the globe](preview.png)

## Highlights

- **IPTV on the globe.** iptv-org channels are placed by country and play directly inside
  the main globe canvas with the same transport controls as radio.
- **Live YouTube subscriptions.** A separate opt-in source lists channels you follow while
  they are broadcasting. Playback goes through `yt-dlp` in the sandbox and never sees your cookies.
- **Tocador archives.** UQT and Hominis Canidae are aggregated into one catalog of albums
  and tracks, cached for a week.
- **Music-folder connectors.** Point Universal Player at any folder: it indexes albums, finds
  sidecar, media-art, and embedded covers, and never uploads your library.
- **Album world.** An animated, theme-aware cover wall with album queues that advance to
  the next track automatically.
- **Universal search.** One search box covers Radio, IPTV, YouTube, Tocador, and My Music, with a
  source label on every result.
- **Random, everywhere.** The Random button (or `R`) plays a random station, channel, or
  album depending on the tab, and skips what you just heard.
- **Song identification.** For stations without track metadata, the music-note button (or `I`)
  samples about 12 seconds and asks Shazam through [`songrec`](https://github.com/marin-m/SongRec).
  The result appears in the player, the bar tooltip, and a notification.
- **One control surface.** Radio, music, embedded IPTV, and YouTube share the Tocador
  transport controls; IPTV stays inside the main window.

## More features

- Kinetic drag rotation that highlights a nearby station when it settles, deep wheel zoom, and a sidebar that follows the signals visible on the globe
- A fast cached world view that progressively adds thousands of stations and keeps the session catalog when closed
- Country browsing, with country-level map estimates for stations without coordinates
- Automatic country focus for the station that is actually playing
- Favorites and listening history
- Independent volume slider, mute, and bar-wheel volume control
- Audio output picker for any PipeWire sink, including AirPlay speakers exposed as RAOP sinks
- A sandboxed player behind a bounded proxy that refuses private network destinations
- Centered floating window, keyboard navigation, and dismissal when the screensaver starts
- Keeps a failed station selected, with explicit retry or next controls

## Install

```bash
omarchy plugin add https://github.com/belisards/universal-player.git --enable
```

Universal Player uses `bubblewrap`, `curl`, `ffmpeg`, `ffprobe`, `iproute2`, `jq`, `mpv`, `python`,
`qt6-multimedia`, `socat`, `coreutils`, and `util-linux`. These packages ship with Omarchy.
`mpv-mpris` connects playback to `omarchy.media` and is also part of the
standard Omarchy installation.

## Remove

Stop the independent radio player before removing the plugin:

```bash
~/.config/omarchy/plugins/akshar.radio-atlas/radio-player stop
omarchy plugin remove akshar.radio-atlas
```

Favorites, listening history, volume, and the selected audio output remain in
`~/.local/share/radio-atlas/state.json` so reinstalling restores them. Remove
`~/.local/share/radio-atlas/` manually if you also want to delete that data.

## IPTV and YouTube

The **IPTV** tab (or `T`) swaps the globe to live channels from the
community-maintained [iptv-org](https://github.com/iptv-org/api) catalog.
The catalog is downloaded once a day (about 11 MB) to
`~/.cache/omarchy-radio-atlas/tv.json`; searching and browsing a country read
that cache locally. Adult, closed, and legally blocklisted channels are
excluded, and each channel keeps its most reliable stream. Channels only
publish a country, so their signals sit on country estimates.

IPTV uses QtMultimedia to render directly inside the main globe canvas. The
sidebar, queue, volume, pause, previous, next, and stop controls stay in the
same window; IPTV does not open a second video window.

Community streams go offline constantly. `./tv-health check` probes every IPTV
stream (playlist, first variant and first segment, with one retry) and hides the
dead ones from the globe, search and Random; the next check brings back any that
recover. Results live in `~/.cache/omarchy-radio-atlas/tv-health.json`, and a
check that fails almost everywhere is treated as a network problem and discarded.
Run it weekly with a systemd user timer whose service executes
`tv-health check`.

If a channel still fails, use **Not working? Remove this channel** in the video
error overlay. Restore every removed channel with `./tv-health restore all`, and
list dead and removed channels with `./tv-health status -v`.

### Live YouTube subscriptions

Channels you subscribe to on YouTube appear in their own **YouTube** source
while they are broadcasting live. Enable the `youtube-subscriptions` connector in
`~/.config/radio-atlas/connectors.json` and point `auth` at a browser-headers
file from a YouTube Music login, such as the `auth.json` that
[ytmusicapi](https://ytmusicapi.readthedocs.io/en/stable/setup/browser.html)
produces:

```json
{ "id": "youtube", "type": "youtube-subscriptions",
  "auth": "~/.config/yt-music/auth.json", "enabled": true }
```

Universal Player reads that session only to fetch your signed-in YouTube sidebar,
which flags subscriptions that are live, and caches the result for three
minutes in `~/.cache/omarchy-radio-atlas/youtube-live.json` without any
credentials. Playback opens the channel's public `/live` page through `yt-dlp`
inside the sandbox and never receives your cookies. The sidebar covers the
subscriptions YouTube ranks as most relevant, not necessarily all of them,
and live channels have no country, so they are listed but not placed on the
globe. This needs `yt-dlp` with a JavaScript runtime such as `deno`. Many free streams are geo-blocked or
offline at any moment; when one fails, press Next. Open IPTV directly with
`omarchy-shell shell toggle akshar.radio-atlas '{"action":"iptv"}'` or YouTube with
`omarchy-shell shell toggle akshar.radio-atlas '{"action":"youtube"}'`.

## Music-folder connectors

Copy `connectors.json.example` to
`~/.config/radio-atlas/connectors.json`, then enable one or more folder
connectors. Any locally mounted or synced folder works; Nextcloud is simply a
folder connector pointed at its synchronized music directory.

The real configuration lives outside the repository and is ignored if a local
copy is accidentally placed in the checkout. Commit `connectors.json.example`
only; never commit `connectors.json`, which may reveal private usernames and paths.

```json
{
  "connectors": [
    {
      "id": "nextcloud",
      "type": "folder",
      "name": "My Music",
      "path": "/home/you/Nextcloud/music",
      "enabled": true
    }
  ]
}
```

Universal Player scans common audio formats, reads one representative file per
album for metadata, discovers sidecar, media-art, and embedded covers, and caches the
result for an hour. Use the refresh button on the album wall to rebuild the index.
`RADIO_ATLAS_MUSIC_DIRS=/path/one:/path/two` is available as a temporary
override. Local playback is restricted to enabled folder roots.

## Controls

| Input | Action |
| --- | --- |
| Drag or flick globe | Rotate; a flick coasts and highlights a nearby station |
| Wheel over globe | Zoom |
| Click signal | Play station |
| Click country | Browse country |
| `/` | Focus search |
| Up / Down | Move through stations |
| Enter | Play selected station |
| Space | Play or pause |
| `R` | Play a random station, channel, or album from the current tab |
| `T` | Cycle Radio, IPTV, and YouTube |
| `F` | Favorite selected station |
| `I` | Identify the playing song (needs `songrec`) |
| `+` / `-` | Raise or lower radio volume |
| `M` | Mute or unmute |
| Speaker icon | Choose the audio output |
| `?` | Show or hide controls |
| Escape | Hide controls, clear search, or close |

Open the Tocador archives (UQT + Hominis) directly with
`omarchy-shell shell toggle akshar.radio-atlas '{"action":"tocador"}'`, open local albums with
`omarchy-shell shell toggle akshar.radio-atlas '{"action":"albums","source":"library"}'`,
or play them headless with
`radio-player tocador`. Archive catalogs are cached for a week in
`~/.cache/radio-atlas/`.

On the bar, left click opens Universal Player, middle click tunes a random station, right
click stops its player or resumes the most recently played station when stopped,
and the mouse wheel adjusts radio volume. If there is no listening history,
right click does nothing.

If a station disconnects or cannot be played, Universal Player keeps it selected and
shows the failure. Click the play button to retry that station, or Next/Previous
to choose another queued station. It does not automatically reconnect or switch
stations. A repeated opening clip can come from the station's stream server;
retrying may play that same clip again. Radio Browser supplies station listings,
not the audio streams.

Fresh world and country caches load without DNS lookups. The globe skips
off-screen station markers when zoomed in, and player-status updates for the
same station preserve the landing highlight without repainting the globe.
Track-title, volume, and pause updates also preserve your station-list selection.
Theme colors update the globe immediately. Background station expansion stops
after three consecutive attempts add no stations, including failed requests;
reopening Universal Player allows expansion to try again.

## Audio outputs and AirPlay

The speaker button next to the volume slider chooses where radio plays. It lists
every PipeWire output device through `pactl`, which ships with Omarchy's
PipeWire setup. "System default" follows the desktop's current output, the
choice is saved alongside the volume in `~/.local/share/radio-atlas/state.json`,
and switching while playing takes effect immediately. If the chosen device
disappears, mpv may pause and will not always resume when it returns. Choose
"System default" or another available output, then resume playback.

AirPlay speakers appear in this list once PipeWire exposes them as RAOP sinks.
On Arch Linux, the RAOP modules ship in the optional `pipewire-zeroconf`
package. Install it, enable discovery, and restart the user services:

```bash
sudo pacman -S pipewire-zeroconf
mkdir -p ~/.config/pipewire/pipewire.conf.d
cp /usr/share/pipewire/pipewire.conf.avail/50-raop.conf \
  ~/.config/pipewire/pipewire.conf.d/
systemctl --user restart pipewire wireplumber
```

If you run a firewall such as ufw, allow the timing feedback AirPlay speakers
send back to the sender on UDP ports 6001-6002; without it the session connects
but the speaker stays silent:

```bash
sudo ufw allow in from 192.168.0.0/16 to any port 6001:6002 proto udp
```

PipeWire's RAOP discovery occasionally drops a sink when a device briefly
stops announcing itself over mDNS. If an AirPlay speaker disappears from the
output list, re-discover it with `systemctl --user restart pipewire wireplumber`.

PipeWire's RAOP sink streams classic AirPlay audio as uncompressed PCM.
AirPort Express, Apple TV, many AV receivers, and HomePods accept it; AirPlay 2
only features such as HomePod stereo pairs are not supported. A device that
refuses the stream simply stays silent; pick another output to recover.

## Data and privacy

Station data comes from the community-run
[Radio Browser](https://www.radio-browser.info/). Universal Player sends its name
and version as the HTTP user agent. Starting a station calls Radio Browser's
click-count endpoint. Favorites and history stay in
`~/.local/share/radio-atlas/state.json`.

IPTV channel data comes from iptv-org's public API on GitHub Pages; no playback
or search data is sent back to it. Station metadata and stream URLs are community supplied. Labels are rendered
as plain text. Embedded video reads only from a loopback relay; its upstream ffmpeg runs in the
same isolated network namespace as audio playback and reaches
stations through a bounded proxy that rejects private and effectively local
destinations, including after redirects. Remote metadata and local JSON are
size- and record-limited before they reach the shell. Universal Player still connects
directly to third-party stations; HTTP streams are unencrypted. Only play
stations you trust.

Map geometry comes from public-domain Natural Earth data.

Folder connector metadata and cover paths remain local. The index is cached at
`~/.cache/radio-atlas/library.json`; Universal Player does not upload a local
library or send it to Radio Browser or tocador.cc.

## Roadmap

- OpenSubsonic connector for user-owned Navidrome, Gonic, and Airsonic servers
- Native Funkwhale connector for explicitly chosen pods and libraries
- Connector settings UI, per-connector health, and search capabilities
- Optional Jellyfin connector

These are intentionally roadmap items. Universal Player does not scrape commercial
music services or mix anonymous open-catalog discovery into a personal library.

## Troubleshooting

Player and proxy diagnostics are written to
`$XDG_RUNTIME_DIR/omarchy-radio-atlas/mpv.log` and `proxy.log`. Proxy diagnostics
identify request, connection, and relay failures, idle timeouts, and which side
closed a connection. They omit URLs, hostnames, and raw error messages and are
capped at 200 lines per player session. Stopping and starting playback begins
a new session and replaces those logs. A connection closing is not necessarily
an error; it also happens when changing stations or stopping playback.

If saved state is malformed, oversized, or contains too many entries, Universal Player
refuses to overwrite it and reports
`~/.local/share/radio-atlas/state.json`; back up that file before repairing or
removing it.

<a href="https://www.greptile.com/?utm_source=oss_badge&amp;utm_medium=readme&amp;utm_campaign=greptile_for_open_source">
  <img src="https://www.greptile.com/badge.svg" alt="Greptile: The War on Bugs" width="100%">
</a>

## Built upon

Universal Player grew out of
[Radio Atlas](https://github.com/AksharP5/omarchy-radio-atlas) by Akshar Patel, which
contributed the globe, radio browsing, favorites, history, audio outputs, and the
sandboxed player. It also stands on:

- [Tocador](https://tocador.cc/), with the UQT and Hominis Canidae archives
- [Omarchy](https://omarchy.org), [Hyprland](https://hyprland.org), and [Quickshell](https://quickshell.org) with Qt Quick
- [mpv](https://mpv.io) and `mpv-mpris` for playback and media controls
- [Radio Browser](https://www.radio-browser.info/) for radio stations
- [iptv-org](https://github.com/iptv-org/iptv) for TV channels
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) and the [ytmusicapi](https://ytmusicapi.readthedocs.io/) auth format for YouTube
- [SongRec](https://github.com/marin-m/SongRec) for song identification
- [PipeWire](https://pipewire.org) for audio outputs and AirPlay
- [bubblewrap](https://github.com/containers/bubblewrap) for the playback sandbox
- [Natural Earth](https://www.naturalearthdata.com/) for map geometry

## Development

The native QML tests require Qt 6.5 or newer for the globe's drag-event API.
CI runs them on Ubuntu 26.04 with Qt 6.10.

```bash
./tests/run
qmllint -I /usr/share/omarchy/shell BarWidget.qml Globe.qml RadioAtlas.qml
```
