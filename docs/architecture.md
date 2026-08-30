# Architecture

Hurricane Tracker is one Omarchy plugin with three shell kinds:

```text
BarWidget.qml ─┐                                      ┌─ NOAA/NHC
               ├─ Service.qml ─ Process ─ omanado-data├─ Open-Meteo search
               │                                  └─ Nominatim reverse lookup
Omanado.qml ───┘                                      └─ user cache/config
     └─ StormMap.qml + Model.js + Natural Earth geometry
```

## Shared service

`Service.qml` is mounted once by the Omarchy shell. It owns refresh scheduling,
starts the helper process, validates the normalized payload, and exposes the
same cyclone, outlook, region, and watch-place arrays to every bar instance and
the overlay. It maintains separate session-local baselines for basin and
place-proximity alerts, then sends at most one grouped notification for a
refresh. This avoids one network poll per monitor and avoids startup
notification floods.

The service also resolves the system measurement family once from Qt's locale,
so the bar, overlay, and notifications present the same units. Model formatters
convert at the presentation boundary. Watch radii, proximity calculations, and
map geometry remain canonical kilometres, while source wind speeds remain
canonical mph. This keeps saved alert behavior stable and gives future tracker
modes, including earthquakes, one shared unit policy.

Watch places are a versioned local configuration, not part of the public NHC
payload. The helper validates at most 12 named coordinates with bounded radii
and atomically writes them with user-only permissions under the XDG config
directory. Saving coordinates never makes a network request.

Typed geographic searches use a separate short-lived process and never share
the cyclone refresh process. QML debounces input, keeps only the newest queued
query, and discards a completed response when its query is no longer current.
The optional setting can disable online search without disabling direct map
placement. Geographic results and reverse lookup suggest an initial place name,
which stays separately editable as the user's personal label. The edited label
is never sent to either provider.

`BarWidget.qml` stays deliberately small. It shows whether any systems are
active, forwards settings to the shared service, and opens the overlay through
the shell's normal plugin IPC route.

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
7. Validates and privately persists the separate watch-place configuration.
8. Sends bounded typed lookups only to Open-Meteo's fixed HTTPS search endpoint
   and user-selected coordinates only to Nominatim's fixed HTTPS reverse
   endpoint. Both refuse redirects; typed search normalizes at most eight safe
   results, while stale reverse results are discarded before reaching the UI.

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
- subtle user-defined watch points and geodesic radius rings.

Place relevance is calculated locally. Formation areas trigger only after the
configured seven-day probability threshold is met and their geometry enters a
watch radius. Active cyclones trigger when the official center track or cone of
uncertainty enters a radius. The UI and notification copy call these
"heads-up" and "monitor" states rather than estimating an unsupported local
impact probability.

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
and adds a `dataWarnings` entry rather than dropping the whole advisory. Failed
outlook products are listed in `incompleteOutlookBasins`; available data stays
visible, the UI reports a partial feed, and alert baselines remain frozen until
all outlook products are complete again.
