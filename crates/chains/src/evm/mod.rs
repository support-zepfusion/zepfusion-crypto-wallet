mod adapter;
mod address;
mod rlp;
mod rpc;

#[cfg(test)]
mod tests;

pub use adapter::{native_transfer_fee, EvmAdapter, NativeFee};
pub use address::{format_eip55, parse_evm_address};
pub use rpc::HttpRpc;

/// EIP-155 chain id for Ethereum Sepolia. Mainnet (1) is never accepted.
pub const SEPOLIA_CHAIN_ID: u64 = 11155111;
