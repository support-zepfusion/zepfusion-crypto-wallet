//! Mnemonic and hierarchical derivation.
//!
//! Secrets live in [`zeroize`] buffers. Nothing in this crate logs a mnemonic,
//! passphrase, seed, or private key. Do not add a `Display` or `Debug` impl
//! that includes those values.
//!
//! secp256k1 derivation uses the `bip32` crate (BIP-32, RustCrypto `k256`).
//! Ed25519 derivation follows SLIP-0010 with HMAC-SHA512 and `ed25519-dalek`.
//! The `slip10` crate was not used: its last release depends on `ed25519-dalek`
//! 1.x and `hmac` 0.9. The SLIP-0010 step itself is the HMAC construction from
//! the spec and is checked against the published test vectors.

#![forbid(unsafe_code)]

mod curve;
mod derive;
mod path;
mod seed;
mod slip10;

#[cfg(test)]
mod tests;

pub use curve::Curve;
pub use derive::{public_key, sign_with_seed, PublicKey, Signature};
pub use path::{DerivationPath, PathSegment};
pub use seed::{generate_mnemonic, Seed};

use thiserror::Error;

/// Failures while parsing a mnemonic or deriving a key.
///
/// Messages stay generic so a caller can show them without echoing the phrase.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum KeyError {
    #[error("invalid mnemonic")]
    InvalidMnemonic,
    #[error("word count must be 12, 15, 18, 21, or 24")]
    BadWordCount,
    #[error("invalid derivation path")]
    InvalidPath,
    #[error("ed25519 derivation requires every path segment to be hardened")]
    Ed25519HardenedOnly,
    #[error("private key is invalid")]
    InvalidKey,
    #[error("signing failed")]
    Sign,
    #[error("message length is invalid for this curve")]
    BadMessage,
}
