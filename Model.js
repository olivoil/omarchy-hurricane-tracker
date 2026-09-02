function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, Number(value)))
}

function wheelScrollDistance(pixelDeltaY, angleDeltaY, discreteStep) {
  var pixels = Number(pixelDeltaY)
  if (isFinite(pixels) && pixels !== 0) return -pixels

  var angle = Number(angleDeltaY)
  if (!isFinite(angle) || angle === 0) return 0
  var step = Number(discreteStep)
  if (!isFinite(step) || step <= 0) step = 272
  return -angle / 120 * step
}

function dragVelocity(previousVelocity, deltaPixels, elapsedMilliseconds) {
  var previous = Number(previousVelocity)
  if (!isFinite(previous)) previous = 0
  var elapsed = Number(elapsedMilliseconds)
  if (!isFinite(elapsed) || elapsed <= 0) return previous
  elapsed = clamp(elapsed, 1, 64)
  var instantaneous = clamp(Number(deltaPixels) * 1000 / elapsed, -1800, 1800)
  if (!isFinite(instantaneous)) return previous
  var blend = 1 - Math.exp(-elapsed / 32)
  return clamp(previous + (instantaneous - previous) * blend, -1800, 1800)
}

// Exponential friction gives the same coast distance whether a frame arrives
// on time or late. Distances are returned in screen pixels so momentum keeps
// the same visual weight at every map zoom level.
function dragMomentumStep(velocityX, velocityY, elapsedMilliseconds) {
  var x = Number(velocityX)
  var y = Number(velocityY)
  if (!isFinite(x)) x = 0
  if (!isFinite(y)) y = 0
  var elapsed = Number(elapsedMilliseconds)
  if (!isFinite(elapsed) || elapsed <= 0) elapsed = 0
  var seconds = clamp(elapsed, 0, 50) / 1000
  var friction = 4.8
  var decay = Math.exp(-friction * seconds)
  var travel = (1 - decay) / friction
  var nextX = x * decay
  var nextY = y * decay
  return {
    deltaX: x * travel,
    deltaY: y * travel,
    velocityX: nextX,
    velocityY: nextY,
    active: Math.hypot(nextX, nextY) >= 18
  }
}

function wrapLongitude(value) {
  var wrapped = (Number(value) + 180) % 360
  if (wrapped < 0) wrapped += 360
  return wrapped - 180
}

function longitudeNear(reference, value) {
  var longitude = Number(value)
  var centre = Number(reference)
  while (longitude - centre > 180) longitude -= 360
  while (longitude - centre < -180) longitude += 360
  return longitude
}

function validCoordinate(latitude, longitude) {
  var lat = Number(latitude)
  var lon = Number(longitude)
  return isFinite(lat) && isFinite(lon)
    && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

function pushCoordinate(output, item) {
  if (!item || !validCoordinate(item.latitude, item.longitude)) return
  output.push({ latitude: Number(item.latitude), longitude: Number(item.longitude) })
}

function outlookCoordinates(outlook) {
  var output = []
  if (!outlook) return output
  pushCoordinate(output, outlook)
  var connector = Array.isArray(outlook.connector) ? outlook.connector : []
  for (var c = 0; c < connector.length; c++) {
    if (!Array.isArray(connector[c]) || connector[c].length < 2) continue
    pushCoordinate(output, { longitude: connector[c][0], latitude: connector[c][1] })
  }
  var rings = Array.isArray(outlook.area) ? outlook.area : []
  for (var r = 0; r < rings.length; r++) {
    var ring = Array.isArray(rings[r]) ? rings[r] : []
    for (var p = 0; p < ring.length; p++) {
      if (!Array.isArray(ring[p]) || ring[p].length < 2) continue
      pushCoordinate(output, { longitude: ring[p][0], latitude: ring[p][1] })
    }
  }
  return output
}

function stormCoordinates(storm) {
  var output = []
  if (!storm) return output
  pushCoordinate(output, storm)

  var groups = [storm.track, storm.pastTrack]
  for (var g = 0; g < groups.length; g++) {
    var rows = Array.isArray(groups[g]) ? groups[g] : []
    for (var i = 0; i < rows.length; i++) pushCoordinate(output, rows[i])
  }

  var rings = Array.isArray(storm.cone) ? storm.cone : []
  for (var r = 0; r < rings.length; r++) {
    var ring = Array.isArray(rings[r]) ? rings[r] : []
    for (var p = 0; p < ring.length; p++) {
      if (!Array.isArray(ring[p]) || ring[p].length < 2) continue
      pushCoordinate(output, { longitude: ring[p][0], latitude: ring[p][1] })
    }
  }
  return output
}

function earthquakeCoordinates(earthquake) {
  var output = []
  pushCoordinate(output, earthquake)
  return output
}

function stormBounds(storm) {
  var coordinates = stormCoordinates(storm)
  var reference = storm && validCoordinate(storm.latitude, storm.longitude)
    ? Number(storm.longitude) : 0
  if (coordinates.length === 0) {
    return { centreLatitude: 18, centreLongitude: -70, latitudeSpan: 42, longitudeSpan: 82 }
  }

  var minimumLatitude = 90
  var maximumLatitude = -90
  var minimumLongitude = reference
  var maximumLongitude = reference
  for (var i = 0; i < coordinates.length; i++) {
    var latitude = coordinates[i].latitude
    var longitude = longitudeNear(reference, coordinates[i].longitude)
    minimumLatitude = Math.min(minimumLatitude, latitude)
    maximumLatitude = Math.max(maximumLatitude, latitude)
    minimumLongitude = Math.min(minimumLongitude, longitude)
    maximumLongitude = Math.max(maximumLongitude, longitude)
  }

  var latitudeSpan = Math.max(8, maximumLatitude - minimumLatitude)
  var longitudeSpan = Math.max(12, maximumLongitude - minimumLongitude)
  return {
    centreLatitude: clamp((minimumLatitude + maximumLatitude) / 2, -70, 70),
    centreLongitude: wrapLongitude((minimumLongitude + maximumLongitude) / 2),
    latitudeSpan: Math.min(150, latitudeSpan),
    longitudeSpan: Math.min(320, longitudeSpan)
  }
}

function boundsForCoordinates(coordinates, referenceLongitude, fallback) {
  var rows = Array.isArray(coordinates) ? coordinates : []
  var reference = isFinite(Number(referenceLongitude)) ? Number(referenceLongitude) : 0
  if (rows.length === 0) return fallback
  var minimumLatitude = 90
  var maximumLatitude = -90
  var minimumLongitude = reference
  var maximumLongitude = reference
  for (var i = 0; i < rows.length; i++) {
    var latitude = Number(rows[i].latitude)
    var longitude = longitudeNear(reference, rows[i].longitude)
    minimumLatitude = Math.min(minimumLatitude, latitude)
    maximumLatitude = Math.max(maximumLatitude, latitude)
    minimumLongitude = Math.min(minimumLongitude, longitude)
    maximumLongitude = Math.max(maximumLongitude, longitude)
  }
  return {
    centreLatitude: clamp((minimumLatitude + maximumLatitude) / 2, -70, 70),
    centreLongitude: wrapLongitude((minimumLongitude + maximumLongitude) / 2),
    latitudeSpan: Math.min(150, Math.max(8, maximumLatitude - minimumLatitude)),
    longitudeSpan: Math.min(320, Math.max(12, maximumLongitude - minimumLongitude))
  }
}

function systemKind(system) {
  if (!system) return ""
  if (String(system.kind || "") === "earthquake" || system.magnitude !== undefined) return "earthquake"
  if (String(system.kind || "") === "outlook" || system.sevenDayChance !== undefined) return "outlook"
  return "storm"
}

function systemCoordinates(system) {
  var kind = systemKind(system)
  if (kind === "earthquake") return earthquakeCoordinates(system)
  return kind === "outlook" ? outlookCoordinates(system) : stormCoordinates(system)
}

function systemKey(system) {
  if (!system) return ""
  return systemKind(system) + ":" + String(system.id || "")
}

function copySystem(system, kind) {
  var output = {}
  if (system) for (var key in system) output[key] = system[key]
  output.kind = kind
  output.key = kind + ":" + String(system && system.id || "")
  return output
}

function orderedSystems(storms, outlooks) {
  var active = Array.isArray(storms) ? storms : []
  var developing = Array.isArray(outlooks) ? outlooks : []
  var output = []
  var basins = ["al", "ep", "cp"]
  for (var b = 0; b < basins.length; b++) {
    for (var s = 0; s < active.length; s++) {
      if (String(active[s] && active[s].basin || "") === basins[b]) output.push(copySystem(active[s], "storm"))
    }
    for (var o = 0; o < developing.length; o++) {
      if (String(developing[o] && developing[o].basin || "") === basins[b]) output.push(copySystem(developing[o], "outlook"))
    }
  }
  return output
}

function orderedEarthquakes(earthquakes) {
  var rows = Array.isArray(earthquakes) ? earthquakes : []
  var output = []
  for (var i = 0; i < rows.length; i++) output.push(copySystem(rows[i], "earthquake"))
  output.sort(function(first, second) {
    var firstTime = Date.parse(String(first && first.occurredAt || ""))
    var secondTime = Date.parse(String(second && second.occurredAt || ""))
    if (!isFinite(firstTime)) firstTime = 0
    if (!isFinite(secondTime)) secondTime = 0
    return secondTime - firstTime
  })
  return output
}

function earthquakeSectionName(earthquake, nowMilliseconds) {
  var now = nowMilliseconds === undefined ? Date.now() : Number(nowMilliseconds)
  var cutoff = now - 24 * 60 * 60 * 1000
  var occurred = Date.parse(String(earthquake && earthquake.occurredAt || ""))
  return isFinite(occurred) && occurred >= cutoff ? "Past 24 hours" : "Earlier this week"
}

function earthquakeRows(earthquakes, nowMilliseconds, collapsedSections) {
  var systems = orderedEarthquakes(earthquakes)
  if (systems.length === 0) return [{ kind: "empty", name: "Earthquakes", sectionName: "" }]
  var now = nowMilliseconds === undefined ? Date.now() : Number(nowMilliseconds)
  var recent = []
  var earlier = []
  for (var i = 0; i < systems.length; i++) {
    if (earthquakeSectionName(systems[i], now) === "Past 24 hours") recent.push(systems[i])
    else earlier.push(systems[i])
  }
  var output = []
  function appendSection(name, rows) {
    if (rows.length === 0) return
    output.push({ kind: "section-anchor", name: name, sectionName: name, count: rows.length })
    if (collapsedSections && collapsedSections[name] === true) return
    for (var index = 0; index < rows.length; index++) {
      output.push({
        kind: "system",
        key: rows[index].key,
        system: rows[index],
        sectionName: name,
        count: rows.length
      })
    }
  }
  appendSection("Past 24 hours", recent)
  appendSection("Earlier this week", earlier)
  return output
}

function regionName(basin) {
  if (basin === "al") return "Atlantic"
  if (basin === "ep") return "Eastern Pacific"
  if (basin === "cp") return "Central Pacific"
  return String(basin || "Region").toUpperCase()
}

function regionalRows(storms, outlooks) {
  var systems = orderedSystems(storms, outlooks)
  var rows = []
  var basins = ["al", "ep", "cp"]
  for (var b = 0; b < basins.length; b++) {
    var basin = basins[b]
    var activeCount = 0
    var outlookCount = 0
    for (var c = 0; c < systems.length; c++) {
      if (systems[c].basin !== basin) continue
      if (systems[c].kind === "storm") activeCount++
      else outlookCount++
    }
    rows.push({ kind: "region", basin: basin, name: regionName(basin), activeCount: activeCount, outlookCount: outlookCount })
    var added = 0
    for (var i = 0; i < systems.length; i++) {
      if (systems[i].basin !== basin) continue
      rows.push({ kind: "system", basin: basin, key: systems[i].key, system: systems[i] })
      added++
    }
    if (added === 0) rows.push({ kind: "empty", basin: basin, name: regionName(basin) })
  }
  return rows
}

function disclosedRegionalRows(storms, outlooks, expandedBasin) {
  var rows = regionalRows(storms, outlooks)
  var basin = String(expandedBasin || "")
  var visible = []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind === "region" || rows[i].basin === basin) visible.push(rows[i])
  }
  return visible
}

function systemByKey(systems, key) {
  var rows = Array.isArray(systems) ? systems : []
  for (var i = 0; i < rows.length; i++) if (rows[i].key === String(key || "")) return rows[i]
  return null
}

function selectedKeyAfterRefresh(systems, selectedKey) {
  if (String(selectedKey || "") === "") return ""
  var selected = systemByKey(systems, selectedKey)
  return selected ? selected.key : (systems.length > 0 ? systems[0].key : "")
}

function systemBounds(system) {
  var kind = systemKind(system)
  if (kind === "earthquake") {
    return {
      centreLatitude: clamp(Number(system && system.latitude || 0), -75, 75),
      centreLongitude: wrapLongitude(Number(system && system.longitude || 0)),
      latitudeSpan: 12,
      longitudeSpan: 18
    }
  }
  if (kind === "outlook") {
    return boundsForCoordinates(
      outlookCoordinates(system),
      system && system.longitude,
      { centreLatitude: 18, centreLongitude: -70, latitudeSpan: 30, longitudeSpan: 55 }
    )
  }
  return stormBounds(system)
}

function regionBounds(storms, outlooks, basin) {
  var systems = orderedSystems(storms, outlooks)
  var coordinates = []
  var defaults = {
    al: { centreLatitude: 20, centreLongitude: -62, latitudeSpan: 52, longitudeSpan: 112 },
    ep: { centreLatitude: 15, centreLongitude: -115, latitudeSpan: 48, longitudeSpan: 94 },
    cp: { centreLatitude: 18, centreLongitude: -158, latitudeSpan: 46, longitudeSpan: 78 }
  }
  var fallback = defaults[basin] || { centreLatitude: 12, centreLongitude: -110, latitudeSpan: 110, longitudeSpan: 250 }
  for (var i = 0; i < systems.length; i++) {
    if (systems[i].basin !== basin) continue
    var next = systemCoordinates(systems[i])
    for (var p = 0; p < next.length; p++) coordinates.push(next[p])
  }
  var bounds = boundsForCoordinates(coordinates, fallback.centreLongitude, fallback)
  bounds.latitudeSpan = Math.max(32, bounds.latitudeSpan)
  bounds.longitudeSpan = Math.max(58, bounds.longitudeSpan)
  return bounds
}

function regionCoordinates(storms, outlooks, basin) {
  var systems = orderedSystems(storms, outlooks)
  var coordinates = []
  for (var i = 0; i < systems.length; i++) {
    if (systems[i].basin !== basin) continue
    var next = systemCoordinates(systems[i])
    for (var p = 0; p < next.length; p++) coordinates.push(next[p])
  }
  return coordinates
}

function orthographicPoint(latitude, longitude, centreLatitude, centreLongitude) {
  var radians = Math.PI / 180
  var phi = Number(latitude) * radians
  var phi0 = Number(centreLatitude) * radians
  var delta = longitudeNear(Number(centreLongitude), longitude) * radians - Number(centreLongitude) * radians
  var cosPhi = Math.cos(phi)
  return {
    x: cosPhi * Math.sin(delta),
    y: Math.cos(phi0) * Math.sin(phi) - Math.sin(phi0) * cosPhi * Math.cos(delta),
    z: Math.sin(phi0) * Math.sin(phi) + Math.cos(phi0) * cosPhi * Math.cos(delta)
  }
}

function sameHemispherePoint(first, second) {
  if (!first || !second) return false
  var dx = first.x - second.x
  var dy = first.y - second.y
  var dz = first.z - second.z
  return dx * dx + dy * dy + dz * dz < 1e-18
}

function pushHemispherePoint(points, point) {
  if (!point) return
  var previous = points.length > 0 ? points[points.length - 1] : null
  if (sameHemispherePoint(previous, point)) {
    if (point.horizon) {
      previous.z = 0
      previous.horizon = true
    }
    return
  }
  points.push(point)
}

function prepareHemisphereRing(coordinates) {
  var rows = Array.isArray(coordinates) ? coordinates : []
  var points = []
  var radians = Math.PI / 180
  for (var index = 0; index < rows.length; index++) {
    var value = rows[index]
    var latitude = Array.isArray(value) ? Number(value[1]) : Number(value && value.latitude)
    var longitude = Array.isArray(value) ? Number(value[0]) : Number(value && value.longitude)
    if (!validCoordinate(latitude, longitude)) continue
    var phi = latitude * radians
    var lambda = longitude * radians
    var cosPhi = Math.cos(phi)
    pushHemispherePoint(points, {
      x: cosPhi * Math.sin(lambda),
      y: Math.sin(phi),
      z: cosPhi * Math.cos(lambda)
    })
  }
  if (points.length > 1 && sameHemispherePoint(points[0], points[points.length - 1]))
    points.pop()
  return points
}

function projectPreparedHemisphereRing(prepared, centreLatitude, centreLongitude) {
  var source = Array.isArray(prepared) ? prepared : []
  var points = []
  var radians = Math.PI / 180
  var phi0 = Number(centreLatitude) * radians
  var lambda0 = Number(centreLongitude) * radians
  var sinPhi0 = Math.sin(phi0)
  var cosPhi0 = Math.cos(phi0)
  var sinLambda0 = Math.sin(lambda0)
  var cosLambda0 = Math.cos(lambda0)
  for (var index = 0; index < source.length; index++) {
    var world = source[index]
    if (!world) continue
    var forward = world.z * cosLambda0 + world.x * sinLambda0
    var z = sinPhi0 * world.y + cosPhi0 * forward
    if (Math.abs(z) < 1e-12) z = 0
    points.push({
      x: world.x * cosLambda0 - world.z * sinLambda0,
      y: cosPhi0 * world.y - sinPhi0 * forward,
      z: z,
      horizon: z === 0
    })
  }
  return points
}

function horizonIntersection(first, second) {
  if (Math.abs(first.z) < 1e-12)
    return { x: first.x, y: first.y, z: 0, horizon: true }
  if (Math.abs(second.z) < 1e-12)
    return { x: second.x, y: second.y, z: 0, horizon: true }
  var denominator = first.z - second.z
  var amount = Math.abs(denominator) < 1e-12 ? 0.5 : first.z / denominator
  amount = clamp(amount, 0, 1)
  var x = first.x + (second.x - first.x) * amount
  var y = first.y + (second.y - first.y) * amount
  var radius = Math.hypot(x, y)
  if (radius < 1e-12) return null
  return { x: x / radius, y: y / radius, z: 0, horizon: true }
}

function closeHemisphereFragment(boundary) {
  if (!Array.isArray(boundary) || boundary.length < 3) return null
  var points = boundary.slice()
  var entry = boundary[0]
  var exit = boundary[boundary.length - 1]
  var startAngle = Math.atan2(exit.y, exit.x)
  var delta = Math.atan2(entry.y, entry.x) - startAngle
  while (delta > Math.PI) delta -= Math.PI * 2
  while (delta < -Math.PI) delta += Math.PI * 2
  var steps = Math.max(1, Math.ceil(Math.abs(delta) / (Math.PI / 90)))
  for (var step = 1; step < steps; step++) {
    var angle = startAngle + delta * step / steps
    points.push({
      x: Math.cos(angle),
      y: Math.sin(angle),
      z: 0,
      horizon: true
    })
  }
  return {
    points: points,
    boundaryLength: boundary.length,
    clipped: true
  }
}

function clipHemispherePoints(source) {
  if (source.length < 3) return []

  var outsideIndex = -1
  for (var pointIndex = 0; pointIndex < source.length; pointIndex++) {
    if (source[pointIndex].z < 0) {
      outsideIndex = pointIndex
      break
    }
  }
  if (outsideIndex < 0) return [{
    points: source,
    boundaryLength: source.length,
    clipped: false
  }]

  var fragments = []
  var current = null
  for (var offset = 0; offset < source.length; offset++) {
    var first = source[(outsideIndex + offset) % source.length]
    var second = source[(outsideIndex + offset + 1) % source.length]
    var firstVisible = first.z >= 0
    var secondVisible = second.z >= 0
    if (!firstVisible && secondVisible) {
      current = []
      pushHemispherePoint(current, horizonIntersection(first, second))
      pushHemispherePoint(current, second)
    } else if (firstVisible && secondVisible) {
      if (!current) {
        current = []
        pushHemispherePoint(current, first)
      }
      pushHemispherePoint(current, second)
    } else if (firstVisible && !secondVisible) {
      if (!current) {
        current = []
        pushHemispherePoint(current, first)
      }
      pushHemispherePoint(current, horizonIntersection(first, second))
      var fragment = closeHemisphereFragment(current)
      if (fragment) fragments.push(fragment)
      current = null
    }
  }
  return fragments
}

function clippedPreparedHemisphereRings(prepared, centreLatitude, centreLongitude) {
  return clipHemispherePoints(projectPreparedHemisphereRing(
    prepared, centreLatitude, centreLongitude))
}

// Intersect a geographic polygon ring with the visible orthographic
// hemisphere. Hidden runs are closed along the curved horizon instead of by
// a straight canvas chord through the globe.
function clippedHemisphereRings(coordinates, centreLatitude, centreLongitude) {
  return clippedPreparedHemisphereRings(
    prepareHemisphereRing(coordinates), centreLatitude, centreLongitude)
}

function orthographicFit(coordinates, bounds) {
  var view = bounds || { centreLatitude: 0, centreLongitude: 0, latitudeSpan: 30, longitudeSpan: 60 }
  var rows = Array.isArray(coordinates) ? coordinates : []
  var maximumEast = 0
  var maximumNorth = 0
  var minimumDepth = 1
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i] || !validCoordinate(rows[i].latitude, rows[i].longitude)) continue
    var point = orthographicPoint(
      rows[i].latitude,
      rows[i].longitude,
      view.centreLatitude,
      view.centreLongitude
    )
    maximumEast = Math.max(maximumEast, Math.abs(point.x))
    maximumNorth = Math.max(maximumNorth, Math.abs(point.y))
    minimumDepth = Math.min(minimumDepth, point.z)
  }

  // Bounds have deliberate minimum spans so a point-only advisory still gets
  // enough geographic context. Preserve those floors in spherical space.
  var radians = Math.PI / 180
  var halfLatitude = Math.min(89, Math.max(1, Number(view.latitudeSpan || 0) / 2)) * radians
  var halfLongitude = Math.min(89, Math.max(1, Number(view.longitudeSpan || 0) / 2)) * radians
  var latitudeScale = Math.max(0.24, Math.cos(Number(view.centreLatitude || 0) * radians))
  maximumEast = Math.max(maximumEast, Math.sin(halfLongitude) * latitudeScale)
  maximumNorth = Math.max(maximumNorth, Math.sin(halfLatitude))

  return {
    centreLatitude: Number(view.centreLatitude || 0),
    centreLongitude: wrapLongitude(view.centreLongitude || 0),
    horizontalExtent: Math.max(0.025, maximumEast),
    verticalExtent: Math.max(0.025, maximumNorth),
    minimumDepth: minimumDepth
  }
}

function inverseOrthographic(x, y, centreLatitude, centreLongitude) {
  var rho = Math.hypot(Number(x), Number(y))
  if (!isFinite(rho) || rho > 1.000001) return null
  if (rho < 0.000001) return { latitude: Number(centreLatitude), longitude: wrapLongitude(centreLongitude) }
  var radians = Math.PI / 180
  var phi0 = Number(centreLatitude) * radians
  var c = Math.asin(Math.min(1, rho))
  var sinC = Math.sin(c)
  var cosC = Math.cos(c)
  var latitude = Math.asin(cosC * Math.sin(phi0) + Number(y) * sinC * Math.cos(phi0) / rho)
  var longitude = Number(centreLongitude) * radians + Math.atan2(
    Number(x) * sinC,
    rho * Math.cos(phi0) * cosC - Number(y) * Math.sin(phi0) * sinC
  )
  return { latitude: latitude / radians, longitude: wrapLongitude(longitude / radians) }
}

function classificationLabel(storm) {
  if (!storm) return "Tropical cyclone"
  if (Number(storm.category) > 0) return "Category " + Number(storm.category) + " hurricane"
  return String(storm.classificationLabel || storm.intensityLabel || "Tropical cyclone")
}

function severityCode(storm) {
  if (!storm) return "TC"
  var category = Number(storm.category || 0)
  if (category > 0) return String(category)
  var code = String(storm.classification || "TC").toUpperCase()
  if (code === "TS" || code === "STS") return "TS"
  if (code === "TD" || code === "STD" || code === "SD") return "TD"
  if (code === "PC") return "PC"
  if (code === "PTC" || code === "EX") return "PT"
  return "TC"
}

// Palette authored in OKLCH, stored as sRGB hex because Qt's QML color
// parser does not accept CSS Color 4 syntax. Hue moves from ocean teal through
// amber and coral to plum as wind severity rises.
function severityColor(value) {
  var category = typeof value === "object" ? Number(value && value.category || 0) : Number(value || 0)
  var classification = typeof value === "object" ? String(value && value.classification || "") : ""
  if (category >= 5) return "#b24582"
  if (category === 4) return "#d84e68"
  if (category === 3) return "#ed6c58"
  if (category === 2) return "#ee9858"
  if (category === 1) return "#e9be62"
  if (classification === "TS" || classification === "STS") return "#45c6b5"
  if (classification === "TD" || classification === "STD" || classification === "SD") return "#62abc0"
  return "#89aab1"
}

function outlookColor(outlook) {
  var chance = Number(outlook && outlook.sevenDayChance || 0)
  if (chance >= 70) return "#ed6c58"
  if (chance >= 40) return "#e9be62"
  return "#62abc0"
}

function earthquakeColor(earthquake) {
  var alert = String(earthquake && earthquake.pagerAlert || "").toLowerCase()
  if (alert === "red") return "#d84e68"
  if (alert === "orange") return "#ed6c58"
  if (alert === "yellow") return "#e9be62"
  if (alert === "green") return "#45c6b5"
  return "#89aab1"
}

function earthquakeMagnitudeLabel(earthquake) {
  var magnitude = Number(earthquake && earthquake.magnitude)
  return isFinite(magnitude) ? "M" + magnitude.toFixed(1) : "M?"
}

function formatDepth(earthquake) {
  var depth = Number(earthquake && earthquake.depthKm)
  if (!isFinite(depth)) return "Depth unavailable"
  if (depth < 1) return "Less than 1 km deep"
  return Math.round(depth) + " km deep"
}

function romanIntensity(value) {
  var intensity = Math.round(Number(value))
  var labels = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
  return isFinite(intensity) && intensity >= 1 ? labels[clamp(intensity, 1, 10)] : ""
}

function formatMaximumIntensity(earthquake) {
  var estimated = romanIntensity(earthquake && earthquake.estimatedIntensity)
  if (estimated) return "MMI " + estimated + " estimated"
  var reported = romanIntensity(earthquake && earthquake.reportedIntensity)
  return reported ? "MMI " + reported + " reported" : "Unavailable"
}

function formatFeltReports(earthquake) {
  var value = earthquake && earthquake.feltReports
  if (value === undefined || value === null || !isFinite(Number(value))) return "Unavailable"
  var count = Math.max(0, Math.round(Number(value)))
  return count === 0 ? "None reported" : groupedInteger(count)
}

function earthquakeReviewLabel(earthquake) {
  var status = String(earthquake && earthquake.reviewStatus || "").toLowerCase()
  if (status === "reviewed") return "Reviewed earthquake"
  if (status === "automatic") return "Automatic earthquake"
  return "Earthquake"
}

function earthquakeImpactLabel(earthquake) {
  var alert = String(earthquake && earthquake.pagerAlert || "").toLowerCase()
  return alert ? "PAGER " + alert.charAt(0).toUpperCase() + alert.slice(1) : "No PAGER estimate"
}

function outlookChanceLabel(outlook) {
  var twoDay = Math.max(0, Math.round(Number(outlook && outlook.twoDayChance || 0)))
  var sevenDay = Math.max(0, Math.round(Number(outlook && outlook.sevenDayChance || 0)))
  return twoDay + "% in 2 days · " + sevenDay + "% in 7 days"
}

function systemClassificationLabel(system) {
  var kind = systemKind(system)
  if (kind === "earthquake") return earthquakeReviewLabel(system)
  if (kind === "outlook") return String(system.classificationLabel || "Developing system")
  return classificationLabel(system)
}

function systemMetric(system, useImperial) {
  var kind = systemKind(system)
  if (kind === "earthquake") return formatDepth(system) + " · " + humanAge(system.occurredAt)
  return kind === "outlook" ? outlookChanceLabel(system) : formatWind(system, useImperial)
}

function discussionExcerpt(system) {
  if (systemKind(system) === "earthquake") return earthquakeNarrative(system)
  return String(system && system.discussionExcerpt || "")
}

function earthquakeNarrative(earthquake) {
  if (!earthquake) return ""
  var review = earthquakeReviewLabel(earthquake).toLowerCase()
  var parts = ["USGS reports a " + review + " at " + formatDepth(earthquake) + "."]
  var shaking = formatMaximumIntensity(earthquake)
  if (shaking !== "Unavailable") parts.push("Maximum shaking: " + shaking + ".")
  var felt = formatFeltReports(earthquake)
  if (felt !== "Unavailable") parts.push("Felt reports: " + felt + ".")
  if (String(earthquake.pagerAlert || "")) parts.push(earthquakeImpactLabel(earthquake) + " impact estimate.")
  if (earthquake.tsunamiInfo === true)
    parts.push("Tsunami information is available from NOAA; the USGS flag is not a warning.")
  return parts.join(" ")
}

function groupedInteger(value) {
  return String(Math.round(Number(value) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function formatDistanceKm(distanceKm, useImperial, roundingIncrement) {
  var distance = Math.max(0, Number(distanceKm || 0))
  var converted = useImperial === true ? distance * 0.621371192237334 : distance
  var increment = Math.max(1, Math.round(Number(roundingIncrement || 1)))
  var rounded = Math.round(converted / increment) * increment
  return groupedInteger(rounded) + (useImperial === true ? " mi" : " km")
}

function watchRadiusOptions(useImperial, currentRadiusKm) {
  var displayed = useImperial === true
    ? [150, 300, 450, 600, 900, 1200]
    : [250, 500, 750, 1000, 1500, 2000]
  var output = []
  for (var i = 0; i < displayed.length; i++) {
    var distanceKm = useImperial === true
      ? Math.round(displayed[i] * 1.609344) : displayed[i]
    output.push({
      value: String(distanceKm),
      label: groupedInteger(displayed[i]) + (useImperial === true ? " mi" : " km")
    })
  }
  var current = Math.round(Number(currentRadiusKm))
  if (isFinite(current) && current >= 50 && current <= 2000) {
    var found = false
    for (var r = 0; r < output.length; r++)
      if (output[r].value === String(current)) found = true
    if (!found) output.push({
      value: String(current),
      label: formatDistanceKm(current, useImperial, 5) + " · current"
    })
  }
  output.sort(function(first, second) { return Number(first.value) - Number(second.value) })
  return output
}

function defaultWatchRadiusKm(useImperial) {
  return Number(watchRadiusOptions(useImperial)[3].value)
}

function formatWatchRadius(distanceKm, useImperial) {
  var distance = Math.max(0, Math.round(Number(distanceKm || 0)))
  var options = watchRadiusOptions(useImperial)
  for (var i = 0; i < options.length; i++)
    if (options[i].value === String(distance)) return options[i].label
  return formatDistanceKm(distance, useImperial, 5)
}

function formatSpeedMph(speedMph, useImperial) {
  var speed = Math.max(0, Number(speedMph || 0))
  var converted = useImperial === true ? speed : speed * 1.609344
  return groupedInteger(converted) + (useImperial === true ? " mph" : " km/h")
}

function formatWind(storm, useImperial) {
  var mph = Math.max(0, Math.round(Number(storm && storm.windMph || 0)))
  return mph > 0 ? formatSpeedMph(mph, useImperial) : "Wind unavailable"
}

function formatPressure(storm) {
  var pressure = Math.max(0, Math.round(Number(storm && storm.pressureMb || 0)))
  return pressure > 0 ? pressure + " mb" : "Pressure unavailable"
}

function formatMovement(storm, useImperial) {
  if (!storm) return "Movement unavailable"
  var direction = String(storm.movementDirectionLabel || "")
  var speed = Math.max(0, Math.round(Number(storm.movementSpeedMph || 0)))
  if (direction && speed) return direction + " at " + formatSpeedMph(speed, useImperial)
  if (direction) return direction
  return "Movement unavailable"
}

function humanAge(iso, nowMilliseconds) {
  var then = Date.parse(String(iso || ""))
  if (!isFinite(then)) return "time unavailable"
  var now = nowMilliseconds === undefined ? Date.now() : Number(nowMilliseconds)
  var minutes = Math.max(0, Math.round((now - then) / 60000))
  if (minutes < 2) return "just now"
  if (minutes < 60) return minutes + " min ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  return days + (days === 1 ? " day ago" : " days ago")
}

function advisoryLabel(storm, nowMilliseconds) {
  if (!storm) return "NHC advisory"
  var number = String(storm.advisoryNumber || "").replace(/^0+/, "")
  var prefix = number ? "Advisory " + number : "NHC advisory"
  return prefix + " · " + humanAge(storm.updatedAt, nowMilliseconds)
}

function forecastHourLabel(point) {
  var hour = Math.max(0, Math.round(Number(point && point.forecastHour || 0)))
  return hour === 0 ? "Now" : "+" + hour + "h"
}

function forecastTimeLabel(point) {
  var value = String(point && point.validTimeLabel || "")
  var match = value.match(/(\d{1,2}:\d{2}\s+[AP]M)\s+([A-Z]{2,5})\s+([A-Za-z]+)\s+(\d{1,2})/i)
  if (!match) return value || "Forecast time unavailable"
  return match[3].slice(0, 3) + " " + match[4] + " · " + match[1] + " " + match[2]
}

function safeOfficialUrl(value) {
  var url = String(value || "")
  if (url.length === 0 || url.length > 2048 || /^https:\/\//.test(url) === false) return ""
  var rest = url.slice(8)
  var slash = rest.indexOf("/")
  var host = (slash === -1 ? rest : rest.slice(0, slash)).toLowerCase()
  if (host.indexOf("@") !== -1 || host.indexOf(":") !== -1) return ""
  return [
    "nhc.noaa.gov", "www.nhc.noaa.gov", "hurricanes.gov", "www.hurricanes.gov",
    "earthquake.usgs.gov", "www.tsunami.gov", "tsunami.gov"
  ].indexOf(host) !== -1 ? url : ""
}

function activeSummary(storms) {
  var rows = Array.isArray(storms) ? storms : []
  if (rows.length === 0) return "No active NHC cyclones"
  var names = []
  for (var i = 0; i < Math.min(rows.length, 3); i++) names.push(String(rows[i].name || "Unnamed"))
  var remainder = rows.length > 3 ? " +" + (rows.length - 3) : ""
  return rows.length + (rows.length === 1 ? " active cyclone: " : " active cyclones: ") + names.join(", ") + remainder
}

function trackingSummary(storms, outlooks) {
  var active = Array.isArray(storms) ? storms : []
  var developing = Array.isArray(outlooks) ? outlooks : []
  if (active.length === 0 && developing.length === 0) return "No NHC tropical systems"
  var parts = []
  if (active.length > 0) parts.push(active.length + (active.length === 1 ? " active cyclone" : " active cyclones"))
  if (developing.length > 0) parts.push(developing.length + (developing.length === 1 ? " outlook area" : " outlook areas"))
  return parts.join(" · ")
}

function earthquakeSummary(earthquakes) {
  var rows = Array.isArray(earthquakes) ? earthquakes : []
  if (rows.length === 0) return "No M4.5+ earthquakes in the past week"
  return rows.length + (rows.length === 1 ? " M4.5+ earthquake" : " M4.5+ earthquakes") + " in the past week"
}

var EARTH_RADIUS_KM = 6371.0088
var UNREACHABLE_DISTANCE_KM = 999999
var OUTLOOK_IDENTITY_MAX_DISTANCE_KM = 1800

function radians(value) {
  return Number(value) * Math.PI / 180
}

function haversineDistanceKm(latitudeA, longitudeA, latitudeB, longitudeB) {
  if (!validCoordinate(latitudeA, longitudeA) || !validCoordinate(latitudeB, longitudeB))
    return UNREACHABLE_DISTANCE_KM
  var phiA = radians(latitudeA)
  var phiB = radians(latitudeB)
  var deltaPhi = phiB - phiA
  var deltaLongitude = radians(longitudeNear(longitudeA, longitudeB) - Number(longitudeA))
  var haversine = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2)
    + Math.cos(phiA) * Math.cos(phiB)
      * Math.sin(deltaLongitude / 2) * Math.sin(deltaLongitude / 2)
  return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(Math.max(0, 1 - haversine)))
}

function watchCoordinate(value) {
  var latitude = Array.isArray(value) ? Number(value[1]) : Number(value && value.latitude)
  var longitude = Array.isArray(value) ? Number(value[0]) : Number(value && value.longitude)
  return validCoordinate(latitude, longitude) ? { latitude: latitude, longitude: longitude } : null
}

function localWatchPoint(place, coordinate) {
  var point = watchCoordinate(coordinate)
  if (!point || !place || !validCoordinate(place.latitude, place.longitude)) return null
  var latitude = Number(place.latitude)
  var longitudeDelta = radians(longitudeNear(place.longitude, point.longitude) - Number(place.longitude))
  return {
    x: EARTH_RADIUS_KM * longitudeDelta * Math.max(0.01, Math.cos(radians(latitude))),
    y: EARTH_RADIUS_KM * radians(point.latitude - latitude)
  }
}

function distanceToWatchSegmentKm(place, first, second) {
  var a = localWatchPoint(place, first)
  var b = localWatchPoint(place, second)
  if (!a || !b) return UNREACHABLE_DISTANCE_KM
  var dx = b.x - a.x
  var dy = b.y - a.y
  var denominator = dx * dx + dy * dy
  if (denominator < 0.000001) return Math.hypot(a.x, a.y)
  var projection = clamp(-(a.x * dx + a.y * dy) / denominator, 0, 1)
  return Math.hypot(a.x + projection * dx, a.y + projection * dy)
}

function watchPlaceInsideRing(place, ring) {
  var rows = Array.isArray(ring) ? ring : []
  if (!place || rows.length < 3 || !validCoordinate(place.latitude, place.longitude)) return false
  var inside = false
  var previous = watchCoordinate(rows[rows.length - 1])
  if (!previous) return false
  for (var i = 0; i < rows.length; i++) {
    var current = watchCoordinate(rows[i])
    if (!current) continue
    var currentX = longitudeNear(place.longitude, current.longitude) - Number(place.longitude)
    var previousX = longitudeNear(place.longitude, previous.longitude) - Number(place.longitude)
    var currentY = current.latitude - Number(place.latitude)
    var previousY = previous.latitude - Number(place.latitude)
    if ((currentY > 0) !== (previousY > 0)) {
      var crossingX = (previousX - currentX) * (-currentY) / (previousY - currentY) + currentX
      if (crossingX > 0) inside = !inside
    }
    previous = current
  }
  return inside
}

function distanceToWatchPathKm(place, coordinates, closed) {
  var rows = Array.isArray(coordinates) ? coordinates : []
  if (!place || rows.length === 0 || !validCoordinate(place.latitude, place.longitude))
    return UNREACHABLE_DISTANCE_KM
  if (closed && watchPlaceInsideRing(place, rows)) return 0
  var best = UNREACHABLE_DISTANCE_KM
  var previous = null
  var first = null
  for (var i = 0; i < rows.length; i++) {
    var current = watchCoordinate(rows[i])
    if (!current) continue
    if (!first) first = current
    best = Math.min(best, haversineDistanceKm(
      place.latitude, place.longitude, current.latitude, current.longitude))
    if (previous) best = Math.min(best, distanceToWatchSegmentKm(place, previous, current))
    previous = current
  }
  if (closed && first && previous) best = Math.min(best, distanceToWatchSegmentKm(place, previous, first))
  return best
}

function normalizeWatchPlace(place) {
  if (!place || !validCoordinate(place.latitude, place.longitude)) return null
  var id = String(place.id || "").replace(/[^a-zA-Z0-9_-]+/g, "").slice(0, 64)
  var name = String(place.name || "").replace(/[\x00-\x1f\x7f]+/g, " ")
    .replace(/\s+/g, " ").trim().slice(0, 40)
  if (!id || !name) return null
  return {
    id: id,
    name: name,
    latitude: Number(Number(place.latitude).toFixed(5)),
    longitude: Number(wrapLongitude(place.longitude).toFixed(5)),
    radiusKm: Math.round(clamp(place.radiusKm || 1000, 50, 2000))
  }
}

function watchPlaceCoverage(place) {
  var normalized = normalizeWatchPlace(place)
  if (!normalized) return { supported: false, label: "Location unavailable" }
  var supported = normalized.latitude >= 0 && normalized.latitude <= 72
    && normalized.longitude >= -180 && normalized.longitude <= 0
  return {
    supported: supported,
    label: supported ? "NHC source coverage only" : "Outside current NHC source coverage"
  }
}

function outlookBasinCoverageRing(basin) {
  var code = String(basin || "")
  if (code === "al") return [
    [-80, 0], [0, 0], [0, 72], [-60, 72], [-75, 45],
    [-82, 32], [-98, 30], [-100, 20], [-90, 10], [-80, 0]
  ]
  if (code === "ep") return [
    [-180, 0], [-180, 60], [-128, 60], [-124, 45], [-117, 32],
    [-107, 24], [-98, 17], [-89, 10], [-80, 0], [-180, 0]
  ]
  if (code === "cp") return [
    [-180, 0], [-140, 0], [-140, 60], [-180, 60], [-180, 0]
  ]
  return []
}

function watchPlaceTouchesOutlookBasin(place, basin) {
  var normalized = normalizeWatchPlace(place)
  var ring = outlookBasinCoverageRing(basin)
  if (!normalized || ring.length === 0) return false
  // These coarse source domains overlap near handoff areas on purpose. They
  // only decide whether missing data is relevant, never whether an alert fires.
  return distanceToWatchPathKm(normalized, ring, true) <= normalized.radiusKm
}

function watchCircleCoordinates(place, requestedSteps) {
  var normalized = normalizeWatchPlace(place)
  if (!normalized) return []
  var steps = Math.round(clamp(requestedSteps || 48, 24, 96))
  var angularDistance = normalized.radiusKm / EARTH_RADIUS_KM
  var latitude = radians(normalized.latitude)
  var longitude = radians(normalized.longitude)
  var output = []
  for (var i = 0; i <= steps; i++) {
    var bearing = Math.PI * 2 * i / steps
    var destinationLatitude = Math.asin(
      Math.sin(latitude) * Math.cos(angularDistance)
      + Math.cos(latitude) * Math.sin(angularDistance) * Math.cos(bearing))
    var destinationLongitude = longitude + Math.atan2(
      Math.sin(bearing) * Math.sin(angularDistance) * Math.cos(latitude),
      Math.cos(angularDistance) - Math.sin(latitude) * Math.sin(destinationLatitude))
    output.push({
      latitude: destinationLatitude * 180 / Math.PI,
      longitude: wrapLongitude(destinationLongitude * 180 / Math.PI)
    })
  }
  return output
}

function watchPlaceBounds(place) {
  var normalized = normalizeWatchPlace(place)
  if (!normalized) return { centreLatitude: 18, centreLongitude: -70, latitudeSpan: 30, longitudeSpan: 55 }
  var angularSpan = normalized.radiusKm / 111
  return boundsForCoordinates(
    watchCircleCoordinates(normalized, 48),
    normalized.longitude,
    {
      centreLatitude: normalized.latitude,
      centreLongitude: normalized.longitude,
      latitudeSpan: Math.max(8, angularSpan * 2.4),
      longitudeSpan: Math.max(12, angularSpan * 2.4)
    }
  )
}

function watchPlaceFocus(place, currentZoom, minimumZoom, maximumZoom) {
  var normalized = normalizeWatchPlace(place)
  if (!normalized) return null
  var minimum = isFinite(Number(minimumZoom)) ? Number(minimumZoom) : 1
  var maximum = isFinite(Number(maximumZoom)) ? Number(maximumZoom) : Math.max(minimum, 8)
  if (maximum < minimum) maximum = minimum
  var current = isFinite(Number(currentZoom)) ? Number(currentZoom) : minimum
  var comfortable = clamp(2.2, minimum, maximum)
  return {
    centreLatitude: clamp(normalized.latitude, -82, 82),
    centreLongitude: normalized.longitude,
    zoom: clamp(Math.max(current, comfortable), minimum, maximum)
  }
}

function stormWatchProximity(storm, place) {
  var normalized = normalizeWatchPlace(place)
  if (!storm || !normalized) return {
    distanceKm: UNREACHABLE_DISTANCE_KM,
    currentDistance: UNREACHABLE_DISTANCE_KM,
    forecastDistance: UNREACHABLE_DISTANCE_KM,
    source: "",
    forecastHour: 0,
    approaching: false
  }
  var best = UNREACHABLE_DISTANCE_KM
  var source = ""
  var rings = Array.isArray(storm.cone) ? storm.cone : []
  for (var r = 0; r < rings.length; r++) {
    var coneDistance = distanceToWatchPathKm(normalized, rings[r], true)
    if (coneDistance < best) {
      best = coneDistance
      source = "cone"
    }
  }
  var track = Array.isArray(storm.track) ? storm.track : []
  var trackDistance = distanceToWatchPathKm(normalized, track, false)
  if (trackDistance < best) {
    best = trackDistance
    source = "track"
  }
  var currentDistance = UNREACHABLE_DISTANCE_KM
  if (validCoordinate(storm.latitude, storm.longitude)) {
    currentDistance = haversineDistanceKm(
      normalized.latitude, normalized.longitude, storm.latitude, storm.longitude)
    if (currentDistance < best) {
      best = currentDistance
      source = "centre"
    }
  }
  var forecastHour = 0
  var forecastDistance = UNREACHABLE_DISTANCE_KM
  for (var i = 0; i < track.length; i++) {
    if (!watchCoordinate(track[i])) continue
    var requestedHour = Math.max(0, Math.round(Number(track[i].forecastHour || 0)))
    if (requestedHour === 0 && i === 0) continue
    var pointDistance = haversineDistanceKm(
      normalized.latitude, normalized.longitude, track[i].latitude, track[i].longitude)
    if (pointDistance < forecastDistance) {
      forecastDistance = pointDistance
      forecastHour = requestedHour
    }
  }
  var approachMargin = currentDistance < UNREACHABLE_DISTANCE_KM
    ? Math.max(75, currentDistance * 0.08) : UNREACHABLE_DISTANCE_KM
  return {
    distanceKm: best,
    currentDistance: currentDistance,
    forecastDistance: forecastDistance,
    source: source,
    forecastHour: forecastHour,
    approaching: currentDistance - forecastDistance >= approachMargin
  }
}

function outlookWatchProximity(outlook, place) {
  var normalized = normalizeWatchPlace(place)
  if (!outlook || !normalized) return { distanceKm: UNREACHABLE_DISTANCE_KM, source: "" }
  var best = UNREACHABLE_DISTANCE_KM
  var source = ""
  var rings = Array.isArray(outlook.area) ? outlook.area : []
  for (var r = 0; r < rings.length; r++) {
    var areaDistance = distanceToWatchPathKm(normalized, rings[r], true)
    if (areaDistance < best) {
      best = areaDistance
      source = "area"
    }
  }
  if (validCoordinate(outlook.latitude, outlook.longitude)) {
    var markerDistance = haversineDistanceKm(
      normalized.latitude, normalized.longitude, outlook.latitude, outlook.longitude)
    if (markerDistance < best) {
      best = markerDistance
      source = "marker"
    }
  }
  return { distanceKm: best, source: source }
}

function watchAttentionRank(level) {
  var normalized = String(level || "")
  if (normalized === "urgent") return 3
  if (normalized === "monitor") return 2
  if (normalized === "heads-up") return 1
  return 0
}

function watchAttentionCount(summaries) {
  var rows = Array.isArray(summaries) ? summaries : []
  var count = 0
  for (var i = 0; i < rows.length; i++)
    if (watchAttentionRank(rows[i] && rows[i].state) > 0) count++
  return count
}

function watchUnsupportedCount(summaries) {
  var rows = Array.isArray(summaries) ? summaries : []
  var count = 0
  for (var i = 0; i < rows.length; i++)
    if (String(rows[i] && rows[i].state || "") === "unsupported") count++
  return count
}

function watchDataLimitedCount(summaries) {
  var rows = Array.isArray(summaries) ? summaries : []
  var count = 0
  for (var i = 0; i < rows.length; i++)
    if (rows[i] && rows[i].dataLimited === true) count++
  return count
}

function watchStrongestAttentionState(summaries) {
  var rows = Array.isArray(summaries) ? summaries : []
  var strongest = ""
  var strongestRank = 0
  for (var i = 0; i < rows.length; i++) {
    var state = String(rows[i] && rows[i].state || "")
    var rank = watchAttentionRank(state)
    if (rank > strongestRank) {
      strongest = state
      strongestRank = rank
    }
  }
  return strongest
}

function watchSnapshotRank(item) {
  if (!item) return 0
  var requested = Number(item.attentionRank)
  if (isFinite(requested)) return Math.max(0, Math.round(requested))
  var ranked = watchAttentionRank(item.attentionLevel)
  return ranked > 0 ? ranked : (item.meetsThreshold ? 1 : 0)
}

function stormWatchAttentionLevel(storm, place, proximity) {
  var normalized = normalizeWatchPlace(place)
  if (!storm || !normalized || !proximity || proximity.distanceKm > normalized.radiusKm) return ""
  var closeApproach = Math.min(proximity.distanceKm, proximity.forecastDistance)
  var localThreshold = Math.min(normalized.radiusKm, Math.max(250, normalized.radiusKm * 0.65))
  if (proximity.currentDistance <= normalized.radiusKm
      && proximity.approaching && closeApproach <= localThreshold) return "urgent"
  return "monitor"
}

function watchAlertSnapshot(storms, outlooks, places, thresholdValue) {
  var active = Array.isArray(storms) ? storms : []
  var developing = Array.isArray(outlooks) ? outlooks : []
  var watches = Array.isArray(places) ? places : []
  var threshold = alertThresholdValue(thresholdValue)
  var output = {}
  for (var p = 0; p < watches.length; p++) {
    var place = normalizeWatchPlace(watches[p])
    if (!place || !watchPlaceCoverage(place).supported) continue
    for (var s = 0; s < active.length; s++) {
      var stormProximity = stormWatchProximity(active[s], place)
      var stormAttention = stormWatchAttentionLevel(active[s], place, stormProximity)
      var stormKey = "place:" + place.id + "|storm:" + String(active[s].id || "")
      output[stormKey] = {
        scope: "place", kind: "storm", key: stormKey,
        placeId: place.id, placeName: place.name, radiusKm: place.radiusKm,
        name: String(active[s].name || "Unnamed storm"),
        basin: String(active[s].basin || ""),
        systemKey: "storm:" + String(active[s].id || ""),
        label: classificationLabel(active[s]),
        distanceKm: stormProximity.distanceKm,
        currentDistance: stormProximity.currentDistance,
        forecastDistance: stormProximity.forecastDistance,
        proximitySource: stormProximity.source,
        forecastHour: stormProximity.forecastHour,
        approaching: stormProximity.approaching,
        attentionLevel: stormAttention,
        attentionRank: watchAttentionRank(stormAttention),
        meetsThreshold: watchAttentionRank(stormAttention) > 0
      }
    }
    for (var o = 0; o < developing.length; o++) {
      var outlookProximity = outlookWatchProximity(developing[o], place)
      var chance = Math.max(0, Math.round(Number(developing[o].sevenDayChance || 0)))
      var outlookAttention = chance >= threshold && outlookProximity.distanceKm <= place.radiusKm
        ? "heads-up" : ""
      var outlookKey = "place:" + place.id + "|outlook:" + String(developing[o].id || "")
      output[outlookKey] = {
        scope: "place", kind: "outlook", key: outlookKey,
        placeId: place.id, placeName: place.name, radiusKm: place.radiusKm,
        name: String(developing[o].name || developing[o].title || "Developing system"),
        basin: String(developing[o].basin || ""),
        sourceBasin: String(developing[o].sourceBasin || developing[o].basin || ""),
        systemKey: "outlook:" + String(developing[o].id || ""),
        outlookIdentity: outlookIdentityLabel(developing[o]),
        outlookStableIdentifier: outlookStableIdentifier(developing[o]),
        outlookIdentityStable: outlookIdentityIsStable(developing[o]),
        latitude: Number(developing[o].latitude),
        longitude: Number(developing[o].longitude),
        label: String(developing[o].classificationLabel || "Developing system"),
        chance: chance,
        distanceKm: outlookProximity.distanceKm,
        proximitySource: outlookProximity.source,
        attentionLevel: outlookAttention,
        attentionRank: watchAttentionRank(outlookAttention),
        meetsThreshold: watchAttentionRank(outlookAttention) > 0
      }
    }
  }
  return output
}

function outlookIdentityLabel(system) {
  var source = String(system && (
    system.outlookIdentity || system.name || system.title) || "")
  return source.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
}

function outlookStableIdentifier(system) {
  var explicit = String(system && system.outlookStableIdentifier || "")
    .toLowerCase().replace(/[^a-z0-9:]+/g, " ").trim().slice(0, 96)
  if (explicit !== "") return explicit
  var identity = outlookIdentityLabel(system)
  var invest = identity.match(/(^| )((al|ep|cp)[0-9]{2})($| )/)
  if (invest) return invest[2]
  var classification = String(system && (
    system.classificationLabel || system.label) || "").toLowerCase()
  return classification !== "" && classification !== "developing system"
    && identity !== "" ? "named:" + identity : ""
}

function outlookIdentityIsStable(system) {
  return outlookStableIdentifier(system) !== ""
}

function outlookSourceBasin(system) {
  return String(system && (system.sourceBasin || system.basin) || "")
}

function outlookDataIncomplete(system, incompleteOutlooks) {
  var rows = incompleteOutlooks || ({})
  var sourceBasin = outlookSourceBasin(system)
  var displayBasin = String(system && system.basin || "")
  return !!(rows[sourceBasin] || rows[displayBasin])
}

function outlooksSharePacificBoundary(first, second) {
  var firstBasin = String(first && first.basin || "")
  var secondBasin = String(second && second.basin || "")
  return (firstBasin === "ep" && secondBasin === "cp")
    || (firstBasin === "cp" && secondBasin === "ep")
}

function outlookIdentityWithoutInvest(system) {
  return outlookIdentityLabel(system)
    .replace(/\b(al|ep|cp)[0-9]{2}\b/g, " ").replace(/\s+/g, " ").trim()
}

function outlookSnapshotIdentityMatches(first, second) {
  if (!first || !second) return false
  var sameBasin = String(first.basin || "") === String(second.basin || "")
  var crossesPacificBoundary = outlooksSharePacificBoundary(first, second)
  if (!sameBasin && !crossesPacificBoundary) return false
  var firstIdentity = outlookIdentityLabel(first)
  var secondIdentity = outlookIdentityLabel(second)
  var firstStableIdentifier = outlookStableIdentifier(first)
  var secondStableIdentifier = outlookStableIdentifier(second)
  var coordinatesAvailable = validCoordinate(first.latitude, first.longitude)
    && validCoordinate(second.latitude, second.longitude)
  var distance = coordinatesAvailable ? haversineDistanceKm(
    first.latitude, first.longitude, second.latitude, second.longitude) : Infinity
  var firstWithoutInvest = outlookIdentityWithoutInvest(first)
  var secondWithoutInvest = outlookIdentityWithoutInvest(second)
  var contentMatches = firstWithoutInvest !== ""
    && firstWithoutInvest === secondWithoutInvest
  if (firstStableIdentifier !== "" || secondStableIdentifier !== "") {
    if (firstStableIdentifier !== "" && firstStableIdentifier === secondStableIdentifier) {
      return contentMatches || (coordinatesAvailable
        && distance <= OUTLOOK_IDENTITY_MAX_DISTANCE_KM)
    }
    if (!crossesPacificBoundary || !coordinatesAvailable
        || distance > OUTLOOK_IDENTITY_MAX_DISTANCE_KM) return false
    return contentMatches
  }
  if (firstIdentity === "" || firstIdentity !== secondIdentity) return false
  if (crossesPacificBoundary && !coordinatesAvailable) return false
  return !coordinatesAvailable || distance <= OUTLOOK_IDENTITY_MAX_DISTANCE_KM
}

function matchingSnapshotEntry(before, item, usedKeys) {
  var source = before || {}
  var used = usedKeys || {}
  var directKey = String(item && item.key || "")
  var direct = directKey ? source[directKey] : null
  if (direct && !used[directKey]) {
    if (item.kind !== "outlook" || outlookSnapshotIdentityMatches(direct, item))
      return { key: directKey, item: direct }
  }
  if (!item || item.kind !== "outlook") return null
  for (var key in source) {
    if (used[key] || key === directKey) continue
    var candidate = source[key]
    if (!candidate || candidate.kind !== "outlook") continue
    if (String(candidate.scope || "") !== String(item.scope || "")) continue
    if (item.scope === "place"
        && String(candidate.placeId || "") !== String(item.placeId || "")) continue
    if (outlookSnapshotIdentityMatches(candidate, item))
      return { key: key, item: candidate }
  }
  return null
}

function watchAlertEvents(previous, current) {
  var before = previous || {}
  var after = current || {}
  var events = []
  var used = ({})
  for (var key in after) {
    var item = after[key]
    var match = matchingSnapshotEntry(before, item, used)
    var old = match ? match.item : null
    if (match) used[match.key] = true
    if (watchSnapshotRank(item) > watchSnapshotRank(old)) events.push(item)
  }
  return events
}

function stringSet(values) {
  var rows = Array.isArray(values) ? values : []
  var output = ({})
  for (var i = 0; i < rows.length; i++) {
    var value = String(rows[i] || "")
    if (value) output[value] = true
  }
  return output
}

function copySnapshot(snapshot) {
  var source = snapshot || {}
  var output = ({})
  for (var key in source) output[key] = source[key]
  return output
}

function incompleteForecastSystemKeys(storms) {
  var rows = Array.isArray(storms) ? storms : []
  var output = []
  var seen = ({})
  for (var i = 0; i < rows.length; i++) {
    var storm = rows[i]
    var warnings = Array.isArray(storm && storm.dataWarnings) ? storm.dataWarnings : []
    var incomplete = false
    for (var w = 0; w < warnings.length; w++) {
      if (warnings[w] === "track unavailable" || warnings[w] === "cone unavailable") {
        incomplete = true
        break
      }
    }
    var key = "storm:" + String(storm && storm.id || "")
    if (incomplete && key !== "storm:" && !seen[key]) {
      seen[key] = true
      output.push(key)
    }
  }
  return output
}

function stabilizedAlertSnapshots(previous, current, incompleteOutlookBasins,
    incompleteSystemKeys) {
  var before = copySnapshot(previous)
  var after = copySnapshot(current)
  var incompleteOutlooks = stringSet(incompleteOutlookBasins)
  var incompleteSystems = stringSet(incompleteSystemKeys)
  var key
  for (key in before) {
    var previousItem = before[key]
    if (!previousItem) continue
    var preserveOutlook = previousItem.kind === "outlook"
      && outlookDataIncomplete(previousItem, incompleteOutlooks)
    if (preserveOutlook) {
      var currentMatch = matchingSnapshotEntry(after, previousItem, ({}))
      var currentSourceBasin = outlookSourceBasin(currentMatch && currentMatch.item)
      if (currentMatch && currentSourceBasin !== ""
          && !incompleteOutlooks[currentSourceBasin]) continue
    }
    var systemKey = previousItem.scope === "place"
      ? String(previousItem.systemKey || "") : String(previousItem.key || "")
    var preserveSystem = previousItem.kind === "storm" && incompleteSystems[systemKey]
    if ((preserveOutlook || preserveSystem)
        && (!after[key] || watchSnapshotRank(after[key]) < watchSnapshotRank(previousItem)))
      after[key] = previousItem
  }
  return { before: before, current: after }
}

function alertEventSystemKey(event) {
  if (!event) return ""
  return String(event.scope === "place" ? event.systemKey || "" : event.key || "")
}

function coalesceAlertEvents(events) {
  var rows = Array.isArray(events) ? events : []
  var placeSystems = ({})
  var output = []
  for (var i = 0; i < rows.length; i++) {
    var placeEvent = rows[i]
    var placeKey = alertEventSystemKey(placeEvent)
    if (placeEvent && placeEvent.scope === "place" && placeKey) placeSystems[placeKey] = true
  }
  for (var r = 0; r < rows.length; r++) {
    var event = rows[r]
    var systemKey = alertEventSystemKey(event)
    if (event && event.scope !== "place" && systemKey && placeSystems[systemKey]) continue
    output.push(event)
  }
  return output
}

function watchDistanceLabel(distanceKm, useImperial) {
  var distance = Math.max(0, Math.round(Number(distanceKm || 0)))
  return distance < 10 ? "at the watch point"
    : formatDistanceKm(distance, useImperial) + " away"
}

function watchForecastLeadLabel(hours) {
  var value = Math.max(0, Math.round(Number(hours || 0)))
  if (value === 0) return ""
  if (value < 36) return " · ~" + value + "h"
  return " · ~" + Math.max(2, Math.round(value / 24)) + "d"
}

function watchForecastLeadHours(event) {
  if (!event) return 0
  var hours = Math.max(0, Math.round(Number(event.forecastHour || 0)))
  return event.attentionLevel === "urgent" || event.proximitySource === "track" ? hours : 0
}

function watchPlaceHasIncompleteData(place, snapshot, incompleteOutlookRows,
    incompleteSystems) {
  var normalized = normalizeWatchPlace(place)
  if (!normalized) return false
  var outlookRows = Array.isArray(incompleteOutlookRows) ? incompleteOutlookRows : []
  for (var b = 0; b < outlookRows.length; b++)
    if (watchPlaceTouchesOutlookBasin(normalized, outlookRows[b])) return true

  var rows = snapshot && typeof snapshot === "object" ? snapshot : ({})
  var systems = incompleteSystems || ({})
  for (var key in rows) {
    var candidate = rows[key]
    if (!candidate || candidate.kind !== "storm" || candidate.placeId !== normalized.id
        || !systems[String(candidate.systemKey || "")]) continue
    if (candidate.meetsThreshold) return true
    var distance = Number(candidate.distanceKm)
    // Missing forecast geometry matters before the centre reaches the watch
    // area, but should not tint locations several regions away.
    if (isFinite(distance) && distance <= normalized.radiusKm + 2500) return true
  }
  return false
}

function watchPlaceSummaries(storms, outlooks, places, thresholdValue, useImperial,
    alertContext) {
  var watches = Array.isArray(places) ? places : []
  var context = alertContext && typeof alertContext === "object" ? alertContext : ({})
  var snapshot = context.snapshot && typeof context.snapshot === "object"
    ? context.snapshot : watchAlertSnapshot(storms, outlooks, watches, thresholdValue)
  var incompleteOutlookRows = Array.isArray(context.incompleteOutlookBasins)
    ? context.incompleteOutlookBasins : []
  var incompleteSystemRows = Array.isArray(context.incompleteSystemKeys)
    ? context.incompleteSystemKeys : []
  var incompleteOutlooks = stringSet(incompleteOutlookRows)
  var incompleteSystems = stringSet(incompleteSystemRows)
  var output = []
  for (var p = 0; p < watches.length; p++) {
    var place = normalizeWatchPlace(watches[p])
    if (!place) continue
    var selected = null
    for (var key in snapshot) {
      var candidate = snapshot[key]
      if (candidate.placeId !== place.id || !candidate.meetsThreshold) continue
      if (!selected || candidate.attentionRank > selected.attentionRank
          || (candidate.attentionRank === selected.attentionRank
            && candidate.distanceKm < selected.distanceKm))
        selected = candidate
    }
    var coverage = watchPlaceCoverage(place)
    var dataIncomplete = coverage.supported && watchPlaceHasIncompleteData(
      place, snapshot, incompleteOutlookRows, incompleteSystems)
    var summary = {
      place: place,
      state: coverage.supported ? "quiet" : "unsupported",
      status: coverage.supported ? "QUIET" : "LIMITED",
      detail: coverage.supported
        ? formatWatchRadius(place.radiusKm, useImperial)
          + " forecast awareness · NHC only"
        : coverage.label,
      dataLimited: coverage.supported && dataIncomplete,
      systemKey: "",
      event: null
    }
    if (coverage.supported && !selected && dataIncomplete) {
      summary.state = "limited"
      summary.status = "DATA LIMITED"
      summary.detail = "Some NHC forecast data is temporarily unavailable"
    }
    if (selected && selected.attentionLevel === "urgent") {
      summary.state = "urgent"
      summary.status = "APPROACHING"
      summary.detail = selected.name + " · closest forecast "
        + watchDistanceLabel(selected.forecastDistance, useImperial)
        + watchForecastLeadLabel(watchForecastLeadHours(selected))
      summary.systemKey = selected.systemKey
      summary.event = selected
    } else if (selected && selected.kind === "storm") {
      summary.state = "monitor"
      summary.status = "MONITORING"
      summary.detail = selected.proximitySource === "cone" && selected.distanceKm < 10
        ? selected.name + " · forecast cone reaches watch area"
          + watchForecastLeadLabel(watchForecastLeadHours(selected))
        : selected.name + " · forecast may pass "
          + watchDistanceLabel(selected.distanceKm, useImperial)
          + watchForecastLeadLabel(watchForecastLeadHours(selected))
      summary.systemKey = selected.systemKey
      summary.event = selected
    } else if (selected) {
      summary.state = "heads-up"
      summary.status = "HEADS-UP"
      summary.detail = selected.proximitySource === "area" && selected.distanceKm < 10
        ? selected.name + " · " + selected.chance + "% formation area reaches watch area"
        : selected.name + " · " + selected.chance + "% formation area may approach "
          + watchDistanceLabel(selected.distanceKm, useImperial)
      summary.systemKey = selected.systemKey
      summary.event = selected
    }
    var selectedSystemKey = selected
      ? String(selected.systemKey || selected.key || "") : ""
    var selectedDataLimited = selected && (
      (selected.kind === "outlook" && outlookDataIncomplete(selected, incompleteOutlooks))
      || (selected.kind === "storm" && incompleteSystems[selectedSystemKey]))
    if (selectedDataLimited) {
      summary.dataLimited = true
      summary.detail += " · update incomplete"
    }
    output.push(summary)
  }
  return output
}

function alertRegionCode(value) {
  var normalized = String(value || "").toLowerCase()
  if (normalized === "atlantic") return "al"
  if (normalized === "eastern pacific") return "ep"
  if (normalized === "central pacific") return "cp"
  if (normalized === "all nhc basins") return "all"
  return ""
}

function relevantIncompleteAlertBasins(regionValue, incompleteOutlookBasins) {
  var basin = alertRegionCode(regionValue)
  if (!basin) return []
  var incomplete = Array.isArray(incompleteOutlookBasins)
    ? incompleteOutlookBasins : []
  var output = []
  var seen = ({})
  for (var i = 0; i < incomplete.length; i++) {
    var unavailable = String(incomplete[i] || "")
    if (unavailable !== "al" && unavailable !== "ep" && unavailable !== "cp") continue
    var relevant = basin === "all" || unavailable === basin
      || ((basin === "ep" || basin === "cp")
        && (unavailable === "ep" || unavailable === "cp"))
    if (relevant && !seen[unavailable]) {
      seen[unavailable] = true
      output.push(unavailable)
    }
  }
  return output
}

function alertThresholdValue(value) {
  var match = String(value || "").match(/(\d{1,3})/)
  return match ? clamp(Number(match[1]), 0, 100) : 40
}

function inAlertRegion(system, basin) {
  return basin === "all" || String(system && system.basin || "") === basin
}

function alertSnapshot(storms, outlooks, regionValue, thresholdValue, includeNamedStorms) {
  var basin = alertRegionCode(regionValue)
  var threshold = alertThresholdValue(thresholdValue)
  var output = {}
  if (!basin) return output
  var active = Array.isArray(storms) ? storms : []
  var developing = Array.isArray(outlooks) ? outlooks : []
  if (includeNamedStorms !== false) {
    for (var s = 0; s < active.length; s++) {
      if (!inAlertRegion(active[s], basin)) continue
      var stormKey = "storm:" + String(active[s].id || "")
      output[stormKey] = {
        kind: "storm", key: stormKey, name: String(active[s].name || "Unnamed storm"),
        basin: String(active[s].basin || ""), label: classificationLabel(active[s]), chance: 100
      }
    }
  }
  for (var o = 0; o < developing.length; o++) {
    if (!inAlertRegion(developing[o], basin)) continue
    var chance = Number(developing[o].sevenDayChance || 0)
    var outlookKey = "outlook:" + String(developing[o].id || "")
    output[outlookKey] = {
      kind: "outlook", key: outlookKey, name: String(developing[o].name || developing[o].title || "Developing system"),
      basin: String(developing[o].basin || ""), label: String(developing[o].classificationLabel || "Developing system"),
      sourceBasin: String(developing[o].sourceBasin || developing[o].basin || ""),
      outlookIdentity: outlookIdentityLabel(developing[o]),
      outlookStableIdentifier: outlookStableIdentifier(developing[o]),
      outlookIdentityStable: outlookIdentityIsStable(developing[o]),
      latitude: Number(developing[o].latitude), longitude: Number(developing[o].longitude),
      chance: chance, meetsThreshold: chance >= threshold
    }
  }
  return output
}

function alertEvents(previous, current) {
  var before = previous || {}
  var after = current || {}
  var events = []
  var used = ({})
  for (var key in after) {
    var item = after[key]
    var match = matchingSnapshotEntry(before, item, used)
    var old = match ? match.item : null
    if (match) used[match.key] = true
    if (item.kind === "storm" && !old) events.push(item)
    if (item.kind === "outlook" && item.meetsThreshold && (!old || !old.meetsThreshold)) events.push(item)
  }
  return events
}

function basinAlertTransition(previous, current, regionValue,
    incompleteOutlookBasins, pendingOutlookBasins, resetQuietly) {
  var currentSnapshot = copySnapshot(current)
  if (resetQuietly) {
    return {
      current: currentSnapshot,
      events: [],
      pendingOutlookBasins: relevantIncompleteAlertBasins(
        regionValue, incompleteOutlookBasins)
    }
  }

  var stable = stabilizedAlertSnapshots(
    previous, currentSnapshot, incompleteOutlookBasins, [])
  var pending = stringSet(pendingOutlookBasins)
  var candidates = alertEvents(stable.before, stable.current)
  var events = []
  for (var i = 0; i < candidates.length; i++) {
    var event = candidates[i]
    if (event && event.kind === "outlook"
        && pending[outlookSourceBasin(event)]) continue
    events.push(event)
  }

  // A feed that was unavailable when alerts were armed gets one quiet payload
  // when it recovers. Named storms and other outlook feeds remain live while
  // that source is pending.
  var stillIncomplete = stringSet(relevantIncompleteAlertBasins(
    regionValue, incompleteOutlookBasins))
  var pendingRows = Array.isArray(pendingOutlookBasins)
    ? pendingOutlookBasins : []
  var remaining = []
  var seen = ({})
  for (var p = 0; p < pendingRows.length; p++) {
    var basin = String(pendingRows[p] || "")
    if (stillIncomplete[basin] && !seen[basin]) {
      seen[basin] = true
      remaining.push(basin)
    }
  }
  return {
    current: stable.current,
    events: events,
    pendingOutlookBasins: remaining
  }
}

function selectedIndexAfterRefresh(storms, selectedId) {
  var rows = Array.isArray(storms) ? storms : []
  for (var i = 0; i < rows.length; i++) {
    if (String(rows[i] && rows[i].id || "") === String(selectedId || "")) return i
  }
  return rows.length > 0 ? 0 : -1
}
