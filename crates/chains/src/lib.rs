//! Blockchain adapters.
//!
//! The EVM adapter reads native and ERC-20 balances for Ethereum, BNB Smart
//! Chain, Polygon, and their testnets. It checks `eth_chainId` against the
//! configured network. Signing and broadcast stay on Sepolia (chain id
//! 11155111): a signed transaction embeds that chain id, and other networks
//! return "not implemented" for every signing method.
//!
//! TRON reads native TRX and TRC-20 `balanceOf` over a TronGrid-compatible
//! HTTP API. It does not sign. Solana SPL balances are still a stub.

#![forbid(unsafe_code)]

mod evm;
mod stub;
mod tron;

pub use evm::{EvmAdapter, EvmNetwork, HttpRpc, SEPOLIA_CHAIN_ID};
pub use stub::StubAdapter;
pub use tron::{HttpTronRpc, TronAdapter};

use cofinex_core::ChainId;

/// Adapters for the non-EVM families in the product vision.
///
/// Every network operation on these returns "not implemented". Derivation
/// paths are still reported so the signer interface can be wired without
/// pretending a balance or a broadcast exists.
pub fn stub_adapters() -> Vec<StubAdapter> {
    vec![
        StubAdapter::new(ChainId::Bitcoin),
        StubAdapter::new(ChainId::Solana),
        StubAdapter::new(ChainId::Sui),
    ]
}
