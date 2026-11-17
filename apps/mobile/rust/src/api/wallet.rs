use std::sync::OnceLock;

use cofinex_chains::EvmAdapter;
use cofinex_core::{Address, ChainAdapter, ChainId, Wallet};
use cofinex_signer::LocalSigner;
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
}
