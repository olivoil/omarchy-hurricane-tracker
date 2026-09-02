import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var storms: []
  property var outlooks: []
  property var earthquakes: []
  property var watchPlaces: []
  property string mode: "cyclones"
  property string selectedKey: ""
  property string selectedPlaceId: ""
  property bool autoFitSelection: true
  property bool placementMode: false
  property var draftWatchPlace: null
  property bool useImperial: false
  property bool preferOverview: false
  property bool motionEnabled: false
  property bool layerSwitchInProgress: false
  readonly property var systems: mode === "earthquakes"
    ? Model.orderedEarthquakes(earthquakes) : Model.orderedSystems(storms, outlooks)
  readonly property var selectedSystem: Model.systemByKey(systems, selectedKey)
  readonly property bool selectedIsStorm: selectedSystem && selectedSystem.kind === "storm"

  property real centreLatitude: 18
  property real centreLongitude: -78
  property real zoom: 1
  property real minimumZoom: 0.94
  property real maximumZoom: 32
  property real bottomInset: 0
  property bool userMoved: false
  property real cameraOffsetY: 0
  property real layerSwitchLatitude: 0
  property real layerSwitchLongitude: 0
  property real layerSwitchMapCenterY: 0
  property real layerSwitchGlobeRadius: 0
  property real openingFlightTargetLongitude: 0
  property var openingArrivalPlace: null
  readonly property bool openingFlightRunning: openingFlight.running
  readonly property real viewHeight: Math.max(1, height - bottomInset)
  readonly property real mapCenterX: width / 2
  readonly property real mapCenterY: layerSwitchInProgress
    ? layerSwitchMapCenterY : viewHeight / 2 + cameraOffsetY
  readonly property real baseGlobeRadius: Math.max(80, Math.min(width, viewHeight) * 0.43)
  readonly property real globeRadius: layerSwitchInProgress
    ? layerSwitchGlobeRadius : baseGlobeRadius * zoom
  readonly property bool wholeGlobeVisible: globeRadius <= Math.min(width, viewHeight) / 2 - 8

  property color oceanColor: "#102f38"
  property color deepOceanColor: "#0a242c"
  property color landColor: "#42585a"
  property color landOutlineColor: "#6f8585"
  property color gridColor: "#9bb1b0"
  property color textColor: "#eef6f4"
  property color mutedTextColor: "#b1c4c1"
  property color coneColor: "#55c9d4"
  property color trackColor: "#eef6f4"
  property color surfaceColor: "#101b20"
  property color surfaceBorderColor: "#50636a"
  property string fontFamily: "sans-serif"

  property var countries: []
  property var preparedCountryRings: []
  property string hoveredKey: ""
  property string hoveredPlaceId: ""
  property var hoveredPoint: null
  property real hoverX: 0
  property real hoverY: 0
  property string hoverTitle: ""
  property string hoverDetail: ""

  signal systemActivated(string key)
  signal placeActivated(string identifier)
  signal placePicked(real latitude, real longitude)
  signal pointerActivity()

  Accessible.name: mode === "earthquakes" ? "Recent earthquakes map" : "NHC tropical systems map"
  Accessible.description: placementMode
    ? "Click the map to place a watch point, drag to pan, or use the wheel to zoom"
    : (mode === "earthquakes"
      ? "Drag to pan or rotate the globe, use the wheel to zoom, and select an earthquake marker"
      : "Drag to pan or rotate the globe, use the wheel to zoom, and select a cyclone, outlook, or watched-location marker")
  Accessible.role: Accessible.Pane

  function coordinateLatitude(value) {
    return Array.isArray(value) ? Number(value[1]) : Number(value && value.latitude)
  }

  function coordinateLongitude(value) {
    return Array.isArray(value) ? Number(value[0]) : Number(value && value.longitude)
  }

  function projectUnwrapped(latitude, longitude) {
    var sphere = Model.orthographicPoint(latitude, Model.wrapLongitude(longitude), centreLatitude, centreLongitude)
    return {
      x: mapCenterX + sphere.x * globeRadius,
      y: mapCenterY - sphere.y * globeRadius,
      visible: sphere.z >= -0.002,
      depth: sphere.z
    }
  }

  function project(latitude, longitude) {
    return projectUnwrapped(latitude, Model.longitudeNear(centreLongitude, longitude))
  }

  function unproject(x, y) {
    return Model.inverseOrthographic(
      (Number(x) - mapCenterX) / globeRadius,
      (mapCenterY - Number(y)) / globeRadius,
      centreLatitude,
      centreLongitude
    )
  }

  function applyBounds(bounds, coordinates, minimum) {
    cancelOpeningFlight()
    cameraOffsetY = 0
    var fit = Model.orthographicFit(coordinates, bounds)
    centreLatitude = fit.centreLatitude
    centreLongitude = fit.centreLongitude
    var horizontal = width * 0.38 / (baseGlobeRadius * fit.horizontalExtent)
    var vertical = viewHeight * 0.34 / (baseGlobeRadius * fit.verticalExtent)
    zoom = Model.clamp(Math.min(horizontal, vertical), minimum, maximumZoom)
    userMoved = false
    clearHover()
    canvas.requestPaint()
  }

  function fitSelected() {
    if (width < 40 || height < 40) return
    if (!selectedSystem) {
      showGlobe()
      return
    }
    applyBounds(Model.systemBounds(selectedSystem), Model.systemCoordinates(selectedSystem), 1.7)
  }

  function fitRegion(basin) {
    if (width < 40 || height < 40) return
    applyBounds(
      Model.regionBounds(storms, outlooks, basin),
      Model.regionCoordinates(storms, outlooks, basin),
      1.12
    )
  }

  function fitWatchPlace(place) {
    var normalized = Model.normalizeWatchPlace(place)
    if (width < 40 || height < 40 || !normalized) return
    applyBounds(
      Model.watchPlaceBounds(normalized),
      Model.watchCircleCoordinates(normalized, 48),
      1.35
    )
  }

  function focusWatchPlace(place) {
    if (width < 40 || height < 40) return
    cancelOpeningFlight()
    var focus = Model.watchPlaceFocus(place, zoom, minimumZoom, maximumZoom)
    if (!focus) return
    cameraOffsetY = 0
    centreLatitude = focus.centreLatitude
    centreLongitude = focus.centreLongitude
    zoom = focus.zoom
    userMoved = true
    clearHover()
    canvas.requestPaint()
  }

  function beginLayerSwitch() {
    cancelOpeningFlight()
    layerSwitchLatitude = centreLatitude
    layerSwitchLongitude = centreLongitude
    layerSwitchMapCenterY = mapCenterY
    layerSwitchGlobeRadius = globeRadius
    layerSwitchInProgress = true
    clearHover()
    canvas.requestPaint()
  }

  function finishLayerSwitch() {
    centreLatitude = layerSwitchLatitude
    centreLongitude = layerSwitchLongitude
    cameraOffsetY = layerSwitchMapCenterY - viewHeight / 2
    if (baseGlobeRadius > 0)
      zoom = layerSwitchGlobeRadius / baseGlobeRadius
    layerSwitchInProgress = false
    canvas.requestPaint()
  }

  function stopMomentum() {
    momentumAnimation.running = false
    pointer.velocityX = 0
    pointer.velocityY = 0
  }

  function finishMomentum() {
    stopMomentum()
    if (pointer.containsMouse && !pointer.pressed && !placementMode)
      updateHover(pointer.mouseX, pointer.mouseY)
  }

  function startMomentum() {
    if (!motionEnabled || pointer.travel < 7) {
      stopMomentum()
      return false
    }
    var sampleAge = Math.max(0, Date.now() - pointer.previousSampleTime)
    var retention = Math.exp(-sampleAge / 80)
    pointer.velocityX *= retention
    pointer.velocityY *= retention
    if (Math.hypot(pointer.velocityX, pointer.velocityY) < 18) {
      stopMomentum()
      return false
    }
    clearHover()
    momentumAnimation.running = true
    return true
  }

  function cancelOpeningFlight() {
    stopMomentum()
    var changed = false
    if (openingFlight.running) {
      openingFlight.stop()
      centreLongitude = Model.wrapLongitude(centreLongitude)
      changed = true
    }
    if (openingArrivalPlace) {
      openingArrivalPlace = null
      changed = true
    }
    if (changed) canvas.requestPaint()
  }

  function beginOpeningFlight(place, animate) {
    var normalized = Model.normalizeWatchPlace(place)
    if (width < 40 || height < 40 || !normalized) return false
    cancelOpeningFlight()
    cameraOffsetY = 0
    var focus = Model.watchPlaceFocus(
      normalized, minimumZoom, minimumZoom, maximumZoom)
    if (!focus) return false
    openingArrivalPlace = normalized
    if (animate !== true) {
      centreLatitude = focus.centreLatitude
      centreLongitude = focus.centreLongitude
      zoom = focus.zoom
      userMoved = true
      clearHover()
      openingArrivalPlace = null
      canvas.requestPaint()
      return true
    }

    var startLatitude = Model.clamp(focus.centreLatitude * 0.16, -10, 10)
    var startLongitude = focus.centreLongitude - 104
    centreLatitude = startLatitude
    centreLongitude = startLongitude
    zoom = minimumZoom
    userMoved = true
    clearHover()
    openingFlightTargetLongitude = focus.centreLongitude
    openingLatitude.from = startLatitude
    openingLatitude.to = focus.centreLatitude
    openingLongitude.from = startLongitude
    openingLongitude.to = focus.centreLongitude
    openingZoom.from = minimumZoom
    openingZoom.to = focus.zoom
    canvas.requestPaint()
    openingFlight.start()
    return true
  }

  function scheduleFitSelected(force) {
    if (layerSwitchInProgress) return
    var forceFit = force === true
    if (!autoFitSelection || openingFlight.running || (!forceFit && userMoved)) return
    Qt.callLater(function() {
      if (root.layerSwitchInProgress) return
      if (!root.autoFitSelection || openingFlight.running
          || (!forceFit && root.userMoved)) return
      root.syncSelectionView()
    })
  }

  function showGlobe(basin) {
    cancelOpeningFlight()
    cameraOffsetY = 0
    if (basin) {
      var bounds = Model.regionBounds(storms, outlooks, basin)
      centreLatitude = bounds.centreLatitude
      centreLongitude = bounds.centreLongitude
    } else if (selectedSystem) {
      centreLatitude = Model.clamp(Number(selectedSystem.latitude || 15), -55, 55)
      centreLongitude = Number(selectedSystem.longitude || -95)
    } else {
      centreLatitude = 14
      centreLongitude = -105
    }
    zoom = minimumZoom
    userMoved = true
    clearHover()
    canvas.requestPaint()
  }

  function zoomAt(amount, x, y) {
    cancelOpeningFlight()
    var anchorX = x === undefined ? mapCenterX : Number(x)
    var anchorY = y === undefined ? mapCenterY : Number(y)
    var coordinate = unproject(anchorX, anchorY)
    var anchorDistance = Math.hypot(anchorX - mapCenterX, anchorY - mapCenterY) / globeRadius
    var next = Model.clamp(zoom * amount, minimumZoom, maximumZoom)
    if (Math.abs(next - zoom) < 0.001) return
    zoom = next
    if (coordinate && anchorDistance < 0.9) {
      // Keep the geographic point beneath the pointer while the same sphere
      // grows or shrinks. A few small corrections converge quickly and avoid
      // introducing a second, flat projection for close views.
      for (var iteration = 0; iteration < 3; iteration++) {
        var after = unproject(anchorX, anchorY)
        if (!after) break
        var longitudeTarget = Model.longitudeNear(after.longitude, coordinate.longitude)
        centreLongitude = Model.wrapLongitude(centreLongitude + longitudeTarget - after.longitude)
        centreLatitude = Model.clamp(centreLatitude + coordinate.latitude - after.latitude, -82, 82)
      }
    }
    userMoved = true
    canvas.requestPaint()
  }

  function zoomIn() { zoomAt(1.32) }
  function zoomOut() { zoomAt(1 / 1.32) }
  function resetView() { fitSelected() }

  function syncSelectionView() {
    if (mode === "earthquakes" && preferOverview) showGlobe()
    else fitSelected()
  }

  function clearHover() {
    hoveredKey = ""
    hoveredPlaceId = ""
    hoveredPoint = null
    hoverTitle = ""
    hoverDetail = ""
  }

  function nearestSystem(x, y, radius) {
    var best = null
    var bestDistance = radius
    for (var i = 0; i < systems.length; i++) {
      var system = systems[i]
      if (!system || !Model.validCoordinate(system.latitude, system.longitude)) continue
      var point = project(system.latitude, system.longitude)
      if (!point.visible) continue
      var distance = Math.hypot(point.x - x, point.y - y)
      if (distance <= bestDistance) {
        bestDistance = distance
        best = system
      }
    }
    return best
  }

  function nearestWatchPlace(x, y, radius) {
    if (mode !== "cyclones") return null
    var rows = Array.isArray(watchPlaces) ? watchPlaces : []
    var best = null
    var bestDistance = radius
    for (var i = 0; i < rows.length; i++) {
      var place = Model.normalizeWatchPlace(rows[i])
      if (!place) continue
      var point = project(place.latitude, place.longitude)
      if (!point.visible) continue
      var distance = Math.hypot(point.x - x, point.y - y)
      if (distance <= bestDistance) {
        bestDistance = distance
        best = place
      }
    }
    return best
  }

  function nearestForecastPoint(x, y, radius) {
    var rows = selectedIsStorm && Array.isArray(selectedSystem.track) ? selectedSystem.track : []
    var best = null
    var bestDistance = radius
    for (var i = 0; i < rows.length; i++) {
      var point = project(rows[i].latitude, rows[i].longitude)
      if (!point.visible) continue
      var distance = Math.hypot(point.x - x, point.y - y)
      if (distance <= bestDistance) {
        bestDistance = distance
        best = rows[i]
      }
    }
    return best
  }

  function updateHover(x, y) {
    hoverX = x
    hoverY = y
    var forecast = mode === "cyclones" ? nearestForecastPoint(x, y, 13) : null
    if (forecast) {
      hoveredPoint = forecast
      hoveredKey = ""
      hoverTitle = Model.forecastHourLabel(forecast) + " · " + Model.classificationLabel(forecast)
      hoverDetail = Model.forecastTimeLabel(forecast) + " · "
        + Model.formatWind(forecast, useImperial)
      canvas.requestPaint()
      return
    }
    var system = nearestSystem(x, y, 22)
    hoveredPoint = null
    hoveredKey = system ? system.key : ""
    hoveredPlaceId = ""
    if (system) {
      hoverTitle = String(system.name || system.title || (mode === "earthquakes"
        ? "Earthquake" : "Tropical system"))
      hoverDetail = system.kind === "earthquake"
        ? Model.earthquakeMagnitudeLabel(system) + " · " + Model.systemMetric(system, useImperial)
        : Model.systemClassificationLabel(system) + " · " + Model.systemMetric(system, useImperial)
    } else {
      var place = nearestWatchPlace(x, y, 16)
      hoveredPlaceId = place ? place.id : ""
      hoverTitle = place ? place.name : ""
      hoverDetail = place ? "Saved alert destination · NHC coverage" : ""
    }
    canvas.requestPaint()
  }

  function beginGeoPath(context, coordinates, closePath) {
    var rows = Array.isArray(coordinates) ? coordinates : []
    if (rows.length === 0) return false
    if (closePath) {
      var fragments = Model.clippedHemisphereRings(
        rows, centreLatitude, centreLongitude)
      var anyFragment = false
      context.beginPath()
      for (var fragmentIndex = 0; fragmentIndex < fragments.length; fragmentIndex++) {
        var fragmentPoints = fragments[fragmentIndex].points
        if (!Array.isArray(fragmentPoints) || fragmentPoints.length < 3) continue
        for (var fragmentPointIndex = 0;
            fragmentPointIndex < fragmentPoints.length; fragmentPointIndex++) {
          var spherePoint = fragmentPoints[fragmentPointIndex]
          var fragmentX = mapCenterX + spherePoint.x * globeRadius
          var fragmentY = mapCenterY - spherePoint.y * globeRadius
          if (fragmentPointIndex === 0) context.moveTo(fragmentX, fragmentY)
          else context.lineTo(fragmentX, fragmentY)
        }
        context.closePath()
        anyFragment = true
      }
      return anyFragment
    }
    var previousLongitude = Model.longitudeNear(centreLongitude, coordinateLongitude(rows[0]))
    var started = false
    context.beginPath()
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) previousLongitude = Model.longitudeNear(previousLongitude, coordinateLongitude(rows[i]))
      var point = projectUnwrapped(coordinateLatitude(rows[i]), previousLongitude)
      if (!point.visible) {
        started = false
        continue
      }
      if (!started) {
        context.moveTo(point.x, point.y)
        started = true
      } else {
        context.lineTo(point.x, point.y)
      }
    }
    return started
  }

  function drawBackground(context) {
    context.globalAlpha = 1
    context.fillStyle = deepOceanColor
    context.fillRect(0, 0, width, height)
    context.fillStyle = oceanColor
    context.beginPath()
    context.arc(mapCenterX, mapCenterY, globeRadius, 0, Math.PI * 2)
    context.fill()
    context.strokeStyle = Qt.rgba(coneColor.r, coneColor.g, coneColor.b, wholeGlobeVisible ? 0.52 : 0.28)
    context.lineWidth = wholeGlobeVisible ? 2 : 1
    context.stroke()
    context.globalAlpha = 1
  }

  function clipToGlobe(context) {
    context.beginPath()
    context.arc(mapCenterX, mapCenterY, globeRadius - 1, 0, Math.PI * 2)
    context.clip()
  }

  function drawGrid(context) {
    var spacing = zoom < 1.6 ? 30 : (zoom < 4.5 ? 10 : (zoom < 12 ? 5 : 2))
    context.lineWidth = 0.8
    context.strokeStyle = Qt.rgba(gridColor.r, gridColor.g, gridColor.b, zoom < 2 ? 0.15 : 0.20)
    for (var longitude = -180; longitude < 180; longitude += spacing) {
      var meridian = []
      for (var latitude = -90; latitude <= 90; latitude += 3) meridian.push([longitude, latitude])
      if (beginGeoPath(context, meridian, false)) context.stroke()
    }
    for (var parallel = -60; parallel <= 60; parallel += spacing) {
      var latitudeLine = []
      for (var lon = -180; lon <= 180; lon += 4) latitudeLine.push([lon, parallel])
      if (beginGeoPath(context, latitudeLine, false)) context.stroke()
    }
  }

  function prepareCountryGeometry(rows) {
    var prepared = []
    var features = Array.isArray(rows) ? rows : []
    for (var featureIndex = 0; featureIndex < features.length; featureIndex++) {
      var geometry = features[featureIndex] && features[featureIndex].geometry
      var polygons = geometry && Array.isArray(geometry.coordinates)
        ? geometry.coordinates : []
      for (var polygonIndex = 0; polygonIndex < polygons.length; polygonIndex++) {
        var ring = polygons[polygonIndex] && polygons[polygonIndex][0]
        var points = Model.prepareHemisphereRing(ring)
        if (points.length >= 3) prepared.push(points)
      }
    }
    return prepared
  }

  function paintCountryRing(context, preparedRing) {
    var fragments = Model.clippedPreparedHemisphereRings(
      preparedRing, centreLatitude, centreLongitude)
    for (var fragmentIndex = 0; fragmentIndex < fragments.length; fragmentIndex++) {
      var fragment = fragments[fragmentIndex]
      var points = fragment.points
      if (!Array.isArray(points) || points.length < 3) continue
      context.beginPath()
      for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
        var point = points[pointIndex]
        var x = mapCenterX + point.x * globeRadius
        var y = mapCenterY - point.y * globeRadius
        if (pointIndex === 0) context.moveTo(x, y)
        else context.lineTo(x, y)
      }
      context.closePath()
      context.fill()

      context.beginPath()
      for (var boundaryIndex = 0;
          boundaryIndex < fragment.boundaryLength; boundaryIndex++) {
        var boundaryPoint = points[boundaryIndex]
        var boundaryX = mapCenterX + boundaryPoint.x * globeRadius
        var boundaryY = mapCenterY - boundaryPoint.y * globeRadius
        if (boundaryIndex === 0) context.moveTo(boundaryX, boundaryY)
        else context.lineTo(boundaryX, boundaryY)
      }
      if (!fragment.clipped) context.closePath()
      context.stroke()
    }
  }

  function drawCountries(context) {
    context.fillStyle = landColor
    context.strokeStyle = Qt.rgba(landOutlineColor.r, landOutlineColor.g, landOutlineColor.b, 0.76)
    context.lineWidth = zoom < 3 ? 0.75 : 1.0
    context.lineJoin = "round"
    var rows = Array.isArray(preparedCountryRings) ? preparedCountryRings : []
    for (var i = 0; i < rows.length; i++) {
      paintCountryRing(context, rows[i])
    }
  }

  function drawCountryLabels(context) {
    if (zoom < 1.3) return
    var rows = Array.isArray(countries) ? countries : []
    var maximumRank = zoom < 2.3 ? 2 : (zoom < 5 ? 4 : 6)
    context.textAlign = "center"
    context.textBaseline = "middle"
    context.font = "600 " + Math.round(Math.min(13, 9 + Math.sqrt(zoom))) + "px '" + fontFamily + "'"
    context.fillStyle = Qt.rgba(textColor.r, textColor.g, textColor.b, zoom < 2 ? 0.54 : 0.68)
    for (var i = 0; i < rows.length; i++) {
      var properties = rows[i] && rows[i].properties
      if (!properties || Number(properties.labelRank || 9) > maximumRank) continue
      if (!Model.validCoordinate(properties.labelLatitude, properties.labelLongitude)) continue
      var point = project(properties.labelLatitude, properties.labelLongitude)
      if (!point.visible || point.x < 20 || point.x > width - 20 || point.y < 20 || point.y > height - 20) continue
      context.fillText(String(properties.name || "").toUpperCase(), point.x, point.y)
    }
  }

  function drawWatchPlace(context, requested, draft) {
    var place = Model.normalizeWatchPlace(requested)
    if (!place) return
    var selected = draft || place.id === selectedPlaceId
    var hovered = place.id === hoveredPlaceId
    if (draft) {
      var ring = Model.watchCircleCoordinates(place, zoom < 2 ? 36 : 64)
      context.strokeStyle = Qt.rgba(coneColor.r, coneColor.g, coneColor.b, 0.82)
      context.fillStyle = Qt.rgba(coneColor.r, coneColor.g, coneColor.b, 0.055)
      context.lineWidth = 1.6
      if (context.setLineDash) context.setLineDash([3, 4])
      if (beginGeoPath(context, ring, true)) {
        context.fill()
        context.stroke()
      }
      if (context.setLineDash) context.setLineDash([])
    }

    var point = project(place.latitude, place.longitude)
    if (!point.visible || point.x < -50 || point.x > width + 50
        || point.y < -50 || point.y > height + 50) return
    var radius = selected || hovered ? 6 : 4.5
    context.fillStyle = surfaceColor
    context.strokeStyle = selected || hovered ? coneColor : mutedTextColor
    context.lineWidth = selected ? 2 : 1.4
    context.beginPath()
    context.arc(point.x, point.y, radius, 0, Math.PI * 2)
    context.fill()
    context.stroke()
    context.fillStyle = selected || hovered ? coneColor : mutedTextColor
    context.beginPath()
    context.arc(point.x, point.y, 1.8, 0, Math.PI * 2)
    context.fill()
    if (selected || hovered || zoom >= 2.2) {
      context.textAlign = "left"
      context.textBaseline = "middle"
      context.font = "700 " + (selected ? 12 : 10) + "px '" + fontFamily + "'"
      context.fillStyle = selected ? textColor : mutedTextColor
      context.fillText(String(place.name || "WATCH PLACE").toUpperCase(), point.x + radius + 7, point.y)
    }
  }

  function drawOpeningArrival(context) {
    var place = Model.normalizeWatchPlace(openingArrivalPlace)
    if (!place) return
    var point = project(place.latitude, place.longitude)
    if (!point.visible || point.x < -90 || point.x > width + 90
        || point.y < -40 || point.y > height + 40) return
    var radius = 6
    context.fillStyle = surfaceColor
    context.strokeStyle = coneColor
    context.lineWidth = 1.8
    context.beginPath()
    context.arc(point.x, point.y, radius, 0, Math.PI * 2)
    context.fill()
    context.stroke()
    context.fillStyle = coneColor
    context.beginPath()
    context.arc(point.x, point.y, 2, 0, Math.PI * 2)
    context.fill()
    context.textAlign = "left"
    context.textBaseline = "middle"
    context.font = "700 10px '" + fontFamily + "'"
    context.fillStyle = textColor
    context.fillText("YOUR LOCATION · " + String(place.name || "LOCATION").toUpperCase(),
      point.x + radius + 7, point.y)
  }

  function drawCone(context, storm) {
    var rings = storm && Array.isArray(storm.cone) ? storm.cone : []
    context.fillStyle = Qt.rgba(coneColor.r, coneColor.g, coneColor.b, 0.22)
    context.strokeStyle = Qt.rgba(coneColor.r, coneColor.g, coneColor.b, 0.88)
    context.lineWidth = 1.4
    for (var i = 0; i < rings.length; i++) {
      if (!beginGeoPath(context, rings[i], true)) continue
      context.fill()
      context.stroke()
    }
  }

  function drawPath(context, rows, color, widthValue, dashed) {
    if (!Array.isArray(rows) || rows.length < 2 || !beginGeoPath(context, rows, false)) return
    context.strokeStyle = color
    context.lineWidth = widthValue
    context.lineCap = "round"
    context.lineJoin = "round"
    if (context.setLineDash) context.setLineDash(dashed ? [6, 6] : [])
    context.stroke()
    if (context.setLineDash) context.setLineDash([])
  }

  function drawPastTrack(context, storm) {
    var rows = storm && Array.isArray(storm.pastTrack) ? storm.pastTrack.slice() : []
    if (rows.length > 0) rows.push({ latitude: storm.latitude, longitude: storm.longitude })
    drawPath(context, rows, Qt.rgba(trackColor.r, trackColor.g, trackColor.b, 0.50), 1.8, true)
  }

  function drawForecastTrack(context, storm) {
    var rows = storm && Array.isArray(storm.track) ? storm.track : []
    drawPath(context, rows, Qt.rgba(trackColor.r, trackColor.g, trackColor.b, 0.94), 2.4, false)
    context.textAlign = "center"
    context.textBaseline = "bottom"
    context.font = "700 11px '" + fontFamily + "'"
    for (var i = 0; i < rows.length; i++) {
      var forecast = rows[i]
      if (Number(forecast.forecastHour || 0) === 0) continue
      var point = project(forecast.latitude, forecast.longitude)
      if (!point.visible || point.x < -20 || point.x > width + 20 || point.y < -20 || point.y > height + 20) continue
      var color = Model.severityColor(forecast)
      var radius = hoveredPoint === forecast ? 7 : 5
      context.fillStyle = color
      context.strokeStyle = deepOceanColor
      context.lineWidth = 2
      context.beginPath()
      context.arc(point.x, point.y, radius, 0, Math.PI * 2)
      context.fill()
      context.stroke()
      if (zoom >= 2.2) {
        context.fillStyle = textColor
        context.fillText(Model.forecastHourLabel(forecast), point.x, point.y - radius - 4)
      }
    }
  }

  function drawOutlookConnector(context, outlook, color, selected) {
    var rows = outlook && Array.isArray(outlook.connector) ? outlook.connector : []
    if (rows.length < 2) return

    var lineColor = Qt.rgba(color.r, color.g, color.b, selected ? 0.96 : 0.76)
    drawPath(context, rows, lineColor, selected ? 2.5 : 1.8, false)

    var previous = rows[rows.length - 2]
    var last = rows[rows.length - 1]
    var previousLongitude = Model.longitudeNear(
      centreLongitude, coordinateLongitude(previous))
    var lastLongitude = Model.longitudeNear(
      previousLongitude, coordinateLongitude(last))
    var previousPoint = projectUnwrapped(coordinateLatitude(previous), previousLongitude)
    var lastPoint = projectUnwrapped(coordinateLatitude(last), lastLongitude)
    if (!previousPoint.visible || !lastPoint.visible) return

    var dx = lastPoint.x - previousPoint.x
    var dy = lastPoint.y - previousPoint.y
    if (Math.sqrt(dx * dx + dy * dy) < 4) return
    var arrowSize = selected ? 9 : 7
    context.save()
    context.translate(lastPoint.x, lastPoint.y)
    context.rotate(Math.atan2(dy, dx))
    context.fillStyle = lineColor
    context.beginPath()
    context.moveTo(0, 0)
    context.lineTo(-arrowSize, -arrowSize * 0.52)
    context.lineTo(-arrowSize, arrowSize * 0.52)
    context.closePath()
    context.fill()
    context.restore()
  }

  function drawOutlook(context, outlook) {
    var selected = outlook.key === selectedKey
    var hovered = outlook.key === hoveredKey
    var color = Qt.color(Model.outlookColor(outlook))
    var rings = Array.isArray(outlook.area) ? outlook.area : []
    context.fillStyle = Qt.rgba(color.r, color.g, color.b, selected ? 0.25 : 0.10)
    context.strokeStyle = Qt.rgba(color.r, color.g, color.b, selected ? 0.96 : 0.62)
    context.lineWidth = selected ? 2 : 1.2
    if (context.setLineDash) context.setLineDash(selected ? [7, 5] : [4, 6])
    for (var r = 0; r < rings.length; r++) {
      if (!beginGeoPath(context, rings[r], true)) continue
      context.fill()
      context.stroke()
    }
    if (context.setLineDash) context.setLineDash([])
    drawOutlookConnector(context, outlook, color, selected)

    var point = project(outlook.latitude, outlook.longitude)
    if (!point.visible) return
    var radius = selected ? 13 : 10
    if (selected || hovered) {
      context.strokeStyle = Qt.rgba(textColor.r, textColor.g, textColor.b, selected ? 0.76 : 0.48)
      context.lineWidth = 1.5
      context.beginPath()
      context.arc(point.x, point.y, radius + 5, 0, Math.PI * 2)
      context.stroke()
    }
    context.fillStyle = color
    context.strokeStyle = deepOceanColor
    context.lineWidth = 2
    context.beginPath()
    context.arc(point.x, point.y, radius, 0, Math.PI * 2)
    context.fill()
    context.stroke()
    context.strokeStyle = "#f7faf9"
    context.lineWidth = 2
    context.beginPath()
    context.moveTo(point.x - radius * 0.35, point.y - radius * 0.35)
    context.lineTo(point.x + radius * 0.35, point.y + radius * 0.35)
    context.moveTo(point.x + radius * 0.35, point.y - radius * 0.35)
    context.lineTo(point.x - radius * 0.35, point.y + radius * 0.35)
    context.stroke()
    if (selected || zoom >= 1.75) {
      context.textAlign = "left"
      context.textBaseline = "middle"
      context.font = "700 " + (selected ? 13 : 11) + "px '" + fontFamily + "'"
      context.fillStyle = textColor
      context.fillText(String(outlook.name || outlook.title || "OUTLOOK").toUpperCase(), point.x + radius + 8, point.y - 1)
    }
  }

  function earthquakeRadius(earthquake, selected) {
    var magnitude = Model.clamp(Number(earthquake && earthquake.magnitude || 4.5), 4.5, 9.5)
    return Model.clamp(6 + (magnitude - 4.5) * 2.6 + (selected ? 2 : 0), 6, 20)
  }

  function earthquakeAgeOpacity(earthquake) {
    var occurred = Date.parse(String(earthquake && earthquake.occurredAt || ""))
    if (!isFinite(occurred)) return 0.62
    var hours = Math.max(0, (Date.now() - occurred) / (60 * 60 * 1000))
    if (hours <= 24) return 0.92
    return Model.clamp(0.82 - (hours - 24) / (6 * 24) * 0.34, 0.48, 0.82)
  }

  function drawEarthquakeMarker(context, earthquake) {
    if (!earthquake || !Model.validCoordinate(earthquake.latitude, earthquake.longitude)) return
    var point = project(earthquake.latitude, earthquake.longitude)
    if (!point.visible || point.x < -70 || point.x > width + 70
        || point.y < -70 || point.y > height + 70) return
    var selected = earthquake.key === selectedKey
    var hovered = earthquake.key === hoveredKey
    var radius = earthquakeRadius(earthquake, selected)
    var color = Qt.color(Model.earthquakeColor(earthquake))

    if (selected || hovered) {
      context.strokeStyle = Qt.rgba(textColor.r, textColor.g, textColor.b,
        selected ? 0.80 : 0.46)
      context.lineWidth = selected ? 2 : 1.5
      context.beginPath()
      context.arc(point.x, point.y, radius + 5, 0, Math.PI * 2)
      context.stroke()
    }

    context.fillStyle = Qt.rgba(color.r, color.g, color.b,
      earthquakeAgeOpacity(earthquake))
    context.strokeStyle = deepOceanColor
    context.lineWidth = 2
    if (context.setLineDash)
      context.setLineDash(String(earthquake.reviewStatus || "") === "automatic" ? [3, 2] : [])
    context.beginPath()
    context.arc(point.x, point.y, radius, 0, Math.PI * 2)
    context.fill()
    context.stroke()
    if (context.setLineDash) context.setLineDash([])

    context.fillStyle = Qt.rgba(textColor.r, textColor.g, textColor.b, 0.88)
    context.beginPath()
    context.arc(point.x, point.y, Math.max(1.5, radius * 0.16), 0, Math.PI * 2)
    context.fill()

    var magnitude = Number(earthquake.magnitude || 0)
    if (selected || hovered || (zoom >= 2.5 && magnitude >= 5.5) || zoom >= 4.5) {
      var place = String(earthquake.name || "Earthquake").toUpperCase()
      if (place.length > 42) place = place.slice(0, 39) + "…"
      context.textAlign = "left"
      context.textBaseline = "middle"
      context.font = "700 " + (selected ? 12 : 10) + "px '" + fontFamily + "'"
      context.fillStyle = textColor
      context.fillText(Model.earthquakeMagnitudeLabel(earthquake) + " · " + place,
        point.x + radius + 8, point.y - 1)
    }
  }

  function drawStormMarker(context, storm) {
    if (!storm || !Model.validCoordinate(storm.latitude, storm.longitude)) return
    var point = project(storm.latitude, storm.longitude)
    if (!point.visible || point.x < -60 || point.x > width + 60 || point.y < -60 || point.y > height + 60) return
    var selected = storm.key === selectedKey
    var hovered = storm.key === hoveredKey
    var radius = selected ? 15 : 11
    var color = Model.severityColor(storm)
    if (selected || hovered) {
      context.strokeStyle = Qt.rgba(textColor.r, textColor.g, textColor.b, selected ? 0.76 : 0.48)
      context.lineWidth = selected ? 2 : 1.5
      context.beginPath()
      context.arc(point.x, point.y, radius + 5, 0, Math.PI * 2)
      context.stroke()
    }
    context.fillStyle = color
    context.strokeStyle = deepOceanColor
    context.lineWidth = 2.2
    context.beginPath()
    context.arc(point.x, point.y, radius, 0, Math.PI * 2)
    context.fill()
    context.stroke()
    context.strokeStyle = "#f7faf9"
    context.lineWidth = Math.max(1.5, radius * 0.15)
    context.lineCap = "round"
    context.beginPath()
    context.arc(point.x - radius * 0.23, point.y - radius * 0.06, radius * 0.42, 0.15, 4.25)
    context.stroke()
    context.beginPath()
    context.arc(point.x + radius * 0.23, point.y + radius * 0.06, radius * 0.42, 3.3, 7.4)
    context.stroke()
    context.textAlign = "left"
    context.textBaseline = "middle"
    context.font = "700 " + (selected ? 13 : 11) + "px '" + fontFamily + "'"
    context.fillStyle = textColor
    context.fillText(String(storm.name || "").toUpperCase(), point.x + radius + 8, point.y - 1)
  }

  function paint(context) {
    context.clearRect(0, 0, width, height)
    drawBackground(context)
    context.save()
    clipToGlobe(context)
    drawGrid(context)
    drawCountries(context)
    drawCountryLabels(context)
    if (mode === "earthquakes") {
      for (var e = 0; e < systems.length; e++) drawEarthquakeMarker(context, systems[e])
      drawOpeningArrival(context)
    } else {
      var draftId = draftWatchPlace ? String(draftWatchPlace.id || "") : ""
      for (var w = 0; w < watchPlaces.length; w++) {
        if (draftId && String(watchPlaces[w] && watchPlaces[w].id || "") === draftId) continue
        drawWatchPlace(context, watchPlaces[w], false)
      }
      if (draftWatchPlace) drawWatchPlace(context, draftWatchPlace, true)
      for (var o = 0; o < systems.length; o++)
        if (systems[o].kind === "outlook") drawOutlook(context, systems[o])
      if (selectedIsStorm) {
        drawCone(context, selectedSystem)
        drawPastTrack(context, selectedSystem)
        drawForecastTrack(context, selectedSystem)
      }
      for (var s = 0; s < systems.length; s++)
        if (systems[s].kind === "storm") drawStormMarker(context, systems[s])
    }
    context.restore()
    context.strokeStyle = Qt.rgba(textColor.r, textColor.g, textColor.b, wholeGlobeVisible ? 0.24 : 0.12)
    context.lineWidth = 1
    context.beginPath()
    context.arc(mapCenterX, mapCenterY, globeRadius + 3, 0, Math.PI * 2)
    context.stroke()
  }

  ParallelAnimation {
    id: openingFlight

    NumberAnimation {
      id: openingLatitude
      target: root
      property: "centreLatitude"
      duration: 1080
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      id: openingLongitude
      target: root
      property: "centreLongitude"
      duration: 1080
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      id: openingZoom
      target: root
      property: "zoom"
      duration: 1080
      easing.type: Easing.InOutSine
    }
    onFinished: {
      root.centreLongitude = Model.wrapLongitude(root.openingFlightTargetLongitude)
      root.openingArrivalPlace = null
      canvas.requestPaint()
    }
  }

  FileView {
    path: Qt.resolvedUrl("assets/countries.json").toString().replace(/^file:\/\//, "")
    watchChanges: false
    printErrors: true
    onLoaded: {
      try {
        var collection = JSON.parse(text())
        root.countries = Array.isArray(collection.features) ? collection.features : []
        root.preparedCountryRings = root.prepareCountryGeometry(root.countries)
      } catch (error) {
        root.countries = []
        root.preparedCountryRings = []
      }
      canvas.requestPaint()
    }
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    renderStrategy: Canvas.Immediate
    onPaint: root.paint(getContext("2d"))
  }

  FrameAnimation {
    id: momentumAnimation
    running: false

    onTriggered: {
      if (!root.motionEnabled || pointer.pressed || !root.visible) {
        root.stopMomentum()
        return
      }
      var elapsed = Math.max(1, frameTime * 1000)
      var step = Model.dragMomentumStep(pointer.velocityX, pointer.velocityY, elapsed)
      pointer.velocityX = step.velocityX
      pointer.velocityY = step.velocityY

      var latitudeDegreesPerPixel = 57.2957795 / root.globeRadius
      var longitudeDegreesPerPixel = latitudeDegreesPerPixel
        / Math.max(0.28, Math.cos(root.centreLatitude * Math.PI / 180))
      root.centreLongitude = Model.wrapLongitude(
        root.centreLongitude - step.deltaX * longitudeDegreesPerPixel)
      var unclampedLatitude = root.centreLatitude
        + step.deltaY * latitudeDegreesPerPixel
      var nextLatitude = Model.clamp(unclampedLatitude, -82, 82)
      root.centreLatitude = nextLatitude
      if (Math.abs(unclampedLatitude - nextLatitude) > 0.000001)
        pointer.velocityY = 0
      root.userMoved = true

      if (!step.active || Math.hypot(pointer.velocityX, pointer.velocityY) < 18)
        root.finishMomentum()
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: root.placementMode ? Qt.CrossCursor
      : (pressed ? Qt.ClosedHandCursor
        : (root.hoveredKey !== "" || root.hoveredPlaceId !== "" || root.hoveredPoint
          ? Qt.PointingHandCursor : Qt.OpenHandCursor))
    property real previousX: 0
    property real previousY: 0
    property real travel: 0
    property real velocityX: 0
    property real velocityY: 0
    property double previousSampleTime: 0
    property bool interruptedMomentum: false

    onPressed: function(mouse) {
      interruptedMomentum = momentumAnimation.running
      root.cancelOpeningFlight()
      previousX = mouse.x
      previousY = mouse.y
      travel = 0
      velocityX = 0
      velocityY = 0
      previousSampleTime = Date.now()
      root.pointerActivity()
    }
    onPositionChanged: function(mouse) {
      if (pressed) {
        var dx = mouse.x - previousX
        var dy = mouse.y - previousY
        var now = Date.now()
        var elapsed = now - previousSampleTime
        travel += Math.abs(dx) + Math.abs(dy)
        if (elapsed > 0 && (dx !== 0 || dy !== 0)) {
          velocityX = Model.dragVelocity(velocityX, dx, elapsed)
          velocityY = Model.dragVelocity(velocityY, dy, elapsed)
          previousSampleTime = now
        }
        var latitudeDegreesPerPixel = 57.2957795 / root.globeRadius
        var longitudeDegreesPerPixel = latitudeDegreesPerPixel
          / Math.max(0.28, Math.cos(root.centreLatitude * Math.PI / 180))
        root.centreLongitude = Model.wrapLongitude(root.centreLongitude - dx * longitudeDegreesPerPixel)
        root.centreLatitude = Model.clamp(root.centreLatitude + dy * latitudeDegreesPerPixel, -82, 82)
        root.userMoved = true
        previousX = mouse.x
        previousY = mouse.y
        root.clearHover()
        canvas.requestPaint()
      } else {
        root.updateHover(mouse.x, mouse.y)
      }
      root.pointerActivity()
    }
    onReleased: function(mouse) {
      if (travel < 7 && !interruptedMomentum) {
        if (root.placementMode) {
          var coordinate = root.unproject(mouse.x, mouse.y)
          if (coordinate) root.placePicked(coordinate.latitude, coordinate.longitude)
        } else {
          var system = root.nearestSystem(mouse.x, mouse.y, 25)
          var place = system ? null : root.nearestWatchPlace(mouse.x, mouse.y, 18)
          if (system) root.systemActivated(system.key)
          else if (place) root.placeActivated(place.id)
        }
      }
      var momentumStarted = root.startMomentum()
      if (!momentumStarted && !root.placementMode)
        root.updateHover(mouse.x, mouse.y)
      interruptedMomentum = false
    }
    onCanceled: {
      interruptedMomentum = false
      root.stopMomentum()
    }
    onExited: {
      if (!pressed) root.clearHover()
      canvas.requestPaint()
    }
    onWheel: function(wheel) {
      root.cancelOpeningFlight()
      root.zoomAt(wheel.angleDelta.y > 0 ? 1.22 : 1 / 1.22, wheel.x, wheel.y)
      root.pointerActivity()
      wheel.accepted = true
    }
  }

  Rectangle {
    visible: root.wholeGlobeVisible
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.bottomInset + 16
    width: globeLabel.implicitWidth + 24
    height: 28
    radius: height / 2
    color: root.surfaceColor
    border.width: 1
    border.color: root.surfaceBorderColor
    z: 4

    Text {
      id: globeLabel
      anchors.centerIn: parent
      text: "GLOBE · DRAG TO ROTATE"
      color: root.mutedTextColor
      font.family: root.fontFamily
      font.pixelSize: 11
      font.bold: true
      font.letterSpacing: 0.5
    }
  }

  Rectangle {
    id: tooltip
    visible: root.hoverTitle !== ""
    x: Math.max(12, Math.min(root.width - width - 12, root.hoverX + 16))
    y: Math.max(12, Math.min(root.height - height - 12, root.hoverY + 16))
    width: Math.max(titleText.implicitWidth, detailText.implicitWidth) + 24
    height: titleText.implicitHeight + detailText.implicitHeight + 18
    radius: 7
    color: root.surfaceColor
    border.width: 1
    border.color: root.surfaceBorderColor
    z: 5

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.top: parent.top
      anchors.topMargin: 8
      text: root.hoverTitle
      textFormat: Text.PlainText
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: true
    }
    Text {
      id: detailText
      anchors.left: titleText.left
      anchors.top: titleText.bottom
      anchors.topMargin: 2
      text: root.hoverDetail
      textFormat: Text.PlainText
      color: root.mutedTextColor
      font.family: root.fontFamily
      font.pixelSize: 11
    }
  }

  onStormsChanged: canvas.requestPaint()
  onOutlooksChanged: canvas.requestPaint()
  onEarthquakesChanged: canvas.requestPaint()
  onWatchPlacesChanged: canvas.requestPaint()
  onModeChanged: {
    cancelOpeningFlight()
    clearHover()
    canvas.requestPaint()
    if (!layerSwitchInProgress) scheduleFitSelected(true)
  }
  onSelectedKeyChanged: scheduleFitSelected(true)
  onPreferOverviewChanged: if (mode === "earthquakes") scheduleFitSelected(true)
  onSelectedPlaceIdChanged: canvas.requestPaint()
  onDraftWatchPlaceChanged: canvas.requestPaint()
  onPlacementModeChanged: {
    clearHover()
    canvas.requestPaint()
  }
  onCentreLatitudeChanged: canvas.requestPaint()
  onCentreLongitudeChanged: canvas.requestPaint()
  onZoomChanged: canvas.requestPaint()
  onWidthChanged: scheduleFitSelected(false)
  onHeightChanged: scheduleFitSelected(false)
  onBottomInsetChanged: scheduleFitSelected(false)
  onOceanColorChanged: canvas.requestPaint()
  onLandColorChanged: canvas.requestPaint()
  onConeColorChanged: canvas.requestPaint()
  onMotionEnabledChanged: if (!motionEnabled) stopMomentum()
  onVisibleChanged: if (!visible) stopMomentum()
  Component.onCompleted: scheduleFitSelected(true)
}
