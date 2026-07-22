# Provider Capability Research

Status: Phase-one scope decision
Date: 2026-07-22

## Decision

QuotaGlance phase one implements only the API Info provider. It supports multiple
API Info credentials, aggregate and per-credential views, refresh scheduling,
WidgetKit snapshots, and low-balance notifications.

The data layer should retain a small source-level provider boundary so another
provider can be added without rewriting refresh, cache, notification, or UI
infrastructure. Phase one must not include a provider picker, a third-party
plugin system, currency conversion, or inactive provider implementations.

## API Info (Phase One)

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

## Deferred Providers

### OpenRouter

Status: Feasible, deferred.

- A normal inference key can call `GET https://openrouter.ai/api/v1/key`.
- It returns per-key spend, an optional per-key spending cap, and daily, weekly,
  and monthly usage. The cap remainder is not the account's credit balance.
- Account credits, all-key metadata, and 30-day activity require a separate
  Management Key through `/credits`, `/keys`, and `/activity`.
- Management Keys are administrative credentials and cannot be treated as
  ordinary inference keys.
- `/key.data.rate_limit` is deprecated and must not be used.

Official sources:

- https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key
- https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits
- https://openrouter.ai/docs/api/api-reference/analytics/get-user-activity-grouped-by-endpoint
- https://openrouter.ai/docs/guides/overview/auth/management-api-keys

### DeepSeek

Status: Feasible as a balance-only provider, deferred.

- Endpoint: `GET https://api.deepseek.com/user/balance`
- Authentication: standard Bearer API key.
- Returns account-wide CNY and/or USD balances, including granted and topped-up
  components.
- The official API does not expose historical usage, billing ledger, or the
  account's effective rate quota.
- Multiple keys from the same account return the same account balance and must
  not be aggregated as independent balances.

Official source:

- https://api-docs.deepseek.com/api/get-user-balance

### Kimi / Moonshot

Status: Feasible as a balance-only provider, deferred.

- China endpoint: `GET https://api.moonshot.cn/v1/users/me/balance`
- International endpoint: `GET https://api.moonshot.ai/v1/users/me/balance`
- Authentication: standard Bearer API key.
- Returns available, cash, and voucher balances. China uses CNY; international
  accounts use USD.
- Balance is shared at account or organization scope rather than per key.
- No official API-key-authenticated historical usage or remaining rate-quota
  endpoint is published.
- Console-private billing endpoints must not be integrated or scraped.

Official sources:

- https://platform.kimi.com/docs/api/balance
- https://platform.kimi.ai/docs/api/balance
- https://platform.kimi.com/docs/guide/org-best-practice

### MiniMax

Status: Partially feasible for Token Plan only, deferred.

- China Token Plan endpoint:
  `GET https://www.minimaxi.com/v1/token_plan/remains`
- International Token Plan endpoint:
  `GET https://www.minimax.io/v1/token_plan/remains`
- Authentication: Bearer Token Plan Subscription Key.
- The endpoint exposes current Token Plan quota-window information, including
  five-hour and weekly usage or remaining data.
- A normal pay-as-you-go API key does not have a documented public endpoint for
  querying the account's cash balance.
- MiniMax would therefore be a quota-window provider, not a monetary-balance
  provider.

Official sources:

- https://platform.minimaxi.com/docs/token-plan/faq.md
- https://platform.minimax.io/docs/token-plan/faq.md

## Future Provider Boundary

Future provider adapters should map vendor responses into capability-based
domain values instead of a single lowest-common-denominator payload:

- monetary balance (`Decimal` plus ISO currency)
- spending-cap remainder
- quota-window remainder and reset time
- optional usage summary
- optional daily series
- credential scope (key, account, organization, or subscription)

Missing capabilities remain absent rather than becoming zero. Monetary totals
are grouped by currency unless a separately designed exchange-rate feature is
introduced. Extensions remain compiled into the app and covered by provider
contract tests; QuotaGlance will not load third-party plugin code.
