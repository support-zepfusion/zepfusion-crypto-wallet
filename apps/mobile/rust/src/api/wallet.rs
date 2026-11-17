use std::sync::OnceLock;

use cofinex_chains::{EvmAdapter, EvmNetwork, StubAdapter, TronAdapter};
use cofinex_core::{
    tether_usdt_snapshot, unified_portfolio, Address, BalanceObservation, BalanceOutcome,
    ChainAdapter, ChainId, FungibleToken, PortfolioDeployment, TokenStandard, Wallet,
    WalletChainAddress,
};
use cofinex_signer::LocalSigner;
use serde::Serialize;
use tokio::runtime::Runtime;
use zeroize::Zeroize;

/// Result of creating a test wallet. The mnemonic is a secret.
///
/// `Debug` redacts the phrase. There is no `Drop` wipe: flutter_rust_bridge
/// moves the fields out, which a `Drop` impl would forbid. Callers must not
/// log the value. The local copy inside [`create_test_wallet`] is moved, not
/// cloned.
pub struct CreatedWallet {
    pub mnemonic: String,
    pub sepolia_address: String,
}

impl core::fmt::Debug for CreatedWallet {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("CreatedWallet")
            .field("mnemonic", &"[redacted]")
            .field("sepolia_address", &self.sepolia_address)
            .finish()
    }
}

pub struct ImportedWallet {
    pub sepolia_address: String,
}

pub struct BalanceView {
    pub symbol: String,
    pub base_units: String,
    pub display: String,
}

/// Create a 12-word English test wallet and its Sepolia address.
///
/// The phrase is returned so the UI can display it. Do not log the return value.
pub fn create_test_wallet() -> Result<CreatedWallet, String> {
    let (signer, phrase) = LocalSigner::generate(12).map_err(|error| error.to_string())?;
    let sepolia_address = address_of(signer)?;
    Ok(CreatedWallet {
        mnemonic: phrase,
        sepolia_address,
    })
}

/// Import an English BIP-39 phrase. The error text never includes the phrase.
pub fn import_test_wallet(mut mnemonic: String) -> Result<ImportedWallet, String> {
    let result = (|| {
        let signer = LocalSigner::from_mnemonic(&mnemonic, "")
            .map_err(|_| "invalid mnemonic".to_string())?;
        Ok(ImportedWallet {
            sepolia_address: address_of(signer)?,
        })
    })();
    mnemonic.zeroize();
    result
}

/// Native Sepolia ETH balance. `rpc_url` wins when it is non-empty; otherwise
/// the adapter reads `COFINEX_SEPOLIA_RPC_URL`.
///
/// This blocks on a private runtime. The Flutter shell is a test screen.
pub fn sepolia_balance(address: String, rpc_url: String) -> Result<BalanceView, String> {
    runtime().block_on(async move {
        let adapter = EvmAdapter::sepolia(Some(rpc_url)).map_err(|error| error.to_string())?;
        let balance = adapter
            .get_balance(&Address::new(ChainId::EthereumSepolia, address))
            .await
            .map_err(|error| error.to_string())?;
        Ok(BalanceView {
            symbol: balance.symbol,
            base_units: balance.base_units,
            display: balance.display,
        })
    })
}

/// Unified USDT balances for the wallet behind `mnemonic`.
///
/// The return value is JSON. Amounts are decimal strings. Solana is included
/// as unavailable: SPL balance reading is still a stub. This function only
/// reads balances. It does not sign, and it zeroizes `mnemonic` before returning.
pub fn unified_assets(mnemonic: String) -> Result<String, String> {
    runtime().block_on(unified_assets_inner(mnemonic))
}

async fn unified_assets_inner(mut mnemonic: String) -> Result<String, String> {
    let result = read_unified_assets(&mnemonic).await;
    mnemonic.zeroize();
    result
}

async fn read_unified_assets(mnemonic: &str) -> Result<String, String> {
    let signer =
        LocalSigner::from_mnemonic(mnemonic, "").map_err(|_| "invalid mnemonic".to_string())?;
    let wallet = Wallet::new(signer);
    let evm = EvmAdapter::sepolia(None).map_err(|error| error.to_string())?;
    let evm_address = wallet.address(&evm, 0).map_err(|error| error.to_string())?;
    let tron = TronAdapter::mainnet(None).map_err(|error| error.to_string())?;
    let tron_address = wallet
        .address(&tron, 0)
        .map_err(|error| error.to_string())?;

    let deployments = tether_usdt_snapshot();
    let mut addresses = Vec::new();
    let mut observations = Vec::new();
    for deployment in &deployments {
        let (address, outcome) =
            read_deployment(deployment, evm_address.text(), tron_address.text()).await?;
        if let Some(address) = address {
            addresses.push(WalletChainAddress {
                chain: deployment.chain,
                address,
            });
        }
        observations.push(BalanceObservation {
            chain: deployment.chain,
            contract: deployment.contract.clone(),
            outcome,
        });
    }
    let assets = unified_portfolio(&addresses, &deployments, &observations)
        .map_err(|error| error.to_string())?;
    let payload = PortfolioJson {
        assets: assets.into_iter().map(AssetJson::from).collect(),
    };
    serde_json::to_string(&payload).map_err(|_| "could not encode the portfolio".to_string())
}

async fn read_deployment(
    deployment: &PortfolioDeployment,
    evm_address: &str,
    tron_address: &str,
) -> Result<(Option<String>, BalanceOutcome), String> {
    let token = FungibleToken {
        symbol: deployment.symbol.clone(),
        decimals: deployment.decimals,
        standard: deployment.standard,
        contract: deployment
            .contract
            .clone()
            .ok_or_else(|| "USDT deployment has no contract".to_string())?,
    };
    match deployment.standard {
        TokenStandard::Erc20 => {
            let outcome = read_erc20(deployment.chain, evm_address, &token).await;
            Ok((Some(evm_address.to_string()), outcome))
        }
        TokenStandard::Trc20 => {
            let outcome = read_trc20(tron_address, &token).await;
            Ok((Some(tron_address.to_string()), outcome))
        }
        TokenStandard::Spl => {
            let stub = StubAdapter::new(deployment.chain);
            let outcome = match stub
                .fungible_balance(&Address::new(deployment.chain, "underived"), &token)
                .await
            {
                Ok(_) => BalanceOutcome::Unavailable(
                    "Solana SPL balance reading is not implemented".to_string(),
                ),
                Err(error) => BalanceOutcome::Unavailable(error.to_string()),
            };
            Ok((None, outcome))
        }
        TokenStandard::Native => Ok((
            None,
            BalanceOutcome::Unavailable(
                "native balances are not part of the USDT snapshot".to_string(),
            ),
        )),
    }
}

async fn read_erc20(chain: ChainId, holder: &str, token: &FungibleToken) -> BalanceOutcome {
    let Some(network) = evm_network(chain) else {
        return BalanceOutcome::Unavailable(format!(
            "{chain} is not an EVM network this shell reads"
        ));
    };
    let adapter = match EvmAdapter::for_network(network, None) {
        Ok(adapter) => adapter,
        Err(error) => return BalanceOutcome::Unavailable(error.to_string()),
    };
    match adapter
        .fungible_balance(&Address::new(chain, holder.to_string()), token)
        .await
    {
        Ok(balance) => BalanceOutcome::Amount(balance.base_units),
        Err(error) => BalanceOutcome::Unavailable(error.to_string()),
    }
}

async fn read_trc20(holder: &str, token: &FungibleToken) -> BalanceOutcome {
    let adapter = match TronAdapter::mainnet(None) {
        Ok(adapter) => adapter,
        Err(error) => return BalanceOutcome::Unavailable(error.to_string()),
    };
    match adapter
        .fungible_balance(&Address::new(ChainId::Tron, holder.to_string()), token)
        .await
    {
        Ok(balance) => BalanceOutcome::Amount(balance.base_units),
        Err(error) => BalanceOutcome::Unavailable(error.to_string()),
    }
}

fn evm_network(chain: ChainId) -> Option<EvmNetwork> {
    Some(match chain {
        ChainId::Ethereum => EvmNetwork::ETHEREUM,
        ChainId::EthereumSepolia => EvmNetwork::SEPOLIA,
        ChainId::Bsc => EvmNetwork::BSC,
        ChainId::BscTestnet => EvmNetwork::BSC_TESTNET,
        ChainId::Polygon => EvmNetwork::POLYGON,
        ChainId::PolygonAmoy => EvmNetwork::POLYGON_AMOY,
        _ => return None,
    })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PortfolioJson {
    assets: Vec<AssetJson>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AssetJson {
    asset_id: String,
    symbol: String,
    name: String,
    decimals: u8,
    total_base_units: Option<String>,
    display: Option<String>,
    complete: bool,
    chains: Vec<ChainJson>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ChainJson {
    chain_id: String,
    label: String,
    address: Option<String>,
    contract: Option<String>,
    decimals: u8,
    base_units: Option<String>,
    display: Option<String>,
    error: Option<String>,
}

impl From<cofinex_core::UnifiedAsset> for AssetJson {
    fn from(asset: cofinex_core::UnifiedAsset) -> Self {
        Self {
            asset_id: asset.asset_id,
            symbol: asset.symbol,
            name: asset.name,
            decimals: asset.decimals,
            total_base_units: asset.total_base_units,
            display: asset.display,
            complete: asset.complete,
            chains: asset.chains.into_iter().map(ChainJson::from).collect(),
        }
    }
}

impl From<cofinex_core::ChainBreakdown> for ChainJson {
    fn from(chain: cofinex_core::ChainBreakdown) -> Self {
        Self {
            chain_id: chain.chain.as_str().to_string(),
            label: chain.chain.label().to_string(),
            address: chain.address,
            contract: chain.contract,
            decimals: chain.decimals,
            base_units: chain.base_units,
            display: chain.display,
            error: chain.error,
        }
    }
}

fn address_of(signer: LocalSigner) -> Result<String, String> {
    let adapter = EvmAdapter::sepolia(None).map_err(|error| error.to_string())?;
    let wallet = Wallet::new(signer);
    let address = wallet
        .address(&adapter, 0)
        .map_err(|error| error.to_string())?;
    Ok(address.text().to_string())
}

fn runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| Runtime::new().expect("failed to start the async runtime"))
}

#[cfg(test)]
mod tests {
    use super::{create_test_wallet, import_test_wallet};

    const ABANDON: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    #[test]
    fn import_matches_the_bip44_vector_and_create_redacts_debug() {
        let imported = import_test_wallet(ABANDON.to_string()).unwrap();
        assert_eq!(
            imported.sepolia_address,
            "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        );
        let created = create_test_wallet().unwrap();
        assert_eq!(created.mnemonic.split_whitespace().count(), 12);
        assert!(created.sepolia_address.starts_with("0x"));
        assert_eq!(created.sepolia_address.len(), 42);
        let debug = format!("{created:?}");
        assert!(!debug.contains(&created.mnemonic));
        assert!(debug.contains("[redacted]"));
        assert!(import_test_wallet("not a real phrase".to_string()).is_err());
    }

    #[test]
    fn unified_assets_lists_cited_usdt_and_hides_the_phrase() {
        let json = super::unified_assets(ABANDON.to_string()).unwrap();
        assert!(!json.to_lowercase().contains("abandon"));
        assert!(json.contains("tether:usdt"));
        assert!(json.contains("0x9858EfFD232B4033E47d90003D41EC34EcaEda94"));
        assert!(json.contains("TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"));
        assert!(json.contains("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"));
        assert!(json.contains("does not implement fungible_balance"));
        let error = super::unified_assets("not a real phrase".to_string()).unwrap_err();
        assert_eq!(error, "invalid mnemonic");
        assert!(!error.contains("not a real"));
    }
}
