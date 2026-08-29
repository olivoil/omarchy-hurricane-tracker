# Architecture

Hurricane Tracker is one Omarchy plugin with three shell kinds:

```text
BarWidget.qml ─┐
               ├─ Service.qml ─ Process ─ bin/omanado-data ─ NOAA/NHC
Omanado.qml ───┘                         └─ user cache
     └─ StormMap.qml + Model.js + Natural Earth geometry
```

## Shared service

`Service.qml` is mounted once by the Omarchy shell. It owns refresh scheduling,
starts the helper process, validates the normalized payload, and exposes the
same cyclone, outlook, and region arrays to every bar instance and the overlay.
It also maintains a session-local alert baseline and sends at most one
region-scoped notification for a refresh. This avoids one network poll per
monitor and avoids startup notification floods.

`BarWidget.qml` stays deliberately small. It shows whether any systems are
active, forwards settings to the shared service, and opens the overlay through
the shell's normal plugin IPC route.

`Omanado.qml` treats a selected system, a regional overview, and the globe as
distinct semantic views. Opening a region clears the system selection so the
summary, forecast layers, timeline, and discussion cannot describe an off-map
cyclone. The most recent semantic view is stored with the plugin's inline shell
settings and restored on the next summon. If a remembered system disappears,
the overlay falls back to that system's region rather than another basin.

## Data boundary

`bin/omanado-data` is a Python standard-library helper. It:

1. Downloads NHC's current-storm JSON and three graphical outlook products
   from fixed URLs.
2. Accepts linked resources only from an HTTPS NHC hostname allowlist.
3. Downloads the forecast track, cone, preliminary best-track KMZ, and linked
   forecast discussion in bounded worker pools.
4. Rejects oversized responses, oversized expanded archives, unexpected KMZ
   structure, invalid coordinates, and malformed XML or JSON.
5. Normalizes the source documents into a versioned JSON contract.
6. Atomically writes a private cache and marks fallback data as stale.

Remote text is normalized before it reaches QML. Browser actions are checked
again against the NHC hostname allowlist in `Model.js` before launch.

## Map renderer

`StormMap.qml` uses a native QML Canvas and one orthographic globe projection at
every scale. Zooming grows the sphere beyond the viewport, so curvature becomes
negligible around a storm without a geometric handoff to a flat map. Dragging
rotates the globe and feels like panning at close scale. The map remains offline
after the bundled Natural Earth geometry has loaded. It draws:

- subdued country geometry and geographic grid;
- the selected official cone;
- a dashed preliminary past center track;
- the solid official forecast center track and forecast intensity points;
- current markers for every active system.
- NHC formation areas and probability markers for developing and remnant
  systems.

Shell chrome, land, ocean, grid, track, and cone colors are derived from the
active Omarchy menu background, foreground, and accent. Storm intensity and
formation probability retain a small stable semantic palette so their meaning
does not change when the desktop theme changes.

There is intentionally no simulated or decorative wind field. Motion that
looks meteorological can be mistaken for observed conditions, so Hurricane Tracker only
renders data it can name and source.

## Payload contract

The helper emits `schemaVersion: 2` with source status, fetch timestamps, three
region summaries, a maximum of 20 cyclones, and a maximum of 24 outlook areas.
Each cyclone contains the current summary, a discussion excerpt, and bounded
arrays named `pastTrack`, `track`, and `cone`. Each outlook contains NHC's
two-day and seven-day probabilities, discussion excerpt, marker, and bounded
formation polygons. Partial detail failure leaves the current cyclone visible
and adds a `dataWarnings` entry rather than dropping the whole advisory.
