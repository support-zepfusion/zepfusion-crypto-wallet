use async_trait::async_trait;
use cofinex_core::{
    Address, Balance, ChainAdapter, ChainError, ChainId, PublicKey, Signature, SignedTx,
    TransferIntent, TxId, TxStatus, UnsignedTx,
};
use cofinex_keys::{Curve, DerivationPath};

/// Compiling placeholder for a chain family that is not implemented yet.
///
/// Solana SPL `balanceOf` stays here: [`ChainAdapter::fungible_balance`](cofinex_core::ChainAdapter::fungible_balance)
/// returns "not implemented". TRON has a real read-only adapter.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StubAdapter {
    chain: ChainId,
}

impl StubAdapter {
    pub fn new(chain: ChainId) -> Self {
        Self { chain }
    }
}

#[async_trait]
impl ChainAdapter for StubAdapter {
    fn chain_id(&self) -> ChainId {
        self.chain
    }

    fn curve(&self) -> Curve {
        match self.chain {
            ChainId::Solana | ChainId::Sui => Curve::Ed25519,
            ChainId::Bitcoin
            | ChainId::Tron
            | ChainId::Ethereum
            | ChainId::EthereumSepolia
            | ChainId::Bsc
            | ChainId::BscTestnet
            | ChainId::Polygon
            | ChainId::PolygonAmoy => Curve::Secp256k1,
        }
    }

    fn derivation_path(&self, account: u32) -> Result<DerivationPath, ChainError> {
        let path = match self.chain {
            ChainId::Bitcoin => DerivationPath::bip44(Curve::Secp256k1, 0, account, 0, 0),
            ChainId::Tron => DerivationPath::bip44(Curve::Secp256k1, 195, account, 0, 0),
            ChainId::Solana => DerivationPath::solana_account(account),
            ChainId::Sui => DerivationPath::bip44(Curve::Ed25519, 784, account, 0, 0),
            ChainId::Ethereum
            | ChainId::EthereumSepolia
            | ChainId::Bsc
            | ChainId::BscTestnet
            | ChainId::Polygon
            | ChainId::PolygonAmoy => DerivationPath::bip44(Curve::Secp256k1, 60, account, 0, 0),
        };
        path.map_err(|_| ChainError::InvalidTransaction)
    }

    fn derive_address(&self, _public_key: &PublicKey) -> Result<Address, ChainError> {
        Err(ChainError::not_implemented(self.chain, "derive_address"))
    }

    async fn get_balance(&self, _address: &Address) -> Result<Balance, ChainError> {
        Err(ChainError::not_implemented(self.chain, "get_balance"))
    }

    async fn build_unsigned_tx(&self, _intent: &TransferIntent) -> Result<UnsignedTx, ChainError> {
        Err(ChainError::not_implemented(self.chain, "build_unsigned_tx"))
    }

    fn attach_signature(
        &self,
        _unsigned: &UnsignedTx,
        _signature: &Signature,
    ) -> Result<SignedTx, ChainError> {
        Err(ChainError::not_implemented(self.chain, "attach_signature"))
    }

    async fn broadcast_signed_tx(&self, _tx: &SignedTx) -> Result<TxId, ChainError> {
        Err(ChainError::not_implemented(
            self.chain,
            "broadcast_signed_tx",
        ))
    }

    async fn tx_status(&self, _tx_id: &TxId) -> Result<TxStatus, ChainError> {
        Err(ChainError::not_implemented(self.chain, "tx_status"))
    }
}
