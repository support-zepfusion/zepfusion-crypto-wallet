//! 2-of-3 threshold signer placeholder.
//!
//! ADR-001 locks the protocols, not an implementation:
//!
//! * ECDSA chains (Bitcoin, EVM, TRON) use CGGMP21 via the Dfns `cggmp21`
//!   crate, which Kudelski Security audited. Threshold is 2-of-3 with key
//!   refresh.
//! * EdDSA chains (Solana, Sui) use FROST via the Zcash Foundation `frost`
//!   crates, which NCC Group audited. The same stack can later cover Bitcoin
//!   Taproot.
//!
//! Share layout when this is built:
//!
//! 1. The user device.
//! 2. A Cofinex signing service. This share cannot sign alone.
//! 3. An encrypted recovery share the user controls.
//!
//! No shares, session transcripts, or protocol messages are stored here.
//! Calling the trait methods returns [`SignerError::NotImplemented`](crate::SignerError::NotImplemented).

use cofinex_keys::{DerivationPath, PublicKey, Signature};

use crate::{SignRequest, Signer, SignerError};

/// Future 2-of-3 MPC signer. It cannot sign.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MpcSigner {
    threshold: u8,
    parties: u8,
}

impl MpcSigner {
    pub fn two_of_three() -> Self {
        Self {
            threshold: 2,
            parties: 3,
        }
    }

    pub fn threshold(self) -> u8 {
        self.threshold
    }

    pub fn parties(self) -> u8 {
        self.parties
    }
}

impl Signer for MpcSigner {
    fn backend_name(&self) -> &'static str {
        "mpc"
    }

    fn public_key(&self, _path: &DerivationPath) -> Result<PublicKey, SignerError> {
        Err(SignerError::NotImplemented {
            backend: self.backend_name(),
            operation: "public_key",
        })
    }

    fn sign(&self, _request: &SignRequest<'_>) -> Result<Signature, SignerError> {
        Err(SignerError::NotImplemented {
            backend: self.backend_name(),
            operation: "sign",
        })
    }
}
