use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use cofinex_core::{
    unified_portfolio, Address, BalanceObservation, BalanceOutcome, ChainAdapter, ChainError,
    ChainId, FungibleToken, PortfolioDeployment, TokenStandard, TransferIntent, TxStatus, Wallet,
    WalletChainAddress, ETHEREUM_USDT,
};
use cofinex_signer::{LocalSigner, MpcSigner};
use serde_json::{json, Value};

use super::adapter::{erc20_balance_of_data, EvmAdapter};
use super::network::EvmNetwork;
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
            ChainId::Tron
            | ChainId::Ethereum
            | ChainId::EthereumSepolia
            | ChainId::Bsc
            | ChainId::BscTestnet
            | ChainId::Polygon
            | ChainId::PolygonAmoy => panic!("{chain} is not a stub"),
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

type RecordedCalls = Arc<Mutex<Vec<(String, Vec<Value>)>>>;

struct TokenScript {
    chain_id: &'static str,
    balance_hex: &'static str,
    calls: RecordedCalls,
}

#[async_trait]
impl EvmRpc for TokenScript {
    async fn request(&self, method: &str, params: Vec<Value>) -> Result<Value, ChainError> {
        self.calls
            .lock()
            .expect("lock")
            .push((method.to_string(), params));
        match method {
            "eth_chainId" => Ok(json!(self.chain_id)),
            "eth_call" => Ok(json!(self.balance_hex)),
            "eth_getBalance" => Ok(json!("0x0")),
            other => panic!("unexpected method {other}"),
        }
    }
}

fn usdt_token() -> FungibleToken {
    FungibleToken {
        symbol: "USDT".to_string(),
        decimals: 6,
        standard: TokenStandard::Erc20,
        contract: ETHEREUM_USDT.to_string(),
    }
}

#[test]
fn balance_of_selector_is_the_erc20_word() {
    let holder = [0x11u8; 20];
    let data = erc20_balance_of_data(&holder);
    assert!(data.starts_with("0x70a08231"));
    assert_eq!(data.len(), 2 + 8 + 64);
}

#[tokio::test]
async fn erc20_balance_of_uses_eth_call_and_refuses_signing() {
    let calls = Arc::new(Mutex::new(Vec::new()));
    let adapter = EvmAdapter::with_network(
        EvmNetwork::ETHEREUM,
        TokenScript {
            chain_id: "0x1",
            balance_hex: "0x16e360",
            calls: calls.clone(),
        },
    );
    let holder = Address::new(ChainId::Ethereum, VECTOR_ADDRESS);
    let balance = adapter
        .fungible_balance(&holder, &usdt_token())
        .await
        .unwrap();
    assert_eq!(balance.symbol, "USDT");
    assert_eq!(balance.base_units, "1500000");
    assert_eq!(balance.display, "1.5");
    assert_eq!(balance.decimals, 6);

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
            operation: "build_unsigned_tx",
            ..
        }
    ));
    let recorded = calls.lock().expect("lock");
    let methods: Vec<_> = recorded.iter().map(|(method, _)| method.as_str()).collect();
    assert_eq!(methods, ["eth_chainId", "eth_call", "eth_chainId"]);
    let data = recorded[1].1[0]["data"].as_str().unwrap();
    assert!(data.starts_with("0x70a08231"));
    assert!(data
        .to_ascii_lowercase()
        .contains("9858effd232b4033e47d90003d41ec34ecaeda94"));
}

#[tokio::test]
async fn mocked_erc20_balances_keep_their_decimals_in_the_total() {
    let ethereum = EvmAdapter::with_network(
        EvmNetwork::ETHEREUM,
        TokenScript {
            chain_id: "0x1",
            balance_hex: "0x16e360",
            calls: Arc::new(Mutex::new(Vec::new())),
        },
    );
    let bsc = EvmAdapter::with_network(
        EvmNetwork::BSC,
        TokenScript {
            chain_id: "0x38",
            balance_hex: "0x1bc16d674ec80000",
            calls: Arc::new(Mutex::new(Vec::new())),
        },
    );
    let holder_eth = Address::new(ChainId::Ethereum, VECTOR_ADDRESS);
    let holder_bsc = Address::new(ChainId::Bsc, VECTOR_ADDRESS);
    let eth_balance = ethereum
        .fungible_balance(&holder_eth, &usdt_token())
        .await
        .unwrap();
    let bsc_token = FungibleToken {
        symbol: "USDT".to_string(),
        decimals: 18,
        standard: TokenStandard::Erc20,
        contract: "0x1111111111111111111111111111111111111111".to_string(),
    };
    let bsc_balance = bsc.fungible_balance(&holder_bsc, &bsc_token).await.unwrap();
    assert_eq!(bsc_balance.display, "2");

    let deployments = vec![
        PortfolioDeployment {
            asset_id: "tether:usdt".to_string(),
            symbol: "USDT".to_string(),
            name: "Tether USD".to_string(),
            chain: ChainId::Ethereum,
            is_testnet: false,
            decimals: 6,
            standard: TokenStandard::Erc20,
            contract: Some(ETHEREUM_USDT.to_string()),
            include_in_unified_balance: true,
        },
        PortfolioDeployment {
            asset_id: "tether:usdt".to_string(),
            symbol: "USDT".to_string(),
            name: "Tether USD".to_string(),
            chain: ChainId::Bsc,
            is_testnet: false,
            decimals: 18,
            standard: TokenStandard::Erc20,
            contract: Some(bsc_token.contract.clone()),
            include_in_unified_balance: true,
        },
    ];
    let assets = unified_portfolio(
        &[
            WalletChainAddress {
                chain: ChainId::Ethereum,
                address: VECTOR_ADDRESS.to_string(),
            },
            WalletChainAddress {
                chain: ChainId::Bsc,
                address: VECTOR_ADDRESS.to_string(),
            },
        ],
        &deployments,
        &[
            BalanceObservation {
                chain: ChainId::Ethereum,
                contract: Some(ETHEREUM_USDT.to_string()),
                outcome: BalanceOutcome::Amount(eth_balance.base_units),
            },
            BalanceObservation {
                chain: ChainId::Bsc,
                contract: Some(bsc_token.contract),
                outcome: BalanceOutcome::Amount(bsc_balance.base_units),
            },
        ],
    )
    .unwrap();
    assert_eq!(assets[0].display.as_deref(), Some("3.5"));
    assert_eq!(assets[0].decimals, 18);
    assert!(assets[0].complete);
}

#[tokio::test]
#[ignore = "needs COFINEX_ETHEREUM_RPC_URL and network access"]
async fn live_ethereum_usdt_balance() {
    live_native(EvmNetwork::ETHEREUM).await;
    let adapter = EvmAdapter::for_network(EvmNetwork::ETHEREUM, None).unwrap();
    let balance = adapter
        .fungible_balance(
            &Address::new(ChainId::Ethereum, VECTOR_ADDRESS),
            &usdt_token(),
        )
        .await
        .unwrap();
    assert_eq!(balance.symbol, "USDT");
    assert_eq!(balance.decimals, 6);
    assert!(!balance.display.is_empty());
}

#[tokio::test]
#[ignore = "needs COFINEX_BSC_RPC_URL and network access"]
async fn live_bsc_native_balance() {
    live_native(EvmNetwork::BSC).await;
}

#[tokio::test]
#[ignore = "needs COFINEX_BSC_TESTNET_RPC_URL and network access"]
async fn live_bsc_testnet_native_balance() {
    live_native(EvmNetwork::BSC_TESTNET).await;
}

#[tokio::test]
#[ignore = "needs COFINEX_POLYGON_RPC_URL and network access"]
async fn live_polygon_native_balance() {
    live_native(EvmNetwork::POLYGON).await;
}

#[tokio::test]
#[ignore = "needs COFINEX_POLYGON_AMOY_RPC_URL and network access"]
async fn live_polygon_amoy_native_balance() {
    live_native(EvmNetwork::POLYGON_AMOY).await;
}

async fn live_native(network: EvmNetwork) {
    let adapter = EvmAdapter::for_network(network, None).unwrap();
    let balance = adapter
        .get_balance(&Address::new(network.chain, VECTOR_ADDRESS))
        .await
        .unwrap();
    assert_eq!(balance.symbol, network.native_symbol);
    assert_eq!(balance.decimals, network.native_decimals);
    assert!(!balance.base_units.is_empty());
}
