// Development probe: loads PlayerService and LyricsView outside the bar,
// prints the state and exits. Handy for checking a change without restarting
// the shell.
//
//   ln -sfn /usr/share/omarchy/shell/Commons Commons   # dev only, git-ignored
//   ln -sfn /usr/share/omarchy/shell/Ui Ui
//   qs -p probe.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "."

Scope {
  id: root

  property int ticks: 0

  PlayerService {
    id: media
    source: Quickshell.env("PROBE_SOURCE") || "Auto"
    romanize: Quickshell.env("PROBE_ROMANIZE") || "Off"
    translate: Quickshell.env("PROBE_TRANSLATE") || "Off"
  }

  PanelWindow {
    anchors.top: true
    anchors.right: true
    margins.top: 40
    margins.right: 20
    implicitWidth: 420
    implicitHeight: 400
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    // Overlay so the probe is visible even over a fullscreen window.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "super-player-probe"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Same surface the popup uses, so the probe looks like the real thing.
    BorderSurface {
      id: card
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      LyricsView {
        id: cardView
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        service: media
        volumeHover: Quickshell.env("PROBE_VOLUME") === "1"
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      const player = media.player
      console.log("PROBE #" + root.ticks
        + " player=" + (player ? (player.identity || player.dbusName) : "-")
        + " track=\"" + media.trackTitle + "\""
        + " playing=" + media.playing
        + " lyrics=" + media.status
        + " lines=" + media.lines.length
        + " index=" + media.currentIndex
        + " volume=" + Math.round(media.volume * 100)
        + " revealed=" + cardView.volumeRevealed
        + " prev=" + media.canGoPrevious
        + " next=" + media.canGoNext)
      if (root.ticks >= (Number(Quickshell.env("PROBE_TICKS")) || 5)) {
        console.log("PROBE done")
        Qt.exit(0)
      }
    }
  }
}
