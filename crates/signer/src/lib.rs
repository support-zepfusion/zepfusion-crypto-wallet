//! Signing boundary for Cofinex Wallet.
//!
//! Chain adapters ask for a signature through [`Signer`]. They do not know
//! whether the signature came from a seed on this device or from a threshold
//! protocol. Replacing [`LocalSigner`] with [`MpcSigner`] is a construction
//! change at the wallet edge, not an adapter change.
//!
//! This crate does not log mnemonics, passphrases, seeds, or private keys.

#![forbid(unsafe_code)]

mod local;
mod mpc;

#[cfg(test)]
mod tests;

pub use local::LocalSigner;
pub use mpc::MpcSigner;

use cofinex_keys::{DerivationPath, KeyError, PublicKey, Signature};
use thiserror::Error;

/// What the signer is asked to sign.
///
/// For secp256k1, `message` is the 32-byte digest and `prehashed` is true.
/// For ed25519, `message` is the raw message and `prehashed` is false.
pub struct SignRequest<'a> {
    pub path: &'a DerivationPath,
    pub message: &'a [u8],
    pub prehashed: bool,
}

#[derive(Debug, Error)]
pub enum SignerError {
    #[error(transparent)]
    Key(#[from] KeyError),
    /// The backend is a documented placeholder. Adapters must keep working
    /// unchanged once a real implementation replaces it.
    #[error("{backend} signer does not implement {operation} yet")]
    NotImplemented {
        backend: &'static str,
        operation: &'static str,
    },
}

/// Produces public keys and signatures for a derivation path.
///
/// Object-safe on purpose: a wallet can hold `Box<dyn Signer>` and swap the
/// local key backend for the MPC backend without recompiling adapters.
pub trait Signer: Send + Sync {
    fn backend_name(&self) -> &'static str;

    fn public_key(&self, path: &DerivationPath) -> Result<PublicKey, SignerError>;

    fn sign(&self, request: &SignRequest<'_>) -> Result<Signature, SignerError>;
}
