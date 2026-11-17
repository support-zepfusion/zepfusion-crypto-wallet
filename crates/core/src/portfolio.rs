//! Unified balances for one canonical asset on several chains.
//!
//! Amounts stay decimal strings. A chain that uses more decimal places is
//! scaled up before it is added. Testnet deployments are refused when a caller
//! marks them for the unified total; the registry view has the same rule.

use crate::{
    add_base_units, format_base_units, scale_base_units, ChainError, ChainId, CoreError,
    TokenStandard,
};

/// One deployment from the token registry, plus the chain's testnet flag.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PortfolioDeployment {
    pub asset_id: String,
    pub symbol: String,
    pub name: String,
    pub chain: ChainId,
    pub is_testnet: bool,
    pub decimals: u8,
    pub standard: TokenStandard,
    pub contract: Option<String>,
    /// Mainnet rows the registry view would include. A testnet row must not set this.
    pub include_in_unified_balance: bool,
}

/// Address the wallet controls on one chain.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WalletChainAddress {
    pub chain: ChainId,
    pub address: String,
}

/// Result of one balance read. `contract` is `None` for the native asset.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BalanceObservation {
    pub chain: ChainId,
    pub contract: Option<String>,
    pub outcome: BalanceOutcome,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BalanceOutcome {
    /// Base units in the deployment's own decimals.
    Amount(String),
    Unavailable(String),
}

/// One chain inside a unified asset.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChainBreakdown {
    pub chain: ChainId,
    pub address: Option<String>,
    pub contract: Option<String>,
    pub decimals: u8,
    pub base_units: Option<String>,
    pub display: Option<String>,
    pub error: Option<String>,
}

/// One canonical asset. `decimals` is the widest deployment included in the total.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UnifiedAsset {
    pub asset_id: String,
    pub symbol: String,
    pub name: String,
    pub decimals: u8,
    /// `None` when every included chain failed. A partial sum is still returned
    /// when `complete` is false and at least one chain succeeded.
    pub total_base_units: Option<String>,
    pub display: Option<String>,
    pub complete: bool,
    pub chains: Vec<ChainBreakdown>,
}

/// Sum registry deployments into per-asset totals.
///
/// Only rows with `include_in_unified_balance` are included. A testnet row
/// with that flag set is an error. Rows without the flag are ignored, which
/// is how testnet USDC stays out of mainnet USDC.
pub fn unified_portfolio(
    addresses: &[WalletChainAddress],
    deployments: &[PortfolioDeployment],
    observations: &[BalanceObservation],
) -> Result<Vec<UnifiedAsset>, CoreError> {
    if deployments
        .iter()
        .any(|deployment| deployment.include_in_unified_balance && deployment.is_testnet)
    {
        return Err(CoreError::TestnetInUnifiedBalance);
    }

    let mut order: Vec<String> = Vec::new();
    let mut groups: Vec<Vec<usize>> = Vec::new();
    for (index, deployment) in deployments.iter().enumerate() {
        if !deployment.include_in_unified_balance {
            continue;
        }
        if let Some(position) = order.iter().position(|id| id == &deployment.asset_id) {
            groups[position].push(index);
        } else {
            order.push(deployment.asset_id.clone());
            groups.push(vec![index]);
        }
    }

    groups
        .iter()
        .map(|indexes| unify_group(addresses, deployments, observations, indexes))
        .collect()
}

fn unify_group(
    addresses: &[WalletChainAddress],
    deployments: &[PortfolioDeployment],
    observations: &[BalanceObservation],
    indexes: &[usize],
) -> Result<UnifiedAsset, CoreError> {
    let first = &deployments[indexes[0]];
    let decimals = indexes
        .iter()
        .map(|index| deployments[*index].decimals)
        .max()
        .unwrap_or(0);
    let mut ordered = indexes.to_vec();
    ordered.sort_by(|left, right| {
        deployments[*left]
            .chain
            .as_str()
            .cmp(deployments[*right].chain.as_str())
    });

    let mut chains = Vec::with_capacity(ordered.len());
    let mut total: Option<String> = None;
    let mut complete = true;
    for index in ordered {
        let deployment = &deployments[index];
        let address = addresses
            .iter()
            .find(|item| item.chain == deployment.chain)
            .map(|item| item.address.clone());
        let observation = find_observation(deployment, observations);
        let (base_units, display, error) = match observation.map(|item| &item.outcome) {
            Some(BalanceOutcome::Unavailable(message)) => {
                complete = false;
                (None, None, Some(message.clone()))
            }
            Some(BalanceOutcome::Amount(amount)) if address.is_none() => {
                complete = false;
                (None, None, Some("no address for this chain".to_string()))
            }
            Some(BalanceOutcome::Amount(amount)) => {
                let normalized = scale_base_units(amount, deployment.decimals, deployment.decimals)
                    .ok_or(ChainError::InvalidAmount)?;
                let scaled = scale_base_units(amount, deployment.decimals, decimals)
                    .ok_or(ChainError::InvalidAmount)?;
                let rendered = format_base_units(&normalized, deployment.decimals)
                    .ok_or(ChainError::InvalidAmount)?;
                total = Some(match &total {
                    None => scaled,
                    Some(current) => {
                        add_base_units(current, &scaled).ok_or(ChainError::InvalidAmount)?
                    }
                });
                (Some(normalized), Some(rendered), None)
            }
            None => {
                complete = false;
                let message = if address.is_none() {
                    "no address for this chain"
                } else {
                    "balance was not read"
                };
                (None, None, Some(message.to_string()))
            }
        };
        chains.push(ChainBreakdown {
            chain: deployment.chain,
            address,
            contract: deployment.contract.clone(),
            decimals: deployment.decimals,
            base_units,
            display,
            error,
        });
    }

    let display = match &total {
        Some(units) => Some(format_base_units(units, decimals).ok_or(ChainError::InvalidAmount)?),
        None => None,
    };
    Ok(UnifiedAsset {
        asset_id: first.asset_id.clone(),
        symbol: first.symbol.clone(),
        name: first.name.clone(),
        decimals,
        total_base_units: total,
        display,
        complete,
        chains,
    })
}

fn find_observation<'a>(
    deployment: &PortfolioDeployment,
    observations: &'a [BalanceObservation],
) -> Option<&'a BalanceObservation> {
    observations.iter().find(|observation| {
        if observation.chain != deployment.chain {
            return false;
        }
        match (&deployment.contract, &observation.contract) {
            (None, None) => deployment.standard == TokenStandard::Native,
            (Some(expected), Some(actual)) => contracts_match(deployment.chain, expected, actual),
            _ => false,
        }
    })
}

fn contracts_match(chain: ChainId, expected: &str, actual: &str) -> bool {
    if chain.is_evm() {
        expected.eq_ignore_ascii_case(actual)
    } else {
        expected == actual
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn deployment(
        chain: ChainId,
        decimals: u8,
        contract: &str,
        include: bool,
        testnet: bool,
    ) -> PortfolioDeployment {
        PortfolioDeployment {
            asset_id: "tether:usdt".to_string(),
            symbol: "USDT".to_string(),
            name: "Tether USD".to_string(),
            chain,
            is_testnet: testnet,
            decimals,
            standard: if chain == ChainId::Tron {
                TokenStandard::Trc20
            } else if chain == ChainId::Solana {
                TokenStandard::Spl
            } else {
                TokenStandard::Erc20
            },
            contract: Some(contract.to_string()),
            include_in_unified_balance: include,
        }
    }

    #[test]
    fn sums_six_and_eighteen_decimal_usdt_without_floats() {
        let deployments = vec![
            deployment(
                ChainId::Ethereum,
                6,
                "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                true,
                false,
            ),
            deployment(
                ChainId::Bsc,
                18,
                "0x1111111111111111111111111111111111111111",
                true,
                false,
            ),
        ];
        let addresses = vec![
            WalletChainAddress {
                chain: ChainId::Ethereum,
                address: "0xabc".to_string(),
            },
            WalletChainAddress {
                chain: ChainId::Bsc,
                address: "0xabc".to_string(),
            },
        ];
        let observations = vec![
            BalanceObservation {
                chain: ChainId::Ethereum,
                contract: Some("0xdac17f958d2ee523a2206206994597c13d831ec7".to_string()),
                outcome: BalanceOutcome::Amount("1500000".to_string()),
            },
            BalanceObservation {
                chain: ChainId::Bsc,
                contract: Some("0x1111111111111111111111111111111111111111".to_string()),
                outcome: BalanceOutcome::Amount("2000000000000000000".to_string()),
            },
        ];
        let assets = unified_portfolio(&addresses, &deployments, &observations).unwrap();
        assert_eq!(assets.len(), 1);
        let usdt = &assets[0];
        assert!(usdt.complete);
        assert_eq!(usdt.decimals, 18);
        assert_eq!(
            usdt.total_base_units.as_deref(),
            Some("3500000000000000000")
        );
        assert_eq!(usdt.display.as_deref(), Some("3.5"));
        assert_eq!(usdt.chains[0].chain, ChainId::Bsc);
        assert_eq!(usdt.chains[0].display.as_deref(), Some("2"));
        assert_eq!(usdt.chains[1].chain, ChainId::Ethereum);
        assert_eq!(usdt.chains[1].base_units.as_deref(), Some("1500000"));
        assert_eq!(usdt.chains[1].display.as_deref(), Some("1.5"));
    }

    #[test]
    fn same_decimals_sum_and_a_failed_chain_stays_partial() {
        let deployments = vec![
            deployment(
                ChainId::Ethereum,
                6,
                "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                true,
                false,
            ),
            deployment(
                ChainId::Tron,
                6,
                "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
                true,
                false,
            ),
        ];
        let addresses = vec![WalletChainAddress {
            chain: ChainId::Ethereum,
            address: "0xabc".to_string(),
        }];
        let observations = vec![
            BalanceObservation {
                chain: ChainId::Ethereum,
                contract: Some("0xdAC17F958D2ee523a2206206994597C13D831ec7".to_string()),
                outcome: BalanceOutcome::Amount("1500000".to_string()),
            },
            BalanceObservation {
                chain: ChainId::Tron,
                contract: Some("TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t".to_string()),
                outcome: BalanceOutcome::Unavailable(
                    "Solana SPL balance reading is not implemented".to_string(),
                ),
            },
        ];
        let usdt = &unified_portfolio(&addresses, &deployments, &observations).unwrap()[0];
        assert!(!usdt.complete);
        assert_eq!(usdt.total_base_units.as_deref(), Some("1500000"));
        assert_eq!(usdt.display.as_deref(), Some("1.5"));
        let tron = usdt
            .chains
            .iter()
            .find(|chain| chain.chain == ChainId::Tron)
            .unwrap();
        assert!(tron.error.as_ref().unwrap().contains("not implemented"));
        assert!(tron.base_units.is_none());
    }

    #[test]
    fn testnet_rows_are_ignored_unless_someone_marks_them_unified() {
        let mut testnet = deployment(
            ChainId::EthereumSepolia,
            6,
            "0x0000000000000000000000000000000000000001",
            false,
            true,
        );
        testnet.asset_id = "tether:usdt-testnet".to_string();
        let mainnet = deployment(
            ChainId::Ethereum,
            6,
            "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            true,
            false,
        );
        let addresses = vec![WalletChainAddress {
            chain: ChainId::Ethereum,
            address: "0xabc".to_string(),
        }];
        let observations = vec![BalanceObservation {
            chain: ChainId::Ethereum,
            contract: Some("0xdAC17F958D2ee523a2206206994597C13D831ec7".to_string()),
            outcome: BalanceOutcome::Amount("0".to_string()),
        }];
        let assets = unified_portfolio(
            &addresses,
            &[mainnet.clone(), testnet.clone()],
            &observations,
        )
        .unwrap();
        assert_eq!(assets.len(), 1);
        assert_eq!(assets[0].asset_id, "tether:usdt");
        assert_eq!(assets[0].chains.len(), 1);
        assert!(assets[0].complete);
        assert_eq!(assets[0].display.as_deref(), Some("0"));

        testnet.include_in_unified_balance = true;
        let error = unified_portfolio(&addresses, &[mainnet, testnet], &observations).unwrap_err();
        assert!(matches!(error, CoreError::TestnetInUnifiedBalance));
    }
}
