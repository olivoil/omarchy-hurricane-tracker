import QtQuick
import Quickshell
import Quickshell.Io
import "Launcher.js" as Launcher
import "Model.js" as Model

Item {
  id: root

  // Injected by the Omarchy shell.
  property var shell: null
  property var manifest: null
  property var settings: ({})

  // Omarchy does not currently have a manifest field for launcher entries, so
  // the service installs one while the plugin is enabled. A pre-existing file
  // without our marker is always left alone.
  readonly property string launcherDataHome: Launcher.dataHome(
    Quickshell.env("XDG_DATA_HOME"), Quickshell.env("HOME"))
  readonly property string launcherRuntimeHome: Launcher.runtimeHome(
    Quickshell.env("XDG_RUNTIME_DIR"), Quickshell.env("XDG_CACHE_HOME"),
    Quickshell.env("HOME"))
  readonly property string launcherEntryPath: launcherDataHome
    + "/applications/io.github.olivoil.hurricane-tracker.desktop"
  readonly property string launcherIntentPath: launcherRuntimeHome
    + "/hurricane-tracker-launcher.intent"
  readonly property string launcherEntryMarker: "X-Hurricane-Tracker-Managed=true"
  property string launcherSourceDir: ""
  property bool launcherEntryInstalled: false

  FileView {
    id: launcherIntentFile
    path: root.launcherIntentPath
    blockWrites: true
    atomicWrites: true
    watchChanges: false
    printErrors: false
  }

  property var payload: ({
    schemaVersion: 2,
    status: "loading",
    stale: false,
    fetchedAt: "",
    checkedAt: "",
    source: ({
      name: "NOAA National Hurricane Center",
      url: "https://www.nhc.noaa.gov/",
      coverage: "Atlantic, Eastern Pacific, and Central Pacific basins"
    }),
    error: "",
    storms: [],
    outlooks: [],
    regions: []
  })
  property var storms: []
  property var outlooks: []
  property var regions: []
  property bool loading: false
  property bool hasLoaded: false
  property bool pendingRefresh: false
  property int consecutiveFailures: 0
  property string processOutput: ""
  property string processError: ""
  property var alertBaseline: ({})
  property bool alertsArmed: false
  property string appliedAlertConfig: ""
  property var pendingNotification: null

  readonly property string backendPath: Qt.resolvedUrl("bin/hurricane-tracker-data").toString().replace(/^file:\/\//, "")
  readonly property string notificationIconPath: Qt.resolvedUrl("assets/hurricane-tracker.svg").toString().replace(/^file:\/\//, "")
  readonly property string status: String(payload && payload.status || "loading")
  readonly property bool stale: payload && payload.stale === true
  readonly property string error: String(payload && payload.error || "")
  readonly property string fetchedAt: String(payload && payload.fetchedAt || "")
  readonly property int activeCount: Array.isArray(storms) ? storms.length : 0
  readonly property int outlookCount: Array.isArray(outlooks) ? outlooks.length : 0
  readonly property int trackingCount: activeCount + outlookCount
  readonly property int refreshMinutes: Math.max(5, Math.min(60, Number(setting("refreshMinutes", 15)) || 15))
  readonly property int retryMultiplier: Math.min(4, Math.pow(2, Math.min(consecutiveFailures, 2)))
  readonly property bool settingsReady: settings && Object.keys(settings).length > 0
  readonly property string alertRegion: settingsReady ? String(setting("alertRegion", "Off")) : "Off"
  readonly property string formationThreshold: String(setting("formationThreshold", "Medium (40%)"))
  readonly property bool notifyNamedStorms: setting("notifyNamedStorms", true) === true
  readonly property string alertConfigKey: alertRegion + "|" + formationThreshold + "|" + notifyNamedStorms
  readonly property bool alertsEnabled: Model.alertRegionCode(alertRegion) !== ""
  readonly property string alertStatus: alertsEnabled
    ? alertRegion + " · " + Model.alertThresholdValue(formationThreshold) + "%+"
    : "Off"

  function reconcileLauncherEntry(intent) {
    launcherIntentFile.setText(intent + "\n")
    Quickshell.execDetached([
      "sh", "-c", Launcher.launcherEntryScript, "sh",
      launcherIntentPath,
      launcherSourceDir + "/hurricane-tracker.desktop",
      launcherEntryPath,
      launcherEntryMarker,
      launcherSourceDir + "/assets/hurricane-tracker.svg"
    ])
  }

  // The shell injects manifest after createObject(), so source paths are
  // resolved when that property arrives rather than in Component.onCompleted.
  onManifestChanged: {
    var dir = manifest && manifest.__sourceDir
    if (launcherEntryInstalled || !dir) return
    launcherSourceDir = dir
    launcherEntryInstalled = true
    reconcileLauncherEntry("install")
  }

  // Disabling and removing a plugin both destroy its service. Delete the
  // launcher only when it is still the entry managed by this plugin.
  Component.onDestruction: {
    if (!launcherEntryInstalled) return
    reconcileLauncherEntry("remove")
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (fetchProcess.running) {
      pendingRefresh = true
      return
    }
    loading = true
    processOutput = ""
    processError = ""
    fetchProcess.command = [backendPath, "fetch"]
    fetchProcess.running = true
  }

  function applyPayload(raw) {
    if (typeof raw !== "string" || raw.length === 0 || raw.length > 8 * 1024 * 1024) return false
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      return false
    }
    if (!parsed || parsed.schemaVersion !== 2 || !Array.isArray(parsed.storms)
        || parsed.storms.length > 20 || !Array.isArray(parsed.outlooks)
        || parsed.outlooks.length > 24 || !Array.isArray(parsed.regions)) return false
    payload = parsed
    storms = parsed.storms
    outlooks = parsed.outlooks
    regions = parsed.regions
    hasLoaded = true
    evaluateAlerts()
    return true
  }

  function currentAlertSnapshot() {
    return Model.alertSnapshot(storms, outlooks, alertRegion, formationThreshold, notifyNamedStorms)
  }

  function armAlertsQuietly() {
    alertBaseline = currentAlertSnapshot()
    alertsArmed = alertsEnabled
    appliedAlertConfig = alertConfigKey
  }

  function evaluateAlerts() {
    if (!settingsReady || !alertsEnabled || stale || status !== "fresh") {
      alertBaseline = ({})
      alertsArmed = false
      appliedAlertConfig = alertConfigKey
      return
    }
    var current = currentAlertSnapshot()
    if (!alertsArmed || appliedAlertConfig !== alertConfigKey) {
      alertBaseline = current
      alertsArmed = true
      appliedAlertConfig = alertConfigKey
      return
    }
    var events = Model.alertEvents(alertBaseline, current)
    alertBaseline = current
    if (events.length > 0) notifyEvents(events)
  }

  function notifyEvents(events) {
    var headline = ""
    var description = ""
    if (events.length === 1) {
      var event = events[0]
      var region = Model.regionName(event.basin)
      if (event.kind === "storm") {
        headline = "New NHC cyclone in " + region
        description = event.label + " " + event.name + " is now under active NHC advisories."
      } else {
        headline = "Development chance in " + region
        description = event.name + " has reached " + Math.round(Number(event.chance || 0))
          + "% formation chance within 7 days."
      }
    } else {
      headline = events.length + " tropical updates in " + alertRegion
      var names = []
      for (var i = 0; i < Math.min(3, events.length); i++) names.push(events[i].name)
      description = names.join(", ") + (events.length > 3 ? " and more" : "")
    }
    if (!headline || !description || headline.charAt(0) === "-" || description.charAt(0) === "-") return
    var notification = { headline: headline, description: description }
    if (notifyProcess.running) {
      pendingNotification = notification
      return
    }
    sendNotification(notification)
  }

  function sendNotification(notification) {
    notifyProcess.command = [
      "omarchy-notification-send",
      "--app-name", "Hurricane Tracker",
      "-i", notificationIconPath,
      "-u", "normal",
      notification.headline,
      notification.description
    ]
    notifyProcess.running = true
  }

  Process {
    id: fetchProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.processOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.processError = text
    }
    onExited: function(exitCode) {
      var accepted = root.applyPayload(root.processOutput)
      root.processOutput = ""
      root.loading = false
      root.consecutiveFailures = accepted && root.status === "fresh"
        ? 0 : Math.min(6, root.consecutiveFailures + 1)
      if (!accepted && !root.hasLoaded) {
        root.payload = {
          schemaVersion: 2,
          status: "error",
          stale: false,
          fetchedAt: "",
          checkedAt: "",
          source: root.payload.source,
          error: "Storm data could not be read. Try again shortly.",
          storms: [],
          outlooks: [],
          regions: []
        }
      }
      if (root.pendingRefresh) {
        root.pendingRefresh = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: notifyProcess
    onExited: {
      if (!root.pendingNotification) return
      var next = root.pendingNotification
      root.pendingNotification = null
      Qt.callLater(function() { root.sendNotification(next) })
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000 * root.retryMultiplier
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onAlertConfigKeyChanged: {
    if (!settingsReady) return
    armAlertsQuietly()
  }
}
