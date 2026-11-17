use bip32::ExtendedPrivateKey;
use ed25519_dalek::Signer as _;
use k256::ecdsa::{RecoveryId, SigningKey as SecpKey};

use crate::curve::Curve;
use crate::path::DerivationPath;
use crate::seed::Seed;
use crate::slip10::Slip10Node;
use crate::KeyError;

#[cfg(test)]
use bip32::Prefix;
#[cfg(test)]
use zeroize::Zeroizing;

/// A public key. Bytes are not secret.
///
/// * [`Curve::Secp256k1`]: SEC1 uncompressed, 65 bytes, `0x04` prefix.
/// * [`Curve::Ed25519`]: 32-byte compressed Edwards point.
#[derive(Clone, PartialEq, Eq)]
pub struct PublicKey {
    curve: Curve,
    bytes: Vec<u8>,
}

impl PublicKey {
    pub fn curve(&self) -> Curve {
        self.curve
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }
}

impl core::fmt::Debug for PublicKey {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("PublicKey")
            .field("curve", &self.curve)
            .field("bytes", &hex::encode(&self.bytes))
            .finish()
    }
}

/// A signature produced by [`sign_with_seed`].
///
/// * [`Curve::Secp256k1`]: 65 bytes, `r || s || v`, with `v` equal to 0 or 1
///   (EIP-1559 `y_parity`, low-s).
/// * [`Curve::Ed25519`]: 64-byte Ed25519 signature over the raw message.
#[derive(Clone, PartialEq, Eq)]
pub struct Signature {
    curve: Curve,
    bytes: Vec<u8>,
}

impl Signature {
    pub fn curve(&self) -> Curve {
        self.curve
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }
}

impl core::fmt::Debug for Signature {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("Signature")
            .field("curve", &self.curve)
            .field("len", &self.bytes.len())
            .finish()
    }
}

/// Derive the public key at `path` from `seed`.
pub fn public_key(seed: &Seed, path: &DerivationPath) -> Result<PublicKey, KeyError> {
    match path.curve() {
        Curve::Secp256k1 => {
            let key = derive_secp(seed, path)?;
            Ok(secp_public_key(&key))
        }
        Curve::Ed25519 => {
            let key = derive_ed25519(seed, path)?;
            Ok(ed25519_public_key(&key))
        }
    }
}

/// Sign `message` with the key at `path`.
///
/// `prehashed` must be true for secp256k1, and `message` must be the 32-byte
/// digest. It must be false for ed25519, which signs the raw message.
pub fn sign_with_seed(
    seed: &Seed,
    path: &DerivationPath,
    message: &[u8],
    prehashed: bool,
) -> Result<Signature, KeyError> {
    match path.curve() {
        Curve::Secp256k1 => {
            if !prehashed || message.len() != 32 {
                return Err(KeyError::BadMessage);
            }
            let key = derive_secp(seed, path)?;
            sign_secp(&key, message)
        }
        Curve::Ed25519 => {
            if prehashed {
                return Err(KeyError::BadMessage);
            }
            let mut secret = derive_ed25519(seed, path)?;
            let signature = sign_ed25519(&secret, message);
            zeroize::Zeroize::zeroize(&mut secret);
            signature
        }
    }
}

fn derive_secp(seed: &Seed, path: &DerivationPath) -> Result<SecpKey, KeyError> {
    let text = path.to_string();
    let parsed: bip32::DerivationPath = text.parse().map_err(|_| KeyError::InvalidPath)?;
    let extended = ExtendedPrivateKey::<SecpKey>::derive_from_path(seed.as_bytes(), &parsed)
        .map_err(|_| KeyError::InvalidKey)?;
    let mut bytes = extended.to_bytes();
    let key = SecpKey::from_slice(&bytes).map_err(|_| KeyError::InvalidKey);
    zeroize::Zeroize::zeroize(&mut bytes);
    key
}

fn secp_public_key(key: &SecpKey) -> PublicKey {
    let point = key.verifying_key().to_encoded_point(false);
    PublicKey {
        curve: Curve::Secp256k1,
        bytes: point.as_bytes().to_vec(),
    }
}

fn sign_secp(key: &SecpKey, digest: &[u8]) -> Result<Signature, KeyError> {
    let (signature, recovery_id) = key
        .sign_prehash_recoverable(digest)
        .map_err(|_| KeyError::Sign)?;
    let (signature, recovery_id) = normalize_low_s(signature, recovery_id)?;
    if recovery_id.is_x_reduced() {
        return Err(KeyError::Sign);
    }
    let compact = signature.to_bytes();
    let mut bytes = Vec::with_capacity(65);
    bytes.extend_from_slice(&compact);
    bytes.push(u8::from(recovery_id.is_y_odd()));
    Ok(Signature {
        curve: Curve::Secp256k1,
        bytes,
    })
}

fn normalize_low_s(
    signature: k256::ecdsa::Signature,
    recovery_id: RecoveryId,
) -> Result<(k256::ecdsa::Signature, RecoveryId), KeyError> {
    if let Some(normalized) = signature.normalize_s() {
        let flipped = RecoveryId::new(!recovery_id.is_y_odd(), recovery_id.is_x_reduced());
        Ok((normalized, flipped))
    } else {
        Ok((signature, recovery_id))
    }
}

fn derive_ed25519(seed: &Seed, path: &DerivationPath) -> Result<[u8; 32], KeyError> {
    let mut node = Slip10Node::master(seed.as_bytes());
    for segment in path.segments() {
        let child = node.derive_child(*segment)?;
        node = child;
    }
    Ok(node.key)
}

fn ed25519_public_key(secret: &[u8; 32]) -> PublicKey {
    let signing = ed25519_dalek::SigningKey::from_bytes(secret);
    PublicKey {
        curve: Curve::Ed25519,
        bytes: signing.verifying_key().to_bytes().to_vec(),
    }
}

fn sign_ed25519(secret: &[u8; 32], message: &[u8]) -> Result<Signature, KeyError> {
    let signing = ed25519_dalek::SigningKey::from_bytes(secret);
    let signature = signing.sign(message);
    Ok(Signature {
        curve: Curve::Ed25519,
        bytes: signature.to_bytes().to_vec(),
    })
}

/// Private key hex for BIP-44 test vectors. Crate tests only.
#[cfg(test)]
pub(crate) fn secp_private_hex(seed: &Seed, path: &DerivationPath) -> Result<String, KeyError> {
    let key = derive_secp(seed, path)?;
    Ok(hex::encode(key.to_bytes()))
}

/// Extended private key serialization, used by BIP-32 test vectors only.
#[cfg(test)]
pub(crate) fn secp_xprv(seed: &[u8], path: &str) -> Result<Zeroizing<String>, KeyError> {
    let parsed: bip32::DerivationPath = path.parse().map_err(|_| KeyError::InvalidPath)?;
    let extended = ExtendedPrivateKey::<SecpKey>::derive_from_path(seed, &parsed)
        .map_err(|_| KeyError::InvalidKey)?;
    Ok(extended.to_string(Prefix::XPRV))
}
