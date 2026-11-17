//! Wallet core.
//!
//! [`ChainAdapter`] is the only thing a chain implementation has to provide.
//! [`Wallet`] asks a [`Signer`](cofinex_signer::Signer) for a signature and
//! hands the signature back to the adapter. Adapters never import a signer.

#![forbid(unsafe_code)]

mod amount;
mod wallet;

pub use amount::{format_base_units, hex_quantity_to_dec, parse_base_units};
pub use wallet::Wallet;

use async_trait::async_trait;
use cofinex_signer::SignerError;
use thiserror::Error;

pub use cofinex_keys::{Curve, DerivationPath, PublicKey, Signature};

/// Networks the signing core knows about.
///
/// Ethereum mainnet is intentionally absent. The only EVM network with a
/// working adapter is Sepolia.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ChainId {
    Bitcoin,
    EthereumSepolia,
    Tron,
    Solana,
    Sui,
}

impl ChainId {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bitcoin => "bitcoin",
            Self::EthereumSepolia => "ethereum-sepolia",
            Self::Tron => "tron",
            Self::Solana => "solana",
            Self::Sui => "sui",
        }
    }
}

impl core::fmt::Display for ChainId {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// An address on one chain. The text form is chain-specific.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Address {
    chain: ChainId,
    text: String,
}

impl Address {
    pub fn new(chain: ChainId, text: impl Into<String>) -> Self {
        Self {
            chain,
            text: text.into(),
        }
    }

    pub fn chain(&self) -> ChainId {
        self.chain
    }

    pub fn text(&self) -> &str {
        &self.text
    }
}

/// A balance in base units (wei, satoshi, lamport, mist).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Balance {
    pub symbol: String,
    pub base_units: String,
    pub decimals: u8,
    pub display: String,
}

/// Native-asset transfer the user has already reviewed.
#[derive(Clone, Debug)]
pub struct TransferIntent {
    pub from: Address,
    pub to: Address,
    pub amount_base_units: String,
    pub path: DerivationPath,
}

/// Chain-specific unsigned transaction.
///
/// `message` is what [`cofinex_signer::Signer::sign`] receives. `body` is
/// opaque to the signer and is interpreted only by the adapter that built it.
#[derive(Clone, Debug)]
pub struct UnsignedTx {
    pub chain: ChainId,
    pub curve: Curve,
    pub path: DerivationPath,
    pub message: Vec<u8>,
    pub prehashed: bool,
    pub body: Vec<u8>,
    pub to: String,
    pub amount_base_units: String,
    pub symbol: String,
}

/// A transaction that has a signature attached and can be broadcast.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SignedTx {
    pub chain: ChainId,
    pub raw: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TxId(String);

impl TxId {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TxStatus {
    NotFound,
    Pending,
    Confirmed { success: bool, block_number: u64 },
}

#[derive(Debug, Error)]
pub enum ChainError {
    #[error("{chain} does not implement {operation} yet")]
    NotImplemented {
        chain: ChainId,
        operation: &'static str,
    },
    #[error("RPC error: {message}")]
    Rpc { message: String },
    #[error("address is invalid")]
    InvalidAddress,
    #[error("public key cannot be used on this chain")]
    InvalidPublicKey,
    #[error("refusing chain id {actual}; this adapter only talks to chain id {expected}")]
    WrongNetwork { expected: u64, actual: u64 },
    #[error("amount is invalid")]
    InvalidAmount,
    #[error("signature is invalid")]
    InvalidSignature,
    #[error("transaction is invalid")]
    InvalidTransaction,
}

impl ChainError {
    pub fn rpc(message: impl Into<String>) -> Self {
        Self::Rpc {
            message: message.into(),
        }
    }

    pub fn not_implemented(chain: ChainId, operation: &'static str) -> Self {
        Self::NotImplemented { chain, operation }
    }
}

#[derive(Debug, Error)]
pub enum CoreError {
    #[error(transparent)]
    Signer(#[from] SignerError),
    #[error(transparent)]
    Chain(#[from] ChainError),
    #[error("signing path does not match the requested account")]
    PathMismatch,
}

/// One blockchain family.
///
/// `attach_signature` is chain-specific encoding. It stays on the adapter so
/// a local signer and an MPC signer produce the same [`Signature`] bytes and
/// the adapter does not change.
#[async_trait]
pub trait ChainAdapter: Send + Sync {
    fn chain_id(&self) -> ChainId;

    fn curve(&self) -> Curve;

    fn derivation_path(&self, account: u32) -> Result<DerivationPath, ChainError>;

    fn derive_address(&self, public_key: &PublicKey) -> Result<Address, ChainError>;

    async fn get_balance(&self, address: &Address) -> Result<Balance, ChainError>;

    async fn build_unsigned_tx(&self, intent: &TransferIntent) -> Result<UnsignedTx, ChainError>;

    fn attach_signature(
        &self,
        unsigned: &UnsignedTx,
        signature: &Signature,
    ) -> Result<SignedTx, ChainError>;

    async fn broadcast_signed_tx(&self, tx: &SignedTx) -> Result<TxId, ChainError>;

    async fn tx_status(&self, tx_id: &TxId) -> Result<TxStatus, ChainError>;
}
