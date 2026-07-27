# Alibaba Cloud Model Studio Provider Design

Date: 2026-07-27
Status: Approved by direct implementation request

## Goal

Add Alibaba Cloud Model Studio (Bailian) as one provider that validates a
DashScope API key against the account's OpenAI-compatible Base URL. The app
must explain when the key is connected but billing metrics are unavailable.

## Verified Capability Boundary

Both the supplied Beijing workspace endpoint and the legacy public Beijing
endpoint returned HTTP 200 from `GET /models` with the supplied API key. The
response used the OpenAI-compatible `object=list` shape and contained 231
models at test time.

DashScope API keys do not have a documented public endpoint for balance,
accumulated spend, or remaining free quota. Alibaba Cloud
`QueryAccountBalance` is a separate BSS OpenAPI that requires a RAM AccessKey
signature and returns the whole Alibaba Cloud account balance. QuotaGlance will
not request that higher-privilege credential or present account-wide BSS data
as a per-key Bailian balance in this feature.

## Account Configuration

One visible `Alibaba Cloud Model Studio` provider supports public and
workspace-specific OpenAI-compatible Base URLs. New accounts default to
`https://dashscope.aliyuncs.com/compatible-mode/v1` and may replace it with the
API Host shown by the Bailian console.

Only HTTPS endpoints on these official host families are accepted:

- `dashscope.aliyuncs.com`
- `dashscope-intl.aliyuncs.com`
- `dashscope-us.aliyuncs.com`
- `{WorkspaceId}.cn-beijing.maas.aliyuncs.com`
- `{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com`
- `{WorkspaceId}.ap-northeast-1.maas.aliyuncs.com`

The path is normalized to `/compatible-mode/v1`. Query strings, fragments,
userinfo, custom ports, and other hosts are rejected before the API key can be
sent. This prevents a user typo or malicious configuration from exfiltrating a
Keychain credential.

The normalized Base URL is non-secret account metadata stored with existing
preferences. The API key remains the only Keychain value. Widget snapshots do
not include either value.

## Detection And Refresh

Saving an account calls `GET {baseURL}/models` with Bearer authentication. A
valid OpenAI-compatible model list produces a healthy snapshot and persists a
China or international profile based on the official endpoint host. Refreshes
reuse the saved Base URL and profile; a region mismatch is rejected.

The snapshot contains no monetary or quota metrics. It carries a concise
notice such as `231 models available. Billing metrics unavailable for this API
key.` The menu bar and Widget render `Connected` plus that notice instead of
`No metric` or a fabricated zero balance.

## Errors

- HTTP 401/403: invalid credential.
- HTTP 429: rate limited.
- Other HTTP failures: retain the status code.
- Invalid or empty model-list payload: invalid provider response.
- Unsupported or malformed Base URL: actionable endpoint validation error.
- Network failure: existing offline, timeout, and stale-data behavior applies.

## Testing

Provider tests cover endpoint normalization and allowlisting, Bearer request
construction, regional detection, payload parsing, profile mismatch, and typed
HTTP errors. Domain and validation tests cover persistence and editor input.
Refresh tests prove the saved public configuration reaches the adapter. Widget
presentation tests prove connection-only snapshots expose the explanatory
notice without inventing a quantitative metric.

