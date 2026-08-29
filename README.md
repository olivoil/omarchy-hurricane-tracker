# Hurricane Tracker

Hurricane Tracker is a native Omarchy weather plugin. Its compact bar signal
opens a calm, spatial view of active National Hurricane Center cyclones, their past and
forecast center tracks, official cone of uncertainty, and regional development
outlooks.

The project keeps its original `io.github.olivoil.omanado` plugin ID and cache
path so existing installations continue to update normally.

The interaction rhythm is inspired by Windy's hurricane view, but the plugin
uses its own native QML interface, public-domain map geometry, and official
NOAA/NHC data. It does not use Windy assets or APIs.

## What it does

- Shows active NHC cyclones and developing or remnant outlook areas
- Groups every system under Atlantic, Eastern Pacific, or Central Pacific
- Draws the official forecast center track and cone of uncertainty
- Shows the preliminary past track and intensity history
- Encodes current and forecast intensity with labels as well as color
- Captures a readable excerpt from the latest forecast discussion or tropical
  weather outlook, with a link to the complete official product
- Uses one rotatable globe at every scale; close views become locally flat
  without switching projections
- Can notify when formation odds cross a chosen threshold in a chosen region,
  or when NHC starts advisories for a new cyclone there
- Supports pan, zoom, system selection, keyboard navigation, and reduced visual noise
- Refreshes in one shared shell service, even on multi-monitor setups
- Falls back to a clearly marked cached advisory when NHC is unavailable
- Requires no API key and adds no background daemon

Hurricane Tracker currently covers the Atlantic, Eastern Pacific, and Central
Pacific basins represented by the NHC feed. It is not yet a global JTWC tracker.

## Install

```bash
omarchy plugin add https://github.com/olivoil/omarchy-hurricane-tracker.git --enable
```

The refresh interval and regional alerts can be changed in Omarchy's bar
settings. Polling defaults to 15 minutes. Alerts default to off; when enabled,
Hurricane Tracker quietly records the current systems as its baseline and only
announces a later threshold crossing or newly advised cyclone.

Formation thresholds follow the NHC seven-day outlook bands exposed by the
plugin: 20%, 40%, or 70%. The alert region can be Atlantic, Eastern Pacific,
Central Pacific, or all NHC basins.

## Runtime requirements

- Omarchy Quattro with its standard Quickshell plugin support
- Python 3; the bundled helper uses only the Python standard library
- HTTPS access to `nhc.noaa.gov` and `www.nhc.noaa.gov`

No API key, third-party Python package, privileged command, system service, or
manual setup is required.

## Controls

| Input | Action |
| --- | --- |
| Left click the bar signal | Open or close Hurricane Tracker |
| Middle click the bar signal | Refresh NHC data |
| Right click the bar signal | Open the NHC website |
| Click a system or map marker | Select and fit that system |
| Click a region heading | Expand or collapse it; opening also fits the region |
| Click **View all** | Refit the map to every system in the expanded basin |
| Drag the map | Rotate the globe, which feels like panning at close scale |
| Mouse wheel | Zoom at the pointer |
| Up / Down | Select the previous or next cyclone or outlook area |
| `+` / `-` | Zoom in or out |
| `F` | Fit the selected system |
| `G` or `0` | Show the whole globe |
| `R` | Refresh |
| `O` | Open the selected storm's official advisory |
| Escape | Close |

## Data, cache, and safety

Storm status comes from
[`CurrentStorms.json`](https://www.nhc.noaa.gov/CurrentStorms.json). Forecast
tracks, cones, and preliminary best tracks come from the KMZ links in that
official feed. Formation areas, probabilities, remnant systems such as Dolly,
and their narratives come from NHC's Graphical Tropical Weather Outlook KMZ
products. Forecast-discussion excerpts come from the linked NHC text product.
Hurricane Tracker only permits HTTPS requests to NHC-owned hostnames and bounds
every response and expanded archive before parsing it.

The last normalized response is stored at
`$XDG_CACHE_HOME/omanado/storms.json`, or `~/.cache/omanado/storms.json` when
`XDG_CACHE_HOME` is unset. The cache contains public weather data only and is
written with user-only permissions.

Hurricane Tracker is an awareness tool, not an emergency warning system. The
forecast cone describes the probable path of the storm center. Hazardous wind, rain,
surge, and tornadoes can occur well outside it. Follow local emergency
management and official weather guidance.

## Update

```bash
omarchy plugin update io.github.olivoil.omanado
omarchy restart shell
```

The restart ensures the updated QML interface and bundled data helper load
together. Alert settings and the cached public NHC response are preserved.

## Uninstall

```bash
omarchy plugin remove io.github.olivoil.omanado
```

This removes the plugin while leaving its public weather cache in
`~/.cache/omanado/`. Delete that directory separately if you also want to
discard the cached response.

## Development

Run the complete local check:

```bash
./tests/run
```

For live development, link the checkout into the user plugin directory:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.olivoil.omanado
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.olivoil.omanado center
omarchy-shell shell summon io.github.olivoil.omanado '{}'
```

The shell watches the linked directory and reloads saved QML automatically.
See [`docs/architecture.md`](docs/architecture.md) for the data and UI split.

## License

Hurricane Tracker is available under the MIT License. The bundled Natural Earth
geometry is public domain; see [`assets/NATURAL_EARTH.md`](assets/NATURAL_EARTH.md) and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
