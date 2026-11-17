use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use cofinex_core::{
    Address, ChainAdapter, ChainError, ChainId, FungibleToken, TokenStandard, TransferIntent,
    Wallet, TRON_USDT,
};
use cofinex_keys::PublicKey;
use cofinex_signer::{LocalSigner, Signer};
use serde_json::{json, Value};

use super::adapter::TronAdapter;
use super::address::{account_bytes, parse_tron_address};
use super::rpc::TronRpc;

const ABANDON: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

struct Script {
    calls: Arc<Mutex<Vec<(String, Value)>>>,
}

#[async_trait]
impl TronRpc for Script {
    async fn post(&self, path: &str, body: Value) -> Result<Value, ChainError> {
        self.calls
            .lock()
            .expect("lock")
            .push((path.to_string(), body));
        match path {
            "/wallet/getaccount" => Ok(json!({ "balance": 2_000_000 })),
            "/wallet/triggerconstantcontract" => Ok(json!({
                "result": { "result": true },
                "constant_result": ["00000000000000000000000000000000000000000000000000000000000f4240"]
            })),
            other => panic!("unexpected path {other}"),
        }
    }
}

fn usdt() -> FungibleToken {
    FungibleToken {
        symbol: "USDT".to_string(),
        decimals: 6,
        standard: TokenStandard::Trc20,
        contract: TRON_USDT.to_string(),
    }
}

#[test]
fn derives_a_tron_base58_address_from_coin_type_195() {
    let adapter = TronAdapter::with_rpc(Script {
        calls: Arc::new(Mutex::new(Vec::new())),
    });
    let signer = LocalSigner::from_mnemonic(ABANDON, "").unwrap();
    let wallet = Wallet::new(signer);
    let address = wallet.address(&adapter, 0).unwrap();
    assert_eq!(address.chain(), ChainId::Tron);
    assert_eq!(
        adapter.derivation_path(0).unwrap().to_string(),
        "m/44'/195'/0'/0/0"
    );
    let payload = parse_tron_address(address.text()).unwrap();
    assert_eq!(payload[0], 0x41);
    assert!(address.text().starts_with('T'));
    assert_ne!(address.text(), "0x9858EfFD232B4033E47d90003D41EC34EcaEda94");

    let public_key: PublicKey = wallet
        .signer()
        .public_key(&adapter.derivation_path(0).unwrap())
        .unwrap();
    let again = adapter.derive_address(&public_key).unwrap();
    assert_eq!(again.text(), address.text());
}

#[tokio::test]
async fn reads_trx_and_trc20_balance_of_without_signing() {
    let calls = Arc::new(Mutex::new(Vec::new()));
    let adapter = TronAdapter::with_rpc(Script {
        calls: calls.clone(),
    });
    let holder = Address::new(ChainId::Tron, TRON_USDT);
    let native = adapter.get_balance(&holder).await.unwrap();
    assert_eq!(native.symbol, "TRX");
    assert_eq!(native.base_units, "2000000");
    assert_eq!(native.display, "2");
    assert_eq!(native.decimals, 6);

    let token = adapter.fungible_balance(&holder, &usdt()).await.unwrap();
    assert_eq!(token.symbol, "USDT");
    assert_eq!(token.base_units, "1000000");
    assert_eq!(token.display, "1");

    let account = account_bytes(&parse_tron_address(TRON_USDT).unwrap());
    let parameter = format!("{:0>64}", hex::encode(account));
    {
        let recorded = calls.lock().expect("lock");
        assert_eq!(recorded[0].0, "/wallet/getaccount");
        assert_eq!(recorded[1].0, "/wallet/triggerconstantcontract");
        assert_eq!(recorded[1].1["function_selector"], "balanceOf(address)");
        assert_eq!(recorded[1].1["parameter"], parameter);
        assert_eq!(recorded.len(), 2);
    }

    let error = adapter
        .build_unsigned_tx(&TransferIntent {
            from: holder.clone(),
            to: holder,
            amount_base_units: "1".to_string(),
            path: adapter.derivation_path(0).unwrap(),
        })
        .await
        .unwrap_err();
    assert!(matches!(
        error,
        ChainError::NotImplemented {
            chain: ChainId::Tron,
            operation: "build_unsigned_tx",
        }
    ));
    assert_eq!(calls.lock().expect("lock").len(), 2);
}

#[tokio::test]
#[ignore = "needs COFINEX_TRON_RPC_URL and network access"]
async fn live_tron_trx_and_usdt_balance() {
    let adapter = crate::TronAdapter::mainnet(None).unwrap();
    let wallet = Wallet::new(LocalSigner::from_mnemonic(ABANDON, "").unwrap());
    let address = wallet.address(&adapter, 0).unwrap();
    let native = adapter.get_balance(&address).await.unwrap();
    assert_eq!(native.symbol, "TRX");
    assert_eq!(native.decimals, 6);
    let token = adapter.fungible_balance(&address, &usdt()).await.unwrap();
    assert_eq!(token.symbol, "USDT");
    assert_eq!(token.decimals, 6);
    assert!(!token.base_units.is_empty());
}
