#!/usr/bin/env node

import { createHash } from "node:crypto"
import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

const SOURCE = {
  name: "Natural Earth 1:110m Admin 0 Countries with boundary lakes",
  url: "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_admin_0_countries_lakes.geojson",
  sha256: "5b00e58dbf91618432ab13844377b40e2132feedf9a7f05fe7aeaa9fe33e8e16"
}
const OUTPUT = fileURLToPath(new URL("../assets/countries.json", import.meta.url))
const CHECK = process.argv.includes("--check")
const TOLERANCE = 0.045

function hash(value) {
  return createHash("sha256").update(value).digest("hex")
}

function distance(point, start, end) {
  const [x, y] = point
  const [x1, y1] = start
  const [x2, y2] = end
  const dx = x2 - x1
  const dy = y2 - y1
  if (dx === 0 && dy === 0) return Math.hypot(x - x1, y - y1)
  const amount = Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
  return Math.hypot(x - (x1 + amount * dx), y - (y1 + amount * dy))
}

function simplify(points) {
  if (points.length <= 2) return points
  let largest = 0
  let index = 0
  for (let candidate = 1; candidate < points.length - 1; candidate++) {
    const candidateDistance = distance(points[candidate], points[0], points[points.length - 1])
    if (candidateDistance > largest) {
      largest = candidateDistance
      index = candidate
    }
  }
  if (largest <= TOLERANCE) return [points[0], points[points.length - 1]]
  const left = simplify(points.slice(0, index + 1))
  const right = simplify(points.slice(index))
  return left.slice(0, -1).concat(right)
}

function simplifyRing(ring) {
  if (!Array.isArray(ring) || ring.length < 4) return []
  const rounded = ring.map(point => [Number(point[0].toFixed(3)), Number(point[1].toFixed(3))])
  const closed = rounded[0][0] === rounded[rounded.length - 1][0]
    && rounded[0][1] === rounded[rounded.length - 1][1]
  const open = closed ? rounded.slice(0, -1) : rounded
  if (open.length < 3) return []
  const pivot = open.reduce((best, point, index) => point[0] < open[best][0] ? index : best, 0)
  const rotated = open.slice(pivot).concat(open.slice(0, pivot), [open[pivot]])
  const result = simplify(rotated)
  if (result[0][0] !== result[result.length - 1][0]
      || result[0][1] !== result[result.length - 1][1]) result.push(result[0])
  return result.length >= 4 ? result : []
}

function simplifyGeometry(geometry) {
  const polygons = geometry.type === "Polygon" ? [geometry.coordinates]
    : geometry.type === "MultiPolygon" ? geometry.coordinates : []
  const output = []
  for (const polygon of polygons) {
    const outer = simplifyRing(polygon && polygon[0])
    if (outer.length > 0) output.push([outer])
  }
  return { type: "MultiPolygon", coordinates: output }
}

const response = await fetch(SOURCE.url)
if (!response.ok) throw new Error(`Could not download ${SOURCE.name}: HTTP ${response.status}`)
const sourceText = await response.text()
const actualHash = hash(sourceText)
if (actualHash !== SOURCE.sha256) throw new Error(`${SOURCE.name} checksum mismatch: ${actualHash}`)
const source = JSON.parse(sourceText)

const output = {
  type: "FeatureCollection",
  source: "Natural Earth v5.1.2, public domain",
  features: source.features.map(feature => ({
    type: "Feature",
    properties: {
      name: String(feature.properties.NAME || feature.properties.ADMIN || ""),
      code: String(feature.properties.ISO_A2 || ""),
      labelLongitude: Number(feature.properties.LABEL_X),
      labelLatitude: Number(feature.properties.LABEL_Y),
      labelRank: Number(feature.properties.LABELRANK || 9)
    },
    geometry: simplifyGeometry(feature.geometry)
  })).filter(feature => feature.geometry.coordinates.length > 0)
}
const encoded = JSON.stringify(output) + "\n"

if (CHECK) {
  if (readFileSync(OUTPUT, "utf8") !== encoded) {
    console.error("assets/countries.json is out of date; run scripts/build-map-data.mjs")
    process.exit(1)
  }
} else {
  writeFileSync(OUTPUT, encoded)
}
