use async_trait::async_trait;
use cofinex_core::{
    format_base_units, hex_quantity_to_dec, parse_base_units, Address, Balance, ChainAdapter,
    ChainError, ChainId, FungibleToken, PublicKey, Signature, SignedTx, TokenStandard,
    TransferIntent, TxId, TxStatus, UnsignedTx,
};
use cofinex_keys::{Curve, DerivationPath};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha3::{Digest, Keccak256};

use super::address::{address_from_public_key, parse_evm_address};
use super::network::{EvmNetwork, SEPOLIA_CHAIN_ID};
use super::rlp::{eip1559_chain_id, Eip1559};
use super::rpc::{EvmRpc, HttpRpc};

const NATIVE_GAS: u64 = 21_000;

/// EVM adapter shared by Ethereum, BNB Smart Chain, Polygon, and their testnets.
///
/// `R` is the JSON-RPC transport. Tests substitute a scripted transport. The
/// signer is not a type parameter: signing happens outside this type, and this
/// adapter will only build or broadcast a Sepolia transaction.
pub struct EvmAdapter<R: EvmRpc> {
    network: EvmNetwork,
    rpc: Option<R>,
}

impl EvmAdapter<HttpRpc> {
    /// Sepolia. `rpc_url` overrides `COFINEX_SEPOLIA_RPC_URL` when it is non-empty.
    /// Address derivation works with no URL; balance and broadcast do not.
    pub fn sepolia(rpc_url: Option<String>) -> Result<Self, ChainError> {
        Self::for_network(EvmNetwork::SEPOLIA, rpc_url)
    }

    /// Read-only constructor for any [`EvmNetwork`].
    ///
    /// An empty `rpc_url` reads `network.rpc_env` (for example
    /// `COFINEX_ETHEREUM_RPC_URL`). Signing stays disabled unless the network
    /// is Sepolia.
    pub fn for_network(network: EvmNetwork, rpc_url: Option<String>) -> Result<Self, ChainError> {
        let configured = match rpc_url {
            Some(url) if !url.trim().is_empty() => Some(url),
            _ => std::env::var(network.rpc_env).ok(),
        };
        let rpc = match configured
            .map(|url| url.trim().to_string())
            .filter(|url| !url.is_empty())
        {
            Some(url) => Some(HttpRpc::new(url)?),
            None => None,
        };
        Ok(Self { network, rpc })
    }
}

impl<R: EvmRpc> EvmAdapter<R> {
    /// Sepolia adapter with a scripted transport.
    pub fn with_rpc(rpc: R) -> Self {
        Self::with_network(EvmNetwork::SEPOLIA, rpc)
    }

    pub fn with_network(network: EvmNetwork, rpc: R) -> Self {
        Self {
            network,
            rpc: Some(rpc),
        }
    }

    pub fn network(&self) -> EvmNetwork {
        self.network
    }

    async fn rpc(&self) -> Result<&R, ChainError> {
        self.rpc
            .as_ref()
            .ok_or_else(|| ChainError::rpc(self.missing_rpc_message()))
    }

    fn missing_rpc_message(&self) -> String {
        if self.network.evm_chain_id == SEPOLIA_CHAIN_ID {
            "Sepolia RPC URL is not configured. Set COFINEX_SEPOLIA_RPC_URL or pass a URL."
                .to_string()
        } else {
            format!(
                "{} RPC URL is not configured. Set {} or pass a URL.",
                self.network.name, self.network.rpc_env
            )
        }
    }

    async fn ensure_network(&self) -> Result<(), ChainError> {
        let value = self.rpc().await?.request("eth_chainId", Vec::new()).await?;
        let text = value
            .as_str()
            .ok_or_else(|| ChainError::rpc("eth_chainId was not a string"))?;
        let actual = parse_u64_quantity(text)?;
        if actual != self.network.evm_chain_id {
            return Err(ChainError::WrongNetwork {
                expected: self.network.evm_chain_id,
                actual,
            });
        }
        Ok(())
    }

    fn ensure_signing(&self, operation: &'static str) -> Result<(), ChainError> {
        if self.network.signing_enabled() {
            Ok(())
        } else {
            Err(ChainError::not_implemented(self.network.chain, operation))
        }
    }
}

#[async_trait]
impl<R: EvmRpc> ChainAdapter for EvmAdapter<R> {
    fn chain_id(&self) -> ChainId {
        self.network.chain
    }

    fn curve(&self) -> Curve {
        Curve::Secp256k1
    }

    fn derivation_path(&self, account: u32) -> Result<DerivationPath, ChainError> {
        DerivationPath::bip44(Curve::Secp256k1, 60, account, 0, 0)
            .map_err(|_| ChainError::InvalidTransaction)
    }

    fn derive_address(&self, public_key: &PublicKey) -> Result<Address, ChainError> {
        address_from_public_key(public_key, self.network.chain)
    }

    async fn get_balance(&self, address: &Address) -> Result<Balance, ChainError> {
        self.ensure_network().await?;
        if address.chain() != self.network.chain {
            return Err(ChainError::InvalidAddress);
        }
        let parsed = parse_evm_address(address.text())?;
        let canonical = super::address::format_eip55(&parsed);
        let value = self
            .rpc()
            .await?
            .request("eth_getBalance", vec![json!(canonical), json!("latest")])
            .await?;
        balance_from_hex(
            value.as_str(),
            self.network.native_symbol,
            self.network.native_decimals,
        )
    }

    async fn fungible_balance(
        &self,
        holder: &Address,
        token: &FungibleToken,
    ) -> Result<Balance, ChainError> {
        if token.standard != TokenStandard::Erc20 {
            return Err(ChainError::not_implemented(
                self.network.chain,
                "fungible_balance",
            ));
        }
        self.ensure_network().await?;
        if holder.chain() != self.network.chain {
            return Err(ChainError::InvalidAddress);
        }
        let holder_bytes = parse_evm_address(holder.text())?;
        let contract_bytes = parse_evm_address(&token.contract)?;
        let contract = super::address::format_eip55(&contract_bytes);
        let data = erc20_balance_of_data(&holder_bytes);
        let value = self
            .rpc()
            .await?
            .request(
                "eth_call",
                vec![json!({ "to": contract, "data": data }), json!("latest")],
            )
            .await?;
        balance_from_hex(value.as_str(), &token.symbol, token.decimals)
    }

    async fn build_unsigned_tx(&self, intent: &TransferIntent) -> Result<UnsignedTx, ChainError> {
        self.ensure_network().await?;
        self.ensure_signing("build_unsigned_tx")?;
        if intent.from.chain() != self.network.chain || intent.to.chain() != self.network.chain {
            return Err(ChainError::InvalidAddress);
        }
        let from = super::address::format_eip55(&parse_evm_address(intent.from.text())?);
        let to = parse_evm_address(intent.to.text())?;
        let to_text = super::address::format_eip55(&to);
        let value = parse_base_units(&intent.amount_base_units).ok_or(ChainError::InvalidAmount)?;
        let rpc = self.rpc().await?;
        let nonce = parse_u64_quantity(expect_hex(
            &rpc.request(
                "eth_getTransactionCount",
                vec![json!(from), json!("pending")],
            )
            .await?,
        )?)?;
        let priority = parse_u128_quantity(expect_hex(
            &rpc.request("eth_maxPriorityFeePerGas", Vec::new()).await?,
        )?)?;
        let block = rpc
            .request("eth_getBlockByNumber", vec![json!("latest"), json!(false)])
            .await?;
        let base_fee_hex = block
            .get("baseFeePerGas")
            .and_then(Value::as_str)
            .ok_or_else(|| ChainError::rpc("latest block has no baseFeePerGas"))?;
        let base_fee = parse_u128_quantity(base_fee_hex)?;
        let max_fee = base_fee.saturating_mul(2).saturating_add(priority);
        if max_fee == 0 {
            return Err(ChainError::rpc("RPC returned zero fees"));
        }
        let tx = Eip1559 {
            chain_id: SEPOLIA_CHAIN_ID,
            nonce,
            max_priority_fee_per_gas: priority,
            max_fee_per_gas: max_fee,
            gas_limit: NATIVE_GAS,
            to,
            value,
            data: Vec::new(),
        };
        let preimage = tx.signing_preimage();
        if eip1559_chain_id(&preimage)? != SEPOLIA_CHAIN_ID {
            return Err(ChainError::InvalidTransaction);
        }
        let digest = Keccak256::digest(&preimage);
        let body = serde_json::to_vec(&StoredTx::from_tx(&tx, &to_text))
            .map_err(|_| ChainError::InvalidTransaction)?;
        Ok(UnsignedTx {
            chain: self.network.chain,
            curve: Curve::Secp256k1,
            path: intent.path.clone(),
            message: digest.to_vec(),
            prehashed: true,
            body,
            to: to_text,
            amount_base_units: intent.amount_base_units.clone(),
            symbol: self.network.native_symbol.to_string(),
        })
    }

    fn attach_signature(
        &self,
        unsigned: &UnsignedTx,
        signature: &Signature,
    ) -> Result<SignedTx, ChainError> {
        self.ensure_signing("attach_signature")?;
        if unsigned.chain != self.network.chain
            || signature.curve() != Curve::Secp256k1
            || signature.as_bytes().len() != 65
        {
            return Err(ChainError::InvalidSignature);
        }
        let stored: StoredTx =
            serde_json::from_slice(&unsigned.body).map_err(|_| ChainError::InvalidTransaction)?;
        let tx = stored.to_tx()?;
        if tx.chain_id != SEPOLIA_CHAIN_ID {
            return Err(ChainError::WrongNetwork {
                expected: SEPOLIA_CHAIN_ID,
                actual: tx.chain_id,
            });
        }
        let bytes = signature.as_bytes();
        let raw = tx.signed_raw(bytes[64], &bytes[..32], &bytes[32..64])?;
        let embedded = eip1559_chain_id(&raw)?;
        if embedded != SEPOLIA_CHAIN_ID {
            return Err(ChainError::WrongNetwork {
                expected: SEPOLIA_CHAIN_ID,
                actual: embedded,
            });
        }
        Ok(SignedTx {
            chain: self.network.chain,
            raw,
        })
    }

    async fn broadcast_signed_tx(&self, tx: &SignedTx) -> Result<TxId, ChainError> {
        self.ensure_signing("broadcast_signed_tx")?;
        if tx.chain != self.network.chain {
            return Err(ChainError::InvalidTransaction);
        }
        let chain_id = eip1559_chain_id(&tx.raw)?;
        if chain_id != SEPOLIA_CHAIN_ID {
            return Err(ChainError::WrongNetwork {
                expected: SEPOLIA_CHAIN_ID,
                actual: chain_id,
            });
        }
        self.ensure_network().await?;
        let raw = format!("0x{}", hex::encode(&tx.raw));
        let value = self
            .rpc()
            .await?
            .request("eth_sendRawTransaction", vec![json!(raw)])
            .await?;
        let hash = value
            .as_str()
            .filter(|hash| is_tx_hash(hash))
            .ok_or_else(|| ChainError::rpc("broadcast did not return a transaction hash"))?;
        Ok(TxId::new(hash.to_ascii_lowercase()))
    }

    async fn tx_status(&self, tx_id: &TxId) -> Result<TxStatus, ChainError> {
        if !is_tx_hash(tx_id.as_str()) {
            return Err(ChainError::InvalidTransaction);
        }
        self.ensure_network().await?;
        let rpc = self.rpc().await?;
        let receipt = rpc
            .request("eth_getTransactionReceipt", vec![json!(tx_id.as_str())])
            .await?;
        if receipt.is_null() {
            let tx = rpc
                .request("eth_getTransactionByHash", vec![json!(tx_id.as_str())])
                .await?;
            return Ok(if tx.is_null() {
                TxStatus::NotFound
            } else {
                TxStatus::Pending
            });
        }
        let success = receipt
            .get("status")
            .and_then(Value::as_str)
            .map(|status| status == "0x1" || status == "0x01")
            .ok_or_else(|| ChainError::rpc("receipt has no status"))?;
        let block_number = parse_u64_quantity(
            receipt
                .get("blockNumber")
                .and_then(Value::as_str)
                .ok_or_else(|| ChainError::rpc("receipt has no block number"))?,
        )?;
        Ok(TxStatus::Confirmed {
            success,
            block_number,
        })
    }
}

/// ABI calldata for `balanceOf(address)`. The selector is keccak256("balanceOf(address)")[..4].
pub(crate) fn erc20_balance_of_data(holder: &[u8; 20]) -> String {
    let hash = Keccak256::digest(b"balanceOf(address)");
    let mut data = Vec::with_capacity(36);
    data.extend_from_slice(&hash[..4]);
    data.extend_from_slice(&[0u8; 12]);
    data.extend_from_slice(holder);
    format!("0x{}", hex::encode(data))
}

fn balance_from_hex(
    value: Option<&str>,
    symbol: &str,
    decimals: u8,
) -> Result<Balance, ChainError> {
    let hex_value = value.ok_or_else(|| ChainError::rpc("balance was not a hex quantity"))?;
    let base_units = hex_quantity_to_dec(hex_value)
        .ok_or_else(|| ChainError::rpc("balance was not a hex quantity"))?;
    let display = format_base_units(&base_units, decimals).ok_or(ChainError::InvalidAmount)?;
    Ok(Balance {
        symbol: symbol.to_string(),
        base_units,
        decimals,
        display,
    })
}

#[derive(Serialize, Deserialize)]
struct StoredTx {
    chain_id: u64,
    nonce: u64,
    max_priority_fee_per_gas: String,
    max_fee_per_gas: String,
    gas_limit: u64,
    to: String,
    value: String,
}

impl StoredTx {
    fn from_tx(tx: &Eip1559, to: &str) -> Self {
        Self {
            chain_id: tx.chain_id,
            nonce: tx.nonce,
            max_priority_fee_per_gas: tx.max_priority_fee_per_gas.to_string(),
            max_fee_per_gas: tx.max_fee_per_gas.to_string(),
            gas_limit: tx.gas_limit,
            to: to.to_string(),
            value: tx.value.to_string(),
        }
    }

    fn to_tx(&self) -> Result<Eip1559, ChainError> {
        let to = parse_evm_address(&self.to)?;
        Ok(Eip1559 {
            chain_id: self.chain_id,
            nonce: self.nonce,
            max_priority_fee_per_gas: self
                .max_priority_fee_per_gas
                .parse()
                .map_err(|_| ChainError::InvalidTransaction)?,
            max_fee_per_gas: self
                .max_fee_per_gas
                .parse()
                .map_err(|_| ChainError::InvalidTransaction)?,
            gas_limit: self.gas_limit,
            to,
            value: self
                .value
                .parse()
                .map_err(|_| ChainError::InvalidTransaction)?,
            data: Vec::new(),
        })
    }
}

fn expect_hex(value: &Value) -> Result<&str, ChainError> {
    value
        .as_str()
        .ok_or_else(|| ChainError::rpc("expected a hex quantity"))
}

fn parse_u64_quantity(value: &str) -> Result<u64, ChainError> {
    let decimal =
        hex_quantity_to_dec(value).ok_or_else(|| ChainError::rpc("invalid hex quantity"))?;
    decimal
        .parse()
        .map_err(|_| ChainError::rpc("hex quantity does not fit u64"))
}

fn parse_u128_quantity(value: &str) -> Result<u128, ChainError> {
    let decimal =
        hex_quantity_to_dec(value).ok_or_else(|| ChainError::rpc("invalid hex quantity"))?;
    decimal
        .parse()
        .map_err(|_| ChainError::rpc("hex quantity does not fit u128"))
}

fn is_tx_hash(value: &str) -> bool {
    let hex_body = value.strip_prefix("0x").unwrap_or(value);
    hex_body.len() == 64 && hex_body.bytes().all(|byte| byte.is_ascii_hexdigit())
}
