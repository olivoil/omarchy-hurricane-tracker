import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  // Injected by the Omarchy shell.
  property var shell: null
  property var settings: ({})

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
  property var watchPlaces: []
  property bool watchPlacesLoaded: false
  property string watchPlacesError: ""
  property bool loading: false
  property bool hasLoaded: false
  property bool pendingRefresh: false
  property int consecutiveFailures: 0
  property string processOutput: ""
  property string processError: ""
  property var alertBaseline: ({})
  property bool alertsArmed: false
  property string appliedAlertConfig: ""
  property var placeAlertBaseline: ({})
  property bool placeAlertsArmed: false
  property string appliedPlaceAlertConfig: ""
  property var pendingNotification: null
  property string watchProcessOutput: ""
  property string watchProcessError: ""
  property string watchProcessOperation: ""
  property string pendingWatchPayload: ""

  readonly property string backendPath: Qt.resolvedUrl("bin/omanado-data").toString().replace(/^file:\/\//, "")
  readonly property string notificationIconPath: Qt.resolvedUrl("assets/hurricane-tracker.svg").toString().replace(/^file:\/\//, "")
  readonly property string status: String(payload && payload.status || "loading")
  readonly property bool stale: payload && payload.stale === true
  readonly property string error: String(payload && payload.error || "")
  readonly property string fetchedAt: String(payload && payload.fetchedAt || "")
  readonly property int activeCount: Array.isArray(storms) ? storms.length : 0
  readonly property int outlookCount: Array.isArray(outlooks) ? outlooks.length : 0
  readonly property int trackingCount: activeCount + outlookCount
  readonly property int watchPlaceCount: Array.isArray(watchPlaces) ? watchPlaces.length : 0
  readonly property int refreshMinutes: Math.max(5, Math.min(60, Number(setting("refreshMinutes", 15)) || 15))
  readonly property int retryMultiplier: Math.min(4, Math.pow(2, Math.min(consecutiveFailures, 2)))
  readonly property bool settingsReady: settings && Object.keys(settings).length > 0
  readonly property string alertRegion: settingsReady ? String(setting("alertRegion", "Off")) : "Off"
  readonly property string formationThreshold: String(setting("formationThreshold", "Medium (40%)"))
  readonly property bool notifyNamedStorms: setting("notifyNamedStorms", true) === true
  readonly property string alertConfigKey: alertRegion + "|" + formationThreshold + "|" + notifyNamedStorms
  readonly property string placeAlertConfigKey: formationThreshold + "|" + JSON.stringify(watchPlaces)
  readonly property bool alertsEnabled: Model.alertRegionCode(alertRegion) !== ""
  readonly property bool placeAlertsEnabled: watchPlacesLoaded && watchPlaceCount > 0
  readonly property string alertStatus: alertsEnabled
    ? alertRegion + " · " + Model.alertThresholdValue(formationThreshold) + "%+"
    : "Off"

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

  function applyWatchConfig(raw, assignValues) {
    if (typeof raw !== "string" || raw.length === 0 || raw.length > 64 * 1024) return false
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      return false
    }
    if (!parsed || parsed.schemaVersion !== 1 || !Array.isArray(parsed.places)
        || parsed.places.length > 12) return false
    var normalized = []
    var identifiers = ({})
    for (var i = 0; i < parsed.places.length; i++) {
      var place = Model.normalizeWatchPlace(parsed.places[i])
      if (!place || identifiers[place.id]) continue
      identifiers[place.id] = true
      normalized.push(place)
    }
    if (assignValues !== false) {
      watchPlaces = normalized
      watchPlacesLoaded = true
      watchPlacesError = ""
    }
    return true
  }

  function runWatchProcess(operation, payload) {
    watchProcessOperation = operation
    watchProcessOutput = ""
    watchProcessError = ""
    watchProcess.command = operation === "save"
      ? [backendPath, "watch-save", payload]
      : [backendPath, "watch-load"]
    watchProcess.running = true
  }

  function loadWatchPlaces() {
    if (watchProcess.running) return
    runWatchProcess("load", "")
  }

  function persistWatchPlaces() {
    if (!watchPlacesLoaded) return
    var payload = JSON.stringify({ schemaVersion: 1, places: watchPlaces })
    if (watchProcess.running) {
      pendingWatchPayload = payload
      return
    }
    runWatchProcess("save", payload)
  }

  function upsertWatchPlace(value) {
    var requested = ({})
    if (value) for (var key in value) requested[key] = value[key]
    if (!requested.id) requested.id = "place-" + Date.now().toString(36)
      + "-" + Math.floor(Math.random() * 1679616).toString(36)
    var place = Model.normalizeWatchPlace(requested)
    if (!place || !watchPlacesLoaded) return ""
    var next = []
    var replaced = false
    for (var i = 0; i < watchPlaces.length; i++) {
      if (watchPlaces[i].id === place.id) {
        next.push(place)
        replaced = true
      } else {
        next.push(watchPlaces[i])
      }
    }
    if (!replaced) {
      if (next.length >= 12) return ""
      next.push(place)
    }
    watchPlaces = next
    persistWatchPlaces()
    return place.id
  }

  function removeWatchPlace(identifier) {
    var id = String(identifier || "")
    if (!id || !watchPlacesLoaded) return
    var next = []
    for (var i = 0; i < watchPlaces.length; i++)
      if (watchPlaces[i].id !== id) next.push(watchPlaces[i])
    if (next.length === watchPlaces.length) return
    watchPlaces = next
    persistWatchPlaces()
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

  function currentPlaceAlertSnapshot() {
    return Model.watchAlertSnapshot(storms, outlooks, watchPlaces, formationThreshold)
  }

  function armAlertsQuietly() {
    alertBaseline = currentAlertSnapshot()
    alertsArmed = alertsEnabled && hasLoaded && !stale && status === "fresh"
    appliedAlertConfig = alertConfigKey
  }

  function armPlaceAlertsQuietly() {
    placeAlertBaseline = currentPlaceAlertSnapshot()
    placeAlertsArmed = placeAlertsEnabled && hasLoaded && !stale && status === "fresh"
    appliedPlaceAlertConfig = placeAlertConfigKey
  }

  function evaluateAlerts() {
    if (!settingsReady || !hasLoaded || stale || status !== "fresh") {
      alertBaseline = ({})
      alertsArmed = false
      appliedAlertConfig = alertConfigKey
      placeAlertBaseline = ({})
      placeAlertsArmed = false
      appliedPlaceAlertConfig = placeAlertConfigKey
      return
    }
    var events = []
    if (alertsEnabled) {
      var current = currentAlertSnapshot()
      if (!alertsArmed || appliedAlertConfig !== alertConfigKey) {
        alertBaseline = current
        alertsArmed = true
      } else {
        events = events.concat(Model.alertEvents(alertBaseline, current))
        alertBaseline = current
      }
      appliedAlertConfig = alertConfigKey
    } else {
      alertBaseline = ({})
      alertsArmed = false
      appliedAlertConfig = alertConfigKey
    }

    if (placeAlertsEnabled) {
      var placeCurrent = currentPlaceAlertSnapshot()
      if (!placeAlertsArmed || appliedPlaceAlertConfig !== placeAlertConfigKey) {
        placeAlertBaseline = placeCurrent
        placeAlertsArmed = true
      } else {
        events = events.concat(Model.watchAlertEvents(placeAlertBaseline, placeCurrent))
        placeAlertBaseline = placeCurrent
      }
      appliedPlaceAlertConfig = placeAlertConfigKey
    } else {
      placeAlertBaseline = ({})
      placeAlertsArmed = false
      appliedPlaceAlertConfig = placeAlertConfigKey
    }
    if (events.length > 0) notifyEvents(events)
  }

  function forecastLeadLabel(hours) {
    var value = Math.max(0, Math.round(Number(hours || 0)))
    if (value === 0) return ""
    if (value < 36) return " in about " + value + " hours"
    return " in about " + Math.max(2, Math.round(value / 24)) + " days"
  }

  function notifyEvents(events) {
    var headline = ""
    var description = ""
    if (events.length === 1) {
      var event = events[0]
      if (event.scope === "place" && event.kind === "storm"
          && event.attentionLevel === "urgent") {
        headline = event.name + " is approaching " + event.placeName
        description = "The cyclone is within the " + Math.round(Number(event.radiusKm || 0))
          + " km awareness area and the NHC forecast continues materially closer"
          + forecastLeadLabel(event.forecastHour) + ". Awareness only, not a local warning."
      } else if (event.scope === "place" && event.kind === "storm") {
        headline = event.name + " may pass near " + event.placeName
        description = "The NHC forecast cone or center track may come within the "
          + Math.round(Number(event.radiusKm || 0)) + " km awareness area"
          + forecastLeadLabel(event.forecastHour) + ". Awareness only, not a local warning."
      } else if (event.scope === "place") {
        headline = "Formation heads-up for " + event.placeName
        description = "An NHC 7-day formation area that may approach the "
          + Math.round(Number(event.radiusKm || 0)) + " km awareness area has reached "
          + Math.round(Number(event.chance || 0))
          + "% formation chance. No local track is available yet."
      } else {
        var region = Model.regionName(event.basin)
        if (event.kind === "storm") {
          headline = "New NHC cyclone in " + region
          description = event.label + " " + event.name + " is now under active NHC advisories."
        } else {
          headline = "Development chance in " + region
          description = event.name + " has reached " + Math.round(Number(event.chance || 0))
            + "% formation chance within 7 days."
        }
      }
    } else {
      headline = events.length + " tropical updates"
      var names = []
      for (var i = 0; i < Math.min(3, events.length); i++) {
        var item = events[i]
        names.push(item.scope === "place" ? item.name + " near " + item.placeName : item.name)
      }
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

  Process {
    id: watchProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.watchProcessOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.watchProcessError = text
    }
    onExited: function(exitCode) {
      var shouldAssign = root.watchProcessOperation === "load" || root.pendingWatchPayload === ""
      var accepted = exitCode === 0 && root.applyWatchConfig(root.watchProcessOutput, shouldAssign)
      if (!accepted) {
        if (root.watchProcessOperation === "load") {
          root.watchPlaces = []
          root.watchPlacesLoaded = true
        }
        root.watchPlacesError = root.watchProcessOperation === "save"
          ? "Watch places could not be saved. They remain active for this session."
          : "Saved watch places could not be loaded."
      }
      root.watchProcessOutput = ""
      root.watchProcessOperation = ""
      if (root.pendingWatchPayload !== "") {
        var nextPayload = root.pendingWatchPayload
        root.pendingWatchPayload = ""
        Qt.callLater(function() { root.runWatchProcess("save", nextPayload) })
      }
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
  onPlaceAlertConfigKeyChanged: armPlaceAlertsQuietly()
  Component.onCompleted: loadWatchPlaces()
}
