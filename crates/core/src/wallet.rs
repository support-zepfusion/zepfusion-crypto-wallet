use cofinex_signer::{SignRequest, Signer};

use crate::{
    Address, ChainAdapter, ChainError, CoreError, SignedTx, TransferIntent, TxId, TxStatus,
};

/// Holds a signer and drives adapters. The signer type is a parameter so the
/// local key signer and the future MPC signer share this code.
pub struct Wallet<S> {
    signer: S,
}

impl<S> Wallet<S> {
    pub fn new(signer: S) -> Self {
        Self { signer }
    }

    pub fn signer(&self) -> &S {
        &self.signer
    }
}

impl<S: Signer> Wallet<S> {
    pub fn address(&self, adapter: &dyn ChainAdapter, account: u32) -> Result<Address, CoreError> {
        let path = adapter.derivation_path(account)?;
        let public_key = self.signer.public_key(&path)?;
        Ok(adapter.derive_address(&public_key)?)
    }

    /// Build, sign, and encode a native transfer. Does not broadcast.
    pub async fn sign_transfer(
        &self,
        adapter: &dyn ChainAdapter,
        account: u32,
        to: &str,
        amount_base_units: &str,
    ) -> Result<SignedTx, CoreError> {
        let path = adapter.derivation_path(account)?;
        let from = self.address(adapter, account)?;
        let unsigned = adapter
            .build_unsigned_tx(&TransferIntent {
                from,
                to: Address::new(adapter.chain_id(), to.to_string()),
                amount_base_units: amount_base_units.to_string(),
                path: path.clone(),
            })
            .await?;
        if unsigned.path != path || unsigned.chain != adapter.chain_id() {
            return Err(CoreError::PathMismatch);
        }
        let signature = self.signer.sign(&SignRequest {
            path: &unsigned.path,
            message: &unsigned.message,
            prehashed: unsigned.prehashed,
        })?;
        Ok(adapter.attach_signature(&unsigned, &signature)?)
    }

    pub async fn broadcast(
        &self,
        adapter: &dyn ChainAdapter,
        tx: &SignedTx,
    ) -> Result<TxId, CoreError> {
        if tx.chain != adapter.chain_id() {
            return Err(CoreError::Chain(ChainError::InvalidTransaction));
        }
        Ok(adapter.broadcast_signed_tx(tx).await?)
    }

    pub async fn tx_status(
        &self,
        adapter: &dyn ChainAdapter,
        tx_id: &TxId,
    ) -> Result<TxStatus, CoreError> {
        Ok(adapter.tx_status(tx_id).await?)
    }
}
