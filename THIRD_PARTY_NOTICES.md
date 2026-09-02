# Third-party notices

## Natural Earth

The derived geometry in `assets/countries.json` comes from Natural Earth
v5.1.2, 1:110m Admin 0 Countries with boundary lakes.

Natural Earth data is in the public domain. See
<https://www.naturalearthdata.com/about/terms-of-use/>.

## NOAA and National Hurricane Center data

The tracker retrieves public weather products from the National Oceanic and
Atmospheric Administration's National Hurricane Center. NOAA and NHC names are
used only to identify the source. They do not imply endorsement of the plugin.

NHC notes that its GIS feeds are experimental conveniences, may not always be
available or timely, and must not be relied upon for life-threatening
decisions. See <https://www.nhc.noaa.gov/gis/>.

## USGS Earthquake Hazards Program data

The tracker retrieves the public magnitude 4.5+ weekly GeoJSON summary from
the U.S. Geological Survey Earthquake Hazards Program. USGS names and PAGER
labels identify the source and do not imply endorsement. Event parameters are
preliminary and can change as observations are reviewed. See
<https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php>.

## Open-Meteo and GeoNames place data

Optional typed location search uses Open-Meteo's Geocoding API. Open-Meteo's
location results are based on GeoNames data. See
<https://open-meteo.com/en/docs/geocoding-api> and
<https://www.geonames.org/>.

## OpenStreetMap and Nominatim place data

Optional naming of points selected directly on the map uses the public
Nominatim reverse-geocoding service. Place data is © OpenStreetMap contributors
and available under the Open Data Commons Open Database License (ODbL).
See <https://www.openstreetmap.org/copyright> and
<https://operations.osmfoundation.org/policies/nominatim/>.

## wttr.in automatic location

When Omarchy has no configured weather location and online place lookup is
enabled, the tracker can make one fixed JSON request to wttr.in to obtain a
coarse IP-based city and coordinate for the removable default alert. See
<https://wttr.in/>.
