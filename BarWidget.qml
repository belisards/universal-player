import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "akshar.radio-atlas"

  property bool playerRunning: false
  property bool playerPaused: false
  property string streamError: ""
  property bool playerMuted: false
  property int playerVolume: 70
  property int reportedVolume: 70
  property int pendingVolume: -1
  property string playerTitle: ""
  property string playerStationUuid: ""
  property string playerKind: ""
  property string identifiedTrack: ""
  property string identifiedStationUuid: ""
  property bool statusReady: false
  property bool playerStateReady: false
  readonly property string playerPath: Qt.resolvedUrl("radio-player").toString().replace(/^file:\/\//, "")
  readonly property string statusPath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-radio-atlas/status.json"
  readonly property string identifyResultPath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-radio-atlas/identify.json"
  readonly property string currentIdentifiedTrack:
    identifiedStationUuid && identifiedStationUuid === playerStationUuid ? identifiedTrack : ""

  function applyIdentifyState(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var result = JSON.parse(raw || "{}")
      identifyExpiry.stop()
      root.identifiedTrack = ""
      if (result.state !== "done" || !result.title) return
      var remaining = Number(result.at || 0) * 1000 + 300000 - Date.now()
      if (remaining <= 0) return
      root.identifiedStationUuid = String(result.stationUuid || "")
      root.identifiedTrack = root.singleLineText(
        String(result.title) + (result.artist ? " — " + result.artist : ""), 160)
      identifyExpiry.interval = remaining
      identifyExpiry.start()
    } catch (error) {
      return
    }
  }

  function singleLineText(value, limit) {
    return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, limit)
  }

  function safeTooltipText(value) {
    return root.singleLineText(value, 160).replace(/</g, "‹").replace(/>/g, "›")
  }

  function applyPlayerState(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var state = JSON.parse(raw || "{}")
      root.playerRunning = state.running === true
      root.playerPaused = state.paused === true
      root.streamError = root.singleLineText(state.error || "", 200)
      root.playerMuted = state.muted === true
      var nextVolume = Math.round(Number(state.volume === undefined ? 70 : state.volume))
      root.reportedVolume = isFinite(nextVolume)
        ? Math.max(0, Math.min(100, nextVolume)) : 70
      if (root.pendingVolume < 0) root.playerVolume = root.reportedVolume
      root.playerStationUuid = String((state.station && state.station.uuid) || "")
      root.playerKind = String((state.station && state.station.kind) || "")
      root.playerTitle = root.singleLineText(
        state.title || (state.station && state.station.name) || "", 160)
      root.playerStateReady = true
    } catch (error) {
      return
    }
  }

  function runPlayerAction(action) {
    if (actionProcess.running) return
    actionProcess.command = [root.playerPath, action]
    actionProcess.running = true
  }

  function changeVolume(delta) {
    var current = pendingVolume >= 0 ? pendingVolume : playerVolume
    pendingVolume = Math.max(0, Math.min(100, current + (delta > 0 ? 5 : -5)))
    playerVolume = pendingVolume
    flushVolume()
  }

  function flushVolume() {
    if (volumeProcess.running || pendingVolume < 0) return
    volumeProcess.submittedVolume = pendingVolume
    volumeProcess.command = [playerPath, "volume", String(pendingVolume)]
    volumeProcess.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  Timer {
    id: identifyExpiry
    onTriggered: root.identifiedTrack = ""
  }

  Process {
    id: statusInitProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.statusReady = true
    }
  }

  Process {
    id: actionProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.statusReady = true
    }
  }

  Process {
    id: volumeProcess
    property int submittedVolume: -1
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (root.pendingVolume === submittedVolume) {
          root.pendingVolume = -1
          root.playerVolume = root.reportedVolume
        } else {
          Qt.callLater(root.flushVolume)
        }
        return
      }

      root.statusReady = true
      root.reportedVolume = submittedVolume
      if (root.pendingVolume === submittedVolume) {
        root.pendingVolume = -1
        root.playerVolume = submittedVolume
        return
      }
      Qt.callLater(root.flushVolume)
    }
  }

  Component.onCompleted: {
    statusInitProcess.command = [playerPath, "status"]
    statusInitProcess.running = true
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.playerKind === "track" ? "\uf001" : "\uf0ac"
    active: root.playerRunning && !root.playerPaused
    tooltipText: root.playerRunning
      ? (root.streamError ? root.streamError + ": " : root.playerPaused ? "Paused: " : "Playing: ")
        + root.safeTooltipText(root.playerTitle)
        + (root.currentIdentifiedTrack ? "  ·  ♪ " + root.safeTooltipText(root.currentIdentifiedTrack) : "")
        + "  ·  " + (root.playerMuted ? "muted" : root.playerVolume + "%")
      : "Open Tocador"

    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) {
        if (!root.playerStateReady) return
        root.runPlayerAction(root.playerRunning ? "stop" : "resume")
        return
      }
      if (mouseButton === Qt.MiddleButton) {
        root.bar.run("omarchy-shell shell summon akshar.radio-atlas '{\"action\":\"random\"}'")
        return
      }
      root.bar.run("omarchy-shell shell toggle akshar.radio-atlas")
    }

    onWheelMoved: function(delta) {
      root.changeVolume(delta)
    }
  }
}
