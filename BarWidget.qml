import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.olivoil.omanado"

  readonly property var tracker: bar && bar.shell
    ? bar.shell.serviceFor("io.github.olivoil.omanado") : null
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
    if (!tracker || (!tracker.hasLoaded && tracker.loading)) return "Omanado is checking the National Hurricane Center"
    var summary = Model.trackingSummary(tracker.storms, tracker.outlooks)
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
    text: root.trackingCount > 0 ? "\uf751  " + root.trackingCount : "\uf751"
    active: root.trackingCount > 0
    activeColor: root.strongestStorm ? Model.severityColor(root.strongestStorm)
      : (root.bar ? root.bar.barForeground : Color.foreground)
    tooltipText: root.tooltip()

    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.MiddleButton) {
        root.refresh()
      } else if (mouseButton === Qt.RightButton) {
        Quickshell.execDetached(["omarchy-launch-browser", "https://www.nhc.noaa.gov/"])
      } else {
        root.bar.run("omarchy-shell shell toggle io.github.olivoil.omanado")
      }
    }
  }
}
