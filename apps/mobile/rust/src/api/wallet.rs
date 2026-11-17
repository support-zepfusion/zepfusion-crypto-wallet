use std::sync::OnceLock;

use cofinex_chains::{format_eip55, native_transfer_fee, parse_evm_address, EvmAdapter};
use cofinex_core::{format_base_units, Address, ChainAdapter, ChainId, TransferIntent, Wallet};
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

/// Worst-case network fee for a native Sepolia transfer. Amounts are decimal strings.
#[derive(Debug)]
pub struct FeeQuote {
    pub gas_limit: String,
    pub max_fee_per_gas_wei: String,
    pub max_priority_fee_per_gas_wei: String,
    pub max_fee_wei: String,
    pub max_fee_display: String,
}

#[derive(Debug)]
pub struct SendReceipt {
    pub tx_hash: String,
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
/// The Flutter shell does not pass an empty URL. It fills the field from
/// `--dart-define=COFINEX_SEPOLIA_RPC_URL`, then the desktop environment, then
/// `https://ethereum-sepolia-rpc.publicnode.com`. Android has no process
/// environment, so the define or the public endpoint is what arrives here.
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

/// Quote the max fee for a native Sepolia ETH transfer. Does not sign or broadcast.
///
/// `amount_eth` is a decimal string such as `0.01`. `0` is allowed so the UI
/// can ask for the fee before the user picks an amount. Only Sepolia is contacted.
pub fn quote_sepolia_transfer(
    from: String,
    to: String,
    amount_eth: String,
    rpc_url: String,
) -> Result<FeeQuote, String> {
    let from = normalize_evm_address(&from)?;
    let to = normalize_evm_address(&to)?;
    let wei = eth_to_wei(&amount_eth)?;
    runtime().block_on(async move {
        let adapter = EvmAdapter::sepolia(Some(rpc_url)).map_err(|error| error.to_string())?;
        let path = adapter
            .derivation_path(0)
            .map_err(|error| error.to_string())?;
        let unsigned = adapter
            .build_unsigned_tx(&TransferIntent {
                from: Address::new(ChainId::EthereumSepolia, from),
                to: Address::new(ChainId::EthereumSepolia, to),
                amount_base_units: wei,
                path,
            })
            .await
            .map_err(|error| error.to_string())?;
        let fee = native_transfer_fee(&unsigned).map_err(|error| error.to_string())?;
        let max_fee_wei = fee.max_fee_wei.to_string();
        let max_fee_display =
            format_base_units(&max_fee_wei, 18).ok_or_else(|| "amount is invalid".to_string())?;
        Ok(FeeQuote {
            gas_limit: fee.gas_limit.to_string(),
            max_fee_per_gas_wei: fee.max_fee_per_gas.to_string(),
            max_priority_fee_per_gas_wei: fee.max_priority_fee_per_gas.to_string(),
            max_fee_wei,
            max_fee_display,
        })
    })
}

/// Sign and broadcast a native Sepolia ETH transfer with [`LocalSigner`].
///
/// Mainnet is refused by the adapter, which checks `eth_chainId` and embeds
/// chain id 11155111 in the EIP-1559 payload. The mnemonic is wiped before
/// this function returns. Errors do not include the phrase.
pub fn send_sepolia_eth(
    mut mnemonic: String,
    to: String,
    amount_eth: String,
    rpc_url: String,
) -> Result<SendReceipt, String> {
    let result = send_inner(&mnemonic, &to, &amount_eth, rpc_url);
    mnemonic.zeroize();
    result
}

fn send_inner(
    mnemonic: &str,
    to: &str,
    amount_eth: &str,
    rpc_url: String,
) -> Result<SendReceipt, String> {
    let to = normalize_evm_address(to)?;
    let wei = eth_to_wei(amount_eth)?;
    if wei == "0" {
        return Err("amount is zero".to_string());
    }
    runtime().block_on(async move {
        let signer =
            LocalSigner::from_mnemonic(mnemonic, "").map_err(|_| "invalid mnemonic".to_string())?;
        let adapter = EvmAdapter::sepolia(Some(rpc_url)).map_err(|error| error.to_string())?;
        let wallet = Wallet::new(signer);
        let signed = wallet
            .sign_transfer(&adapter, 0, &to, &wei)
            .await
            .map_err(|error| error.to_string())?;
        let tx_id = wallet
            .broadcast(&adapter, &signed)
            .await
            .map_err(|error| error.to_string())?;
        Ok(SendReceipt {
            tx_hash: tx_id.as_str().to_string(),
        })
    })
}

fn normalize_evm_address(text: &str) -> Result<String, String> {
    let bytes = parse_evm_address(text.trim()).map_err(|_| "address is invalid".to_string())?;
    Ok(format_eip55(&bytes))
}

/// Convert a non-negative decimal ETH amount to a wei integer string.
fn eth_to_wei(amount: &str) -> Result<String, String> {
    let trimmed = amount.trim();
    if trimmed.is_empty() || trimmed.starts_with('+') || trimmed.starts_with('-') {
        return Err("amount is invalid".to_string());
    }
    let (whole, frac) = match trimmed.split_once('.') {
        Some((whole, frac)) => (whole, frac),
        None => (trimmed, ""),
    };
    if whole.is_empty() && frac.is_empty() {
        return Err("amount is invalid".to_string());
    }
    if frac.len() > 18 {
        return Err("amount has more than 18 decimal places".to_string());
    }
    let whole = if whole.is_empty() { "0" } else { whole };
    if !whole.bytes().all(|byte| byte.is_ascii_digit())
        || !frac.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err("amount is invalid".to_string());
    }
    let mut combined = String::with_capacity(whole.len() + 18);
    combined.push_str(whole);
    combined.push_str(frac);
    combined.extend(std::iter::repeat_n('0', 18 - frac.len()));
    let digits = combined.trim_start_matches('0');
    if digits.is_empty() {
        return Ok("0".to_string());
    }
    if digits.len() > 39 || digits.parse::<u128>().is_err() {
        return Err("amount is too large".to_string());
    }
    Ok(digits.to_string())
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
    fn eth_amounts_and_send_validation_do_not_leak_the_phrase() {
        assert_eq!(super::eth_to_wei("1.5").unwrap(), "1500000000000000000");
        assert_eq!(super::eth_to_wei("0").unwrap(), "0");
        assert_eq!(super::eth_to_wei(".001").unwrap(), "1000000000000000");
        assert!(super::eth_to_wei("1.0000000000000000001").is_err());
        assert!(super::eth_to_wei("-1").is_err());
        assert!(super::eth_to_wei("1e2").is_err());

        let error = super::send_sepolia_eth(
            ABANDON.to_string(),
            "not-an-address".to_string(),
            "0.1".to_string(),
            "http://127.0.0.1:9".to_string(),
        )
        .unwrap_err();
        assert_eq!(error, "address is invalid");
        assert!(!error.contains("abandon"));

        let error = super::send_sepolia_eth(
            ABANDON.to_string(),
            "0x9858EfFD232B4033E47d90003D41EC34EcaEda94".to_string(),
            "0".to_string(),
            "http://127.0.0.1:9".to_string(),
        )
        .unwrap_err();
        assert_eq!(error, "amount is zero");
    }
}
