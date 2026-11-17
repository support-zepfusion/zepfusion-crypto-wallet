//! Blockchain adapters.
//!
//! The Sepolia adapter speaks JSON-RPC and refuses any `eth_chainId` other
//! than 11155111. Signed transactions also embed that chain id, so a mainnet
//! node will not accept them. Bitcoin, TRON, Solana, and Sui compile and
//! return [`ChainError::NotImplemented`](cofinex_core::ChainError::NotImplemented).

#![forbid(unsafe_code)]

mod evm;
mod stub;

pub use evm::{
    format_eip55, native_transfer_fee, parse_evm_address, EvmAdapter, HttpRpc, NativeFee,
    SEPOLIA_CHAIN_ID,
};
pub use stub::StubAdapter;

use cofinex_core::ChainId;

/// Adapters for the non-EVM families in the product vision.
///
/// Every network operation on these returns "not implemented". Derivation
/// paths are still reported so the signer interface can be wired without
/// pretending a balance or a broadcast exists.
pub fn stub_adapters() -> Vec<StubAdapter> {
    vec![
        StubAdapter::new(ChainId::Bitcoin),
        StubAdapter::new(ChainId::Tron),
        StubAdapter::new(ChainId::Solana),
        StubAdapter::new(ChainId::Sui),
    ]
}
