# Cardiac analysis safety boundary

S2Y treats HealthKit cardiac metrics as user-owned observations for wellness and
health management. The app may show recorded values, coverage, trends, personal
baseline deviations, and descriptive relationships between paired observations.

The iOS app must not infer or display a diagnosis, cardiovascular risk level,
autonomic nervous system state, stress level, recovery readiness, or treatment
effect from fixed thresholds. It must not invent a target or imply that a change
is medically good or bad.

Supported interpretations are:

- coverage-aware summaries of observed HealthKit samples;
- comparison with the same user's sufficiently populated historical baseline;
- associations calculated from paired observed days, explicitly labeled as
  non-causal;
- optional general-wellness choices; and
- explicit emergency guidance triggered by user language, never by a HealthKit
  value classification.

Clinical interpretation requires an independently validated and reviewed medical
feature boundary. It is intentionally outside the current product scope.
