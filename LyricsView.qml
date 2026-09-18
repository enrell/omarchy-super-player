import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Themed lyrics content: track header (cover art, title, artist, state), the
// synced lyrics list and a progress bar.
//
// Shared by the bar popup (Bar.qml) and the floating panel (Floating.qml); the
// host decides the height, the list fills the space between header and bar.
Item {
  id: root

  property QtObject bar: null      // set when hosted inside the bar
  property var service: null       // Service instance
  property bool interactive: true  // click a line to seek there
  property bool showControls: true  // previous / play-pause / next, volume, mute
  property real headerSize: Style.space(64)
  property real headerRightInset: 0 // room for a control in the host header

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color faint: Qt.darker(foreground, 1.8)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string statusLabel: {
    if (!service) return ""
    switch (service.status) {
    case "loading": return "fetching lyrics…"
    case "synced": return "synced lyrics"
    case "plain": return "unsynced lyrics"
    case "notfound": return "no lyrics found"
    case "error": return "network error"
    }
    return ""
  }

  readonly property string emptyMessage: {
    if (!service) return ""
    switch (service.status) {
    case "noplayer": return "No player running.\nOpen Spotify and press play."
    case "loading": return "Fetching lyrics…"
    case "notfound": return "No lyrics found on LRCLIB."
    case "error": return "Could not fetch the lyrics.\nCheck your connection."
    }
    return ""
  }

  implicitHeight: root.headerSize + Style.space(12) + Style.space(240) + Style.space(10) + controls.height + Style.space(10) + progressBar.height

  // ------------------------------------------------------------------ header
  Row {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.headerSize
    spacing: Style.space(10)

    BorderSurface {
      width: root.headerSize
      height: root.headerSize
      radius: Style.spacing.labelGap
      color: Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

      Image {
        id: art
        anchors.fill: parent
        anchors.margins: Style.space(2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: root.service ? root.service.trackArtUrl : ""
        visible: source !== "" && status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: !art.visible
        text: "󰝚"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.displayLarge
      }
    }

    Column {
      width: parent.width - root.headerSize - Style.space(10) - root.headerRightInset
      spacing: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter

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

      Text {
        textFormat: Text.PlainText
        text: root.statusLabel
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
        visible: text !== ""
      }
    }
  }

  // ---------------------------------------------------------- media controls
  Row {
    id: controls
    anchors.bottom: progressBar.top
    anchors.bottomMargin: Style.space(12)
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.spacing.controlHeight
    spacing: Style.space(4)
    visible: root.showControls && root.service !== null

    Button {
      iconText: "󰒮"
      foreground: root.foreground
      fontFamily: root.fontFamily
      tooltipText: "Previous track"
      enabled: root.service !== null && root.service.canGoPrevious
      opacity: enabled ? 1.0 : 0.35
      onClicked: root.service.previous()
    }

    Button {
      iconText: root.service && root.service.playing ? "󰏤" : "󰐊"
      iconSize: Style.font.iconLarge
      foreground: root.foreground
      fontFamily: root.fontFamily
      tooltipText: root.service && root.service.playing ? "Pause" : "Play"
      enabled: root.service !== null && root.service.canTogglePlaying
      opacity: enabled ? 1.0 : 0.35
      onClicked: root.service.togglePlaying()
    }

    Button {
      iconText: "󰒭"
      foreground: root.foreground
      fontFamily: root.fontFamily
      tooltipText: "Next track"
      enabled: root.service !== null && root.service.canGoNext
      opacity: enabled ? 1.0 : 0.35
      onClicked: root.service.next()
    }

    Item {
      width: Style.space(8)
      height: 1
    }

    Button {
      iconText: root.service && root.service.volume > 0.001 ? "󰕾" : "󰖁"
      foreground: root.foreground
      fontFamily: root.fontFamily
      tooltipText: root.service && root.service.volume > 0.001 ? "Mute" : "Unmute"
      enabled: root.service !== null && root.service.volumeSupported
      opacity: enabled ? 1.0 : 0.35
      onClicked: root.service.toggleMute()
    }

    PanelSlider {
      id: volumeSlider
      width: Math.max(Style.space(90), controls.width - Style.space(150))
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar
      minimum: 0
      maximum: 1
      enabled: root.service !== null && root.service.volumeSupported
      opacity: enabled ? 1.0 : 0.35
      Binding on value { value: root.service ? root.service.volume : 0 }
      onMoved: function (value) { if (root.service) root.service.setVolume(value) }
    }
  }

  // ------------------------------------------------------------------ lyrics
  ListView {
    id: view
    anchors.top: header.bottom
    anchors.topMargin: Style.space(12)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: controls.visible ? controls.top : progressBar.top
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

  // ---------------------------------------------------------------- progress
  Rectangle {
    id: progressBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(1, Style.space(2))
    radius: height / 2
    color: Util.alpha(root.foreground, 0.12)

    Rectangle {
      width: parent.width * (root.service ? root.service.progress : 0)
      height: parent.height
      radius: parent.radius
      color: Color.accent
    }
  }
}
