# Provider Capability Research

Status: Implemented
Date: 2026-07-27

## Decision

QuotaGlance implements five visible provider families: API Info, DeepSeek,
Kimi, OpenRouter, and MiniMax. Kimi and MiniMax each remain one provider in the
picker; the app detects China versus international credentials and persists the
resolved region. OpenRouter detects standard versus management credentials.

Provider responses map into independent balance, spending-limit, spend-period,
and quota-window capabilities. Only real balances enter All Accounts totals.
Totals are grouped by ISO currency without conversion, and missing capabilities
remain absent rather than becoming zero.

Adapters are compiled into the app. QuotaGlance does not load third-party
provider plugins or accept arbitrary endpoint URLs.

## API Info

Status: Implemented.

- Endpoint: `GET https://www.api-info.net/v1/usage`
- Authentication: `Authorization: Bearer <API key>`
- Confirmed capabilities:
  - quota limit, used amount, remaining balance, and currency
  - today's cost, requests, and token counts
  - aggregate historical usage
  - daily usage series
  - model-level statistics
- Scope assumption supplied by the user: each key has an independent quota.

The API's `remaining` field is authoritative. QuotaGlance must not derive the
remaining balance from usage totals because provider accounting fields may not
reconcile exactly.

## OpenRouter

Status: Implemented for standard and Management Keys.

- A normal inference key can call `GET https://openrouter.ai/api/v1/key`.
- It returns per-key spend, an optional per-key spending cap, and daily, weekly,
  and monthly usage. The cap remainder is not the account's credit balance.
- Account credits, all-key metadata, and 30-day activity require a separate
  Management Key through `/credits`, `/keys`, and `/activity`.
- Management Keys are administrative credentials and cannot be treated as
  ordinary inference keys.
- `/key.data.rate_limit` is deprecated and must not be used.
- QuotaGlance always calls `/key`. It calls `/credits` only when the response
  identifies a Management Key.
- A standard key's optional cap is a spending limit, not an account balance.
  A Management Key's credits remainder is a real `USD` balance and may be
  negative.

Official sources:

- https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key
- https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits
- https://openrouter.ai/docs/api/api-reference/analytics/get-user-activity-grouped-by-endpoint
- https://openrouter.ai/docs/guides/overview/auth/management-api-keys

## DeepSeek

Status: Implemented as a balance-only provider.

- Endpoint: `GET https://api.deepseek.com/user/balance`
- Authentication: standard Bearer API key.
- Returns account-wide CNY and/or USD balances, including granted and topped-up
  components.
- The official API does not expose historical usage, billing ledger, or the
  account's effective rate quota.
- Multiple keys from the same account return the same account balance and must
  not conceptually be aggregated as independent balances. Official responses
  do not provide a stable account identity, so QuotaGlance warns about this but
  cannot deduplicate such keys automatically.

Official source:

- https://api-docs.deepseek.com/api/get-user-balance

## Kimi / Moonshot

Status: Implemented as one automatically detected regional provider.

- China endpoint: `GET https://api.moonshot.cn/v1/users/me/balance`
- International endpoint: `GET https://api.moonshot.ai/v1/users/me/balance`
- Authentication: standard Bearer API key.
- Returns available, cash, and voucher balances. China uses CNY; international
  accounts use USD.
- Balance is shared at account or organization scope rather than per key.
- No official API-key-authenticated historical usage or remaining rate-quota
  endpoint is published.
- Console-private billing endpoints must not be integrated or scraped.
- Detection tries the locale-matching official endpoint first and probes the
  other region only after definitive authentication rejection. Routine refresh
  uses only the persisted region.
- China balances are normalized as `CNY`; international balances are normalized
  as `USD`.

Official sources:

- https://platform.kimi.com/docs/api/balance
- https://platform.kimi.ai/docs/api/balance
- https://platform.kimi.com/docs/guide/org-best-practice

## MiniMax

Status: Implemented for Token/Coding Plan subscription keys only.

- China Token Plan endpoint:
  `GET https://www.minimaxi.com/v1/token_plan/remains`
- International Token Plan endpoint:
  `GET https://www.minimax.io/v1/token_plan/remains`
- Authentication: Bearer Token Plan Subscription Key.
- The endpoint exposes current Token Plan quota-window information, including
  five-hour and weekly usage or remaining data.
- A normal pay-as-you-go API key does not have a documented public endpoint for
  querying the account's cash balance.
- MiniMax is therefore a quota-window provider, not a monetary-balance
  provider.
- Known `sk-api-...` pay-as-you-go keys are rejected before any network request
  with an unsupported-credential error.
- China and international subscription endpoints are detected using the same
  definitive-authentication-rejection rule as Kimi. HTTP-200 responses with a
  nonzero embedded `base_resp.status_code` are still errors.

Official sources:

- https://platform.minimaxi.com/docs/token-plan/faq.md
- https://platform.minimax.io/docs/token-plan/faq.md

## Implemented Provider Boundary

Provider adapters map vendor responses into capability-based domain values
instead of a single lowest-common-denominator payload:

- monetary balance (`Decimal` plus ISO currency)
- spending-cap remainder
- quota-window remainder and reset time
- optional usage summary
- optional daily series
- credential scope (key, account, organization, or subscription)

Detection validates a newly supplied key and returns both the persisted profile
and the first snapshot. Scheduled refresh uses that stored profile and never
repeats regional probing. Authentication, rate limiting, malformed responses,
and unsupported credential types remain distinct typed errors.

Missing capabilities remain absent rather than becoming zero. Monetary totals
are grouped by currency unless a separately designed exchange-rate feature is
introduced. Spending limits and quota windows never enter cash totals.

## Persistence and Security

- Provider and detected-profile metadata are non-secret and live with account
  preferences in schema version 2.
- Version-1 accounts migrate to API Info without changing their UUIDs or
  UserDefaults storage key.
- Credentials remain in macOS Keychain. The historical service identifier
  `com.liangrui.QuotaGlance.api-info` is intentionally unchanged and now acts as
  the shared internal namespace for all provider keys.
- Request URLs, headers, raw provider responses, and credentials are not logged.
- Widget snapshots contain normalized usage data but never credentials.

## Presentation Rules

- Compact surfaces prefer real balance, spending-limit remainder, quota
  remainder/used percentage, then month/week/today/total spend.
- Every compact value keeps an explicit semantic label; spend is never labeled
  as remaining balance.
- Account views render only capability sections returned by that provider.
- All Accounts and Widgets display separate currency totals; Widgets cap the
  list at two totals.
- Low-balance alerts apply only to a real primary balance. They are unavailable
  for MiniMax and OpenRouter standard keys.
