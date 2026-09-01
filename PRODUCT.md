# Hurricane + Earthquake Tracker

## Register

product

## Users

Omarchy users who care about tropical weather, recent significant earthquakes, or a saved home, family, or travel location. They may glance at the bar during an ordinary workday or open the full tracker as conditions develop. Their primary job is to understand what is happening, where, how recent and authoritative the data is, and whether an NHC forecast has become relevant to a watched place.

## Product Purpose

The plugin is a native Omarchy hazard tracker. A compact bar status opens one spatial, source-forward shell where users switch between National Hurricane Center cyclones and recent USGS earthquakes; a separate global Alerts destination holds locally saved NHC watch places. Success means a user can scan a hazard, understand a selected event in seconds, and opt into calm tropical basin or place awareness without mistaking the plugin for local emergency guidance.

## Brand Personality

Calm, exact, atmospheric. The tracker should feel composed during uncertain conditions, technically credible without looking clinical, and at home in the Omarchy desktop.

## Anti-references

- Alarmist interfaces that make every state red or urgent.
- Weather dashboards made from dense, repeated metric cards.
- Decorative wind animation that could be mistaken for observed conditions.
- A pixel-for-pixel Windy imitation or use of Windy's proprietary assets.
- Maps that hide source, update age, coverage limits, or uncertainty.

## Design Principles

1. Spatial first: the map is the primary explanation, and supporting text helps interpret it.
2. Severity has meaning: reserve strong color for storm intensity, forecast uncertainty, and actionable states.
3. Freshness is part of the data: show the source and advisory time wherever users judge risk.
4. Organize by hazard and place: preserve NHC's basin hierarchy, group earthquakes by recency, and keep named personal locations in a global Alerts destination without implying unsupported coverage.
5. Reveal detail progressively: start with regional or time-bucket activity, then expose the selected track, cone, formation area, earthquake detail, discussion, and official links.
6. Feel native to Omarchy: derive surfaces from the shell theme and use its interaction patterns, keyboard behavior, notifications, and lightweight plugin model.
7. Reward scale changes: use one coherent globe at every scale. World views reveal the sphere; storm-scale views become locally flat without changing projections or obscuring sourced data.

## Accessibility & Inclusion

Target WCAG 2.2 AA contrast. Never encode storm class or selection by color alone. Support keyboard navigation, clear focus states, reduced motion, readable labels, and touch targets of at least 40 by 40 pixels. Motion must stop when reduced motion is requested. Include a clear safety disclaimer and direct links to official advisories.
