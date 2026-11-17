use cofinex_core::ChainId;

/// EIP-155 chain id for Ethereum Sepolia. Signing is allowed only for this id.
pub const SEPOLIA_CHAIN_ID: u64 = 11155111;
/// EIP-155 chain ids from ethereum-lists/chains. Used to check `eth_chainId`.
pub const ETHEREUM_CHAIN_ID: u64 = 1;
pub const BSC_CHAIN_ID: u64 = 56;
pub const BSC_TESTNET_CHAIN_ID: u64 = 97;
pub const POLYGON_CHAIN_ID: u64 = 137;
pub const POLYGON_AMOY_CHAIN_ID: u64 = 80002;

/// One EVM network sharing the same adapter.
///
/// `allows_signing` is true only for Sepolia. Other networks are read-only:
/// balance and token `balanceOf` work, and build/broadcast stay unimplemented.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EvmNetwork {
    pub chain: ChainId,
    pub evm_chain_id: u64,
    pub name: &'static str,
    pub native_symbol: &'static str,
    pub native_decimals: u8,
    pub rpc_env: &'static str,
    pub allows_signing: bool,
}

impl EvmNetwork {
    pub const ETHEREUM: Self = Self {
        chain: ChainId::Ethereum,
        evm_chain_id: ETHEREUM_CHAIN_ID,
        name: "Ethereum",
        native_symbol: "ETH",
        native_decimals: 18,
        rpc_env: "COFINEX_ETHEREUM_RPC_URL",
        allows_signing: false,
    };

    pub const SEPOLIA: Self = Self {
        chain: ChainId::EthereumSepolia,
        evm_chain_id: SEPOLIA_CHAIN_ID,
        name: "Sepolia",
        native_symbol: "ETH",
        native_decimals: 18,
        rpc_env: "COFINEX_SEPOLIA_RPC_URL",
        allows_signing: true,
    };

    pub const BSC: Self = Self {
        chain: ChainId::Bsc,
        evm_chain_id: BSC_CHAIN_ID,
        name: "BNB Smart Chain",
        native_symbol: "BNB",
        native_decimals: 18,
        rpc_env: "COFINEX_BSC_RPC_URL",
        allows_signing: false,
    };

    pub const BSC_TESTNET: Self = Self {
        chain: ChainId::BscTestnet,
        evm_chain_id: BSC_TESTNET_CHAIN_ID,
        name: "BNB Smart Chain Testnet",
        native_symbol: "BNB",
        native_decimals: 18,
        rpc_env: "COFINEX_BSC_TESTNET_RPC_URL",
        allows_signing: false,
    };

    pub const POLYGON: Self = Self {
        chain: ChainId::Polygon,
        evm_chain_id: POLYGON_CHAIN_ID,
        name: "Polygon",
        native_symbol: "POL",
        native_decimals: 18,
        rpc_env: "COFINEX_POLYGON_RPC_URL",
        allows_signing: false,
    };

    pub const POLYGON_AMOY: Self = Self {
        chain: ChainId::PolygonAmoy,
        evm_chain_id: POLYGON_AMOY_CHAIN_ID,
        name: "Polygon Amoy",
        native_symbol: "POL",
        native_decimals: 18,
        rpc_env: "COFINEX_POLYGON_AMOY_RPC_URL",
        allows_signing: false,
    };

    /// True only for the Sepolia network. A mismatched flag cannot enable mainnet signing.
    pub fn signing_enabled(self) -> bool {
        self.allows_signing
            && self.evm_chain_id == SEPOLIA_CHAIN_ID
            && self.chain == ChainId::EthereumSepolia
    }
}
