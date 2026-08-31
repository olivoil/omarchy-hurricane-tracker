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
  property var placeSearchResults: []
  property bool placeSearchLoading: false
  property string placeSearchError: ""
  property string requestedPlaceSearchQuery: ""
  property string activePlaceSearchQuery: ""
  property string pendingPlaceSearchQuery: ""
  property string placeSearchProcessOutput: ""
  property string placeSearchProcessError: ""
  property var reverseGeocodeResult: null
  property bool reverseGeocodeLoading: false
  property string reverseGeocodeError: ""
  property string requestedReverseGeocodeKey: ""
  property string activeReverseGeocodeKey: ""
  property var pendingReverseCoordinate: null
  property double lastReverseGeocodeStartedAt: 0
  property string reverseGeocodeProcessOutput: ""
  property string reverseGeocodeProcessError: ""
  property var reverseGeocodeCache: ({})
  property var reverseGeocodeCacheKeys: []

  readonly property string backendPath: Qt.resolvedUrl("bin/hurricane-tracker-data").toString().replace(/^file:\/\//, "")
  readonly property string notificationIconPath: Qt.resolvedUrl("assets/hurricane-tracker.svg").toString().replace(/^file:\/\//, "")
  readonly property string status: String(payload && payload.status || "loading")
  readonly property bool stale: payload && payload.stale === true
  readonly property string error: String(payload && payload.error || "")
  readonly property string fetchedAt: String(payload && payload.fetchedAt || "")
  readonly property int activeCount: Array.isArray(storms) ? storms.length : 0
  readonly property int outlookCount: Array.isArray(outlooks) ? outlooks.length : 0
  readonly property int trackingCount: activeCount + outlookCount
  readonly property var incompleteOutlookBasins: payload
    && Array.isArray(payload.incompleteOutlookBasins) ? payload.incompleteOutlookBasins : []
  readonly property bool outlookDataComplete: incompleteOutlookBasins.length === 0
  readonly property var incompleteForecastSystemKeys:
    Model.incompleteForecastSystemKeys(storms)
  readonly property int watchPlaceCount: Array.isArray(watchPlaces) ? watchPlaces.length : 0
  readonly property int refreshMinutes: Math.max(5, Math.min(60, Number(setting("refreshMinutes", 15)) || 15))
  readonly property int retryMultiplier: Math.min(4, Math.pow(2, Math.min(consecutiveFailures, 2)))
  readonly property bool settingsReady: settings && Object.keys(settings).length > 0
  readonly property string alertRegion: settingsReady ? String(setting("alertRegion", "Off")) : "Off"
  readonly property string formationThreshold: String(setting("formationThreshold", "Medium (40%)"))
  readonly property bool notifyNamedStorms: setting("notifyNamedStorms", true) === true
  readonly property bool onlinePlaceSearchEnabled: setting("onlinePlaceSearch", true) === true
  readonly property bool useImperial:
    Qt.locale().measurementSystem !== Locale.MetricSystem
  readonly property string alertConfigKey: alertRegion + "|" + formationThreshold + "|" + notifyNamedStorms
  readonly property string placeAlertConfigKey: formationThreshold + "|" + JSON.stringify(watchPlaces)
  readonly property bool alertsEnabled: Model.alertRegionCode(alertRegion) !== ""
  readonly property bool placeAlertsEnabled: watchPlacesLoaded && watchPlaceCount > 0
  readonly property var watchPlaceSummaries: Model.watchPlaceSummaries(
    storms, outlooks, watchPlaces, formationThreshold, useImperial,
    ({
      snapshot: placeAlertsArmed ? placeAlertBaseline : null,
      incompleteOutlookBasins: incompleteOutlookBasins,
      incompleteSystemKeys: incompleteForecastSystemKeys
    }))
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

  function normalizedPlaceSearchQuery(value) {
    return String(value || "").replace(/\s+/g, " ").trim().slice(0, 120)
  }

  function safePlaceSearchText(value, maximum, required) {
    if (typeof value !== "string" || value.length > maximum
        || /[\x00-\x1f\x7f<>]/.test(value)) return null
    var normalized = value.replace(/\s+/g, " ").trim()
    return required && normalized === "" ? null : normalized
  }

  function applyPlaceSearch(raw, expectedQuery) {
    if (typeof raw !== "string" || raw.length === 0 || raw.length > 64 * 1024) return false
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      return false
    }
    var expected = normalizedPlaceSearchQuery(expectedQuery)
    if (!parsed || parsed.schemaVersion !== 1
        || parsed.provider !== "open-meteo-geonames"
        || normalizedPlaceSearchQuery(parsed.query) !== expected
        || !Array.isArray(parsed.results) || parsed.results.length > 8) return false

    var normalized = []
    var identifiers = ({})
    for (var i = 0; i < parsed.results.length; i++) {
      var row = parsed.results[i]
      if (!row || typeof row !== "object") return false
      var id = safePlaceSearchText(row.id, 80, true)
      var name = safePlaceSearchText(row.name, 256, true)
      var context = safePlaceSearchText(row.context, 768, false)
      var kind = safePlaceSearchText(row.kind, 32, true)
      var latitude = Number(row.latitude)
      var longitude = Number(row.longitude)
      if (id === null || name === null || context === null || kind === null
          || identifiers[id]
          || !Number.isFinite(latitude) || !Number.isFinite(longitude)
          || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180)
        return false
      identifiers[id] = true
      normalized.push({
        id: id,
        name: name,
        context: context,
        kind: kind,
        latitude: latitude,
        longitude: longitude
      })
    }
    placeSearchResults = normalized
    placeSearchError = ""
    return true
  }

  function runPlaceSearch(query) {
    var normalized = normalizedPlaceSearchQuery(query)
    if (!onlinePlaceSearchEnabled || normalized.length < 2 || placeSearchProcess.running) return
    activePlaceSearchQuery = normalized
    placeSearchProcessOutput = ""
    placeSearchProcessError = ""
    placeSearchLoading = requestedPlaceSearchQuery === normalized
    placeSearchProcess.command = [backendPath, "place-search", normalized]
    placeSearchProcess.running = true
  }

  function searchPlaces(value) {
    var query = normalizedPlaceSearchQuery(value)
    requestedPlaceSearchQuery = query
    placeSearchError = ""
    if (!onlinePlaceSearchEnabled) {
      pendingPlaceSearchQuery = ""
      placeSearchResults = []
      placeSearchLoading = false
      placeSearchError = "Online place search is off. You can still click the map."
      return
    }
    if (query.length < 2) {
      pendingPlaceSearchQuery = ""
      placeSearchResults = []
      placeSearchLoading = false
      return
    }
    placeSearchLoading = true
    if (placeSearchProcess.running) {
      pendingPlaceSearchQuery = activePlaceSearchQuery === query ? "" : query
      return
    }
    runPlaceSearch(query)
  }

  function clearPlaceSearch() {
    requestedPlaceSearchQuery = ""
    pendingPlaceSearchQuery = ""
    placeSearchResults = []
    placeSearchLoading = false
    placeSearchError = ""
  }

  function reverseCoordinate(latitude, longitude) {
    var latitudeValue = Number(latitude)
    var longitudeValue = Number(longitude)
    if (!Number.isFinite(latitudeValue) || !Number.isFinite(longitudeValue)
        || latitudeValue < -90 || latitudeValue > 90
        || longitudeValue < -180 || longitudeValue > 180) return null
    return {
      latitude: latitudeValue,
      longitude: longitudeValue,
      key: latitudeValue.toFixed(5) + "," + longitudeValue.toFixed(5)
    }
  }

  function applyReverseGeocode(raw, expectedKey) {
    if (typeof raw !== "string" || raw.length === 0 || raw.length > 64 * 1024) return false
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      return false
    }
    var coordinate = reverseCoordinate(parsed && parsed.latitude, parsed && parsed.longitude)
    var name = parsed ? safePlaceSearchText(parsed.name, 256, true) : null
    var context = parsed ? safePlaceSearchText(parsed.context, 768, false) : null
    if (!parsed || parsed.schemaVersion !== 1
        || parsed.provider !== "nominatim-openstreetmap"
        || !coordinate || coordinate.key !== expectedKey
        || name === null || context === null) return false
    reverseGeocodeResult = {
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      name: name,
      context: context
    }
    var cache = ({})
    for (var cacheKey in reverseGeocodeCache) cache[cacheKey] = reverseGeocodeCache[cacheKey]
    var keys = reverseGeocodeCacheKeys.slice()
    if (!(coordinate.key in cache)) keys.push(coordinate.key)
    cache[coordinate.key] = reverseGeocodeResult
    while (keys.length > 32) delete cache[keys.shift()]
    reverseGeocodeCache = cache
    reverseGeocodeCacheKeys = keys
    reverseGeocodeError = ""
    return true
  }

  function scheduleReverseGeocode() {
    if (!pendingReverseCoordinate) return
    var elapsed = Date.now() - lastReverseGeocodeStartedAt
    reverseGeocodeDebounce.interval = Math.max(350, 1100 - elapsed)
    reverseGeocodeDebounce.restart()
  }

  function runReverseGeocode(coordinate) {
    if (!coordinate || !onlinePlaceSearchEnabled || reverseGeocodeProcess.running) return
    activeReverseGeocodeKey = coordinate.key
    reverseGeocodeProcessOutput = ""
    reverseGeocodeProcessError = ""
    reverseGeocodeLoading = requestedReverseGeocodeKey === coordinate.key
    lastReverseGeocodeStartedAt = Date.now()
    reverseGeocodeProcess.command = [
      backendPath,
      "place-reverse",
      coordinate.latitude.toFixed(5),
      coordinate.longitude.toFixed(5)
    ]
    reverseGeocodeProcess.running = true
  }

  function reverseGeocode(latitude, longitude) {
    var coordinate = reverseCoordinate(latitude, longitude)
    if (!coordinate) return
    requestedReverseGeocodeKey = coordinate.key
    reverseGeocodeError = ""
    if (coordinate.key in reverseGeocodeCache) {
      pendingReverseCoordinate = null
      reverseGeocodeResult = reverseGeocodeCache[coordinate.key]
      reverseGeocodeLoading = false
      return
    }
    reverseGeocodeResult = null
    if (!onlinePlaceSearchEnabled) {
      pendingReverseCoordinate = null
      reverseGeocodeLoading = false
      return
    }
    pendingReverseCoordinate = coordinate
    reverseGeocodeLoading = true
    scheduleReverseGeocode()
  }

  function clearReverseGeocode() {
    reverseGeocodeDebounce.stop()
    requestedReverseGeocodeKey = ""
    pendingReverseCoordinate = null
    reverseGeocodeResult = null
    reverseGeocodeLoading = false
    reverseGeocodeError = ""
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
    var incomplete = parsed.incompleteOutlookBasins
    if (incomplete === undefined) incomplete = []
    if (!Array.isArray(incomplete) || incomplete.length > 3) return false
    var incompleteSeen = ({})
    for (var i = 0; i < incomplete.length; i++) {
      var basin = incomplete[i]
      if (typeof basin !== "string" || !/^(al|ep|cp)$/.test(basin)
          || incompleteSeen[basin]) return false
      incompleteSeen[basin] = true
    }
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
    if (!settingsReady || !hasLoaded) {
      alertBaseline = ({})
      alertsArmed = false
      appliedAlertConfig = alertConfigKey
      placeAlertBaseline = ({})
      placeAlertsArmed = false
      appliedPlaceAlertConfig = placeAlertConfigKey
      return
    }
    // A failed refresh must not turn the next fresh payload into a new quiet
    // baseline. Retain the last fresh comparison until the feed recovers.
    if (stale || status !== "fresh") return
    var events = []
    var incompleteForecastKeys = root.incompleteForecastSystemKeys
    if (alertsEnabled) {
      var current = currentAlertSnapshot()
      if (!alertsArmed || appliedAlertConfig !== alertConfigKey) {
        alertBaseline = current
        alertsArmed = true
      } else {
        var stableAlerts = Model.stabilizedAlertSnapshots(
          alertBaseline, current, incompleteOutlookBasins, [])
        events = events.concat(Model.alertEvents(stableAlerts.before, stableAlerts.current))
        alertBaseline = stableAlerts.current
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
        var stablePlaceAlerts = Model.stabilizedAlertSnapshots(
          placeAlertBaseline, placeCurrent, incompleteOutlookBasins,
          incompleteForecastKeys)
        events = events.concat(Model.watchAlertEvents(
          stablePlaceAlerts.before, stablePlaceAlerts.current))
        placeAlertBaseline = stablePlaceAlerts.current
      }
      appliedPlaceAlertConfig = placeAlertConfigKey
    } else {
      placeAlertBaseline = ({})
      placeAlertsArmed = false
      appliedPlaceAlertConfig = placeAlertConfigKey
    }
    events = Model.coalesceAlertEvents(events)
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
        description = "The cyclone is within the "
          + Model.formatWatchRadius(event.radiusKm, useImperial)
          + " awareness area and the NHC forecast continues materially closer"
          + forecastLeadLabel(Model.watchForecastLeadHours(event))
          + ". Awareness only, not a local warning."
      } else if (event.scope === "place" && event.kind === "storm") {
        headline = event.name + " may pass near " + event.placeName
        description = "The NHC forecast cone or center track may come within the "
          + Model.formatWatchRadius(event.radiusKm, useImperial) + " awareness area"
          + forecastLeadLabel(Model.watchForecastLeadHours(event))
          + ". Awareness only, not a local warning."
      } else if (event.scope === "place") {
        headline = "Formation heads-up for " + event.placeName
        description = "An NHC 7-day formation area that may approach the "
          + Model.formatWatchRadius(event.radiusKm, useImperial)
          + " awareness area has reached "
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
        if (root.watchProcessOperation === "load") root.watchPlacesLoaded = false
        root.watchPlacesError = root.watchProcessOperation === "save"
          ? "Watch places could not be saved. They remain active for this session."
          : "Saved watch places could not be loaded. The file was left unchanged."
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

  Process {
    id: placeSearchProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.placeSearchProcessOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.placeSearchProcessError = text
    }
    onExited: function(exitCode) {
      var completedQuery = root.activePlaceSearchQuery
      var stillRequested = completedQuery !== ""
        && completedQuery === root.requestedPlaceSearchQuery
      var accepted = exitCode === 0 && stillRequested
        && root.applyPlaceSearch(root.placeSearchProcessOutput, completedQuery)
      if (stillRequested) {
        root.placeSearchLoading = false
        if (!accepted) {
          root.placeSearchResults = []
          root.placeSearchError = "Place search is unavailable. You can still click the map."
        }
      }
      root.placeSearchProcessOutput = ""
      root.placeSearchProcessError = ""
      root.activePlaceSearchQuery = ""
      var nextQuery = root.pendingPlaceSearchQuery
      root.pendingPlaceSearchQuery = ""
      if (nextQuery.length >= 2 && nextQuery === root.requestedPlaceSearchQuery) {
        root.placeSearchLoading = true
        Qt.callLater(function() { root.runPlaceSearch(nextQuery) })
      }
    }
  }

  Timer {
    id: reverseGeocodeDebounce
    interval: 350
    repeat: false
    onTriggered: {
      var coordinate = root.pendingReverseCoordinate
      root.pendingReverseCoordinate = null
      if (coordinate && coordinate.key === root.requestedReverseGeocodeKey) {
        if (reverseGeocodeProcess.running) root.pendingReverseCoordinate = coordinate
        else root.runReverseGeocode(coordinate)
      }
    }
  }

  Process {
    id: reverseGeocodeProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.reverseGeocodeProcessOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.reverseGeocodeProcessError = text
    }
    onExited: function(exitCode) {
      var completedKey = root.activeReverseGeocodeKey
      var stillRequested = completedKey !== ""
        && completedKey === root.requestedReverseGeocodeKey
      var accepted = exitCode === 0 && stillRequested
        && root.applyReverseGeocode(root.reverseGeocodeProcessOutput, completedKey)
      if (stillRequested) {
        root.reverseGeocodeLoading = false
        if (!accepted) root.reverseGeocodeError = "Nearby place naming is unavailable."
      }
      root.reverseGeocodeProcessOutput = ""
      root.reverseGeocodeProcessError = ""
      root.activeReverseGeocodeKey = ""
      if (root.pendingReverseCoordinate
          && root.pendingReverseCoordinate.key === root.requestedReverseGeocodeKey)
        root.scheduleReverseGeocode()
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
  onOnlinePlaceSearchEnabledChanged: {
    if (!onlinePlaceSearchEnabled) {
      clearPlaceSearch()
      clearReverseGeocode()
    }
  }
  Component.onCompleted: loadWatchPlaces()
}
