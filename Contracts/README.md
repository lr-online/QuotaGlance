# Provider Contract Fixtures

Shared contract fixtures keep the Swift (macOS) and ArkTS (HarmonyOS) provider
implementations from drifting. Both platforms parse the same recorded provider
response and assert the same expected snapshot. The same mechanism also covers
the cross-platform aggregation and alert behavior modules (see "Aggregation
contract fixtures" and "Alert contract fixtures" below); those fixture sets
are synced into HarmonyOS ohosTest rawfiles and consumed by ArkTS contract
suites as well.

## Layout

```
Contracts/Providers/<provider>/<case>-response.json   # raw provider API response
Contracts/Providers/<provider>/<case>-expected.json   # expected parsed snapshot subset
Contracts/Providers/<provider>/<case>-requests.json   # expected request sequence
```

`<provider>` is the Swift `ProviderID` raw value lowercased (`deepseek`,
`apiinfo`, ...). Each case is a `<case>-response.json` / `<case>-expected.json`
pair, plus a `<case>-requests.json` file pinning the HTTP requests the fetch
issues.

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

## Requests-fixture schema

A requests file (`<case>-requests.json`) is a JSON array pinning the exact
HTTP request sequence one fetch issues, in order:

```json
[
  {
    "method": "GET",
    "url": "https://api.moonshot.cn/v1/users/me/balance",
    "headers": { "Authorization": "Bearer", "Accept": "application/json" }
  }
]
```

Both Swift and ArkTS harnesses assert count, order, `method`, `url`, and
header patterns. Header values are **assertion patterns**, not literal values:

- `"Bearer"` asserts the header is present and uses the Bearer scheme
  (`Bearer <key>`). **API key values are never pinned.**
- Any other string is an exact-value assertion.

Headers not listed in the fixture are unchecked. Fixtures mirror the current
implementation (they pin what the code does today, not a redesign).

On HarmonyOS the `HttpFetcher` signature is
`(url, headers) => Promise<RawJsonResponse>`: the spec engine builds the exact
header table from the spec's `request.headers` list and the shared
`network/HttpClient.ets` (`getJsonWithStatus`) sends it verbatim, so
MiniMax's `Content-Type` header is unified across both platforms. The ArkTS
harness records the same request triple as Swift — `method`, `url`, and
header patterns from the fixture.

When a case has no `<case>-requests.json` yet, both harnesses skip request
assertions for it.

`Money` is `{amount: string, currency: string}` where `amount` is a **decimal
string**. On HarmonyOS amounts are compared as exact strings, so pin the
canonical decimal form the ArkTS parser produces (`"6655.9"`, not
`"6655.90"`); on Swift they are compared numerically as `Decimal`.

Token/request counters are JSON numbers. `receivedAtMs` is never pinned —
tests inject a fixed clock instead.

## Aggregation contract fixtures

The same pin-what-matters mechanism covers `SnapshotAggregator`, the shared
cross-account rollup. Each case is a pair:

```
Contracts/Aggregation/<case>-input.json     # accounts + snapshots + now
Contracts/Aggregation/<case>-expected.json  # expected AggregateSnapshot subset
```

### Input schema

- `now` (ISO-8601 string, required): the evaluation instant. Engines run the
  aggregation under a **UTC Gregorian calendar** so `dailyUsage` dates are
  deterministic on both platforms.
- `accounts`: array of `{id, displayName, isEnabled?, sortOrder?}`
  (`isEnabled` default true, `sortOrder` default 0). `id` is a UUID string.
- `snapshots`: array of `{accountID, health, usage?}`:
  - `health`: `"healthy"` / `"belowThreshold"`, or
    `{"stale": "<failure>"}` / `{"unavailable": "<failure>"}` where
    `<failure>` is a `SnapshotFailure` raw value (`offline`,
    `invalidResponse`, ...).
  - `usage` (absent = no cached usage): `{balances?, today?, dailyUsage?}`
    with `balances: [{label, available: Money}]`,
    `today: {actualCost?: Money, requests?: number}`, and
    `dailyUsage: [{date, actualCost: Money, requests?, totalTokens?}]`.
    Snapshots in a fixture carry no display name/provider metadata of their
    own — the aggregator copies those from the account, which the `accounts`
    rows in the expected file can pin.

### Expected schema

An expected file pins a **subset** of `AggregateSnapshot`; only present keys
are asserted. Any of these keys may appear:

- `balances`: array of `Money`, exact count and order (per-currency totals,
  sorted by currency)
- `todayActualCost`: `Money`, or explicit `null`
- `todayRequests`: number, or explicit `null`
- `dailyUsage`: array of `{date, actualCost?: Money}` pinning count, dates,
  and order
- `accounts`: array of `{accountID, displayName?}` pinning count, order, and
  optionally the name the aggregator copied from the account
- `isPartial`: boolean

**Null assertion:** unlike the provider fixtures, several aggregation
guarantees are *absence* guarantees (missing metrics must stay absent rather
than become zero), so a key present with JSON `null` asserts the field is
nil; an absent key stays unchecked.

Current cases:

- `healthy-sum`: two healthy accounts sum balances and today metrics; the
  7-day window ends at `now` and zero-fills missing days; accounts follow
  `sortOrder`.
- `stale-partial`: a stale account keeps its last values in the totals and
  marks the aggregate partial.
- `disabled-excluded`: disabled accounts contribute neither totals nor rows.
- `mixed-currency`: currencies are never added together; totals sort by
  currency code.
- `missing-metrics`: when any account lacks today metrics, the aggregate
  cost/request fields are null, not zero.
- `request-overflow`: an Int64 request-count overflow nulls `todayRequests`
  and marks the aggregate partial.

## Alert contract fixtures

Covers `AlertEvaluator`'s batch evaluation (which the single-account entry
points feed into). Each case is a pair:

```
Contracts/Alerts/<case>-input.json     # accounts + fresh snapshots
Contracts/Alerts/<case>-expected.json  # expected batch result subset
```

### Input schema

- `accounts`: array of `{id, displayName, isEnabled?, lowBalanceThreshold?,
  alertEpisodeActive?}` (`isEnabled` default true, `alertEpisodeActive`
  default false; `lowBalanceThreshold` is a decimal string, absent = no
  threshold).
- `freshSnapshots`: array of `{accountID, health, remaining?: Money}` — one
  fresh snapshot per account, keyed by `accountID`. `health` uses the same
  encoding as the aggregation fixtures. Absent `remaining` = a snapshot
  without a balance (skipped by the evaluator).

### Expected schema

Pins a subset of the batch result; only present keys are asserted:

- `didChange`: boolean
- `notifications`: array of `{accountID, remaining?: Money}` pinning count
  and order of the pending notifications
- `accounts`: array of `{accountID, alertEpisodeActive?: bool}` pinning the
  resulting episode state per account (matched by id, not order)

Current cases:

- `notify-on-low`: remaining at or below the threshold starts an episode and
  emits one notification carrying the remaining balance.
- `episode-debounce`: an active episode does not re-notify while the balance
  stays low.
- `episode-reset`: recovery above the threshold ends the episode
  (`didChange`, no notification) so the next dip alerts again.
- `stale-no-change`: a stale snapshot can neither start nor reset an
  episode, in either direction.
- `batch-notify-and-reset`: one batch can notify one account and reset
  another; only the notify produces a notification.
- `no-alert-without-threshold`: disabled accounts and accounts without a
  threshold never alert.

## Refresh-lifecycle contract fixtures

The host-level refresh-run module is the common seam between a platform
trigger and its observable post-refresh effects. These fixtures pin that seam;
they do not replace the provider, aggregation, or alert fixture suites that
define the algorithms used inside a run. Each case is a pair:

```
Contracts/RefreshLifecycle/<case>-input.json     # state and per-account results before completion
Contracts/RefreshLifecycle/<case>-expected.json  # persisted state and ordered completion effects
```

### Input schema

- `invocation` (required): `{scope: "allEnabled"}` or `{scope: "account",
  accountID: string}`. An account-scoped run only considers the named enabled
  account; an all-enabled run considers every enabled account.
- `accounts` (required): array of `{id, isEnabled?, state?,
  lowBalanceThreshold?, alertEpisodeActive?}`. `isEnabled` defaults to true;
  `state` is `"active"` or `"deleted"` and defaults to `"active"`.
  `lowBalanceThreshold` is a decimal string and `alertEpisodeActive` defaults
  to false.
- `snapshotsBefore` (required): array of `{accountID, health, remaining?}`.
  `health` uses the aggregation fixture encoding. It is the persisted snapshot
  before the run; an omitted row means no cached snapshot.
- `results` (required): one result per account considered by the invocation:
  - success: `{accountID, outcome: "success", health, remaining?}` supplies a
    fresh provider snapshot;
  - failure: `{accountID, outcome: "failure", failure}` preserves any cached
    snapshot while marking it stale, or makes an uncached account unavailable;
  - superseded: `{accountID, outcome: "superseded"}` is discarded because an
    edit or deletion made the result obsolete.
- `notificationPermission` (required): `"granted"` or `"denied"`.
- `notificationDelivery` (required): `"succeeds"` or `"fails"`. It affects
  delivery only; it must not roll back an alert episode transition.

### Expected schema

Expected files pin all resulting persisted snapshots and account alert-episode
states, plus the ordered effects exposed by a completed run:

- `snapshots`: array of `{accountID, health, remaining?}` describing persisted
  state after the run. A failure is represented by `{"stale": "<failure>"}`
  when cached data existed and `{"unavailable": "<failure>"}` otherwise.
- `accounts`: array of `{accountID, alertEpisodeActive}`. Deleted accounts are
  omitted because their account, credential, snapshot, and episode state are
  removed.
- `effects`: ordered array. Each effect is one of
  `{kind: "persistSnapshots", accountIDs: [...]}`,
  `{kind: "evaluateAlerts", accountIDs: [...]}`,
  `{kind: "persistAlertEpisodes", accountIDs: [...]}`,
  `{kind: "notificationCandidates", accountIDs: [...]}`,
  `{kind: "deliverNotifications", accountIDs: [...]}`, or
  `{kind: "removeDeletedAccounts", accountIDs: [...]}`, or
  `{kind: "invalidateQuickViews"}`.

The effect order is part of the protocol: snapshot persistence happens first,
then at most one batch alert evaluation when the fresh-success set is
non-empty, then any alert episode persistence, then notification candidate and delivery handling,
followed by one quick-view invalidation when the run changed persisted state.
An alert episode transition is persisted before a notification is delivered.
Failed, stale, unavailable, disabled, deleted, and superseded results cannot
start or reset an episode.

Current cases cover all-success, partial and total failure, one-account runs,
low-balance transitions, denied or failed notification delivery, disabled and
deleted accounts, and superseded results.

## Provider spec schema (draft v1)

Each provider directory additionally contains a `spec.json`: a **data-driven
provider definition** that has replaced the hand-written per-provider Swift /
ArkTS implementations. Both platforms ship one generic **spec engine** that
loads `Contracts/Providers/<provider>/spec.json` and executes it; per-provider
code has disappeared except for the named parse strategies described below.

Status: **normative** — the schema is pinned by this document, and both
engines (Swift `SpecDrivenProvider`, ArkTS `SpecDrivenProvider`/`SpecEngine`)
execute it and pass the fixture suites replayed through the engine.

The design deliberately stays declarative: no expressions beyond the closed
value/condition operator sets below, no arbitrary JSONPath, no control flow
beyond ordered steps and first-match status branches. If a provider cannot be
expressed with these primitives, the escape hatch is a **named parse
strategy**, not new syntax (see "Named parse strategies" and "When a
hand-written adapter is allowed").

### File location and identity

```
Contracts/Providers/<provider>/spec.json
```

`<provider>` is the Swift `ProviderID` raw value lowercased. Top level:

```json
{
  "specVersion": 1,
  "id": "deepSeek",
  "displayName": "DeepSeek",
  "descriptor": { ... },
  "credential": { ... },
  "profiles": { ... },
  "detect": { ... },
  "fetch": { ... }
}
```

- `specVersion` (int, required): schema version. Engines must reject specs
  with a higher version than they implement.
- `id` (string, required): the Swift `ProviderID` raw value (`apiInfo`,
  `deepSeek`, `kimi`, `openRouter`, `miniMax`, `bioMapCoding`). Must match the
  lowercased directory name.
- `displayName` (string, required): mirrors `ProviderDescriptor.displayName`.

### `descriptor`

Mirrors the two capability closures of `ProviderDescriptor` as data:

```json
"descriptor": {
  "supportsLowBalanceThreshold": { "always": true },
  "profileDescription": {
    "undetected": { "l10nKey": "notDetected" },
    "detected": { "style": "regionCredential" }
  }
}
```

- `supportsLowBalanceThreshold`: one of
  - `{ "always": true|false }`
  - `{ "undetected": <bool>, "credentialKinds": [<kind>, ...] }` — true when
    the profile is nil and `undetected` is true, or when the profile's
    `credentialKind` is in the list (OpenRouter: undetected or `management`).
- `profileDescription`: the copy rule for the detected profile.
  - `undetected.l10nKey`: L10n key returned when no profile has been detected
    (always `notDetected` today).
  - `detected`: one of
    - `{ "style": "regionCredential" }` — L10n key `regionCredential` with the
      region and credential-kind display names as arguments.
    - `{ "style": "credentialKind" }` — the credential kind's display name.
    - `{ "byRegion": { "<region>": { "l10nKey": "<key>", "args": [...] } } }` —
      per-region key selection (Kimi). `args` entries are limited to
      `"credentialKind"` (the kind's display name); absent `args` = no
      arguments.

**Why L10n keys, not copy:** the strings are per-language and already live in
each platform's L10n tables (Swift `L10n.Key`, mirrored on ArkTS). Copy in the
spec would drift and could never carry translations. What the spec pins is the
*branch structure* (which key for which region/profile); key names are stable
tokens both platforms share, exactly like the error tokens below.

### `credential`

API-key preprocessing, applied (in this order) at the top of both `detect`
and `fetch`, before any profile validation or request:

```json
"credential": {
  "trimWhitespace": true,
  "reject": [
    { "prefix": "sk-api-", "caseInsensitive": true, "error": "unsupportedCredential" }
  ]
}
```

- `trimWhitespace` (bool, default false): trim leading/trailing whitespace
  and newlines from the key (MiniMax).
- `reject` (array, default []): first matching rule throws the named error.
  Match operators: `prefix` (with optional `caseInsensitive`, default false).

### `profiles`

```json
"profiles": {
  "supported": [
    { "region": "china", "credentialKind": "standard" },
    { "region": "international", "credentialKind": "standard" }
  ]
}
```

The exhaustive list of `ProviderProfile` combinations this provider accepts.
`fetch` with any other profile throws `profileMismatch` before issuing
requests. Regions are `global | china | international`; kinds are
`standard | management | tokenPlan`.

### JSON paths

All `path` strings are **dot-separated object keys** only: `data.usage`,
`base_resp.status_code`. There is no array indexing, no wildcards, no
descent operators. Arrays are handled structurally by `fromArray`,
`count`, and `eachItem` (below). Resolution rules:

- a missing key, explicit `null`, or a non-object intermediate resolves to
  *absent* (not an error);
- anything depending on an absent value is null/omitted, unless a `required`
  rule says otherwise.

### Value expressions

A *value expression* evaluates to a scalar or null. Closed set:

- `{ "path": "<path>", "type": "decimal|string|int|bool" }` — typed
  extraction. `decimal` accepts a JSON number **or** a numeric string
  (trimmed; `ProviderDecimal` semantics). An unparseable value counts as
  absent unless `required: true` is set on the same object, in which case the
  step fails with `invalidResponse`.
  Optional modifiers: `"required": true` (absent/unparseable → the step
  fails with `invalidResponse`), `"nonEmpty": true` (with `required`:
  empty-after-transform string → `invalidResponse`),
  `"transforms": ["trim", "uppercase"]` (strings, applied
  in order), `"nullIfEmpty": true` (empty-after-trim string → null).
- `{ "literal": <json scalar> }`
- `{ "value": "<name>" }` — a named value from the parse block's `values`
  (or `itemValues` inside an array item).
- `{ "byRegion": { "<region>": <scalar>, ... } }` — pick by the profile
  region the step runs under (region-scoped currency, endpoint).
- `{ "op": "subtract", "a": <value>, "b": <value> }` — decimal `a - b`;
  null-propagating (either side null → null).
- `{ "op": "count", "path": "<path>" }` — length of the array at path;
  absent/non-array → null.

That is the whole arithmetic vocabulary. No nested ops beyond `subtract`
operands, no string concatenation beyond templates (below).

### Conditions

A *condition* is a boolean test, used in `when` clauses and `checks`:

- `{ "path": "<path>", "exists": true|false }`
- `{ "path": "<path>", "equals": <scalar> }` / `"notEquals"` — if the
  expected value is a JSON number, the actual value is parsed as a decimal
  (number-or-string) and compared numerically; otherwise exact scalar
  comparison. Absent actual → condition false.
- `{ "path": "<path>", "lt": <number> }` / `"gt"` — numeric comparison;
  absent/unparseable → false.
- `{ "any": [<condition>, ...] }` / `{ "all": [<condition>, ...] }` — the
  only combinators.

Inside a step-level `when` (see below) the condition takes an extra `step`
field and evaluates against that earlier step's parsed body:
`{ "step": "key", "path": "data.is_management_key", "equals": true }`.

### `checks` (ordered validation / error mapping)

Each parse block has a `checks` array, evaluated **in order** against the
step's response body; the first failing entry throws. Entry forms:

- `{ "path": "<path>", "required": true }` — absent (or unparseable when
  `"type"` is given) → `invalidResponse`. Models Swift's non-optional
  `Decodable` fields and `guard let` chains.
- `{ "path": "<path>", "required": true, "nonEmpty": true }` — additionally
  fails on an empty string or empty array.
- `{ "path": "<path>", "type": "...", "strict": true, "error": "<token>" }` —
  the value may be absent, but when present it must parse as `type` (and
  satisfy `nonEmpty` when given); failure throws `error` (default
  `invalidResponse`). Models Swift's *optional* `Decodable` fields: a present
  value that fails to decode rejects the whole payload instead of decoding as
  nil (BioMap Coding's `info.spend`).
- `{ "path": "<path>", "type": "...", "when": { <condition on the value> }, "error": "<token>" }`
  — if the condition holds, throw `error` (default `invalidResponse`).
  `type` declares how the value is parsed before the condition is evaluated
  (e.g. decimal for numeric comparisons).
  Example: `{ "path": "isValid", "when": { "equals": false }, "error": "providerInactive" }`.
- `{ "eachItem": { "of": "<path>", "path": "<item path>", "type": "...",
  "transforms": [...], "required": true, "nonEmpty": true }, "error": "<token>" }`
  — per-array-element validation (BioMap Coding's non-empty model ids).

This single ordered list replaces separate "validate then map errors"
phases; providers interleave the two (API Info checks `isValid` before
requiring `remaining`; MiniMax requires `status_code` before mapping 1004),
so the spec keeps them in one sequence, in the order the original
hand-written Swift code used.

### Snapshot builders

`parse.snapshot` maps step bodies onto `ProviderUsageSnapshot` fields. When
several steps execute (OpenRouter), their `snapshot` blocks merge in step
order: a later step overrides only the fields it sets. Field forms:

- any value expression → sets the field directly (null = omitted);
- `{ "when": <condition>, "value": <value expression> }` — conditional
  scalar/object field; omitted when the condition is false;
- `{ "when": <condition>, "object": { ... } }` — conditional composite;
- `{ "money": { "amount": <value>, "currency": <value> } }` — null if either
  side is null;
- `{ "template": "Budget period: ${duration}" }` — string template
  interpolating **named values only** (`${name}`); null if any referenced
  value is null;
- `{ "path": ..., "map": { "<scalar>": <scalar>, ... } }` — scalar remap
  (`is_available` → `"active"/"unavailable"`); no match → null;
- array fields (`balances`, `quotaWindows`, `dailyUsage`, `modelUsage`):
  - `{ "fromArray": "<path>", "itemValues": { ... }, "item": { ... },
    "skipItemWhen": <condition> }` — map each element; `item` is an object of
    per-field builders evaluated in item scope; `itemValues` are named values
    evaluated once per item; `skipItemWhen` drops the element
    (API Info's `dailyUsage` drops entries without `actual_cost`). A field
    builder with `"required": true` that resolves null fails the whole step
    with `invalidResponse`. Absent source array → `[]`.
  - `{ "fixed": [ { "when": <condition>, ...item builders... }, ... ] }` —
    a literal list whose entries appear only when their `when` holds
    (balance breakdown entries, single-entry `balances`).
  - `{ "strategy": "<name>", "path": "<path>", "requireNonEmpty": true }` —
    named parse strategy, see below.

`receivedAt` is always injected by the engine clock; it never appears in a
spec. `providerStatus`, `metricsUnavailableReason`, `spend`,
`spendingLimit`, `today`, `total` follow the same builder rules.

### Request steps and status branches

`fetch.steps` is an ordered array. Step schema:

```json
{
  "name": "balance",
  "when": { "step": "key", "path": "data.is_management_key", "equals": true },
  "request": {
    "method": "GET",
    "url": "https://..." ,
    "headers": [
      { "name": "Authorization", "value": "Bearer ${apiKey}" },
      { "name": "Accept", "value": "application/json" }
    ]
  },
  "onStatus": [
    { "match": "2xx", "action": "parse" },
    { "match": [403, 404, 405], "action": "gotoStep", "step": "models" },
    { "match": [401], "action": "error", "error": "invalidCredential" },
    { "match": [429], "action": "error", "error": "rateLimited" },
    { "match": "default", "action": "error", "error": "httpStatus" }
  ],
  "parse": { "checks": [ ... ], "values": { ... }, "snapshot": { ... },
             "credentialKindDetection": { ... } }
}
```

- `name` (required): unique within the spec; referenced by `gotoStep` and
  step-scoped conditions.
- `when` (optional): the step runs only if the condition (against an earlier
  step's body) holds. Steps without `when` run in listed order; the first
  step never has `when`.
- `onDemand` (optional bool, default false): the step never runs in listed
  order; it runs only when a `gotoStep` branch targets it, and its result
  then becomes the fetch result (BioMap Coding's `models` step).
- `request.method` / `request.url`: `url` is a string or
  `{ "byRegion": { "china": "...", "international": "..." } }` resolved by
  the profile region.
- `request.headers`: exact header list, in order; `${apiKey}` interpolates
  the (preprocessed) API key. The engine sends exactly these headers — no
  implicit platform headers. This is what unifies the MiniMax
  `Content-Type: application/json` divergence: the spec lists it, so both
  engines send it (the ArkTS shared `HttpClient` accepts the header list
  as-is; its harness still does not assert headers).
- `onStatus`: **first match wins**, in array order. `match` is `"2xx"`, an
  array of exact codes, or `"default"`. Actions:
  - `parse` — run the step's `parse` block;
  - `error` — throw the named token (`httpStatus` carries the actual code:
    Swift `httpStatus(Int)`, ArkTS `httpStatus:<code>`);
  - `gotoStep` — abandon this step, execute the named step, and use *its*
    result as the fetch result (BioMap Coding 403/404/405 → `/v1/models`).
- `parse.credentialKindDetection` (optional):
  `{ "path": "data.is_management_key", "map": { "true": "management", "false": "standard" } }`.
  Semantics differ by entry point: in `detect` the mapped value **becomes**
  the detected profile's `credentialKind`; in `fetch` it must equal the
  requested profile's `credentialKind`, else `profileMismatch` (OpenRouter).

### `detect`

```json
"detect": { "strategy": "fixedProfile",
            "profile": { "region": "global", "credentialKind": "standard" } }
```

or

```json
"detect": { "strategy": "regionFallback",
            "candidates": [
              { "region": "china", "credentialKind": "standard" },
              { "region": "international", "credentialKind": "standard" }
            ],
            "fallbackOn": ["invalidCredential"],
            "exhaustedError": "regionDetectionFailed" }
```

- `fixedProfile`: run the fetch pipeline under the declared profile; success
  → `ProviderDetection(profile, snapshot)`; errors propagate unchanged. The
  literal credential kind may be `"detected"` (OpenRouter), meaning "take the
  kind from `credentialKindDetection`".
- `regionFallback`: try each candidate profile in order by running the fetch
  pipeline under it. A failure whose token is in `fallbackOn` (and only
  those) advances to the next candidate; any other error propagates
  immediately. If every candidate fails with a fallback error, throw
  `exhaustedError`.

"Running the fetch pipeline" from `detect` means engine steps 3–6 of the
`fetch` semantics below: `profiles.supported` validation (step 2) does not
apply — `detect` constructs the profile — and `credentialKindDetection`
takes its detect-side meaning. Credential preprocessing (step 1) always
applies, in both entry points.

For `regionFallback`, the engine moves the runtime-preferred region's
candidate to the front before iterating. The preference itself (injected
parameter, or locale — `CN` → `china`, else `international`) is *not* part
of the spec; the spec pins only the candidate set, the fallback condition,
and the terminal error. This mirrors the behavior of the deleted hand-written
`KimiProvider`/`MiniMaxProvider`, including their init-time clamping of an
unsupported injected region to the locale default.

### Engine execution semantics

`fetch(apiKey, profile)`:

1. Credential preprocessing (`credential.trimWhitespace`, then
   `credential.reject` rules in order).
2. Profile validation: `profile` must exactly equal one
   `profiles.supported` entry, else `profileMismatch`.
3. Execute steps in order. A step with `when` is skipped unless the
   condition holds; a step with `onDemand: true` is always skipped in listed
   order. For each executed step: build the request (region-aware
   URL, interpolated headers), send it, then:
   - transport failure → the platform network error (ArkTS
     `network:<detail>`; Swift surfaces the `URLError`) — outside the spec's
     error model;
   - otherwise evaluate `onStatus` first-match: `parse`, `error`, or
     `gotoStep`.
4. Parsing a step: evaluate `checks` in order; then `values`; then merge
   `snapshot` into the result. Any JSON structural failure, and any failure
   of a `required` rule, is `invalidResponse` — matching the Swift catch-all
   that maps non-`ProviderError` parse failures to `invalidResponse`.
5. If a step declares `credentialKindDetection`, enforce it **immediately
   after that step parses**, before any later step runs: in `fetch`, a
   mismatch with the requested profile's `credentialKind` throws
   `profileMismatch` (so a standard-profile fetch of a management key fails
   right after `/key`, without calling `/credits`); in `detect`, the mapped
   kind becomes the detected profile's `credentialKind`.
6. Set `receivedAt` from the injected clock and return the merged snapshot.

`detect(apiKey)`: credential preprocessing, then the strategy above (which
itself runs the fetch pipeline per candidate).

### Error tokens

Specs reference only these stable tokens, identical on both platforms (see
the table in `HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets` and
Swift `ProviderError`): `invalidCredential`, `rateLimited`, `httpStatus`
(engine appends the code), `invalidResponse`, `providerInactive`,
`unsupportedCredential`, `regionDetectionFailed`, `profileMismatch`.
`providerUnavailable` (registry) and `network:<detail>` (transport) are
engine/framework-level and never appear in a spec.

### Decimal and Money canonicalization

Fixtures pin `Money.amount` as exact strings on HarmonyOS, so both engines
must produce the same canonical form:

- decimal parsed from a JSON **string**: preserved verbatim after trimming
  (`"10.00"` stays `"10.00"`);
- decimal parsed from a JSON **number**: shortest round-trip rendering
  (`6655.90` → `"6655.9"`, `10` → `"10"`);
- results of `subtract`: canonical decimal rendering of the exact result
  (`25 - 3.25` → `"21.75"`).

Swift compares numerically so only the ArkTS rendering is pinned, but both
engines should share one implementation of these rules.

### Named parse strategies

A snapshot array field may delegate to a named strategy:
`{ "strategy": "miniMaxModelRemains", "path": "model_remains", "requireNonEmpty": true }`.
The engine ships a small, fixture-pinned, hand-written function per strategy
name (same on both platforms); an unknown name is a spec-load error. The
strategy receives the JSON value at `path` and returns the field value.
`requireNonEmpty: true` maps an empty result to `invalidResponse`.

Currently defined strategies:

- **`miniMaxModelRemains`** → `QuotaWindow[]`. For each entry of the array:
  1. *Direct window* — if any of `total`/`used`/`remains` is present: emit
     `{label: trim(entry.label) || "<model> quota", unit: trim(entry.unit) || "requests",
     limit: total, used: used ?? (total - remains), remaining: remains ?? (total - used),
     resetsAt: reset_time ?? end_time}`. Missing derived operands stay null.
  2. Otherwise, *interval window* — when `current_interval_status != 0`:
     counted form when `current_interval_total_count > 0` or
     `current_interval_usage_count > 0` (`limit`/`used` from those, `remaining
     = limit - used`, unit `requests`); otherwise percent form when
     `current_interval_remaining_percent` is present (`remaining =
     clamp(percent, 0, 100)`, `used = 100 - remaining`, `limit = 100`, unit
     `%`). Label is `"<model> 5-hour quota"` when `end_time - start_time` is
     18000 s ± 1 s, else `"<model> quota"`. `resetsAt` = `end_time`.
  3. *Weekly window* — independently of the interval window, when
     `current_weekly_status != 0`: same counted-or-percent rule with the
     `current_weekly_*` fields, label `"<model> weekly quota"`, `resetsAt` =
     `weekly_end_time`.
  4. Interval and weekly windows can both be emitted for one entry; an entry
     producing none contributes nothing.
  
  where `<model>` = `trim(model_name) || "Token Plan"`, all numbers are
  decimals (number-or-string), and timestamps are epoch seconds or
  milliseconds (magnitude > 1e10 ⇒ milliseconds) normalized to ms.

### When a hand-written adapter is allowed

In priority order, when a provider's behavior does not fit the schema:

1. **Named parse strategy** — for *response-shape* complexity only: nested
   conditionals, multiple emitted objects per array element, date arithmetic,
   derived/clamped values beyond `subtract`/`count`. One strategy per shape,
   implemented once per platform, pinned by fixtures. Request orchestration,
   headers, detect, and error mapping must still come from the spec.
2. **Fully hand-written provider** — only when the *orchestration* itself
   doesn't fit: non-GET methods with bodies, auth schemes other than a static
   header template, pagination, response-dependent request *construction*
   (not just conditional execution), or non-JSON payloads. Such a provider
   keeps a hand-written implementation on both platforms and must still ship
   contract fixtures; its spec.json is omitted.

Adding schema features to accommodate a single provider is an anti-pattern;
prefer the escape hatches above and keep the schema small.

Current status of the six providers:

| provider | expressible | notes |
| --- | --- | --- |
| apiinfo | yes | fully declarative |
| deepseek | yes | fully declarative |
| kimi | yes | `regionFallback` detect |
| openrouter | yes | conditional second step + `credentialKindDetection` |
| minimax | mostly | `miniMaxModelRemains` strategy for `quotaWindows`; everything else declarative |
| biomapcoding | yes | `gotoStep` status fallback |
