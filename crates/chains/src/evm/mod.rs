mod adapter;
mod address;
mod rlp;
mod rpc;

#[cfg(test)]
mod tests;

pub use adapter::EvmAdapter;
pub use rpc::HttpRpc;

/// EIP-155 chain id for Ethereum Sepolia. Mainnet (1) is never accepted.
pub const SEPOLIA_CHAIN_ID: u64 = 11155111;
