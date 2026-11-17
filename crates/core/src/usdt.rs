//! In-app snapshot of Tether USD deployments.
//!
//! This matches `services/registry/migrations/0003_usdt.sql`. Addresses are
//! copied from Tether's supported-protocols page (retrieved 2026-11-17,
//! https://tether.to/supported-protocols/) and checked against the chain.
//! BSC Binance-Peg USDT and Polygon USDT0 are intentionally absent: Tether's
//! page does not publish a USD₮ contract for either chain.

use crate::{ChainId, PortfolioDeployment, TokenStandard};

pub const ETHEREUM_USDT: &str = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
pub const TRON_USDT: &str = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
pub const SOLANA_USDT: &str = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB";

/// Mainnet USD₮ rows that belong in one unified balance.
///
/// Ethereum: https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7
/// (decimals() == 6 on chain id 1).
/// TRON: https://tronscan.org/#/token20/TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
/// (decimals() == 6, Tronscan precision 6).
/// Solana: https://explorer.solana.com/address/Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB
/// (mint decimals 6 via Solana RPC). SPL balance reading is still a stub.
pub fn tether_usdt_snapshot() -> Vec<PortfolioDeployment> {
    vec![
        deployment(ChainId::Ethereum, TokenStandard::Erc20, ETHEREUM_USDT, 6),
        deployment(ChainId::Tron, TokenStandard::Trc20, TRON_USDT, 6),
        deployment(ChainId::Solana, TokenStandard::Spl, SOLANA_USDT, 6),
    ]
}

fn deployment(
    chain: ChainId,
    standard: TokenStandard,
    contract: &str,
    decimals: u8,
) -> PortfolioDeployment {
    PortfolioDeployment {
        asset_id: "tether:usdt".to_string(),
        symbol: "USDT".to_string(),
        name: "Tether USD".to_string(),
        chain,
        is_testnet: false,
        decimals,
        standard,
        contract: Some(contract.to_string()),
        include_in_unified_balance: true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_matches_the_cited_mainnet_contracts() {
        let rows = tether_usdt_snapshot();
        assert_eq!(rows.len(), 3);
        assert!(rows.iter().all(|row| {
            row.asset_id == "tether:usdt"
                && row.include_in_unified_balance
                && !row.is_testnet
                && row.decimals == 6
        }));
        assert_eq!(rows[0].contract.as_deref(), Some(ETHEREUM_USDT));
        assert_eq!(rows[1].contract.as_deref(), Some(TRON_USDT));
        assert_eq!(rows[2].contract.as_deref(), Some(SOLANA_USDT));
        assert!(rows
            .iter()
            .all(|row| row.chain != ChainId::Bsc && row.chain != ChainId::Polygon));
    }
}
