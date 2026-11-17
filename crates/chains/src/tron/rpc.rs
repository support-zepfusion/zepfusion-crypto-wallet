use std::time::Duration;

use async_trait::async_trait;
use cofinex_core::ChainError;
use serde_json::Value;

/// TronGrid-compatible HTTP API. Implementations must not log request bodies.
#[async_trait]
pub trait TronRpc: Send + Sync {
    async fn post(&self, path: &str, body: Value) -> Result<Value, ChainError>;
}

#[derive(Clone, Debug)]
pub struct HttpTronRpc {
    base_url: String,
    client: reqwest::Client,
}

impl HttpTronRpc {
    pub fn new(base_url: String) -> Result<Self, ChainError> {
        let trimmed = base_url.trim().trim_end_matches('/');
        if !(trimmed.starts_with("https://") || trimmed.starts_with("http://")) {
            return Err(ChainError::rpc(
                "TRON API URL must start with http:// or https://",
            ));
        }
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(20))
            .user_agent("cofinex-wallet/0.1")
            .build()
            .map_err(|_| ChainError::rpc("failed to build HTTP client"))?;
        Ok(Self {
            base_url: trimmed.to_string(),
            client,
        })
    }
}

#[async_trait]
impl TronRpc for HttpTronRpc {
    async fn post(&self, path: &str, body: Value) -> Result<Value, ChainError> {
        let url = format!("{}{path}", self.base_url);
        let response = self
            .client
            .post(url)
            .json(&body)
            .send()
            .await
            .map_err(|_| ChainError::rpc("network request failed"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(ChainError::rpc(format!("http status {status}")));
        }
        response
            .json()
            .await
            .map_err(|_| ChainError::rpc("invalid JSON response"))
    }
}
