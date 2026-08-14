// HTTP seam. Mirrors Swift `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`
// `protocol HTTPClient`. The spec engine talks to this trait only; production
// uses `reqwest`, tests use a recording mock.
//
// The trait is `async` (Tokio runtime; matches Swift's `URLSession.data(for:)`)
// and returns the raw body + status code so the spec engine can implement
// `onStatus` first-match dispatch.

use async_trait::async_trait;

use crate::providers::provider_error::TransportError;

/// Raw response body. Either parsed JSON (the common case) or a `Bytes`
/// buffer for binary transport. The spec engine never has to touch the
/// transport type; it works on `serde_json::Value`.
#[derive(Debug, Clone)]
pub struct RawResponse {
    pub status: u16,
    pub body: serde_json::Value,
}

#[async_trait]
pub trait HttpClient: Send + Sync {
    /// Issue `GET <url>` with the given header table. Header values are
    /// already interpolated by the spec engine (`${apiKey}` is gone); the
    /// client just sends them verbatim. Transport failures map to
    /// `TransportError`, not `ProviderError`.
    async fn get_json(
        &self,
        url: &str,
        headers: &[(&str, &str)],
    ) -> Result<RawResponse, TransportError>;
}

/// Production transport for the spec runtime. The contract engine owns all
/// request construction; this type only sends the already-resolved GET request
/// and returns its JSON body with the original HTTP status.
pub struct ReqwestHttpClient {
    client: reqwest::Client,
}

impl ReqwestHttpClient {
    pub fn new() -> Result<Self, TransportError> {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(20))
            .build()
            .map_err(|error| TransportError::Network(error.to_string()))?;
        Ok(Self { client })
    }
}

#[async_trait]
impl HttpClient for ReqwestHttpClient {
    async fn get_json(
        &self,
        url: &str,
        headers: &[(&str, &str)],
    ) -> Result<RawResponse, TransportError> {
        let mut request = self.client.get(url);
        for (name, value) in headers {
            request = request.header(*name, *value);
        }

        let response = request.send().await.map_err(map_reqwest_error)?;
        let status = response.status().as_u16();
        let body = response
            .json::<serde_json::Value>()
            .await
            .map_err(|error| TransportError::Network(format!("invalid JSON: {error}")))?;
        Ok(RawResponse { status, body })
    }
}

fn map_reqwest_error(error: reqwest::Error) -> TransportError {
    if error.is_timeout() {
        TransportError::Timeout
    } else if error.is_connect() {
        TransportError::Offline
    } else {
        TransportError::Network(error.to_string())
    }
}
