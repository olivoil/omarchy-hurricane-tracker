# Architecture

Hurricane + Earthquake Tracker is one Omarchy plugin with three shell kinds:

```text
BarWidget.qml ────────┐
                      ├─ Service.qml ─ Process ─ bin/hurricane-tracker-data ─┬─ NOAA/NHC
HurricaneTracker.qml ─┘                                                     ├─ USGS earthquakes
        └─ StormMap.qml + Model.js + Natural Earth geometry                 ├─ Open-Meteo search
                                                                            ├─ Nominatim reverse lookup
                                                                            ├─ Omarchy/wttr.in default location
                                                                            └─ user cache/config
```

## Shared service

`Service.qml` is mounted once by the Omarchy shell. It owns refresh scheduling,
starts the helper process, validates the normalized payload, and exposes the
same cyclone, outlook, region, earthquake, and watch-place arrays to every bar
instance and the overlay. Tropical and earthquake fetches have independent
processes, refresh schedules, status, retry state, and caches. It maintains
separate session-local baselines for basin and
place-proximity alerts, then sends at most one grouped notification for a
refresh. This avoids one network poll per monitor and avoids startup
notification floods. If an outlook feed is unavailable when a basin alert is
armed or reconfigured, only that source waits for one quiet recovery payload;
named storms and healthy outlook feeds continue comparing against their live
baselines.

The service also resolves the system measurement family once from Qt's locale,
so the bar, overlay, and notifications present the same units. Model formatters
convert at the presentation boundary. Watch radii, proximity calculations, and
map geometry remain canonical kilometres, while source wind speeds remain
canonical mph. This keeps saved alert behavior stable and gives future tracker
modes, including earthquakes, one shared unit policy.

Watch places are a versioned local configuration, not part of the public NHC
payload. The helper validates at most 12 named coordinates with bounded radii
and atomically writes them with user-only permissions under the XDG config
directory. The schema also remembers whether the one-time default location has
been initialized, so removing it is durable. Saving coordinates never makes a
network request.

The first default alert reuses exact coordinates from Omarchy's weather state
when present. If the state only has a name, the existing Open-Meteo path resolves
it. With no configured weather location, the helper can make one bounded request
to wttr.in for a coarse IP-based city. The latter two paths run only while online
place lookup is enabled. The service exposes the resulting reserved watch place
to the overlay, but it otherwise behaves like an ordinary editable and removable
place.

Typed geographic searches use a separate short-lived process and never share
the cyclone refresh process. QML debounces input, keeps only the newest queued
query, and discards a completed response when its query is no longer current.
The optional setting can disable online search without disabling direct map
placement. Geographic results and reverse lookup suggest an initial place name,
which stays separately editable as the user's personal label. The edited label
is never sent to either provider.

While enabled, the service also manages the plugin-owned desktop entry that
exposes the overlay through
Omarchy's application launcher; it leaves any unmarked user entry untouched.
Launcher changes first record the latest desired state synchronously, then a
locked detached worker reconciles the desktop entry to that state. This keeps
plugin reload, disable, and removal operations correctly ordered.

`BarWidget.qml` stays deliberately small. Personal NHC location alerts retain
priority; otherwise it can summarize tropical activity or recent earthquakes.
It forwards settings to the shared service and opens the overlay through the
shell's normal plugin IPC route.

## Data boundary

`bin/hurricane-tracker-data` is a Python standard-library helper. It:

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
9. Downloads the fixed USGS M4.5+ weekly GeoJSON feed, rejects non-earthquake
   features and invalid event geometry, and writes a separate private cache.
10. Resolves the one-time default alert from local Omarchy weather coordinates,
    or from a bounded allowlisted lookup when online location lookup is enabled.

Remote text is normalized before it reaches QML. Browser actions are checked
again against NHC, USGS, and tsunami-information hostname allowlists in
`Model.js` before launch.

## Map renderer

`StormMap.qml` uses a native QML Canvas and one orthographic globe projection at
every scale. Zooming grows the sphere beyond the viewport, so curvature becomes
negligible around a storm without a geometric handoff to a flat map. Dragging
rotates the globe and feels like panning at close scale. The map remains offline
after the bundled Natural Earth geometry has loaded. A normal open starts with
the whole sphere, rotates toward the default location, and zooms to its watch
point. The earthquake layer uses a clearly labeled temporary arrival marker so
the camera target is not confused with an earthquake alert. Pointer or keyboard
map interaction cancels the flight, and the flight is skipped when Hyprland
animations are disabled. It draws:

- subdued country geometry and geographic grid;
- the selected official cone;
- a dashed preliminary past center track;
- the solid official forecast center track and forecast intensity points;
- current markers for every active system.
- NHC formation areas, probability markers, and directional connectors from a
  disturbance's current position toward its potential formation area.
- subtle user-defined watch points and geodesic radius rings.
- magnitude-scaled earthquake markers whose stable colors represent USGS PAGER
  impact estimates and whose opacity communicates age.

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
looks meteorological can be mistaken for observed conditions, so the tracker
only renders data it can name and source.

## Payload contract

The helper emits `schemaVersion: 2` with source status, fetch timestamps, three
region summaries, a maximum of 20 cyclones, and a maximum of 24 outlook areas.
Each cyclone contains the current summary, a discussion excerpt, and bounded
arrays named `pastTrack`, `track`, and `cone`. Each outlook contains NHC's
two-day and seven-day probabilities, discussion excerpt, marker, and bounded
formation polygons. Outlooks retain both their display `basin` and the
`sourceBasin` feed that supplied them, so partial-feed handling survives the
Eastern/Central Pacific display handoff. When NHC publishes one, an outlook
also contains a bounded `connector` from its current marker toward that area. The connector is
presentation-only; alert proximity continues to use the marker and official
formation polygon. Partial detail failure leaves the current cyclone visible
and adds a `dataWarnings` entry rather than dropping the whole advisory. Failed
outlook products are listed in `incompleteOutlookBasins`; available data stays
visible and the UI reports a partial feed. For entries tied to a failed outlook
basin or incomplete forecast geometry, only disappearance or a lower attention
level is held at the last reliable baseline. New entries and valid increases,
along with complete basins, named storms, and unrelated watched-place
transitions, continue to be evaluated.

The independent earthquake helper command emits `schemaVersion: 1`, source and
freshness status, and at most 500 normalized M4.5+ events. Each event includes
validated coordinates, magnitude, depth, occurrence/update times, review
status, optional shaking and felt-report values, optional PAGER color, and
allowlisted official USGS links. Failure can fall back only to the earthquake
cache; it never changes tropical alert baselines.
