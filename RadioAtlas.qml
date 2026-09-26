import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "RadioModel.js" as RadioModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var countries: []
  property var worldStations: []
  property var results: []
  property var favorites: []
  property var recent: []
  property string mode: "world"
  property string catalog: "radio"
  property var catalogWorlds: ({})
  property string activeCountryCode: ""
  property string activeCountryName: ""
  property bool helpVisible: false
  property int selectedIndex: -1
  property var selectedStation: null
  property bool keyboardSelectionVisible: false

  property bool fetching: false
  property string fetchAction: ""
  property string fetchValue: ""
  property string fetchCatalog: ""
  property string pendingFetchAction: ""
  property string pendingFetchValue: ""
  property string fetchError: ""
  property string fetchOutput: ""
  property string fetchStderr: ""
  property string worldExpandOutput: ""
  readonly property int worldStationLimit: 5000
  property int worldExpansionMisses: 0

  property bool playerRunning: false
  property bool playerPaused: false
  property string streamError: ""
  property bool playerMuted: false
  property int playerVolume: 70
  property int reportedVolume: 70
  property int pendingVolume: -1
  property string playerTitle: ""
  property string identifyState: ""
  property string identifyText: ""
  property string identifyStationUuid: ""
  readonly property bool identifying: identifyProcess.running || identifyState === "listening"
  readonly property string identifiedTrack: identifyStationUuid === playingStationUuid
    && (identifyState === "done" || identifyState === "none" || identifyState === "error")
    ? identifyText : ""
  property string playerOutput: ""
  property var audioOutputs: []
  property string outputsError: ""
  property bool outputMenuOpen: false
  readonly property var outputChoices: {
    var rows = [{ id: "", label: "System default" }]
    for (var i = 0; i < audioOutputs.length; i++) rows.push(audioOutputs[i])
    return rows
  }

  property var playingStation: null
  property string playingStationUuid: ""
  property string recordedStationUuid: ""
  property string lastRandomUuid: ""
  property bool playCancellationRequested: false
  property var pendingPlayStation: null
  property string pendingPlayScope: ""
  property var pendingPlayStations: []
  property bool statusReady: false
  readonly property bool playPreparing: playerActionProcess.running
    && playerActionProcess.action === "play"
  readonly property bool playerActionBusy: playerActionProcess.running || stopProcess.running
  property int playlistPosition: -1
  property int playlistCount: 0
  property string playerError: ""
  property string localError: ""
  property bool localReloadPending: false
  property var pendingFavoriteRequests: []
  property string pendingRecentUuid: ""
  property string albumSource: "library"
  property string albumError: ""
  property string universalSearchOutput: ""
  property string universalSearchQuery: ""

  readonly property string fetchPath: Qt.resolvedUrl("radio-fetch").toString().replace(/^file:\/\//, "")
  readonly property string tvFetchPath: Qt.resolvedUrl("tv-fetch").toString().replace(/^file:\/\//, "")
  readonly property bool tvCatalog: catalog === "tv"
  readonly property string stationNoun: tvCatalog ? "channels" : "stations"
  readonly property string playerPath: Qt.resolvedUrl("radio-player").toString().replace(/^file:\/\//, "")
  readonly property string searchPath: Qt.resolvedUrl("radio-search").toString().replace(/^file:\/\//, "")
  readonly property string statePath: Qt.resolvedUrl("radio-state").toString().replace(/^file:\/\//, "")
  readonly property string runtimePath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-radio-atlas"
  readonly property string statusPath: runtimePath + "/status.json"
  readonly property string identifyPath: Qt.resolvedUrl("radio-identify").toString().replace(/^file:\/\//, "")
  readonly property string identifyResultPath: runtimePath + "/identify.json"
  readonly property string playSelectionPath: runtimePath + "/play-selection.json"
  readonly property string favoriteSelectionPath: runtimePath + "/favorite-selection.json"

  readonly property var displayStations: mode === "favorites"
    ? favorites
    : (mode === "recent" ? recent : results)
  readonly property bool albumMode: mode === "albums"
  readonly property var albumCards: {
    var cards = []
    var seen = ({})
    for (var i = 0; i < results.length; i++) {
      var row = results[i]
      var key = String(row && (row.albumKey || row.uuid) || "")
      if (!key || seen["$" + key]) continue
      seen["$" + key] = true
      cards.push(row)
    }
    return cards
  }
  readonly property string albumSourceTitle: albumSource === "library"
    ? "MY MUSIC" : "TOCADOR"
  readonly property string albumSourceSubtitle: albumSource === "library"
    ? albumCards.length + " albums from your connected folders"
    : albumCards.length + " albums from UQT + Hominis Canidae"
  readonly property var currentGeoStations:
    RadioModel.mergeGeoStations(worldStations, displayStations, countries)
  readonly property string playingStationName: playingStation
    ? String(playingStation.name || "").trim() : ""
  readonly property string playingTrackTitle: {
    var title = String(playerTitle || "").trim()
    var station = playingStationName.toLowerCase()
    return title && station && title.toLowerCase() !== station ? title : ""
  }
  readonly property string trackLine: playingTrackTitle
    || (identifying ? "Listening for the song…" : identifiedTrack)
  readonly property bool playingTrack: playingStation && playingStation.kind === "track"
  readonly property bool playingTv: playingStation && playingStation.kind === "tv"

  function applyIdentifyState(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var result = JSON.parse(raw || "{}")
      identifyState = String(result.state || "")
      identifyStationUuid = String(result.stationUuid || "")
      var text = result.state === "done"
        ? String(result.title || "") + (result.artist ? " — " + result.artist : "")
        : String(result.message || "")
      identifyText = text.replace(/[\r\n\t]+/g, " ").slice(0, 200)
      var ttl = result.state === "done" ? 300000 : result.state === "listening" ? 60000 : 20000
      var remaining = Number(result.at || 0) * 1000 + ttl - Date.now()
      identifyExpiry.stop()
      if (remaining <= 0) identifyState = ""
      else {
        identifyExpiry.interval = remaining
        identifyExpiry.start()
      }
    } catch (error) {
      return
    }
  }

  function identifySong() {
    if (!playerRunning || playerPaused || identifying) return
    identifyState = "listening"
    identifyStationUuid = playingStationUuid
    identifyProcess.running = true
  }

  readonly property bool remoteMode: mode !== "favorites" && mode !== "recent"
  readonly property bool lightTheme:
    0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b > 0.5

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
  property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  property color favoriteColor: lightTheme ? "#8a6100" : "#f2c94c"
  property color mapBackground: lightTheme ? "#e7e6e1" : "#090a0c"
  property color mapSphere: lightTheme ? "#d2d0ca" : "#11151a"
  property color mapLand: lightTheme ? "#a9aaa6" : "#283039"
  property color mapGrid: lightTheme ? "#3f454a" : "#7d8791"

  property bool windowSetupReady: false
  property bool windowFrameReady: false
  property string pendingOpenPayload: ""
  readonly property int preferredWidth: Style.space(1180)
  readonly property int preferredHeight: Style.space(760)
  readonly property string windowPath:
    Qt.resolvedUrl("radio-window").toString().replace(/^file:\/\//, "")
  readonly property int cardWidth: panel.width
  readonly property int cardHeight: panel.height
  readonly property int headerHeight: Style.space(68)
  readonly property int sidebarWidth: Math.min(Style.space(390), cardWidth * 0.39)
  readonly property var controlSections: [
    {
      title: "KEYBOARD",
      inputWidth: 112,
      controls: [
        { input: "/", action: "Search" },
        { input: "UP / DOWN", action: "Select station" },
        { input: "ENTER", action: "Play selected station" },
        { input: "SPACE", action: "Play or pause" },
        { input: "R", action: "Play something random" },
        { input: "T", action: "Switch between radio and TV" },
        { input: "F", action: "Favorite selected station" },
        { input: "I", action: "Identify playing song" },
        { input: "M", action: "Mute or unmute" },
        { input: "+ / -", action: "Change volume" },
        { input: "ESC", action: "Back, clear, or close" },
        { input: "?", action: "Show or hide controls" }
      ]
    },
    {
      title: "MOUSE AND BAR",
      inputWidth: 124,
      controls: [
        { input: "DRAG / FLICK", action: "Spin globe" },
        { input: "GLOBE WHEEL", action: "Zoom" },
        { input: "CLICK SIGNAL", action: "Play station" },
        { input: "CLICK COUNTRY", action: "Browse stations" },
        { input: "BAR LEFT", action: "Open or close" },
        { input: "BAR MIDDLE", action: "Tune randomly" },
        { input: "BAR RIGHT", action: "Stop playback" },
        { input: "BAR WHEEL", action: "Change volume" },
        { input: "SPEAKER", action: "Choose audio output" }
      ]
    }
  ]

  function isHelpKey(event) {
    return event.key === Qt.Key_Question || event.text === "?"
      || (event.key === Qt.Key_Slash && (event.modifiers & Qt.ShiftModifier))
  }

  function toggleControls() {
    helpVisible = !helpVisible
    outputMenuOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function registerWindowSetup() {
    windowSetupReady = false
    if (!windowSetupProcess.running) windowSetupProcess.running = true
  }

  function open(payloadJson) {
    if (!windowSetupReady) {
      pendingOpenPayload = payloadJson || "{}"
      return
    }
    openWindow(payloadJson)
  }

  function openWindow(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (error) { payload = ({}) }

    opened = true
    worldExpansionMisses = 0
    windowFrameReady = false
    windowRevealTimer.stop()
    panel.visible = true
    fetchError = ""
    loadState()
    if (payload.action === "random") {
      if (worldStations.length === 0) showWorld()
      tuneRandom()
    } else if (payload.action === "tocador") {
      if (worldStations.length === 0) showWorld()
      showAlbums("tocador")
    } else if (payload.action === "albums") {
      showAlbums(payload.source || "library")
    } else if (payload.action === "tv") {
      showCatalog("tv")
    } else if (worldStations.length === 0) showWorld()
    scheduleWorldExpansion(800)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    helpVisible = false
    outputMenuOpen = false
    globe.stopKineticRotation(true)
    opened = false
    windowFrameReady = false
    windowRevealTimer.stop()
    panel.visible = false
    worldExpandTimer.stop()
    if (worldExpandProcess.running) worldExpandProcess.running = false
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "akshar.radio-atlas")
  }

  function scheduleWindowReveal() {
    if (windowFrameReady || !panel.visible || !panel.backingWindowVisible) return
    windowRevealTimer.restart()
  }

  function handleHyprlandEvent(event) {
    var eventName = String(event && event.name || "")
    if (eventName === "configreloaded") {
      windowSetupReloadTimer.restart()
      return
    }
    if (!opened || eventName !== "openwindow") return
    var parts = []
    try {
      parts = event.parse(4)
    } catch (error) {
      parts = String(event && event.data || "").split(",")
    }
    var windowClass = String(parts[2] || "")
    if (windowClass === "org.omarchy.screensaver") {
      dismiss()
    }
  }

  function highlightStationCountry(station, focusGlobe) {
    if (!station) {
      activeCountryCode = ""
      activeCountryName = ""
      return
    }
    activeCountryCode = String(station.countryCode || "").toUpperCase()
    activeCountryName = String(station.country || activeCountryCode)
    if (focusGlobe !== true) return
    var latitude = Number(station.latitude)
    var longitude = Number(station.longitude)
    if (station.latitude !== null && station.longitude !== null
        && isFinite(latitude) && isFinite(longitude)) {
      globe.focusCoordinate(latitude, longitude)
    } else if (activeCountryCode) {
      globe.focusCountry(activeCountryCode)
    }
  }

  function restorePlayingCountry(focusGlobe) {
    if (playerRunning && playingStation) {
      highlightStationCountry(playingStation, focusGlobe === true)
      return
    }
    activeCountryCode = ""
    activeCountryName = ""
  }

  function setSelection(index, fromKeyboard) {
    keyboardSelectionVisible = fromKeyboard === true
    var stations = displayStations
    if (!Array.isArray(stations) || stations.length === 0) {
      selectedIndex = -1
      selectedStation = null
      return
    }
    selectedIndex = Math.max(0, Math.min(stations.length - 1, index))
    selectedStation = stations[selectedIndex]
    stationList.currentIndex = selectedIndex
    stationList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function moveSelection(delta) {
    if (displayStations.length === 0) return
    if (selectedIndex < 0) setSelection(delta < 0 ? displayStations.length - 1 : 0, true)
    else setSelection((selectedIndex + delta + displayStations.length) % displayStations.length, true)
  }

  function setStationList(nextMode, stations) {
    mode = nextMode
    if (nextMode !== "favorites" && nextMode !== "recent") results = stations
    setSelection(stations.length > 0 ? 0 : -1)
  }

  function scheduleWorldExpansion(delay) {
    if (!opened || catalog !== "radio" || worldStations.length === 0
        || worldStations.length >= worldStationLimit || worldExpansionMisses >= 3) return
    worldExpandTimer.interval = Math.max(500, Number(delay || 1600))
    worldExpandTimer.restart()
  }

  function cancelPendingFetch() {
    pendingFetchAction = ""
    pendingFetchValue = ""
  }

  function cancelPendingPlay() {
    pendingPlayStation = null
    pendingPlayScope = ""
    pendingPlayStations = []
  }

  function startFetch(action, value) {
    var nextValue = value || ""
    if (fetchProcess.running) {
      if (fetchAction === action && fetchValue === nextValue && fetchCatalog === catalog) {
        cancelPendingFetch()
        return
      }
      if (pendingFetchAction === action && pendingFetchValue === nextValue) return
      pendingFetchAction = action
      pendingFetchValue = nextValue
      fetching = true
      return
    }
    fetching = true
    fetchAction = action
    fetchValue = nextValue
    fetchCatalog = catalog
    fetchError = ""
    fetchOutput = ""
    fetchStderr = ""
    var path = tvCatalog ? tvFetchPath : fetchPath
    fetchProcess.command = nextValue ? [path, action, nextValue] : [path, action]
    fetchProcess.running = true
  }

  function showWorld(refresh) {
    searchDebounce.stop()
    cancelPendingFetch()
    searchField.text = ""
    restorePlayingCountry(false)
    fetchError = ""
    localError = ""
    setStationList("world", worldStations)
    if (refresh !== false) startFetch("world", "")
  }

  function showCatalog(name) {
    var next = name === "tv" ? "tv" : "radio"
    if (next !== catalog) {
      var worlds = Object.assign({}, catalogWorlds)
      worlds[catalog] = worldStations
      catalogWorlds = worlds
      worldExpandTimer.stop()
      if (worldExpandProcess.running) worldExpandProcess.running = false
      catalog = next
      worldStations = Array.isArray(worlds[next]) ? worlds[next] : []
      worldExpansionMisses = 0
    }
    showWorld()
    scheduleWorldExpansion(800)
  }

  function showFavorites() {
    searchDebounce.stop()
    cancelPendingFetch()
    searchField.text = ""
    mode = "favorites"
    restorePlayingCountry(true)
    fetchError = ""
    localError = ""
    setSelection(favorites.length > 0 ? 0 : -1)
  }

  function showAlbums(source, refresh) {
    searchDebounce.stop()
    cancelPendingFetch()
    searchField.text = ""
    var nextSource = String(source || albumSource)
    if (nextSource !== "library" && nextSource !== "tocador")
      nextSource = "library"
    albumSource = nextSource
    restorePlayingCountry(false)
    fetchError = ""
    localError = ""
    albumError = ""
    setStationList("albums", [])
    if (albumProcess.running) albumProcess.running = false
    albumProcess.source = nextSource
    albumProcess.command = nextSource === "library"
      ? [playerPath, "library-list"].concat(refresh === true ? ["refresh"] : [])
      : [playerPath, "tocador-list", nextSource]
    albumProcess.running = true
  }

  function showTocador() { showAlbums("tocador") }

  function playAlbum(row) {
    if (!row) return
    var key = String(row.albumKey || row.uuid || "")
    var tracks = results.filter(function(candidate) {
      return String(candidate && (candidate.albumKey || candidate.uuid) || "") === key
    })
    if (tracks.length === 0) return
    var index = RadioModel.indexByUuid(displayStations, row.uuid)
    if (index >= 0) setSelection(index)
    playStation(row, albumSource === "library" ? "local-selection" : "selection", tracks)
  }

  function showRecent() {
    searchDebounce.stop()
    cancelPendingFetch()
    searchField.text = ""
    mode = "recent"
    restorePlayingCountry(true)
    fetchError = ""
    localError = ""
    setSelection(recent.length > 0 ? 0 : -1)
  }

  function previewSearch(text) {
    var query = String(text || "").trim()
    if (!query) {
      showWorld()
      return false
    }
    restorePlayingCountry(false)
    fetchError = ""
    setStationList("search", RadioModel.searchStations(worldStations, query))
    return true
  }

  function search(text) {
    var query = String(text || "").trim()
    if (!previewSearch(query)) return
    if (universalSearchProcess.running) universalSearchProcess.running = false
    universalSearchQuery = query
    universalSearchOutput = ""
    universalSearchProcess.query = query
    universalSearchProcess.command = [searchPath, query]
    universalSearchProcess.running = true
  }

  function browseCountry(code, name) {
    var countryCode = String(code || "").toUpperCase()
    if (!/^[A-Z]{2}$/.test(countryCode)) return
    var countryName = String(name || "")
    if (!countryName) {
      for (var i = 0; i < countries.length; i++) {
        var properties = countries[i] && countries[i].properties
        if (String(properties && properties.code || "").toUpperCase() !== countryCode) continue
        countryName = String(properties.name || "")
        break
      }
    }
    if (!countryName) countryName = countryCode
    searchDebounce.stop()
    cancelPendingFetch()
    var cachedStations = RadioModel.stationsForCountry(worldStations, countryCode)
    worldStations = RadioModel.prioritizeStations(
      cachedStations, worldStations, worldStationLimit)
    setStationList("country", cachedStations)
    activeCountryCode = countryCode
    activeCountryName = countryName
    fetchError = ""
    searchField.text = countryName
    startFetch("country", countryCode)
    keyCatcher.forceActiveFocus()
  }

  function tuneRandom() {
    searchDebounce.stop()
    cancelPendingFetch()
    searchField.text = ""
    setStationList("random", [])
    restorePlayingCountry(false)
    fetchError = ""
    startFetch("random", randomExclusions())
  }

  function playRandom() {
    if (!albumMode) {
      tuneRandom()
      return
    }
    var playingKey = playingStation ? String(playingStation.albumKey || playingStation.uuid || "") : ""
    var pool = albumCards.filter(function(row) {
      return String(row.albumKey || row.uuid || "") !== playingKey
    })
    if (pool.length === 0) pool = albumCards
    if (pool.length === 0) return
    playAlbum(pool[Math.floor(Math.random() * pool.length)])
  }

  function randomExclusions() {
    var output = []
    var seen = ({})

    function append(uuid) {
      var value = String(uuid || "")
      if (!/^[0-9A-Fa-f-]{20,64}$/.test(value) || seen["$" + value]) return
      seen["$" + value] = true
      output.push(value)
    }

    append(playingStationUuid)
    append(lastRandomUuid)
    for (var i = 0; i < recent.length && output.length < 32; i++)
      append(recent[i] && recent[i].uuid)
    return output.join(",")
  }

  function activateMapStation(station) {
    var index = RadioModel.indexByUuid(displayStations, station.uuid)
    if (index < 0) {
      index = RadioModel.indexByUuid(worldStations, station.uuid)
      if (index < 0) return
      showWorld(false)
    }
    setSelection(index)
    playSelected()
  }

  function playlistScope() {
    if (mode === "world") return "world"
    if (mode === "favorites") return "favorites"
    if (mode === "recent") return "recent"
    if (mode === "albums") return albumSource === "library" ? "library" : "tocador"
    return "results"
  }

  function playSelected() {
    if (!selectedStation) return
    playStation(selectedStation, playlistScope(), displayStations)
  }

  function writeSelection(fileView, station, stations) {
    var rows = RadioModel.stationWindow(stations, station && station.uuid, 500)
    if (rows.length === 0) return false
    fileView.setText(JSON.stringify(rows) + "\n")
    return true
  }

  function playStation(station, scope, stations) {
    if (!station) return
    if (playerActionBusy) {
      pendingPlayStation = station
      pendingPlayScope = scope
      pendingPlayStations = Array.isArray(stations) ? stations.slice(0) : []
      return
    }
    cancelPendingPlay()
    var playerScope = scope
    if (scope === "world" || scope === "results"
        || scope === "selection" || scope === "local-selection") {
      if (!writeSelection(playSelectionFile, station, stations)) {
        playerError = "Could not prepare this station"
        return
      }
      playerScope = scope === "local-selection" ? "local-selection" : "selection"
    }
    playCancellationRequested = false
    highlightStationCountry(station, true)
    playerError = ""
    playerActionProcess.action = "play"
    playerActionProcess.output = ""
    playerActionProcess.errorOutput = ""
    playerActionProcess.command = [playerPath, "play", station.uuid, playerScope]
    playerActionProcess.running = true
  }

  function playPendingStation() {
    if (!pendingPlayStation || playerActionBusy) return
    var station = pendingPlayStation
    var scope = pendingPlayScope
    var stations = pendingPlayStations
    cancelPendingPlay()
    playStation(station, scope, stations)
  }

  function playerAction(action) {
    if (playerActionBusy) return
    playerError = ""
    playerActionProcess.action = action
    playerActionProcess.output = ""
    playerActionProcess.errorOutput = ""
    playerActionProcess.command = [playerPath, action]
    playerActionProcess.running = true
  }

  function stopPlayer() {
    cancelPendingPlay()
    if (stopProcess.running || playCancellationRequested) return
    if (playerActionProcess.running && !playPreparing) return
    if (playPreparing) playCancellationRequested = true
    playerError = ""
    stopProcess.command = [playerPath, "stop"]
    stopProcess.running = true
  }

  function applyPlayerState(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536)
        throw new Error("Player status is too large")
      var state = JSON.parse(raw || "{}")
      var previousUuid = playingStationUuid
      var nextPlayingStation = state.station && typeof state.station === "object"
        && String(state.station.uuid || "") ? state.station : null
      var nextPlayingUuid = nextPlayingStation ? String(nextPlayingStation.uuid) : ""
      playerRunning = state.running === true
      playerPaused = state.paused === true
      streamError = String(state.error || "").replace(/[\r\n\t]+/g, " ").slice(0, 200)
      playerMuted = state.muted === true
      playerOutput = /^[A-Za-z0-9._:+-]{0,160}$/.test(String(state.output || ""))
        ? String(state.output) : ""
      var nextVolume = Math.round(Number(state.volume === undefined ? 70 : state.volume))
      reportedVolume = isFinite(nextVolume) ? Math.max(0, Math.min(100, nextVolume)) : 70
      if (pendingVolume < 0) playerVolume = reportedVolume
      playerTitle = String(state.title || (nextPlayingStation && nextPlayingStation.name) || "")
        .replace(/[\r\n\t]+/g, " ").slice(0, 512)
      playlistPosition = Number(state.playlistPosition === undefined ? -1 : state.playlistPosition)
      playlistCount = Number(state.playlistCount || 0)

      var playingChanged = playerRunning && nextPlayingUuid && nextPlayingUuid !== previousUuid
      playingStation = nextPlayingStation
      playingStationUuid = playerRunning ? nextPlayingUuid : ""
      if (playerError === "Player status is unavailable") playerError = ""
      if (!playerRunning) recordedStationUuid = ""

      var matchingIndex = nextPlayingUuid
        ? RadioModel.indexByUuid(displayStations, nextPlayingUuid) : -1
      if (matchingIndex < 0 && playerTitle) {
        for (var i = 0; i < displayStations.length; i++) {
          if (displayStations[i].name === playerTitle) { matchingIndex = i; break }
        }
      }
      if (playingChanged && matchingIndex >= 0) setSelection(matchingIndex)

      var countryStation = nextPlayingStation || (matchingIndex >= 0 ? selectedStation : null)
      if (playerRunning && playingChanged && countryStation)
        highlightStationCountry(countryStation, true)
      if (state.loaded === true && nextPlayingUuid && nextPlayingUuid !== recordedStationUuid) {
        recordedStationUuid = nextPlayingUuid
        recordPlayed(nextPlayingUuid)
      }
    } catch (error) {
      playerError = "Player status is unavailable"
    }
  }

  function setPlayerVolume(value) {
    pendingVolume = Math.max(0, Math.min(100, Math.round(value)))
    playerVolume = pendingVolume
    playerError = ""
    volumeTimer.restart()
  }

  function changePlayerVolume(delta) {
    var current = pendingVolume >= 0 ? pendingVolume : playerVolume
    setPlayerVolume(current + delta)
  }

  function flushPlayerVolume() {
    if (stopProcess.running) {
      volumeTimer.restart()
      return
    }
    if (volumeProcess.running || pendingVolume < 0) return
    volumeProcess.submittedVolume = pendingVolume
    volumeProcess.output = ""
    volumeProcess.errorOutput = ""
    volumeProcess.command = [root.playerPath, "volume", String(pendingVolume)]
    volumeProcess.running = true
  }

  function refreshOutputs() {
    if (outputsProcess.running) return
    outputsError = ""
    outputsProcess.output = ""
    outputsProcess.errorOutput = ""
    outputsProcess.command = [playerPath, "outputs"]
    outputsProcess.running = true
  }

  function selectOutput(value) {
    var sink = String(value || "")
    if (outputProcess.running) return
    playerError = ""
    outputProcess.submittedOutput = sink
    outputProcess.output = ""
    outputProcess.errorOutput = ""
    outputProcess.command = sink
      ? [playerPath, "output", sink]
      : [playerPath, "output"]
    outputProcess.running = true
  }

  function toggleOutputMenu() {
    if (outputMenuOpen) {
      outputMenuOpen = false
      return
    }
    outputMenuOpen = true
    refreshOutputs()
  }

  function outputLabel(sink) {
    for (var i = 0; i < audioOutputs.length; i++) {
      if (audioOutputs[i].id === sink) return audioOutputs[i].label
    }
    return sink
  }

  function loadState() {
    if (stateProcess.running) {
      localReloadPending = true
      return
    }
    localReloadPending = false
    stateProcess.action = "get"
    stateProcess.output = ""
    stateProcess.errorOutput = ""
    stateProcess.command = [statePath, "get"]
    stateProcess.running = true
  }

  function requestLocalStateReload() {
    localReloadPending = true
    Qt.callLater(reloadLocalStateWhenIdle)
  }

  function reloadLocalStateWhenIdle() {
    if (!localReloadPending || stateProcess.running || historyProcess.running
        || pendingFavoriteRequests.length > 0 || pendingRecentUuid) return
    loadState()
  }

  function applyLocalState(raw) {
    try {
      var state = JSON.parse(raw || "{}")
      favorites = Array.isArray(state.favorites) ? state.favorites : []
      recent = Array.isArray(state.recent) ? state.recent : []
      localError = ""
    } catch (error) {
      localError = "Saved stations could not be loaded"
    }
  }

  function isFavorite(uuid) {
    return RadioModel.indexByUuid(favorites, uuid) >= 0
  }

  function toggleFavorite(uuid) {
    if (!uuid) return
    localError = ""
    var request = { uuid: uuid, rows: [] }
    var index = RadioModel.indexByUuid(displayStations, uuid)
    if (remoteMode && index >= 0) {
      request.rows = RadioModel.stationWindow(displayStations, uuid, 500)
      if (request.rows.length === 0) {
        localError = "Favorite could not be updated"
        return
      }
    }
    if (stateProcess.running) {
      pendingFavoriteRequests = pendingFavoriteRequests.concat([request])
      return
    }
    startFavorite(request)
  }

  function startFavorite(request) {
    if (request.rows.length > 0)
      favoriteSelectionFile.setText(JSON.stringify(request.rows) + "\n")
    stateProcess.action = "favorite"
    stateProcess.output = ""
    stateProcess.errorOutput = ""
    stateProcess.command = [statePath, "favorite", request.uuid]
    stateProcess.running = true
  }

  function recordPlayed(uuid) {
    if (!uuid) return
    if (historyProcess.running) {
      pendingRecentUuid = uuid
      return
    }
    startRecordPlayed(uuid)
  }

  function startRecordPlayed(uuid) {
    historyProcess.output = ""
    historyProcess.errorOutput = ""
    historyProcess.command = [statePath, "played", uuid]
    historyProcess.running = true
  }

  function refreshLocalSelection() {
    if (mode !== "favorites" && mode !== "recent") return
    var stations = displayStations
    var preferredUuid = selectedStation ? selectedStation.uuid : playingStationUuid
    var index = preferredUuid ? RadioModel.indexByUuid(stations, preferredUuid) : -1
    if (index < 0 && stations.length > 0) index = Math.min(Math.max(selectedIndex, 0), stations.length - 1)
    setSelection(index)
  }

  function emptyStateText() {
    if (fetchError) return fetchError
    if (localError) return localError
    if (mode === "favorites") return "No favorites yet. Select a station and press F."
    if (mode === "recent") return "No listening history yet."
    if (mode === "albums") return albumError || (albumProcess.running
      ? "Loading " + albumSourceTitle + "…" : "No albums found in this connector.")
    if (mode === "search") return universalSearchProcess.running
      ? "Searching Radio, TV, Tocador, and My Music…"
      : "Nothing matches “" + String(searchField.text || "").trim() + "”."
    if (mode === "country") return "No working " + stationNoun + " found in " + (activeCountryName || "this country") + "."
    return "No working " + stationNoun + " found."
  }

  FileView {
    path: Qt.resolvedUrl("assets/countries.json").toString().replace(/^file:\/\//, "")
    watchChanges: false
    printErrors: true
    onLoaded: {
      try {
        var collection = JSON.parse(text())
        root.countries = Array.isArray(collection.features) ? collection.features : []
      } catch (error) {
        root.countries = []
        root.fetchError = "Map data could not be loaded"
      }
    }
  }

  FileView {
    path: root.statusReady ? root.statusPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyPlayerState(text())
    onFileChanged: reload()
  }

  FileView {
    path: root.statusReady ? root.identifyResultPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyIdentifyState(text())
    onFileChanged: reload()
  }

  Process {
    id: identifyProcess
    command: [root.identifyPath]
  }

  Timer {
    id: identifyExpiry
    onTriggered: root.identifyState = ""
  }

  FileView {
    id: playSelectionFile
    path: root.playSelectionPath
    preload: false
    watchChanges: false
    blockWrites: true
    atomicWrites: true
    printErrors: true
    onSaveFailed: root.playerError = "Could not prepare this station"
  }

  FileView {
    id: favoriteSelectionFile
    path: root.favoriteSelectionPath
    preload: false
    watchChanges: false
    blockWrites: true
    atomicWrites: true
    printErrors: true
    onSaveFailed: root.localError = "Favorite could not be updated"
  }

  Process {
    id: windowSetupProcess
    command: [root.windowPath, String(root.preferredWidth), String(root.preferredHeight)]
    onExited: function(exitCode) {
      root.windowSetupReady = true
      if (!root.pendingOpenPayload) return
      var payload = root.pendingOpenPayload
      root.pendingOpenPayload = ""
      root.openWindow(payload)
    }
  }

  Process {
    id: statusInitProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.statusReady = true
    }
  }

  Process {
    id: fetchProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fetchOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fetchStderr = text
    }
    onExited: function(exitCode) {
      var completedOutput = root.fetchOutput
      root.fetchOutput = ""
      var stations = null
      if (exitCode === 0) {
        try {
          var parsed = JSON.parse(completedOutput || "[]")
          if (Array.isArray(parsed)) stations = parsed
        } catch (error) {
          stations = null
        }
      }
      var sameCatalog = root.fetchCatalog === root.catalog
      // TV's world is a complete snapshot; replacing it drops ended YouTube lives.
      var nextWorld = null
      if (root.fetchAction === "world" && stations !== null)
        nextWorld = root.fetchCatalog === "tv" ? stations.slice(0, root.worldStationLimit)
          : RadioModel.mergeStations(sameCatalog ? root.worldStations
            : root.catalogWorlds[root.fetchCatalog], stations, root.worldStationLimit)
      if (nextWorld !== null && !sameCatalog) {
        var worlds = Object.assign({}, root.catalogWorlds)
        worlds[root.fetchCatalog] = nextWorld
        root.catalogWorlds = worlds
      } else if (nextWorld !== null) {
        root.worldStations = nextWorld
        root.scheduleWorldExpansion(1200)
      }

      if (root.pendingFetchAction) {
        var nextAction = root.pendingFetchAction
        var nextValue = root.pendingFetchValue
        root.pendingFetchAction = ""
        root.pendingFetchValue = ""
        root.fetching = false
        Qt.callLater(function() {
          if (root.mode === nextAction)
            root.startFetch(nextAction,
              nextAction === "random" ? root.randomExclusions() : nextValue)
        })
        return
      }

      root.fetching = false
      if (!sameCatalog || root.mode !== root.fetchAction) return
      if (root.fetchAction === "search"
          && String(searchField.text || "").trim() !== root.fetchValue) return
      if (exitCode !== 0) {
        var service = root.tvCatalog ? "The TV channel list" : "Radio Browser"
        root.fetchError = root.displayStations.length > 0
          ? "Showing cached " + root.stationNoun + " · " + service + " is unavailable"
          : service + " is unavailable. Try again shortly."
        return
      }
      if (stations === null) {
        root.fetchError = "Station data was not valid"
        return
      }
      root.fetchError = ""

      if (root.fetchAction === "world") {
        root.setStationList("world", root.worldStations)
      } else if (root.fetchAction === "country") {
        var countryStations = RadioModel.mergeStations(root.results, stations, 500)
        root.worldStations = RadioModel.prioritizeStations(
          countryStations, root.worldStations, root.worldStationLimit)
        root.setStationList("country", countryStations)
      } else if (root.fetchAction === "search") {
        root.setStationList("search", stations)
      } else if (root.fetchAction === "random") {
        root.setStationList("random", stations)
        if (stations.length > 0) {
          root.lastRandomUuid = String(stations[0].uuid || "")
          root.playSelected()
        }
      }

    }
  }

  Process {
    id: worldExpandProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.worldExpandOutput = text
    }
    onExited: function(exitCode) {
      var output = root.worldExpandOutput
      root.worldExpandOutput = ""
      if (!root.opened || root.catalog !== "radio") return
      root.worldExpansionMisses += 1
      if (exitCode !== 0) {
        root.scheduleWorldExpansion(30000)
        return
      }

      var stations = null
      try {
        var parsed = JSON.parse(output || "[]")
        if (Array.isArray(parsed)) stations = parsed
      } catch (error) {
        stations = null
      }
      if (stations === null || stations.length === 0) {
        root.scheduleWorldExpansion(30000)
        return
      }

      var merged = RadioModel.mergeStations(
        root.worldStations, stations, root.worldStationLimit)
      var added = merged.length - root.worldStations.length
      if (added === 0) {
        root.scheduleWorldExpansion(10000)
        return
      }
      root.worldExpansionMisses = 0
      root.worldStations = merged
      if (root.mode === "world") root.results = merged
      root.scheduleWorldExpansion(1600)
    }
  }

  Process {
    id: albumProcess
    property string source: "library"
    property string output: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: albumProcess.output = text
    }
    onExited: function(exitCode) {
      if (root.mode !== "albums" || source !== root.albumSource) return
      var stations = null
      try { stations = JSON.parse(output || "null") } catch (e) {}
      if (exitCode !== 0 || !Array.isArray(stations)) {
        root.albumError = source === "library"
          ? "Your connected music folders could not be indexed."
          : "tocador.cc is unavailable. Try again shortly."
        return
      }
      root.setStationList("albums", stations)
    }
  }

  Process {
    id: universalSearchProcess
    property string query: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.universalSearchOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: universalSearchProcess.errorOutput = text
    }
    onExited: function(exitCode) {
      if (root.mode !== "search"
          || String(searchField.text || "").trim() !== query) return
      var rows = null
      try { rows = JSON.parse(root.universalSearchOutput || "null") } catch (error) {}
      root.universalSearchOutput = ""
      if (exitCode !== 0 || !Array.isArray(rows)) {
        root.fetchError = "Universal search could not reach the connectors."
        return
      }
      root.fetchError = ""
      root.setStationList("search", rows)
    }
  }

  Process {
    id: volumeProcess
    property int submittedVolume: -1
    property string output: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: volumeProcess.output = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: volumeProcess.errorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (root.pendingVolume === submittedVolume) {
          root.pendingVolume = -1
          root.playerVolume = root.reportedVolume
        } else {
          Qt.callLater(root.flushPlayerVolume)
        }
        root.playerError = "Could not change volume"
        return
      }

      root.statusReady = true
      root.playerError = ""
      root.reportedVolume = submittedVolume
      if (root.pendingVolume === submittedVolume) {
        root.pendingVolume = -1
        root.playerVolume = submittedVolume
        return
      }
      Qt.callLater(root.flushPlayerVolume)
    }
  }

  Process {
    id: outputsProcess
    property string output: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: outputsProcess.output = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: outputsProcess.errorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.outputsError = "Audio outputs are unavailable"
        root.audioOutputs = []
        return
      }
      var parsed = null
      try {
        var document = JSON.parse(outputsProcess.output || "{}")
        if (document && Array.isArray(document.outputs)) parsed = document.outputs
      } catch (error) {
        parsed = null
      }
      if (parsed === null) {
        root.outputsError = "Audio outputs are unavailable"
        root.audioOutputs = []
        return
      }
      root.audioOutputs = parsed.filter(function(row) {
        return row && typeof row === "object"
          && /^[A-Za-z0-9._:+-]{1,160}$/.test(String(row.id || ""))
      }).map(function(row) {
        return {
          id: String(row.id),
          label: String(row.label || row.id).replace(/[\r\n\t]+/g, " ").slice(0, 160)
        }
      })
      root.outputsError = ""
    }
  }

  Process {
    id: outputProcess
    property string submittedOutput: ""
    property string output: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: outputProcess.output = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: outputProcess.errorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.statusReady = true
        root.playerError = ""
        root.playerOutput = outputProcess.submittedOutput
        root.outputMenuOpen = false
        return
      }
      root.playerError = "Could not change audio output"
    }
  }

  Process {
    id: playerActionProcess
    property string action: ""
    property string output: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: playerActionProcess.output = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: playerActionProcess.errorOutput = text
    }
    onExited: function(exitCode) {
      var canceled = playerActionProcess.action === "play"
        && root.playCancellationRequested
      root.playCancellationRequested = false
      if (exitCode !== 0 && !canceled) {
        root.playerError = playerActionProcess.action === "play"
          ? "Could not play this station" : "Player action failed"
      }
      if (exitCode === 0) root.statusReady = true
      Qt.callLater(root.playPendingStation)
    }
  }

  Process {
    id: stopProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) root.playerError = "Could not stop the player"
      else root.statusReady = true
      Qt.callLater(root.playPendingStation)
    }
  }

  Process {
    id: stateProcess
    property string action: ""
    property string output: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: stateProcess.output = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: stateProcess.errorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        if (stateProcess.action === "get") {
          root.applyLocalState(output)
          root.refreshLocalSelection()
        } else {
          root.localError = ""
          root.localReloadPending = true
        }
      } else {
        root.localError = stateProcess.action === "favorite"
          ? "Favorite could not be updated" : "Saved stations could not be loaded"
      }

      if (root.pendingFavoriteRequests.length > 0) {
        var nextRequest = root.pendingFavoriteRequests[0]
        root.pendingFavoriteRequests = root.pendingFavoriteRequests.slice(1)
        Qt.callLater(function() { root.startFavorite(nextRequest) })
        return
      }
      if (root.localReloadPending) root.requestLocalStateReload()
    }
  }

  Process {
    id: historyProcess
    property string output: ""
    property string errorOutput: ""
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: historyProcess.output = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: historyProcess.errorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.localError = ""
        root.localReloadPending = true
      } else {
        root.localError = "Listening history could not be updated"
      }

      if (root.pendingRecentUuid) {
        var nextUuid = root.pendingRecentUuid
        root.pendingRecentUuid = ""
        Qt.callLater(function() { root.startRecordPlayed(nextUuid) })
        return
      }
      if (root.localReloadPending) root.requestLocalStateReload()
    }
  }

  Timer {
    id: searchDebounce
    interval: 300
    repeat: false
    onTriggered: root.search(searchField.text)
  }

  Timer {
    id: worldExpandTimer
    interval: 1600
    repeat: false
    onTriggered: {
      if (!root.opened || worldExpandProcess.running
          || root.worldStations.length >= root.worldStationLimit) return
      root.worldExpandOutput = ""
      worldExpandProcess.command = [root.fetchPath, "world-more"]
      worldExpandProcess.running = true
    }
  }

  Timer {
    id: windowSetupReloadTimer
    interval: 100
    repeat: false
    onTriggered: root.registerWindowSetup()
  }

  Timer {
    id: windowRevealTimer
    interval: 50
    repeat: false
    onTriggered: {
      if (panel.visible && panel.backingWindowVisible) root.windowFrameReady = true
    }
  }

  Timer {
    id: volumeTimer
    interval: 90
    repeat: false
    onTriggered: root.flushPlayerVolume()
  }

  Component.onCompleted: {
    registerWindowSetup()
    statusInitProcess.command = [playerPath, "status"]
    statusInitProcess.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  FloatingWindow {
    id: panel
    visible: false
    title: "Universal Player"
    color: root.background
    implicitWidth: root.preferredWidth
    implicitHeight: root.preferredHeight
    minimumSize: Qt.size(Style.space(800), Style.space(560))
    HyprlandWindow.opacity: root.windowFrameReady ? 1 : 0

    onVisibleChanged: {
      if (visible) root.scheduleWindowReveal()
      if (!visible && root.opened) root.dismiss()
    }
    onBackingWindowVisibleChanged: root.scheduleWindowReveal()
    onWidthChanged: root.scheduleWindowReveal()
    onHeightChanged: root.scheduleWindowReveal()

    BorderSurface {
      id: card
      anchors.fill: parent
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (searchField.activeFocus) {
          if (event.key === Qt.Key_Escape) {
            if (searchField.text) {
              searchField.clear()
              root.showWorld()
            }
            else keyCatcher.forceActiveFocus()
            event.accepted = true
          }
          return
        }

        if (root.helpVisible) {
          if (event.key === Qt.Key_Escape || root.isHelpKey(event)) {
            root.toggleControls()
            event.accepted = true
          }
          return
        }

        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (root.isHelpKey(event)) {
          root.toggleControls()
          event.accepted = true
        } else if (event.key === Qt.Key_Slash) {
          searchField.forceActiveFocus()
          searchField.selectAll()
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.moveSelection(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.moveSelection(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.playSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Space) {
          if (root.playerRunning) root.playerAction("toggle")
          else root.playSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_R) {
          root.playRandom()
          event.accepted = true
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
          root.changePlayerVolume(5)
          event.accepted = true
        } else if (event.key === Qt.Key_Minus) {
          root.changePlayerVolume(-5)
          event.accepted = true
        } else if (event.key === Qt.Key_M) {
          root.playerAction("mute")
          event.accepted = true
        } else if (event.key === Qt.Key_T) {
          root.showCatalog(root.tvCatalog ? "radio" : "tv")
          event.accepted = true
        } else if (event.key === Qt.Key_I) {
          root.identifySong()
          event.accepted = true
        } else if (event.key === Qt.Key_F && root.selectedStation) {
          root.toggleFavorite(root.selectedStation.uuid)
          event.accepted = true
        }
      }

      MouseArea {
        id: cardMouse
        anchors.fill: parent
        onClicked: keyCatcher.forceActiveFocus()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        z: 1
      }

      Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.headerHeight
        z: 2

        Text {
          id: title
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          text: "UNIVERSAL PLAYER"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        TextField {
          id: searchField
          anchors.right: randomButton.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(Style.space(330), card.width * 0.32)
          visible: true
          placeholderText: "Search"
          maximumLength: 128
          foreground: root.foreground
          accent: root.accent
          onTextEdited: {
            if (!root.previewSearch(text)) return
            searchDebounce.restart()
          }
          onAccepted: {
            searchDebounce.stop()
            root.search(text)
          }
        }

        Button {
          id: randomButton
          anchors.right: favoritesNavButton.left
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf074"
          text: "Random"
          tooltipText: root.albumMode ? "Play a random album (R)"
            : (root.tvCatalog ? "Play a random channel (R)" : "Play a random station (R)")
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.playRandom()
        }

        Button {
          id: favoritesNavButton
          anchors.right: historyNavButton.left
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf005"
          tooltipText: "Radio favorites"
          selected: root.mode === "favorites"
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.showFavorites()
        }

        Button {
          id: historyNavButton
          anchors.right: helpButton.left
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf1da"
          tooltipText: "Listening history"
          selected: root.mode === "recent"
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.showRecent()
        }

        Button {
          id: helpButton
          anchors.right: closeButton.left
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          text: "?"
          tooltipText: root.helpVisible ? "Hide controls (?)" : "Show controls (?)"
          selected: root.helpVisible
          focusable: true
          foreground: root.foreground
          accent: root.accent
          Accessible.role: Accessible.Button
          Accessible.name: tooltipText
          onClicked: root.toggleControls()
        }

        Button {
          id: closeButton
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf00d"
          tooltipText: "Close"
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.dismiss()
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: root.faint
        }
      }

      Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        visible: !root.helpVisible
        z: 2

        Item {
          id: mapPane
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: sidebar.left
          visible: !root.albumMode

          Globe {
            id: globe
            anchors.fill: parent
            anchors.margins: Style.spacing.lg
            countries: root.countries
            stations: root.currentGeoStations
            selectedStation: root.playingStation || root.selectedStation
            activeCountryCode: root.activeCountryCode
            backgroundColor: root.mapBackground
            sphereColor: root.mapSphere
            landColor: root.mapLand
            gridColor: root.mapGrid
            outlineColor: root.lightTheme ? "#3c4247" : "#9099a3"
            signalColor: root.lightTheme ? "#202428" : "#d9dee3"
            accentColor: root.accent
            textColor: root.foreground
            fontFamily: Style.font.menuFamily
            onInteractionStarted: {
              root.keyboardSelectionVisible = false
              keyCatcher.forceActiveFocus()
            }
            onPointerMoved: root.keyboardSelectionVisible = false
            onStationActivated: function(station) { root.activateMapStation(station) }
            onCountryActivated: function(code, name) { root.browseCountry(code, name) }
          }

          Text {
            id: mapHint
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.panelPadding
            anchors.right: signalCount.left
            anchors.rightMargin: Style.spacing.md
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.md
            text: root.fetchError || root.localError
              ? root.fetchError || root.localError
              : (root.activeCountryName
                ? root.activeCountryName + "  ·  click another country to browse"
                : "Drag or flick to spin  ·  wheel to zoom  ·  click a signal or country")
            textFormat: Text.PlainText
            color: root.fetchError || root.localError ? root.urgent : root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            id: signalCount
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.panelPadding
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.md
            text: root.currentGeoStations.length + " signals"
            textFormat: Text.PlainText
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        AlbumWorld {
          id: albumWorld
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: sidebar.left
          anchors.margins: Style.spacing.lg
          visible: root.albumMode
          model: root.albumCards
          selectedUuid: root.selectedStation ? String(root.selectedStation.uuid || "") : ""
          selectedAlbumKey: root.selectedStation ? String(root.selectedStation.albumKey || "") : ""
          playingUuid: root.playingStationUuid
          playingAlbumKey: root.playingStation ? String(root.playingStation.albumKey || "") : ""
          foreground: root.foreground
          accent: root.accent
          background: root.mapBackground
          dim: root.dim
          faint: root.faint
          fontFamily: Style.font.menuFamily
          sourceTitle: root.albumSourceTitle
          sourceSubtitle: root.albumSourceSubtitle
          loading: albumProcess.running
          onAlbumActivated: function(row) { root.playAlbum(row) }
          onReshuffleRequested: root.showAlbums(root.albumSource, true)
        }

        Rectangle {
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: sidebar.left
          width: 1
          color: root.faint
        }

        Item {
          id: sidebar
          width: root.sidebarWidth
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom

          Item {
            id: tabs
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.space(48)

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Button {
                text: "Radio"
                selected: !root.albumMode && root.mode !== "favorites" && root.mode !== "recent"
                  && !root.tvCatalog
                foreground: root.foreground
                accent: root.accent
                fontSize: Style.font.caption
                onClicked: root.showCatalog("radio")
              }
              Button {
                text: "TV"
                tooltipText: "Free live TV channels from iptv-org (T)"
                selected: !root.albumMode && root.mode !== "favorites" && root.mode !== "recent"
                  && root.tvCatalog
                foreground: root.foreground
                accent: root.accent
                fontSize: Style.font.caption
                onClicked: root.showCatalog("tv")
              }
              Button {
                text: "Tocador"
                tooltipText: "UQT + Hominis Canidae curated archives"
                selected: root.albumMode && root.albumSource === "tocador"
                foreground: root.foreground
                accent: root.accent
                fontSize: Style.font.caption
                onClicked: root.showAlbums("tocador")
              }
              Button {
                text: "My Music"
                tooltipText: "Configured local and synced folders"
                selected: root.albumMode && root.albumSource === "library"
                foreground: root.foreground
                accent: root.accent
                fontSize: Style.font.caption
                onClicked: root.showAlbums("library")
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.faint
            }
          }

          ListView {
            id: stationList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tabs.bottom
            anchors.bottom: playerPanel.top
            clip: true
            model: root.displayStations
            currentIndex: root.selectedIndex
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 500
            interactive: !root.outputMenuOpen

            QQC.ScrollBar.vertical: QQC.ScrollBar {}

            delegate: Rectangle {
              id: stationRow
              required property var modelData
              required property int index
              readonly property bool isTrack: String(modelData.kind || "") === "track"

              width: stationList.width
              height: isTrack ? Style.space(72) : Style.space(64)
              color: root.playingStationUuid === stationRow.modelData.uuid
                ? Style.selectedFillFor(root.foreground, root.accent)
                : (rowMouse.containsMouse
                  ? Style.hoverFillFor(root.foreground, root.accent)
                  : "transparent")

              Accessible.name: modelData.name + ", " + RadioModel.stationMeta(modelData)
              Accessible.role: Accessible.ListItem
              Accessible.selected: root.selectedIndex === index
              Accessible.onPressAction: {
                root.setSelection(stationRow.index)
                root.playSelected()
              }

              Rectangle {
                visible: root.playingStationUuid === stationRow.modelData.uuid
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 2
                color: root.accent
              }

              Rectangle {
                anchors.fill: parent
                visible: root.keyboardSelectionVisible
                  && root.selectedIndex === stationRow.index
                  && root.playingStationUuid !== stationRow.modelData.uuid
                  && !rowMouse.containsMouse
                color: "transparent"
                border.color: root.accent
                border.width: 1
              }

              Rectangle {
                id: trackCover
                visible: stationRow.isTrack
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(48)
                height: width
                radius: Style.cornerRadius
                color: Style.hoverFillFor(root.foreground, root.accent)
                clip: true

                Image {
                  id: trackCoverImage
                  anchors.fill: parent
                  source: String(stationRow.modelData.cover || stationRow.modelData.favicon || "")
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  visible: status === Image.Ready
                }

                Text {
                  anchors.centerIn: parent
                  visible: !trackCoverImage.visible
                  text: "♪"
                  textFormat: Text.PlainText
                  color: root.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.heading
                }
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: stationRow.isTrack ? Style.space(72) : Style.spacing.md
                anchors.right: favoriteButton.left
                anchors.rightMargin: Style.spacing.sm
                anchors.top: parent.top
                anchors.topMargin: Style.space(10)
                text: stationRow.modelData.name
                textFormat: Text.PlainText
                color: root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: root.playingStationUuid === stationRow.modelData.uuid
                elide: Text.ElideRight
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: stationRow.isTrack ? Style.space(72) : Style.spacing.md
                anchors.right: favoriteButton.left
                anchors.rightMargin: Style.spacing.sm
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(9)
                text: stationRow.isTrack
                  ? [stationRow.modelData.connectorLabel, stationRow.modelData.artist, stationRow.modelData.album,
                      stationRow.modelData.year].filter(function(value) { return value }).join("  ·  ")
                  : RadioModel.stationMeta(stationRow.modelData)
                    + (RadioModel.compactTags(stationRow.modelData.tags, 2)
                      ? "  ·  " + RadioModel.compactTags(stationRow.modelData.tags, 2) : "")
                textFormat: Text.PlainText
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Button {
                id: favoriteButton
                visible: !stationRow.isTrack
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.isFavorite(stationRow.modelData.uuid) ? "\uf005" : "\uf006"
                tooltipText: root.isFavorite(stationRow.modelData.uuid) ? "Remove favorite" : "Add favorite"
                foreground: root.isFavorite(stationRow.modelData.uuid)
                  ? root.favoriteColor : root.foreground
                accent: root.accent
                onClicked: root.toggleFavorite(stationRow.modelData.uuid)
              }

              MouseArea {
                id: rowMouse
                anchors.left: parent.left
                anchors.right: stationRow.isTrack ? parent.right : favoriteButton.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.setSelection(stationRow.index)
                onClicked: {
                  root.setSelection(stationRow.index)
                  root.playSelected()
                  keyCatcher.forceActiveFocus()
                }
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.faint
              }
            }

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.spacing.panelPadding * 2
              visible: (!root.fetching || !root.remoteMode) && root.displayStations.length === 0
              text: root.emptyStateText()
              textFormat: Text.PlainText
              color: root.fetchError || root.localError ? root.urgent : root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
            }

            Text {
              anchors.centerIn: parent
              visible: root.fetching && root.remoteMode && root.displayStations.length === 0
              text: "LOADING " + root.stationNoun.toUpperCase()
              textFormat: Text.PlainText
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            id: playerPanel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.space(126)
            color: "transparent"

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: 1
              color: root.faint
            }

            Text {
              id: nowPlaying
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.right: identifyButton.left
              anchors.rightMargin: Style.spacing.xs
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.md
              text: root.playerRunning
                ? (root.playingStationName || root.playerTitle || "Unknown station")
                : "Nothing playing"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              font.bold: root.playerRunning
              elide: Text.ElideRight
            }

            Text {
              anchors.left: nowPlaying.left
              anchors.right: nowPlaying.right
              anchors.top: nowPlaying.bottom
              anchors.topMargin: Style.spacing.xs
              text: root.playerError
                ? root.playerError
                : root.streamError ? root.streamError + ". Play to retry, or Next."
                : (!root.playerRunning ? (root.albumMode ? "Choose an album to begin" : "Choose a signal to begin")
                : (root.trackLine ? root.trackLine + "  ·  " : "")
                  + (root.playerPaused ? "Paused" : (root.playingTrack ? "Playing" : "Live"))
                  + (root.playlistCount > 1 ? "  ·  " + root.playlistCount
                    + (root.playingTrack ? " tracks queued"
                      : root.playingTv ? " channels queued" : " stations queued") : ""))
              textFormat: Text.PlainText
              color: root.playerError || root.streamError ? root.urgent : root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Button {
              id: identifyButton
              anchors.right: playingFavoriteButton.left
              anchors.top: playingFavoriteButton.top
              visible: root.playerRunning && root.playingStationUuid !== "" && !root.playingTrack
                && !root.playingTv
              iconText: root.identifying ? "\uf130" : "\uf001"
              tooltipText: root.identifying ? "Listening…" : "Identify the playing song"
              enabled: !root.identifying && !root.playerPaused
              focusable: true
              foreground: root.identifying ? root.accent : root.foreground
              accent: root.accent
              Accessible.role: Accessible.Button
              Accessible.name: tooltipText
              onClicked: root.identifySong()
            }

            Button {
              id: playingFavoriteButton
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.sm
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.sm
              visible: root.playerRunning && root.playingStationUuid !== "" && !root.playingTrack
              iconText: root.isFavorite(root.playingStationUuid) ? "\uf005" : "\uf006"
              tooltipText: root.isFavorite(root.playingStationUuid)
                ? "Remove playing station from favorites"
                : "Add playing station to favorites"
              focusable: true
              foreground: root.isFavorite(root.playingStationUuid)
                ? root.favoriteColor : root.foreground
              accent: root.accent
              Accessible.role: Accessible.Button
              Accessible.name: tooltipText
              onClicked: root.toggleFavorite(root.playingStationUuid)
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.sm
              spacing: Style.spacing.xs

              Button {
                iconText: "\uf048"
                tooltipText: root.playingTrack ? "Previous track" : "Previous station"
                enabled: root.playerRunning && !root.playerActionBusy
                focusable: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.playerAction("previous")
              }
              Button {
                iconText: root.playerRunning && !root.playerPaused ? "\uf04c" : "\uf04b"
                tooltipText: root.streamError ? (root.playingTrack ? "Retry track" : "Retry station")
                  : root.playerRunning && !root.playerPaused ? "Pause" : "Play"
                enabled: !root.playerActionBusy
                focusable: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.playerRunning ? root.playerAction("toggle") : root.playSelected()
              }
              Button {
                iconText: "\uf051"
                tooltipText: root.playingTrack ? "Next track" : "Next station"
                enabled: root.playerRunning && !root.playerActionBusy
                focusable: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.playerAction("next")
              }
              Button {
                iconText: "\uf04d"
                tooltipText: "Stop"
                enabled: (root.playerRunning || root.playPreparing)
                  && !stopProcess.running
                  && !root.playCancellationRequested
                  && (!playerActionProcess.running || root.playPreparing)
                focusable: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.stopPlayer()
              }
            }

            Row {
              id: outputControls
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.leftMargin: Style.spacing.sm
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.sm
              spacing: Style.spacing.xs

              Button {
                id: outputButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf0a1"
                tooltipText: root.playerOutput
                  ? "Audio output: " + root.outputLabel(root.playerOutput)
                  : "Choose audio output"
                active: root.playerOutput !== ""
                enabled: !stopProcess.running && !outputProcess.running
                focusable: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.toggleOutputMenu()
              }

              Button {
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.playerMuted || root.playerVolume === 0 ? "\uf026" : "\uf028"
                tooltipText: root.playerMuted ? "Unmute" : "Mute (M)"
                active: root.playerMuted
                enabled: root.playerRunning && !root.playerActionBusy
                focusable: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.playerAction("mute")
              }

              PanelSlider {
                id: volumeSlider
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(116)
                height: implicitHeight
                minimum: 0
                maximum: 100
                step: 1
                integer: true
                value: root.playerVolume
                trackColor: root.faint
                fillColor: root.accent
                knobColor: root.foreground
                tickColor: root.background
                enabled: !stopProcess.running
                Accessible.name: "Radio volume"
                onMoved: function(nextVolume) { root.setPlayerVolume(nextVolume) }
                onRightClicked: root.playerAction("mute")
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                text: root.playerVolume + "%"
                textFormat: Text.PlainText
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          MouseArea {
            visible: root.outputMenuOpen
            anchors.fill: parent
            z: 2
            onClicked: root.outputMenuOpen = false
          }

          Rectangle {
            id: outputMenu
            visible: root.outputMenuOpen
            readonly property point buttonPosition: {
              sidebar.width
              sidebar.height
              outputControls.x
              outputControls.y
              return outputButton.mapToItem(
                sidebar, outputButton.width / 2, 0)
            }
            x: Math.max(Style.spacing.sm, Math.min(
              parent.width - width - Style.spacing.sm,
              buttonPosition.x - width / 2))
            y: buttonPosition.y - height - Style.spacing.xs
            z: 3
            width: Math.min(Style.space(300), parent.width - Style.spacing.md * 2)
            height: outputMenuColumn.implicitHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: root.background
            border.color: root.faint
            border.width: 1

            Accessible.role: Accessible.Pane
            Accessible.name: "Audio output"

            Column {
              id: outputMenuColumn
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.md
              anchors.left: parent.left
              anchors.right: parent.right
              spacing: Style.spacing.xs

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xs
                text: "AUDIO OUTPUT"
                textFormat: Text.PlainText
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              ListView {
                id: outputList
                width: parent.width
                height: Math.min(contentHeight, Style.space(320))
                model: root.outputChoices
                spacing: Style.spacing.xs
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                QQC.ScrollBar.vertical: QQC.ScrollBar {
                  policy: QQC.ScrollBar.AsNeeded
                }

                delegate: Button {
                  id: outputOption
                  required property var modelData
                  width: ListView.view.width
                  leftAlign: true
                  text: outputOption.modelData.label
                  selected: outputOption.modelData.id === root.playerOutput
                  focusable: true
                  foreground: root.foreground
                  accent: root.accent
                  Accessible.role: Accessible.Button
                  Accessible.name: outputOption.modelData.label
                  onClicked: root.selectOutput(outputOption.modelData.id)
                }
              }

              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.spacing.xs
                visible: root.audioOutputs.length === 0 && !outputsProcess.running
                text: root.outputsError || "No other audio outputs found"
                textFormat: Text.PlainText
                color: root.outputsError ? root.urgent : root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }
          }
        }
      }

      Item {
        id: controlsPane
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.borderLeft
        anchors.rightMargin: card.borderRight
        anchors.bottomMargin: card.borderBottom
        visible: root.helpVisible
        z: 2
        Accessible.role: Accessible.Pane
        Accessible.name: "Universal Player controls"

        Rectangle {
          anchors.fill: parent
          color: root.background
        }

        Column {
          id: controlsContent
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.spacing.panelPadding * 2, Style.space(920))
          height: implicitHeight
          spacing: Style.space(24)

          Text {
            text: "CONTROLS"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Row {
            id: controlsColumns
            width: parent.width
            height: implicitHeight
            spacing: Style.space(72)

            Repeater {
              model: root.controlSections

              delegate: Column {
                id: controlSection
                required property var modelData
                width: (controlsColumns.width - controlsColumns.spacing) / 2
                height: implicitHeight

                Text {
                  width: parent.width
                  height: Style.space(36)
                  text: controlSection.modelData.title
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                  model: controlSection.modelData.controls

                  delegate: Item {
                    required property var modelData
                    width: controlSection.width
                    height: Style.space(38)

                    Text {
                      id: controlInput
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(controlSection.modelData.inputWidth)
                      text: modelData.input
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      anchors.left: controlInput.right
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.action
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Rectangle {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      height: 1
                      color: root.faint
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
