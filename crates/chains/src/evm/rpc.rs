use std::time::Duration;

use async_trait::async_trait;
use cofinex_core::ChainError;
use serde_json::{json, Value};

/// JSON-RPC client used by the Sepolia adapter. Implementations must not log
/// request bodies: a signed transaction is not a key, but it is still not
/// something to print while debugging.
#[async_trait]
pub trait EvmRpc: Send + Sync {
    async fn request(&self, method: &str, params: Vec<Value>) -> Result<Value, ChainError>;
}

#[derive(Clone, Debug)]
pub struct HttpRpc {
    url: String,
    client: reqwest::Client,
}

impl HttpRpc {
    pub fn new(url: String) -> Result<Self, ChainError> {
        let trimmed = url.trim();
        if !(trimmed.starts_with("https://") || trimmed.starts_with("http://")) {
            return Err(ChainError::rpc(
                "Sepolia RPC URL must start with http:// or https://",
            ));
        }
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(20))
            .user_agent("cofinex-wallet/0.1")
            .build()
            .map_err(|_| ChainError::rpc("failed to build HTTP client"))?;
        Ok(Self {
            url: trimmed.to_string(),
            client,
        })
    }
}

#[async_trait]
impl EvmRpc for HttpRpc {
    async fn request(&self, method: &str, params: Vec<Value>) -> Result<Value, ChainError> {
        let body = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });
        let response = self
            .client
            .post(&self.url)
            .json(&body)
            .send()
            .await
            .map_err(|_| ChainError::rpc("network request failed"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(ChainError::rpc(format!("http status {status}")));
        }
        let payload: Value = response
            .json()
            .await
            .map_err(|_| ChainError::rpc("invalid JSON response"))?;
        if let Some(error) = payload.get("error") {
            let message = error
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("RPC error");
            return Err(ChainError::rpc(message));
        }
        payload
            .get("result")
            .cloned()
            .ok_or_else(|| ChainError::rpc("response has no result"))
    }
}
