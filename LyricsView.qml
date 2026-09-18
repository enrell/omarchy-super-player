import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The player card: cover art with a hover play/pause, the track header with the
// transport and a hover-revealed volume bar, the synced lyrics and a draggable
// seek bar.
//
// Hosts set the height; the lyrics list fills the space in between.
Item {
  id: root

  property QtObject bar: null       // set when hosted inside the bar
  property var service: null        // PlayerService instance
  property bool interactive: true   // click a line to seek there
  property real headerSize: Style.space(64)
  property real headerRightInset: 0 // room for a control in the host header

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color faint: Qt.darker(foreground, 1.8)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool playing: service !== null && service.playing
  readonly property bool volumeRevealed: volumeHover
  property bool volumeHover: false

  // The status line only shows up when it is worth acting on; "synced lyrics"
  // is the normal case and the controls take its place.
  readonly property string statusLabel: {
    if (!service) return ""
    switch (service.status) {
    case "loading": return "fetching lyrics…"
    case "plain": return "unsynced lyrics"
    case "notfound": return "no lyrics found"
    case "error": return "network error"
    }
    return ""
  }

  readonly property string emptyMessage: {
    if (!service) return ""
    switch (service.status) {
    case "noplayer": return "No player running.\nStart something and press play."
    case "loading": return "Fetching lyrics…"
    case "notfound": return "No lyrics found on LRCLIB."
    case "error": return "Could not fetch the lyrics.\nCheck your connection."
    }
    return ""
  }

  implicitHeight: root.headerSize + Style.space(12) + Style.space(240) + Style.space(12) + seekBar.implicitHeight

  Timer {
    id: volumeHideTimer
    interval: 260
    onTriggered: root.volumeHover = false
  }

  function revealVolume() {
    volumeHideTimer.stop()
    root.volumeHover = true
  }

  function scheduleHideVolume() {
    volumeHideTimer.restart()
  }

  // ------------------------------------------------------------------ header
  Row {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.headerSize
    spacing: Style.space(10)

    // Cover art: hovering shows a play/pause glyph, clicking toggles playback.
    BorderSurface {
      id: art
      width: root.headerSize
      height: root.headerSize
      radius: Style.spacing.labelGap
      color: Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

      Image {
        id: artImage
        anchors.fill: parent
        anchors.margins: Style.space(2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: root.service ? root.service.trackArtUrl : ""
        visible: source !== "" && status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: !artImage.visible
        text: "󰝚"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.displayLarge
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(2)
        radius: art.radius - Style.space(2)
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: artArea.containsMouse ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Text {
          anchors.centerIn: parent
          text: root.playing ? "󰏤" : "󰐊"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          scale: artArea.containsMouse ? 1.0 : 0.75

          Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }
        }
      }

      MouseArea {
        id: artArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.service) root.service.togglePlaying()
      }
    }

    Column {
      width: parent.width - root.headerSize - Style.space(10) - root.headerRightInset
      spacing: Style.space(2)
      anchors.top: parent.top

      Text {
        textFormat: Text.PlainText
        text: root.service && root.service.trackTitle !== "" ? root.service.trackTitle : "Nothing playing"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: root.service ? root.service.trackArtist : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: parent.width
        visible: text !== ""
      }

      // Transport and volume, right under the artist.
      Row {
        id: headerControls
        spacing: Style.space(2)
        height: Style.spacing.controlHeight

        Button {
          width: Style.space(30)
          horizontalPadding: 0
          iconText: "󰒮"
          foreground: root.foreground
          fontFamily: root.fontFamily
          tooltipText: "Previous track"
          enabled: root.service !== null && root.service.canGoPrevious
          opacity: enabled ? 1.0 : 0.35
          onClicked: root.service.previous()
        }

        Button {
          width: Style.space(30)
          horizontalPadding: 0
          iconText: "󰒭"
          foreground: root.foreground
          fontFamily: root.fontFamily
          tooltipText: "Next track"
          enabled: root.service !== null && root.service.canGoNext
          opacity: enabled ? 1.0 : 0.35
          onClicked: root.service.next()
        }

        Button {
          id: volumeButton
          width: Style.space(30)
          horizontalPadding: 0
          iconText: root.service && root.service.volume > 0.001 ? "󰕾" : "󰖁"
          foreground: root.foreground
          fontFamily: root.fontFamily
          tooltipText: root.service && root.service.volume > 0.001 ? "Mute" : "Unmute"
          enabled: root.service !== null && root.service.volumeSupported
          opacity: enabled ? 1.0 : 0.35
          onClicked: root.service.toggleMute()
          onHovered: function (isHovered) { isHovered ? root.revealVolume() : root.scheduleHideVolume() }
        }

        // Same design and colors as the seek bar, revealed next to the icon.
        // Height matches the row so the Row's top alignment centres the track.
        SliderBar {
          id: volumeBar
          width: root.volumeRevealed ? Style.space(110) : 0
          height: headerControls.height
          opacity: root.volumeRevealed ? 1 : 0
          enabled: root.volumeRevealed && root.service !== null && root.service.volumeSupported
          value: root.service ? root.service.volume : 0
          trackColor: Util.alpha(root.foreground, 0.15)
          fillColor: Color.accent
          onMoved: function (value) { if (root.service) root.service.setVolume(value) }
          onHoveredChanged: hovered ? root.revealVolume() : root.scheduleHideVolume()

          Behavior on width {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }
          Behavior on opacity {
            NumberAnimation { duration: 160 }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.statusLabel
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: Math.max(0, headerControls.width - x)
          visible: text !== ""
        }
      }
    }
  }

  // ------------------------------------------------------------------ lyrics
  ListView {
    id: view
    anchors.top: header.bottom
    anchors.topMargin: Style.space(12)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: seekBar.top
    anchors.bottomMargin: Style.space(12)
    clip: true
    model: root.service ? root.service.lines : []
    spacing: Style.space(12)
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 2000

    // Spacers so the first and the last line can sit in the middle.
    header: Item {
      width: view.width
      height: Math.max(0, view.height / 2 - Style.space(24))
    }
    footer: Item {
      width: view.width
      height: Math.max(0, view.height / 2 - Style.space(24))
    }

    delegate: Item {
      id: line
      width: view.width
      height: content.implicitHeight

      readonly property int currentIndex: root.service ? root.service.currentIndex : -1
      readonly property bool isCurrent: index === currentIndex
      readonly property bool isPast: currentIndex >= 0 && index < currentIndex
      readonly property bool clickable: root.interactive && root.service && root.service.status === "synced" && modelData.time >= 0
      readonly property bool hovered: hoverArea.containsMouse
      readonly property string romanizeMode: root.service ? root.service.romanize : "Off"
      readonly property string romanizedText: modelData.romanized && modelData.romanized !== modelData.text ? modelData.romanized : ""
      readonly property bool showRomanized: romanizeMode !== "Off" && romanizedText !== ""
      readonly property string mainText: (romanizeMode === "Replace" && showRomanized) ? romanizedText : (modelData.text.length > 0 ? modelData.text : "♪")
      readonly property string translatedText: modelData.translated && modelData.translated !== modelData.text ? modelData.translated : ""
      readonly property bool showTranslated: translatedText !== "" && root.service && root.service.translate !== "Off"

      Column {
        id: content
        width: parent.width
        spacing: Style.space(2)

        Text {
          id: lineText
          width: parent.width
          text: line.mainText
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: line.isCurrent ? root.foreground : root.dim
          opacity: line.isCurrent ? 1.0 : (line.hovered ? 0.9 : (line.isPast ? 0.35 : 0.6))
          font.family: root.fontFamily
          font.pixelSize: line.isCurrent ? Style.font.title : Style.font.body
          font.bold: line.isCurrent

          Behavior on opacity {
            NumberAnimation { duration: 180 }
          }
          Behavior on color {
            ColorAnimation { duration: 180 }
          }
        }

        Text {
          width: parent.width
          visible: line.romanizeMode === "Below" && line.showRomanized
          text: line.romanizedText
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: root.faint
          opacity: line.isCurrent ? 1.0 : 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          visible: line.showTranslated
          text: line.translatedText
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: root.dim
          opacity: line.isCurrent ? 1.0 : 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }
      }

      MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: line.clickable
        cursorShape: line.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.service.seekTo(modelData.time)
      }
    }

    onMovementStarted: scrollAnim.stop()

    Connections {
      target: root.service
      function onLinesChanged() {
        scrollAnim.stop()
        view.positionViewAtBeginning()
      }
      function onCurrentIndexChanged() {
        view.scrollToCurrent()
      }
    }

    function scrollToCurrent() {
      const idx = root.service ? root.service.currentIndex : -1
      if (idx < 0) return
      const item = view.itemAtIndex(idx)
      if (!item) return

      let y = item.y + item.height / 2 - view.height / 2
      y = Math.max(0, Math.min(y, Math.max(0, view.contentHeight - view.height)))
      if (Math.abs(y - view.contentY) < 2) return

      scrollAnim.stop()
      scrollAnim.to = y
      scrollAnim.restart()
    }

    NumberAnimation {
      id: scrollAnim
      target: view
      property: "contentY"
      duration: 400
      easing.type: Easing.OutCubic
    }
  }

  // ------------------------------------------------------------- empty state
  Column {
    anchors.centerIn: view
    width: view.width - Style.space(24)
    spacing: Style.space(10)
    visible: root.service && root.service.lines.length === 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "󰝚"
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      visible: root.service && root.service.status === "loading"

      SequentialAnimation on opacity {
        running: root.service && root.service.status === "loading"
        loops: Animation.Infinite
        NumberAnimation { to: 0.2; duration: 650; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
      }
    }

    Text {
      width: parent.width
      text: root.emptyMessage
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Try again"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      visible: root.service && (root.service.status === "error" || root.service.status === "notfound")
      onClicked: root.service.reload()
    }
  }

  // -------------------------------------------------------------- seek bar
  // Knobless: click anywhere to jump, press and drag to scrub.
  SliderBar {
    id: seekBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    value: root.service ? root.service.progress : 0
    enabled: root.service !== null && root.service.canSeek
    trackColor: Util.alpha(root.foreground, 0.15)
    fillColor: Color.accent
    onCommitted: function (value) {
      if (root.service) root.service.seekTo(value * root.service.length)
    }
  }
}
