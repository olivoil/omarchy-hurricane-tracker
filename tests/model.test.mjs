import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const testDir = path.dirname(fileURLToPath(import.meta.url))
const source = fs.readFileSync(path.join(testDir, "..", "Model.js"), "utf8")
const model = { Math, Number, Array, String, Date, RegExp, isFinite }
vm.createContext(model)
vm.runInContext(source, model)

assert.equal(model.wrapLongitude(190), -170)
assert.equal(model.longitudeNear(170, -175), 185)
assert.equal(model.validCoordinate(20, -70), true)
assert.equal(model.validCoordinate(100, -70), false)

const storm = {
  id: "al012026",
  name: "Ada",
  classification: "HU",
  classificationLabel: "Hurricane",
  basin: "al",
  category: 2,
  windMph: 105,
  pressureMb: 968,
  latitude: 22.4,
  longitude: -73.1,
  movementDirectionLabel: "WNW",
  movementSpeedMph: 12,
  advisoryNumber: "014",
  updatedAt: "2026-08-28T15:00:00Z",
  track: [
    { latitude: 22.4, longitude: -73.1 },
    { latitude: 26.8, longitude: -77.2 }
  ],
  pastTrack: [{ latitude: 19.8, longitude: -69.2 }],
  cone: [[[-73.4, 22.1], [-80.2, 27.2], [-78.4, 29.0], [-73.4, 22.1]]]
}

assert.equal(model.classificationLabel(storm), "Category 2 hurricane")
assert.equal(model.severityCode(storm), "2")
assert.equal(model.severityColor(storm), "#ee9858")
assert.equal(model.formatWind(storm, true), "105 mph")
assert.equal(model.formatWind(storm, false), "169 km/h")
assert.equal(model.formatPressure(storm), "968 mb")
assert.equal(model.formatMovement(storm, true), "WNW at 12 mph")
assert.equal(model.formatMovement(storm, false), "WNW at 19 km/h")
assert.equal(model.systemMetric(storm, false), "169 km/h")
assert.equal(model.formatDistanceKm(1000, false, 5), "1,000 km")
assert.equal(model.formatDistanceKm(1000, true, 5), "620 mi")
const imperialWatchRadiusOptions = model.watchRadiusOptions(true)
assert.deepEqual(
  Array.from(imperialWatchRadiusOptions, option => option.label),
  ["150 mi", "300 mi", "450 mi", "600 mi", "900 mi", "1,200 mi"]
)
assert.deepEqual(
  Array.from(imperialWatchRadiusOptions, option => option.value),
  ["241", "483", "724", "966", "1448", "1931"]
)
assert.equal(model.defaultWatchRadiusKm(true), 966)
assert.equal(model.defaultWatchRadiusKm(false), 1000)
assert.equal(model.formatWatchRadius(966, true), "600 mi")
assert.equal(model.formatWatchRadius(1000, true), "620 mi")
assert.equal(model.formatWatchRadius(1000, false), "1,000 km")
assert.equal(
  model.watchRadiusOptions(true, 1000).find(option => option.value === "1000").label,
  "620 mi · current"
)
assert.equal(model.watchDistanceLabel(160.9344, true), "100 mi away")
assert.equal(model.advisoryLabel(storm, Date.parse("2026-08-28T18:00:00Z")), "Advisory 14 · 3h ago")
assert.equal(model.forecastHourLabel({ forecastHour: 0 }), "Now")
assert.equal(model.forecastHourLabel({ forecastHour: 48 }), "+48h")
assert.equal(
  model.forecastTimeLabel({ validTimeLabel: "11:00 AM EDT August 29, 2026" }),
  "Aug 29 · 11:00 AM EDT"
)

const bounds = model.stormBounds(storm)
assert.ok(bounds.centreLatitude > 20 && bounds.centreLatitude < 28)
assert.ok(bounds.centreLongitude < -70 && bounds.centreLongitude > -80)
assert.ok(bounds.latitudeSpan >= 8)
assert.ok(bounds.longitudeSpan >= 12)

const outlook = {
  id: "al-outlook-1",
  name: "Dolly",
  title: "East of the Leeward Islands (Remnants of Dolly)",
  basin: "al",
  classificationLabel: "Remnant",
  latitude: 16.2,
  longitude: -51.4,
  twoDayChance: 0,
  sevenDayChance: 10,
  discussionExcerpt: "Redevelopment is unlikely.",
  connector: [[-51.7, 16.3], [-59, 17.4], [-67, 19]],
  area: [[[-67, 19], [-78, 22], [-75, 27], [-65, 24], [-67, 19]]]
}

assert.equal(model.systemKey(outlook), "outlook:al-outlook-1")
assert.equal(model.outlookChanceLabel(outlook), "0% in 2 days · 10% in 7 days")
assert.equal(model.systemClassificationLabel(outlook), "Remnant")
assert.equal(model.discussionExcerpt(outlook), "Redevelopment is unlikely.")
assert.ok(model.systemBounds(outlook).longitudeSpan >= 12)
assert.ok(model.systemCoordinates(outlook).length >= 8)
const visualOnlyConnector = {
  ...outlook,
  latitude: 5,
  longitude: -30,
  connector: [[-30, 5], [-71, 23]],
  area: [[[-35, 4], [-34, 4], [-34, 6], [-35, 6], [-35, 4]]]
}
assert.ok(model.outlookWatchProximity(visualOnlyConnector, {
  id: "connector-test",
  name: "Connector test",
  latitude: 23,
  longitude: -71,
  radiusKm: 100
}).distanceKm > 1000)

const systems = model.orderedSystems([storm], [outlook])
assert.deepEqual(Array.from(systems, item => item.key), ["storm:al012026", "outlook:al-outlook-1"])
assert.equal(model.selectedKeyAfterRefresh(systems, "outlook:al-outlook-1"), "outlook:al-outlook-1")
assert.equal(model.selectedKeyAfterRefresh(systems, "missing"), "storm:al012026")

const regionRows = model.regionalRows([storm], [outlook])
assert.equal(regionRows[0].kind, "region")
assert.equal(regionRows[0].name, "Atlantic")
assert.equal(regionRows[0].activeCount, 1)
assert.equal(regionRows[0].outlookCount, 1)
assert.equal(regionRows.filter(row => row.kind === "region").length, 3)
const disclosedRows = model.disclosedRegionalRows([storm], [outlook], "al")
assert.equal(disclosedRows.filter(row => row.kind === "region").length, 3)
assert.equal(disclosedRows.filter(row => row.kind === "system").length, 2)
assert.equal(model.disclosedRegionalRows([storm], [outlook], "").length, 3)

const globe = model.orthographicPoint(20, -70, 20, -70)
assert.ok(Math.abs(globe.x) < 1e-9)
assert.ok(Math.abs(globe.y) < 1e-9)
assert.ok(globe.z > 0.999)
const inverse = model.inverseOrthographic(globe.x, globe.y, 20, -70)
assert.ok(Math.abs(inverse.latitude - 20) < 1e-9)
assert.ok(Math.abs(inverse.longitude + 70) < 1e-9)
const sphericalFit = model.orthographicFit(model.systemCoordinates(storm), bounds)
assert.equal(sphericalFit.centreLatitude, bounds.centreLatitude)
assert.equal(sphericalFit.centreLongitude, bounds.centreLongitude)
assert.ok(sphericalFit.horizontalExtent > 0.08)
assert.ok(sphericalFit.verticalExtent > 0.05)
assert.ok(sphericalFit.minimumDepth > 0.9)
assert.ok(model.regionCoordinates([storm], [outlook], "al").length > model.systemCoordinates(storm).length)

assert.equal(model.alertRegionCode("Atlantic"), "al")
assert.equal(model.alertThresholdValue("Medium (40%)"), 40)
assert.equal(model.alertRegionDataComplete("Atlantic", []), true)
assert.equal(model.alertRegionDataComplete("Atlantic", ["al"]), false)
assert.equal(model.alertRegionDataComplete("Atlantic", ["ep"]), true)
assert.equal(model.alertRegionDataComplete("Eastern Pacific", ["cp"]), false)
assert.equal(model.alertRegionDataComplete("Central Pacific", ["ep"]), false)
assert.equal(model.alertRegionDataComplete("All NHC basins", ["al"]), false)
assert.equal(model.alertRegionDataComplete("Off", ["al", "ep", "cp"]), true)
const quietSnapshot = model.alertSnapshot([], [outlook], "Atlantic", "Medium (40%)", true)
assert.equal(model.alertEvents({}, quietSnapshot).length, 0)
const developing = { ...outlook, sevenDayChance: 40 }
const developingSnapshot = model.alertSnapshot([], [developing], "Atlantic", "Medium (40%)", true)
assert.equal(model.alertEvents(quietSnapshot, developingSnapshot)[0].name, "Dolly")
const invest = {
  ...developing,
  name: "Central Tropical Atlantic (AL90)",
  title: "Central Tropical Atlantic (AL90)",
  classificationLabel: "Developing system"
}
const renamedInvest = {
  ...invest,
  name: "Western Tropical Atlantic (AL90)",
  title: "Western Tropical Atlantic (AL90)"
}
assert.equal(model.outlookStableIdentifier(invest), "al90")
assert.equal(model.alertEvents(
  model.alertSnapshot([], [invest], "Atlantic", "Medium (40%)", true),
  model.alertSnapshot([], [renamedInvest], "Atlantic", "Medium (40%)", true)
).length, 0)
const reusedFarInvest = {
  ...invest,
  name: "Eastern Tropical Atlantic (AL90)",
  title: "Eastern Tropical Atlantic (AL90)",
  latitude: 16.2,
  longitude: -25,
  area: [[[-27, 15], [-23, 15], [-23, 17], [-27, 17], [-27, 15]]]
}
assert.equal(model.outlookSnapshotIdentityMatches(invest, reusedFarInvest), false)
assert.equal(model.alertEvents(
  model.alertSnapshot([], [invest], "Atlantic", "Medium (40%)", true),
  model.alertSnapshot([], [reusedFarInvest], "Atlantic", "Medium (40%)", true)
).length, 1)
const reusedInvestWatch = {
  id: "reused-invest-watch",
  name: "Mid-Atlantic",
  latitude: 16.2,
  longitude: -38,
  radiusKm: 2000
}
const oldInvestWatchSnapshot = model.watchAlertSnapshot(
  [], [invest], [reusedInvestWatch], "Medium (40%)"
)
const reusedInvestWatchSnapshot = model.watchAlertSnapshot(
  [], [reusedFarInvest], [reusedInvestWatch], "Medium (40%)"
)
assert.equal(Object.values(oldInvestWatchSnapshot)[0].meetsThreshold, true)
assert.equal(Object.values(reusedInvestWatchSnapshot)[0].meetsThreshold, true)
assert.equal(model.watchAlertEvents(
  oldInvestWatchSnapshot, reusedInvestWatchSnapshot
).length, 1)
assert.equal(model.alertEvents(
  model.alertSnapshot([], [invest], "Atlantic", "Medium (40%)", true),
  model.alertSnapshot([], [{
    ...renamedInvest,
    name: "Western Tropical Atlantic (AL91)",
    title: "Western Tropical Atlantic (AL91)"
  }], "Atlantic", "Medium (40%)", true)
).length, 1)
const renumberedDeveloping = { ...developing, id: "al-outlook-2", longitude: -52 }
const renumberedDevelopingSnapshot = model.alertSnapshot(
  [], [renumberedDeveloping], "Atlantic", "Medium (40%)", true
)
assert.equal(model.alertEvents(developingSnapshot, renumberedDevelopingSnapshot).length, 0)
const renumberedRisingSnapshot = model.alertSnapshot(
  [], [{ ...outlook, id: "al-outlook-2", longitude: -52, sevenDayChance: 40 }],
  "Atlantic", "Medium (40%)", true
)
assert.equal(model.alertEvents(quietSnapshot, renumberedRisingSnapshot).length, 1)
const reusedOutlookOrdinal = {
  ...developing,
  name: "New eastern Atlantic wave",
  title: "New eastern Atlantic wave",
  classificationLabel: "Developing system",
  latitude: 12,
  longitude: -30
}
assert.equal(model.alertEvents(
  developingSnapshot,
  model.alertSnapshot([], [reusedOutlookOrdinal], "Atlantic", "Medium (40%)", true)
).length, 1)
assert.equal(model.alertEvents(
  developingSnapshot,
  model.alertSnapshot([], [{
    ...reusedOutlookOrdinal,
    latitude: developing.latitude,
    longitude: developing.longitude
  }], "Atlantic", "Medium (40%)", true)
).length, 1)
assert.equal(model.alertEvents(
  developingSnapshot,
  model.alertSnapshot([], [{
    ...reusedOutlookOrdinal,
    id: "al-outlook-2",
    latitude: developing.latitude,
    longitude: developing.longitude + 0.5
  }], "Atlantic", "Medium (40%)", true)
).length, 1)
const partialGlobalSnapshot = model.alertSnapshot(
  [storm], [], "Atlantic", "Medium (40%)", true
)
const stabilizedGlobal = model.stabilizedAlertSnapshots(
  developingSnapshot, partialGlobalSnapshot, ["al"], []
)
assert.equal(stabilizedGlobal.current["outlook:al-outlook-1"].meetsThreshold, true)
assert.deepEqual(
  Array.from(model.alertEvents(stabilizedGlobal.before, stabilizedGlobal.current), item => item.key),
  ["storm:al012026"]
)
const recoveredGlobalSnapshot = model.alertSnapshot(
  [storm], [developing], "Atlantic", "Medium (40%)", true
)
const stabilizedRecovery = model.stabilizedAlertSnapshots(
  stabilizedGlobal.current, recoveredGlobalSnapshot, [], []
)
assert.equal(model.alertEvents(stabilizedRecovery.before, stabilizedRecovery.current).length, 0)
const newlyRecoveredOutlook = {
  ...developing,
  id: "al-outlook-new",
  name: "New Atlantic wave"
}
const recoveryWithNewOutlook = model.stabilizedAlertSnapshots(
  stabilizedGlobal.current,
  model.alertSnapshot(
    [storm], [developing, newlyRecoveredOutlook], "Atlantic", "Medium (40%)", true
  ),
  [], []
)
assert.deepEqual(
  Array.from(model.alertEvents(
    recoveryWithNewOutlook.before, recoveryWithNewOutlook.current
  ), item => item.key),
  ["outlook:al-outlook-new"]
)
const easternPacificDeveloping = {
  ...developing,
  id: "ep-outlook-1",
  basin: "ep",
  name: "Eastern Pacific wave"
}
const healthyBasinDuringPartial = model.stabilizedAlertSnapshots(
  model.alertSnapshot([], [developing], "All NHC basins", "Medium (40%)", true),
  model.alertSnapshot([], [easternPacificDeveloping], "All NHC basins", "Medium (40%)", true),
  ["al"], []
)
assert.deepEqual(
  Array.from(model.alertEvents(
    healthyBasinDuringPartial.before, healthyBasinDuringPartial.current
  ), item => item.key),
  ["outlook:ep-outlook-1"]
)

const easternPacificBoundaryOutlook = {
  ...developing,
  id: "ep-outlook-1",
  basin: "ep",
  sourceBasin: "ep",
  name: "Pacific boundary disturbance",
  title: "Pacific boundary disturbance",
  latitude: 15,
  longitude: -139.8,
  area: [[[-141, 14], [-139, 14], [-139, 16], [-141, 16], [-141, 14]]]
}
const centralPacificBoundaryOutlook = {
  ...easternPacificBoundaryOutlook,
  id: "cp-outlook-1",
  basin: "cp",
  sourceBasin: "cp",
  longitude: -140.2
}
const allBasinsBeforeBoundary = model.alertSnapshot(
  [], [easternPacificBoundaryOutlook], "All NHC basins", "Medium (40%)", true
)
const allBasinsAfterBoundary = model.alertSnapshot(
  [], [centralPacificBoundaryOutlook], "All NHC basins", "Medium (40%)", true
)
assert.equal(model.alertEvents(allBasinsBeforeBoundary, allBasinsAfterBoundary).length, 0)
const stabilizedAllBasinsBoundary = model.stabilizedAlertSnapshots(
  allBasinsBeforeBoundary, allBasinsAfterBoundary, ["ep"], []
)
assert.equal(Object.keys(stabilizedAllBasinsBoundary.current).length, 1)
assert.equal(model.alertEvents(
  stabilizedAllBasinsBoundary.before, stabilizedAllBasinsBoundary.current
).length, 0)
const easternBoundaryInvest = {
  ...easternPacificBoundaryOutlook,
  name: "Pacific boundary disturbance (EP90)",
  title: "Pacific boundary disturbance (EP90)"
}
const centralBoundaryInvest = {
  ...centralPacificBoundaryOutlook,
  name: "Pacific boundary disturbance (CP90)",
  title: "Pacific boundary disturbance (CP90)"
}
assert.equal(model.alertEvents(
  model.alertSnapshot(
    [], [easternBoundaryInvest], "All NHC basins", "Medium (40%)", true
  ),
  model.alertSnapshot(
    [], [centralBoundaryInvest], "All NHC basins", "Medium (40%)", true
  )
).length, 0)
assert.equal(model.alertEvents(
  allBasinsBeforeBoundary,
  model.alertSnapshot([], [{
    ...centralPacificBoundaryOutlook,
    name: "Different Pacific disturbance",
    title: "Different Pacific disturbance"
  }], "All NHC basins", "Medium (40%)", true)
).length, 1)
assert.equal(model.alertEvents(
  model.alertSnapshot(
    [], [easternPacificBoundaryOutlook], "Central Pacific", "Medium (40%)", true
  ),
  model.alertSnapshot(
    [], [centralPacificBoundaryOutlook], "Central Pacific", "Medium (40%)", true
  )
).length, 1)

const pacificBoundaryPlace = {
  id: "pacific-boundary",
  name: "Pacific boundary",
  latitude: 15,
  longitude: -140,
  radiusKm: 500
}
const boundaryPlaceBefore = model.watchAlertSnapshot(
  [], [easternPacificBoundaryOutlook], [pacificBoundaryPlace], "Medium (40%)"
)
const boundaryPlaceAfter = model.watchAlertSnapshot(
  [], [centralPacificBoundaryOutlook], [pacificBoundaryPlace], "Medium (40%)"
)
assert.equal(model.watchAlertEvents(
  boundaryPlaceBefore, boundaryPlaceAfter
).length, 0)
const stabilizedBoundaryPlace = model.stabilizedAlertSnapshots(
  boundaryPlaceBefore, boundaryPlaceAfter, ["ep"], []
)
assert.equal(Object.keys(stabilizedBoundaryPlace.current).length, 1)
assert.equal(model.watchAlertEvents(
  stabilizedBoundaryPlace.before, stabilizedBoundaryPlace.current
).length, 0)

const centralPacificSourcePlace = {
  id: "central-pacific-source",
  name: "Central Pacific source",
  latitude: 15,
  longitude: -155,
  radiusKm: 500
}
const relabeledEasternSourceOutlook = {
  ...centralPacificBoundaryOutlook,
  id: "cp-outlook-ep-source",
  sourceBasin: "ep",
  longitude: -155,
  area: [[[-156, 14], [-154, 14], [-154, 16], [-156, 16], [-156, 14]]]
}
const relabeledSourceSnapshot = model.alertSnapshot(
  [], [relabeledEasternSourceOutlook], "All NHC basins", "Medium (40%)", true
)
assert.equal(
  relabeledSourceSnapshot["outlook:cp-outlook-ep-source"].sourceBasin,
  "ep"
)
const preservedEasternSource = model.stabilizedAlertSnapshots(
  relabeledSourceSnapshot,
  model.alertSnapshot([], [], "All NHC basins", "Medium (40%)", true),
  ["ep"], []
)
assert.equal(
  preservedEasternSource.current["outlook:cp-outlook-ep-source"].meetsThreshold,
  true
)
const recoveredEasternSource = model.stabilizedAlertSnapshots(
  preservedEasternSource.current, relabeledSourceSnapshot, [], []
)
assert.equal(model.alertEvents(
  recoveredEasternSource.before, recoveredEasternSource.current
).length, 0)
const dedicatedCentralReplacement = {
  ...relabeledEasternSourceOutlook,
  id: "cp-outlook-cp-source",
  sourceBasin: "cp"
}
const stabilizedSourceReplacement = model.stabilizedAlertSnapshots(
  relabeledSourceSnapshot,
  model.alertSnapshot(
    [], [dedicatedCentralReplacement], "All NHC basins", "Medium (40%)", true
  ),
  ["ep"], []
)
assert.equal(Object.keys(stabilizedSourceReplacement.current).length, 1)
assert.equal(model.alertEvents(
  stabilizedSourceReplacement.before, stabilizedSourceReplacement.current
).length, 0)
const dedicatedCentralSnapshot = model.alertSnapshot(
  [], [dedicatedCentralReplacement], "All NHC basins", "Medium (40%)", true
)
const stabilizedHealthyEasternReplacement = model.stabilizedAlertSnapshots(
  dedicatedCentralSnapshot, relabeledSourceSnapshot, ["cp"], []
)
assert.equal(Object.keys(stabilizedHealthyEasternReplacement.current).length, 1)
assert.equal(model.alertEvents(
  stabilizedHealthyEasternReplacement.before,
  stabilizedHealthyEasternReplacement.current
).length, 0)
const renamedEasternSourceOutlook = {
  ...relabeledEasternSourceOutlook,
  id: "cp-outlook-ep-source-renamed"
}
const renamedEasternSourceSnapshot = model.alertSnapshot(
  [], [renamedEasternSourceOutlook], "All NHC basins", "Medium (40%)", true
)
const stabilizedSameSourceReplacement = model.stabilizedAlertSnapshots(
  relabeledSourceSnapshot, renamedEasternSourceSnapshot, ["cp"], []
)
assert.equal(Object.keys(stabilizedSameSourceReplacement.current).length, 1)
assert.equal(model.alertEvents(
  stabilizedSameSourceReplacement.before,
  stabilizedSameSourceReplacement.current
).length, 0)
assert.equal(model.watchPlaceTouchesOutlookBasin(centralPacificSourcePlace, "ep"), true)
const relabeledSourcePlaceSnapshot = model.watchAlertSnapshot(
  [], [relabeledEasternSourceOutlook], [centralPacificSourcePlace], "Medium (40%)"
)
const dedicatedCentralPlaceSnapshot = model.watchAlertSnapshot(
  [], [dedicatedCentralReplacement], [centralPacificSourcePlace], "Medium (40%)"
)
const stabilizedHealthyEasternPlaceReplacement = model.stabilizedAlertSnapshots(
  dedicatedCentralPlaceSnapshot, relabeledSourcePlaceSnapshot, ["cp"], []
)
assert.equal(Object.keys(stabilizedHealthyEasternPlaceReplacement.current).length, 1)
assert.equal(model.watchAlertEvents(
  stabilizedHealthyEasternPlaceReplacement.before,
  stabilizedHealthyEasternPlaceReplacement.current
).length, 0)
const renamedEasternSourcePlaceSnapshot = model.watchAlertSnapshot(
  [], [renamedEasternSourceOutlook], [centralPacificSourcePlace], "Medium (40%)"
)
const stabilizedSameSourcePlaceReplacement = model.stabilizedAlertSnapshots(
  relabeledSourcePlaceSnapshot, renamedEasternSourcePlaceSnapshot, ["cp"], []
)
assert.equal(Object.keys(stabilizedSameSourcePlaceReplacement.current).length, 1)
assert.equal(model.watchAlertEvents(
  stabilizedSameSourcePlaceReplacement.before,
  stabilizedSameSourcePlaceReplacement.current
).length, 0)
const preservedEasternSourcePlace = model.stabilizedAlertSnapshots(
  relabeledSourcePlaceSnapshot, {}, ["ep"], []
)
const easternSourceSummary = model.watchPlaceSummaries(
  [], [], [centralPacificSourcePlace], "Medium (40%)", false,
  {
    snapshot: preservedEasternSourcePlace.current,
    incompleteOutlookBasins: ["ep"]
  }
)[0]
assert.equal(easternSourceSummary.state, "heads-up")
assert.equal(easternSourceSummary.dataLimited, true)
assert.match(easternSourceSummary.detail, /update incomplete$/)
assert.equal(model.watchAlertEvents(
  preservedEasternSourcePlace.current, relabeledSourcePlaceSnapshot
).length, 0)

const home = {
  id: "home",
  name: "Home",
  latitude: 27.5,
  longitude: -78.5,
  radiusKm: 250
}
const focusedPlace = model.watchPlaceFocus(home, 4.25, 1, 8)
assert.equal(focusedPlace.centreLatitude, home.latitude)
assert.equal(focusedPlace.centreLongitude, home.longitude)
assert.equal(focusedPlace.zoom, 4.25)
assert.equal(model.watchPlaceFocus(home, 1.1, 1, 8).zoom, 2.2)
assert.deepEqual(
  { ...model.normalizeWatchPlace({ ...home, name: "  Home\nbase  ", radiusKm: 9999 }) },
  { ...home, name: "Home base", radiusKm: 2000 }
)
assert.equal(model.normalizeWatchPlace({ ...home, radiusKm: undefined }).radiusKm, 1000)
assert.ok(model.haversineDistanceKm(25.7617, -80.1918, 27.9506, -82.4572) > 250)
assert.ok(model.haversineDistanceKm(25.7617, -80.1918, 27.9506, -82.4572) < 400)
const watchCircle = model.watchCircleCoordinates(home, 32)
assert.equal(watchCircle.length, 33)
assert.ok(Math.abs(model.haversineDistanceKm(
  home.latitude, home.longitude, watchCircle[0].latitude, watchCircle[0].longitude
) - home.radiusKm) < 1)
assert.equal(model.watchPlaceCoverage(home).supported, true)
assert.equal(model.watchPlaceCoverage({ ...home, longitude: 139.69 }).supported, false)

const unsupportedPlace = {
  id: "unsupported",
  name: "Outside coverage",
  latitude: -1,
  longitude: -73,
  radiusKm: 2000
}
const unsupportedStorm = {
  ...storm,
  id: "al-unsupported",
  latitude: -1,
  longitude: -73,
  track: [{ latitude: -1, longitude: -73 }],
  cone: []
}
const unsupportedSnapshot = model.watchAlertSnapshot(
  [unsupportedStorm], [], [unsupportedPlace], "Medium (40%)"
)
assert.equal(Object.keys(unsupportedSnapshot).length, 0)
assert.equal(model.watchAlertEvents({}, unsupportedSnapshot).length, 0)
assert.equal(model.watchPlaceSummaries(
  [unsupportedStorm], [], [unsupportedPlace], "Medium (40%)"
)[0].state, "unsupported")

const stormProximity = model.stormWatchProximity(storm, home)
assert.equal(stormProximity.distanceKm, 0)
assert.equal(stormProximity.source, "cone")
const placeSnapshot = model.watchAlertSnapshot([storm], [], [home], "Medium (40%)")
assert.equal(placeSnapshot["place:home|storm:al012026"].meetsThreshold, true)
assert.equal(model.watchAlertEvents({}, placeSnapshot)[0].placeName, "Home")
assert.equal(model.watchAlertEvents(placeSnapshot, placeSnapshot).length, 0)
assert.equal(model.watchPlaceSummaries([storm], [], [home], "Medium (40%)")[0].state, "monitor")

const family = {
  id: "family",
  name: "Family",
  latitude: 23,
  longitude: -71,
  radiusKm: 100
}
const formationSnapshot = model.watchAlertSnapshot([], [developing], [family], "Medium (40%)")
assert.equal(formationSnapshot["place:family|outlook:al-outlook-1"].meetsThreshold, true)
assert.equal(model.watchPlaceSummaries([], [developing], [family], "Medium (40%)")[0].state, "heads-up")
const renumberedFormationSnapshot = model.watchAlertSnapshot(
  [], [renumberedDeveloping], [family], "Medium (40%)"
)
assert.equal(model.watchAlertEvents(
  formationSnapshot, renumberedFormationSnapshot
).length, 0)
assert.equal(model.watchAlertEvents(
  model.watchAlertSnapshot([], [invest], [family], "Medium (40%)"),
  model.watchAlertSnapshot([], [renamedInvest], [family], "Medium (40%)")
).length, 0)
const reusedPlaceOrdinal = {
  ...developing,
  name: "New Caribbean disturbance",
  title: "New Caribbean disturbance",
  classificationLabel: "Developing system",
  latitude: 23,
  longitude: -71,
  area: [[[-72, 22], [-70, 22], [-70, 24], [-72, 24], [-72, 22]]]
}
assert.equal(model.watchAlertEvents(
  formationSnapshot,
  model.watchAlertSnapshot([], [reusedPlaceOrdinal], [family], "Medium (40%)")
).length, 1)
assert.equal(model.watchAlertEvents(
  formationSnapshot,
  model.watchAlertSnapshot([], [{
    ...reusedPlaceOrdinal,
    id: "al-outlook-2"
  }], [family], "Medium (40%)")
).length, 1)
const lowFormationSnapshot = model.watchAlertSnapshot([], [outlook], [family], "Medium (40%)")
assert.equal(model.watchAlertEvents(lowFormationSnapshot, formationSnapshot).length, 1)
const basinFormationEvent = model.alertEvents(quietSnapshot, developingSnapshot)[0]
const placeFormationEvent = model.watchAlertEvents(lowFormationSnapshot, formationSnapshot)[0]
const coalescedFormationEvents = model.coalesceAlertEvents([
  basinFormationEvent, placeFormationEvent
])
assert.equal(coalescedFormationEvents.length, 1)
assert.equal(coalescedFormationEvents[0].scope, "place")
assert.equal(model.coalesceAlertEvents([
  basinFormationEvent,
  placeFormationEvent,
  { ...placeFormationEvent, placeId: "family-two", placeName: "Family two" }
]).length, 2)

const cancun = {
  id: "cancun",
  name: "Cancun",
  latitude: 21.1225,
  longitude: -86.8261,
  radiusKm: 1000
}
assert.equal(
  model.watchPlaceSummaries([], [], [cancun], "Medium (40%)", true)[0].detail,
  "620 mi forecast awareness · NHC only"
)
const caribbeanFormation = {
  ...outlook,
  id: "al-outlook-caribbean",
  name: "Eastern Atlantic wave",
  latitude: 15.5,
  longitude: -50,
  sevenDayChance: 70,
  area: [[[-84, 18], [-77, 18], [-77, 25], [-84, 25], [-84, 18]]]
}
const caribbeanHeadsUp = model.watchAlertSnapshot(
  [], [caribbeanFormation], [cancun], "High (70%)"
)
assert.equal(caribbeanHeadsUp["place:cancun|outlook:al-outlook-caribbean"].attentionLevel, "heads-up")
assert.equal(model.watchPlaceSummaries(
  [], [caribbeanFormation], [cancun], "High (70%)"
)[0].state, "heads-up")

const caribbeanMonitor = {
  ...storm,
  id: "al022026",
  name: "Bea",
  latitude: 17.3,
  longitude: -59.6,
  track: [
    { forecastHour: 0, latitude: 17.3, longitude: -59.6 },
    { forecastHour: 72, latitude: 20.5, longitude: -72.5 },
    { forecastHour: 120, latitude: 22.2, longitude: -81.5 }
  ],
  cone: []
}
const monitorSnapshot = model.watchAlertSnapshot([caribbeanMonitor], [], [cancun], "Medium (40%)")
assert.equal(monitorSnapshot["place:cancun|storm:al022026"].attentionLevel, "monitor")
assert.equal(model.watchPlaceSummaries([caribbeanMonitor], [], [cancun], "Medium (40%)")[0].state, "monitor")

const incompleteForecastStorm = {
  ...caribbeanMonitor,
  track: [],
  cone: [],
  dataWarnings: ["track unavailable"]
}
const incompleteForecastSnapshot = model.watchAlertSnapshot(
  [incompleteForecastStorm], [], [cancun], "Medium (40%)"
)
const incompleteForecastKeys = model.incompleteForecastSystemKeys([incompleteForecastStorm])
assert.deepEqual(Array.from(incompleteForecastKeys), ["storm:al022026"])
const stabilizedForecast = model.stabilizedAlertSnapshots(
  monitorSnapshot, incompleteForecastSnapshot, [], incompleteForecastKeys
)
assert.equal(
  stabilizedForecast.current["place:cancun|storm:al022026"].attentionLevel,
  "monitor"
)
assert.equal(model.watchAlertEvents(
  stabilizedForecast.before, stabilizedForecast.current
).length, 0)
const preservedPartialSummary = model.watchPlaceSummaries(
  [incompleteForecastStorm], [], [cancun], "Medium (40%)", false,
  {
    snapshot: stabilizedForecast.current,
    incompleteSystemKeys: incompleteForecastKeys
  }
)[0]
assert.equal(preservedPartialSummary.state, "monitor")
assert.equal(preservedPartialSummary.dataLimited, true)
assert.match(preservedPartialSummary.detail, /update incomplete$/)
const unknownPartialSummary = model.watchPlaceSummaries(
  [incompleteForecastStorm], [], [cancun], "Medium (40%)", false,
  {
    snapshot: incompleteForecastSnapshot,
    incompleteSystemKeys: incompleteForecastKeys
  }
)[0]
assert.equal(unknownPartialSummary.state, "limited")
assert.equal(unknownPartialSummary.status, "DATA LIMITED")
assert.equal(unknownPartialSummary.dataLimited, true)
const missingOutlookSummary = model.watchPlaceSummaries(
  [], [], [cancun], "Medium (40%)", false,
  { incompleteOutlookBasins: ["al"] }
)[0]
assert.equal(missingOutlookSummary.state, "limited")
assert.equal(missingOutlookSummary.dataLimited, true)
const scopedPacificOutageSummaries = model.watchPlaceSummaries(
  [], [], [cancun, pacificBoundaryPlace], "Medium (40%)", false,
  { incompleteOutlookBasins: ["cp"] }
)
assert.equal(scopedPacificOutageSummaries[0].state, "quiet")
assert.equal(scopedPacificOutageSummaries[0].dataLimited, false)
assert.equal(scopedPacificOutageSummaries[1].state, "limited")
assert.equal(scopedPacificOutageSummaries[1].dataLimited, true)
const recoveredForecast = model.stabilizedAlertSnapshots(
  stabilizedForecast.current, monitorSnapshot, [], []
)
assert.equal(model.watchAlertEvents(
  recoveredForecast.before, recoveredForecast.current
).length, 0)

const quietForecastStorm = {
  ...caribbeanMonitor,
  track: [{ forecastHour: 120, latitude: 31, longitude: -62 }],
  cone: []
}
const quietForecastSnapshot = model.watchAlertSnapshot(
  [quietForecastStorm], [], [cancun], "Medium (40%)"
)
const completeTrackOnlyStorm = {
  ...caribbeanMonitor,
  cone: [],
  dataWarnings: ["cone unavailable"]
}
const completeTrackOnlySnapshot = model.watchAlertSnapshot(
  [completeTrackOnlyStorm], [], [cancun], "Medium (40%)"
)
const trackOnlyIncrease = model.stabilizedAlertSnapshots(
  quietForecastSnapshot,
  completeTrackOnlySnapshot,
  [],
  model.incompleteForecastSystemKeys([completeTrackOnlyStorm])
)
assert.equal(
  trackOnlyIncrease.current["place:cancun|storm:al022026"].attentionLevel,
  "monitor"
)
assert.equal(model.watchAlertEvents(
  trackOnlyIncrease.before, trackOnlyIncrease.current
).length, 1)

const incompleteCentralPacificStorm = {
  ...storm,
  id: "cp012026",
  basin: "cp",
  latitude: 15,
  longitude: -155,
  track: [],
  cone: [],
  dataWarnings: ["track unavailable", "cone unavailable"]
}
const incompleteCentralPacificKeys = model.incompleteForecastSystemKeys(
  [incompleteCentralPacificStorm]
)
const scopedForecastOutageSummaries = model.watchPlaceSummaries(
  [incompleteCentralPacificStorm], [], [cancun, pacificBoundaryPlace],
  "Medium (40%)", false,
  { incompleteSystemKeys: incompleteCentralPacificKeys }
)
assert.equal(scopedForecastOutageSummaries[0].state, "quiet")
assert.equal(scopedForecastOutageSummaries[0].dataLimited, false)
assert.equal(scopedForecastOutageSummaries[1].state, "limited")
assert.equal(scopedForecastOutageSummaries[1].dataLimited, true)

const coneOnlyStorm = {
  ...caribbeanMonitor,
  id: "al-cone-only",
  name: "Cone only",
  latitude: 17,
  longitude: -60,
  track: [
    { forecastHour: 0, latitude: 17, longitude: -60 },
    { forecastHour: 120, latitude: 29, longitude: -78 }
  ],
  cone: [[[-88, 19], [-84, 19], [-84, 23], [-88, 23], [-88, 19]]]
}
const coneOnlySnapshot = model.watchAlertSnapshot(
  [coneOnlyStorm], [], [cancun], "Medium (40%)"
)
assert.equal(coneOnlySnapshot["place:cancun|storm:al-cone-only"].proximitySource, "cone")
assert.equal(model.watchForecastLeadHours(
  coneOnlySnapshot["place:cancun|storm:al-cone-only"]
), 0)
assert.equal(
  model.watchPlaceSummaries(
    [coneOnlyStorm], [], [cancun], "Medium (40%)"
  )[0].detail,
  "Cone only · forecast cone reaches watch area"
)

const yucatanApproach = {
  ...caribbeanMonitor,
  latitude: 20.8,
  longitude: -80.2,
  track: [
    { forecastHour: 0, latitude: 20.8, longitude: -80.2 },
    { forecastHour: 24, latitude: 21.0, longitude: -83.0 },
    { forecastHour: 48, latitude: 21.2, longitude: -86.0 }
  ]
}
const urgentSnapshot = model.watchAlertSnapshot([yucatanApproach], [], [cancun], "Medium (40%)")
assert.equal(urgentSnapshot["place:cancun|storm:al022026"].attentionLevel, "urgent")
const urgentSummary = model.watchPlaceSummaries([yucatanApproach], [], [cancun], "Medium (40%)")[0]
assert.equal(urgentSummary.state, "urgent")
assert.match(urgentSummary.detail, /closest forecast .* · ~2d$/)
assert.equal(model.watchAlertEvents(monitorSnapshot, urgentSnapshot)[0].attentionLevel, "urgent")
assert.equal(model.watchAlertEvents(urgentSnapshot, urgentSnapshot).length, 0)
assert.equal(model.watchAttentionCount([
  { state: "quiet" }, { state: "heads-up" }, { state: "monitor" }, { state: "unsupported" }
]), 2)
assert.equal(model.watchAttentionCount(null), 0)
assert.equal(model.watchUnsupportedCount([
  { state: "quiet" }, { state: "unsupported" }, { state: "unsupported" }
]), 2)
assert.equal(model.watchUnsupportedCount(null), 0)
assert.equal(model.watchDataLimitedCount([
  { state: "quiet" }, { state: "limited", dataLimited: true },
  { state: "monitor", dataLimited: true }
]), 2)
assert.equal(model.watchDataLimitedCount(null), 0)
assert.equal(model.watchStrongestAttentionState([
  { state: "quiet" }, { state: "heads-up" }, { state: "monitor" }, { state: "urgent" }
]), "urgent")
assert.equal(model.watchStrongestAttentionState([{ state: "quiet" }]), "")

const yucatanDeparting = {
  ...yucatanApproach,
  track: [
    { forecastHour: 0, latitude: 20.8, longitude: -80.2 },
    { forecastHour: 24, latitude: 20.5, longitude: -76.0 },
    { forecastHour: 48, latitude: 20.0, longitude: -72.0 }
  ]
}
assert.equal(model.watchAlertSnapshot(
  [yucatanDeparting], [], [cancun], "Medium (40%)"
)["place:cancun|storm:al022026"].attentionLevel, "monitor")

assert.equal(model.safeOfficialUrl("https://www.nhc.noaa.gov/text/MIATCPAT1.shtml").length > 0, true)
assert.equal(model.safeOfficialUrl("http://www.nhc.noaa.gov/text"), "")
assert.equal(model.safeOfficialUrl("https://nhc.noaa.gov.attacker.example/text"), "")
assert.equal(model.activeSummary([]), "No active NHC cyclones")
assert.equal(model.activeSummary([storm]), "1 active cyclone: Ada")
assert.equal(model.selectedIndexAfterRefresh([storm], "al012026"), 0)
assert.equal(model.selectedIndexAfterRefresh([storm], "missing"), 0)
assert.equal(model.trackingSummary([storm], [outlook]), "1 active cyclone · 1 outlook area")
