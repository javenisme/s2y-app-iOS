# Health query tool schema

Health Assistant uses a versioned, closed request schema before reading HealthKit trend or comparison data.

```json
{
  "version": 1,
  "operation": "trend | compare_periods",
  "metric": "HealthKit MetricKind raw value",
  "windowDays": "integer from 1 through 90"
}
```

Validation happens locally before HealthKit is queried or an AI provider is contacted. Unknown operations fail JSON decoding. Unknown metrics, unsupported schema versions, zero-length windows, and windows above 90 days fail validation.

Natural-language parsing, chat chart selection, and AI health context use the same validated request. An invalid structured request returns a corrective message instead of silently changing its metric, operation, or time window. A query that does not describe a supported structured tool remains ordinary conversation.

HealthKit authorization and data-availability failures are not retried automatically: retrying cannot grant permission and must not obscure missing data. Read caching handles repeated valid requests.
