import QtQuick 6.5
import QtTest
import "../.." as Atlas

TestCase {
  id: testCase
  name: "AlbumWorld"
  when: windowShown
  width: 760
  height: 680
  visible: true

  Atlas.AlbumWorld {
    id: albums
    width: 760
    height: 680
    model: [
      { uuid: "one", title: "First", artist: "Artist", album: "Album One", albumKey: "a" },
      { uuid: "two", title: "Second", artist: "Other", album: "Album Two", albumKey: "b" }
    ]
  }

  SignalSpy {
    id: activations
    target: albums
    signalName: "albumActivated"
  }

  function init() {
    albums.selectedUuid = ""
    albums.playingUuid = ""
    activations.clear()
  }

  function test_selectedAndPlayingRowsFollowIds() {
    albums.selectedUuid = "one"
    albums.playingUuid = "two"
    compare(albums.selectedRow.album, "Album One")
    compare(albums.playingRow.album, "Album Two")
  }

  function test_clickActivatesAlbum() {
    waitForRendering(albums)
    mouseClick(albums, 65, 295)
    compare(activations.count, 1)
    compare(activations.signalArguments[0][0].uuid, "one")
  }
}
