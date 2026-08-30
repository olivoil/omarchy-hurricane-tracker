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
  property string sidebarMode: "activity"
  property string activeTrackerId: "cyclones"
  property bool trackerMenuOpen: false
  property string selectedPlaceId: ""
  property bool editingWatchPlace: false
  property string editingPlaceId: ""
  property string draftPlaceName: ""
  property real draftPlaceLatitude: 999
  property real draftPlaceLongitude: 999
  property int draftPlaceRadiusKm: 1000
  property string placeEditorError: ""
  property bool draftPlaceNameManuallyEdited: false
  property string draftPlaceSearchQuery: ""
  property string draftResolvedPlaceLabel: ""
  property string draftPlaceLookupProvider: ""
  property bool draftLocationPending: false
  property bool placeSearchMenuOpen: false
  property int placeSearchHighlightIndex: -1
  property string pendingRemovePlaceId: ""
  property int clockTick: 0

  onDraftPlaceNameChanged: {
    if (placeNameField.text !== root.draftPlaceName)
      placeNameField.text = root.draftPlaceName
  }

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.olivoil.hurricane-tracker"
  readonly property var tracker: shell ? shell.serviceFor(pluginId) : null
  readonly property bool useImperial: tracker
    ? tracker.useImperial === true
    : Qt.locale().measurementSystem !== Locale.MetricSystem
  readonly property var storms: tracker && Array.isArray(tracker.storms) ? tracker.storms : []
  readonly property var outlooks: tracker && Array.isArray(tracker.outlooks) ? tracker.outlooks : []
  readonly property var watchPlaces: tracker && Array.isArray(tracker.watchPlaces) ? tracker.watchPlaces : []
  readonly property var placeSearchResults: tracker && Array.isArray(tracker.placeSearchResults)
    ? tracker.placeSearchResults : []
  readonly property bool placeSearchLoading: tracker && tracker.placeSearchLoading === true
  readonly property bool onlinePlaceSearchEnabled: !tracker
    || tracker.onlinePlaceSearchEnabled !== false
  readonly property string placeSearchError: tracker
    ? String(tracker.placeSearchError || "") : ""
  readonly property bool reverseGeocodeLoading: tracker
    && tracker.reverseGeocodeLoading === true
  readonly property string reverseGeocodeError: tracker
    ? String(tracker.reverseGeocodeError || "") : ""
  readonly property bool locationLookupLoading: placeSearchLoading || reverseGeocodeLoading
  readonly property int visiblePlaceSearchResultCount: Math.min(6, placeSearchResults.length)
  readonly property bool placeSearchSettledEmpty: tracker
    && !placeSearchDebounce.running && !placeSearchLoading && placeSearchError === ""
    && draftPlaceSearchQuery.trim().length >= 2 && placeSearchResults.length === 0
    && String(tracker.requestedPlaceSearchQuery || "")
      === draftPlaceSearchQuery.replace(/\s+/g, " ").trim()
  readonly property var systems: Model.orderedSystems(storms, outlooks)
  readonly property var regionalRows: Model.regionalRows(storms, outlooks)
  readonly property var watchPlaceSummaries: tracker
    && Array.isArray(tracker.watchPlaceSummaries) ? tracker.watchPlaceSummaries : []
  readonly property var selectedSystem: Model.systemByKey(systems, selectedKey)
  readonly property var selectedStorm: selectedSystem && selectedSystem.kind === "storm" ? selectedSystem : null
  readonly property var selectedOutlook: selectedSystem && selectedSystem.kind === "outlook" ? selectedSystem : null
  readonly property var selectedPlace: watchPlaceById(selectedPlaceId)
  readonly property var selectedPlaceSummary: watchPlaceSummaryById(selectedPlaceId)
  readonly property string mapSelectedKey: sidebarMode === "activity" ? selectedKey
    : (selectedPlaceSummary ? String(selectedPlaceSummary.systemKey || "") : "")
  readonly property int alertDestinationCount: watchPlaces.length
  readonly property int alertUpdateCount: Model.watchAttentionCount(watchPlaceSummaries)
  readonly property int alertUnsupportedDestinationCount:
    Model.watchUnsupportedCount(watchPlaceSummaries)
  readonly property int alertDataLimitedDestinationCount:
    Model.watchDataLimitedCount(watchPlaceSummaries)
  readonly property int alertLimitedDestinationCount: Math.min(alertDestinationCount,
    alertUnsupportedDestinationCount + alertDataLimitedDestinationCount)
  readonly property string alertAttentionState:
    Model.watchStrongestAttentionState(watchPlaceSummaries)
  readonly property int dataFeedCount: 1
  readonly property var trackerDefinitions: [
    {
      id: "cyclones",
      name: "CYCLONES",
      title: "HURRICANE TRACKER",
      description: "Tracks, forecast cones, and formation outlooks",
      state: String(systems.length) + " TRACKED",
      available: true
    },
    {
      id: "earthquakes",
      name: "EARTHQUAKES",
      title: "EARTHQUAKE TRACKER",
      description: "Recent events, shaking, depth, and impact",
      state: "COMING NEXT",
      available: false
    }
  ]
  readonly property string activeTrackerTitle: {
    for (var i = 0; i < trackerDefinitions.length; i++)
      if (trackerDefinitions[i].id === activeTrackerId)
        return String(trackerDefinitions[i].title || trackerDefinitions[i].name)
    return "HURRICANE TRACKER"
  }
  readonly property var draftWatchPlace: editingWatchPlace
    && Model.validCoordinate(draftPlaceLatitude, draftPlaceLongitude) ? ({
      id: editingPlaceId || "draft",
      name: draftPlaceName.trim() || (draftResolvedPlaceLabel
        ? draftResolvedPlaceLabel.split(",", 1)[0]
        : coordinateLabel(draftPlaceLatitude, draftPlaceLongitude, 2)),
      latitude: draftPlaceLatitude,
      longitude: draftPlaceLongitude,
      radiusKm: draftPlaceRadiusKm
    }) : null
  readonly property bool lightTheme:
    0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b > 0.5

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.72)
  property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.50)
  property color shellSurface: blendColor(background, foreground, lightTheme ? 0.018 : 0.025)
  property color raisedSurface: blendColor(background, foreground, lightTheme ? 0.045 : 0.065)
  property color softSurface: blendColor(background,
    lightTheme ? foreground : Qt.rgba(0, 0, 0, 1), lightTheme ? 0.018 : 0.045)
  property color deepSurface: blendColor(background,
    lightTheme ? foreground : Qt.rgba(0, 0, 0, 1), lightTheme ? 0.035 : 0.10)
  property color softBorder: Qt.rgba(border.r, border.g, border.b, 0.42)
  property color mapDeepOcean: blendColor(background, foreground, lightTheme ? 0.035 : 0.018)
  property color mapOcean: blendColor(background, accent, lightTheme ? 0.13 : 0.10)
  property color mapLand: blendColor(blendColor(background, foreground, lightTheme ? 0.28 : 0.18), accent, 0.08)
  property color mapLandOutline: blendColor(background, foreground, lightTheme ? 0.50 : 0.46)
  property color mapGrid: blendColor(background, foreground, lightTheme ? 0.52 : 0.58)
  property color mapText: foreground
  property color mapMuted: blendColor(background, foreground, lightTheme ? 0.70 : 0.66)
  property color mapCone: accent
  property color mapTrack: foreground

  readonly property int typeMicro: Math.max(10, Style.font.caption)
  readonly property int typeCaption: Math.max(11, Style.font.bodySmall)
  readonly property int typeBody: Math.max(12, Style.font.body)
  readonly property int typeSubtitle: Math.max(13, Style.font.subtitle)
  readonly property int typeHeading: Math.max(16, Style.font.heading)
  readonly property int minimumTouchTarget: Style.space(40)
  readonly property color alertAttentionColor: alertAttentionState === "urgent" ? root.urgent
    : (alertAttentionState === "monitor" ? "#e9be62" : root.accent)
  readonly property color alertStatusColor: alertUpdateCount > 0 ? alertAttentionColor
    : (alertLimitedDestinationCount > 0 ? "#e9be62" : root.accent)

  readonly property int cardWidth: Math.min(Style.space(1660), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(980), panel.height - Style.gapsOut * 2)
  readonly property int headerHeight: Style.space(68)
  readonly property int sidebarWidth: Math.min(Style.space(440),
    Math.max(Style.space(350), Math.round(cardWidth * 0.27)))
  readonly property int sidebarFooterHeight: Style.space(44)
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
      { label: "MAX WIND", value: Model.formatWind(system, useImperial) },
      { label: "PRESSURE", value: Model.formatPressure(system) },
      { label: "MOVEMENT", value: Model.formatMovement(system, useImperial) }
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
    if (payload.alerts === true) sidebarMode = "alerts"
    else if (payload.activity === true) sidebarMode = "activity"
    if (payload.stormId) selectedKey = "storm:" + String(payload.stormId)
    if (payload.outlookId) selectedKey = "outlook:" + String(payload.outlookId)
    opened = true
    syncSelection(true)
    if (tracker && !tracker.hasLoaded && !tracker.loading) tracker.refresh()
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      if (payload.globe === true) stormMap.showGlobe()
      else if (root.sidebarMode === "alerts" && root.selectedPlace) {
        if (root.editingWatchPlace) stormMap.fitWatchPlace(root.selectedPlace)
        else stormMap.focusWatchPlace(root.selectedPlace)
      }
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
      shell.hide(pluginId)
  }

  function showActivity() {
    if (editingWatchPlace) cancelWatchPlaceEditor()
    trackerMenuOpen = false
    sidebarMode = "activity"
    keyCatcher.forceActiveFocus()
  }

  function showAlerts() {
    trackerMenuOpen = false
    sidebarMode = "alerts"
    keyCatcher.forceActiveFocus()
  }

  function toggleTrackerMenu() {
    if (sidebarMode !== "activity") sidebarMode = "activity"
    trackerMenuOpen = !trackerMenuOpen
    keyCatcher.forceActiveFocus()
  }

  function activateTracker(identifier) {
    var id = String(identifier || "")
    for (var i = 0; i < trackerDefinitions.length; i++) {
      var definition = trackerDefinitions[i]
      if (definition.id !== id || !definition.available) continue
      activeTrackerId = id
      sidebarMode = "activity"
      trackerMenuOpen = false
      keyCatcher.forceActiveFocus()
      return
    }
  }

  function syncSelection(_forceReveal) {
    selectedKey = Model.selectedKeyAfterRefresh(systems, selectedKey)
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

  function viewRegion(basin) {
    if (!basin) return
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
    sidebarMode = "activity"
    trackerMenuOpen = false
    selectedPlaceId = ""
    selectedKey = key
    Qt.callLater(function() {
      var rowIndex = root.rowIndexForKey(key)
      if (rowIndex >= 0) systemList.positionViewAtIndex(rowIndex, ListView.Contain)
    })
    keyCatcher.forceActiveFocus()
  }

  function moveSelection(delta) {
    if (sidebarMode === "alerts") {
      movePlaceSelection(delta)
      return
    }
    if (systems.length === 0) return
    var current = 0
    for (var i = 0; i < systems.length; i++) if (systems[i].key === selectedKey) current = i
    var next = (current + delta + systems.length) % systems.length
    selectSystem(systems[next].key)
  }

  function watchPlaceById(identifier) {
    var id = String(identifier || "")
    for (var i = 0; i < watchPlaces.length; i++)
      if (String(watchPlaces[i] && watchPlaces[i].id || "") === id) return watchPlaces[i]
    return null
  }

  function watchPlaceSummaryById(identifier) {
    var id = String(identifier || "")
    for (var i = 0; i < watchPlaceSummaries.length; i++) {
      var summary = watchPlaceSummaries[i]
      if (summary && summary.place && summary.place.id === id) return summary
    }
    return null
  }

  function selectWatchPlace(identifier) {
    var place = watchPlaceById(identifier)
    if (!place) return
    sidebarMode = "alerts"
    trackerMenuOpen = false
    selectedPlaceId = place.id
    stormMap.focusWatchPlace(place)
    keyCatcher.forceActiveFocus()
  }

  function movePlaceSelection(delta) {
    if (editingWatchPlace || watchPlaces.length === 0) return
    var current = 0
    for (var i = 0; i < watchPlaces.length; i++)
      if (watchPlaces[i].id === selectedPlaceId) current = i
    var next = (current + delta + watchPlaces.length) % watchPlaces.length
    selectWatchPlace(watchPlaces[next].id)
  }

  function beginAddWatchPlace() {
    if (!tracker || !tracker.watchPlacesLoaded || watchPlaces.length >= 12) return
    sidebarMode = "alerts"
    trackerMenuOpen = false
    editingWatchPlace = true
    editingPlaceId = ""
    draftPlaceName = ""
    draftPlaceLatitude = 999
    draftPlaceLongitude = 999
    draftPlaceRadiusKm = 1000
    placeEditorError = ""
    draftPlaceNameManuallyEdited = false
    resetPlaceSearch()
    Qt.callLater(function() { placeSearchField.forceActiveFocus() })
  }

  function beginEditWatchPlace(identifier) {
    var place = watchPlaceById(identifier)
    if (!place) return
    sidebarMode = "alerts"
    trackerMenuOpen = false
    editingWatchPlace = true
    editingPlaceId = place.id
    draftPlaceName = place.name
    draftPlaceLatitude = Number(place.latitude)
    draftPlaceLongitude = Number(place.longitude)
    draftPlaceRadiusKm = Number(place.radiusKm)
    placeEditorError = ""
    draftPlaceNameManuallyEdited = true
    resetPlaceSearch()
    draftPlaceSearchQuery = coordinateLabel(place.latitude, place.longitude, 3)
    selectedPlaceId = place.id
    stormMap.fitWatchPlace(place)
    Qt.callLater(function() {
      placeNameField.forceActiveFocus()
      placeNameField.selectAll()
    })
  }

  function cancelWatchPlaceEditor() {
    editingWatchPlace = false
    editingPlaceId = ""
    draftPlaceName = ""
    draftPlaceLatitude = 999
    draftPlaceLongitude = 999
    placeEditorError = ""
    draftPlaceNameManuallyEdited = false
    resetPlaceSearch()
    keyCatcher.forceActiveFocus()
  }

  function resetPlaceSearch() {
    placeSearchDebounce.stop()
    draftPlaceSearchQuery = ""
    draftResolvedPlaceLabel = ""
    draftPlaceLookupProvider = ""
    draftLocationPending = false
    placeSearchMenuOpen = false
    placeSearchHighlightIndex = -1
    if (tracker && tracker.clearPlaceSearch) tracker.clearPlaceSearch()
    if (tracker && tracker.clearReverseGeocode) tracker.clearReverseGeocode()
  }

  function suggestDraftPlaceName(value) {
    var suggestion = String(value || "").replace(/\s+/g, " ").trim().slice(0, 40)
    if (!suggestion) return
    if (!draftPlaceNameManuallyEdited || draftPlaceName.trim() === "") {
      draftPlaceName = suggestion
      draftPlaceNameManuallyEdited = false
    }
  }

  function queuePlaceSearch(value) {
    draftPlaceSearchQuery = String(value || "").slice(0, 120)
    draftResolvedPlaceLabel = ""
    draftPlaceLookupProvider = ""
    draftLocationPending = true
    placeSearchMenuOpen = onlinePlaceSearchEnabled
      && draftPlaceSearchQuery.trim().length >= 2
    placeSearchHighlightIndex = -1
    if (tracker && tracker.clearPlaceSearch) tracker.clearPlaceSearch()
    if (tracker && tracker.clearReverseGeocode) tracker.clearReverseGeocode()
    if (!tracker || !tracker.searchPlaces || draftPlaceSearchQuery.trim().length < 2) {
      placeSearchDebounce.stop()
      return
    }
    placeSearchDebounce.restart()
  }

  function movePlaceSearchHighlight(delta) {
    var count = visiblePlaceSearchResultCount
    if (count === 0) return
    var current = placeSearchHighlightIndex
    if (current < 0) current = delta > 0 ? -1 : 0
    placeSearchHighlightIndex = (current + delta + count) % count
  }

  function selectPlaceSearchResult(result) {
    if (!result || !Model.validCoordinate(result.latitude, result.longitude)) return
    var label = String(result.name || "")
    var context = String(result.context || "")
    draftResolvedPlaceLabel = label + (context ? ", " + context : "")
    draftPlaceLookupProvider = "open-meteo-geonames"
    draftPlaceSearchQuery = draftResolvedPlaceLabel
    draftLocationPending = false
    placeSearchMenuOpen = false
    placeSearchDebounce.stop()
    placeSearchHighlightIndex = -1
    if (tracker && tracker.clearPlaceSearch) tracker.clearPlaceSearch()
    if (tracker && tracker.clearReverseGeocode) tracker.clearReverseGeocode()
    root.suggestDraftPlaceName(result.name)
    setDraftWatchCoordinate(result.latitude, result.longitude, true)
    Qt.callLater(function() {
      if (root.draftWatchPlace) stormMap.fitWatchPlace(root.draftWatchPlace)
      placeNameField.forceActiveFocus()
      placeNameField.selectAll()
    })
  }

  function selectHighlightedPlaceSearchResult() {
    var index = placeSearchHighlightIndex
    if (index < 0 && visiblePlaceSearchResultCount > 0) index = 0
    if (index >= 0 && index < visiblePlaceSearchResultCount)
      selectPlaceSearchResult(placeSearchResults[index])
  }

  function setDraftWatchCoordinate(latitude, longitude, fromSearch) {
    if (!editingWatchPlace || !Model.validCoordinate(latitude, longitude)) return
    draftPlaceLatitude = Number(latitude)
    draftPlaceLongitude = Number(longitude)
    placeEditorError = ""
    if (fromSearch !== true) {
      placeSearchDebounce.stop()
      draftPlaceSearchQuery = coordinateLabel(latitude, longitude, 3)
      draftResolvedPlaceLabel = ""
      draftPlaceLookupProvider = ""
      draftLocationPending = false
      placeSearchMenuOpen = false
      placeSearchHighlightIndex = -1
      if (tracker && tracker.clearPlaceSearch) tracker.clearPlaceSearch()
      if (tracker && tracker.clearReverseGeocode) tracker.clearReverseGeocode()
      if (tracker && tracker.reverseGeocode)
        root.tracker.reverseGeocode(latitude, longitude)
    }
  }

  function applyReverseGeocodeSuggestion(result) {
    if (!editingWatchPlace || !result
        || !Model.validCoordinate(result.latitude, result.longitude)
        || Math.abs(Number(result.latitude) - draftPlaceLatitude) > 0.00001
        || Math.abs(Number(result.longitude) - draftPlaceLongitude) > 0.00001) return
    var name = String(result.name || "").replace(/\s+/g, " ").trim()
    var context = String(result.context || "").replace(/\s+/g, " ").trim()
    if (!name) return
    draftResolvedPlaceLabel = name + (context ? ", " + context : "")
    draftPlaceLookupProvider = "nominatim-openstreetmap"
    draftPlaceSearchQuery = draftResolvedPlaceLabel
    suggestDraftPlaceName(name)
    placeEditorError = ""
  }

  function coordinateLabel(latitudeValue, longitudeValue, precision) {
    if (!Model.validCoordinate(latitudeValue, longitudeValue)) return "LOCATION UNAVAILABLE"
    var digits = Math.max(0, Math.min(5, Number(precision === undefined ? 2 : precision)))
    var latitude = Math.abs(Number(latitudeValue)).toFixed(digits)
      + (Number(latitudeValue) >= 0 ? "° N" : "° S")
    var longitude = Math.abs(Number(longitudeValue)).toFixed(digits)
      + (Number(longitudeValue) >= 0 ? "° E" : "° W")
    return latitude + ", " + longitude
  }

  function locationHint() {
    if (placeSearchError !== "") return placeSearchError
    if (placeSearchLoading) return "Searching… You can still click the globe."
    if (reverseGeocodeLoading) return "Finding the nearest place name…"
    if (draftLocationPending) {
      if (placeSearchSettledEmpty)
        return "No matching places. Try adding a region or country."
      return draftPlaceSearchQuery.trim().length < 2
        ? "Keep typing, or click the globe to choose the location."
        : "Choose a result, or click the globe to use an exact point."
    }
    if (Model.validCoordinate(draftPlaceLatitude, draftPlaceLongitude)) {
      var coordinate = coordinateLabel(draftPlaceLatitude, draftPlaceLongitude, 3)
      if (reverseGeocodeError !== "") return coordinate + " · Add a name below."
      if (draftPlaceLookupProvider === "nominatim-openstreetmap")
        return coordinate + " · © OpenStreetMap contributors"
      return coordinate
    }
    return onlinePlaceSearchEnabled
      ? "Search for a place, or click the globe to choose an exact point."
      : "Click the globe to choose an exact point."
  }

  function watchPlaceCoordinateLabel(place) {
    return place ? coordinateLabel(place.latitude, place.longitude, 2) : "LOCATION UNAVAILABLE"
  }

  function watchPlaceRuleLabel(place) {
    return "Forecast cone or 7-day formation area within "
      + Model.formatDistanceKm(place && place.radiusKm || 1000, useImperial, 5)
  }

  function watchPlaceScopeLabel(summary) {
    if (!summary || !summary.place) return "Official coverage: NHC basins only"
    return summary.state === "unsupported"
      ? "Outside current NHC source coverage" : "Official coverage: NHC basins only"
  }

  function saveWatchPlace() {
    var name = draftPlaceName.replace(/\s+/g, " ").trim()
    if (!name) {
      placeEditorError = "Give this location a short name."
      placeNameField.forceActiveFocus()
      return
    }
    if (draftLocationPending) {
      placeEditorError = "Choose a location result or click the map."
      placeSearchField.forceActiveFocus()
      return
    }
    if (!Model.validCoordinate(draftPlaceLatitude, draftPlaceLongitude)) {
      placeEditorError = "Search for a location or click the map."
      placeSearchField.forceActiveFocus()
      return
    }
    if (!tracker || !tracker.upsertWatchPlace) {
      placeEditorError = "Watched locations are not available yet."
      return
    }
    var identifier = tracker.upsertWatchPlace({
      id: editingPlaceId,
      name: name,
      latitude: draftPlaceLatitude,
      longitude: draftPlaceLongitude,
      radiusKm: draftPlaceRadiusKm
    })
    if (!identifier) {
      placeEditorError = "This watched location could not be saved."
      return
    }
    selectedPlaceId = identifier
    var savedPlace = {
      id: identifier,
      name: name,
      latitude: draftPlaceLatitude,
      longitude: draftPlaceLongitude,
      radiusKm: draftPlaceRadiusKm
    }
    cancelWatchPlaceEditor()
    stormMap.focusWatchPlace(savedPlace)
  }

  function requestRemoveWatchPlace(identifier) {
    var id = String(identifier || "")
    if (!id || !tracker || !tracker.removeWatchPlace) return
    if (pendingRemovePlaceId !== id) {
      pendingRemovePlaceId = id
      removeConfirmTimer.restart()
      return
    }
    tracker.removeWatchPlace(id)
    pendingRemovePlaceId = ""
    if (selectedPlaceId === id) selectedPlaceId = ""
  }

  function placeStateColor(summary) {
    if (!summary) return dim
    if (summary.state === "urgent") return root.urgent
    if (summary.state === "monitor") return "#e9be62"
    if (summary.state === "heads-up") return root.accent
    if (summary.state === "limited") return "#e9be62"
    return dim
  }

  function refresh() {
    if (tracker && tracker.refresh) tracker.refresh()
  }

  function officialUrl(storm, field) {
    return Model.safeOfficialUrl(storm && storm[field])
  }

  function openBrowser(url) {
    var safeUrl = Model.safeOfficialUrl(url)
    if (!safeUrl) return
    Quickshell.execDetached(["omarchy-launch-browser", safeUrl])
    dismiss()
  }

  function openOfficial(storm, field) {
    openBrowser(officialUrl(storm, field))
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
    ignoreUnknownSignals: true
    function onStormsChanged() { root.syncSelection(false) }
    function onOutlooksChanged() { root.syncSelection(false) }
    function onWatchPlacesChanged() {
      if (root.selectedPlaceId && !root.watchPlaceById(root.selectedPlaceId))
        root.selectedPlaceId = ""
    }
    function onReverseGeocodeResultChanged() {
      Qt.callLater(function() {
        if (root.tracker)
          root.applyReverseGeocodeSuggestion(root.tracker.reverseGeocodeResult)
      })
    }
    function onOnlinePlaceSearchEnabledChanged() {
      if (!root.onlinePlaceSearchEnabled) {
        root.resetPlaceSearch()
        if (Model.validCoordinate(root.draftPlaceLatitude, root.draftPlaceLongitude))
          root.draftPlaceSearchQuery = root.coordinateLabel(
            root.draftPlaceLatitude, root.draftPlaceLongitude, 3)
      }
    }
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

  Timer {
    id: removeConfirmTimer
    interval: 5000
    repeat: false
    onTriggered: root.pendingRemovePlaceId = ""
  }

  Timer {
    id: placeSearchDebounce
    interval: 450
    repeat: false
    onTriggered: {
      if (root.tracker && root.tracker.searchPlaces
          && root.draftPlaceSearchQuery.trim().length >= 2)
        root.tracker.searchPlaces(root.draftPlaceSearchQuery)
    }
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
            if (root.trackerMenuOpen) root.trackerMenuOpen = false
            else if (root.editingWatchPlace) root.cancelWatchPlaceEditor()
            else if (root.sidebarMode === "alerts") root.showActivity()
            else root.dismiss()
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
          } else if (event.key === Qt.Key_A) {
            if (root.sidebarMode === "alerts") root.showActivity()
            else root.showAlerts()
            event.accepted = true
          } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            stormMap.zoomIn()
            event.accepted = true
          } else if (event.key === Qt.Key_Minus) {
            stormMap.zoomOut()
            event.accepted = true
          } else if (event.key === Qt.Key_F) {
            if (root.sidebarMode === "alerts" && root.selectedPlace)
              stormMap.fitWatchPlace(root.selectedPlace)
            else stormMap.resetView()
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
        color: root.shellSurface
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
          text: "\uf0ac"
          color: root.accent
          font.family: Style.font.family
          font.pixelSize: Style.space(19)
        }

        Column {
          anchors.left: brandIcon.right
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Text {
            text: root.activeTrackerTitle
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title + 1
            font.bold: true
            font.letterSpacing: 1.2
          }
          Text {
            text: "LIVE HAZARDS · OFFICIAL SOURCES · PERSONAL ALERTS"
            textFormat: Text.PlainText
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: root.typeMicro
            font.letterSpacing: 0.6
          }
        }

        Button {
          id: closeButton
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: root.minimumTouchTarget
          height: root.minimumTouchTarget
          iconText: "\uf00d"
          tooltipText: "Close (Esc)"
          focusable: true
          foreground: root.foreground
          accent: root.accent
          horizontalPadding: 0
          verticalPadding: 0
          radius: Style.space(7)
          onClicked: root.dismiss()
        }

        Button {
          id: alertsButton
          anchors.right: closeButton.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          width: alertButtonContent.implicitWidth + Style.space(18)
          height: root.minimumTouchTarget
          radius: Style.space(7)
          bordered: true
          selected: root.sidebarMode === "alerts"
          tooltipText: root.alertUpdateCount === 0
            ? (root.alertLimitedDestinationCount > 0
              ? "Manage alerts (A). " + String(root.alertLimitedDestinationCount)
                + (root.alertLimitedDestinationCount === 1
                  ? " watched location has limited coverage"
                  : " watched locations have limited coverage")
              : "Manage alerts (A). No watched locations need attention")
            : (root.alertUpdateCount === 1
              ? "1 watched location needs attention"
              : String(root.alertUpdateCount) + " watched locations need attention")
          focusable: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.showAlerts()
          Accessible.name: tooltipText

          Row {
            id: alertButtonContent
            anchors.centerIn: parent
            spacing: Style.spacing.sm

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "◇"
              color: root.alertStatusColor
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "ALERTS"
              color: alertsButton.selected
                ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeCaption
              font.bold: true
              font.letterSpacing: 0.8
            }
            Rectangle {
              visible: root.alertUpdateCount > 0
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(17)
              height: width
              radius: width / 2
              color: Qt.rgba(root.alertAttentionColor.r, root.alertAttentionColor.g,
                root.alertAttentionColor.b, 0.18)

              Text {
                anchors.centerIn: parent
                text: String(root.alertUpdateCount)
                color: root.alertAttentionColor
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeMicro
                font.bold: true
              }
            }
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
          watchPlaces: root.watchPlaces
          selectedKey: root.mapSelectedKey
          autoFitSelection: root.sidebarMode === "activity"
          selectedPlaceId: root.selectedPlaceId
          placementMode: root.editingWatchPlace
          draftWatchPlace: root.draftWatchPlace
          useImperial: root.useImperial
          bottomInset: root.sidebarMode === "activity" && root.selectedStorm ? root.timelineHeight : 0
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
          onPlaceActivated: function(identifier) { root.selectWatchPlace(identifier) }
          onPlacePicked: function(latitude, longitude) {
            root.setDraftWatchCoordinate(latitude, longitude)
          }
          onPointerActivity: keyCatcher.forceActiveFocus()
        }

        BorderSurface {
          id: placementGuide
          visible: root.editingWatchPlace
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Style.spacing.lg
          width: Math.min(Style.space(390), mapArea.width - Style.spacing.xl * 2)
          height: Style.space(48)
          radius: Style.cornerRadius
          color: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.94)
          borderSpec: Border.surfaceSpec("menu", "border", root.mapCone,
            Math.max(1, Style.normalBorderWidth))
          z: 5

          Row {
            anchors.centerIn: parent
            spacing: Style.spacing.md

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf041"
              color: root.mapCone
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Text {
                text: root.draftWatchPlace ? "CLICK TO MOVE THE WATCH POINT" : "CLICK TO PLACE THE WATCH POINT"
                color: root.mapText
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeBody
                font.bold: true
                font.letterSpacing: 0.35
              }
              Text {
                text: "Drag to move the globe · scroll to zoom"
                color: root.mapMuted
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeCaption
              }
            }
          }
        }

        BorderSurface {
          id: stormSummary
          visible: root.sidebarMode === "activity" && root.selectedSystem !== null
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
                font.pixelSize: root.typeCaption
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
                font.pixelSize: root.typeCaption
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
              font.pixelSize: root.typeCaption
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
                    font.pixelSize: root.typeMicro
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
                    font.pixelSize: root.typeBody
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
            font.pixelSize: root.typeCaption
          }
          Button {
            id: retryButton
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            height: root.minimumTouchTarget
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
          visible: root.sidebarMode === "activity" && root.systems.length === 0
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
          visible: root.sidebarMode === "activity" && root.selectedSystem !== null
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
                font.pixelSize: root.typeCaption
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
                font.pixelSize: root.typeCaption
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
            width: root.minimumTouchTarget
            height: root.minimumTouchTarget
            foreground: root.mapText
            background: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.92)
            onClicked: stormMap.zoomIn()
          }
          Button {
            iconText: "\uf068"
            tooltipText: "Zoom out (-)"
            focusable: true
            width: root.minimumTouchTarget
            height: root.minimumTouchTarget
            foreground: root.mapText
            background: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.92)
            onClicked: stormMap.zoomOut()
          }
          Button {
            iconText: "\uf05b"
            tooltipText: root.sidebarMode === "alerts" && root.selectedPlace
              ? "Fit selected watch area (F)" : "Fit selected system (F)"
            focusable: true
            width: root.minimumTouchTarget
            height: root.minimumTouchTarget
            foreground: root.mapText
            background: Qt.rgba(root.mapDeepOcean.r, root.mapDeepOcean.g, root.mapDeepOcean.b, 0.92)
            onClicked: {
              if (root.sidebarMode === "alerts" && root.selectedPlace)
                stormMap.fitWatchPlace(root.selectedPlace)
              else stormMap.resetView()
            }
          }
          Button {
            iconText: "\uf0ac"
            tooltipText: "Show the whole globe (G)"
            focusable: true
            width: root.minimumTouchTarget
            height: root.minimumTouchTarget
            foreground: root.mapText
            background: root.background
            onClicked: stormMap.showGlobe()
          }
        }

        Rectangle {
          id: timeline
          visible: root.sidebarMode === "activity" && root.selectedStorm
            && Array.isArray(root.selectedStorm.track)
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
                font.pixelSize: root.typeBody
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
                font.pixelSize: root.typeMicro
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(73)
                text: Model.formatWind(forecast, root.useImperial)
                color: Model.severityColor(forecast)
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeCaption
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
        color: root.softSurface
        z: 2

        Rectangle {
          id: sidebarDivider
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: root.border
          z: 20
        }

        Rectangle {
          id: listHeader
          visible: root.sidebarMode === "activity"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: visible ? Style.space(60) : 0
          color: root.shellSurface

          BorderSurface {
            id: trackerMenuButton
            readonly property bool hot: trackerMenuMouse.containsMouse
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: trackerButtonContent.implicitWidth + Style.spacing.md * 2
            height: root.minimumTouchTarget
            radius: Style.space(6)
            color: root.trackerMenuOpen || hot || activeFocus ? root.raisedSurface : "transparent"
            borderSpec: activeFocus
              ? Border.controlSpec("focus", root.foreground, root.accent) : Border.none()
            activeFocusOnTab: true
            Keys.onReturnPressed: root.toggleTrackerMenu()
            Keys.onEnterPressed: root.toggleTrackerMenu()
            Keys.onSpacePressed: root.toggleTrackerMenu()
            Accessible.name: root.trackerMenuOpen ? "Close tracker menu" : "Choose a tracker"
            Accessible.role: Accessible.Button

            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
              id: trackerButtonContent
              anchors.centerIn: parent
              spacing: Style.spacing.sm

              HurricaneIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                height: width
                iconColor: root.accent
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "CYCLONES"
                color: root.trackerMenuOpen
                  ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 1
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf078"
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: root.typeMicro
                rotation: root.trackerMenuOpen ? 180 : 0

                Behavior on rotation { NumberAnimation { duration: 140 } }
              }
            }

            MouseArea {
              id: trackerMenuMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                trackerMenuButton.forceActiveFocus()
                root.toggleTrackerMenu()
              }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.systems.length) + " TRACKED"
            color: root.dim
            font.family: Style.font.menuFamily
            font.pixelSize: root.typeMicro
            font.bold: true
            font.letterSpacing: 0.45
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.border
          }
        }

        Rectangle {
          id: trackerMenuPanel
          visible: root.sidebarMode === "activity" && root.trackerMenuOpen
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: listHeader.bottom
          anchors.bottom: dataFooter.top
          color: root.softSurface
          clip: true
          z: 8

          Column {
            anchors.fill: parent

            Rectangle {
              width: parent.width
              height: trackerMenuIntroduction.implicitHeight + Style.space(30)
              color: root.shellSurface

              Column {
                id: trackerMenuIntroduction
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(14)
                anchors.top: parent.top
                anchors.topMargin: Style.space(16)
                spacing: Style.space(6)

                Text {
                  text: "TRACKERS"
                  color: root.foreground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  font.letterSpacing: 1
                }
                Text {
                  width: parent.width
                  text: "Choose what the map monitors. New hazard modules can join this menu without changing the app shell."
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  lineHeight: 1.45
                }
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.softBorder
              }
            }

            Repeater {
              model: root.trackerDefinitions

              delegate: Button {
                required property var modelData
                width: trackerMenuPanel.width
                height: Style.space(88)
                enabled: modelData.available
                selected: false
                radius: 0
                background: modelData.id === root.activeTrackerId
                  ? root.raisedSurface : "transparent"
                opacity: enabled ? 1 : 0.58
                foreground: root.foreground
                accent: root.accent
                horizontalPadding: 0
                verticalPadding: 0
                onClicked: root.activateTracker(modelData.id)
                Accessible.name: modelData.name + ", " + modelData.description

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: 1
                  color: root.softBorder
                }

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  BorderSurface {
                    id: trackerPreview
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(68)
                    height: Style.space(60)
                    radius: Style.space(7)
                    color: root.deepSurface
                    borderSpec: Border.surfaceSpec("menu", "border", root.softBorder,
                      Math.max(1, Style.normalBorderWidth))

                    Rectangle {
                      visible: modelData.id === "cyclones"
                      anchors.centerIn: parent
                      width: Style.space(42)
                      height: width
                      radius: width / 2
                      color: "transparent"
                      border.width: 1
                      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                    }
                    Rectangle {
                      visible: modelData.id === "cyclones"
                      anchors.centerIn: parent
                      width: Style.space(29)
                      height: width
                      radius: width / 2
                      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.06)
                      border.width: 1
                      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)
                    }

                    HurricaneIcon {
                      visible: modelData.id === "cyclones"
                      anchors.centerIn: parent
                      width: Style.space(25)
                      height: width
                      iconColor: root.accent
                    }
                    Rectangle {
                      visible: modelData.id === "earthquakes"
                      x: Style.space(13)
                      y: Style.space(11)
                      width: Style.space(15)
                      height: width
                      radius: width / 2
                      color: root.deepSurface
                      border.width: 2
                      border.color: root.accent
                    }
                    Rectangle {
                      visible: modelData.id === "earthquakes"
                      x: Style.space(39)
                      y: Style.space(32)
                      width: Style.space(18)
                      height: width
                      radius: width / 2
                      color: root.deepSurface
                      border.width: 2
                      border.color: root.mapMuted
                    }
                    Rectangle {
                      visible: modelData.id === "earthquakes"
                      x: Style.space(46)
                      y: Style.space(10)
                      width: Style.space(9)
                      height: width
                      radius: width / 2
                      color: root.faint
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - trackerPreview.width - trackerState.implicitWidth
                      - Style.space(20)
                    spacing: Style.space(5)

                    Text {
                      width: parent.width
                      text: modelData.name
                      color: root.foreground
                      elide: Text.ElideRight
                      font.family: Style.font.menuFamily
                      font.pixelSize: root.typeBody
                      font.bold: true
                      font.letterSpacing: 0.65
                    }
                    Text {
                      width: parent.width
                      text: modelData.description
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                      color: root.dim
                      font.family: Style.font.menuFamily
                      font.pixelSize: root.typeCaption
                      lineHeight: 1.4
                    }
                  }

                  Text {
                    id: trackerState
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.state
                    color: modelData.available ? root.dim : root.faint
                    font.family: Style.font.menuFamily
                    font.pixelSize: root.typeMicro
                    font.bold: true
                    font.letterSpacing: 0.35
                  }
                }
              }
            }
          }
        }

        ListView {
          id: systemList
          visible: root.sidebarMode === "activity"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: listHeader.bottom
          anchors.bottom: discussionPanel.visible ? discussionPanel.top : dataFooter.top
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.regionalRows
          currentIndex: -1

          delegate: Rectangle {
            id: systemRow
            property var rowData: modelData
            property var system: rowData.kind === "system" ? rowData.system : null
            property bool isSelected: system && system.key === root.selectedKey
            readonly property color itemColor: system ? root.systemColor(system) : root.dim
            width: systemList.width
            height: rowData.kind === "region" ? Style.space(48)
              : (rowData.kind === "empty" ? Style.space(34) : Style.space(82))
            color: isSelected ? root.raisedSurface
              : (system && rowMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: rowData.kind === "region" ? root.border : root.softBorder
            }

            Text {
              id: regionTitle
              visible: rowData.kind === "region"
              anchors.left: parent.left
              anchors.leftMargin: Style.space(13)
              anchors.right: regionCountLabel.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: String(rowData.name || "REGION").toUpperCase()
              color: root.foreground
              elide: Text.ElideRight
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeCaption
              font.bold: true
              font.letterSpacing: 0.7
            }

            Text {
              id: regionCountLabel
              anchors.right: regionViewButton.visible ? regionViewButton.left : parent.right
              anchors.rightMargin: regionViewButton.visible ? Style.space(8) : Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
              visible: rowData.kind === "region"
              text: {
                var parts = []
                if (Number(rowData.activeCount || 0) > 0) parts.push(rowData.activeCount + " ACTIVE")
                if (Number(rowData.outlookCount || 0) > 0) parts.push(rowData.outlookCount + " OUTLOOK")
                return parts.length > 0 ? parts.join(" · ") : "QUIET"
              }
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeMicro
              font.bold: true
            }

            Button {
              id: regionViewButton
              visible: rowData.kind === "region"
                && (Number(rowData.activeCount || 0) + Number(rowData.outlookCount || 0) > 0)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              height: root.minimumTouchTarget
              text: "View all"
              iconText: "\uf05b"
              tooltipText: "Fit every system in " + String(rowData.name || "this region")
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontSize: root.typeCaption
              iconSize: root.typeMicro
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(4)
              z: 2
              onClicked: root.viewRegion(rowData.basin)
              Accessible.name: "View all systems in " + String(rowData.name || "this region")
            }

            Text {
              visible: rowData.kind === "empty"
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: "No current systems"
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeCaption
            }

            Rectangle {
              id: severityBadge
              visible: system !== null
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(46)
              height: Style.space(40)
              radius: Style.space(9)
              color: Qt.rgba(Qt.color(itemColor).r, Qt.color(itemColor).g,
                Qt.color(itemColor).b, root.lightTheme ? 0.20 : 0.18)
              border.width: 2
              border.color: itemColor

              Text {
                anchors.centerIn: parent
                text: system ? (system.kind === "storm" ? Model.severityCode(system)
                  : String(system.sevenDayChance || 0) + "%") : ""
                color: itemColor
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeCaption
                font.bold: true
              }
            }

            Column {
              visible: system !== null
              anchors.left: severityBadge.right
              anchors.leftMargin: Style.space(9)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                width: parent.width
                text: system ? String(system.name || system.title || "Tropical system") : ""
                textFormat: Text.PlainText
                color: root.foreground
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeBody
                font.bold: true
              }
              Text {
                width: parent.width
                text: system ? Model.systemClassificationLabel(system) + " · "
                  + Model.systemMetric(system, root.useImperial) : ""
                textFormat: Text.PlainText
                color: root.dim
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeCaption
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              enabled: system !== null
              hoverEnabled: true
              cursorShape: system ? Qt.PointingHandCursor : Qt.ArrowCursor
              z: 1
              onClicked: {
                if (system) root.selectSystem(system.key)
              }
            }

            Accessible.name: rowData.kind === "region" ? String(rowData.name || "Region") + " region"
              : (system ? String(system.name || "Tropical system") + ", "
                + Model.systemClassificationLabel(system) + ", "
                + Model.systemMetric(system, root.useImperial) : "No current systems")
            Accessible.role: rowData.kind === "region" ? Accessible.StaticText : Accessible.ListItem
          }

          QQC.ScrollBar.vertical: QQC.ScrollBar {
            policy: systemList.contentHeight > systemList.height
              ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
          }
        }

        Item {
          id: watchPlacesPanel
          visible: root.sidebarMode === "alerts"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: dataFooter.top
          clip: true

          Rectangle {
            id: alertsHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.space(70)
            color: root.shellSurface

            Item {
              id: alertsBack
              anchors.left: parent.left
              anchors.leftMargin: Style.space(13)
              anchors.top: parent.top
              anchors.topMargin: Style.space(2)
              width: alertsBackContent.implicitWidth
              height: root.minimumTouchTarget
              activeFocusOnTab: true

              readonly property bool hot: activeFocus || alertsBackHitArea.containsMouse

              function activate() {
                if (root.editingWatchPlace) root.cancelWatchPlaceEditor()
                else root.showActivity()
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                  alertsBack.activate()
                  event.accepted = true
                }
              }

              Row {
                id: alertsBackContent
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uf053"
                  color: alertsBack.hot ? root.accent : root.dim
                  font.family: Style.font.family
                  font.pixelSize: root.typeCaption

                  Behavior on color { ColorAnimation { duration: 100 } }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.editingWatchPlace ? "WATCHED LOCATIONS" : "BACK TO ACTIVITY"
                  color: alertsBack.hot ? root.foreground : root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  font.letterSpacing: 0.15

                  Behavior on color { ColorAnimation { duration: 100 } }
                }
              }

              Rectangle {
                visible: alertsBack.activeFocus
                anchors.left: alertsBackContent.left
                anchors.right: alertsBackContent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.accent
                opacity: 0.7
              }

              MouseArea {
                id: alertsBackHitArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  alertsBack.forceActiveFocus()
                  alertsBack.activate()
                }
              }

              Accessible.name: root.editingWatchPlace
                ? "Back to watch alerts" : "Back to cyclone activity"
              Accessible.role: Accessible.Button
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(13)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(11)
              text: root.editingWatchPlace
                ? (root.editingPlaceId ? "EDIT LOCATION" : "ADD WATCHED LOCATION") : "WATCHED LOCATIONS"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 0.85
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(13)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(11)
              text: root.editingWatchPlace ? "AREA VISIBLE"
                : String(root.alertDestinationCount) + (root.alertDestinationCount === 1
                  ? " LOCATION" : " LOCATIONS")
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeMicro
              font.bold: true
              font.letterSpacing: 0.4
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.border
            }
          }

          Item {
            id: watchPlaceEditor
            visible: root.editingWatchPlace
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: alertsHeader.bottom
            anchors.bottom: parent.bottom

            Flickable {
              id: editorScroll
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: editorActions.top
              contentWidth: width
              contentHeight: editorForm.implicitHeight + Style.space(26)
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: editorForm
                x: Style.space(13)
                y: Style.space(13)
                width: editorScroll.width - Style.space(26)
                spacing: Style.space(13)

              Column {
                id: placeLocationSection
                z: 20
                width: parent.width
                spacing: Style.space(6)

                Text {
                  text: "LOCATION"
                  color: root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  font.bold: true
                  font.letterSpacing: 0.55
                }

                Item {
                  id: locationPicker
                  width: parent.width
                  height: root.minimumTouchTarget

                  TextField {
                    id: placeSearchField
                    anchors.fill: parent
                    readOnly: !root.onlinePlaceSearchEnabled
                    text: root.draftPlaceSearchQuery
                    placeholderText: root.onlinePlaceSearchEnabled
                      ? "Search a place or click the map" : "Click the map to choose a location"
                    maximumLength: 120
                    rightPadding: Style.space(38)
                    foreground: root.foreground
                    accent: root.accent
                    font.family: Style.font.menuFamily
                    font.pixelSize: root.typeBody
                    onTextEdited: root.queuePlaceSearch(text)
                    onActiveFocusChanged: {
                      if (activeFocus) {
                        if (!root.draftLocationPending && text !== "") selectAll()
                        if (root.draftLocationPending && text.trim().length >= 2) {
                          root.placeSearchMenuOpen = true
                          if (root.placeSearchResults.length === 0
                              && !root.placeSearchLoading) placeSearchDebounce.restart()
                        }
                      } else {
                        Qt.callLater(function() {
                          if (!placeSearchField.activeFocus) root.placeSearchMenuOpen = false
                        })
                      }
                    }
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) {
                        if (root.placeSearchMenuOpen) {
                          root.placeSearchMenuOpen = false
                          if (root.tracker && root.tracker.clearPlaceSearch)
                            root.tracker.clearPlaceSearch()
                        } else {
                          root.cancelWatchPlaceEditor()
                        }
                        event.accepted = true
                      } else if (event.key === Qt.Key_Down) {
                        root.placeSearchMenuOpen = true
                        root.movePlaceSearchHighlight(1)
                        event.accepted = true
                      } else if (event.key === Qt.Key_Up) {
                        root.placeSearchMenuOpen = true
                        root.movePlaceSearchHighlight(-1)
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.placeSearchMenuOpen
                            && root.visiblePlaceSearchResultCount > 0) {
                          root.selectHighlightedPlaceSearchResult()
                        } else if (root.draftLocationPending
                            && root.draftPlaceSearchQuery.trim().length >= 2
                            && root.tracker && root.tracker.searchPlaces) {
                          root.placeSearchMenuOpen = true
                          placeSearchDebounce.stop()
                          root.tracker.searchPlaces(root.draftPlaceSearchQuery)
                        }
                        event.accepted = true
                      }
                    }
                    Accessible.name: "Location, searchable or selectable on the map"
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(11)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.locationLookupLoading
                    text: root.draftWatchPlace && !root.draftLocationPending
                      ? "\uf041" : "\uf002"
                    color: root.draftWatchPlace && !root.draftLocationPending
                      ? root.accent : root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon
                  }

                  Text {
                    id: placeSearchSpinner
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(11)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.locationLookupLoading
                    text: "\uf110"
                    color: root.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.icon
                    transformOrigin: Item.Center

                    RotationAnimator on rotation {
                      running: root.locationLookupLoading
                      from: 0
                      to: 360
                      duration: 900
                      loops: Animation.Infinite
                    }
                  }

                  BorderSurface {
                    id: placeSearchResultsSurface
                    parent: watchPlaceEditor
                    x: editorScroll.x + editorForm.x + placeLocationSection.x
                      + locationPicker.x - editorScroll.contentX
                    y: editorScroll.y + editorForm.y + placeLocationSection.y
                      + locationPicker.y + locationPicker.height
                      - editorScroll.contentY + Style.space(6)
                    z: 50
                    visible: root.placeSearchMenuOpen
                      && root.visiblePlaceSearchResultCount > 0
                    width: placeSearchField.width
                    height: visible ? searchResultsColumn.implicitHeight : 0
                    radius: Style.space(7)
                    color: root.deepSurface
                    borderSpec: Border.surfaceSpec("menu", "border", root.border,
                      Math.max(1, Style.normalBorderWidth))
                    clip: true

                    Column {
                      id: searchResultsColumn
                      width: parent.width

                      Repeater {
                        model: root.placeSearchResults.slice(0,
                          root.visiblePlaceSearchResultCount)

                        delegate: Rectangle {
                          id: searchResultRow
                          required property var modelData
                          required property int index
                          width: searchResultsColumn.width
                          height: Style.space(52)
                          color: root.placeSearchHighlightIndex === index
                            ? Style.selectedFillFor(root.foreground, root.accent)
                            : (searchResultMouse.containsMouse
                              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

                          Behavior on color { ColorAnimation { duration: 90 } }

                          Rectangle {
                            visible: searchResultRow.index > 0
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(10)
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(10)
                            anchors.top: parent.top
                            height: 1
                            color: root.softBorder
                          }

                          Column {
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(10)
                            anchors.right: searchResultKind.left
                            anchors.rightMargin: Style.space(10)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(3)

                            Text {
                              width: parent.width
                              text: String(searchResultRow.modelData.name || "Place")
                              textFormat: Text.PlainText
                              color: root.foreground
                              elide: Text.ElideRight
                              font.family: Style.font.menuFamily
                              font.pixelSize: root.typeBody
                              font.bold: true
                            }
                            Text {
                              width: parent.width
                              text: String(searchResultRow.modelData.context || "")
                              textFormat: Text.PlainText
                              color: root.dim
                              elide: Text.ElideRight
                              font.family: Style.font.menuFamily
                              font.pixelSize: root.typeCaption
                            }
                          }

                          Text {
                            id: searchResultKind
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(10)
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(searchResultRow.modelData.kind || "Place").toUpperCase()
                            textFormat: Text.PlainText
                            color: root.faint
                            font.family: Style.font.menuFamily
                            font.pixelSize: root.typeMicro
                            font.bold: true
                            font.letterSpacing: 0.35
                          }

                          MouseArea {
                            id: searchResultMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.placeSearchHighlightIndex = searchResultRow.index
                            onClicked: root.selectPlaceSearchResult(searchResultRow.modelData)
                          }

                          Accessible.name: String(modelData.name || "Place") + ", "
                            + String(modelData.context || "")
                          Accessible.role: Accessible.ListItem
                        }
                      }

                      Item {
                        width: parent.width
                        height: Style.space(27)

                        Rectangle {
                          anchors.left: parent.left
                          anchors.leftMargin: Style.space(10)
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(10)
                          anchors.top: parent.top
                          height: 1
                          color: root.softBorder
                        }
                        Text {
                          anchors.left: parent.left
                          anchors.leftMargin: Style.space(10)
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Place search: Open-Meteo · GeoNames"
                          textFormat: Text.PlainText
                          color: root.faint
                          font.family: Style.font.menuFamily
                          font.pixelSize: root.typeMicro
                        }
                      }
                    }
                  }
                }

                Text {
                  width: parent.width
                  text: root.locationHint()
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  color: root.placeSearchError !== "" || root.reverseGeocodeError !== ""
                    ? "#e9be62" : root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  lineHeight: 1.4
                }
                Text {
                  visible: root.draftWatchPlace
                    && !Model.watchPlaceCoverage(root.draftWatchPlace).supported
                  width: parent.width
                  text: "Outside current NHC source coverage. This location can stay saved, but reliable alerts need another official source."
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  color: "#e9be62"
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  lineHeight: 1.4
                }
              }

              Column {
                id: placeNameSection
                width: parent.width
                spacing: Style.space(6)

                Text {
                  text: "NAME"
                  color: root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  font.bold: true
                  font.letterSpacing: 0.55
                }
                TextField {
                  id: placeNameField
                  width: parent.width
                  height: root.minimumTouchTarget
                  text: root.draftPlaceName
                  placeholderText: "Home, Beach House, Mom’s Place"
                  maximumLength: 40
                  foreground: root.foreground
                  accent: root.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeBody
                  onTextEdited: {
                    root.draftPlaceName = text
                    root.draftPlaceNameManuallyEdited = true
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      root.cancelWatchPlaceEditor()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.saveWatchPlace()
                      event.accepted = true
                    }
                  }
                  Accessible.name: "Personal name for this watched location"
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: "ALERTS"
                  color: root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  font.bold: true
                  font.letterSpacing: 0.55
                }
                BorderSurface {
                  width: parent.width
                  height: Style.space(102)
                  radius: Style.space(8)
                  color: root.shellSurface
                  borderSpec: Border.surfaceSpec("menu", "border", root.softBorder,
                    Math.max(1, Style.normalBorderWidth))

                  Column {
                    id: cycloneRuleContent
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(10)
                    spacing: Style.space(9)

                    Item {
                      width: parent.width
                      height: Style.space(14)

                      Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CYCLONES"
                        color: root.foreground
                        font.family: Style.font.menuFamily
                        font.pixelSize: root.typeMicro
                        font.bold: true
                      }
                      Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(5)

                        Rectangle {
                          anchors.verticalCenter: parent.verticalCenter
                          width: 5
                          height: 5
                          radius: 3
                          color: root.accent
                        }
                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "ACTIVE"
                          color: root.dim
                          font.family: Style.font.menuFamily
                          font.pixelSize: root.typeMicro
                          font.bold: true
                          font.letterSpacing: 0.5
                        }
                      }
                    }

                    Row {
                      width: parent.width
                      spacing: Style.space(8)

                      Column {
                        width: (parent.width - parent.spacing) / 2
                        spacing: Style.space(5)

                        Text {
                          text: "WITHIN"
                          color: root.dim
                          font.family: Style.font.menuFamily
                          font.pixelSize: root.typeMicro
                          font.bold: true
                          font.letterSpacing: 0.45
                        }
                        Dropdown {
                          width: parent.width
                          height: root.minimumTouchTarget
                          showLabel: false
                          rowHeight: root.minimumTouchTarget
                          value: String(root.draftPlaceRadiusKm)
                          options: [
                            { value: "250", label: Model.formatDistanceKm(250, root.useImperial, 5) },
                            { value: "500", label: Model.formatDistanceKm(500, root.useImperial, 5) },
                            { value: "750", label: Model.formatDistanceKm(750, root.useImperial, 5) },
                            { value: "1000", label: Model.formatDistanceKm(1000, root.useImperial, 5) },
                            { value: "1500", label: Model.formatDistanceKm(1500, root.useImperial, 5) },
                            { value: "2000", label: Model.formatDistanceKm(2000, root.useImperial, 5) }
                          ]
                          foreground: root.foreground
                          background: root.deepSurface
                          popupBorder: root.softBorder
                          accent: root.accent
                          fontFamily: Style.font.menuFamily
                          onChanged: function(value) { root.draftPlaceRadiusKm = Number(value) }
                        }
                      }

                      Column {
                        width: (parent.width - parent.spacing) / 2
                        spacing: Style.space(5)

                        Text {
                          text: "FORMATION"
                          color: root.dim
                          font.family: Style.font.menuFamily
                          font.pixelSize: root.typeMicro
                          font.bold: true
                          font.letterSpacing: 0.45
                        }
                        BorderSurface {
                          width: parent.width
                          height: root.minimumTouchTarget
                          radius: Style.space(7)
                          color: root.deepSurface
                          borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                          Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(10)
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(root.tracker
                              ? Model.alertThresholdValue(root.tracker.formationThreshold) : 40) + "%+"
                            color: root.foreground
                            font.family: Style.font.menuFamily
                            font.pixelSize: root.typeMicro
                          }
                          Text {
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(9)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "APP"
                            color: root.faint
                            font.family: Style.font.menuFamily
                            font.pixelSize: root.typeMicro
                            font.bold: true
                            font.letterSpacing: 0.4
                          }
                        }
                      }
                    }
                  }
                }
              }

                Text {
                  visible: root.placeEditorError !== ""
                  width: parent.width
                  text: root.placeEditorError
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  color: root.urgent
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                }
              }

              QQC.ScrollBar.vertical: QQC.ScrollBar {
                policy: editorScroll.contentHeight > editorScroll.height
                  ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
              }
            }

            Rectangle {
              id: editorActions
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Style.space(63)
              color: root.shellSurface
              z: 3

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: root.border
              }
              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(13)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(13)
                anchors.top: parent.top
                anchors.topMargin: Style.space(11)
                spacing: Style.space(8)

                Button {
                  width: (parent.width - parent.spacing) / 2
                  height: root.minimumTouchTarget
                  text: "CANCEL"
                  radius: Style.space(7)
                  background: root.raisedSurface
                  bordered: true
                  focusable: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: Style.font.menuFamily
                  fontSize: root.typeCaption
                  onClicked: root.cancelWatchPlaceEditor()
                }
                BorderSurface {
                  width: (parent.width - parent.spacing) / 2
                  height: root.minimumTouchTarget
                  radius: Style.space(7)
                  color: root.raisedSurface
                  borderSpec: Border.surfaceSpec("menu", "border",
                    Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.64),
                    Math.max(1, Style.normalBorderWidth))

                  Button {
                    anchors.fill: parent
                    text: "SAVE ALERTS"
                    radius: parent.radius
                    background: "transparent"
                    focusable: true
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: Style.font.menuFamily
                    fontSize: root.typeCaption
                    onClicked: root.saveWatchPlace()
                  }
                }
              }
            }
          }

          Item {
            id: alertDestinationsContent
            visible: !root.editingWatchPlace
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: alertsHeader.bottom
            anchors.bottom: parent.bottom

            Rectangle {
              id: alertsSummary
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Math.max(Style.space(76), Style.space(13)
                + alertsSummaryTitle.implicitHeight + Style.space(6)
                + alertsSummaryCopy.implicitHeight + Style.space(13))
              color: root.shellSurface

              Text {
                id: alertsSummaryTitle
                anchors.left: parent.left
                anchors.leftMargin: Style.space(13)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(13)
                anchors.top: parent.top
                anchors.topMargin: Style.space(13)
                text: root.alertDestinationCount === 0 ? "NO LOCATIONS WATCHED"
                  : (root.alertUpdateCount > 0
                    ? String(root.alertUpdateCount) + (root.alertUpdateCount === 1
                      ? " LOCATION NEEDS ATTENTION" : " LOCATIONS NEED ATTENTION")
                    : (root.alertLimitedDestinationCount > 0
                      ? String(root.alertLimitedDestinationCount)
                        + (root.alertLimitedDestinationCount === 1
                          ? " LOCATION HAS LIMITED COVERAGE"
                          : " LOCATIONS HAVE LIMITED COVERAGE")
                      : "ALL LOCATIONS QUIET"))
                color: root.alertStatusColor
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeCaption
                font.bold: true
                font.letterSpacing: 0.6
              }
              Text {
                id: alertsSummaryCopy
                anchors.left: parent.left
                anchors.leftMargin: Style.space(13)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(13)
                anchors.top: alertsSummaryTitle.bottom
                anchors.topMargin: Style.space(6)
                text: root.alertDestinationCount === 0
                  ? "Save a location for calm heads-ups from official formation areas and forecast paths. Alert perimeters appear only while editing."
                  : (root.alertUpdateCount === 0 && root.alertLimitedDestinationCount > 0
                    ? "Some official source or forecast data is unavailable. Review each location below for coverage."
                    : "Official formation areas and forecast paths are monitored for each location. Alert perimeters appear only while editing.")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: root.typeCaption
                lineHeight: 1.45
              }
              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.border
              }
            }

            Text {
              id: watchSaveError
              visible: root.tracker && root.tracker.watchPlacesError !== ""
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.top: alertsSummary.bottom
              anchors.topMargin: Style.spacing.md
              height: visible ? implicitHeight : 0
              text: root.tracker ? root.tracker.watchPlacesError : ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: "#e9be62"
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeCaption
            }

            ListView {
              id: watchPlaceList
              visible: root.watchPlaces.length > 0
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: watchSaveError.visible ? watchSaveError.bottom : alertsSummary.bottom
              anchors.topMargin: watchSaveError.visible ? Style.spacing.md : 0
              anchors.bottom: addWatchLocation.visible ? addWatchLocation.top : parent.bottom
              anchors.bottomMargin: addWatchLocation.visible ? Style.spacing.sm : 0
              model: root.watchPlaceSummaries
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              currentIndex: -1

              delegate: Rectangle {
                id: placeRow
                required property var modelData
                readonly property var summary: modelData
                readonly property var place: summary.place
                readonly property bool isSelected: place && place.id === root.selectedPlaceId
                readonly property bool summaryExpanded: isSelected
                readonly property real compactHeight: Style.space(108)
                readonly property real summaryTop: Style.space(60)
                readonly property string primarySummaryText:
                  summary.event || summary.state === "limited"
                    ? String(summary.detail || "")
                    : root.watchPlaceRuleLabel(place)
                readonly property string secondarySummaryText: summary.event
                  ? root.watchPlaceRuleLabel(place) : root.watchPlaceScopeLabel(summary)
                readonly property bool summaryTruncated: placePrimaryText.truncated
                  || placeSecondaryText.truncated
                  || placePrimaryText.implicitWidth > placePrimaryText.width
                  || placeSecondaryText.implicitWidth > placeSecondaryText.width
                width: watchPlaceList.width
                height: summaryExpanded
                  ? Math.max(compactHeight,
                    summaryTop + placeRules.implicitHeight + Style.space(10))
                  : compactHeight
                color: isSelected ? Style.selectedFillFor(root.foreground, root.accent)
                  : (placeMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

                QQC.ToolTip.visible: !placeRow.summaryExpanded
                  && placeMouse.containsMouse && placeRow.summaryTruncated
                QQC.ToolTip.delay: 550
                QQC.ToolTip.timeout: 6000
                QQC.ToolTip.text: placeRow.primarySummaryText + "\n"
                  + placeRow.secondarySummaryText

                Behavior on color { ColorAnimation { duration: 120 } }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: 1
                  color: root.softBorder
                }
                Text {
                  id: placeName
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: placeStatus.left
                  anchors.rightMargin: Style.space(10)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(12)
                  text: String(place && place.name || "Watched location").toUpperCase()
                  textFormat: Text.PlainText
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeBody
                  font.bold: true
                }

                BorderSurface {
                  id: placeStatus
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(12)
                  width: placeStatusText.implicitWidth + Style.space(12)
                  height: Style.space(24)
                  radius: Style.space(5)
                  color: "transparent"
                  borderSpec: Border.surfaceSpec("menu", "border",
                    root.placeStateColor(summary), Math.max(1, Style.normalBorderWidth))

                  Text {
                    id: placeStatusText
                    anchors.centerIn: parent
                    text: String(summary.status || "QUIET")
                    color: root.placeStateColor(summary)
                    font.family: Style.font.menuFamily
                    font.pixelSize: root.typeMicro
                    font.bold: true
                    font.letterSpacing: 0.55
                  }
                }

                Text {
                  id: placeCoordinate
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.top: placeName.bottom
                  anchors.topMargin: Style.space(4)
                  text: root.watchPlaceCoordinateLabel(place)
                  textFormat: Text.PlainText
                  color: root.dim
                  elide: Text.ElideRight
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                }

                Column {
                  id: placeRules
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: parent.right
                  anchors.rightMargin: placeActions.visible ? Style.space(96) : Style.space(12)
                  anchors.top: parent.top
                  anchors.topMargin: placeRow.summaryTop
                  spacing: Style.space(5)

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Rectangle {
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(6)
                      width: Style.space(5)
                      height: width
                      radius: width / 2
                      color: summary.event || summary.state === "limited"
                        ? root.placeStateColor(summary) : root.accent
                    }
                    Text {
                      id: placePrimaryText
                      width: parent.width - Style.space(11)
                      text: placeRow.primarySummaryText
                      textFormat: Text.PlainText
                      color: root.foreground
                      wrapMode: placeRow.summaryExpanded ? Text.WordWrap : Text.NoWrap
                      elide: placeRow.summaryExpanded ? Text.ElideNone
                        : (summary.event ? Text.ElideMiddle : Text.ElideRight)
                      font.family: Style.font.menuFamily
                      font.pixelSize: root.typeCaption
                      lineHeight: 1.3
                    }
                  }
                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Rectangle {
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(6)
                      width: Style.space(5)
                      height: width
                      radius: width / 2
                      color: root.mapMuted
                    }
                    Text {
                      id: placeSecondaryText
                      width: parent.width - Style.space(11)
                      text: placeRow.secondarySummaryText
                      textFormat: Text.PlainText
                      color: root.dim
                      wrapMode: placeRow.summaryExpanded ? Text.WordWrap : Text.NoWrap
                      elide: placeRow.summaryExpanded ? Text.ElideNone : Text.ElideRight
                      font.family: Style.font.menuFamily
                      font.pixelSize: root.typeCaption
                      lineHeight: 1.3
                    }
                  }
                }

                Row {
                  id: placeActions
                  visible: isSelected || root.pendingRemovePlaceId === place.id
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(7)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(5)
                  spacing: 1
                  z: 2

                  Button {
                    iconText: "\uf044"
                    tooltipText: "Edit " + String(place && place.name || "watched location")
                    focusable: true
                    foreground: root.dim
                    accent: root.accent
                    width: root.minimumTouchTarget
                    height: root.minimumTouchTarget
                    iconSize: root.typeCaption
                    horizontalPadding: 0
                    verticalPadding: 0
                    onClicked: root.beginEditWatchPlace(place.id)
                  }
                  Button {
                    iconText: root.pendingRemovePlaceId === place.id ? "\uf00c" : "\uf1f8"
                    tooltipText: root.pendingRemovePlaceId === place.id
                      ? "Click again to remove " + place.name : "Remove " + place.name
                    focusable: true
                    foreground: root.pendingRemovePlaceId === place.id ? root.urgent : root.dim
                    accent: root.urgent
                    width: root.minimumTouchTarget
                    height: root.minimumTouchTarget
                    iconSize: root.typeCaption
                    horizontalPadding: 0
                    verticalPadding: 0
                    onClicked: root.requestRemoveWatchPlace(place.id)
                  }
                }
                MouseArea {
                  id: placeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  z: 1
                  onClicked: root.selectWatchPlace(place.id)
                }
                Accessible.name: String(place && place.name || "Watched location") + ", "
                  + String(summary.status || "") + ", " + String(summary.detail || "")
                Accessible.role: Accessible.ListItem
              }

              QQC.ScrollBar.vertical: QQC.ScrollBar {
                policy: watchPlaceList.contentHeight > watchPlaceList.height
                  ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
              }
            }

            Button {
              id: addWatchLocation
              visible: root.tracker && root.tracker.watchPlacesLoaded
                && root.watchPlaces.length < 12
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(12)
              height: visible ? Style.space(42) : 0
              radius: Style.space(8)
              background: root.raisedSurface
              text: "ADD WATCHED LOCATION"
              iconText: "\uf067"
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: Style.font.menuFamily
              fontSize: root.typeCaption
              onClicked: root.beginAddWatchPlace()
            }

            Item {
              id: emptyPlaceState
              visible: root.tracker && root.tracker.watchPlacesLoaded && root.watchPlaces.length === 0
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: alertsSummary.bottom
              anchors.bottom: addWatchLocation.top
              anchors.bottomMargin: Style.space(10)

              Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(36)
                spacing: Style.space(8)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "\uf041"
                  color: root.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.space(22)
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "No alert destinations yet"
                  color: root.foreground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "Save home, family, or a destination. Alert locations remain on this computer."
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.typeCaption
                  lineHeight: 1.45
                }
              }
            }

            Text {
              visible: root.tracker && !root.tracker.watchPlacesLoaded
                && root.tracker.watchPlacesError === ""
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: alertsSummary.height / 2
              text: "Loading watched locations"
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Rectangle {
          id: dataFooter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.sidebarFooterHeight
          color: root.deepSurface
          z: 9

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: root.softBorder
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 5
              height: 5
              radius: 3
              color: !root.tracker || root.tracker.loading ? root.dim
                : (root.tracker.stale ? "#e9be62"
                  : (root.tracker.status !== "fresh" ? root.urgent
                    : (!root.tracker.outlookDataComplete ? "#e9be62" : "#45c6b5")))
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: !root.tracker || (!root.tracker.hasLoaded && root.tracker.loading)
                ? "CHECKING DATA" : (root.tracker.stale ? "SAVED DATA"
                  : (root.tracker.status !== "fresh" ? "DATA ISSUE"
                    : (!root.tracker.outlookDataComplete ? "DATA PARTIAL" : "DATA LIVE")))
              textFormat: Text.PlainText
              color: root.dim
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeCaption
              font.bold: true
              font.letterSpacing: 0.5
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: String(root.dataFeedCount) + (root.dataFeedCount === 1 ? " FEED" : " FEEDS")
              textFormat: Text.PlainText
              color: root.faint
              font.family: Style.font.menuFamily
              font.pixelSize: root.typeMicro
              font.bold: true
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(7)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Button {
              width: root.minimumTouchTarget
              height: root.minimumTouchTarget
              iconText: "\uf021"
              iconSpinning: root.tracker ? root.tracker.loading : false
              tooltipText: "Refresh data (R)"
              focusable: true
              foreground: root.dim
              accent: root.accent
              iconSize: root.typeCaption
              horizontalPadding: 0
              verticalPadding: 0
              onClicked: root.refresh()
            }
            Button {
              width: root.minimumTouchTarget
              height: root.minimumTouchTarget
              iconText: "\uf35d"
              tooltipText: "View source: National Hurricane Center"
              focusable: true
              foreground: root.dim
              accent: root.accent
              iconSize: root.typeCaption
              horizontalPadding: 0
              verticalPadding: 0
              onClicked: root.openBrowser("https://www.nhc.noaa.gov/")
            }
          }
        }

        Rectangle {
          id: discussionPanel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: dataFooter.top
          visible: root.sidebarMode === "activity" && root.selectedSystem
            && Model.discussionExcerpt(root.selectedSystem) !== ""
          height: visible ? Math.max(0, Math.min(
            sidebar.height * 0.30,
            Math.min(Style.space(250), Style.space(86)
              + Math.max(Style.space(68), Math.ceil(discussionText.implicitHeight))))) : 0
          color: root.shellSurface
          clip: true

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: root.softBorder
          }

          Text {
            id: discussionLabel
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.top: parent.top
            anchors.topMargin: Style.space(10)
            text: root.selectedOutlook ? "TROPICAL WEATHER OUTLOOK" : "FORECAST DISCUSSION"
            color: root.dim
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: root.typeCaption
            font.bold: true
            font.letterSpacing: 0.45
          }

          Flickable {
            id: discussionScroll
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
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
              font.pixelSize: root.typeCaption
              lineHeight: 1.5
            }

            QQC.ScrollBar.vertical: QQC.ScrollBar {
              policy: discussionScroll.contentHeight > discussionScroll.height
                ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
            }
          }

          Row {
            id: discussionActions
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.bottom: discussionSafety.top
            anchors.bottomMargin: Style.spacing.sm
            spacing: Style.spacing.sm

            Button {
              visible: root.selectedStorm !== null
              text: "Advisory"
              iconText: "\uf35d"
              height: root.minimumTouchTarget
              radius: root.minimumTouchTarget / 2
              focusable: true
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontSize: root.typeCaption
              iconSize: root.typeMicro
              horizontalPadding: Style.space(10)
              verticalPadding: 0
              enabled: root.officialUrl(root.selectedStorm, "advisoryUrl") !== ""
              onClicked: root.openOfficial(root.selectedStorm, "advisoryUrl")
            }
            Button {
              text: root.selectedOutlook ? "Full outlook" : "Full discussion"
              iconText: "\uf35d"
              height: root.minimumTouchTarget
              radius: root.minimumTouchTarget / 2
              focusable: true
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontSize: root.typeCaption
              iconSize: root.typeMicro
              horizontalPadding: Style.space(10)
              verticalPadding: 0
              enabled: root.officialUrl(root.selectedSystem, "discussionUrl") !== ""
              onClicked: root.openOfficial(root.selectedSystem, "discussionUrl")
            }
          }

          Text {
            id: discussionSafety
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(10)
            text: "Awareness only. Follow local alerts."
            textFormat: Text.PlainText
            color: root.dim
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: root.typeCaption
          }
        }
      }
    }
  }
}
