import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Bar widget: the line being sung right now plus a thin progress underline, and
// a popup with the full lyrics and the media controls.
//
//   left click   open/close the popup (lyrics + controls)
//   right click  open the popup straight on its settings page
//   middle click play/pause
//   wheel        volume, with a tooltip showing the new level
//
// It follows any MPRIS player (Spotify, mpv, browsers, ...), hides itself while
// nothing is running and, optionally, while the current track has no lyrics.
BarWidget {
  id: root
  moduleName: "io.github.enrell.super-player"

  PlayerService {
    id: media
    source: String(root.settingValue("source"))
    romanize: String(root.settingValue("romanize"))
    translate: String(root.settingValue("translate"))
  }

  // --------------------------------------------------------------- settings
  // Values live on this widget's entry in ~/.config/omarchy/shell.json, which
  // the shell hot-reloads; updateEntryInline persists a change.
  readonly property var settingFallbacks: ({
    source: "Auto",
    romanize: "Off",
    translate: "Off",
    barLabel: "Lyric line",
    maxLabelWidth: 180,
    hideWhenNoLyrics: false
  })

  readonly property var languageOptions: [
    { value: "Off", label: "Off" },
    { value: "pt-BR", label: "Portuguese (Brazil)" },
    { value: "pt-PT", label: "Portuguese (Portugal)" },
    { value: "en", label: "English" },
    { value: "es", label: "Spanish" },
    { value: "fr", label: "French" },
    { value: "de", label: "German" },
    { value: "it", label: "Italian" },
    { value: "ja", label: "Japanese" },
    { value: "ko", label: "Korean" },
    { value: "zh-CN", label: "Chinese (Simplified)" },
    { value: "ru", label: "Russian" }
  ]

  readonly property var labelWidthOptions: [
    { value: 120, label: "120 px" },
    { value: 180, label: "180 px" },
    { value: 240, label: "240 px" },
    { value: 320, label: "320 px" }
  ]

  // Every MPRIS player currently on the bus, plus the automatic choice.
  readonly property var sourceOptions: {
    const out = [{ value: "Auto", label: "Automatic (playing player)" }]
    const all = media.players
    for (let i = 0; i < all.length; i++) {
      const p = all[i]
      out.push({ value: p.dbusName, label: p.identity || p.desktopEntry || p.dbusName })
    }
    return out
  }

  function settingValue(key) {
    return root.setting(key, root.settingFallbacks[key])
  }

  function persistSetting(key, value) {
    const entry = { id: root.moduleName }
    for (const existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  readonly property string romanizeHint: {
    if (media.romanize === "Off") return ""
    if (media.romanizeTool === "pykakasi") return "Romanization uses pykakasi (Japanese readings, words split into tokens)."
    if (media.romanizeTool === "kakasi") return "Romanization uses kakasi. For better Japanese readings install the python-pykakasi package: omarchy pkg add python-pykakasi"
    if (media.romanizeTool === "uconv") return "Romanization uses ICU only: kana, Hangul, Cyrillic, Greek... Japanese kanji are left as-is. Install python-pykakasi or kakasi for readings."
    return "No transliterator found. Install the python-pykakasi or kakasi package to enable romanization."
  }

  readonly property string translateHint: {
    if (media.translate === "Off") return ""
    if (media.translateStatus === "loading") return "Translating lyrics…"
    if (media.translateStatus === "error") return "Translation failed — check your connection (Google Translate)."
    return "Translated with Google Translate, cached per track."
  }

  // --------------------------------------------------------------- bar item
  readonly property color foreground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color faint: Qt.darker(root.foreground, 1.8)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property bool hasPlayer: media.player !== null
  readonly property bool hideWithoutLyrics: root.settingValue("hideWhenNoLyrics") === true
  readonly property int labelWidth: Number(root.settingValue("maxLabelWidth"))

  // The bar shows the most readable version of the current line: the
  // translation, else the romanization, else the original.
  readonly property string lyricLine: {
    if (media.currentLine === "") return ""
    if (media.translate !== "Off" && media.currentTranslatedLine !== "") return media.currentTranslatedLine
    if (media.romanize !== "Off" && media.currentRomanizedLine !== "") return media.currentRomanizedLine
    return media.currentLine
  }

  readonly property string label: {
    const mode = String(root.settingValue("barLabel"))
    if (mode === "Icon only") return ""
    if (mode === "Track") return media.trackTitle
    return root.lyricLine !== "" ? root.lyricLine : media.trackTitle
  }

  readonly property bool shown: root.hasPlayer && !(root.hideWithoutLyrics && media.currentLine === "")

  property bool popupOpen: false
  property bool settingsOpen: false

  function close() {
    root.popupOpen = false
    root.settingsOpen = false
  }

  visible: root.shown
  implicitWidth: root.shown ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  Timer {
    id: tooltipTimer
    interval: 1400
    onTriggered: if (root.bar) root.bar.hideTooltip(root)
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰝚"
      color: media.playing ? root.foreground : Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.labelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && labelText.text !== ""

      Text {
        id: labelText
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body

        readonly property bool needsScroll: implicitWidth > scrollClip.width

        // A long line scrolls through the slot; a short one rests at the left
        // edge, so the offset has to be cleared when the line changes.
        onTextChanged: if (!needsScroll) x = 0
        onNeedsScrollChanged: if (!needsScroll) x = 0

        NumberAnimation on x {
          running: labelText.needsScroll && !root.popupOpen && !root.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  // The widget doubles as a progress bar: a hairline along its bottom edge.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    visible: root.shown
    color: Util.alpha(root.foreground, 0.15)

    Rectangle {
      width: parent.width * media.progress
      height: parent.height
      color: Color.accent
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function (mouse) {
      if (!root.hasPlayer) return
      if (mouse.button === Qt.MiddleButton) {
        media.togglePlaying()
        return
      }
      if (mouse.button === Qt.RightButton) {
        if (root.popupOpen && root.settingsOpen) root.close()
        else {
          root.settingsOpen = true
          root.popupOpen = true
        }
        return
      }
      if (root.popupOpen) root.close()
      else root.popupOpen = true
    }
    onWheel: function (wheel) {
      if (!root.hasPlayer || !media.volumeSupported) return
      media.volumeBy(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
      if (root.bar) root.bar.showTooltip(root, "Volume " + Math.round(media.volume * 100) + "%")
      tooltipTimer.restart()
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, media.trackTitle + (media.trackArtist !== "" ? " — " + media.trackArtist : ""))
    onExited: {
      tooltipTimer.stop()
      if (root.bar) root.bar.hideTooltip(root)
    }
  }

  IpcHandler {
    target: "super-player"
    function toggle(): void { root.popupOpen ? root.close() : root.popupOpen = true }
    function open(): void { root.settingsOpen = false; root.popupOpen = true }
    function close(): void { root.close() }
    function settings(): void { root.settingsOpen = true; root.popupOpen = true }
    function playPause(): void { media.togglePlaying() }
    function next(): void { media.next() }
    function previous(): void { media.previous() }
    function mute(): void { media.toggleMute() }
    function volumeUp(): void { media.volumeBy(0.05) }
    function volumeDown(): void { media.volumeBy(-0.05) }
    function status(): string {
      return JSON.stringify({
        player: media.player ? (media.player.identity || media.player.dbusName) : "",
        track: media.trackTitle,
        artist: media.trackArtist,
        playing: media.playing,
        lyrics: media.status,
        lines: media.lines.length,
        index: media.currentIndex,
        volume: Math.round(media.volume * 100),
        muted: media.volume <= 0.001
      })
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(root.settingsOpen ? settingsColumn.implicitHeight : Style.space(390), Style.space(620))

    LyricsView {
      visible: !root.settingsOpen
      width: parent.width
      height: Style.space(390)
      headerRightInset: Style.space(30)
      bar: root.bar
      service: media
    }

    Button {
      anchors.top: parent.top
      anchors.right: parent.right
      visible: !root.settingsOpen
      iconText: "󰒓"
      iconSize: Style.font.icon
      foreground: root.faint
      tooltipText: "Super Player settings"
      onClicked: root.settingsOpen = true
    }

    Column {
      id: settingsColumn
      visible: root.settingsOpen
      width: parent.width
      spacing: Style.space(8)

      PanelHero {
        width: parent.width
        title: "Super Player"
        meta: "Settings"
        foreground: root.foreground
        fontFamily: root.fontFamily
        trailingControl: Component {
          Button {
            text: "Back"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.settingsOpen = false
          }
        }
      }

      Dropdown {
        width: settingsColumn.width
        label: "Player"
        showLabel: true
        options: root.sourceOptions
        foreground: root.foreground
        background: Color.popups.background
        accent: Color.accent
        fontFamily: root.fontFamily
        Binding on value { value: String(root.settingValue("source")) }
        onChanged: function (value) { root.persistSetting("source", value) }
      }

      Dropdown {
        width: settingsColumn.width
        label: "Romanize"
        showLabel: true
        options: ["Off", "Replace", "Below"]
        foreground: root.foreground
        background: Color.popups.background
        accent: Color.accent
        fontFamily: root.fontFamily
        Binding on value { value: String(root.settingValue("romanize")) }
        onChanged: function (value) { root.persistSetting("romanize", value) }
      }

      Dropdown {
        width: settingsColumn.width
        label: "Translate to"
        showLabel: true
        options: root.languageOptions
        foreground: root.foreground
        background: Color.popups.background
        accent: Color.accent
        fontFamily: root.fontFamily
        Binding on value { value: String(root.settingValue("translate")) }
        onChanged: function (value) { root.persistSetting("translate", value) }
      }

      Dropdown {
        width: settingsColumn.width
        label: "Bar label"
        showLabel: true
        options: ["Lyric line", "Track", "Icon only"]
        foreground: root.foreground
        background: Color.popups.background
        accent: Color.accent
        fontFamily: root.fontFamily
        Binding on value { value: String(root.settingValue("barLabel")) }
        onChanged: function (value) { root.persistSetting("barLabel", value) }
      }

      Dropdown {
        width: settingsColumn.width
        label: "Label width"
        showLabel: true
        options: root.labelWidthOptions
        foreground: root.foreground
        background: Color.popups.background
        accent: Color.accent
        fontFamily: root.fontFamily
        Binding on value { value: String(root.settingValue("maxLabelWidth")) }
        onChanged: function (value) { root.persistSetting("maxLabelWidth", Number(value)) }
      }

      Dropdown {
        width: settingsColumn.width
        label: "Hide without lyrics"
        showLabel: true
        options: [{ value: false, label: "Off" }, { value: true, label: "On" }]
        foreground: root.foreground
        background: Color.popups.background
        accent: Color.accent
        fontFamily: root.fontFamily
        Binding on value { value: String(root.settingValue("hideWhenNoLyrics")) }
        onChanged: function (value) { root.persistSetting("hideWhenNoLyrics", value === "true") }
      }

      PanelSeparator {
        foreground: root.foreground
      }

      Text {
        width: parent.width
        visible: root.romanizeHint !== ""
        textFormat: Text.PlainText
        text: root.romanizeHint
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: root.translateHint !== ""
        textFormat: Text.PlainText
        text: root.translateHint
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  // A failed fetch is worth another try as soon as the popup is opened.
  onPopupOpenChanged: if (popupOpen && (media.status === "error" || media.status === "notfound")) media.reload()
}
