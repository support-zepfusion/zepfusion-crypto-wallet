//! SLIP-0010 ed25519 private-key derivation.
//!
//! Only hardened child derivation is defined for ed25519. The 32-byte result
//! is an ed25519 seed (the value `ed25519-dalek` hashes), matching the
//! published SLIP-0010 vectors.

use hmac::{Hmac, Mac};
use sha2::Sha512;

use crate::path::PathSegment;
use crate::KeyError;

type HmacSha512 = Hmac<Sha512>;

pub(crate) struct Slip10Node {
    pub key: [u8; 32],
    pub chain_code: [u8; 32],
}

impl Drop for Slip10Node {
    fn drop(&mut self) {
        zeroize::Zeroize::zeroize(&mut self.key);
        zeroize::Zeroize::zeroize(&mut self.chain_code);
    }
}

impl Slip10Node {
    pub(crate) fn master(seed: &[u8]) -> Self {
        let (key, chain_code) = split_hmac(b"ed25519 seed", seed);
        Self { key, chain_code }
    }

    pub(crate) fn derive_child(&self, segment: PathSegment) -> Result<Self, KeyError> {
        if !segment.hardened {
            return Err(KeyError::Ed25519HardenedOnly);
        }
        let mut data = [0u8; 37];
        data[0] = 0x00;
        data[1..33].copy_from_slice(&self.key);
        data[33..37].copy_from_slice(&segment.to_wire().to_be_bytes());
        let (key, chain_code) = split_hmac(&self.chain_code, &data);
        Ok(Self { key, chain_code })
    }
}

fn split_hmac(key: &[u8], data: &[u8]) -> ([u8; 32], [u8; 32]) {
    let mut mac = HmacSha512::new_from_slice(key).expect("HMAC-SHA512 accepts any key length");
    mac.update(data);
    let bytes = mac.finalize().into_bytes();
    let mut left = [0u8; 32];
    let mut right = [0u8; 32];
    left.copy_from_slice(&bytes[..32]);
    right.copy_from_slice(&bytes[32..]);
    (left, right)
}
