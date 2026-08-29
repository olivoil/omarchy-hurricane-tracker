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
  property int clockTick: 0

  readonly property var tracker: shell ? shell.serviceFor("io.github.olivoil.omanado") : null
  readonly property var storms: tracker && Array.isArray(tracker.storms) ? tracker.storms : []
  readonly property var outlooks: tracker && Array.isArray(tracker.outlooks) ? tracker.outlooks : []
  readonly property var systems: Model.orderedSystems(storms, outlooks)
  readonly property var regionalRows: Model.regionalRows(storms, outlooks)
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

  function systemStatusLabel(system) {
    return system ? Model.systemClassificationLabel(system).toUpperCase() : ""
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (error) { payload = ({}) }
    if (payload.stormId) selectedKey = "storm:" + String(payload.stormId)
    if (payload.outlookId) selectedKey = "outlook:" + String(payload.outlookId)
    opened = true
    syncSelection()
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

  function syncSelection() {
    selectedKey = Model.selectedKeyAfterRefresh(systems, selectedKey)
    var rowIndex = rowIndexForKey(selectedKey)
    Qt.callLater(function() {
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

  function selectSystem(key) {
    if (!Model.systemByKey(systems, key)) return
    selectedKey = key
    var rowIndex = rowIndexForKey(key)
    if (rowIndex >= 0) systemList.positionViewAtIndex(rowIndex, ListView.Contain)
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
    function onStormsChanged() { root.syncSelection() }
    function onOutlooksChanged() { root.syncSelection() }
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

        Text {
          id: brandIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          text: "\uf751"
          color: root.storms.length > 0 ? Model.severityColor(root.storms[0])
            : (root.outlooks.length > 0 ? Model.outlookColor(root.outlooks[0]) : root.accent)
          font.family: Style.font.family
          font.pixelSize: Style.font.heading + 5
          renderType: Text.NativeRendering
        }

        Column {
          anchors.left: brandIcon.right
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          Text {
            text: "OMANADO"
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
          bottomInset: root.selectedStorm ? Style.space(116) : 0
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

        Rectangle {
          id: stormSummary
          visible: root.selectedSystem !== null
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.top: parent.top
          anchors.topMargin: Style.spacing.lg
          width: Math.min(Style.space(500), mapArea.width - Style.spacing.lg * 2)
          height: Style.space(124)
          radius: 9
          color: root.background
          border.width: 1
          border.color: root.border
          z: 4

          Text {
            id: stormName
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.md
            text: root.selectedSystem ? String(root.selectedSystem.name || root.selectedSystem.title || "Tropical system") : ""
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Rectangle {
            anchors.left: stormName.right
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: stormName.verticalCenter
            width: intensityText.implicitWidth + 14
            height: intensityText.implicitHeight + 6
            radius: height / 2
            color: root.selectedSystem
              ? Qt.rgba(Qt.color(root.systemColor(root.selectedSystem)).r,
                Qt.color(root.systemColor(root.selectedSystem)).g,
                Qt.color(root.systemColor(root.selectedSystem)).b, 0.18)
              : "transparent"
            border.width: 1
            border.color: root.selectedSystem ? root.systemColor(root.selectedSystem) : root.border

            Text {
              id: intensityText
              anchors.centerIn: parent
              text: root.systemStatusLabel(root.selectedSystem)
              textFormat: Text.PlainText
              color: root.selectedSystem ? root.systemColor(root.selectedSystem) : root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.lg
            text: {
              root.clockTick
              if (!root.selectedSystem) return ""
              if (root.selectedOutlook) return "NHC OUTLOOK · " + Model.humanAge(root.selectedOutlook.updatedAt)
              if (!root.selectedStorm) return ""
              var label = Model.advisoryLabel(root.selectedStorm)
              return Array.isArray(root.selectedStorm.dataWarnings) && root.selectedStorm.dataWarnings.length > 0
                ? "PARTIAL DATA · " + label : label
            }
            textFormat: Text.PlainText
            color: root.selectedStorm && Array.isArray(root.selectedStorm.dataWarnings)
              && root.selectedStorm.dataWarnings.length > 0 ? "#e9be62" : root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.md
            height: Style.space(47)
            spacing: Style.spacing.xl

            Column {
              width: Math.max(90, (parent.width - parent.spacing * 2) / 3)
              spacing: 2
              Text {
                text: root.selectedOutlook ? "2-DAY CHANCE" : "MAX WIND"
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: root.selectedOutlook ? String(root.selectedOutlook.twoDayChance || 0) + "%"
                  : Model.formatWind(root.selectedStorm)
                color: root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
            Column {
              width: Math.max(90, (parent.width - parent.spacing * 2) / 3)
              spacing: 2
              Text {
                text: root.selectedOutlook ? "7-DAY CHANCE" : "PRESSURE"
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: root.selectedOutlook ? String(root.selectedOutlook.sevenDayChance || 0) + "%"
                  : Model.formatPressure(root.selectedStorm)
                color: root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
            Column {
              width: Math.max(110, (parent.width - parent.spacing * 2) / 3)
              spacing: 2
              Text {
                text: root.selectedOutlook ? "REGION" : "MOVEMENT"
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: root.selectedOutlook ? String(root.selectedOutlook.basinLabel || "")
                  : Model.formatMovement(root.selectedStorm)
                color: root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
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
            text: "The Atlantic, Eastern Pacific, and Central Pacific basins have no active cyclones or outlook areas. Omanado will keep checking."
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
          height: Style.space(116)
          color: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.95)
          z: 4

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Qt.rgba(root.mapGrid.r, root.mapGrid.g, root.mapGrid.b, 0.42)
          }

          Text {
            id: timelineTitle
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.sm
            text: "NHC FORECAST"
            color: root.mapMuted
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.5
          }

          ListView {
            id: timelineList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: timelineTitle.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: Style.spacing.xs
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
                anchors.topMargin: Style.space(49)
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
                anchors.topMargin: Style.space(66)
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
          height: Style.space(64)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: "NHC REGIONS"
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            font.letterSpacing: 0.6
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.systems.length)
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.bold: true
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
          anchors.bottom: discussionPanel.top
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.regionalRows
          currentIndex: -1

          delegate: Rectangle {
            property var rowData: modelData
            property var system: rowData.kind === "system" ? rowData.system : null
            property bool isSelected: system && system.key === root.selectedKey
            readonly property color itemColor: system ? root.systemColor(system) : root.dim
            width: systemList.width
            height: rowData.kind === "region" ? Style.space(54)
              : (rowData.kind === "empty" ? Style.space(34) : Style.space(86))
            color: isSelected ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.border
              opacity: rowData.kind === "region" ? 1 : 0.62
            }

            Text {
              visible: rowData.kind === "region"
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: String(rowData.name || "REGION").toUpperCase()
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 0.45
            }

            Text {
              visible: rowData.kind === "region"
              anchors.right: regionTarget.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
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

            Text {
              id: regionTarget
              visible: rowData.kind === "region"
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf05b"
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: rowData.kind === "empty"
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.xl
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
              width: Style.space(38)
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
              anchors.right: chevron.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: 3

              Text {
                width: parent.width
                text: system ? String(system.name || system.title || "Tropical system") : ""
                textFormat: Text.PlainText
                color: root.foreground
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body + 1
                font.bold: true
              }
              Text {
                width: parent.width
                text: system ? Model.systemClassificationLabel(system) : ""
                textFormat: Text.PlainText
                color: itemColor
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                width: parent.width
                text: system ? Model.systemMetric(system) : ""
                textFormat: Text.PlainText
                color: root.dim
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              id: chevron
              visible: system !== null
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf054"
              color: isSelected ? root.foreground : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (rowData.kind === "region") stormMap.fitRegion(rowData.basin)
                else if (system) root.selectSystem(system.key)
              }
            }

            Accessible.name: rowData.kind === "region" ? String(rowData.name || "Region") + " region"
              : (system ? String(system.name || "Tropical system") + ", "
                + Model.systemClassificationLabel(system) + ", " + Model.systemMetric(system) : "No current systems")
            Accessible.role: Accessible.ListItem
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
          anchors.bottom: sourceFooter.top
          height: root.selectedSystem && Model.discussionExcerpt(root.selectedSystem) !== ""
            ? Style.space(214) : 0
          visible: height > 0
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

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.top: discussionLabel.bottom
            anchors.topMargin: Style.spacing.sm
            text: root.selectedSystem ? Model.discussionExcerpt(root.selectedSystem) : ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: 6
            elide: Text.ElideRight
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.2
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.md
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
        }

        Item {
          id: sourceFooter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(132)

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: root.border
          }

          Text {
            id: sourceLabel
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.md
            text: "SOURCE · NOAA NATIONAL HURRICANE CENTER"
            textFormat: Text.PlainText
            color: root.dim
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.3
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.top: sourceLabel.bottom
            anchors.topMargin: Style.spacing.sm
            text: "ALERTS · " + (root.tracker ? root.tracker.alertStatus : "Off")
            color: root.tracker && root.tracker.alertsEnabled ? root.accent : root.dim
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.md
            wrapMode: Text.WordWrap
            text: "For awareness only. Guidance can change quickly, and hazards can extend beyond tracks, cones, or formation areas. Follow local emergency guidance."
            textFormat: Text.PlainText
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            lineHeight: 1.18
          }
        }
      }
    }
  }
}
