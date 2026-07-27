# Provider Capability Research

Status: Implemented
Date: 2026-07-27

## Decision

QuotaGlance implements seven visible provider families: API Info, DeepSeek,
Kimi, OpenRouter, MiniMax, Alibaba Cloud Model Studio (Bailian), and BioMap
Coding. Kimi and MiniMax each remain one provider in the picker; the app detects
China versus international credentials and persists the resolved region.
OpenRouter detects standard versus management credentials. Bailian detects
region from its validated official Base URL. BioMap Coding uses its fixed
company LiteLLM deployment.

Provider responses map into independent balance, spending-limit, spend-period,
and quota-window capabilities. Only real balances enter All Accounts totals.
Totals are grouped by ISO currency without conversion, and missing capabilities
remain absent rather than becoming zero.

Adapters are compiled into the app. QuotaGlance does not load third-party
provider plugins or accept arbitrary endpoint URLs. Bailian accepts only its
documented Alibaba Cloud DashScope and workspace endpoint families.

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

## Alibaba Cloud Model Studio / Bailian

Status: Implemented as a connection-only provider.

- Default Beijing Base URL:
  `https://dashscope.aliyuncs.com/compatible-mode/v1`
- Preferred Beijing workspace Base URL:
  `https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`
- Other documented regions include Singapore and Tokyo workspace hosts plus
  the Virginia public host. Keys are regional and are not interchangeable.
- Authentication: DashScope Bearer API key.
- Validation endpoint: `GET <Base URL>/models`.
- Live verification on 2026-07-27 returned HTTP 200 and the OpenAI-compatible
  `object=list` shape from both the supplied Beijing workspace URL and the
  public Beijing URL. Both listed 231 models at verification time.
- Newly issued pay-as-you-go keys use the longer `sk-ws` format. This is a key
  format upgrade, not a separate balance credential type.
- Probes of plausible `/usage`, `/balance`, `/billing`, `/credits`, `/account`,
  and usage-summary paths did not identify a documented API-key-authenticated
  billing endpoint.
- Alibaba Cloud BSS `QueryAccountBalance` is a separate RAM AccessKey-signed
  OpenAPI. It returns the whole Alibaba Cloud account balance, not a balance
  scoped to the Bailian API key, and therefore is not integrated here.
- Free quotas are model-specific and exposed through the console rather than a
  documented DashScope API-key endpoint. Console-private APIs and login cookies
  are not scraped.
- A successful refresh returns a healthy connection-only snapshot with model
  count and an explicit billing-unavailable notice. It returns no fabricated
  balance, spend, quota, or currency. China and international endpoint profiles
  remain distinct, but CNY or USD is shown only if a future official API returns
  an actual monetary value.
- Base URL validation requires HTTPS, the exact OpenAI-compatible path, and an
  allowlisted official host. Userinfo, ports, query strings, fragments, and
  unrelated hosts are rejected before a Keychain credential is read or sent.

Official sources:

- https://help.aliyun.com/zh/model-studio/get-api-key
- https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope
- https://help.aliyun.com/zh/user-center/developer-reference/api-bssopenapi-2017-12-14-queryaccountbalance

## BioMap Coding

Status: Implemented for LiteLLM virtual keys.

- Fixed deployment: `https://coding.biomap-int.com`
- The deployment's public OpenAPI document reported LiteLLM `1.82.3` during
  research on 2026-07-27.
- Authentication: Bearer virtual key. The credential is never placed in a URL
  query parameter.
- Primary endpoint: `GET /key/info`, called without a `key` query parameter so
  LiteLLM resolves the authorized Bearer key itself.
- The nested `info.spend` value maps to cumulative `USD` key spend.
  `info.max_budget` maps to a spending cap, and the displayed remainder is
  `max_budget - spend`. Neither the cap nor its remainder is a cash balance, so
  it never enters All Accounts monetary totals.
- An `info.blocked` key is treated as inactive. Missing spend or budget fields
  remain unavailable rather than becoming zero.
- Some LiteLLM deployments restrict the key-info management route. Only an
  explicit 403, 404, or 405 response falls back to `GET /v1/models`; a valid
  model list then produces a connection-only snapshot with model count and a
  clear budget-unavailable notice.
- Authentication failures, rate limits, server errors, and malformed responses
  do not trigger fallback and remain typed errors.

Research sources:

- https://coding.biomap-int.com/openapi.json
- https://docs.litellm.ai/docs/proxy/virtual_keys

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

- Provider, detected-profile, and allowlisted Base URL metadata are non-secret
  and live with account preferences in schema version 2.
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
- Healthy connection-only accounts show `Connected` and the provider's reason
  that quantitative metrics are unavailable instead of `No metric`.
- Low-balance alerts apply only to a real primary balance. They are unavailable
  for MiniMax, Bailian, BioMap Coding, and OpenRouter standard keys.
