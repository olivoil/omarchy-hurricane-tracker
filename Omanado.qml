import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string selectedKey: ""
  property string expandedRegion: ""
  property bool regionDisclosureInitialized: false
  property int clockTick: 0

  readonly property var tracker: shell ? shell.serviceFor("io.github.olivoil.omanado") : null
  readonly property var storms: tracker && Array.isArray(tracker.storms) ? tracker.storms : []
  readonly property var outlooks: tracker && Array.isArray(tracker.outlooks) ? tracker.outlooks : []
  readonly property var systems: Model.orderedSystems(storms, outlooks)
  readonly property var regionalRows: Model.disclosedRegionalRows(storms, outlooks, expandedRegion)
  readonly property var selectedSystem: Model.systemByKey(systems, selectedKey)
  readonly property var selectedStorm: selectedSystem && selectedSystem.kind === "storm" ? selectedSystem : null
  readonly property var selectedOutlook: selectedSystem && selectedSystem.kind === "outlook" ? selectedSystem : null
  readonly property bool lightTheme:
    0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b > 0.5

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
  property color mapDeepOcean: blendColor(background, foreground, lightTheme ? 0.035 : 0.018)
  property color mapOcean: blendColor(background, accent, lightTheme ? 0.13 : 0.10)
  property color mapLand: blendColor(blendColor(background, foreground, lightTheme ? 0.28 : 0.18), accent, 0.08)
  property color mapLandOutline: blendColor(background, foreground, lightTheme ? 0.50 : 0.46)
  property color mapGrid: blendColor(background, foreground, lightTheme ? 0.52 : 0.58)
  property color mapText: foreground
  property color mapMuted: blendColor(background, foreground, lightTheme ? 0.70 : 0.66)
  property color mapCone: accent
  property color mapTrack: foreground

  readonly property int cardWidth: Math.min(Style.space(1660), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(980), panel.height - Style.gapsOut * 2)
  readonly property int headerHeight: Style.space(66)
  readonly property int sidebarWidth: Math.min(Style.space(370), cardWidth * 0.35)
  readonly property int timelineHeight: Style.space(100)

  function blendColor(first, second, amount) {
    var t = Math.max(0, Math.min(1, Number(amount)))
    return Qt.rgba(
      first.r * (1 - t) + second.r * t,
      first.g * (1 - t) + second.g * t,
      first.b * (1 - t) + second.b * t,
      first.a * (1 - t) + second.a * t
    )
  }

  function systemColor(system) {
    return system && system.kind === "outlook" ? Model.outlookColor(system) : Model.severityColor(system)
  }

  function summaryFacts(system) {
    if (!system) return []
    if (system.kind === "outlook") return [
      { label: "2-DAY CHANCE", value: String(system.twoDayChance || 0) + "%" },
      { label: "7-DAY CHANCE", value: String(system.sevenDayChance || 0) + "%" },
      { label: "BASIN", value: String(system.basinLabel || Model.regionName(system.basin)) }
    ]
    return [
      { label: "MAX WIND", value: Model.formatWind(system) },
      { label: "PRESSURE", value: Model.formatPressure(system) },
      { label: "MOVEMENT", value: Model.formatMovement(system) }
    ]
  }

  function summaryContext(system) {
    if (!system) return ""
    var classification = Model.systemClassificationLabel(system)
    if (system.kind === "outlook") return classification + " · NHC outlook"
    var advisory = String(system.advisoryNumber || "").replace(/^0+/, "")
    return classification + (advisory !== "" ? " · Advisory " + advisory : "")
  }

  function summaryAgeLabel(system) {
    clockTick
    if (!system) return ""
    var age = Model.humanAge(system.updatedAt)
    var partial = Array.isArray(system.dataWarnings) && system.dataWarnings.length > 0
    return partial ? "Partial · " + age : age
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (error) { payload = ({}) }
    if (payload.stormId) selectedKey = "storm:" + String(payload.stormId)
    if (payload.outlookId) selectedKey = "outlook:" + String(payload.outlookId)
    opened = true
    syncSelection(true)
    if (tracker && !tracker.hasLoaded && !tracker.loading) tracker.refresh()
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      if (payload.globe === true) stormMap.showGlobe()
      else stormMap.fitSelected()
    })
  }

  function close() {
    opened = false
  }

  function showGlobe(_payload) {
    stormMap.showGlobe()
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.olivoil.omanado")
  }

  function syncSelection(forceReveal) {
    var previousKey = selectedKey
    selectedKey = Model.selectedKeyAfterRefresh(systems, selectedKey)
    var selected = Model.systemByKey(systems, selectedKey)
    if (selected && (forceReveal || selected.key !== previousKey || !regionDisclosureInitialized)) {
      expandedRegion = String(selected.basin || "")
      regionDisclosureInitialized = true
    }
    Qt.callLater(function() {
      var rowIndex = root.rowIndexForKey(root.selectedKey)
      var sectionIndex = regionRowForIndex(rowIndex)
      if (sectionIndex >= 0) systemList.positionViewAtIndex(sectionIndex, ListView.Beginning)
    })
  }

  function rowIndexForKey(key) {
    for (var i = 0; i < regionalRows.length; i++) {
      if (regionalRows[i].kind === "system" && regionalRows[i].key === key) return i
    }
    return -1
  }

  function regionRowForIndex(index) {
    for (var i = Math.min(index, regionalRows.length - 1); i >= 0; i--) {
      if (regionalRows[i].kind === "region") return i
    }
    return -1
  }

  function regionIndexForBasin(basin) {
    for (var i = 0; i < regionalRows.length; i++) {
      if (regionalRows[i].kind === "region" && regionalRows[i].basin === basin) return i
    }
    return -1
  }

  function toggleRegion(basin) {
    var opening = expandedRegion !== basin
    expandedRegion = opening ? basin : ""
    regionDisclosureInitialized = true
    if (opening) stormMap.fitRegion(basin)
    Qt.callLater(function() {
      var index = root.regionIndexForBasin(basin)
      if (index >= 0) systemList.positionViewAtIndex(index, ListView.Contain)
    })
    keyCatcher.forceActiveFocus()
  }

  function viewRegion(basin) {
    if (!basin) return
    expandedRegion = String(basin)
    regionDisclosureInitialized = true
    stormMap.fitRegion(basin)
    Qt.callLater(function() {
      var index = root.regionIndexForBasin(basin)
      if (index >= 0) systemList.positionViewAtIndex(index, ListView.Beginning)
    })
    keyCatcher.forceActiveFocus()
  }

  function selectSystem(key) {
    var system = Model.systemByKey(systems, key)
    if (!system) return
    selectedKey = key
    expandedRegion = String(system.basin || "")
    regionDisclosureInitialized = true
    Qt.callLater(function() {
      var rowIndex = root.rowIndexForKey(key)
      if (rowIndex >= 0) systemList.positionViewAtIndex(rowIndex, ListView.Contain)
    })
    keyCatcher.forceActiveFocus()
  }

  function moveSelection(delta) {
    if (systems.length === 0) return
    var current = 0
    for (var i = 0; i < systems.length; i++) if (systems[i].key === selectedKey) current = i
    var next = (current + delta + systems.length) % systems.length
    selectSystem(systems[next].key)
  }

  function refresh() {
    if (tracker && tracker.refresh) tracker.refresh()
  }

  function officialUrl(storm, field) {
    return Model.safeOfficialUrl(storm && storm[field])
  }

  function openOfficial(storm, field) {
    var url = officialUrl(storm, field)
    if (url) Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function handleHyprlandEvent(event) {
    if (!opened || String(event && event.name || "") !== "openwindow") return
    var parts = []
    try { parts = event.parse(4) }
    catch (error) { parts = String(event && event.data || "").split(",") }
    if (String(parts[2] || "") === "org.omarchy.screensaver") dismiss()
  }

  Connections {
    target: root.tracker
    function onStormsChanged() { root.syncSelection(false) }
    function onOutlooksChanged() { root.syncSelection(false) }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.clockTick++
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region { item: card }
    color: "transparent"
    WlrLayershell.namespace: "omanado"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && cardHover.hovered
      ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius
      clip: true

      MouseArea {
        anchors.fill: parent
        onPressed: keyCatcher.forceActiveFocus()
      }

      HoverHandler {
        id: cardHover
        onHoveredChanged: if (hovered) keyCatcher.forceActiveFocus()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        z: 1
        Keys.priority: Keys.AfterItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_R) {
            root.refresh()
            event.accepted = true
          } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            stormMap.zoomIn()
            event.accepted = true
          } else if (event.key === Qt.Key_Minus) {
            stormMap.zoomOut()
            event.accepted = true
          } else if (event.key === Qt.Key_F) {
            stormMap.resetView()
            event.accepted = true
          } else if (event.key === Qt.Key_0 || event.key === Qt.Key_G) {
            stormMap.showGlobe()
            event.accepted = true
          } else if (event.key === Qt.Key_O && root.selectedStorm) {
            root.openOfficial(root.selectedStorm, "advisoryUrl")
            event.accepted = true
          }
        }
      }

      Rectangle {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.headerHeight
        color: root.background
        z: 3

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: root.border
        }

        HurricaneIcon {
          id: brandIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(21)
          height: width
          iconColor: root.storms.length > 0 ? Model.severityColor(root.storms[0])
            : (root.outlooks.length > 0 ? Model.outlookColor(root.outlooks[0]) : root.accent)
        }

        Column {
          anchors.left: brandIcon.right
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          Text {
            text: "HURRICANE TRACKER"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            font.letterSpacing: 1.2
          }
          Text {
            text: "CYCLONES · OUTLOOKS · DISCUSSIONS"
            textFormat: Text.PlainText
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.6
          }
        }

        Button {
          id: closeButton
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf00d"
          tooltipText: "Close (Esc)"
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.dismiss()
        }

        Button {
          id: nhcButton
          anchors.right: closeButton.left
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf35d"
          tooltipText: "Open the National Hurricane Center"
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: Quickshell.execDetached(["omarchy-launch-browser", "https://www.nhc.noaa.gov/"])
        }

        Button {
          id: refreshButton
          anchors.right: nhcButton.left
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf021"
          iconSpinning: root.tracker ? root.tracker.loading : false
          tooltipText: "Refresh NHC data (R)"
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.refresh()
        }

        Row {
          anchors.right: refreshButton.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 4
            color: !root.tracker || root.tracker.loading ? root.dim
              : (root.tracker.stale ? "#e9be62"
                : (root.tracker.status === "fresh" ? "#45c6b5" : root.urgent))
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !root.tracker || (!root.tracker.hasLoaded && root.tracker.loading) ? "CHECKING NHC"
              : (root.tracker.stale ? "SAVED ADVISORY"
                : (root.tracker.status === "fresh" ? "LIVE NHC" : "NHC UNAVAILABLE"))
            textFormat: Text.PlainText
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.5
          }
        }
      }

      Item {
        id: mapArea
        anchors.left: parent.left
        anchors.right: sidebar.left
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        clip: true
        z: 2

        StormMap {
          id: stormMap
          anchors.fill: parent
          storms: root.storms
          outlooks: root.outlooks
          selectedKey: root.selectedKey
          bottomInset: root.selectedStorm ? root.timelineHeight : 0
          oceanColor: root.mapOcean
          deepOceanColor: root.mapDeepOcean
          landColor: root.mapLand
          landOutlineColor: root.mapLandOutline
          gridColor: root.mapGrid
          textColor: root.mapText
          mutedTextColor: root.mapMuted
          coneColor: root.mapCone
          trackColor: root.mapTrack
          surfaceColor: root.background
          surfaceBorderColor: root.border
          fontFamily: Style.font.menuFamily
          onSystemActivated: function(key) { root.selectSystem(key) }
          onPointerActivity: keyCatcher.forceActiveFocus()
        }

        BorderSurface {
          id: stormSummary
          visible: root.selectedSystem !== null
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.top: parent.top
          anchors.topMargin: Style.spacing.lg
          width: Math.min(Style.space(384), mapArea.width - Style.spacing.lg * 2)
          height: Style.space(108)
          radius: Style.cornerRadius
          color: root.blendColor(root.background, root.foreground, root.lightTheme ? 0.018 : 0.028)
          borderSpec: Border.surfaceSpec("menu", "border", root.border,
            Math.max(1, Style.normalBorderWidth))
          z: 4

          Item {
            id: summaryIdentity
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.space(59)

            Rectangle {
              id: summaryBadge
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(36)
              height: width
              radius: root.selectedStorm ? width / 2 : Style.space(8)
              color: root.selectedSystem
                ? Qt.rgba(Qt.color(root.systemColor(root.selectedSystem)).r,
                  Qt.color(root.systemColor(root.selectedSystem)).g,
                  Qt.color(root.systemColor(root.selectedSystem)).b, root.lightTheme ? 0.20 : 0.18)
                : "transparent"
              border.width: 1
              border.color: root.selectedSystem ? root.systemColor(root.selectedSystem) : root.border

              Text {
                anchors.centerIn: parent
                text: root.selectedSystem
                  ? (root.selectedSystem.kind === "storm" ? Model.severityCode(root.selectedSystem)
                    : String(root.selectedSystem.sevenDayChance || 0) + "%")
                  : ""
                textFormat: Text.PlainText
                color: root.selectedSystem ? root.systemColor(root.selectedSystem) : root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Column {
              anchors.left: summaryBadge.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: summaryAge.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                text: root.selectedSystem
                  ? String(root.selectedSystem.name || root.selectedSystem.title || "Tropical system") : ""
                textFormat: Text.PlainText
                color: root.foreground
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                width: parent.width
                text: root.summaryContext(root.selectedSystem)
                textFormat: Text.PlainText
                color: root.selectedSystem ? root.systemColor(root.selectedSystem) : root.dim
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              id: summaryAge
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.xxl
              anchors.verticalCenter: parent.verticalCenter
              text: root.summaryAgeLabel(root.selectedSystem)
              textFormat: Text.PlainText
              color: root.selectedSystem && Array.isArray(root.selectedSystem.dataWarnings)
                && root.selectedSystem.dataWarnings.length > 0 ? "#e9be62" : root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            id: summaryDivider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: summaryIdentity.bottom
            height: 1
            color: root.border
            opacity: 0.72
          }

          Row {
            id: summaryMetrics
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.top: summaryDivider.bottom
            anchors.bottom: parent.bottom

            Repeater {
              model: root.summaryFacts(root.selectedSystem)

              Item {
                required property int index
                required property var modelData
                width: summaryMetrics.width / 3
                height: summaryMetrics.height

                Rectangle {
                  visible: index > 0
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.topMargin: Style.spacing.md
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.spacing.md
                  width: 1
                  color: root.border
                  opacity: 0.58
                }

                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: index > 0 ? Style.spacing.md : 0
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    text: String(modelData.label || "")
                    textFormat: Text.PlainText
                    color: root.dim
                    elide: Text.ElideRight
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.35
                  }
                  Text {
                    width: parent.width
                    text: String(modelData.value || "")
                    textFormat: Text.PlainText
                    color: root.foreground
                    elide: Text.ElideRight
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }
              }
            }
          }
        }

        Rectangle {
          id: errorBanner
          visible: root.tracker && root.tracker.error !== ""
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.top: stormSummary.visible ? stormSummary.bottom : parent.top
          anchors.topMargin: Style.spacing.sm
          height: Style.space(42)
          radius: 7
          color: Qt.rgba(0.92, 0.75, 0.38, root.lightTheme ? 0.24 : 0.17)
          border.width: 1
          border.color: "#e9be62"
          z: 4

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.right: retryButton.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            text: root.tracker ? root.tracker.error : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.mapText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }
          Button {
            id: retryButton
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            text: "Retry"
            focusable: true
            foreground: root.mapText
            accent: "#e9be62"
            horizontalPadding: Style.spacing.md
            verticalPadding: Style.spacing.xs
            onClicked: root.refresh()
          }
        }

        Column {
          visible: root.systems.length === 0
            && (!root.tracker || (!root.tracker.loading && root.tracker.hasLoaded))
          anchors.centerIn: parent
          width: Math.min(Style.space(430), parent.width - Style.spacing.xl * 2)
          spacing: Style.spacing.sm
          z: 3

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "\uf751"
            color: root.mapMuted
            font.family: Style.font.family
            font.pixelSize: Style.space(38)
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No NHC tropical systems"
            color: root.mapText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "The Atlantic, Eastern Pacific, and Central Pacific basins have no active cyclones or outlook areas. Hurricane Tracker will keep checking."
            color: root.mapMuted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }

        Column {
          visible: root.tracker && root.tracker.loading && !root.tracker.hasLoaded
          anchors.centerIn: parent
          width: Style.space(310)
          spacing: Style.spacing.sm
          z: 3

          Repeater {
            model: 3
            Rectangle {
              width: parent.width - index * Style.space(42)
              height: index === 0 ? Style.space(18) : Style.space(11)
              radius: height / 2
              color: Qt.rgba(root.mapText.r, root.mapText.g, root.mapText.b, 0.13 - index * 0.02)
            }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: Style.spacing.md
            text: "Checking the National Hurricane Center"
            color: root.mapMuted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }

        Rectangle {
          id: mapLegend
          visible: root.selectedSystem !== null
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.bottom: timeline.visible ? timeline.top : parent.bottom
          anchors.bottomMargin: Style.spacing.md
          width: legendRow.implicitWidth + Style.spacing.lg * 2
          height: Style.space(34)
          radius: 7
          color: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.90)
          border.width: 1
          border.color: Qt.rgba(root.mapGrid.r, root.mapGrid.g, root.mapGrid.b, 0.30)
          z: 4

          Row {
            id: legendRow
            anchors.centerIn: parent
            spacing: Style.spacing.md
            Row {
              spacing: Style.spacing.xs
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 8
                radius: 2
                color: root.selectedOutlook
                  ? Qt.rgba(Qt.color(root.systemColor(root.selectedOutlook)).r,
                    Qt.color(root.systemColor(root.selectedOutlook)).g,
                    Qt.color(root.systemColor(root.selectedOutlook)).b, 0.24)
                  : Qt.rgba(root.mapCone.r, root.mapCone.g, root.mapCone.b, 0.32)
                border.width: 1
                border.color: root.selectedOutlook ? root.systemColor(root.selectedOutlook) : root.mapCone
              }
              Text {
                text: root.selectedOutlook ? "Formation area" : "Forecast cone"
                color: root.mapMuted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
            Row {
              visible: root.selectedStorm !== null
              spacing: Style.spacing.xs
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 2
                color: root.mapTrack
              }
              Text {
                text: "Center track"
                color: root.mapMuted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Column {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.bottom: timeline.visible ? timeline.top : parent.bottom
          anchors.bottomMargin: Style.spacing.md
          spacing: 2
          z: 4

          Button {
            iconText: "\uf067"
            tooltipText: "Zoom in (+)"
            focusable: true
            foreground: root.mapText
            background: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.92)
            onClicked: stormMap.zoomIn()
          }
          Button {
            iconText: "\uf068"
            tooltipText: "Zoom out (-)"
            focusable: true
            foreground: root.mapText
            background: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.92)
            onClicked: stormMap.zoomOut()
          }
          Button {
            iconText: "\uf05b"
            tooltipText: "Fit selected system (F)"
            focusable: true
            foreground: root.mapText
            background: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.92)
            onClicked: stormMap.resetView()
          }
          Button {
            iconText: "\uf0ac"
            tooltipText: "Show the whole globe (G)"
            focusable: true
            foreground: root.mapText
            background: root.background
            onClicked: stormMap.showGlobe()
          }
        }

        Rectangle {
          id: timeline
          visible: root.selectedStorm && Array.isArray(root.selectedStorm.track)
            && root.selectedStorm.track.length > 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.timelineHeight
          color: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.95)
          z: 4

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Qt.rgba(root.mapGrid.r, root.mapGrid.g, root.mapGrid.b, 0.42)
          }

          ListView {
            id: timelineList
            anchors.fill: parent
            orientation: ListView.Horizontal
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.selectedStorm && Array.isArray(root.selectedStorm.track)
              ? root.selectedStorm.track : []

            delegate: Item {
              property var forecast: modelData
              width: Math.max(Style.space(126), Math.min(Style.space(162), timelineList.width / Math.max(1, Math.min(6, timelineList.count))))
              height: timelineList.height

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Style.space(18)
                height: 1
                color: Qt.rgba(root.mapTrack.r, root.mapTrack.g, root.mapTrack.b, 0.36)
              }
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(13)
                width: 11
                height: 11
                radius: 6
                color: Model.severityColor(forecast)
                border.width: 2
                border.color: root.mapDeepOcean
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(30)
                text: Model.forecastHourLabel(forecast)
                color: root.mapText
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(51)
                width: parent.width - Style.spacing.sm
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: Model.forecastTimeLabel(forecast)
                color: root.mapMuted
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(73)
                text: String(forecast.windMph || 0) + " mph"
                color: Model.severityColor(forecast)
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            QQC.ScrollBar.horizontal: QQC.ScrollBar {
              policy: timelineList.contentWidth > timelineList.width
                ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
            }
          }
        }
      }

      Rectangle {
        id: sidebar
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: root.sidebarWidth
        color: root.background
        z: 2

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: root.border
        }

        Item {
          id: listHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.space(56)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: "SYSTEMS"
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            font.letterSpacing: 0.8
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.systems.length) + " tracked"
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.border
          }
        }

        ListView {
          id: systemList
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: listHeader.bottom
          anchors.bottom: discussionPanel.visible ? discussionPanel.top : parent.bottom
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.regionalRows
          currentIndex: -1

          delegate: Rectangle {
            id: systemRow
            property var rowData: modelData
            property var system: rowData.kind === "system" ? rowData.system : null
            property bool isSelected: system && system.key === root.selectedKey
            property bool regionExpanded: rowData.kind === "region" && rowData.basin === root.expandedRegion
            readonly property color itemColor: system ? root.systemColor(system) : root.dim
            width: systemList.width
            height: rowData.kind === "region" ? Style.space(44)
              : (rowData.kind === "empty" ? Style.space(28) : Style.space(68))
            color: isSelected ? Style.selectedFillFor(root.foreground, root.accent)
              : (rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.border
              opacity: rowData.kind === "region" ? 0.44 : 0.62
            }

            Text {
              visible: rowData.kind === "region"
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: String(rowData.name || "REGION").toUpperCase()
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.7
            }

            Text {
              anchors.right: regionTarget.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              visible: rowData.kind === "region" && !systemRow.regionExpanded
              text: {
                var parts = []
                if (Number(rowData.activeCount || 0) > 0) parts.push(rowData.activeCount + " active")
                if (Number(rowData.outlookCount || 0) > 0) parts.push(rowData.outlookCount + " outlook")
                return parts.length > 0 ? parts.join(" · ") : "quiet"
              }
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              id: regionViewButton
              visible: rowData.kind === "region" && systemRow.regionExpanded
              anchors.right: regionTarget.left
              anchors.rightMargin: Style.spacing.xs
              anchors.verticalCenter: parent.verticalCenter
              text: "View all"
              iconText: "\uf05b"
              tooltipText: "Fit every system in " + String(rowData.name || "this region")
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontSize: Style.font.caption
              iconSize: Style.font.caption
              horizontalPadding: Style.spacing.md
              verticalPadding: Style.spacing.xs
              z: 2
              onClicked: root.viewRegion(rowData.basin)
              Accessible.name: "View all systems in " + String(rowData.name || "this region")
            }

            Text {
              id: regionTarget
              visible: rowData.kind === "region"
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: systemRow.regionExpanded ? "\uf078" : "\uf054"
              color: systemRow.regionExpanded ? root.foreground : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: rowData.kind === "empty"
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: "No current systems"
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              id: severityBadge
              visible: system !== null
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: width
              radius: system && system.kind === "storm" ? width / 2 : 8
              color: Qt.rgba(Qt.color(itemColor).r, Qt.color(itemColor).g,
                Qt.color(itemColor).b, root.lightTheme ? 0.20 : 0.18)
              border.width: isSelected ? 2 : 1
              border.color: itemColor

              Text {
                anchors.centerIn: parent
                text: system ? (system.kind === "storm" ? Model.severityCode(system)
                  : String(system.sevenDayChance || 0) + "%") : ""
                color: itemColor
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Column {
              visible: system !== null
              anchors.left: severityBadge.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              spacing: 3

              Text {
                width: parent.width
                text: system ? String(system.name || system.title || "Tropical system") : ""
                textFormat: Text.PlainText
                color: root.foreground
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                width: parent.width
                text: system ? Model.systemClassificationLabel(system) + " · " + Model.systemMetric(system) : ""
                textFormat: Text.PlainText
                color: root.dim
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              z: 1
              onClicked: {
                if (rowData.kind === "region") root.toggleRegion(rowData.basin)
                else if (system) root.selectSystem(system.key)
              }
            }

            Accessible.name: rowData.kind === "region" ? String(rowData.name || "Region") + " region, "
              + (regionExpanded ? "expanded" : "collapsed")
              : (system ? String(system.name || "Tropical system") + ", "
                + Model.systemClassificationLabel(system) + ", " + Model.systemMetric(system) : "No current systems")
            Accessible.role: rowData.kind === "region" ? Accessible.Button : Accessible.ListItem
          }

          QQC.ScrollBar.vertical: QQC.ScrollBar {
            policy: systemList.contentHeight > systemList.height
              ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
          }
        }

        Item {
          id: discussionPanel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          visible: root.selectedSystem && Model.discussionExcerpt(root.selectedSystem) !== ""
          height: visible ? Math.max(0, Math.min(
            sidebar.height * 0.36,
            Math.min(Style.space(300), Style.space(86)
              + Math.max(Style.space(68), Math.ceil(discussionText.implicitHeight))))) : 0
          clip: true

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: root.border
          }

          Text {
            id: discussionLabel
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.md
            text: root.selectedOutlook ? "TROPICAL WEATHER OUTLOOK" : "FORECAST DISCUSSION"
            color: root.dim
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.45
          }

          Flickable {
            id: discussionScroll
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.top: discussionLabel.bottom
            anchors.topMargin: Style.spacing.sm
            anchors.bottom: discussionActions.top
            anchors.bottomMargin: Style.spacing.sm
            contentWidth: width
            contentHeight: discussionText.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            clip: true

            Text {
              id: discussionText
              width: Math.max(0, discussionScroll.width - Style.spacing.md)
              text: root.selectedSystem ? Model.discussionExcerpt(root.selectedSystem) : ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
              lineHeight: 1.2
            }

            QQC.ScrollBar.vertical: QQC.ScrollBar {
              policy: discussionScroll.contentHeight > discussionScroll.height
                ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
            }
          }

          Row {
            id: discussionActions
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.bottom: discussionSafety.top
            anchors.bottomMargin: Style.spacing.sm
            spacing: Style.spacing.sm

            Button {
              visible: root.selectedStorm !== null
              text: "Advisory"
              iconText: "\uf35d"
              focusable: true
              bordered: true
              foreground: root.foreground
              accent: root.accent
              enabled: root.officialUrl(root.selectedStorm, "advisoryUrl") !== ""
              onClicked: root.openOfficial(root.selectedStorm, "advisoryUrl")
            }
            Button {
              text: root.selectedOutlook ? "Full outlook" : "Full discussion"
              iconText: "\uf35d"
              focusable: true
              bordered: true
              foreground: root.foreground
              accent: root.accent
              enabled: root.officialUrl(root.selectedSystem, "discussionUrl") !== ""
              onClicked: root.openOfficial(root.selectedSystem, "discussionUrl")
            }
          }

          Text {
            id: discussionSafety
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.md
            text: "Awareness only. Follow local alerts."
            textFormat: Text.PlainText
            color: root.dim
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
