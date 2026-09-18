import QtQuick
import qs.Commons

// A modern, knobless slider: a hairline that thickens slightly on hover to show
// it can be dragged. Clicking anywhere jumps there (forwards or backwards),
// pressing and moving follows the pointer.
//
//   value      0..1, the position to display (the host keeps it in sync)
//   moved      live value while dragging (optional, for previews)
//   committed  final value, emitted on release and on a plain click
Item {
  id: root

  property real value: 0
  property bool enabled: true
  property color trackColor: Util.alpha(Color.foreground, 0.15)
  property color fillColor: Color.accent
  property real thickness: Math.max(2, Style.space(3))
  property real hoverThickness: Math.max(4, Style.space(7))
  property bool dragging: false

  readonly property bool hovered: area.containsMouse
  readonly property real displayValue: root.dragging ? dragValue : root.value
  property real dragValue: 0

  signal moved(real value)
  signal committed(real value)
  // Comfortable grab area; the visible track stays a hairline.
  implicitHeight: Math.max(Style.space(14), root.hoverThickness)

  function valueAt(x) {
    return Math.max(0, Math.min(1, x / Math.max(1, root.width)))
  }

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: (area.containsMouse || root.dragging) ? root.hoverThickness : root.thickness
    radius: height / 2
    color: root.trackColor

    Behavior on height {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Rectangle {
      width: parent.width * root.displayValue
      height: parent.height
      radius: parent.radius
      color: root.enabled ? root.fillColor : root.trackColor
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    onPressed: function (mouse) {
      root.dragValue = root.valueAt(mouse.x)
      root.dragging = true
      root.moved(root.dragValue)
    }
    onPositionChanged: function (mouse) {
      if (!root.dragging) return
      root.dragValue = root.valueAt(mouse.x)
      root.moved(root.dragValue)
    }
    onReleased: {
      root.dragging = false
      root.committed(root.dragValue)
    }
  }
}
