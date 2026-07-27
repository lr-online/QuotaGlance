# QuotaGlance Multi-Provider Design

**Date:** 2026-07-27  
**Status:** Approved for implementation

## Goal

Extend QuotaGlance from an API Info-only balance monitor into a capability-aware
monitor for API Info, DeepSeek, Kimi, OpenRouter, and MiniMax. A user chooses
only the provider family while adding a key. QuotaGlance detects regional and
credential variants, remembers the result, and renders only the metrics that
the credential can actually expose.

The interface must not ask users to understand Kimi or MiniMax regional API
hosts, or the difference between OpenRouter standard and management keys.

## Product Decisions

- The provider picker contains exactly five choices: API Info, DeepSeek, Kimi,
  OpenRouter, and MiniMax.
- Kimi China and International remain one visible provider. The app detects the
  region by probing the two official balance endpoints sequentially during key
  validation, then persists the successful region.
- MiniMax China and International remain one visible provider. The app detects
  region in the same way against the official Token Plan endpoints.
- OpenRouter credential type is read from the official `/key` response. A
  management key is enriched through `/credits`; a standard key stays scoped
  to per-key spend and its optional spending limit.
- MiniMax standard pay-as-you-go keys are detected but rejected with a clear
  explanation because MiniMax does not publish an official cash-balance query
  for them. Token/Coding Plan keys are supported.
- Chinese regional balances use `CNY`; international balances use `USD`.
- Monetary balances are aggregated by currency without exchange-rate
  conversion. Spending caps and quota windows never contribute to the cash
  balance total.
- Keys continue to live only in Keychain. Detection metadata is non-secret and
  may be persisted with the account.

## Current-State Constraints

The current app stores no provider on `Account`, owns one `APIInfoProvider` in
`AppModel`, and gives every account to a `RefreshCoordinator` that calls that
single provider. `ProviderUsageSnapshot` requires one monetary `remaining`
value, which cannot accurately represent an uncapped OpenRouter key or a
MiniMax Token Plan window. The menu bar and Widget presentations also assume
one aggregate currency.

The implementation will replace those assumptions rather than mapping unlike
vendor concepts into misleading monetary fields.

## Domain Model

### Provider identity and detected profile

`ProviderID` is a stable, Codable enum with these cases:

- `apiInfo`
- `deepSeek`
- `kimi`
- `openRouter`
- `miniMax`

`Account` gains a required `provider` and an optional `detectedProfile`.
`ProviderProfile` records only facts needed to make later requests and label
the result:

- region: global, China, or international;
- credential kind: standard API key, management key, or Token Plan key.

Endpoints are derived in code from these enum values and are never persisted
as arbitrary URLs.

### Capability-based snapshot

`ProviderUsageSnapshot` becomes a collection of independently optional
capabilities:

- `balances`: one or more real monetary balances;
- `spendingLimit`: an optional monetary used/limit/remaining metric that is not
  a cash balance;
- `spend`: optional today, week, month, and total monetary spend;
- `quotaWindows`: non-monetary used/limit/remaining metrics with optional reset
  times;
- existing daily and model usage where the provider publishes them;
- provider status and fetch timestamp.

A monetary balance includes an available `Money` value and optional named
breakdown values. DeepSeek can expose granted and topped-up amounts. Kimi can
expose cash and voucher amounts. Breakdowns are informational and are not
aggregated separately.

A quota window stores Decimal values and a unit label rather than `Money`.
MiniMax response fields such as `remains` and `total` map here. Missing values
remain absent and are never converted to zero.

### Primary presentation metric

For compact surfaces, the presenter chooses the first available metric in this
order:

1. real monetary balance;
2. spending-limit remaining amount;
3. quota-window remaining amount or used percentage;
4. current-month, current-week, current-day, then total spend.

The label always states the semantic meaning, such as `Balance`, `Key limit`,
`5-hour quota`, or `Spent this month`. A spend amount is never labeled as
remaining.

## Provider Contracts

All adapters conform to a provider contract with two operations:

- detection validates a newly supplied key, resolves its profile, and returns
  the first snapshot in the same request flow;
- refresh uses the persisted profile and calls only its resolved official
  endpoint.

The registry selects an adapter from `ProviderID`. The refresh coordinator does
not contain vendor switches and receives a registry rather than one fixed
provider.

### API Info

- `GET https://www.api-info.net/v1/usage`
- Bearer authentication.
- Top-level `remaining` remains authoritative.
- Existing quota, today, total, daily, and model mappings are preserved.
- Profile is global plus standard API key.

### DeepSeek

- `GET https://api.deepseek.com/user/balance`
- Bearer authentication.
- Every `balance_infos` item becomes a separate monetary balance using the
  response currency, including `CNY` and `USD` when both are returned.
- `total_balance` is available balance; `granted_balance` and
  `topped_up_balance` are breakdown rows.
- `is_available == false` is a valid zero/insufficient state, not an invalid
  credential by itself.
- The official endpoint exposes no historical usage, so those capabilities are
  absent.

### Kimi

- China: `GET https://api.moonshot.cn/v1/users/me/balance`, currency `CNY`.
- International: `GET https://api.moonshot.ai/v1/users/me/balance`, currency
  `USD`.
- Bearer authentication.
- `available_balance` is the real balance. `cash_balance` and
  `voucher_balance` are breakdown rows.
- During detection, the locale-matching official region is tried first, then
  the other region only after a definitive credential rejection. A successful
  region is persisted. Transient transport or server errors do not classify a
  key as belonging to the other region.

### OpenRouter

- `GET https://openrouter.ai/api/v1/key` for all supplied credentials.
- Bearer authentication.
- `is_management_key` determines the credential kind.
- Standard keys expose total/day/week/month spend. When `limit` exists,
  `limit_remaining`, `usage`, and `limit` become a non-aggregate spending
  limit. An uncapped standard key exposes spend only.
- Management keys additionally call
  `GET https://openrouter.ai/api/v1/credits`. `total_credits - total_usage`
  becomes an aggregate-eligible USD credit balance. A negative result is
  preserved rather than clamped so debt is not hidden.
- Deprecated `rate_limit` data is ignored.

### MiniMax

- China: `GET https://www.minimaxi.com/v1/token_plan/remains`.
- International: `GET https://www.minimax.io/v1/token_plan/remains`.
- Bearer authentication.
- A known `sk-api-` standard key is rejected before probing with an explanation
  that public pay-as-you-go balance reporting is unavailable.
- Token/Coding Plan keys are region-probed using the same definitive-rejection
  rule as Kimi. Both HTTP status and an embedded nonzero `base_resp.status_code`
  are treated as provider errors.
- Recognized `model_remains` entries map to quota windows. `remains`, `total`,
  reset timestamps, and labels are decoded defensively because official plans
  may expose different window/model buckets.
- A successful response with no recognizable quota bucket is an invalid
  response, not a zero quota.

## Save and Refresh Flow

When adding an account, the user chooses a provider, name, and key. Saving runs
validation and provider detection before writing either account metadata or the
credential. The returned profile and snapshot are persisted only after all
validation succeeds.

When editing an account, its provider may be changed only when a replacement
key is supplied. A replacement key always triggers fresh detection. Edits that
leave the key blank retain both the credential and detected profile.

Scheduled refresh reads the credential, selects the adapter by provider, and
uses the stored profile. An invalid credential does not silently switch region;
the user must replace the key to trigger detection again. This prevents a
revoked key from being sent repeatedly to both regional hosts.

Concurrent-refresh coalescing, timeout handling, stale snapshots, and partial
results retain their current behavior.

## Aggregation

Only real balances participate in All Accounts totals. They are grouped and
summed by ISO currency code, producing independent CNY and USD totals. Mixed
currencies are expected and do not make the aggregate partial.

Spending limits, periodic spend, and quota windows remain account-scoped.
Today-spend aggregation is shown only where values have the same currency and
semantic period; otherwise the account rows carry the information.

Multiple keys may represent the same provider account and therefore return the
same account-wide balance. QuotaGlance cannot identify this from official
responses. The UI labels detected account-scoped credentials, and the README
warns that adding multiple keys from one DeepSeek or Kimi account can duplicate
All Accounts totals.

## Alerts

The existing low-balance threshold applies only when an account exposes a real
primary monetary balance. It is hidden for MiniMax and for OpenRouter standard
keys, because quota windows and spending caps have different semantics.

For providers returning multiple balances, the first provider-reported balance
is the primary alert balance while every currency remains visible in account
details. Existing API Info thresholds retain their behavior. Stale or failed
refreshes never start or reset an alert episode.

## Interface

### Account settings

The account editor adds a native Provider picker above the key field. Provider
names use text labels rather than unexplained logos. Saving shows the existing
progress indicator while detection runs.

Account rows show the provider plus detected detail, for example:

- `Kimi - China (CNY)`
- `Kimi - International (USD)`
- `OpenRouter - Management key`
- `MiniMax - International Token Plan`

Provider-specific validation failures are concise and actionable. MiniMax
pay-as-you-go keys explain which key type is supported. Regional detection
failure says that neither official region accepted the key. Raw responses,
headers, URLs containing secrets, and keys are never displayed or logged.

### Menu bar dashboard

All Accounts shows one balance summary per currency followed by account rows.
An individual account renders sections only when backed by capabilities:

- available balances and breakdowns;
- key spending-limit progress;
- spend period values;
- quota-window progress and reset time;
- daily chart and model rows where available.

The existing fixed panel size remains stable. Content scrolls rather than
resizing the popover.

### Widgets

Account widgets use the primary presentation metric and its explicit label.
All Accounts widgets show separate currency totals when space permits and fall
back to compact account rows for mixed capabilities. Existing configurable
account selection and deep links remain unchanged.

## Persistence and Migration

The stored account schema increments to version 2 while retaining the existing
UserDefaults storage key so old data can be read. Custom decoding supplies
`provider = apiInfo` and the fixed API Info profile when those fields are
missing. Existing UUIDs, sort order, thresholds, and Keychain items are
unchanged.

The existing Keychain service identifier remains stable as a storage namespace
despite its historical `api-info` suffix. Changing it would add credential
migration risk without a user-visible benefit.

Widget snapshot schema increments to version 2. An incompatible version-1
cache is discarded and the host performs its normal immediate refresh. No old
monetary field is guessed into a new capability.

## Error Handling

Adapters normalize 401/403 to invalid credentials and 429 to rate limiting.
Kimi and MiniMax regional fallback occurs only for a definitive authentication
rejection. Offline, timeout, 429, 5xx, or malformed responses stop detection
and preserve their real error category.

Refresh failures retain the last successful capability snapshot and mark it
stale. Unsupported MiniMax key types fail before persistence. Partial provider
payloads preserve available capabilities and leave missing capabilities absent.

## Testing

- Domain tests cover provider/profile Codable migration and capability
  semantics.
- Each adapter has request, complete-payload, sparse-payload, authentication,
  rate-limit, and malformed-response tests using redacted fixtures.
- Kimi and MiniMax tests prove regional fallback, no fallback on transient
  errors, region persistence, CNY/USD mapping, and embedded MiniMax errors.
- OpenRouter tests cover standard capped, standard uncapped, management credit,
  and deprecated-field behavior.
- Coordinator tests prove per-account registry routing, coalescing, timeouts,
  stale retention, and mixed-provider concurrency.
- Aggregation tests prove per-currency balance totals and exclusion of spending
  limits and quota windows.
- Presentation tests cover each capability combination and compact Widget
  fallbacks.
- `swift test`, both Xcode schemes, script tests, secret scans, and visual
  inspection of Settings, menu bar, and Widgets form the completion gate.

## Documentation

README and provider research are updated to describe supported providers,
credential limitations, regional auto-detection, currency grouping, duplicate
account-wide balances, and the fact that MiniMax pay-as-you-go balances are not
available through an official API.
