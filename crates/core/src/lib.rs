//! Wallet core.
//!
//! [`ChainAdapter`] is the only thing a chain implementation has to provide.
//! [`Wallet`] asks a [`Signer`](cofinex_signer::Signer) for a signature and
//! hands the signature back to the adapter. Adapters never import a signer.

#![forbid(unsafe_code)]

mod amount;
mod portfolio;
mod usdt;
mod wallet;

pub use amount::{
    add_base_units, format_base_units, hex_quantity_to_dec, parse_base_units, scale_base_units,
};
pub use portfolio::{
    unified_portfolio, BalanceObservation, BalanceOutcome, ChainBreakdown, PortfolioDeployment,
    UnifiedAsset, WalletChainAddress,
};
pub use usdt::{tether_usdt_snapshot, ETHEREUM_USDT, SOLANA_USDT, TRON_USDT};
pub use wallet::Wallet;

use async_trait::async_trait;
use cofinex_signer::SignerError;
use thiserror::Error;

pub use cofinex_keys::{Curve, DerivationPath, PublicKey, Signature};

/// Networks the wallet core knows about.
///
/// EVM networks other than Sepolia are for balance reads. The signer still
/// builds transactions only for Sepolia.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ChainId {
    Bitcoin,
    Ethereum,
    EthereumSepolia,
    Bsc,
    BscTestnet,
    Polygon,
    PolygonAmoy,
    Tron,
    Solana,
    Sui,
}

impl ChainId {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bitcoin => "bitcoin",
            Self::Ethereum => "ethereum",
            Self::EthereumSepolia => "ethereum-sepolia",
            Self::Bsc => "bsc",
            Self::BscTestnet => "bsc-testnet",
            Self::Polygon => "polygon",
            Self::PolygonAmoy => "polygon-amoy",
            Self::Tron => "tron",
            Self::Solana => "solana",
            Self::Sui => "sui",
        }
    }

    /// Short name for a balance row.
    pub fn label(self) -> &'static str {
        match self {
            Self::Bitcoin => "Bitcoin",
            Self::Ethereum => "Ethereum",
            Self::EthereumSepolia => "Ethereum Sepolia",
            Self::Bsc => "BNB Smart Chain",
            Self::BscTestnet => "BNB Smart Chain Testnet",
            Self::Polygon => "Polygon",
            Self::PolygonAmoy => "Polygon Amoy",
            Self::Tron => "TRON",
            Self::Solana => "Solana",
            Self::Sui => "Sui",
        }
    }

    pub fn is_evm(self) -> bool {
        matches!(
            self,
            Self::Ethereum
                | Self::EthereumSepolia
                | Self::Bsc
                | Self::BscTestnet
                | Self::Polygon
                | Self::PolygonAmoy
        )
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

/// A balance in base units (wei, sun, token base units). No floating point.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Balance {
    pub symbol: String,
    pub base_units: String,
    pub decimals: u8,
    pub display: String,
}

/// How a fungible balance is queried. Native balances use [`ChainAdapter::get_balance`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TokenStandard {
    Native,
    Erc20,
    Trc20,
    Spl,
}

/// A fungible token deployment the adapter can read. `contract` is the
/// chain's display form (EIP-55, TRON base58, or Solana mint).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FungibleToken {
    pub symbol: String,
    pub decimals: u8,
    pub standard: TokenStandard,
    pub contract: String,
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
    /// The registry view drops testnets. Callers must not add them back.
    #[error("a testnet deployment cannot be included in a unified balance")]
    TestnetInUnifiedBalance,
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

    /// Fungible-token balance. The default is "not implemented" so a stub
    /// adapter keeps compiling. Native assets stay on [`Self::get_balance`].
    async fn fungible_balance(
        &self,
        holder: &Address,
        token: &FungibleToken,
    ) -> Result<Balance, ChainError> {
        let _ = (holder, token);
        Err(ChainError::not_implemented(
            self.chain_id(),
            "fungible_balance",
        ))
    }

    async fn build_unsigned_tx(&self, intent: &TransferIntent) -> Result<UnsignedTx, ChainError>;

    fn attach_signature(
        &self,
        unsigned: &UnsignedTx,
        signature: &Signature,
    ) -> Result<SignedTx, ChainError>;

    async fn broadcast_signed_tx(&self, tx: &SignedTx) -> Result<TxId, ChainError>;

    async fn tx_status(&self, tx_id: &TxId) -> Result<TxStatus, ChainError>;
}
