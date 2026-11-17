use std::sync::Mutex;

use async_trait::async_trait;
use cofinex_core::{Address, ChainAdapter, ChainError, ChainId, TransferIntent, TxStatus, Wallet};
use cofinex_signer::{LocalSigner, MpcSigner};
use serde_json::{json, Value};

use super::adapter::{native_transfer_fee, EvmAdapter};
use super::rpc::EvmRpc;
use super::SEPOLIA_CHAIN_ID;

const ABANDON: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const VECTOR_ADDRESS: &str = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94";

struct Script {
    calls: Mutex<Vec<String>>,
    chain_id: &'static str,
}

#[async_trait]
impl EvmRpc for Script {
    async fn request(&self, method: &str, _params: Vec<Value>) -> Result<Value, ChainError> {
        self.calls.lock().expect("lock").push(method.to_string());
        if self.chain_id != "0xaa36a7" && method != "eth_chainId" {
            panic!("adapter called {method} before rejecting the network");
        }
        match method {
            "eth_chainId" => Ok(json!(self.chain_id)),
            "eth_getBalance" => Ok(json!("0xde0b6b3a7640000")),
            "eth_getTransactionCount" => Ok(json!("0x2")),
            "eth_maxPriorityFeePerGas" => Ok(json!("0x3b9aca00")),
            "eth_getBlockByNumber" => Ok(json!({ "baseFeePerGas": "0x3b9aca00" })),
            "eth_sendRawTransaction" => Ok(json!(
                "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            )),
            "eth_getTransactionReceipt" => Ok(json!(null)),
            "eth_getTransactionByHash" => Ok(json!(null)),
            other => panic!("unexpected method {other}"),
        }
    }
}

fn sepolia_script() -> EvmAdapter<Script> {
    EvmAdapter::with_rpc(Script {
        calls: Mutex::new(Vec::new()),
        chain_id: "0xaa36a7",
    })
}

#[test]
fn derives_the_bip44_sepolia_address_without_a_network() {
    let adapter = sepolia_script();
    let wallet = Wallet::new(LocalSigner::from_mnemonic(ABANDON, "").unwrap());
    let address = wallet.address(&adapter, 0).unwrap();
    assert_eq!(address.text(), VECTOR_ADDRESS);
    assert_eq!(address.chain(), ChainId::EthereumSepolia);

    let mpc = Wallet::new(MpcSigner::two_of_three());
    let error = mpc.address(&adapter, 0).unwrap_err();
    assert!(error.to_string().contains("does not implement public_key"));
}

#[tokio::test]
async fn balance_and_sign_stay_on_sepolia() {
    let adapter = sepolia_script();
    let address = Address::new(ChainId::EthereumSepolia, VECTOR_ADDRESS);
    let balance = adapter.get_balance(&address).await.unwrap();
    assert_eq!(balance.symbol, "ETH");
    assert_eq!(balance.base_units, "1000000000000000000");
    assert_eq!(balance.display, "1");

    let path = adapter.derivation_path(0).unwrap();
    let unsigned = adapter
        .build_unsigned_tx(&TransferIntent {
            from: address.clone(),
            to: address.clone(),
            amount_base_units: "1".to_string(),
            path,
        })
        .await
        .unwrap();
    let fee = native_transfer_fee(&unsigned).unwrap();
    assert_eq!(fee.gas_limit, 21_000);
    assert_eq!(fee.max_priority_fee_per_gas, 1_000_000_000);
    assert_eq!(fee.max_fee_per_gas, 3_000_000_000);
    assert_eq!(fee.max_fee_wei, 63_000_000_000_000);

    let wallet = Wallet::new(LocalSigner::from_mnemonic(ABANDON, "").unwrap());
    let signed = wallet
        .sign_transfer(&adapter, 0, VECTOR_ADDRESS, "1")
        .await
        .unwrap();
    assert_eq!(signed.raw[0], 0x02);
    assert_eq!(
        super::rlp::eip1559_chain_id(&signed.raw).unwrap(),
        SEPOLIA_CHAIN_ID
    );

    let tx_id = adapter.broadcast_signed_tx(&signed).await.unwrap();
    assert!(tx_id.as_str().starts_with("0xbbbb"));
    let status = adapter.tx_status(&tx_id).await.unwrap();
    assert_eq!(status, TxStatus::NotFound);
}

#[tokio::test]
async fn mainnet_chain_id_is_refused_before_any_other_call() {
    let adapter = EvmAdapter::with_rpc(Script {
        calls: Mutex::new(Vec::new()),
        chain_id: "0x1",
    });
    let address = Address::new(ChainId::EthereumSepolia, VECTOR_ADDRESS);
    let error = adapter.get_balance(&address).await.unwrap_err();
    match error {
        ChainError::WrongNetwork { expected, actual } => {
            assert_eq!(expected, SEPOLIA_CHAIN_ID);
            assert_eq!(actual, 1);
        }
        other => panic!("unexpected error {other}"),
    }
}

#[tokio::test]
async fn stubs_do_not_pretend_to_work() {
    for adapter in crate::stub_adapters() {
        let chain = adapter.chain_id();
        let error = adapter
            .get_balance(&Address::new(chain, "unused"))
            .await
            .unwrap_err();
        assert!(
            matches!(error, ChainError::NotImplemented { .. }),
            "{chain} returned {error}"
        );
        let path = adapter.derivation_path(0).unwrap();
        match chain {
            ChainId::Solana => assert_eq!(path.to_string(), "m/44'/501'/0'/0'"),
            ChainId::Sui => assert_eq!(path.to_string(), "m/44'/784'/0'/0'/0'"),
            ChainId::Bitcoin => assert_eq!(path.to_string(), "m/44'/0'/0'/0/0"),
            ChainId::Tron => assert_eq!(path.to_string(), "m/44'/195'/0'/0/0"),
            ChainId::EthereumSepolia => unreachable!(),
        }
    }
}

#[tokio::test]
#[ignore = "needs COFINEX_SEPOLIA_RPC_URL and network access"]
async fn live_sepolia_balance() {
    let adapter = crate::EvmAdapter::sepolia(None).unwrap();
    let address = Address::new(ChainId::EthereumSepolia, VECTOR_ADDRESS);
    let balance = adapter.get_balance(&address).await.unwrap();
    assert_eq!(balance.symbol, "ETH");
    assert!(!balance.display.is_empty());
}
