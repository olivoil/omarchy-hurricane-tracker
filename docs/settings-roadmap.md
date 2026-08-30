# Settings roadmap

Status: product notes only. This is not an implemented settings screen.

## Product boundary

Settings should be a global app destination, separate from Cyclones,
Earthquakes, and Alerts. The hazard switcher chooses what the user is looking
at. Alerts manages watched places and their rules. Settings changes how the app
behaves everywhere.

A compact entry in the tracker menu or sidebar footer would scale better than
placing settings under one hazard. The screen can group app-wide preferences
first, followed by hazard-specific defaults.

## General

### Units

Options:

- **Auto (system)**: current behavior. Follow the Qt measurement convention
  inherited from the system locale. Imperial locales show miles and mph;
  metric locales show kilometres and km/h.
- **Metric**: always show kilometres and km/h.
- **Imperial**: always show miles and mph.

The selection should affect map distances, alert-radius choices, proximity
copy, wind and movement speeds, notifications, and future earthquake depths.
Pressure can remain in mb/hPa. Persisted coordinates and alert geometry should
remain in canonical units, with conversion only at the display boundary.

## Omarchy bar indicator

### Indicator scope

Options:

- **Automatic**: current behavior. When watched places exist, color and count
  reflect only saved locations needing attention. When no watched places exist,
  they reflect worldwide tracked activity. Quiet watched places show no badge.
- **Watched locations**: always reflect saved-location attention. With no saved
  places or no relevant activity, show the quiet icon with no count.
- **Global activity**: always reflect tracked systems worldwide, independent of
  saved locations.

### Indicator appearance

Possible controls:

- **Color**: Automatic attention severity, theme accent, or monochrome.
- **Count badge**: Show or hide the number while preserving color and tooltip
  state.
- **Tooltip detail**: Concise summary by default, with an optional expanded
  summary if users ask for it.

Automatic color should keep the existing meaning: neutral when quiet, amber
for monitoring, and urgent red only for activity that warrants immediate
attention near a watched place. The tooltip should state what the icon is
currently reflecting without repeating source branding.

## Hazard-specific defaults

Potential groups:

- **Cyclones**: basin-wide alerts, formation threshold, and named-storm
  notifications. These currently live in Omarchy's plugin settings and could
  move into the shared screen later.
- **Earthquakes**: default magnitude, depth, proximity, or impact thresholds.
  Final controls should follow the earthquake tracker's domain model rather
  than copying cyclone concepts.

Per-location alert radii and thresholds should stay in Alerts because they are
properties of a watched place, not global app preferences.

## Deferred decisions

- Exact navigation entry and whether the tracker menu or sidebar footer owns it.
- Whether indicator color customization is useful beyond automatic and
  monochrome.
- Whether each hazard needs its own unit exception, such as knots for cyclone
  wind or nautical miles for marine users.
- How existing Omarchy plugin settings migrate if a native in-app settings
  screen replaces them.
