// ProviderError enum + cross-platform error-token table.
//
// The error tokens below are the cross-platform protocol. They appear verbatim
// in `Contracts/README.md` "Error tokens" and in:
//   - Swift `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`
//   - ArkTS `HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets` header
//   - Kotlin `Android/app/src/main/java/.../core/ProviderError.kt`
// New tokens must be appended on all four platforms; the Rust enum mirrors
// the Swift shape exactly (NOT ArkTS' `httpStatus:<code>` string-tag form).
//
// Two tokens are framework-level and NEVER appear in a spec JSON:
//   - `providerUnavailable` (registry), and
//   - `network:<detail>` (transport).
// They are produced by the registry / HTTP seam, not by the spec engine.

use thiserror::Error;

use crate::domain::ProviderID;

#[derive(Debug, Clone, Error, PartialEq, Eq)]
pub enum ProviderError {
    #[error("invalidCredential")]
    InvalidCredential,
    #[error("rateLimited")]
    RateLimited,
    /// Carries the actual HTTP status code. The contract layer uses
    /// `httpStatus:<code>` for the ArkTS side, but Rust stores the code in a
    /// struct field so the value is round-trippable.
    #[error("httpStatus:{}", _0)]
    HttpStatus(u16),
    #[error("invalidResponse")]
    InvalidResponse,
    #[error("providerInactive")]
    ProviderInactive,
    #[error("unsupportedCredential")]
    UnsupportedCredential,
    #[error("regionDetectionFailed")]
    RegionDetectionFailed,
    #[error("profileMismatch")]
    ProfileMismatch,
    #[error("providerUnavailable:{}", _0.raw_value())]
    ProviderUnavailable(ProviderID),
}

/// Cross-platform error-token table.
///
/// `KNOWN_ERROR_TOKENS` in `providers/provider_spec.rs` validates spec JSON
/// against this list. Tokens not in this set are rejected at spec load.
pub const KNOWN_ERROR_TOKENS: &[&str] = &[
    "invalidCredential",
    "rateLimited",
    "httpStatus",
    "invalidResponse",
    "providerInactive",
    "unsupportedCredential",
    "regionDetectionFailed",
    "profileMismatch",
];

/// Transport-level error surface. Distinct from `ProviderError`; the spec
/// engine never emits these (they're produced by the HTTP seam). Modeled
/// as a separate type so callers can distinguish "provider said X" from
/// "we couldn't reach the provider".
#[derive(Debug, Clone, Error, PartialEq, Eq)]
pub enum TransportError {
    #[error("offline")]
    Offline,
    #[error("timeout")]
    Timeout,
    #[error("tls")]
    Tls,
    #[error("network:{0}")]
    Network(String),
}

impl ProviderError {
    /// Stable token string used in fixture cross-checks and log lines.
    pub fn token(&self) -> &'static str {
        match self {
            Self::InvalidCredential => "invalidCredential",
            Self::RateLimited => "rateLimited",
            Self::HttpStatus(_) => "httpStatus",
            Self::InvalidResponse => "invalidResponse",
            Self::ProviderInactive => "providerInactive",
            Self::UnsupportedCredential => "unsupportedCredential",
            Self::RegionDetectionFailed => "regionDetectionFailed",
            Self::ProfileMismatch => "profileMismatch",
            Self::ProviderUnavailable(_) => "providerUnavailable",
        }
    }

    /// True if the error should advance to the next profile candidate under
    /// `regionFallback` detect (Swift `fallbackOn` list). Matches the spec
    /// schema and is the only condition under which a fallback occurs.
    pub fn is_region_fallback_trigger(&self) -> bool {
        matches!(self, Self::InvalidCredential)
    }
}

impl From<crate::providers::spec_engine::SpecError> for ProviderError {
    fn from(_err: crate::providers::spec_engine::SpecError) -> Self {
        ProviderError::InvalidResponse
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_error_tokens_stable() {
        // Mirror `knownErrorTokens` from Swift `ProviderSpec.swift` and the
        // header of `HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets`.
        assert_eq!(
            KNOWN_ERROR_TOKENS,
            &[
                "invalidCredential",
                "rateLimited",
                "httpStatus",
                "invalidResponse",
                "providerInactive",
                "unsupportedCredential",
                "regionDetectionFailed",
                "profileMismatch",
            ],
        );
    }

    #[test]
    fn http_status_carries_code() {
        let err = ProviderError::HttpStatus(503);
        assert_eq!(err.token(), "httpStatus");
        assert!(matches!(err, ProviderError::HttpStatus(503)));
    }

    #[test]
    fn provider_unavailable_token_carries_provider() {
        let err = ProviderError::ProviderUnavailable(ProviderID::OpenRouter);
        assert_eq!(err.token(), "providerUnavailable");
        assert!(matches!(err, ProviderError::ProviderUnavailable(ProviderID::OpenRouter)));
    }

    #[test]
    fn region_fallback_only_on_invalid_credential() {
        assert!(ProviderError::InvalidCredential.is_region_fallback_trigger());
        assert!(!ProviderError::RateLimited.is_region_fallback_trigger());
        assert!(!ProviderError::HttpStatus(429).is_region_fallback_trigger());
    }
}
