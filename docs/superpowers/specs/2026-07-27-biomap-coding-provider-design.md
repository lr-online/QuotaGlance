# BioMap Coding Provider Design

Date: 2026-07-27
Status: Approved by direct implementation request

## Goal

Add a fixed `BioMap Coding` provider for the company LiteLLM proxy at
`https://coding.biomap-int.com`. Show the current virtual key's real LiteLLM
spend and budget when authorized, while degrading clearly to connection-only
status when key-management routes are restricted.

## Verified Deployment Contract

The deployment's public OpenAPI document identifies LiteLLM API version
`1.82.3`. It exposes authenticated `GET /key/info` and `GET /v1/models`, plus an
unauthenticated `GET /health/liveliness`. Both authenticated routes return HTTP
401 without a key, and the service returns the standard LiteLLM auth-error
shape.

LiteLLM 1.82.3 documents `GET /key/info` without a `key` query parameter as a
lookup of the Bearer key itself. Its response is `{ "key": ..., "info": ... }`;
the nested info includes `spend`, `max_budget`, `budget_duration`, `blocked`,
and model restrictions. QuotaGlance ignores the echoed key and never stores it
outside Keychain.

## Data Semantics

- `spend` is cumulative key spend and maps to `SpendSummary.total` in USD.
- `max_budget` is a spending cap, not cash or prepaid credit.
- When both fields exist, remaining budget is derived as
  `max_budget - spend` and presented under `SpendingLimit`.
- No BioMap value enters All Accounts cash-balance totals.
- Missing `spend` stays absent rather than becoming zero.
- The provider does not expose daily history through the two required calls.

LiteLLM's cost system uses USD-denominated model costs and does not return a
currency field from `/key/info`; QuotaGlance labels these standard LiteLLM
cost values as USD and documents the assumption.

## Request Flow

Detection and refresh first call `GET https://coding.biomap-int.com/key/info`
with Bearer authentication and no query string. A valid response maps the
budget capabilities above. A blocked key is rejected as inactive.

If `/key/info` returns HTTP 403, 404, or 405, QuotaGlance calls
`GET https://coding.biomap-int.com/v1/models` with the same key. A valid model
list produces a healthy connection-only snapshot with model count and the
notice `Budget metrics unavailable for this key.` This supports deployments
that allow inference but restrict key-management routes. HTTP 401 remains an
invalid credential; 429 remains rate limiting; unrelated failures are not
hidden by fallback.

## UI And Security

`BioMap Coding` appears as one global standard-key provider. It has no editable
Base URL and no low-balance alert because remaining budget is a cap, not a cash
balance. Existing menu bar and Widget capability rendering show the budget
remainder when available and the existing `Connected` explanation when the
provider is connection-only.

The API key remains in Keychain. It is sent only in the Authorization header,
never in a URL, log, preference, Widget snapshot, or provider response field.

## Testing

Adapter tests cover nested key-info parsing, Decimal precision, budget
derivation, missing metrics, blocked keys, Bearer request construction,
fallback statuses, model-list validation, typed HTTP failures, and fixed
profile enforcement. Domain and registry tests cover provider identity and
low-balance behavior. Full Swift, Xcode, installation, Widget, and secret scans
run before push.

