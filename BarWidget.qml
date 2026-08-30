import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.olivoil.hurricane-tracker"

  readonly property string pluginId: root.moduleName
    || "io.github.olivoil.hurricane-tracker"
  readonly property var tracker: bar && bar.shell
    ? bar.shell.serviceFor(pluginId) : null
  readonly property int activeCount: tracker ? tracker.activeCount : 0
  readonly property int trackingCount: tracker ? tracker.trackingCount : 0
  readonly property var strongestStorm: activeCount > 0 ? tracker.storms[0] : null

  function syncService() {
    if (root.tracker && "settings" in root.tracker) root.tracker.settings = root.settings
  }

  function refresh() {
    if (root.tracker && root.tracker.refresh) root.tracker.refresh()
  }

  function tooltip() {
    if (!tracker || (!tracker.hasLoaded && tracker.loading)) return "Hurricane Tracker is checking the National Hurricane Center"
    var summary = Model.trackingSummary(tracker.storms, tracker.outlooks)
    if (tracker.watchPlaceCount > 0) summary += " · " + tracker.watchPlaceCount
      + (tracker.watchPlaceCount === 1 ? " watched location" : " watched locations")
    if (tracker.stale) summary = "Saved advisory: " + summary
    return summary + "  ·  left open  ·  middle refresh  ·  right NHC"
  }

  onTrackerChanged: syncService()
  onSettingsChanged: syncService()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    fixedWidth: Math.max(Style.space(24), barContent.implicitWidth + Style.space(10))
    active: root.trackingCount > 0
    activeColor: root.strongestStorm ? Model.severityColor(root.strongestStorm)
      : (root.bar ? root.bar.barForeground : Color.foreground)
    tooltipText: root.tooltip()

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.spacing.xxs

      readonly property color contentColor: button.active ? button.activeColor : button.foreground

      HurricaneIcon {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.icon
        height: width
        iconColor: barContent.contentColor
      }

      Text {
        visible: root.trackingCount > 0
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.trackingCount)
        textFormat: Text.PlainText
        color: barContent.contentColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true

        Behavior on color { ColorAnimation { duration: 160 } }
      }
    }

    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.MiddleButton) {
        root.refresh()
      } else if (mouseButton === Qt.RightButton) {
        Quickshell.execDetached(["omarchy-launch-browser", "https://www.nhc.noaa.gov/"])
      } else {
        root.bar.run("omarchy-shell shell toggle " + root.pluginId)
      }
    }
  }
}
