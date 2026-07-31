# Provider Contract Fixtures

Shared contract fixtures keep the Swift (macOS) and ArkTS (HarmonyOS) provider
implementations from drifting. Both platforms parse the same recorded provider
response and assert the same expected snapshot.

## Layout

```
Contracts/Providers/<provider>/<case>-response.json   # raw provider API response
Contracts/Providers/<provider>/<case>-expected.json   # expected parsed snapshot subset
```

`<provider>` is the Swift `ProviderID` raw value lowercased (`deepseek`,
`apiinfo`, ...). Each case is a `<case>-response.json` / `<case>-expected.json`
pair.

The Swift test suite reads these files directly
(`Tests/QuotaGlanceCoreTests/ContractTests.swift`). The HarmonyOS ohosTest
suite reads copies synced into
`HarmonyOS/entry/src/ohosTest/resources/rawfile/contracts/` by
`scripts/sync-contracts-to-harmonyos.sh` — run it after adding or changing any
fixture.

## Expected-fixture schema

An expected file is a JSON object pinning a **subset** of `UsageSnapshot`
fields. Only fields present in the file are asserted; absent fields are
unchecked. Any of these keys may appear:

- `balances`: array of `{label, available: Money, breakdown: [{label, value: Money}]}`
- `spendingLimit`: `{label, used?: Money, limit?: Money, remaining?: Money, resetDescription?: string}`
- `spend`: `{today?: Money, week?: Money, month?: Money, total?: Money}`
- `quotaWindows`: array of `{label, used?: number, limit?: number, remaining?: number, unit, resetsAtMs?: number}`
- `today`, `total`: `{actualCost?: Money, requests?, inputTokens?, outputTokens?, cacheReadTokens?, cacheCreationTokens?, totalTokens?}` (numbers)
- `dailyUsage`: array of `{date, actualCost?: Money, requests?, totalTokens?}`
- `modelUsage`: array of `{model, actualCost?: Money, requests?, totalTokens?}`
- `providerStatus`: string
- `metricsUnavailableReason`: string

## Multi-step cases

Most providers answer one request per fetch. Some flows hit a second endpoint
(OpenRouter Management Keys call `/credits` after `/key`; BioMap Coding calls
`/v1/models` after a 403/404/405 from `/key/info`; regional providers may probe
a second region). For those, additional step bodies are named
`<case>-response2.json`, `<case>-response3.json`, ... and are served **in the
provider's documented request order**. Every step has a file; when a step is an
error status its body is ignored, so a placeholder file (e.g. `{}`) is fine —
the HTTP status each step is served with is declared in the test harness
entries on both platforms (default 200).

Current multi-step cases:

- `openrouter/key-management`: response = `/api/v1/key` (200),
  response2 = `/api/v1/credits` (200).
- `biomapcoding/fallback`: response = `/key/info` body (served with 403),
  response2 = `/v1/models` (200).

`Money` is `{amount: string, currency: string}` where `amount` is a **decimal
string**. On HarmonyOS amounts are compared as exact strings, so pin the
canonical decimal form the ArkTS parser produces (`"6655.9"`, not
`"6655.90"`); on Swift they are compared numerically as `Decimal`.

Token/request counters are JSON numbers. `receivedAtMs` is never pinned —
tests inject a fixed clock instead.
