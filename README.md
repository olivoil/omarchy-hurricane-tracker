# Hurricane + Earthquake Tracker

Hurricane + Earthquake Tracker adds a live-hazards icon to your Omarchy bar.
Open it to switch between National Hurricane Center (NHC) tropical activity
and recent worldwide earthquakes from the USGS Earthquake Hazards Program.

![Hurricane Tracker showing Tropical Storm Karina's forecast cone, nearby systems, and NHC forecast discussion](preview.png)

Tropical coverage spans the Atlantic, Eastern Pacific, and Central Pacific
basins; it does not include storms tracked only by the JTWC or other agencies.
Earthquake coverage is worldwide for events in the selected USGS weekly feed.

## Features

- Active storms and developing systems, grouped by basin
- Official forecast tracks and cones of uncertainty
- Past tracks and intensity history
- Two-day and seven-day formation chances for NHC outlook areas
- Forecast intensity shown with both labels and color
- Excerpts from the latest NHC discussions, with links to the full advisories
- Optional notifications for new cyclones and rising formation chances
- A global Alerts destination for locally saved locations and proximity notifications
- Typed city, region, and postal-code search while positioning an alert destination
- Keyboard navigation, map controls, and support for reduced motion
- Cached data when the NHC is temporarily unavailable
- Worldwide magnitude 4.5+ earthquakes from the past seven days
- Magnitude-scaled map markers, depth, shaking, felt reports, and USGS PAGER impact
- Sticky, collapsible earthquake time buckets with faster mouse-wheel paging
- Independent NHC and USGS refresh schedules and caches

The map is rendered locally in QML using bundled Natural Earth geometry. The
plugin does not need an API key or extra Python packages, and it does not
install a background daemon.

## Install

Hurricane + Earthquake Tracker requires Omarchy Quattro with Quickshell plugin support and
Python 3.

```bash
omarchy plugin add https://github.com/olivoil/omarchy-hurricane-tracker.git --enable
```

Once enabled, open it from `Super+Space` by searching for
**Hurricane + Earthquake Tracker**.
The plugin removes its launcher entry when it is disabled or uninstalled.

It needs HTTPS access to `nhc.noaa.gov` and `www.nhc.noaa.gov` for tropical
advisories and to `earthquake.usgs.gov` for the official M4.5+ weekly GeoJSON
feed. Typed place search uses
`geocoding-api.open-meteo.com`; map placement still works when online place
search is disabled.

## Settings and notifications

The tracker checks NHC data every 15 minutes and USGS earthquake data every
five minutes by default. Both intervals can be changed in Omarchy's bar settings.

Distances and speeds automatically follow the system measurement convention
inherited from Omarchy: miles and mph for imperial locales, kilometres and
km/h for metric locales. Alert radii stay stored in kilometres internally, so
changing the display convention does not change an alert area. A manual unit
override is not exposed yet.

Broad basin notifications are off until you choose a basin. You can be notified when:

- an outlook area's seven-day formation chance reaches 20%, 40%, or 70%; or
- the NHC begins issuing advisories for a new cyclone.

Alerts can cover the Atlantic, Eastern Pacific, Central Pacific, or all three.
When you turn them on, existing systems are treated as the starting point, so
you will not get a burst of notifications for storms already underway.

Open **Alerts** in the app header to save up to 12 locations such as home,
family, or a destination. Search for a city, region, or postal code, or click
its position directly on the globe. Give each location a watch radius from 250
km to 2,000 km, shown in the system's preferred units. A search result or nearby
map place supplies the initial name, then the separate **Name** field lets you
personalize it, so Sarasota can still be saved as “Mom’s Place.” The map keeps
saved locations quiet as dots and reveals their alert areas while editing.
Location notifications are sent when:

- an NHC formation area within that radius reaches your formation threshold; or
- an official NHC forecast cone or center track enters the radius.

Formation notifications are early awareness only. They do not claim that a
developing system will affect the saved place. Place notifications use the same
quiet starting baseline as basin notifications and are grouped when one refresh
produces several updates.

Watch places are stored locally in
`~/.config/hurricane-tracker/watch-places.json`, or under `$XDG_CONFIG_HOME`
when set. The file is written with user-only permissions. Current source
coverage is limited to NHC basins; a place elsewhere remains saved but is
marked as outside the current source coverage.

Online place lookup waits until typing pauses, then sends only the geographic
search text to Open-Meteo. Choosing a point on the globe sends that coordinate
to OpenStreetMap's Nominatim service once to suggest a nearby place name.
Personal labels, saved watch-place lists, and alert radii are never included.
Turn off **Online place lookup** in the plugin settings to keep globe placement
entirely local; coordinate labels remain available as a fallback.

## Controls

| Input | Action |
| --- | --- |
| Left-click the bar icon | Open or close the tracker |
| Middle-click the bar icon | Refresh NHC and USGS data |
| Right-click the bar icon | Open the most relevant official source |
| Click **Cyclones** or **Earthquakes** | Open the tracker menu |
| Click **Alerts** | View, add, edit, or remove watched locations |
| Click a system or map marker | Select it and fit it on the map |
| Click **View all** beside a basin | Fit every system in that always-open basin on the map |
| Click a watched location | Select it and fit it on the map |
| Click the map while adding a location | Set or move the watch point |
| Drag the map | Move around the globe |
| Mouse wheel over the map | Zoom at the pointer |
| Mouse wheel over the earthquake list | Page quickly with a mouse wheel; touchpad scrolling stays precise |
| Up / Down | Select the previous or next system |
| `+` / `-` | Zoom in or out |
| `F` | Fit the selected system |
| `G` or `0` | Show the whole globe |
| `R` | Refresh |
| `O` | Open the selected system's official source page |
| Page Up / Page Down / Home / End | Move quickly through the activity list |
| Escape | Close the current menu or alert view, then close the tracker |

## Data and safety

Active storm data comes from the NHC's
[`CurrentStorms.json`](https://www.nhc.noaa.gov/CurrentStorms.json) feed. The
plugin follows the KMZ links in that feed for forecast tracks, cones, and
preliminary best tracks. Formation areas and probabilities come from the NHC's
Graphical Tropical Weather Outlook products. It also fetches the linked text
products for forecast discussion excerpts.

Earthquake activity comes from the USGS
[`4.5_week.geojson`](https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_week.geojson)
summary feed. Only features identified as earthquakes with valid coordinates,
times, depths, and magnitudes are shown. PAGER colors are impact estimates, not
local warnings; a tsunami-information flag points users back to official guidance.

Cyclone requests are limited to NHC-owned HTTPS hosts, and earthquake requests
to `earthquake.usgs.gov`. Place lookups use only
Open-Meteo's fixed HTTPS search endpoint and OpenStreetMap Nominatim's fixed
HTTPS reverse endpoint. All interfaces refuse redirects and non-success
responses and enforce streaming response limits before parsing. Place-name
responses are capped at 64 KiB, Open-Meteo results are capped at eight, and
remote display fields and coordinates are validated again before QML renders
them. Reverse lookups are debounced, serialized, and discarded when they no
longer match the selected point.

Location results are provided by
[Open-Meteo](https://open-meteo.com/en/docs/geocoding-api) using
[GeoNames](https://www.geonames.org/) place data.
Map-click place names are provided by
[OpenStreetMap contributors](https://www.openstreetmap.org/copyright) through
[Nominatim](https://nominatim.org/release-docs/latest/api/Reverse/).

The latest public data is cached independently at
`~/.cache/hurricane-tracker/storms.json` and
`~/.cache/hurricane-tracker/earthquakes.json`. If `$XDG_CACHE_HOME` is set,
the same `hurricane-tracker` directory is used there instead.

> This tracker is an awareness tool, not an emergency warning system. The
> forecast cone shows the probable path of the storm's center; dangerous wind,
> rain, storm surge, and tornadoes can occur well outside it. Follow guidance
> from local authorities and official weather services.

## Update

```bash
omarchy plugin update io.github.olivoil.hurricane-tracker
omarchy restart shell
```

Restarting the shell makes sure the QML interface and data helper are updated
together. Your alert settings and watch places are preserved. Version 0.0.1
used a different cache location, so its first update starts a fresh weather
cache; later updates preserve the cache at the path above.

## Uninstall

```bash
omarchy plugin remove io.github.olivoil.hurricane-tracker
```

Omarchy leaves cached public data and saved watch places behind. If you want to
remove them as well, delete `~/.cache/hurricane-tracker/storms.json`,
`~/.cache/hurricane-tracker/earthquakes.json`, and
`~/.config/hurricane-tracker/watch-places.json`, or their equivalents under
your custom XDG directories.

## Development

Run the full test suite with:

```bash
./tests/run
```

For live development, link the checkout into your Omarchy plugin directory:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.olivoil.hurricane-tracker
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.olivoil.hurricane-tracker center
omarchy-shell shell summon io.github.olivoil.hurricane-tracker '{}'
```

The shell watches the linked directory and reloads saved QML files
automatically. See [`docs/architecture.md`](docs/architecture.md) for an
overview of the data pipeline and UI.

## License

Hurricane + Earthquake Tracker is licensed under the MIT License. The bundled Natural Earth
geometry is public domain; see
[`assets/NATURAL_EARTH.md`](assets/NATURAL_EARTH.md) and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for details.
