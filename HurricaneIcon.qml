import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property color iconColor: "#45c6b5"
  readonly property real strokeWidth: Math.max(1.25, Math.min(width, height) * 0.102)

  implicitWidth: 18
  implicitHeight: 18

  Shape {
    anchors.fill: parent
    antialiasing: true

    ShapePath {
      strokeColor: root.iconColor
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root.width * 0.109
      startY: root.height * 0.484

      PathCubic {
        control1X: root.width * 0.156
        control1Y: root.height * 0.188
        control2X: root.width * 0.484
        control2Y: root.height * 0.063
        x: root.width * 0.734
        y: root.height * 0.203
      }
      PathCubic {
        control1X: root.width * 0.859
        control1Y: root.height * 0.281
        control2X: root.width * 0.906
        control2Y: root.height * 0.422
        x: root.width * 0.828
        y: root.height * 0.531
      }
      PathCubic {
        control1X: root.width * 0.766
        control1Y: root.height * 0.625
        control2X: root.width * 0.641
        control2Y: root.height * 0.641
        x: root.width * 0.547
        y: root.height * 0.578
      }
    }

    ShapePath {
      strokeColor: root.iconColor
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root.width * 0.891
      startY: root.height * 0.516

      PathCubic {
        control1X: root.width * 0.844
        control1Y: root.height * 0.813
        control2X: root.width * 0.516
        control2Y: root.height * 0.938
        x: root.width * 0.266
        y: root.height * 0.797
      }
      PathCubic {
        control1X: root.width * 0.141
        control1Y: root.height * 0.719
        control2X: root.width * 0.094
        control2Y: root.height * 0.578
        x: root.width * 0.172
        y: root.height * 0.469
      }
      PathCubic {
        control1X: root.width * 0.234
        control1Y: root.height * 0.375
        control2X: root.width * 0.359
        control2Y: root.height * 0.359
        x: root.width * 0.453
        y: root.height * 0.422
      }
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.max(2, Math.min(parent.width, parent.height) * 0.14)
    height: width
    radius: width / 2
    color: root.iconColor
    antialiasing: true
  }

  Behavior on iconColor { ColorAnimation { duration: 160 } }
}
