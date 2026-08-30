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
  readonly property bool hasWatchPlaces: tracker ? tracker.watchPlaceCount > 0 : false
  readonly property var watchPlaceSummaries: hasWatchPlaces
    ? Model.watchPlaceSummaries(tracker.storms, tracker.outlooks,
      tracker.watchPlaces, tracker.formationThreshold, tracker.useImperial === true) : []
  readonly property int personalAlertCount: Model.watchAttentionCount(watchPlaceSummaries)
  readonly property string personalAttentionState:
    Model.watchStrongestAttentionState(watchPlaceSummaries)
  readonly property int indicatorCount: hasWatchPlaces ? personalAlertCount : trackingCount
  readonly property color personalAlertColor: personalAttentionState === "urgent" ? Color.urgent
    : (personalAttentionState === "monitor" ? "#e9be62" : Color.accent)
  readonly property color indicatorColor: hasWatchPlaces ? personalAlertColor
    : (strongestStorm ? Model.severityColor(strongestStorm)
      : (bar ? bar.barForeground : Color.foreground))

  function syncService() {
    if (root.tracker && "settings" in root.tracker) root.tracker.settings = root.settings
  }

  function refresh() {
    if (root.tracker && root.tracker.refresh) root.tracker.refresh()
  }

  function openSource() {
    Quickshell.execDetached(["omarchy-launch-browser", "https://www.nhc.noaa.gov/"])
    if (root.bar && root.bar.shell && typeof root.bar.shell.hide === "function")
      root.bar.shell.hide(root.pluginId)
  }

  function tooltip() {
    if (!tracker || (!tracker.hasLoaded && tracker.loading)) return "Checking NHC data"
    var summary = ""
    if (hasWatchPlaces) {
      summary = personalAlertCount > 0
        ? personalAlertCount + (personalAlertCount === 1
          ? " location needs attention" : " locations need attention")
        : "All locations quiet"
      if (trackingCount > 0) summary += " · " + trackingCount
        + (trackingCount === 1 ? " system tracked" : " systems tracked")
    } else {
      summary = Model.trackingSummary(tracker.storms, tracker.outlooks)
    }
    return tracker.stale ? "Saved data · " + summary : summary
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
    active: root.indicatorCount > 0
    activeColor: root.indicatorColor
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
        visible: root.indicatorCount > 0
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.indicatorCount)
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
        root.openSource()
      } else if (root.hasWatchPlaces && root.personalAlertCount > 0) {
        root.bar.run("omarchy-shell shell summon " + root.pluginId + " '{\"alerts\":true}'")
      } else {
        root.bar.run("omarchy-shell shell toggle " + root.pluginId)
      }
    }
  }
}
