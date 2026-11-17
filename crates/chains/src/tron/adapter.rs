use async_trait::async_trait;
use cofinex_core::{
    format_base_units, hex_quantity_to_dec, Address, Balance, ChainAdapter, ChainError, ChainId,
    FungibleToken, PublicKey, Signature, SignedTx, TokenStandard, TransferIntent, TxId, TxStatus,
    UnsignedTx,
};
use cofinex_keys::{Curve, DerivationPath};
use serde_json::{json, Value};

use super::address::{account_bytes, address_from_public_key, parse_tron_address};
use super::rpc::{HttpTronRpc, TronRpc};

const TRX_DECIMALS: u8 = 6;

/// Read-only TRON adapter. Native TRX uses `/wallet/getaccount`. TRC-20 uses
/// `balanceOf(address)` via `/wallet/triggerconstantcontract`. There is no
/// signing path.
pub struct TronAdapter<R: TronRpc> {
    rpc: Option<R>,
}

impl TronAdapter<HttpTronRpc> {
    /// `rpc_url` overrides `COFINEX_TRON_RPC_URL` when it is non-empty.
    /// Address derivation works with no URL.
    pub fn mainnet(rpc_url: Option<String>) -> Result<Self, ChainError> {
        let configured = match rpc_url {
            Some(url) if !url.trim().is_empty() => Some(url),
            _ => std::env::var("COFINEX_TRON_RPC_URL").ok(),
        };
        let rpc = match configured
            .map(|url| url.trim().to_string())
            .filter(|url| !url.is_empty())
        {
            Some(url) => Some(HttpTronRpc::new(url)?),
            None => None,
        };
        Ok(Self { rpc })
    }
}

impl<R: TronRpc> TronAdapter<R> {
    pub fn with_rpc(rpc: R) -> Self {
        Self { rpc: Some(rpc) }
    }

    fn rpc(&self) -> Result<&R, ChainError> {
        self.rpc.as_ref().ok_or_else(|| {
            ChainError::rpc(
                "TRON API URL is not configured. Set COFINEX_TRON_RPC_URL or pass a URL.",
            )
        })
    }

    fn require_holder(&self, holder: &Address) -> Result<[u8; 20], ChainError> {
        if holder.chain() != ChainId::Tron {
            return Err(ChainError::InvalidAddress);
        }
        let payload = parse_tron_address(holder.text())?;
        Ok(account_bytes(&payload))
    }
}

#[async_trait]
impl<R: TronRpc> ChainAdapter for TronAdapter<R> {
    fn chain_id(&self) -> ChainId {
        ChainId::Tron
    }

    fn curve(&self) -> Curve {
        Curve::Secp256k1
    }

    fn derivation_path(&self, account: u32) -> Result<DerivationPath, ChainError> {
        DerivationPath::bip44(Curve::Secp256k1, 195, account, 0, 0)
            .map_err(|_| ChainError::InvalidTransaction)
    }

    fn derive_address(&self, public_key: &PublicKey) -> Result<Address, ChainError> {
        address_from_public_key(public_key)
    }

    async fn get_balance(&self, address: &Address) -> Result<Balance, ChainError> {
        self.require_holder(address)?;
        let value = self
            .rpc()?
            .post(
                "/wallet/getaccount",
                json!({ "address": address.text(), "visible": true }),
            )
            .await?;
        let sun = match value.get("balance") {
            None => "0".to_string(),
            Some(balance) => json_uint(balance)?,
        };
        render_balance("TRX", &sun, TRX_DECIMALS)
    }

    async fn fungible_balance(
        &self,
        holder: &Address,
        token: &FungibleToken,
    ) -> Result<Balance, ChainError> {
        if token.standard != TokenStandard::Trc20 {
            return Err(ChainError::not_implemented(
                ChainId::Tron,
                "fungible_balance",
            ));
        }
        let account = self.require_holder(holder)?;
        parse_tron_address(&token.contract)?;
        let parameter = format!("{:0>64}", hex::encode(account));
        let value = self
            .rpc()?
            .post(
                "/wallet/triggerconstantcontract",
                json!({
                    "owner_address": holder.text(),
                    "contract_address": token.contract,
                    "function_selector": "balanceOf(address)",
                    "parameter": parameter,
                    "visible": true,
                }),
            )
            .await?;
        let accepted = value
            .get("result")
            .and_then(|result| result.get("result"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if !accepted {
            return Err(ChainError::rpc("TRC-20 balanceOf was rejected"));
        }
        let hex_word = value
            .get("constant_result")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .and_then(Value::as_str)
            .ok_or_else(|| ChainError::rpc("TRC-20 balanceOf returned no word"))?;
        let base_units = hex_quantity_to_dec(hex_word)
            .ok_or_else(|| ChainError::rpc("TRC-20 balanceOf returned a non-integer"))?;
        render_balance(&token.symbol, &base_units, token.decimals)
    }

    async fn build_unsigned_tx(&self, _intent: &TransferIntent) -> Result<UnsignedTx, ChainError> {
        Err(ChainError::not_implemented(
            ChainId::Tron,
            "build_unsigned_tx",
        ))
    }

    fn attach_signature(
        &self,
        _unsigned: &UnsignedTx,
        _signature: &Signature,
    ) -> Result<SignedTx, ChainError> {
        Err(ChainError::not_implemented(
            ChainId::Tron,
            "attach_signature",
        ))
    }

    async fn broadcast_signed_tx(&self, _tx: &SignedTx) -> Result<TxId, ChainError> {
        Err(ChainError::not_implemented(
            ChainId::Tron,
            "broadcast_signed_tx",
        ))
    }

    async fn tx_status(&self, _tx_id: &TxId) -> Result<TxStatus, ChainError> {
        Err(ChainError::not_implemented(ChainId::Tron, "tx_status"))
    }
}

fn render_balance(symbol: &str, base_units: &str, decimals: u8) -> Result<Balance, ChainError> {
    let display = format_base_units(base_units, decimals).ok_or(ChainError::InvalidAmount)?;
    Ok(Balance {
        symbol: symbol.to_string(),
        base_units: base_units.to_string(),
        decimals,
        display,
    })
}

fn json_uint(value: &Value) -> Result<String, ChainError> {
    if let Some(number) = value.as_u64() {
        return Ok(number.to_string());
    }
    if let Some(number) = value.as_i64() {
        if number >= 0 {
            return Ok(number.to_string());
        }
    }
    if let Some(text) = value.as_str() {
        if !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()) {
            let trimmed = text.trim_start_matches('0');
            return Ok(if trimmed.is_empty() {
                "0".to_string()
            } else {
                trimmed.to_string()
            });
        }
    }
    Err(ChainError::rpc("TRON balance was not an integer"))
}
