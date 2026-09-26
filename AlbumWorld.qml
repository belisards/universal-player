pragma ComponentBehavior: Bound
import QtQuick

// A self-contained album wall for connector-backed music collections.
// Rows may contain: uuid, title, artist, album, year, favicon/cover, albumKey.
Item {
  id: root

  property var model: []
  property string selectedUuid: ""
  property string selectedAlbumKey: ""
  property string playingUuid: ""
  property string playingAlbumKey: ""
  property color foreground: "#f3f4f5"
  property color accent: "#ff8a3d"
  property color background: "#11151a"
  property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.64)
  property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  property string fontFamily: "monospace"
  property string sourceTitle: "YOUR COLLECTION"
  property string sourceSubtitle: "A small world of albums"
  property bool loading: false

  signal albumActivated(var row)
  signal reshuffleRequested()

  readonly property var selectedRow: rowForIdentity(selectedUuid, selectedAlbumKey)
  readonly property var playingRow: rowForIdentity(playingUuid, playingAlbumKey)

  function rowForUuid(uuid) {
    var wanted = String(uuid || "")
    var rows = Array.isArray(model) ? model : []
    for (var i = 0; i < rows.length; i++) {
      if (String(rows[i] && rows[i].uuid || "") === wanted) return rows[i]
    }
    return null
  }

  function rowForIdentity(uuid, albumKey) {
    var rows = Array.isArray(model) ? model : []
    var wantedAlbum = String(albumKey || "")
    if (wantedAlbum) {
      for (var i = 0; i < rows.length; i++) {
        if (String(rows[i] && rows[i].albumKey || "") === wantedAlbum) return rows[i]
      }
    }
    return rowForUuid(uuid)
  }

  function coverFor(row) {
    if (!row) return ""
    return String(row.cover || row.favicon || "")
  }

  function labelFor(row) {
    if (!row) return ""
    return String(row.album || row.title || "Untitled album")
  }

  function artistFor(row) {
    return row ? String(row.artist || "Unknown artist") : ""
  }

  function detailsFor(row) {
    if (!row) return ""
    return [artistFor(row), String(row.year || "")]
      .filter(function(value) { return value }).join("  ·  ")
  }

  function initialsFor(row) {
    var value = labelFor(row).replace(/[^A-Za-z0-9À-ÿ ]/g, " ").trim()
    if (!value) return "♪"
    var bits = value.split(/\s+/)
    return String(bits[0].charAt(0)
      + (bits.length > 1 ? bits[bits.length - 1].charAt(0) : "")).toUpperCase()
  }

  function activate(row) {
    if (!row) return
    albumActivated(row)
  }

  Accessible.name: sourceTitle
  Accessible.description: sourceSubtitle
  Accessible.role: Accessible.Pane

  Rectangle {
    anchors.fill: parent
    radius: 18
    color: root.background
    border.color: root.faint
    border.width: 1
  }

  // Quiet orbital glow gives the hero some depth without requiring a shader.
  Rectangle {
    id: glow
    width: Math.min(root.width, root.height) * 0.82
    height: width
    x: root.width * 0.58 - width / 2
    y: -height * 0.58
    radius: width / 2
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.07)
    opacity: root.loading ? 0.45 : 0.8
    Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutSine } }
    SequentialAnimation on rotation {
      loops: Animation.Infinite
      NumberAnimation { from: -3; to: 3; duration: 4200; easing.type: Easing.InOutSine }
      NumberAnimation { from: 3; to: -3; duration: 4200; easing.type: Easing.InOutSine }
    }
  }

  Item {
    id: hero
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(174, Math.min(220, root.height * 0.32))
    anchors.margins: 22

    Column {
      anchors.left: parent.left
      anchors.leftMargin: 2
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(150, parent.width - heroCover.width - 38)
      spacing: 7

      Text {
        text: root.sourceTitle
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 21
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        text: root.sourceSubtitle
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        text: root.loading ? "SYNCING YOUR LIBRARY…" : (root.playingRow ? "NOW PLAYING" : "SELECT AN ALBUM")
        textFormat: Text.PlainText
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: 10
        font.bold: true
        topPadding: 10
      }
      Text {
        text: root.playingRow ? root.labelFor(root.playingRow) : (root.selectedRow ? root.labelFor(root.selectedRow) : "")
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 16
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        text: root.playingRow ? root.detailsFor(root.playingRow) : (root.selectedRow ? root.detailsFor(root.selectedRow) : "")
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
        width: parent.width
      }
    }

    Rectangle {
      id: heroCover
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(142, parent.height - 4)
      height: width
      radius: 12
      clip: true
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
      border.color: root.playingRow ? root.accent : root.faint
      border.width: root.playingRow ? 2 : 1
      scale: root.playingRow ? 1.02 : 1
      Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

      Image {
        id: heroImage
        anchors.fill: parent
        anchors.margins: 1
        source: root.coverFor(root.playingRow || root.selectedRow)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: status === Image.Ready
        layer.enabled: true
        layer.smooth: true
      }
      Text {
        anchors.centerIn: parent
        text: root.initialsFor(root.playingRow || root.selectedRow)
        textFormat: Text.PlainText
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: 30
        font.bold: true
        visible: !heroImage.visible
      }
    }
  }

  Rectangle {
    id: divider
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: hero.bottom
    anchors.leftMargin: 22
    anchors.rightMargin: 22
    height: 1
    color: root.faint
  }

  GridView {
    id: albumGrid
    anchors.top: divider.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 22
    anchors.topMargin: 16
    clip: true
    // Keep cards comfortably sized while allowing one to many columns.
    cellWidth: width / Math.max(1, Math.floor(width / 142))
    cellHeight: cellWidth + 46
    model: Array.isArray(root.model) ? root.model : []
    boundsBehavior: Flickable.StopAtBounds
    delegate: Item {
      id: card
      required property var modelData
      width: albumGrid.cellWidth - 10
      height: albumGrid.cellHeight - 6
      property var row: modelData
      property bool isSelected: (root.selectedAlbumKey
          && String(row && row.albumKey || "") === root.selectedAlbumKey)
        || String(row && row.uuid || "") === root.selectedUuid
      property bool isPlaying: (root.playingAlbumKey
          && String(row && row.albumKey || "") === root.playingAlbumKey)
        || String(row && row.uuid || "") === root.playingUuid
      activeFocusOnTab: true
      Accessible.name: root.labelFor(row) + " by " + root.artistFor(row)
      Accessible.role: Accessible.Button
      Accessible.onPressAction: root.activate(row)
      Keys.onReturnPressed: root.activate(row)
      Keys.onEnterPressed: root.activate(row)
      Keys.onSpacePressed: root.activate(row)

      Rectangle {
        id: art
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: width
        radius: 10
        clip: true
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, card.isSelected ? 0.24 : 0.11)
        border.color: card.isPlaying ? root.accent : (card.isSelected || card.activeFocus ? root.foreground : root.faint)
        border.width: card.isPlaying || card.isSelected || card.activeFocus ? 2 : 1
        scale: tap.containsMouse ? 0.96 : (card.isPlaying ? 1.025 : 1)
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Image {
          id: cover
          anchors.fill: parent
          anchors.margins: 1
          source: root.coverFor(card.row)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          smooth: true
          visible: status === Image.Ready
        }
        Text {
          anchors.centerIn: parent
          text: root.initialsFor(card.row)
          textFormat: Text.PlainText
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Math.max(18, parent.width * 0.24)
          font.bold: true
          visible: !cover.visible
        }
        Rectangle {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 7
          width: 20
          height: 20
          radius: 10
          color: root.accent
          visible: card.isPlaying
          Text {
            anchors.centerIn: parent
            text: "▶"
            textFormat: Text.PlainText
            color: root.background
            font.pixelSize: 10
          }
        }
        MouseArea {
          id: tap
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activate(card.row)
        }
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: art.bottom
        anchors.topMargin: 7
        spacing: 2
        Text {
          text: root.labelFor(card.row)
          textFormat: Text.PlainText
          color: card.isSelected ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: 11
          font.bold: card.isSelected
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          text: root.artistFor(card.row)
          textFormat: Text.PlainText
          color: root.faint.a > 0.01 ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: 10
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }
  }

  Column {
    anchors.centerIn: albumGrid
    spacing: 8
    visible: !root.loading && (!Array.isArray(root.model) || root.model.length === 0)
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "◎"
      textFormat: Text.PlainText
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 34
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "NO ALBUMS IN THIS SOURCE"
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: 11
      font.bold: true
    }
  }

  Rectangle {
    id: reshuffleButton
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 18
    width: 34
    height: 34
    radius: 17
    color: root.accent
    opacity: shuffleMouse.containsMouse ? 1 : 0.88
    visible: !root.loading
    activeFocusOnTab: true
    Accessible.name: "Reshuffle albums"
    Accessible.role: Accessible.Button
    Accessible.onPressAction: root.reshuffleRequested()
    Keys.onReturnPressed: root.reshuffleRequested()
    Keys.onEnterPressed: root.reshuffleRequested()
    Keys.onSpacePressed: root.reshuffleRequested()
    Text {
      anchors.centerIn: parent
      text: "↻"
      textFormat: Text.PlainText
      color: root.background
      font.family: root.fontFamily
      font.pixelSize: 19
      font.bold: true
    }
    MouseArea {
      id: shuffleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.reshuffleRequested()
    }
  }
}
